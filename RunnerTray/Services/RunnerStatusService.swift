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

        if !runnerProcessExists(in: folder) {
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

    /// Check if Runner.Listener is running from the specific runner folder.
    private func runnerProcessExists(in folder: URL) -> Bool {
        let result = try? executor.run("/bin/ps", arguments: ["axo", "pid,command"])
        guard let stdout = result?.stdout, result?.exitCode == 0 else { return false }
        let folderPath = folder.path
        return stdout.split(separator: "\n").contains { line in
            line.contains("Runner.Listener") && line.contains(folderPath)
        }
    }

    private func detectActivityHint(folder: URL) -> RunnerActivityHint {
        // Check for Worker scoped to this runner's folder
        if let result = try? executor.run("/bin/ps", arguments: ["axo", "pid,command"]),
           result.exitCode == 0 {
            let folderPath = folder.path
            let hasWorker = result.stdout.split(separator: "\n").contains { line in
                line.contains("Runner.Worker") && line.contains(folderPath)
            }
            if hasWorker { return .workerActive }
        }

        let tail = logService.tail(in: folder, lineCount: 80)
        return lastLogEvent(in: tail)
    }

    /// Scan log lines bottom-to-top and return the LAST matching event,
    /// so a "Job completed" after "Running job" correctly reports finished.
    private func lastLogEvent(in tail: String) -> RunnerActivityHint {
        let lines = tail.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines.reversed() {
            let s = String(line)
            if matches(pattern: #"\b(ERROR|Unhandled\s+exception|Runner\s+listener\s+exited\s+with\s+error)\b"#, text: s) {
                return .failed("Runner reported an error in recent logs")
            }
            if matches(pattern: #"\b(Job\s+completed|finished\s+with\s+result|has\s+finished\s+with\s+conclusion)\b"#, text: s) {
                return .recentJobFinished
            }
            if matches(pattern: #"\b(Running\s+job|Job\s+request\s+.*received)\b"#, text: s) {
                return .recentJobStarted
            }
        }

        return .running
    }

    private func matches(pattern: String, text: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))?
            .firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }
}
