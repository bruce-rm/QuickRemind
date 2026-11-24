import SwiftUI
import EventKit

struct SettingsView: View {
    @Environment(ReminderStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("权限") {
                    HStack {
                        Label("提醒事项", systemImage: "checklist")
                        Spacer()
                        Text(permissionText)
                            .foregroundStyle(.secondary)
                    }
                    Button("重新检查权限") {
                        store.checkAccess()
                        if store.permission == .granted {
                            Task { await store.refresh() }
                        }
                    }
                    if let error = store.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("支持的语法") {
                    SyntaxRow(example: "明天下午三点交报告", meaning: "日期 + 时刻")
                    SyntaxRow(example: "30分钟后吃药", meaning: "相对时长")
                    SyntaxRow(example: "每周一三五 9点健身", meaning: "重复规则")
                    SyntaxRow(example: "下周一 8:30 项目评审", meaning: "下周 + 精确时刻")
                    SyntaxRow(example: "紧急 明天交税", meaning: "高优先级 → 系统「紧急」")
                    SyntaxRow(example: "明天 #工作 对齐需求", meaning: "标签")
                }

                Section("闹钟说明") {
                    Text("普通事项：通过提醒事项的 EKAlarm 到点响铃，并附带 5 分钟预提醒。")
                    Text("紧急事项（含「紧急」关键词）：额外创建一个系统级全屏闹钟，穿透静音与专注模式，首次使用会请求闹钟权限（iOS 26+）。")
                    Text("受 EventKit 限制，**无法**给已有提醒事项打上系统原生的「紧急」标记——只能用高优先级代理。原生紧急需在提醒事项 App 内手动开启。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Section("关于") {
                    Text("速记直接读写系统「提醒事项」，不上传任何数据。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var permissionText: String {
        switch store.permission {
        case .notDetermined: return "未申请"
        case .granted: return "已授权"
        case .denied: return "已拒绝"
        case .restricted: return "受限制"
        }
    }
}

private struct SyntaxRow: View {
    let example: String
    let meaning: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(example)
                .font(.system(.body, design: .monospaced))
            Text(meaning)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
