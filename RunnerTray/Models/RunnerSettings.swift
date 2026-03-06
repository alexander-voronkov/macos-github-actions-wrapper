import Foundation

struct RunnerSettings: Codable {
    var githubURL: String = ""
    var runnerName: String = Host.current().localizedName ?? "RunnerTray"
    var labels: String = "self-hosted,macOS"
    var workFolder: String = "_work"
    var installationFolder: String = ""
    var useExistingFolder: Bool = true
    var unattendedConfigure: Bool = true
    var launchAtLogin: Bool = false
    var autoStartAfterLaunch: Bool = false

    var runnerFolderURL: URL? {
        guard !installationFolder.isEmpty else { return nil }
        return URL(fileURLWithPath: installationFolder)
    }

    var isConfigured: Bool {
        guard let url = runnerFolderURL else { return false }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("run.sh").path)
    }
}
