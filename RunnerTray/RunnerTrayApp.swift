import AppKit
import SwiftUI

@main
struct RunnerTrayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = AppViewModel()
    private var menuBarController: MenuBarController?
    private var settingsWindow: NSWindow?
    private var logWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(
            viewModel: viewModel,
            openSettings: { [weak self] in self?.showSettingsWindow() },
            openLogs: { [weak self] in self?.showLogsWindow() }
        )

        if viewModel.settings.autoStartAfterLaunch {
            Task { await viewModel.startRunner() }
        }
    }

    func showSettingsWindow() {
        if settingsWindow == nil {
            let root = SettingsView(viewModel: viewModel)
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 120, y: 120, width: 720, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "RunnerTray Settings"
            settingsWindow?.contentView = NSHostingView(rootView: root)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showLogsWindow() {
        if logWindow == nil {
            let root = LogViewerView(viewModel: viewModel)
            logWindow = NSWindow(
                contentRect: NSRect(x: 140, y: 140, width: 760, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            logWindow?.title = "RunnerTray Logs"
            logWindow?.contentView = NSHostingView(rootView: root)
        }
        logWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
