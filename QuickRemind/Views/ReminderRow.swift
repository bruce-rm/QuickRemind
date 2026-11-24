import SwiftUI
import EventKit

struct ReminderRow: View {
    @Environment(ReminderStore.self) private var store
    let reminder: EKReminder

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                try? store.toggleComplete(reminder)
                Task { await store.refresh() }
            } label: {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(reminder.priority == 1 ? .orange : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(reminder.title)
                        .font(.body)
                    if reminder.priority == 1 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 10) {
                    if let comps = reminder.dueDateComponents,
                       let date = Calendar.current.date(from: comps) {
                        Label(formatDate(date), systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(isOverdue(date) ? .red : .secondary)
                    }
                    if let calendar = reminder.calendar {
                        Label(calendar.title, systemImage: "folder")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "今天 HH:mm"
        } else if calendar.isDateInTomorrow(date) {
            formatter.dateFormat = "明天 HH:mm"
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            formatter.dateFormat = "M月d日 HH:mm"
        } else {
            formatter.dateFormat = "yyyy/M/d HH:mm"
        }
        return formatter.string(from: date)
    }

    private func isOverdue(_ date: Date) -> Bool {
        date < Date() && !reminder.isCompleted
    }
}
