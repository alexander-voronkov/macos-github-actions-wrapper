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
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
            let window = NSWindow(
                contentRect: NSRect(x: 120, y: 120, width: 720, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "RunnerTray Settings"
            window.contentView = NSHostingView(rootView: root)
            window.delegate = self
            window.setFrameAutosaveName("RunnerTraySettingsWindow")
            window.minSize = NSSize(width: 620, height: 480)
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showLogsWindow() {
        if logWindow == nil {
            let root = LogViewerView(viewModel: viewModel)
            let window = NSWindow(
                contentRect: NSRect(x: 140, y: 140, width: 760, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "RunnerTray Logs"
            window.contentView = NSHostingView(rootView: root)
            window.delegate = self
            window.setFrameAutosaveName("RunnerTrayLogWindow")
            window.minSize = NSSize(width: 640, height: 420)
            logWindow = window
        }
        logWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            settingsWindow = nil
        } else if window === logWindow {
            logWindow = nil
        }
    }
}
