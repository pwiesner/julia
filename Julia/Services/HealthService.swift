import BeeperKit
import Foundation

/// Detects the state of julia's external dependencies for the settings
/// health section: tmux (required), beeper hooks and gh (optional, but
/// features quietly shrink without them). Checked when the settings
/// window opens — never on a timer.
enum HealthService {
    struct Dependency: Identifiable, Sendable {
        enum Level: Sendable {
            case good
            /// Absent or unusable, and julia degrades rather than breaks.
            case limited
            /// Absent and julia can't do its job.
            case missing
        }

        let name: String
        /// Fixed display position, so rows streaming in as their checks
        /// finish don't shuffle.
        let rank: Int
        let level: Level
        let detail: String
        var id: String { name }
    }

    /// Yields each dependency as its check completes. Streamed, not
    /// gathered: gh's check can hang on network or keychain, and one
    /// slow probe must not hold the whole section at "Checking…".
    static func check() -> AsyncStream<Dependency> {
        AsyncStream { continuation in
            Task {
                await withTaskGroup(of: Dependency.self) { group in
                    group.addTask { await checkTmux() }
                    group.addTask { checkBeeper() }
                    group.addTask { await checkVisitHooks() }
                    group.addTask { await checkGh() }
                    for await dependency in group {
                        continuation.yield(dependency)
                    }
                    continuation.finish()
                }
            }
        }
    }

    /// The one opt-in dependency: julia never touches tmux hooks on its
    /// own — the health row offers an install button instead.
    private static func checkVisitHooks() async -> Dependency {
        guard TmuxService.installedPath() != nil else {
            return Dependency(name: "visit hooks", rank: 2, level: .limited, detail: "needs tmux")
        }
        let hooks = (try? await TmuxService().globalHooks()) ?? ""
        return hooks.contains("visits.log")
            ? Dependency(name: "visit hooks", rank: 2, level: .good, detail: "native switches feed frecency")
            : Dependency(name: "visit hooks", rank: 2, level: .limited, detail: "only palette jumps rank")
    }

    /// True when the visit hooks aren't installed and could be — drives
    /// the install button on the health row.
    static func canInstallVisitHooks(_ dependency: Dependency) -> Bool {
        dependency.name == "visit hooks" && dependency.level == .limited
            && TmuxService.installedPath() != nil
    }

    static func installVisitHooks() async {
        try? await TmuxService().installVisitHooks(logPath: VisitIngestService.logPath)
    }

    private static func checkTmux() async -> Dependency {
        guard let path = TmuxService.installedPath() else {
            return Dependency(name: "tmux", rank: 0, level: .missing, detail: "not found — julia can't see any windows")
        }
        let running = await TmuxService().isServerRunning()
        return Dependency(
            name: "tmux",
            rank: 0,
            level: .good,
            detail: running ? "\(path) · server running" : "\(path) · no server running"
        )
    }

    private static func checkBeeper() -> Dependency {
        let binary = URL.homeDirectory.appending(path: ".local/bin/beeper")
        let installed = FileManager.default.fileExists(atPath: binary.path(percentEncoded: false))
        let reporting = BeeperStore.sessions().count

        return if reporting > 0 {
            Dependency(
                name: "beeper hooks",
                rank: 1,
                level: .good,
                detail: reporting == 1
                    ? "1 session reporting exact state"
                    : "\(reporting) sessions reporting exact state"
            )
        } else if installed {
            Dependency(name: "beeper hooks", rank: 1, level: .good, detail: "installed — no sessions reporting yet")
        } else {
            Dependency(name: "beeper hooks", rank: 1, level: .limited, detail: "not installed — agent state falls back to pane scraping")
        }
    }

    private static func checkGh() async -> Dependency {
        guard let path = PullRequestService.installedPath() else {
            return Dependency(name: "gh", rank: 3, level: .limited, detail: "not installed — PR lookups off")
        }
        let authed = await exitStatus(of: path, arguments: ["auth", "status"]) == 0
        return authed
            ? Dependency(name: "gh", rank: 3, level: .good, detail: "signed in — PR lookups on")
            : Dependency(name: "gh", rank: 3, level: .limited, detail: "not signed in or not responding — PR lookups off")
    }

    /// Runs to completion or the timeout, whichever comes first — gh can
    /// stall on the network or a keychain prompt, and a health probe
    /// must never hang the page it reports to.
    private static func exitStatus(
        of executable: String,
        arguments: [String],
        timeout: Duration = .seconds(5)
    ) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
                Task {
                    try? await Task.sleep(for: timeout)
                    if process.isRunning {
                        process.terminate()
                    }
                }
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: -1)
            }
        }
    }
}
