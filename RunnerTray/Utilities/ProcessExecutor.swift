import Foundation

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ProcessExecutorError: LocalizedError {
    case executableNotFound(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let binary):
            return "Executable not found: \(binary)"
        }
    }
}

final class ProcessExecutor {
    func run(_ launchPath: String, arguments: [String], currentDirectory: URL? = nil) throws -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: launchPath) || launchPath.hasPrefix("/") else {
            throw ProcessExecutorError.executableNotFound(launchPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }
}
