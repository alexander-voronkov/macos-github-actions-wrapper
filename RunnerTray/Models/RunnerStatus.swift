import Foundation

enum RunnerStatus: String, Codable, CaseIterable {
    case notConfigured = "Not Configured"
    case stopped = "Stopped"
    case starting = "Starting"
    case idle = "Idle"
    case busy = "Busy"
    case pausing = "Pausing"
    case error = "Error"

    var menuDescription: String { rawValue }
}

enum RunnerActivityHint {
    case unknown
    case running
    case workerActive
    case recentJobStarted
    case recentJobFinished
    case failed(String)
}
