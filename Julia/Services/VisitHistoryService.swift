import Foundation

/// Remembers when the user jumped to each tmux window or session so the
/// palette can order by frecency — recent visits weigh most, but a window
/// visited constantly all day outranks one visited once an hour ago. Only
/// jumps made through Julia are seen; native tmux switches don't update
/// the history.
@MainActor
final class VisitHistoryService {
    private static let defaultsKey = "visitHistory.v2"
    private static let legacyKey = "windowVisitHistory"
    private static let maxVisitsPerItem = 20
    /// A visit's contribution to the frecency score halves every 24 hours.
    private static let halfLife: TimeInterval = 24 * 60 * 60

    /// Visit timestamps keyed by tmux id. Window ids ("@5") and session
    /// ids ("$3") share the dictionary; tmux keeps the namespaces distinct.
    private var visits: [String: [Date]]

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: [Date]].self, from: data) {
            visits = decoded
        } else if let data = defaults.data(forKey: Self.legacyKey),
                  let legacy = try? JSONDecoder().decode([String: Date].self, from: data) {
            // Pre-frecency format stored only the latest visit.
            visits = legacy.mapValues { [$0] }
        } else {
            visits = [:]
        }
    }

    func recordVisit(id: String) {
        var dates = visits[id, default: []]
        dates.append(.now)
        if dates.count > Self.maxVisitsPerItem {
            dates.removeFirst(dates.count - Self.maxVisitsPerItem)
        }
        visits[id] = dates
        save()
    }

    /// Exponentially decayed visit count; nil if never visited.
    func score(id: String, now: Date = .now) -> Double? {
        guard let dates = visits[id], !dates.isEmpty else { return nil }
        return dates.reduce(0) { total, date in
            total + pow(2, -now.timeIntervalSince(date) / Self.halfLife)
        }
    }

    /// Ids reset when the tmux server restarts; drop entries for windows
    /// and sessions that no longer exist.
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
