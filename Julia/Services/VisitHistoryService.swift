import Foundation

/// Remembers when the user jumped to each tmux window or session so the
/// palette can order by frecency — recent visits weigh most, but a window
/// visited constantly all day outranks one visited once an hour ago.
/// Fed from two sides: julia's own jumps directly, and native tmux
/// switches via VisitIngestService's hook log.
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

    /// Wall-clock of the latest record per id, for hook-echo detection —
    /// julia's own jumps also fire the tmux hooks, and the ingest side
    /// must be able to tell "julia just recorded this" from a native
    /// switch.
    private var lastRecordedAt: [String: Date] = [:]

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

    func recordVisit(id: String, at date: Date = .now) {
        var dates = visits[id, default: []]
        dates.append(date)
        if dates.count > Self.maxVisitsPerItem {
            dates.removeFirst(dates.count - Self.maxVisitsPerItem)
        }
        visits[id] = dates
        lastRecordedAt[id] = .now
        save()
    }

    /// True if a visit to this id was recorded within the interval —
    /// measured in wall-clock, since it exists to catch hook echoes of
    /// records that just happened.
    func recordedRecently(id: String, within interval: TimeInterval) -> Bool {
        guard let recorded = lastRecordedAt[id] else { return false }
        return Date.now.timeIntervalSince(recorded) < interval
    }

    /// Recency term: how fresh the newest visit is. Decays four times
    /// faster than the frequency term and outweighs it by three orders of
    /// magnitude, so the window you were last in is the top row and the
    /// working set orders itself underneath by how hard you lean on it.
    /// Only visits within minutes of each other land close enough on this
    /// curve for frequency to decide between them — which is exactly the
    /// pair you are ping-ponging through.
    private static let recencyHalfLife: TimeInterval = 6 * 60 * 60
    private static let recencyWeight: Double = 1000

    /// Windows julia has never watched you visit are ranked by tmux's own
    /// activity clock on the same curve, discounted: output is not intent.
    /// An agent printing tokens should place below a window you actually
    /// chose today, but above one you opened a fortnight ago and forgot.
    private static let activityDiscount: Double = 0.25

    private static func decay(_ age: TimeInterval, halfLife: TimeInterval) -> Double {
        pow(2, -age / halfLife)
    }

    /// Recency-dominant frecency; nil if never visited. Deliberately not a
    /// plain decayed count: summed frequency alone let a window with a
    /// fortnight of accumulated history sit above the one you left ten
    /// seconds ago, which is the opposite of what the top row is for.
    func score(id: String, now: Date = .now) -> Double? {
        guard let dates = visits[id], let newest = dates.max() else { return nil }
        let frequency = dates.reduce(0.0) { total, date in
            total + Self.decay(now.timeIntervalSince(date), halfLife: Self.halfLife)
        }
        let recency = Self.decay(now.timeIntervalSince(newest), halfLife: Self.recencyHalfLife)
        return Self.recencyWeight * recency + frequency
    }

    /// Where a never-visited window or session sits on the same curve, so
    /// the two populations can be ranked together instead of in tiers. The
    /// old tier split asked only *whether* a visit existed, so a single
    /// visit from weeks ago — decayed to a millionth of a point, but not
    /// nil — outranked every window in live use.
    static func activityScore(at lastActivity: Date?, now: Date = .now) -> Double {
        guard let lastActivity else { return 0 }
        let age = now.timeIntervalSince(lastActivity)
        let recency = decay(age, halfLife: recencyHalfLife)
        return activityDiscount * (recencyWeight * recency + decay(age, halfLife: halfLife))
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
