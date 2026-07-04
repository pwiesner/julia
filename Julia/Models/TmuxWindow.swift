import SwiftUI

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
    /// What the Claude session in this window's directory is doing, if
    /// known. Mutable because it's filled in by a second, slower pass after
    /// the window list has already been shown.
    var agentActivity: ClaudeActivity?

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

    /// Claude Code (2.1+) sets its process title to a bare version string
    /// like "2.1.191", so that's what tmux reports as the pane command.
    static func isVersionNumber(_ command: String?) -> Bool {
        guard let command else { return false }
        return command.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil
    }

    var isAgentRunning: Bool {
        Self.isAgentCommand(currentCommand) || agentActivity != nil
    }

    /// How recently a waiting session must have been active to count as
    /// genuinely waiting on the user; beyond this it's just idle.
    static let waitingFreshnessLimit: TimeInterval = 24 * 60 * 60

    /// Claude asked for input recently enough that an answer is plausibly
    /// wanted. Sessions left at a prompt for days are idle, not waiting.
    var isAwaitingUser: Bool {
        guard agentActivity == .waitingForInput else { return false }
        guard let lastActivity else { return true }
        return Date.now.timeIntervalSince(lastActivity) < Self.waitingFreshnessLimit
    }

    var isIdleAgent: Bool {
        agentActivity == .waitingForInput && !isAwaitingUser
    }

    /// Short label for the agent's state; the glyph shape shows it visually,
    /// this names it for VoiceOver.
    var agentStatusText: String? {
        switch agentActivity {
        case .working: "working"
        case .waitingForInput: isAwaitingUser ? "your turn" : "idle"
        case nil: nil
        }
    }

    /// SF Symbol for agent windows: a filled speech bubble when Claude is
    /// freshly waiting on the user, an outline once it's gone idle,
    /// sparkles otherwise. Nil for non-agent windows.
    var agentGlyph: String? {
        guard isAgentRunning else { return nil }
        return switch agentActivity {
        case .waitingForInput: isAwaitingUser ? "bubble.left.fill" : "bubble.left"
        default: "sparkles"
        }
    }

    var agentGlyphColor: Color? {
        switch agentActivity {
        case .working: .orange
        case .waitingForInput: isAwaitingUser ? .blue : .secondary
        case nil: isAgentRunning ? .orange : nil
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
            currentCommand.map { command in
                if Self.isVersionNumber(command), agentActivity != nil {
                    // A classified Claude session whose process title is its
                    // version number; show what it is, not "2.1.191".
                    "claude"
                } else if command.hasSuffix(".exe") {
                    String(command.dropLast(4))
                } else {
                    command
                }
            }
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
