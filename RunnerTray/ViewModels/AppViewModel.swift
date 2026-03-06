import AppKit
import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var settings: RunnerSettings
    @Published var status: RunnerStatus = .notConfigured
    @Published var statusDetail: String = ""
    @Published var latestLog: String = "No logs loaded yet"
    @Published var registrationToken: String = ""
    @Published var pauseRequested = false
    @Published var alertMessage: String?

    private let settingsStore: SettingsStore
    private let configService: RunnerConfigService
    private let launchAgentService: LaunchAgentService
    private let logService: LogService
    private let launchAtLoginService: LaunchAtLoginService
    private lazy var statusService = RunnerStatusService(launchAgentService: launchAgentService, logService: logService)

    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var pauseDrainInFlight = false

    init(
        settingsStore: SettingsStore = SettingsStore(),
        configService: RunnerConfigService = RunnerConfigService(),
        launchAgentService: LaunchAgentService = LaunchAgentService(),
        logService: LogService = LogService(),
        launchAtLoginService: LaunchAtLoginService = LaunchAtLoginService()
    ) {
        self.settingsStore = settingsStore
        self.configService = configService
        self.launchAgentService = launchAgentService
        self.logService = logService
        self.launchAtLoginService = launchAtLoginService

        self.settings = settingsStore.load()
        self.settings.launchAtLogin = launchAtLoginService.isEnabled()

        $settings
            .dropFirst()
            .sink { [weak self] newSettings in
                self?.settingsStore.save(newSettings)
            }
            .store(in: &cancellables)

        refreshStatus()
        startPolling()
    }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
    }

    func persistSettings() {
        settingsStore.save(settings)
    }

    func configureRunner() async {
        do {
            let token = registrationToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else {
                throw NSError(domain: "RunnerTray", code: 99, userInfo: [NSLocalizedDescriptionKey: "Registration token is required"])
            }
            try configService.configure(settings: settings, registrationToken: token)
            registrationToken = ""
            if let runnerFolderURL = settings.runnerFolderURL {
                try launchAgentService.writeLaunchAgent(for: runnerFolderURL)
            }
            refreshStatus()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func startRunner() async {
        do {
            guard let folder = settings.runnerFolderURL else {
                throw NSError(domain: "RunnerTray", code: 97, userInfo: [NSLocalizedDescriptionKey: "Please select a runner folder first"])
            }
            try launchAgentService.writeLaunchAgent(for: folder)
            try launchAgentService.bootstrap()
            pauseRequested = false
            refreshStatus()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func stopRunner() async {
        do {
            try launchAgentService.bootout()
            pauseRequested = false
            pauseDrainInFlight = false
            refreshStatus()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func restartRunner() async {
        await stopRunner()
        try? await Task.sleep(nanoseconds: 400_000_000)
        await startRunner()
    }

    func pauseAfterCurrentJob() {
        pauseRequested = true
        pauseDrainInFlight = false
        refreshStatus()
    }

    func resumeRunner() async {
        pauseRequested = false
        pauseDrainInFlight = false
        await startRunner()
    }

    func openRunnerFolder() {
        guard let folder = settings.runnerFolderURL else { return }
        NSWorkspace.shared.open(folder)
    }

    func openLogsFolder() {
        guard let folder = settings.runnerFolderURL else { return }
        NSWorkspace.shared.open(logService.diagDirectory(for: folder))
    }

    func refreshStatus() {
        let snapshot = statusService.determineStatus(settings: settings, isPauseRequested: pauseRequested)
        status = snapshot.status
        statusDetail = snapshot.detail

        if let folder = settings.runnerFolderURL {
            latestLog = logService.tail(in: folder, lineCount: 40)
        }

        if pauseRequested, status == .idle, !pauseDrainInFlight {
            pauseDrainInFlight = true
            Task { @MainActor in
                do {
                    try launchAgentService.bootout()
                    pauseRequested = false
                } catch {
                    alertMessage = error.localizedDescription
                }
                pauseDrainInFlight = false
                refreshStatus()
            }
        }
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.installationFolder = url.path
            refreshStatus()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(enabled)
            settings.launchAtLogin = enabled
        } catch {
            settings.launchAtLogin = launchAtLoginService.isEnabled()
            alertMessage = "Could not change Launch at Login: \(error.localizedDescription)"
        }
    }
}
