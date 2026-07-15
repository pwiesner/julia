import AppKit
import BeeperKit
import Foundation
import Observation

/// Watches agent state in the background so julia can signal without being
/// asked: the menu bar badge shows how many Claudes are waiting unseen,
/// and the jump hotkey walks through them.
///
/// "Waiting" alone would badge forever — a Claude at rest is always at a
/// prompt, and visiting it doesn't change that. The badge therefore uses
/// unread semantics: an agent counts until the user has *looked* at it
/// (jumped there, or had it as the current window) since it last asked.
@MainActor
@Observable
final class AgentMonitorService {
    /// Waiting agent windows the user hasn't seen yet, longest wait first.
    private(set) var waitingWindows: [TmuxWindow] = []

    var waitingCount: Int { waitingWindows.count }

    /// Set by the app so waits can become system notifications.
    var notifications: NotificationService?

    private let tmuxService = TmuxService()
    private let beeperMonitor = BeeperMonitor()
    private var monitorTask: Task<Void, Never>?
    private var beeperTask: Task<Void, Never>?
    private var appSwitchTask: Task<Void, Never>?
    /// When the user last looked at each window; disk-backed so a julia
    /// restart doesn't resurrect the badge for already-seen asks.
    private let seenLedger = SeenLedgerService()
    /// The ask each window was last notified about, to notify once per ask.
    private var notifiedAskAt: [String: Date] = [:]
    /// True while the palette is on screen. Banners hold while it's up —
    /// the palette already narrates state flips in front of the user, so
    /// a banner on top is pure interruption. An ask still waiting when
    /// the palette hides banners then: closing without acting is the
    /// "walked away" case the banner exists for.
    private var isPaletteVisible = false
    /// Asks on the current window that have gone unanswered past the
    /// nudge delay. Not part of waitingWindows — the user is on them, so
    /// they don't badge or list — but they do banner: front and center
    /// isn't always looked at.
    private var overdueCurrentAsks: [TmuxWindow] = []
    /// Fallback cadence for sessions not reporting through beeper hooks;
    /// hook-reporting sessions update the instant their state changes.
    private static let scanInterval: Duration = .seconds(30)
    /// How long an ask on the current window can sit unanswered before
    /// it banners anyway.
    private static let currentWindowNudgeDelay: TimeInterval = 60

    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scan()
                try? await Task.sleep(for: Self.scanInterval)
            }
        }

        // Waiting semantics depend on which app is front (a current
        // window behind Chrome notifies; in front it defers), so app
        // switches rescan right away instead of riding the 30s tick.
        appSwitchTask = Task { [weak self] in
            let activations = NSWorkspace.shared.notificationCenter
                .notifications(named: NSWorkspace.didActivateApplicationNotification)
            for await _ in activations {
                await self?.scan()
            }
        }

        try? beeperMonitor.start()
        beeperTask = Task { [weak self] in
            guard let changes = self?.beeperMonitor.changes else { return }
            for await _ in changes {
                // Hooks fire in quick bursts (Stop right after PostToolUse);
                // let them settle before rescanning.
                try? await Task.sleep(for: .milliseconds(200))
                await self?.scan()
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        beeperTask?.cancel()
        beeperTask = nil
        appSwitchTask?.cancel()
        appSwitchTask = nil
        beeperMonitor.stop()
    }

    func paletteDidShow() {
        isPaletteVisible = true
    }

    /// Releases held banners by rescanning rather than posting from the
    /// current state: a jump from the palette makes its target the
    /// current window, but until a scan runs the target still sits in
    /// waitingWindows — posting directly would banner the very agent the
    /// user just went to. The settle delay lets the tmux switch land
    /// before the scan reads who is current.
    func paletteDidHide() {
        isPaletteVisible = false
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            await self?.scan()
        }
    }

    /// Switches to the unseen agent that has been waiting longest and marks
    /// it seen — the badge decrements immediately, and the next press
    /// naturally moves to the next one in the queue.
    func jumpToLongestWaiting() {
        guard let target = waitingWindows.first(where: { !$0.isCurrent }) ?? waitingWindows.first
        else { return }

        seenLedger.markSeen(target.id)
        waitingWindows.removeAll { $0.id == target.id }

        Task {
            try? await tmuxService.switchToWindow(
                sessionName: target.sessionName,
                windowIndex: target.index
            )
            await raiseTerminal()
        }
    }

    /// Brings the terminal hosting the tmux client forward. A jump the
    /// user can't see isn't a jump: the tmux switch lands behind
    /// whatever app is frontmost unless the terminal comes with it.
    private func raiseTerminal() async {
        guard let clientPid = await tmuxService.attachedClientPid() else { return }
        TerminalFocusService.activateTerminal(hostingClientPid: clientPid)
    }

    private func scan() async {
        guard let sessions = try? await tmuxService.listSessions() else {
            waitingWindows = []
            return
        }
        let windows = sessions.flatMap(\.windows)
        let statuses = await tmuxService.agentActivities(in: windows)
        let clientPid = await tmuxService.attachedClientPid()
        let terminalFrontmost = clientPid
            .map(TerminalFocusService.isTerminalFrontmost(hostingClientPid:)) ?? false

        // Being on a window counts as seeing it only while the terminal
        // is actually front — behind another app, "current" means
        // nothing is being seen. A live ask never marks seen either:
        // it's answered or it keeps counting.
        for window in windows where window.isCurrent {
            let hasLiveAsk = statuses[window.id].map { $0.activity != .working } ?? false
            if terminalFrontmost && !hasLiveAsk {
                seenLedger.markSeen(window.id)
            }
        }
        seenLedger.prune(keeping: Set(windows.map(\.id)))
        var waiting: [TmuxWindow] = []
        var overdue: [TmuxWindow] = []
        for var window in windows {
            guard let status = statuses[window.id], status.activity != .working else { continue }
            window.agentActivity = status.activity
            window.agentMessage = status.message
            window.agentSince = status.since
            window.agentTask = status.task
            // Day-old prompts are idle, not waiting; don't badge them.
            guard window.isAwaitingUser else { continue }
            let asked = window.askedAt ?? .distantPast

            if window.isCurrent && terminalFrontmost {
                // The user is watching the ask happen — no banner, no
                // badge. But watching isn't always looking: an ask still
                // unanswered after the nudge delay banners anyway.
                // Beeper-exact ask times only — a scraped ask time is
                // pane activity, which stray output keeps perpetually
                // young. With the terminal behind another app, "current"
                // earns no deferral: fall through and notify like any
                // other window.
                if window.agentSince != nil,
                   Date.now.timeIntervalSince(asked) >= Self.currentWindowNudgeDelay {
                    overdue.append(window)
                }
                continue
            }

            // Already seen since it asked — the user knows. Windows
            // without beeper's exact timestamps use pane activity as
            // the ask time, and merely visiting one makes Claude
            // redraw — output that lands right after the seen mark and
            // masquerades as a fresh ask. Grant those a grace period.
            let seen = seenLedger[window.id] ?? .distantPast
            let graceAfterSeen: TimeInterval = window.agentSince == nil ? 90 : 0
            guard asked > seen.addingTimeInterval(graceAfterSeen) else { continue }
            waiting.append(window)
        }
        overdueCurrentAsks = overdue
        waitingWindows = waiting
            .sorted { a, b in
                // Urgency tiers: permission blocks a running task, a real
                // ask blocks a decision, a finished reply just waits.
                func tier(_ window: TmuxWindow) -> Int {
                    if window.agentActivity == .waitingForPermission { return 0 }
                    return window.isUnreadReply ? 2 : 1
                }
                let tierA = tier(a)
                let tierB = tier(b)
                if tierA != tierB { return tierA < tierB }
                return (a.askedAt ?? .distantPast) < (b.askedAt ?? .distantPast)
            }

        postNotifications()
    }

    /// One notification per ask, honoring the user's notification mode;
    /// answered or seen windows get their banners withdrawn.
    private func postNotifications() {
        guard let notifications else { return }
        let mode = NotificationMode.saved

        if mode != .off && !isPaletteVisible {
            for window in waitingWindows + overdueCurrentAsks {
                if mode == .permissionRequests && window.agentActivity != .waitingForPermission {
                    continue
                }
                let asked = window.askedAt ?? .distantPast
                guard notifiedAskAt[window.id] != asked else { continue }
                notifiedAskAt[window.id] = asked

                let fallback = window.agentActivity == .waitingForPermission
                    ? "Needs permission to run a tool"
                    : "Finished — ready for you"
                notifications.notify(
                    windowId: window.id,
                    title: window.displayTitle,
                    body: window.agentMessage ?? fallback,
                    sessionName: window.sessionName,
                    windowIndex: window.index
                )
            }
        }

        // Overdue current-window asks count as live: withdrawing a nudge
        // the moment the next scan runs would retract it unanswered.
        let stillLive = Set((waitingWindows + overdueCurrentAsks).map(\.id))
        let resolved = notifiedAskAt.keys.filter { !stillLive.contains($0) }
        if !resolved.isEmpty {
            notifications.withdraw(windowIds: resolved)
            for id in resolved {
                notifiedAskAt[id] = nil
            }
        }
    }

    /// Switches to a specific window, e.g. from a clicked notification or
    /// the menu bar's waiting list, with the same badge semantics as the
    /// jump hotkey: going there is seeing it.
    func jump(toSession sessionName: String, windowIndex: Int) {
        if let target = waitingWindows.first(where: {
            $0.sessionName == sessionName && $0.index == windowIndex
        }) {
            seenLedger.markSeen(target.id)
            waitingWindows.removeAll { $0.id == target.id }
        }
        Task {
            try? await tmuxService.switchToWindow(
                sessionName: sessionName,
                windowIndex: windowIndex
            )
            await raiseTerminal()
        }
    }
}
