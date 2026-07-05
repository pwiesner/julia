import BeeperKit
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

    /// What the empty-query browsing list shows; tab flips between windows
    /// and agents, and the tidy command opens the third.
    enum BrowseList {
        case windows
        /// Agent windows only: waiting on the user first (longest wait at
        /// the top), then working.
        case agents
        /// Cleanup candidates: idle agents to wrap up, stale windows to kill.
        case tidy
        /// The keymap, tig-style.
        case help
    }

    var searchText = ""
    var sessions: [TmuxSession] = []
    var selectedIndex = 0
    var errorMessage: String?
    var isLoading = false
    var mode: Mode = .browsing
    var browseList: BrowseList = .windows
    /// One-shot override for what the next palette open shows, e.g. the
    /// menu bar's keymap item. Consumed by the view on appear, which
    /// otherwise resets to windows.
    var pendingBrowseList: BrowseList?
    var previewContent: TmuxService.PaneCapture?
    /// The selected window's pull request, once resolved; nil while
    /// unresolved or when there is none.
    var selectedPullRequest: PullRequestService.PullRequest?

    private let tmuxService = TmuxService()
    private let visitHistory = VisitHistoryService()
    private let pullRequests = PullRequestService()
    private var previewTask: Task<Void, Never>?
    private var pullRequestTask: Task<Void, Never>?
    private var loadGeneration = 0
    private let beeperMonitor = BeeperMonitor()
    private var liveUpdatesTask: Task<Void, Never>?
    /// Whether the palette is on screen; beeper events are ignored while
    /// it isn't, since the next show reloads from scratch anyway.
    private var isPaletteVisible = false

    var placeholder: String {
        switch mode {
        case .browsing:
            switch browseList {
            case .windows: "Search sessions, windows, or commands..."
            case .agents: "Agents — tab for windows"
            case .tidy: "Tidy — ⌘⇧W wrap up · ⌘K kill · esc back"
            case .help: "Keyboard shortcuts — esc back"
            }
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

        // Empty query: the palette's job is jumping, so windows come first
        // in frecency order — the working set assembles at the top and
        // row 0 (preselected) is the previous window, making hotkey+return
        // an instant toggle. Tab flips to the agents overview. Sessions
        // (also by frecency) and commands follow in windows mode.
        if query.isEmpty {
            switch browseList {
            case .agents: return agentOverviewItems
            case .tidy: return tidyItems
            case .help: return []  // the help page renders its own content
            case .windows: break
            }
            items.append(contentsOf: recentWindowItems)
            items.append(contentsOf: frecentSessionItems)
            addAllCommands(to: &items)
            return items
        }

        // Add matching sessions
        for session in sessions {
            if session.name.lowercased().contains(query) {
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
        }
        // Contextual commands appear regardless: a session named "tidy"
        // must not shadow the Tidy up feature (or "help" the keymap).
        addContextualCommands(to: &items, query: query)

        return items
    }

    /// All windows in working-set order: visited windows by frecency, then
    /// unvisited ones by tmux activity, with the window the user is
    /// sitting in last — the palette exists to leave it.
    private var recentWindowItems: [PaletteItem] {
        let all = sessions.flatMap { session in
            session.windows.map { (session: session, window: $0) }
        }
        let now = Date.now

        func rank(_ window: TmuxWindow) -> (tier: Int, value: Double) {
            if window.isCurrent {
                (2, 0)
            } else if let score = visitHistory.score(id: window.id, now: now) {
                (0, score)
            } else {
                (1, window.lastActivity?.timeIntervalSince1970 ?? 0)
            }
        }

        return all
            .sorted {
                let a = rank($0.window)
                let b = rank($1.window)
                return a.tier != b.tier ? a.tier < b.tier : a.value > b.value
            }
            .map { Self.windowItem(for: $0.window, in: $0.session) }
    }

    /// All agents in labeled sections: blocked on permission first (they
    /// have a task mid-flight), then waiting for a reply (longest wait
    /// first), working, and idle sessions parked for over a day.
    private var agentOverviewItems: [PaletteItem] {
        let permission = agentWindows
            .filter { $0.window.agentActivity == .waitingForPermission && $0.window.isAwaitingUser }
            .sorted { ($0.window.askedAt ?? .distantPast) < ($1.window.askedAt ?? .distantPast) }
        let waiting = agentWindows
            .filter { $0.window.agentActivity == .waitingForInput && $0.window.isAwaitingUser }
            .sorted { ($0.window.askedAt ?? .distantPast) < ($1.window.askedAt ?? .distantPast) }
        let working = agentWindows
            .filter { $0.window.agentActivity == .working }
            .sorted { ($0.window.lastActivity ?? .distantPast) > ($1.window.lastActivity ?? .distantPast) }
        let idle = agentWindows
            .filter(\.window.isIdleAgent)
            .sorted { ($0.window.lastActivity ?? .distantPast) > ($1.window.lastActivity ?? .distantPast) }

        var items: [PaletteItem] = []
        for group in [(title: "Needs permission", members: permission),
                      (title: "Needs you", members: waiting),
                      (title: "Working", members: working),
                      (title: "Idle", members: idle)] {
            for (offset, entry) in group.members.enumerated() {
                var item = Self.windowItem(for: entry.window, in: entry.session)
                if offset == 0 {
                    item.sectionTitle = "\(group.title) (\(group.members.count))"
                }
                items.append(item)
            }
        }
        return items
    }

    private var agentWindows: [(session: TmuxSession, window: TmuxWindow)] {
        sessions.flatMap { session in
            session.windows.filter(\.isAgentRunning).map { (session, $0) }
        }
    }

    /// Cleanup candidates: idle agents first (wrap them up before killing),
    /// then windows nothing has touched in days. Oldest first — the most
    /// forgotten window is the most deserving.
    private var tidyItems: [PaletteItem] {
        let all = sessions.flatMap { session in
            session.windows.map { (session: session, window: $0) }
        }
        let idleAgents = all
            .filter { $0.window.isAgentRunning && $0.window.isTidyCandidate }
            .sorted { ($0.window.lastActivity ?? .distantPast) < ($1.window.lastActivity ?? .distantPast) }
        let staleWindows = all
            .filter { !$0.window.isAgentRunning && $0.window.isTidyCandidate }
            .sorted { ($0.window.lastActivity ?? .distantPast) < ($1.window.lastActivity ?? .distantPast) }

        var items: [PaletteItem] = []
        for group in [(title: "Idle agents · ⌘⇧W to wrap up", members: idleAgents),
                      (title: "Stale windows · ⌘K to kill", members: staleWindows)] {
            for (offset, entry) in group.members.enumerated() {
                var item = Self.windowItem(for: entry.window, in: entry.session)
                if offset == 0 {
                    item.sectionTitle = group.title
                }
                items.append(item)
            }
        }
        return items
    }

    /// Header for the actions column.
    var listHeader: String {
        guard mode == .browsing else { return "Actions" }
        switch browseList {
        case .windows: return "Actions"
        case .agents: return "Agents"
        case .tidy: return "Tidy up"
        case .help: return "Keyboard shortcuts"
        }
    }

    /// The window behind the currently selected row, if the selection is a
    /// window — drives the preview pane's header.
    var selectedWindow: TmuxWindow? {
        let items = filteredItems
        guard selectedIndex < items.count,
              case .switchWindow(let sessionName, let windowIndex) = items[selectedIndex].action
        else { return nil }
        return sessions.first { $0.name == sessionName }?
            .windows.first { $0.index == windowIndex }
    }

    /// True when agents mode has nothing actionable to show.
    var isAgentListEmpty: Bool {
        mode == .browsing && browseList == .agents
            && searchText.isEmpty && filteredItems.isEmpty
    }

    /// All sessions ranked for flipping: visited sessions by frecency, then
    /// the rest by last attach time, with the attached session last.
    private var frecentSessionItems: [PaletteItem] {
        let now = Date.now

        func rank(_ session: TmuxSession) -> (tier: Int, value: Double) {
            if session.isAttached {
                (2, 0)
            } else if let score = visitHistory.score(id: session.id, now: now) {
                (0, score)
            } else {
                (1, session.lastAttached?.timeIntervalSince1970 ?? 0)
            }
        }

        return sessions
            .sorted {
                let a = rank($0)
                let b = rank($1)
                return a.tier != b.tier ? a.tier < b.tier : a.value > b.value
            }
            .map { session in
                PaletteItem(
                    title: session.name,
                    subtitle: Self.sessionSubtitle(for: session),
                    icon: "terminal",
                    action: .switchSession(session.name)
                )
            }
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
        // The session is already in the title prefix and the glyph carries
        // agent state, so the subtitle holds process, branch, and recency —
        // narrated for agents ("asked 9m ago") since their timestamps mean
        // something specific — plus what the agent was asked to do, quoted:
        // with several agents in one directory, the task is what tells
        // their otherwise-identical rows apart.
        let recency: String? = {
            guard let askedAt = window.askedAt else { return nil }
            let relative = askedAt.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
            return switch window.agentActivity {
            case .working: "active now"
            case .waitingForInput: "asked \(relative)"
            case .waitingForPermission: "blocked \(relative)"
            case nil: relative
            }
        }()
        let context = window.agentContextTokens.map {
            "\($0.formatted(.number.notation(.compactName))) ctx"
        }
        let details = [
            window.secondaryLabel,
            window.gitBranch,
            recency,
            context,
            window.agentMessage,
            window.agentTask.map { "“\($0)”" }
        ].compactMap(\.self)
        return PaletteItem(
            title: "\(session.name):\(window.index) \(window.displayName)",
            subtitle: details.isEmpty ? nil : details.joined(separator: " · "),
            icon: window.agentGlyph ?? "macwindow",
            iconColor: window.agentGlyphColor,
            isStale: window.isStale,
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

    func takePendingBrowseList() -> BrowseList? {
        defer { pendingBrowseList = nil }
        return pendingBrowseList
    }

    func refresh() {
        isPaletteVisible = true
        startLiveUpdates()
        Task {
            await loadSessions()
        }
    }

    /// Called whenever the palette hides; live reloads pause until the
    /// next show.
    func paletteDidHide() {
        isPaletteVisible = false
    }

    /// Reloads the open palette whenever a beeper hook reports a state
    /// change, so the HUD shows working → waiting flips as they happen
    /// instead of freezing at open time. One long-lived listener for the
    /// view model's lifetime: the change stream is single-consumer and
    /// finishes if its iterating task is cancelled, so it is never torn
    /// down between shows — hiding just makes events no-ops.
    private func startLiveUpdates() {
        guard liveUpdatesTask == nil else { return }
        try? beeperMonitor.start()
        liveUpdatesTask = Task { [weak self] in
            guard let changes = self?.beeperMonitor.changes else { return }
            for await _ in changes {
                // Hooks fire in quick bursts (Stop right after
                // PostToolUse); let them settle before reloading.
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, self.isPaletteVisible else { continue }
                await self.loadSessions(quiet: true)
            }
        }
    }

    /// Loads tmux state into the palette. Quiet loads are the live
    /// refreshes of an already-painted palette: no loading indicator, and
    /// the cursor follows the row it was on — rows re-order as agents
    /// change state, and the selection tracking a *position* would hand
    /// the user's next keystroke to whatever slid underneath it.
    func loadSessions(quiet: Bool = false) async {
        if !quiet { isLoading = true }
        defer { if !quiet { isLoading = false } }
        loadGeneration += 1
        let generation = loadGeneration
        let anchor = quiet ? selectionAnchor() : nil

        do {
            // Fast pass: sessions, windows, branches — two tmux spawns.
            // The palette paints (and MRU-sorts) from this immediately.
            let base = try await tmuxService.listSessions()
            guard generation == loadGeneration else { return }
            sessions = base
            errorMessage = nil
            visitHistory.prune(keeping: Set(base.flatMap(\.windows).map(\.id) + base.map(\.id)))
            if quiet { restoreSelection(toAnchor: anchor) }

            // Slow pass: agent states (beeper first, pane captures as
            // fallback), off the critical path; glyphs appear when
            // classification lands.
            let statuses = await tmuxService.agentActivities(in: base.flatMap(\.windows))
            guard generation == loadGeneration, !statuses.isEmpty else { return }
            sessions = base.map { session in
                var session = session
                session.windows = session.windows.map { window in
                    var window = window
                    let status = statuses[window.id]
                    window.agentActivity = status?.activity
                    window.agentMessage = status?.message
                    window.agentSince = status?.since
                    window.agentPaneId = status?.paneId
                    window.agentTask = status?.task
                    window.agentContextTokens = status?.contextTokens
                    return window
                }
                return session
            }
            if quiet { restoreSelection(toAnchor: anchor) }
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
            sessions = []
        }
    }

    /// Identity of the currently selected row, if it names a session or
    /// window — command rows don't move between reloads and need none.
    private func selectionAnchor() -> String? {
        let items = filteredItems
        guard selectedIndex < items.count else { return nil }
        return Self.anchorKey(for: items[selectedIndex].action)
    }

    /// Puts the cursor back on the anchored row after a live reload, or
    /// clamps it if that row is gone (its agent answered, its window died).
    private func restoreSelection(toAnchor anchor: String?) {
        let items = filteredItems
        let restored = anchor.flatMap { key in
            items.firstIndex { Self.anchorKey(for: $0.action) == key }
        }
        let newIndex = restored ?? min(selectedIndex, max(0, items.count - 1))
        if newIndex != selectedIndex {
            selectedIndex = newIndex  // the view's onChange re-previews
        } else if restored == nil {
            // Same index but possibly a different row now; the preview
            // must not keep playing the old window.
            updatePreview()
        }
    }

    private static func anchorKey(for action: PaletteItem.PaletteAction) -> String? {
        switch action {
        case .switchSession(let name): "session:\(name)"
        case .switchWindow(let sessionName, let windowIndex): "window:\(sessionName):\(windowIndex)"
        default: nil
        }
    }

    /// Resolves stable tmux ids and records the jump against both the
    /// window and its session — window activity is session activity. Ids
    /// survive renames and moves, which "session:index" keys would not.
    private func recordWindowVisit(session: String, windowIndex: Int) {
        guard let session = sessions.first(where: { $0.name == session }) else { return }
        visitHistory.recordVisit(id: session.id)
        if let windowId = session.windows.first(where: { $0.index == windowIndex })?.id {
            visitHistory.recordVisit(id: windowId)
        }
    }

    private func recordSessionVisit(named name: String) {
        guard let id = sessions.first(where: { $0.name == name })?.id else { return }
        visitHistory.recordVisit(id: id)
    }

    /// Streams the selected window's pane into `previewContent`: captures
    /// after a tiny debounce (so rapid arrow-key navigation doesn't spam
    /// tmux), then keeps re-capturing every second while the selection
    /// holds — a working agent's output plays live in the preview. Cancels
    /// any loop from a previous selection.
    func updatePreview() {
        previewTask?.cancel()
        resolveSelectedPullRequest()

        let items = filteredItems
        guard selectedIndex < items.count,
              case .switchWindow(let sessionName, let windowIndex) = items[selectedIndex].action else {
            previewContent = nil
            return
        }

        let target = "\(sessionName):\(windowIndex)"
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let content = try await self.tmuxService.capturePane(target: target)
                    guard !Task.isCancelled else { return }
                    // Only publish real changes so a quiet pane doesn't
                    // re-render every tick.
                    if content.content != self.previewContent?.content
                        || content.cols != self.previewContent?.cols
                        || content.rows != self.previewContent?.rows {
                        self.previewContent = content
                    }
                } catch {
                    self.previewContent = nil
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Stops the live preview loop; called whenever the palette hides.
    func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        pullRequestTask?.cancel()
        pullRequestTask = nil
    }

    /// Looks up the selected window's pull request — lazily, off the
    /// selection change, so no gh call ever runs for rows nobody is
    /// looking at. The service caches per repo-and-branch, making
    /// repeat visits free.
    private func resolveSelectedPullRequest() {
        pullRequestTask?.cancel()
        selectedPullRequest = nil
        guard let window = selectedWindow,
              let directory = window.currentPath,
              let branch = window.gitBranch else { return }
        pullRequestTask = Task { [weak self] in
            guard let self else { return }
            let pullRequest = await self.pullRequests.pullRequest(directory: directory, branch: branch)
            guard !Task.isCancelled, self.selectedWindow?.id == window.id else { return }
            self.selectedPullRequest = pullRequest
        }
    }

    /// Opens the selected window's pull request in the browser. Returns
    /// whether there was one to open, so the caller can dismiss.
    func openSelectedPullRequest() -> Bool {
        guard let pullRequest = selectedPullRequest else { return false }
        NSWorkspace.shared.open(pullRequest.url)
        return true
    }

    /// Flips the empty-query list between windows and the agents overview.
    func toggleBrowseList() {
        guard mode == .browsing, searchText.isEmpty else { return }
        browseList = browseList == .windows ? .agents : .windows
        selectedIndex = 0
        updatePreview()
    }

    /// Plain language rather than "/wrap-up": slash commands are snapshotted
    /// at session start, so sessions older than the command file — exactly
    /// the ones tidy targets — wouldn't recognize it. Text works in every
    /// session, and pointing at the file keeps the meaning versioned there,
    /// project override included, resolved by the agent itself.
    private static let wrapUpInstruction = "Wrap up this session gracefully. Follow the instructions in .claude/commands/wrap-up.md if this project has one, otherwise ~/.claude/commands/wrap-up.md."

    /// Sends the wrap-up instruction to the selected agent's pane. Queues
    /// politely if the agent is mid-turn.
    func wrapUpSelectedAgent() {
        guard let window = selectedWindow, window.isAgentRunning else { return }
        let target = window.agentPaneId ?? "\(window.sessionName):\(window.index)"
        Task {
            do {
                try await tmuxService.sendKeys(target: target, text: Self.wrapUpInstruction)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Kills the selected window. Only honored in the tidy view, where
    /// destruction is the stated purpose.
    func killSelectedWindow() {
        guard browseList == .tidy, let window = selectedWindow else { return }
        Task {
            do {
                try await tmuxService.killWindow(sessionName: window.sessionName, windowIndex: window.index)
                await loadSessions()
                selectedIndex = min(selectedIndex, max(0, filteredItems.count - 1))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Leaves the tidy or help view; returns false if we weren't in one.
    func exitOverlayList() -> Bool {
        guard browseList == .tidy || browseList == .help else { return false }
        browseList = .windows
        selectedIndex = 0
        updatePreview()
        return true
    }

    /// Opens the keymap page.
    func showHelp() {
        guard mode == .browsing else { return }
        browseList = .help
        searchText = ""
        selectedIndex = 0
        updatePreview()
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

            if case .showTidy = item.action {
                browseList = .tidy
                searchText = ""
                selectedIndex = 0
                updatePreview()
                return false
            }

            if case .showHelp = item.action {
                showHelp()
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
            recordSessionVisit(named: sessionName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func switchToWindow(session: String, windowIndex: Int) async {
        do {
            try await tmuxService.switchToWindow(sessionName: session, windowIndex: windowIndex)
            recordWindowVisit(session: session, windowIndex: windowIndex)
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
                recordSessionVisit(named: name)

            case .switchWindow(let session, let windowIndex):
                try await tmuxService.switchToWindow(sessionName: session, windowIndex: windowIndex)
                recordWindowVisit(session: session, windowIndex: windowIndex)

            case .command, .showTidy, .showHelp:
                // Handled before execution or needing more input.
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

        if "tidy up".localizedStandardContains(lowerQuery) {
            items.append(Self.tidyCommandItem)
        }
        if "help keys keyboard shortcuts".localizedStandardContains(lowerQuery) {
            items.append(Self.helpCommandItem)
        }

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

    private static let tidyCommandItem = PaletteItem(
        title: "Tidy up",
        subtitle: "review idle agents and stale windows",
        icon: "wind",
        action: .showTidy
    )

    private static let helpCommandItem = PaletteItem(
        title: "Keyboard shortcuts",
        subtitle: "⌘/",
        icon: "questionmark.circle",
        action: .showHelp
    )

    private func addAllCommands(to items: inout [PaletteItem]) {
        items.append(contentsOf: [
            Self.tidyCommandItem,
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
            ),
            Self.helpCommandItem
        ])
    }
}
