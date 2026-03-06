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
            return .init(status: .stopped, detail: "Paused after current job")
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

        let tail = logService.tail(in: folder, lineCount: 60)
        if tail.localizedCaseInsensitiveContains("Running job") || tail.localizedCaseInsensitiveContains("Job request") {
            return .recentJobStarted
        }
        if tail.localizedCaseInsensitiveContains("Job completed") || tail.localizedCaseInsensitiveContains("finished with result") {
            return .recentJobFinished
        }
        if tail.localizedCaseInsensitiveContains("error") && tail.localizedCaseInsensitiveContains("listener") {
            return .failed("Runner reported an error in recent logs")
        }

        return .running
    }
}

extension RunnerActivityHint: Equatable {
    static func == (lhs: RunnerActivityHint, rhs: RunnerActivityHint) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown), (.running, .running), (.workerActive, .workerActive), (.recentJobStarted, .recentJobStarted), (.recentJobFinished, .recentJobFinished):
            return true
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}
