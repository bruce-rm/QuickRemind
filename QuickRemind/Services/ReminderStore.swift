import Foundation
import EventKit
import Observation

/// 系统提醒事项读写服务。所有变更直接落到用户 iCloud / 本地提醒事项数据库。
@MainActor
@Observable
final class ReminderStore {

    enum PermissionState: Equatable {
        case notDetermined
        case granted
        case denied
        case restricted
    }

    var permission: PermissionState = .notDetermined
    var reminders: [EKReminder] = []
    var calendars: [EKCalendar] = []
    var errorMessage: String?
    var isLoading = false

    private let store = EKEventStore()

    // MARK: - 权限

    func requestAccess() async {
        do {
            if #available(iOS 17.0, *) {
                let granted = try await store.requestFullAccessToReminders()
                permission = granted ? .granted : .denied
            } else {
                let granted = try await store.requestAccess(to: .reminder)
                permission = granted ? .granted : .denied
            }
            if permission == .granted {
                await refresh()
            }
        } catch {
            permission = .denied
            errorMessage = error.localizedDescription
        }
    }

    func checkAccess() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(iOS 17.0, *) {
            switch status {
            case .notDetermined: permission = .notDetermined
            case .fullAccess, .writeOnly: permission = .granted
            case .denied: permission = .denied
            case .restricted: permission = .restricted
            @unknown default: permission = .denied
            }
        } else {
            switch status {
            case .notDetermined: permission = .notDetermined
            case .authorized: permission = .granted
            case .denied: permission = .denied
            case .restricted: permission = .restricted
            @unknown default: permission = .denied
            }
        }
    }

    // MARK: - 读取

    func refresh() async {
        guard permission == .granted else { return }
        isLoading = true
        defer { isLoading = false }

        calendars = store.calendars(for: .reminder)

        let incomplete = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        let fetched = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: incomplete) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }

        reminders = fetched.sorted { lhs, rhs in
            switch (lhs.dueDateComponents, rhs.dueDateComponents) {
            case (nil, nil): return lhs.title < rhs.title
            case (nil, _): return false
            case (_, nil): return true
            case let (l?, r?):
                let ld = Calendar.current.date(from: l) ?? .distantFuture
                let rd = Calendar.current.date(from: r) ?? .distantFuture
                return ld < rd
            }
        }
    }

    /// 高优先级（= 系统"紧急"筛选可命中）的未完成事项
    var urgentReminders: [EKReminder] {
        reminders.filter { $0.priority == 1 && !$0.isCompleted }
    }

    var todayReminders: [EKReminder] {
        reminders.filter { reminder in
            guard let comps = reminder.dueDateComponents,
                  let date = Calendar.current.date(from: comps) else { return false }
            return Calendar.current.isDateInToday(date) && !reminder.isCompleted
        }
    }

    // MARK: - 写入

    /// 根据解析结果创建系统提醒事项
    @discardableResult
    func createReminder(from result: ParseResult, list: EKCalendar? = nil) throws -> EKReminder {
        guard permission == .granted else {
            throw StoreError.notAuthorized
        }
        guard let targetCalendar = list ?? defaultCalendar() else {
            throw StoreError.noCalendar
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = result.title
        reminder.calendar = targetCalendar
        reminder.priority = result.priority // 1 = 高，系统"紧急"智能列表可筛选

        var notes: [String] = []
        if !result.originalText.isEmpty {
            notes.append("原始输入：\(result.originalText)")
        }
        if !result.tags.isEmpty {
            notes.append("标签：\(result.tags.map { "#\($0)" }.joined(separator: " "))")
        }
        if !notes.isEmpty {
            reminder.notes = notes.joined(separator: "\n")
        }

        if let due = result.dueDate {
            let calendar = Calendar.current
            reminder.dueDateComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
            // 关键：EventKit 必须显式挂 EKAlarm 才会到点响铃
            reminder.alarms = [EKAlarm(absoluteDate: due)]
        }

        if let recurrence = result.recurrence {
            let rule = makeRecurrenceRule(recurrence)
            reminder.addRecurrenceRule(rule)
        }

        try store.save(reminder, commit: true)
        return reminder
    }

    /// 把已有事项切到"紧急"（高优先级）
    func markUrgent(_ reminder: EKReminder) throws {
        reminder.priority = 1
        try store.save(reminder, commit: true)
    }

    func toggleComplete(_ reminder: EKReminder) throws {
        reminder.isCompleted.toggle()
        try store.save(reminder, commit: true)
    }

    func delete(_ reminder: EKReminder) throws {
        try store.remove(reminder, commit: true)
    }

    // MARK: - 私有

    private func defaultCalendar() -> EKCalendar? {
        if let cal = store.defaultCalendarForNewReminders() {
            return cal
        }
        return calendars.first ?? store.calendars(for: .reminder).first
    }

    private func makeRecurrenceRule(_ spec: RecurrenceSpec) -> EKRecurrenceRule {
        let weekdays: [EKRecurrenceDayOfWeek]? = spec.frequency == .weekly
            ? spec.weekdays.map { EKRecurrenceDayOfWeek(EKWeekday(rawValue: $0)!) }
            : nil
        return EKRecurrenceRule(
            recurrenceWith: ekFrequency(spec.frequency),
            interval: spec.interval,
            daysOfTheWeek: weekdays,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
    }

    private func ekFrequency(_ f: RecurrenceSpec.Frequency) -> EKRecurrenceFrequency {
        switch f {
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        case .yearly: return .yearly
        }
    }

    enum StoreError: LocalizedError {
        case notAuthorized
        case noCalendar
        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "未获得提醒事项访问权限，请在系统设置中开启。"
            case .noCalendar:
                return "找不到可用的提醒事项清单，请先在「提醒事项」App 中创建一个清单。"
            }
        }
    }
}
