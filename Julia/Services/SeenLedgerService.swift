import Foundation

/// Remembers when the user last looked at each waiting agent window, so
/// unread semantics survive julia restarts. The ledger used to live in
/// memory only, and every relaunch resurrected the badge for anything
/// still waiting — asks the user had already seen and dealt with.
@MainActor
final class SeenLedgerService {
    private static let defaultsKey = "seenLedger.v1"

    /// Re-marking the current window happens on every scan; skip the
    /// disk write when the saved time is already this fresh. Only the
    /// write is throttled — the in-memory mark must stay exact, because
    /// beeper-backed waiting filters compare it against sub-second ask
    /// times. A crash loses at most this much freshness.
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
        let existing = seenAt[id]
        seenAt[id] = .now
        if let existing, Date.now.timeIntervalSince(existing) < Self.rewriteThreshold {
            return
        }
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
