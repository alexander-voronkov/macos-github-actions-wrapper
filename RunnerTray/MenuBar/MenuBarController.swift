import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables: Set<AnyCancellable> = []

    private let viewModel: AppViewModel
    private let openSettings: () -> Void
    private let openLogs: () -> Void

    init(viewModel: AppViewModel, openSettings: @escaping () -> Void, openLogs: @escaping () -> Void) {
        self.viewModel = viewModel
        self.openSettings = openSettings
        self.openLogs = openLogs
        super.init()
        setup()
        bind()
    }

    private func setup() {
        if let button = statusItem.button {
            button.title = "RunnerTray"
            button.imagePosition = .imageLeading
        }
        rebuildMenu()
    }

    private func bind() {
        viewModel.$status.combineLatest(viewModel.$settings, viewModel.$updateStatus).sink { [weak self] _, _, _ in
            self?.updateIcon()
            self?.rebuildMenu()
        }.store(in: &cancellables)
    }

    private func updateIcon() {
        let symbol: String
        switch viewModel.status {
        case .stopped, .notConfigured:
            symbol = "circle.fill"
        case .idle:
            symbol = "checkmark.circle.fill"
        case .busy, .pausing, .starting:
            symbol = "clock.fill"
        case .error:
            symbol = "xmark.circle.fill"
        }

        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Runner status") else { return }
        image.isTemplate = false
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = iconColor(for: viewModel.status)
    }

    private func iconColor(for status: RunnerStatus) -> NSColor {
        switch status {
        case .stopped, .notConfigured:
            return .systemGray
        case .idle:
            return .systemGreen
        case .busy, .pausing, .starting:
            return .systemOrange
        case .error:
            return .systemRed
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Runner: \(viewModel.settings.runnerName)", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Status: \(viewModel.status.menuDescription)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        menu.addItem(makeAction("Start Runner", #selector(startRunner), enabled: viewModel.status == .stopped || viewModel.status == .notConfigured || viewModel.status == .error))
        menu.addItem(makeAction("Stop Runner", #selector(stopRunner), enabled: viewModel.status == .idle || viewModel.status == .busy || viewModel.status == .starting || viewModel.status == .pausing))
        menu.addItem(makeAction("Restart Runner", #selector(restartRunner), enabled: viewModel.status != .notConfigured))
        menu.addItem(makeAction("Pause After Current Job", #selector(pauseRunner), enabled: viewModel.status == .busy || viewModel.status == .idle))
        menu.addItem(makeAction("Resume", #selector(resumeRunner), enabled: viewModel.status == .stopped || viewModel.status == .pausing))

        menu.addItem(.separator())
        let updateTitle = viewModel.isUpdating ? "Updating…" : "Check for Updates"
        menu.addItem(makeAction(updateTitle, #selector(checkForUpdates), enabled: !viewModel.isUpdating && viewModel.settings.isConfigured))
        if !viewModel.updateStatus.isEmpty {
            let statusItem = NSMenuItem(title: "  \(viewModel.updateStatus)", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
        }

        menu.addItem(.separator())
        menu.addItem(makeAction("Open Logs", #selector(openLogsAction), enabled: true))
        menu.addItem(makeAction("Open Runner Folder", #selector(openRunnerFolder), enabled: viewModel.settings.runnerFolderURL != nil))
        menu.addItem(makeAction("Open Settings", #selector(openSettingsAction), enabled: true))

        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.state = viewModel.settings.launchAtLogin ? .on : .off
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())
        menu.addItem(makeAction("Quit", #selector(quit), enabled: true))

        statusItem.menu = menu
    }

    private func makeAction(_ title: String, _ selector: Selector, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    @objc private func startRunner() { Task { await viewModel.startRunner() } }
    @objc private func stopRunner() { Task { await viewModel.stopRunner() } }
    @objc private func restartRunner() { Task { await viewModel.restartRunner() } }
    @objc private func pauseRunner() { viewModel.pauseAfterCurrentJob() }
    @objc private func resumeRunner() { Task { await viewModel.resumeRunner() } }
    @objc private func checkForUpdates() { Task { await viewModel.checkForUpdates(silent: false) } }
    @objc private func openLogsAction() { openLogs() }
    @objc private func openRunnerFolder() { viewModel.openRunnerFolder() }
    @objc private func openSettingsAction() { openSettings() }

    @objc private func toggleLaunchAtLogin() {
        viewModel.setLaunchAtLogin(!viewModel.settings.launchAtLogin)
        rebuildMenu()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
