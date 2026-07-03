import Foundation

/// Remembers when the user last jumped to each tmux window so the palette
/// can order windows by working set (visit recency) rather than
/// session/index order. Only jumps made through Julia are seen; switches
/// done with native tmux bindings don't update the history.
@MainActor
final class VisitHistoryService {
    private static let defaultsKey = "windowVisitHistory"
    private var visits: [String: Date]

    init() {
        let data = UserDefaults.standard.data(forKey: Self.defaultsKey)
        visits = data.flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
    }

    func recordVisit(windowId: String) {
        visits[windowId] = .now
        save()
    }

    func lastVisit(windowId: String) -> Date? {
        visits[windowId]
    }

    /// Window ids reset when the tmux server restarts; drop entries for
    /// windows that no longer exist.
    func prune(keeping ids: Set<String>) {
        let pruned = visits.filter { ids.contains($0.key) }
        if pruned.count != visits.count {
            visits = pruned
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(visits) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
