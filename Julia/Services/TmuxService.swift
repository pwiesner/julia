import Foundation

actor TmuxService {
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
        async let sessionsOutput = execute([
            "list-sessions",
            "-F",
            "#{session_id}:#{session_name}:#{session_attached}:#{session_last_attached}"
        ])

        async let windowsOutput = execute([
            "list-windows",
            "-a",
            "-F",
            "#{session_id}:#{session_name}:#{window_id}:#{window_index}:#{window_name}:#{window_active}:#{window_activity}"
        ])

        let (sessionsLines, windowsLines) = try await (sessionsOutput, windowsOutput)
        guard !sessionsLines.isEmpty else { return [] }

        // Bucket all windows by session id in one pass.
        var windowsBySessionId: [String: [TmuxWindow]] = [:]
        for line in windowsLines.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: ":")
            guard parts.count >= 7,
                  let index = Int(parts[3]) else { continue }

            let sessionId = parts[0]
            let lastActivity: Date? = {
                guard let timestamp = TimeInterval(parts[6]), timestamp > 0 else { return nil }
                return Date(timeIntervalSince1970: timestamp)
            }()
            let window = TmuxWindow(
                id: parts[2],
                index: index,
                name: parts[4],
                sessionName: parts[1],
                isActive: parts[5] == "1",
                lastActivity: lastActivity
            )
            windowsBySessionId[sessionId, default: []].append(window)
        }

        var sessions: [TmuxSession] = []
        for line in sessionsLines.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: ":")
            guard parts.count >= 4 else { continue }

            let sessionId = parts[0]
            let sessionName = parts[1]
            let isAttached = parts[2] == "1"
            // tmux returns 0 for sessions that have never been attached.
            let lastAttached: Date? = {
                guard let timestamp = TimeInterval(parts[3]), timestamp > 0 else { return nil }
                return Date(timeIntervalSince1970: timestamp)
            }()

            sessions.append(TmuxSession(
                id: sessionId,
                name: sessionName,
                windows: windowsBySessionId[sessionId] ?? [],
                isAttached: isAttached,
                lastAttached: lastAttached
            ))
        }

        return sessions
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

    private func execute(_ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tmuxPath)
            process.arguments = arguments

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
