import Foundation
import Darwin

final class LaunchAgentService {
    static let label = "com.runnertray.github-runner"

    private let executor = ProcessExecutor()
    private let fileManager = FileManager.default

    private var launchAgentsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
    }

    var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(Self.label).plist")
    }

    func writeLaunchAgent(for runnerFolder: URL) throws {
        try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)

        let standardOut = runnerFolder.appendingPathComponent("runnertray-stdout.log").path
        let standardError = runnerFolder.appendingPathComponent("runnertray-stderr.log").path

        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": ["/usr/bin/env", "bash", "-lc", "./run.sh"],
            "WorkingDirectory": runnerFolder.path,
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "StandardOutPath": standardOut,
            "StandardErrorPath": standardError
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
    }

    func isLoaded() -> Bool {
        (try? executor.run("/bin/launchctl", arguments: ["print", "gui/\(uid())/\(Self.label)"]))?.exitCode == 0
    }

    func bootstrap() throws {
        let result = try executor.run("/bin/launchctl", arguments: ["bootstrap", "gui/\(uid())", plistURL.path])
        if result.exitCode != 0 && !result.stderr.contains("Service already loaded") {
            throw RunnerTrayError.launchAgentFailed(reason: result.stderr)
        }
        _ = try? executor.run("/bin/launchctl", arguments: ["kickstart", "-k", "gui/\(uid())/\(Self.label)"])
    }

    func bootout() throws {
        let result = try executor.run("/bin/launchctl", arguments: ["bootout", "gui/\(uid())/\(Self.label)"])
        if result.exitCode != 0 && !result.stderr.contains("No such process") {
            throw RunnerTrayError.launchAgentFailed(reason: result.stderr)
        }
    }

    private func uid() -> String {
        String(getuid())
    }
}
