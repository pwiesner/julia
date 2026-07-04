import AppKit
import UserNotifications

/// Posts "an agent needs you" notifications and routes clicks back to the
/// window that asked.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    /// Invoked when the user clicks a notification.
    var onJump: ((_ sessionName: String, _ windowIndex: Int) -> Void)?

    func activate() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    func notify(windowId: String, title: String, body: String, sessionName: String, windowIndex: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["sessionName": sessionName, "windowIndex": windowIndex]
        // The window id as identifier: a newer ask from the same window
        // replaces the stale banner instead of stacking.
        let request = UNNotificationRequest(identifier: windowId, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Clears delivered notifications for windows that no longer need
    /// attention (answered, or seen another way).
    func withdraw(windowIds: [String]) {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: windowIds)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let sessionName = userInfo["sessionName"] as? String
        let windowIndex = userInfo["windowIndex"] as? Int
        // The jump is fire-and-forget; the system doesn't need to wait on it.
        completionHandler()
        Task { @MainActor in
            if let sessionName, let windowIndex {
                self.onJump?(sessionName, windowIndex)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(.banner)
    }
}
