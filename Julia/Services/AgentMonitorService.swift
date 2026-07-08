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
    /// When the user last looked at each window, keyed by window id.
    private var seenAt: [String: Date] = [:]
    /// The ask each window was last notified about, to notify once per ask.
    private var notifiedAskAt: [String: Date] = [:]
    /// Fallback cadence for sessions not reporting through beeper hooks;
    /// hook-reporting sessions update the instant their state changes.
    private static let scanInterval: Duration = .seconds(30)

    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scan()
                try? await Task.sleep(for: Self.scanInterval)
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
        beeperMonitor.stop()
    }

    /// Switches to the unseen agent that has been waiting longest and marks
    /// it seen — the badge decrements immediately, and the next press
    /// naturally moves to the next one in the queue.
    func jumpToLongestWaiting() {
        guard let target = waitingWindows.first(where: { !$0.isCurrent }) ?? waitingWindows.first
        else { return }

        seenAt[target.id] = .now
        waitingWindows.removeAll { $0.id == target.id }

        Task {
            try? await tmuxService.switchToWindow(
                sessionName: target.sessionName,
                windowIndex: target.index
            )
        }
    }

    private func scan() async {
        guard let sessions = try? await tmuxService.listSessions() else {
            waitingWindows = []
            return
        }
        let windows = sessions.flatMap(\.windows)

        // Being on a window counts as seeing whatever it was asking.
        for window in windows where window.isCurrent {
            seenAt[window.id] = .now
        }
        seenAt = seenAt.filter { key, _ in windows.contains { $0.id == key } }

        let statuses = await tmuxService.agentActivities(in: windows)
        waitingWindows = windows
            .compactMap { window -> TmuxWindow? in
                guard let status = statuses[window.id], status.activity != .working else { return nil }
                var window = window
                window.agentActivity = status.activity
                window.agentMessage = status.message
                window.agentSince = status.since
                window.agentTask = status.task
                // Day-old prompts are idle, not waiting; don't badge them.
                guard window.isAwaitingUser else { return nil }
                // Already seen since it asked — the user knows. Windows
                // without beeper's exact timestamps use pane activity as
                // the ask time, and merely visiting one makes Claude
                // redraw — output that lands right after the seen mark and
                // masquerades as a fresh ask. Grant those a grace period.
                let asked = window.askedAt ?? .distantPast
                let seen = seenAt[window.id] ?? .distantPast
                let graceAfterSeen: TimeInterval = window.agentSince == nil ? 90 : 0
                guard asked > seen.addingTimeInterval(graceAfterSeen) else { return nil }
                return window
            }
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

        if mode != .off {
            for window in waitingWindows {
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

        let stillWaiting = Set(waitingWindows.map(\.id))
        let resolved = notifiedAskAt.keys.filter { !stillWaiting.contains($0) }
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
            seenAt[target.id] = .now
            waitingWindows.removeAll { $0.id == target.id }
        }
        Task {
            try? await tmuxService.switchToWindow(
                sessionName: sessionName,
                windowIndex: windowIndex
            )
        }
    }
}
