import SwiftUI
import EventKit

struct ContentView: View {
    @Environment(ReminderStore.self) private var store

    @State private var inputText = ""
    @State private var parseResult: ParseResult?
    @State private var selectedList: EKCalendar?
    @State private var showSettings = false
    @State private var filter: Filter = .all
    @State private var toast: String?
    @FocusState private var inputFocused: Bool

    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case urgent = "紧急"
        case today = "今天"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                composeBar
                Divider()

                if store.permission == .denied || store.permission == .restricted {
                    permissionView
                } else {
                    filterBar
                    reminderList
                }
            }
            .navigationTitle("速记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.snappy, value: toast)
                }
            }
            .task {
                if store.permission == .granted {
                    await store.refresh()
                    selectedList = store.calendars.first
                }
            }
        }
    }

    // MARK: - 输入区

    private var composeBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)

                TextField("明天下午三点交报告", text: $inputText)
                    .focused($inputFocused)
                    .submitLabel(.done)
                    .onChange(of: inputText) { _, newValue in
                        parseResult = newValue.isEmpty
                            ? nil
                            : NaturalLanguageParser.parse(newValue)
                    }
                    .onSubmit { Task { await addReminder() } }

                if !inputText.isEmpty {
                    Button {
                        inputText = ""
                        parseResult = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))

            if let result = parseResult {
                ParsePreview(result: result, selectedList: $selectedList, calendars: store.calendars)
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - 筛选

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(Filter.allCases) { f in
                Button {
                    filter = f
                } label: {
                    HStack(spacing: 4) {
                        Text(f.rawValue)
                        if f == .urgent && !store.urgentReminders.isEmpty {
                            Text("\(store.urgentReminders.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.red, in: Capsule())
                        }
                    }
                    .font(.subheadline.weight(filter == f ? .semibold : .regular))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        filter == f ? Color.accentColor.opacity(0.15) : Color.clear,
                        in: Capsule()
                    )
                    .foregroundStyle(filter == f ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 列表

    private var reminderList: some View {
        List {
            if store.reminders.isEmpty {
                ContentUnavailableView(
                    "还没有提醒事项",
                    systemImage: "checklist",
                    description: Text("在上面输入一句话，比如「明天下午三点交报告」")
                )
            } else {
                ForEach(displayedReminders, id: \.calendarItemIdentifier) { reminder in
                    ReminderRow(reminder: reminder)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                try? store.delete(reminder)
                                Task { await store.refresh() }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                try? store.markUrgent(reminder)
                                Task { await store.refresh() }
                            } label: {
                                Label("设为紧急", systemImage: "exclamationmark.triangle")
                            }
                            .tint(.orange)
                        }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await store.refresh() }
    }

    private var displayedReminders: [EKReminder] {
        switch filter {
        case .all: return store.reminders
        case .urgent: return store.urgentReminders
        case .today: return store.todayReminders
        }
    }

    private var permissionView: some View {
        ContentUnavailableView {
            Label("需要提醒事项权限", systemImage: "lock")
        } description: {
            Text("速记直接读写系统「提醒事项」，需要你授权完整访问。数据只存在你的设备上。")
        } actions: {
            Button("去授权") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - 操作

    private func addReminder() async {
        guard let result = parseResult, !result.title.isEmpty else { return }
        do {
            let created = try store.createReminder(from: result, list: selectedList)
            if let due = result.dueDate {
                await AlarmService.shared.schedulePreAlert(
                    id: created.calendarItemIdentifier,
                    title: result.title,
                    at: due,
                    minutesBefore: 5
                )
                // 紧急 + 有明确时刻 → 额外挂一个系统级全屏闹钟（iOS 26+）
                // 失败不影响提醒事项本身（EKAlarm 已能到点响铃）
                if result.priority == 1 {
                    await scheduleSystemAlarm(id: created.calendarItemIdentifier, title: result.title, at: due)
                }
            }
            inputText = ""
            parseResult = nil
            inputFocused = false
            showToast("已添加：\(result.title)")
            await store.refresh()
        } catch {
            showToast("添加失败：\(error.localizedDescription)")
        }
    }

    /// 系统级全屏闹钟（iOS 26+）。仅在紧急事项上调用，失败静默降级。
    private func scheduleSystemAlarm(id calendarItemID: String, title: String, at date: Date) async {
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else { return }
        // 每条提醒只在创建时调度一次，用新 UUID 即可
        _ = calendarItemID
        do {
            try await AlarmKitService.shared.scheduleAlarm(id: UUID(), title: title, at: date)
        } catch {
            // 权限被拒或系统不支持时静默降级，EKAlarm 仍会响铃
        }
        #endif
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            toast = nil
        }
    }
}
