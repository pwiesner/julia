import Foundation

struct TmuxWindow: Identifiable, Hashable, Sendable {
    let id: String
    let index: Int
    let name: String
    let sessionName: String
    let isActive: Bool
    let lastActivity: Date?
    /// Working directory of the window's active pane.
    let currentPath: String?
    /// Foreground process of the window's active pane (e.g. "zsh", "claude").
    let currentCommand: String?
    /// Checked-out branch of the repository at `currentPath`, if any.
    let gitBranch: String?
    /// What the Claude session in this window's directory is doing, if known.
    let agentActivity: ClaudeActivity?

    init(
        id: String,
        index: Int,
        name: String,
        sessionName: String,
        isActive: Bool = false,
        lastActivity: Date? = nil,
        currentPath: String? = nil,
        currentCommand: String? = nil,
        gitBranch: String? = nil,
        agentActivity: ClaudeActivity? = nil
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.sessionName = sessionName
        self.isActive = isActive
        self.lastActivity = lastActivity
        self.currentPath = currentPath
        self.currentCommand = currentCommand
        self.gitBranch = gitBranch
        self.agentActivity = agentActivity
    }

    /// Last component of the pane's working directory — the "project" the
    /// window is sitting in. Nil at uninformative locations like "/" or home.
    var projectName: String? {
        guard let currentPath else { return nil }
        // tmux emits paths without a trailing slash, but normalize both
        // sides anyway so the home comparison can't miss.
        let path = Self.trimmingTrailingSlash(currentPath)
        let home = Self.trimmingTrailingSlash(
            FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        )
        guard !path.isEmpty, path != "/", path != home else { return nil }
        return URL(filePath: path).lastPathComponent
    }

    private static func trimmingTrailingSlash(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// Foreground commands that indicate a coding agent is running in the pane.
    private static let agentCommands: Set<String> = ["claude", "claude.exe", "codex", "aider", "gemini"]

    static func isAgentCommand(_ command: String?) -> Bool {
        guard let command else { return false }
        return agentCommands.contains(command.lowercased())
    }

    var isAgentRunning: Bool {
        Self.isAgentCommand(currentCommand) || agentActivity != nil
    }

    /// Short label for the agent's state, shown alongside the glyph so the
    /// state doesn't rely on color alone.
    var agentStatusText: String? {
        switch agentActivity {
        case .working: "working"
        case .waitingForInput: "your turn"
        case nil: nil
        }
    }

    /// True when the name is tmux's automatic rename (the foreground process)
    /// rather than something the user chose.
    var hasAutomaticName: Bool {
        name.isEmpty || name == currentCommand
    }

    /// Name to show in listings. Auto-generated names like "zsh" or
    /// "claude.exe" say nothing about the window, so prefer the project
    /// directory when there is one; user-chosen names win.
    var displayName: String {
        if hasAutomaticName, let projectName {
            projectName
        } else {
            name.isEmpty ? (currentCommand ?? "?") : name
        }
    }

    /// Context for the detail line, complementing `displayName`: the project
    /// when the title is a user-chosen name, otherwise the foreground command
    /// (since the project has been promoted to the title).
    var secondaryLabel: String? {
        if displayName == projectName {
            currentCommand.map { $0.hasSuffix(".exe") ? String($0.dropLast(4)) : $0 }
        } else {
            projectName
        }
    }

    /// True if the window's name, project directory, path, or foreground
    /// command matches the query. Used for palette filtering.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if name.localizedStandardContains(query) { return true }
        if let currentPath, currentPath.localizedStandardContains(query) { return true }
        if let currentCommand, currentCommand.localizedStandardContains(query) { return true }
        if let gitBranch, gitBranch.localizedStandardContains(query) { return true }
        return false
    }
}
