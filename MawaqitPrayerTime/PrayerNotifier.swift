import Foundation
import UserNotifications

struct PrayerAlert: Sendable {
    let id: String
    let date: Date
    let title: String
    let body: String
}

/// Schedules the system notifications for upcoming prayers.
final class PrayerNotifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    /// Replaces every pending prayer notification with `alerts`.
    func replacePending(with alerts: [PrayerAlert]) async {
        center.removeAllPendingNotificationRequests()
        for alert in alerts {
            guard !Task.isCancelled else { return }
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: alert.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger))
        }
        // A cancelled earlier run may have slipped one request in after the reset above.
        guard !Task.isCancelled else { return }
        let wanted = Set(alerts.map(\.id))
        let stale = await center.pendingNotificationRequests().map(\.identifier).filter { !wanted.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
    }

    /// Show the banner even while the prayer panel is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
