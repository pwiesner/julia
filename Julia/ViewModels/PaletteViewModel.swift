import Foundation
import SwiftUI

@MainActor
@Observable
final class PaletteViewModel {
    var searchText = ""
    var sessions: [TmuxSession] = []
    var selectedIndex = 0
    var errorMessage: String?
    var isLoading = false

    private let tmuxService = TmuxService()

    var filteredItems: [PaletteItem] {
        var items: [PaletteItem] = []
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)

        // Parse command from search text
        let parsedCommand = parseCommand(from: searchText)

        // Add matching sessions
        for session in sessions {
            if query.isEmpty || session.name.lowercased().contains(query) {
                items.append(PaletteItem(
                    title: session.name,
                    subtitle: "^[\(session.windows.count) window](inflect: true)" + (session.isAttached ? " (attached)" : ""),
                    icon: "terminal",
                    action: .switchSession(session.name)
                ))
            }

            // Add matching windows
            for window in session.windows {
                if query.isEmpty || window.name.lowercased().contains(query) {
                    items.append(PaletteItem(
                        title: "\(session.name):\(window.index) \(window.name)",
                        subtitle: "Window in \(session.name)",
                        icon: "macwindow",
                        action: .switchWindow(sessionName: session.name, windowIndex: window.index)
                    ))
                }
            }
        }

        // Add commands based on context
        if let command = parsedCommand {
            // Add the parsed command as the first option
            items.insert(PaletteItem(
                title: command.displayText,
                subtitle: "Execute command",
                icon: command.type.icon,
                action: .executeCommand(command)
            ), at: 0)
        } else if !query.isEmpty {
            // Show relevant commands when there's a search query
            addContextualCommands(to: &items, query: query)
        } else {
            // Show all commands when search is empty
            addAllCommands(to: &items)
        }

        return items
    }

    func refresh() {
        Task {
            await loadSessions()
        }
    }

    func loadSessions() async {
        isLoading = true
        defer { isLoading = false }

        do {
            sessions = try await tmuxService.listSessions()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            sessions = []
        }
    }

    func selectNext() {
        let items = filteredItems
        guard !items.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, items.count - 1)
    }

    func selectPrevious() {
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func executeSelected() async {
        let items = filteredItems
        guard selectedIndex < items.count else { return }

        let item = items[selectedIndex]
        await execute(action: item.action)
    }

    func switchToSession(_ sessionName: String) async {
        do {
            try await tmuxService.switchToSession(sessionName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func switchToWindow(session: String, windowIndex: Int) async {
        do {
            try await tmuxService.switchToWindow(sessionName: session, windowIndex: windowIndex)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private

    private func execute(action: PaletteItem.PaletteAction) async {
        do {
            switch action {
            case .switchSession(let name):
                try await tmuxService.switchToSession(name)

            case .switchWindow(let session, let windowIndex):
                try await tmuxService.switchToWindow(sessionName: session, windowIndex: windowIndex)

            case .command:
                // Commands without arguments need more input
                break

            case .executeCommand(let command):
                try await tmuxService.executeCommand(command)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parseCommand(from input: String) -> TmuxCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)

        guard let firstPart = parts.first?.lowercased() else { return nil }

        // Direct session switch: just type session name
        if let session = sessions.first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            return TmuxCommand(type: .switchSession, argument: session.name)
        }

        // Command parsing
        switch firstPart {
        case "new", "n":
            if parts.count > 1 {
                return TmuxCommand(type: .newSession, argument: parts[1])
            }

        case "kill", "k":
            if parts.count > 1 {
                return TmuxCommand(type: .killSession, argument: parts[1])
            }

        case "rename", "r":
            // Format: "rename old to new" or "rename new" (for current session)
            if parts.count > 1 {
                let args = parts[1]
                if args.lowercased().contains(" to ") {
                    let renameParts = args.components(separatedBy: " to ")
                    if renameParts.count == 2 {
                        return TmuxCommand(
                            type: .renameSession,
                            argument: renameParts[1].trimmingCharacters(in: .whitespaces),
                            targetSession: renameParts[0].trimmingCharacters(in: .whitespaces)
                        )
                    }
                }
            }

        case "move", "m":
            if parts.count > 1 {
                let target = parts[1].replacingOccurrences(of: "to ", with: "").trimmingCharacters(in: .whitespaces)
                return TmuxCommand(type: .moveWindow, argument: target)
            }

        case "window", "w":
            return TmuxCommand(type: .newWindow)

        case "rename-window", "rw":
            if parts.count > 1 {
                return TmuxCommand(type: .renameWindow, argument: parts[1])
            }

        case "switch", "s":
            if parts.count > 1 {
                return TmuxCommand(type: .switchSession, argument: parts[1])
            }

        default:
            break
        }

        return nil
    }

    private func addContextualCommands(to items: inout [PaletteItem], query: String) {
        let lowerQuery = query.lowercased()

        // If query might be a new session name
        if !sessions.contains(where: { $0.name.lowercased() == lowerQuery }) {
            items.append(PaletteItem(
                title: "Create session: \(query)",
                subtitle: "new \(query)",
                icon: TmuxCommandType.newSession.icon,
                action: .executeCommand(TmuxCommand(type: .newSession, argument: query))
            ))
        }

        // Add filtered commands
        for commandType in TmuxCommandType.allCases {
            if commandType.displayName.lowercased().contains(lowerQuery) ||
               commandType.rawValue.contains(lowerQuery) {
                items.append(PaletteItem(
                    title: commandType.displayName,
                    subtitle: commandType.rawValue,
                    icon: commandType.icon,
                    action: .command(commandType)
                ))
            }
        }
    }

    private func addAllCommands(to items: inout [PaletteItem]) {
        items.append(contentsOf: [
            PaletteItem(
                title: "New session",
                subtitle: "new <name>",
                icon: TmuxCommandType.newSession.icon,
                action: .command(.newSession)
            ),
            PaletteItem(
                title: "New window",
                subtitle: "window",
                icon: TmuxCommandType.newWindow.icon,
                action: .executeCommand(TmuxCommand(type: .newWindow))
            ),
            PaletteItem(
                title: "Rename session",
                subtitle: "rename <old> to <new>",
                icon: TmuxCommandType.renameSession.icon,
                action: .command(.renameSession)
            ),
            PaletteItem(
                title: "Rename window",
                subtitle: "rename-window <name>",
                icon: TmuxCommandType.renameWindow.icon,
                action: .command(.renameWindow)
            ),
            PaletteItem(
                title: "Move window",
                subtitle: "move <session>",
                icon: TmuxCommandType.moveWindow.icon,
                action: .command(.moveWindow)
            ),
            PaletteItem(
                title: "Kill session",
                subtitle: "kill <name>",
                icon: TmuxCommandType.killSession.icon,
                action: .command(.killSession)
            )
        ])
    }
}
