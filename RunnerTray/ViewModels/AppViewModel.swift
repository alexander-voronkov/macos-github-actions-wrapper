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
    @Published var updateStatus: String = ""
    @Published var isUpdating = false

    private let settingsStore: SettingsStore
    private let updateService = RunnerUpdateService()
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
        scheduleUpdateCheck()

        // Check for updates on launch
        if settings.isConfigured {
            Task { await checkForUpdates(silent: true) }
        }
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
                throw RunnerTrayError.registrationTokenRequired
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
            guard let folder = settings.runnerFolderURL, settings.isConfigured else {
                throw RunnerTrayError.runnerFolderRequired
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

    // MARK: - Runner Auto-Update

    private var updateTimer: Timer?

    func scheduleUpdateCheck() {
        updateTimer?.invalidate()
        // Check every 24 hours
        updateTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkForUpdates(silent: true) }
        }
    }

    /// Check for runner binary updates. If silent, only alerts when update is available.
    func checkForUpdates(silent: Bool = false) async {
        guard let folder = settings.runnerFolderURL else {
            if !silent { alertMessage = "Runner folder is not configured" }
            return
        }

        updateStatus = "Checking for updates…"
        do {
            if let release = try await updateService.checkForUpdate(in: folder) {
                let current = updateService.currentVersion(in: folder) ?? "unknown"
                updateStatus = "Update available: \(release.version) (current: \(current))"
                if silent {
                    // Auto-update: stop → update → start
                    await applyUpdate(release: release)
                } else {
                    alertMessage = "Runner update available: \(current) → \(release.version). Use 'Update Runner' to install."
                }
            } else {
                let current = updateService.currentVersion(in: folder) ?? "unknown"
                updateStatus = "Up to date (\(current))"
                if !silent { alertMessage = "Runner is up to date (\(current))" }
            }
        } catch {
            updateStatus = "Update check failed"
            if !silent { alertMessage = "Update check failed: \(error.localizedDescription)" }
        }
    }

    /// Download and apply the runner update. Stops the runner, updates, restarts.
    func applyUpdate(release: RunnerRelease? = nil) async {
        guard let folder = settings.runnerFolderURL else {
            alertMessage = "Runner folder is not configured"
            return
        }

        isUpdating = true
        updateStatus = "Preparing update…"

        do {
            let targetRelease: RunnerRelease
            if let release {
                targetRelease = release
            } else {
                updateStatus = "Fetching latest release…"
                targetRelease = try await updateService.fetchLatestRelease()
            }

            // Stop runner if running
            let wasRunning = (status == .idle || status == .busy || status == .starting)
            if wasRunning {
                updateStatus = "Stopping runner…"
                await stopRunner()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }

            updateStatus = "Downloading \(targetRelease.version)…"
            try await updateService.applyUpdate(release: targetRelease, to: folder)

            updateStatus = "Update complete: \(targetRelease.version)"

            // Restart if it was running before
            if wasRunning {
                updateStatus = "Restarting runner…"
                await startRunner()
            }

            updateStatus = "Updated to \(targetRelease.version) ✓"
        } catch {
            updateStatus = "Update failed"
            alertMessage = "Update failed: \(error.localizedDescription)"
        }

        isUpdating = false
    }
}
