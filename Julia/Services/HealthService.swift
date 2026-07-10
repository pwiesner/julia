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
        let level: Level
        let detail: String
        var id: String { name }
    }

    static func check() async -> [Dependency] {
        async let tmux = checkTmux()
        async let gh = checkGh()
        async let visitHooks = checkVisitHooks()
        return await [tmux, checkBeeper(), visitHooks, gh]
    }

    private static func checkVisitHooks() async -> Dependency {
        guard TmuxService.installedPath() != nil else {
            return Dependency(name: "visit hooks", level: .limited, detail: "needs tmux")
        }
        let hooks = (try? await TmuxService().globalHooks()) ?? ""
        return hooks.contains("visits.log")
            ? Dependency(name: "visit hooks", level: .good, detail: "native switches feed frecency")
            : Dependency(name: "visit hooks", level: .limited, detail: "not installed — only palette jumps rank")
    }

    private static func checkTmux() async -> Dependency {
        guard let path = TmuxService.installedPath() else {
            return Dependency(name: "tmux", level: .missing, detail: "not found — julia can't see any windows")
        }
        let running = await TmuxService().isServerRunning()
        return Dependency(
            name: "tmux",
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
                level: .good,
                detail: reporting == 1
                    ? "1 session reporting exact state"
                    : "\(reporting) sessions reporting exact state"
            )
        } else if installed {
            Dependency(name: "beeper hooks", level: .good, detail: "installed — no sessions reporting yet")
        } else {
            Dependency(name: "beeper hooks", level: .limited, detail: "not installed — agent state falls back to pane scraping")
        }
    }

    private static func checkGh() async -> Dependency {
        guard let path = PullRequestService.installedPath() else {
            return Dependency(name: "gh", level: .limited, detail: "not installed — PR lookups off")
        }
        let authed = await exitStatus(of: path, arguments: ["auth", "status"]) == 0
        return authed
            ? Dependency(name: "gh", level: .good, detail: "signed in — PR lookups on")
            : Dependency(name: "gh", level: .limited, detail: "not signed in — PR lookups off")
    }

    private static func exitStatus(of executable: String, arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: -1)
            }
        }
    }
}
