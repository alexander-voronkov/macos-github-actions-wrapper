import Foundation

final class RunnerConfigService {
    private let executor = ProcessExecutor()
    private let keychain: KeychainService

    init(keychain: KeychainService) {
        self.keychain = keychain
    }

    func configure(settings: RunnerSettings, registrationToken: String) throws {
        guard let folder = settings.runnerFolderURL else {
            throw NSError(domain: "RunnerConfig", code: 10, userInfo: [NSLocalizedDescriptionKey: "Runner folder is required"])
        }

        let configScript = folder.appendingPathComponent("config.sh")
        guard FileManager.default.fileExists(atPath: configScript.path) else {
            throw NSError(domain: "RunnerConfig", code: 11, userInfo: [NSLocalizedDescriptionKey: "config.sh not found in selected runner folder"])
        }

        var args = [
            configScript.path,
            "--url", settings.githubURL,
            "--name", settings.runnerName,
            "--work", settings.workFolder,
            "--labels", settings.labels,
            "--token", registrationToken
        ]

        if settings.unattendedConfigure {
            args.append("--unattended")
            args.append("--replace")
        }

        let result = try executor.run("/bin/bash", arguments: args, currentDirectory: folder)
        if result.exitCode != 0 {
            throw NSError(domain: "RunnerConfig", code: Int(result.exitCode), userInfo: [
                NSLocalizedDescriptionKey: "Runner configuration failed. \(result.stderr)"
            ])
        }

        try? keychain.saveSecret(registrationToken, account: "registration-token")
    }
}
