import Foundation

final class RunnerConfigService {
    private let executor = ProcessExecutor()

    func configure(settings: RunnerSettings, registrationToken: String) throws {
        guard let folder = settings.runnerFolderURL else {
            throw RunnerTrayError.runnerFolderRequired
        }

        let configScript = folder.appendingPathComponent("config.sh")
        guard FileManager.default.fileExists(atPath: configScript.path) else {
            throw RunnerTrayError.configScriptNotFound
        }

        var command = "./config.sh --url \(shellEscape(settings.githubURL)) --name \(shellEscape(settings.runnerName)) --work \(shellEscape(settings.workFolder)) --labels \(shellEscape(settings.labels)) --token \"$RUNNER_CFG_TOKEN\""

        if settings.unattendedConfigure {
            command += " --unattended --replace"
        }

        let result = try executor.run(
            "/usr/bin/env",
            arguments: ["bash", "-lc", command],
            currentDirectory: folder,
            environment: ["RUNNER_CFG_TOKEN": registrationToken]
        )

        if result.exitCode != 0 {
            throw RunnerTrayError.configurationFailed(exitCode: Int(result.exitCode), stderr: result.stderr)
        }
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
