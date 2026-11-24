import Foundation
import UserNotifications

/// 本地通知兜底闹钟。
/// 系统提醒事项的 EKAlarm 已能响铃；这里的本地通知用于「5 分钟前预提醒」等补充场景，
/// 以及提醒事项权限被限制时的降级方案。
final class AlarmService: NSObject, @unchecked Sendable {

    static let shared = AlarmService()

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// 在到期时间前 minutes 分钟发一条预提醒
    func schedulePreAlert(
        id: String,
        title: String,
        at dueDate: Date,
        minutesBefore: Int = 5
    ) async {
        let fireDate = dueDate.addingTimeInterval(-TimeInterval(minutesBefore * 60))
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "即将到期"
        content.body = title
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: "prealert.\(id)", content: content, trigger: trigger
        )
        try? await center.add(request)
    }

    func cancelPreAlert(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["prealert.\(id)"])
    }

    func pendingCount() async -> Int {
        let requests = await center.pendingNotificationRequests()
        return requests.filter { $0.identifier.hasPrefix("prealert.") }.count
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AlarmService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
