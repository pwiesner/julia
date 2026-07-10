import Foundation

/// Remembers when the user last looked at each waiting agent window, so
/// unread semantics survive julia restarts. The ledger used to live in
/// memory only, and every relaunch resurrected the badge for anything
/// still waiting — asks the user had already seen and dealt with.
@MainActor
final class SeenLedgerService {
    private static let defaultsKey = "seenLedger.v1"

    /// Re-marking the current window happens on every scan; skip the
    /// disk write when the recorded time is already this fresh. Grace
    /// comparisons tolerate the staleness — they operate in minutes.
    private static let rewriteThreshold: TimeInterval = 15

    /// When the user last looked at each window, keyed by tmux window id.
    private var seenAt: [String: Date]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            seenAt = decoded
        } else {
            seenAt = [:]
        }
    }

    subscript(id: String) -> Date? {
        seenAt[id]
    }

    func markSeen(_ id: String) {
        if let existing = seenAt[id], Date.now.timeIntervalSince(existing) < Self.rewriteThreshold {
            return
        }
        seenAt[id] = .now
        save()
    }

    /// Window ids reset when the tmux server restarts; drop the departed.
    func prune(keeping ids: Set<String>) {
        let pruned = seenAt.filter { ids.contains($0.key) }
        if pruned.count != seenAt.count {
            seenAt = pruned
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(seenAt) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
