import Foundation
import SwiftUI

@MainActor
@Observable
final class PaletteViewModel {
    enum Mode: Equatable {
        case browsing
        case selectingTarget(command: TmuxCommandType)
        case enteringInput(command: TmuxCommandType, target: String)
    }

    var searchText = ""
    var sessions: [TmuxSession] = []
    var selectedIndex = 0
    var errorMessage: String?
    var isLoading = false
    var mode: Mode = .browsing
    var previewContent: TmuxService.PaneCapture?

    private let tmuxService = TmuxService()
    private var previewTask: Task<Void, Never>?

    var placeholder: String {
        switch mode {
        case .browsing:
            "Search sessions, windows, or commands..."
        case .selectingTarget(let command):
            switch command {
            case .renameWindow:
                "Select window to rename..."
            default:
                "Select session to \(command.displayName.lowercased())..."
            }
        case .enteringInput(let command, let target):
            switch command {
            case .renameWindow:
                "New name for window \(target):"
            default:
                "New name for \(target):"
            }
        }
    }

    var filteredItems: [PaletteItem] {
        switch mode {
        case .browsing:
            return browsingItems
        case .selectingTarget(let command):
            switch command {
            case .renameWindow:
                return windowPickerItems
            default:
                return sessionPickerItems
            }
        case .enteringInput:
            return []
        }
    }

    private var browsingItems: [PaletteItem] {
        var items: [PaletteItem] = []
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)

        // Parse command from search text
        let parsedCommand = parseCommand(from: searchText)

        // "<session>:[<window filter>]" — drill into a session and only
        // show its windows, filtered by what comes after the colon.
        if let (session, windowFilter) = sessionDrillDown(query: query) {
            for window in session.windows {
                if window.matches(windowFilter) {
                    items.append(Self.windowItem(for: window, in: session))
                }
            }
            return items
        }

        // Add matching sessions
        for session in sessions {
            if query.isEmpty || session.name.lowercased().contains(query) {
                items.append(PaletteItem(
                    title: session.name,
                    subtitle: Self.sessionSubtitle(for: session),
                    icon: "terminal",
                    action: .switchSession(session.name)
                ))
            }

            // Add matching windows
            for window in session.windows {
                if window.matches(query) {
                    items.append(Self.windowItem(for: window, in: session))
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

    /// Detects "<session>:<filter>" syntax and returns the matched session
    /// plus the window-filter portion. Returns nil if the query doesn't have
    /// a colon or the part before it doesn't exactly match a session name.
    private func sessionDrillDown(query: String) -> (session: TmuxSession, filter: String)? {
        guard let colonIndex = query.firstIndex(of: ":") else { return nil }
        let sessionPart = String(query[..<colonIndex])
        let filterPart = String(query[query.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        guard !sessionPart.isEmpty,
              let session = sessions.first(where: { $0.name.lowercased() == sessionPart }) else {
            return nil
        }
        return (session, filterPart)
    }

    private static func sessionSubtitle(for session: TmuxSession) -> String {
        let count = session.windows.count
        let windows = count == 1 ? "1 window" : "\(count) windows"
        return session.isAttached ? "\(windows) (attached)" : windows
    }

    private static func windowItem(for window: TmuxWindow, in session: TmuxSession) -> PaletteItem {
        // The session is already in the title prefix, so the subtitle carries
        // what the title can't: process, branch, and recency.
        let details = [
            window.secondaryLabel,
            window.gitBranch,
            window.lastActivity?.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
        ].compactMap(\.self)
        return PaletteItem(
            title: "\(session.name):\(window.index) \(window.displayName)",
            subtitle: details.isEmpty ? nil : details.joined(separator: " · "),
            icon: window.isAgentRunning ? "sparkles" : "macwindow",
            action: .switchWindow(sessionName: session.name, windowIndex: window.index)
        )
    }

    private var sessionPickerItems: [PaletteItem] {
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        return sessions
            .filter { query.isEmpty || $0.name.lowercased().contains(query) }
            .map { session in
                PaletteItem(
                    title: session.name,
                    subtitle: Self.sessionSubtitle(for: session),
                    icon: "terminal",
                    action: .switchSession(session.name)
                )
            }
    }

    private var windowPickerItems: [PaletteItem] {
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        var items: [PaletteItem] = []
        for session in sessions {
            for window in session.windows {
                let title = "\(session.name):\(window.index) \(window.displayName)"
                if query.isEmpty || title.localizedStandardContains(query) || window.matches(query) {
                    items.append(Self.windowItem(for: window, in: session))
                }
            }
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

    /// Refreshes `previewContent` based on the current selection. If the
    /// selection is a window, captures its active pane (with a tiny debounce
    /// so rapid arrow-key navigation doesn't spam tmux). Cancels any
    /// in-flight capture from a previous selection.
    func updatePreview() {
        previewTask?.cancel()

        let items = filteredItems
        guard selectedIndex < items.count,
              case .switchWindow(let sessionName, let windowIndex) = items[selectedIndex].action else {
            previewContent = nil
            return
        }

        let target = "\(sessionName):\(windowIndex)"
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, let self else { return }

            do {
                let content = try await tmuxService.capturePane(target: target)
                guard !Task.isCancelled else { return }
                self.previewContent = content
            } catch {
                self.previewContent = nil
            }
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

    /// Returns `true` if the palette should dismiss after this action, `false` to stay open.
    func executeSelected() async -> Bool {
        switch mode {
        case .browsing:
            let items = filteredItems
            guard selectedIndex < items.count else { return false }
            let item = items[selectedIndex]

            // Clicking a chained-flow command transitions into the flow
            // instead of dismissing the palette.
            if case .command(let type) = item.action, beginChainedFlow(for: type) {
                return false
            }

            await execute(action: item.action)
            return true

        case .selectingTarget(let command):
            let items = filteredItems
            guard selectedIndex < items.count else { return false }
            let target: String
            switch items[selectedIndex].action {
            case .switchSession(let name):
                target = name
            case .switchWindow(let sessionName, let windowIndex):
                target = "\(sessionName):\(windowIndex)"
            default:
                return false
            }
            mode = .enteringInput(command: command, target: target)
            searchText = ""
            selectedIndex = 0
            return false

        case .enteringInput(let command, let target):
            let newValue = searchText.trimmingCharacters(in: .whitespaces)
            guard !newValue.isEmpty else { return false }
            let cmd = TmuxCommand(type: command, argument: newValue, targetSession: target)
            await execute(action: .executeCommand(cmd))
            resetToBrowsing()
            return true
        }
    }

    /// Cancels any in-progress chained flow. Returns `true` if a flow was cancelled,
    /// `false` if there was nothing to cancel (caller should treat as a dismiss request).
    func cancelChainedFlow() -> Bool {
        switch mode {
        case .browsing:
            return false
        case .selectingTarget, .enteringInput:
            resetToBrowsing()
            return true
        }
    }

    private func beginChainedFlow(for type: TmuxCommandType) -> Bool {
        switch type {
        case .renameSession, .renameWindow:
            mode = .selectingTarget(command: type)
            searchText = ""
            selectedIndex = 0
            return true
        default:
            return false
        }
    }

    private func resetToBrowsing() {
        mode = .browsing
        searchText = ""
        selectedIndex = 0
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
