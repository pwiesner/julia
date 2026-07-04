import Foundation
import Observation

/// Watches agent state in the background so julia can signal without being
/// asked: the menu bar badge shows how many Claudes are waiting, and the
/// jump hotkey goes straight to the one that has waited longest.
@MainActor
@Observable
final class AgentMonitorService {
    /// Freshly-waiting agent windows, longest wait first.
    private(set) var waitingWindows: [TmuxWindow] = []

    var waitingCount: Int { waitingWindows.count }

    private let tmuxService = TmuxService()
    private var monitorTask: Task<Void, Never>?
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

    /// Switches to the agent that has been waiting on the user longest.
    /// No-op when nothing is waiting.
    func jumpToLongestWaiting() {
        guard let target = waitingWindows.first else { return }
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
        let activities = await tmuxService.agentActivities(in: windows)
        waitingWindows = windows
            .compactMap { window -> TmuxWindow? in
                guard activities[window.id] == .waitingForInput else { return nil }
                var window = window
                window.agentActivity = .waitingForInput
                // Day-old prompts are idle, not waiting; don't badge them.
                return window.isAwaitingUser ? window : nil
            }
            .sorted { ($0.lastActivity ?? .distantPast) < ($1.lastActivity ?? .distantPast) }
    }
}
