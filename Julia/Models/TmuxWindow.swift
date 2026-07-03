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

    init(
        id: String,
        index: Int,
        name: String,
        sessionName: String,
        isActive: Bool = false,
        lastActivity: Date? = nil,
        currentPath: String? = nil,
        currentCommand: String? = nil
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.sessionName = sessionName
        self.isActive = isActive
        self.lastActivity = lastActivity
        self.currentPath = currentPath
        self.currentCommand = currentCommand
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

    /// True if the window's name, project directory, path, or foreground
    /// command matches the query. Used for palette filtering.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if name.localizedStandardContains(query) { return true }
        if let currentPath, currentPath.localizedStandardContains(query) { return true }
        if let currentCommand, currentCommand.localizedStandardContains(query) { return true }
        return false
    }
}
