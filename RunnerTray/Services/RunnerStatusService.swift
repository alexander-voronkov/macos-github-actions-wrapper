import Foundation

struct RunnerStatusSnapshot {
    let status: RunnerStatus
    let detail: String
}

final class RunnerStatusService {
    private let executor = ProcessExecutor()
    private let launchAgentService: LaunchAgentService
    private let logService: LogService

    init(launchAgentService: LaunchAgentService, logService: LogService) {
        self.launchAgentService = launchAgentService
        self.logService = logService
    }

    func determineStatus(settings: RunnerSettings, isPauseRequested: Bool) -> RunnerStatusSnapshot {
        guard settings.isConfigured, let folder = settings.runnerFolderURL else {
            return .init(status: .notConfigured, detail: "Runner folder is not configured")
        }

        let loaded = launchAgentService.isLoaded()
        if !loaded {
            return .init(status: .stopped, detail: "LaunchAgent is not loaded")
        }

        if !runnerProcessExists() {
            return .init(status: .starting, detail: "Runner is starting")
        }

        let hint = detectActivityHint(folder: folder)
        if case .failed(let reason) = hint {
            return .init(status: .error, detail: reason)
        }

        if isPauseRequested {
            if hint == .workerActive || hint == .recentJobStarted {
                return .init(status: .pausing, detail: "Waiting for current job to finish")
            }
            return .init(status: .idle, detail: "Runner is idle and ready to pause")
        }

        if hint == .workerActive || hint == .recentJobStarted {
            return .init(status: .busy, detail: "Runner is processing a job")
        }

        return .init(status: .idle, detail: "Runner is online and idle")
    }

    private func runnerProcessExists() -> Bool {
        let result = try? executor.run("/usr/bin/pgrep", arguments: ["-f", "Runner.Listener"])
        return result?.exitCode == 0
    }

    private func detectActivityHint(folder: URL) -> RunnerActivityHint {
        if let worker = try? executor.run("/usr/bin/pgrep", arguments: ["-f", "Runner.Worker"]), worker.exitCode == 0 {
            return .workerActive
        }

        let tail = logService.tail(in: folder, lineCount: 80)

        if matches(pattern: #"\b(Running\s+job|Job\s+request\s+.*received|Listening\s+for\s+Jobs)\b"#, text: tail) {
            return .recentJobStarted
        }

        if matches(pattern: #"\b(Job\s+completed|finished\s+with\s+result|has\s+finished\s+with\s+conclusion)\b"#, text: tail) {
            return .recentJobFinished
        }

        if matches(pattern: #"\b(ERROR|Unhandled\s+exception|Runner\s+listener\s+exited\s+with\s+error)\b"#, text: tail) {
            return .failed("Runner reported an error in recent logs")
        }

        return .running
    }

    private func matches(pattern: String, text: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))?
            .firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }
}
