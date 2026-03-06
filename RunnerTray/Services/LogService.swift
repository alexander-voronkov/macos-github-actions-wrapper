import Foundation

final class LogService {
    func diagDirectory(for runnerFolder: URL) -> URL {
        runnerFolder.appendingPathComponent("_diag")
    }

    func latestLogFile(in runnerFolder: URL) -> URL? {
        let diag = diagDirectory(for: runnerFolder)
        guard let files = try? FileManager.default.contentsOfDirectory(at: diag, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return nil
        }

        return files
            .filter { $0.pathExtension == "log" }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
            .first
    }

    func readLatestLog(in runnerFolder: URL) -> String {
        guard let url = latestLogFile(in: runnerFolder),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return "No diagnostic logs found yet."
        }
        return text
    }

    func tail(in runnerFolder: URL, lineCount: Int = 30) -> String {
        let body = readLatestLog(in: runnerFolder)
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(lineCount).joined(separator: "\n")
    }
}
