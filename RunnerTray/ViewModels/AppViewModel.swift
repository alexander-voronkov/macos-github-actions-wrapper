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

    private let settingsStore = SettingsStore()
    private let keychain = KeychainService()
    private lazy var configService = RunnerConfigService(keychain: keychain)
    private let launchAgentService = LaunchAgentService()
    private let logService = LogService()
    private lazy var statusService = RunnerStatusService(launchAgentService: launchAgentService, logService: logService)
    private let launchAtLoginService = LaunchAtLoginService()

    private var timer: Timer?

    init() {
        self.settings = settingsStore.load()
        self.settings.launchAtLogin = launchAtLoginService.isEnabled()
        refreshStatus()
        startPolling()

        if settings.autoStartAfterLaunch {
            Task { await startRunner() }
        }
    }

    deinit { timer?.invalidate() }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
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
            try launchAgentService.writeLaunchAgent(for: settings.runnerFolderURL!)
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
        refreshStatus()
    }

    func resumeRunner() async {
        pauseRequested = false
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

        if pauseRequested {
            if status == .idle {
                Task { await stopRunner() }
            } else if status == .stopped {
                pauseRequested = false
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
            persistSettings()
            refreshStatus()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(enabled)
            settings.launchAtLogin = enabled
            persistSettings()
        } catch {
            settings.launchAtLogin = launchAtLoginService.isEnabled()
            alertMessage = "Could not change Launch at Login: \(error.localizedDescription)"
        }
    }
}
