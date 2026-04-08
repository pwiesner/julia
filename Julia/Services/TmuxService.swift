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
        let output = try await execute([
            "list-sessions",
            "-F",
            "#{session_id}:#{session_name}:#{session_attached}"
        ])

        guard !output.isEmpty else { return [] }

        var sessions: [TmuxSession] = []

        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: ":")
            guard parts.count >= 3 else { continue }

            let sessionId = parts[0]
            let sessionName = parts[1]
            let isAttached = parts[2] == "1"

            let windows = try await listWindows(for: sessionName)
            let session = TmuxSession(
                id: sessionId,
                name: sessionName,
                windows: windows,
                isAttached: isAttached
            )
            sessions.append(session)
        }

        return sessions
    }

    func listWindows(for sessionName: String) async throws -> [TmuxWindow] {
        let output = try await execute([
            "list-windows",
            "-t", sessionName,
            "-F",
            "#{window_id}:#{window_index}:#{window_name}:#{window_active}"
        ])

        guard !output.isEmpty else { return [] }

        var windows: [TmuxWindow] = []

        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: ":")
            guard parts.count >= 4,
                  let index = Int(parts[1]) else { continue }

            let window = TmuxWindow(
                id: parts[0],
                index: index,
                name: parts[2],
                sessionName: sessionName,
                isActive: parts[3] == "1"
            )
            windows.append(window)
        }

        return windows
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
