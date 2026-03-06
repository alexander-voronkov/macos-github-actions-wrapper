import Foundation

final class RunnerConfigService {
    private let executor = ProcessExecutor()

    func configure(settings: RunnerSettings, registrationToken: String) throws {
        guard let folder = settings.runnerFolderURL else {
            throw NSError(domain: "RunnerConfig", code: 10, userInfo: [NSLocalizedDescriptionKey: "Runner folder is required"])
        }

        let configScript = folder.appendingPathComponent("config.sh")
        guard FileManager.default.fileExists(atPath: configScript.path) else {
            throw NSError(domain: "RunnerConfig", code: 11, userInfo: [NSLocalizedDescriptionKey: "config.sh not found in selected runner folder"])
        }

        var command = "./config.sh --url \(shellEscape(settings.githubURL)) --name \(shellEscape(settings.runnerName)) --work \(shellEscape(settings.workFolder)) --labels \(shellEscape(settings.labels)) --token \"$RUNNER_CFG_TOKEN\""

        if settings.unattendedConfigure {
            command += " --unattended --replace"
        }

        let result = try executor.run(
            "/bin/bash",
            arguments: ["-lc", command],
            currentDirectory: folder,
            environment: ["RUNNER_CFG_TOKEN": registrationToken]
        )

        if result.exitCode != 0 {
            throw NSError(domain: "RunnerConfig", code: Int(result.exitCode), userInfo: [
                NSLocalizedDescriptionKey: "Runner configuration failed. \(result.stderr)"
            ])
        }
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
