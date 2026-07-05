import Foundation

/// Resolves whether a branch has a pull request, via the `gh` CLI.
///
/// `gh pr view` is a network call, so it never runs during scans or
/// refreshes: only the palette's *selected* row resolves, and both hits
/// and misses are cached per repo-and-branch so lingering on a row or
/// revisiting it costs nothing. Without `gh` installed (or authed) every
/// lookup quietly reports no PR.
actor PullRequestService {
    struct PullRequest: Sendable, Equatable {
        let number: Int
        let url: URL
        /// GitHub's lifecycle state: "OPEN", "MERGED", or "CLOSED".
        let state: String
    }

    private var cache: [String: (fetchedAt: Date, pullRequest: PullRequest?)] = [:]

    /// How long an answer stays fresh. PRs appear and merge on human
    /// timescales; five minutes keeps the palette honest without
    /// hammering the API from a held arrow key.
    private static let lifetime: TimeInterval = 5 * 60

    private let ghPath: String? = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        .first { FileManager.default.fileExists(atPath: $0) }

    func pullRequest(directory: String, branch: String) async -> PullRequest? {
        guard let ghPath else { return nil }
        let key = "\(directory)@\(branch)"
        if let cached = cache[key], Date.now.timeIntervalSince(cached.fetchedAt) < Self.lifetime {
            return cached.pullRequest
        }
        let pullRequest = await Self.fetch(ghPath: ghPath, directory: directory, branch: branch)
        cache[key] = (.now, pullRequest)
        return pullRequest
    }

    /// Asks gh for the branch's PR. A non-zero exit usually just means
    /// "no pull request found" — that's an answer, not an error.
    private static func fetch(ghPath: String, directory: String, branch: String) async -> PullRequest? {
        let output: Data? = await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ghPath)
            process.arguments = ["pr", "view", branch, "--json", "number,url,state"]
            process.currentDirectoryURL = URL(filePath: directory)

            // Finder-launched apps get launchd's bare C-locale environment;
            // force UTF-8 so gh's output survives regardless of launch path.
            var environment = ProcessInfo.processInfo.environment
            environment["LC_CTYPE"] = "en_US.UTF-8"
            process.environment = environment

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: process.terminationStatus == 0 ? data : nil)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: nil)
            }
        }

        guard let output,
              let object = try? JSONSerialization.jsonObject(with: output) as? [String: Any],
              let number = object["number"] as? Int,
              let urlString = object["url"] as? String,
              let url = URL(string: urlString),
              let state = object["state"] as? String else { return nil }
        return PullRequest(number: number, url: url, state: state)
    }
}
