import Foundation

/// How long an ask on the current window can sit unanswered before it
/// banners anyway. Being on the window means the user is probably
/// looking; after a while, probably not. "Never" restores the old
/// behavior: the current window never pings while the terminal is
/// front.
enum NudgeDelay: Int, CaseIterable, Identifiable {
    case never = 0
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .never: "Never"
        case .thirtySeconds: "30 sec"
        case .oneMinute: "1 min"
        case .twoMinutes: "2 min"
        case .fiveMinutes: "5 min"
        }
    }

    var seconds: TimeInterval {
        TimeInterval(rawValue)
    }

    // MARK: - Persistence

    static let defaultsKey = "nudgeDelay"

    static var saved: NudgeDelay {
        (UserDefaults.standard.object(forKey: defaultsKey) as? Int)
            .flatMap(NudgeDelay.init) ?? .oneMinute
    }
}
