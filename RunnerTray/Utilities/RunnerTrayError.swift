import Foundation

enum RunnerTrayError: LocalizedError {
    case runnerFolderRequired
    case configScriptNotFound
    case registrationTokenRequired
    case launchAgentFailed(reason: String)
    case configurationFailed(exitCode: Int, stderr: String)

    var errorDescription: String? {
        switch self {
        case .runnerFolderRequired:
            return "Please select a runner folder first"
        case .configScriptNotFound:
            return "config.sh not found in selected runner folder"
        case .registrationTokenRequired:
            return "Registration token is required"
        case .launchAgentFailed(let reason):
            return "LaunchAgent operation failed: \(reason)"
        case .configurationFailed(let exitCode, let stderr):
            return "Runner configuration failed (exit \(exitCode)). \(stderr)"
        }
    }
}
