import Foundation
import SwiftUI

// AlarmKit 从 iOS 26 起对所有开发者开放，不需要向苹果申请特殊 entitlement。
// 唯一前提：Info.plist 里的 NSAlarmKitUsageDescription（项目已配置）+ 运行时用户授权。
//
// 用 canImport 保护：Xcode 25 及更早版本没有 AlarmKit SDK，仍能编译本 App，
// 只是不启用全屏闹钟，自动回退到 EKAlarm + 本地通知。

#if canImport(AlarmKit) && compiler(>=6.0)
import AlarmKit
import AppIntents

/// 全屏闹钟上的「停止」按钮动作
@available(iOS 26.0, *)
struct StopQuickRemindAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "停止闹钟"

    @Parameter(title: "闹钟 ID") var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        try? await AlarmKitService.shared.stopAlarm(id: id)
        return .result()
    }
}

/// 全屏闹钟上的「稍后提醒」按钮动作
@available(iOS 26.0, *)
struct SnoozeQuickRemindAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "稍后提醒"

    @Parameter(title: "闹钟 ID") var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        await AlarmKitService.shared.snoozeAlarm(id: id)
        return .result()
    }
}

/// 随 Live Activity 序列化的轻量元数据
@available(iOS 26.0, *)
struct QuickRemindAlarmMetadata: AlarmMetadata {}

@available(iOS 26.0, *)
@MainActor
final class AlarmKitService {

    static let shared = AlarmKitService()

    private let manager = AlarmManager.shared

    enum AlarmError: LocalizedError {
        case denied
        case unavailable
        case limitReached

        var errorDescription: String? {
            switch self {
            case .denied: return "闹钟权限被拒绝，请在「设置 → 速记」中开启闹钟权限。"
            case .unavailable: return "全屏闹钟需要 iOS 26 或更高版本。"
            case .limitReached: return "系统闹钟数量已达上限。"
            }
        }
    }

    /// 请求闹钟权限。首次创建闹钟时系统会自动弹窗，这里也可手动调用。
    func ensureAuthorized() async throws {
        switch manager.authorizationState {
        case .authorized:
            return
        case .denied:
            throw AlarmError.denied
        case .notDetermined:
            let state = try await manager.requestAuthorization()
            guard state == .authorized else { throw AlarmError.denied }
        @unknown default:
            throw AlarmError.unavailable
        }
    }

    /// 安排一个系统级全屏闹钟：穿透静音与专注模式，显示在锁屏 / 灵动岛 / Apple Watch。
    @discardableResult
    func scheduleAlarm(id: UUID, title: String, at date: Date) async throws -> UUID {
        try await ensureAuthorized()

        let snoozeButton = AlarmButton(
            text: "稍后提醒",
            textColor: .white,
            systemImageName: "bell.slash"
        )
        let alert = AlarmPresentation.Alert(
            title: title,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .countdown
        )
        let presentation = AlarmPresentation(alert: alert)
        let attributes = AlarmAttributes<QuickRemindAlarmMetadata>(
            presentation: presentation,
            metadata: QuickRemindAlarmMetadata(),
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: StopQuickRemindAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: SnoozeQuickRemindAlarmIntent(alarmID: id.uuidString),
            sound: .default
        )
        try await manager.schedule(id: id, configuration: configuration)
        return id
    }

    func stopAlarm(id: UUID) async throws {
        try await manager.stop(id: id)
    }

    /// 稍后提醒：从响铃状态重新开始倒计时
    func snoozeAlarm(id: UUID) async {
        await manager.countdown(id: id)
    }

    func cancelAlarm(id: UUID) async {
        await manager.cancel(id: id)
    }

    func listAlarms() -> [Alarm] {
        manager.alarms
    }
}
#endif
