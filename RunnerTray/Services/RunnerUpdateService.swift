import Foundation

struct RunnerRelease: Codable {
    let tag_name: String
    let assets: [RunnerAsset]

    var version: String {
        tag_name.replacingOccurrences(of: "v", with: "")
    }

    var arm64Asset: RunnerAsset? {
        assets.first { $0.name.contains("osx-arm64") && $0.name.hasSuffix(".tar.gz") }
    }
}

struct RunnerAsset: Codable {
    let name: String
    let browser_download_url: String
    let size: Int
}

enum RunnerUpdateError: LocalizedError {
    case noRunnerFolder
    case cannotDetermineCurrentVersion
    case noCompatibleAsset
    case downloadFailed(String)
    case extractionFailed(String)
    case alreadyUpToDate(current: String, latest: String)

    var errorDescription: String? {
        switch self {
        case .noRunnerFolder:
            return "Runner folder is not configured"
        case .cannotDetermineCurrentVersion:
            return "Cannot determine current runner version"
        case .noCompatibleAsset:
            return "No compatible macOS ARM64 runner binary found in the latest release"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .extractionFailed(let reason):
            return "Extraction failed: \(reason)"
        case .alreadyUpToDate(let current, let latest):
            return "Runner is up to date (current: \(current), latest: \(latest))"
        }
    }
}

final class RunnerUpdateService {
    private let executor = ProcessExecutor()
    private let session = URLSession.shared
    private let fileManager = FileManager.default

    private let releasesURL = URL(string: "https://api.github.com/repos/actions/runner/releases/latest")!

    /// Fetch the latest runner release info from GitHub.
    func fetchLatestRelease() async throws -> RunnerRelease {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RunnerUpdateError.downloadFailed("GitHub API returned non-200 status")
        }
        return try JSONDecoder().decode(RunnerRelease.self, from: data)
    }

    /// Read the current runner version from the runner folder.
    func currentVersion(in folder: URL) -> String? {
        // Try reading from bin/Runner.Listener --version via run.sh
        let runnerBin = folder.appendingPathComponent("bin/Runner.Listener")
        if fileManager.isExecutableFile(atPath: runnerBin.path) {
            if let result = try? executor.run(runnerBin.path, arguments: ["--version"], timeout: 10),
               result.exitCode == 0 {
                let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !version.isEmpty { return version }
            }
        }

        // Fallback: read from .runner file
        let dotRunner = folder.appendingPathComponent(".runner")
        if let data = try? Data(contentsOf: dotRunner),
           let text = String(data: data, encoding: .utf8) {
            // .runner is JSON with "agentVersion" field
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ver = json["agentVersion"] as? String {
                return ver
            }
        }

        return nil
    }

    /// Check if an update is available. Returns the release if newer, nil if up to date.
    func checkForUpdate(in folder: URL) async throws -> RunnerRelease? {
        let release = try await fetchLatestRelease()
        let current = currentVersion(in: folder)

        guard let current else {
            // Can't determine current — offer update
            return release
        }

        if compareVersions(current, release.version) == .orderedAscending {
            return release
        }
        return nil
    }

    /// Download and extract the runner update, replacing files in the runner folder.
    /// The runner MUST be stopped before calling this.
    func applyUpdate(release: RunnerRelease, to folder: URL) async throws {
        guard let asset = release.arm64Asset else {
            throw RunnerUpdateError.noCompatibleAsset
        }

        // Download to temp
        let downloadURL = URL(string: asset.browser_download_url)!
        let (tempFile, response) = try await session.download(from: downloadURL)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RunnerUpdateError.downloadFailed("HTTP status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        // Move to a known temp path
        let tarPath = fileManager.temporaryDirectory.appendingPathComponent("runner-update.tar.gz")
        try? fileManager.removeItem(at: tarPath)
        try fileManager.moveItem(at: tempFile, to: tarPath)

        // Extract over existing folder
        let result = try executor.run(
            "/usr/bin/tar",
            arguments: ["xzf", tarPath.path, "-C", folder.path, "--strip-components=0"],
            timeout: 120
        )

        // Cleanup
        try? fileManager.removeItem(at: tarPath)

        if result.exitCode != 0 {
            throw RunnerUpdateError.extractionFailed(result.stderr)
        }
    }

    /// Simple semver comparison (major.minor.patch).
    private func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let partsA = a.split(separator: ".").compactMap { Int($0) }
        let partsB = b.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(partsA.count, partsB.count) {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va < vb { return .orderedAscending }
            if va > vb { return .orderedDescending }
        }
        return .orderedSame
    }
}
