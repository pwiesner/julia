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

    private let tmuxService = TmuxService()
    private var monitorTask: Task<Void, Never>?
    /// When the user last looked at each window, keyed by window id.
    private var seenAt: [String: Date] = [:]
    private static let scanInterval: Duration = .seconds(30)

    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scan()
                try? await Task.sleep(for: Self.scanInterval)
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
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

        let activities = await tmuxService.agentActivities(in: windows)
        waitingWindows = windows
            .compactMap { window -> TmuxWindow? in
                guard activities[window.id] == .waitingForInput else { return nil }
                var window = window
                window.agentActivity = .waitingForInput
                // Day-old prompts are idle, not waiting; don't badge them.
                guard window.isAwaitingUser else { return nil }
                // Already seen since it asked — the user knows.
                let asked = window.lastActivity ?? .distantPast
                guard asked > (seenAt[window.id] ?? .distantPast) else { return nil }
                return window
            }
            .sorted { ($0.lastActivity ?? .distantPast) < ($1.lastActivity ?? .distantPast) }
    }
}
