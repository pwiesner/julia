import Foundation

/// How chatty agent notifications should be. With a fleet of Claudes,
/// "every wait" can overwhelm; permission requests are the ones that
/// block a running task.
enum NotificationMode: String, CaseIterable, Identifiable {
    case off
    case permissionRequests = "permission"
    case allWaits = "all"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .permissionRequests: "Permission requests"
        case .allWaits: "All waits"
        }
    }

    // MARK: - Persistence

    static let defaultsKey = "notificationMode"

    static var saved: NotificationMode {
        UserDefaults.standard.string(forKey: defaultsKey)
            .flatMap(NotificationMode.init) ?? .permissionRequests
    }
}
