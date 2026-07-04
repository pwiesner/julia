import BeeperKit
import Foundation

actor TmuxService {
    /// Field separator for `-F` format strings. Window names and pane paths
    /// can contain ":" (or nearly anything else printable), so fields need an
    /// exotic separator. It must be a *printable* character: tmux escapes
    /// non-printable bytes in format output (U+001F would arrive as the
    /// literal text "\037"), so the ASCII unit separator itself is unusable.
    /// U+241F (␟, "symbol for unit separator") passes through verbatim and
    /// does not plausibly appear in session names, window names, or paths.
    private static let fieldSeparator = "\u{241F}"

    private let tmuxPath: String

    init() {
        // Try common tmux locations
        let paths = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        self.tmuxPath = paths.first { FileManager.default.fileExists(atPath: $0) } ?? "tmux"
    }

    // MARK: - Query Commands

    func listSessions() async throws -> [TmuxSession] {
        // Two tmux calls regardless of session count: one for sessions,
        // one for ALL windows across ALL sessions. This is O(1) in tmux
        // process spawns and scales cleanly to hundreds of sessions/windows.
        let sep = Self.fieldSeparator
        async let sessionsOutput = execute([
            "list-sessions",
            "-F",
            ["#{session_id}", "#{session_name}", "#{session_attached}", "#{session_last_attached}", "#{session_created}"]
                .joined(separator: sep)
        ])

        // Pane fields resolve to the window's active pane.
        async let windowsOutput = execute([
            "list-windows",
            "-a",
            "-F",
            ["#{session_id}", "#{session_name}", "#{window_id}", "#{window_index}", "#{window_name}",
             "#{window_active}", "#{window_activity}", "#{pane_current_path}", "#{pane_current_command}"]
                .joined(separator: sep)
        ])

        // The window the user's client is on. window_active can't answer
        // this: every attached session has an "active" window. Errors (no
        // client at all) just mean no window is current.
        async let currentWindowOutput = execute(["display-message", "-p", "#{window_id}"])

        let (sessionsLines, windowsLines) = try await (sessionsOutput, windowsOutput)
        let currentWindowId = (try? await currentWindowOutput) ?? ""
        guard !sessionsLines.isEmpty else { return [] }

        // Bucket all windows by session id in one pass. Branch lookups are
        // file reads; cache per refresh since windows often share a directory.
        var windowsBySessionId: [String: [TmuxWindow]] = [:]
        var branchByPath: [String: String?] = [:]
        for line in windowsLines.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: sep)
            guard parts.count >= 9,
                  let index = Int(parts[3]) else { continue }

            let sessionId = parts[0]
            let lastActivity: Date? = {
                guard let timestamp = TimeInterval(parts[6]), timestamp > 0 else { return nil }
                return Date(timeIntervalSince1970: timestamp)
            }()
            let currentPath = parts[7].isEmpty ? nil : parts[7]
            let currentCommand = parts[8].isEmpty ? nil : parts[8]
            let gitBranch = currentPath.flatMap { path in
                branchByPath[path, default: GitService.currentBranch(forDirectory: path)]
            }
            if let currentPath { branchByPath[currentPath] = gitBranch }
            // Agent activity is deliberately NOT resolved here: it needs a
            // pane capture per candidate window, which dominates load time
            // on large servers. See agentActivities(in:).
            let window = TmuxWindow(
                id: parts[2],
                index: index,
                name: parts[4],
                sessionName: parts[1],
                isActive: parts[5] == "1",
                isCurrent: parts[2] == currentWindowId,
                lastActivity: lastActivity,
                currentPath: currentPath,
                currentCommand: currentCommand,
                gitBranch: gitBranch
            )
            windowsBySessionId[sessionId, default: []].append(window)
        }

        var sessions: [TmuxSession] = []
        for line in sessionsLines.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: sep)
            guard parts.count >= 5 else { continue }

            let sessionId = parts[0]
            let sessionName = parts[1]
            let isAttached = parts[2] == "1"
            // tmux returns 0 for sessions that have never been attached.
            let lastAttached: Date? = {
                guard let timestamp = TimeInterval(parts[3]), timestamp > 0 else { return nil }
                return Date(timeIntervalSince1970: timestamp)
            }()
            let created: Date? = {
                guard let timestamp = TimeInterval(parts[4]), timestamp > 0 else { return nil }
                return Date(timeIntervalSince1970: timestamp)
            }()

            sessions.append(TmuxSession(
                id: sessionId,
                name: sessionName,
                windows: windowsBySessionId[sessionId] ?? [],
                isAttached: isAttached,
                lastAttached: lastAttached,
                created: created
            ))
        }

        // tmux produced output but nothing parsed: something mangled the
        // field separator. Fail loudly rather than showing an empty palette.
        guard !sessions.isEmpty else {
            throw TmuxError.executionFailed("Could not parse tmux output — unexpected format")
        }

        return sessions
    }

    /// Commands whose panes are worth inspecting for a Claude session.
    /// Claude sometimes runs behind a "node" shim, and newer builds title
    /// their process with a bare version string, so plain agent-command
    /// matching misses both; the pane classifier returns nil for actual
    /// node apps or other version-titled processes, so the extra captures
    /// cost a few spawns and nothing else.
    private static func mayHostAgent(_ command: String?) -> Bool {
        TmuxWindow.isAgentCommand(command)
            || command?.lowercased() == "node"
            || TmuxWindow.isVersionNumber(command)
    }

    /// Maps every pane id to its window id, for resolving beeper sessions
    /// (which record their $TMUX_PANE) to windows.
    private nonisolated func paneWindowMap() async throws -> [String: String] {
        let sep = Self.fieldSeparator
        let output = try await execute([
            "list-panes", "-a", "-F",
            ["#{pane_id}", "#{window_id}"].joined(separator: sep)
        ])
        var map: [String: String] = [:]
        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: sep)
            guard parts.count >= 2 else { continue }
            map[parts[0]] = parts[1]
        }
        return map
    }

    /// Captures the given window's active pane and classifies any Claude
    /// session found in it.
    private nonisolated func paneActivity(windowId: String) async -> ClaudeActivity? {
        guard let text = try? await execute(["capture-pane", "-p", "-t", windowId]) else { return nil }
        return ClaudeSessionService.activity(fromPaneText: text)
    }

    /// A window's agent classification, with whatever context the source
    /// provides: beeper-backed entries carry the exact ask time and the
    /// notification text; scraped entries have only the activity.
    struct AgentStatus: Sendable, Equatable {
        var activity: ClaudeActivity
        var message: String?
        var since: Date?
    }

    /// Classifies agent state for every candidate window. Sessions that
    /// report through beeper hooks are authoritative — exact state, mapped
    /// to their window by pane id, no scraping. Windows without beeper
    /// data fall back to pane-capture classification, a bounded number at
    /// a time. Kept separate from listSessions() so the palette paints
    /// immediately; on servers with 100+ windows the captures otherwise
    /// add whole seconds of latency.
    nonisolated func agentActivities(in windows: [TmuxWindow]) async -> [String: AgentStatus] {
        var result: [String: AgentStatus] = [:]

        // Pane ids are never reused within a tmux server's lifetime, so a
        // stale state file (session died without SessionEnd) simply maps
        // to no live pane and drops out.
        if let paneMap = try? await paneWindowMap() {
            for session in BeeperStore.sessions() {
                guard let pane = session.tmuxPane, let windowId = paneMap[pane] else { continue }
                let activity: ClaudeActivity = switch session.state {
                case .working: .working
                case .waitingForInput: .waitingForInput
                case .waitingForPermission: .waitingForPermission
                }
                result[windowId] = AgentStatus(
                    activity: activity,
                    message: session.message,
                    since: session.since
                )
            }
        }

        let candidates = windows
            .filter { result[$0.id] == nil && Self.mayHostAgent($0.currentCommand) }
            .map(\.id)
        guard !candidates.isEmpty else { return result }
        await withTaskGroup(of: (String, ClaudeActivity?).self) { group in
            var pending = candidates.makeIterator()
            func addNext() -> Bool {
                guard let id = pending.next() else { return false }
                group.addTask { (id, await self.paneActivity(windowId: id)) }
                return true
            }
            // Each capture briefly ties up a thread while tmux responds;
            // keep the fan-out modest so the thread pool isn't starved.
            var started = 0
            while started < 6, addNext() { started += 1 }
            for await (id, activity) in group {
                if let activity { result[id] = AgentStatus(activity: activity) }
                _ = addNext()
            }
        }
        return result
    }

    /// Snapshot of an active pane's visible state, including the actual
    /// pane dimensions so a renderer can size itself correctly.
    struct PaneCapture: Sendable {
        let content: String
        let cols: Int
        let rows: Int
    }

    /// Captures the current visible content of the active pane in the given
    /// target window along with its pixel dimensions. Target format is
    /// "<session>:<window_index>". Two parallel tmux calls (capture + size).
    func capturePane(target: String) async throws -> PaneCapture {
        async let content = execute([
            "capture-pane",
            "-p",
            "-e",
            "-J",
            "-t", target
        ])
        async let dimensions = execute([
            "display-message",
            "-p",
            "-t", target,
            "#{pane_width}x#{pane_height}"
        ])

        let (text, dim) = try await (content, dimensions)
        let parts = dim.components(separatedBy: "x")
        guard parts.count == 2,
              let cols = Int(parts[0]),
              let rows = Int(parts[1]) else {
            throw TmuxError.executionFailed("Invalid pane dimensions: \(dim)")
        }
        return PaneCapture(content: text, cols: cols, rows: rows)
    }

    func isServerRunning() async -> Bool {
        do {
            _ = try await execute(["list-sessions"])
            return true
        } catch {
            return false
        }
    }

    // MARK: - Session Commands

    func switchToSession(_ sessionName: String) async throws {
        _ = try await execute(["switch-client", "-t", sessionName])
    }

    func createSession(name: String) async throws {
        _ = try await execute(["new-session", "-d", "-s", name])
        _ = try await execute(["switch-client", "-t", name])
    }

    func renameSession(from oldName: String, to newName: String) async throws {
        _ = try await execute(["rename-session", "-t", oldName, newName])
    }

    func killSession(_ sessionName: String) async throws {
        _ = try await execute(["kill-session", "-t", sessionName])
    }

    // MARK: - Window Commands

    func switchToWindow(sessionName: String, windowIndex: Int) async throws {
        _ = try await execute(["select-window", "-t", "\(sessionName):\(windowIndex)"])
        _ = try await execute(["switch-client", "-t", sessionName])
    }

    func createWindow(in sessionName: String? = nil) async throws {
        if let session = sessionName {
            _ = try await execute(["new-window", "-t", session])
        } else {
            _ = try await execute(["new-window"])
        }
    }

    func moveWindow(to sessionName: String) async throws {
        _ = try await execute(["move-window", "-t", sessionName])
    }

    func renameWindow(_ newName: String, target: String? = nil) async throws {
        if let target {
            _ = try await execute(["rename-window", "-t", target, newName])
        } else {
            _ = try await execute(["rename-window", newName])
        }
    }

    // MARK: - Execute Command

    func executeCommand(_ command: TmuxCommand) async throws {
        switch command.type {
        case .switchSession:
            guard let session = command.argument else {
                throw TmuxError.missingArgument("session name")
            }
            try await switchToSession(session)

        case .newSession:
            guard let name = command.argument else {
                throw TmuxError.missingArgument("session name")
            }
            try await createSession(name: name)

        case .renameSession:
            guard let newName = command.argument,
                  let oldName = command.targetSession else {
                throw TmuxError.missingArgument("session names")
            }
            try await renameSession(from: oldName, to: newName)

        case .killSession:
            guard let session = command.argument else {
                throw TmuxError.missingArgument("session name")
            }
            try await killSession(session)

        case .moveWindow:
            guard let session = command.argument else {
                throw TmuxError.missingArgument("target session")
            }
            try await moveWindow(to: session)

        case .newWindow:
            try await createWindow()

        case .renameWindow:
            guard let name = command.argument else {
                throw TmuxError.missingArgument("window name")
            }
            try await renameWindow(name, target: command.targetSession)
        }
    }

    // MARK: - Private

    // Nonisolated so pane captures can run concurrently instead of
    // serializing on the actor. The body only touches locals and the
    // immutable tmuxPath. waitUntilExit blocks the calling thread, which is
    // why callers bound their fan-out.
    private nonisolated func execute(_ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tmuxPath)
            process.arguments = arguments

            // Finder-launched apps get launchd's bare C-locale environment,
            // under which tmux transliterates the multibyte field separator
            // to "_" and every row fails parsing. Force UTF-8 so output is
            // identical regardless of how the app was launched.
            var environment = ProcessInfo.processInfo.environment
            environment["LC_CTYPE"] = "en_US.UTF-8"
            process.environment = environment

            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: output)
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: TmuxError.executionFailed(errorMessage))
                }
            } catch {
                continuation.resume(throwing: TmuxError.processError(error))
            }
        }
    }
}

enum TmuxError: LocalizedError {
    case executionFailed(String)
    case processError(Error)
    case missingArgument(String)
    case serverNotRunning

    var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            "tmux error: \(message)"
        case .processError(let error):
            "Process error: \(error.localizedDescription)"
        case .missingArgument(let arg):
            "Missing argument: \(arg)"
        case .serverNotRunning:
            "tmux server is not running"
        }
    }
}
