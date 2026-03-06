import Foundation

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ProcessExecutorError: LocalizedError {
    case executableNotFound(String)
    case timedOut(command: String, timeout: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let binary):
            return "Executable not found: \(binary)"
        case .timedOut(let command, let timeout):
            return "Command timed out after \(Int(timeout))s: \(command)"
        }
    }
}

final class ProcessExecutor {
    func run(
        _ launchPath: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval = 90
    ) throws -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: launchPath) || launchPath.hasPrefix("/") else {
            throw ProcessExecutorError.executableNotFound(launchPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment, uniquingKeysWith: { _, new in new })
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutData = NSMutableData()
        let stderrData = NSMutableData()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdoutData.append(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderrData.append(data)
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        try process.run()
        let waitResult = semaphore.wait(timeout: .now() + timeout)

        if waitResult == .timedOut {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 2)
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw ProcessExecutorError.timedOut(command: "\(launchPath) \(arguments.joined(separator: " "))", timeout: timeout)
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingStdout.isEmpty { stdoutData.append(remainingStdout) }

        let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingStderr.isEmpty { stderrData.append(remainingStderr) }

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData as Data, as: UTF8.self),
            stderr: String(decoding: stderrData as Data, as: UTF8.self)
        )
    }
}
