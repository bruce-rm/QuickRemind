import SwiftUI
import EventKit

/// 解析结果可视化预览，用户可在添加前微调
struct ParsePreview: View {
    let result: ParseResult
    @Binding var selectedList: EKCalendar?
    let calendars: [EKCalendar]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("已识别", systemImage: "wand.and.stars")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if result.priority == 1 {
                    Label("紧急", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            Text(result.title)
                .font(.headline)

            HStack(spacing: 12) {
                if let desc = result.timeDescription {
                    Label(desc, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if result.dueDate == nil {
                    Label("无日期", systemImage: "calendar.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let rec = result.recurrence {
                    Label(recurrenceText(rec), systemImage: "repeat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !result.tags.isEmpty {
                    Label(result.tags.map { "#\($0)" }.joined(separator: " "), systemImage: "number")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if calendars.count > 1 {
                Menu {
                    ForEach(calendars, id: \.calendarIdentifier) { cal in
                        Button {
                            selectedList = cal
                        } label: {
                            Label(cal.title, systemImage: selectedList == cal ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text(selectedList?.title ?? "默认清单")
                        Image(systemName: "chevron.down")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.snappy, value: result.title)
    }

    private func recurrenceText(_ spec: RecurrenceSpec) -> String {
        switch spec.frequency {
        case .daily: return "每天"
        case .weekly:
            let names = ["日", "一", "二", "三", "四", "五", "六"]
            return "每周" + spec.weekdays.compactMap { names[safe: $0 - 1] }.joined(separator: "、")
        case .monthly: return "每月"
        case .yearly: return "每年"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
