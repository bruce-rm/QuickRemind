import Foundation

/// 自然语义解析后的提醒结构
struct ParseResult: Equatable {
    /// 任务标题（已从原句中剥离时间词）
    var title: String
    /// 到期时间；nil 表示无日期
    var dueDate: Date?
    /// 是否解析出了具体时刻（false 时为仅日期的"全天"提醒）
    var hasTime: Bool
    /// 重复规则
    var recurrence: RecurrenceSpec?
    /// 优先级：1 = 高（对应系统"紧急"筛选），0 = 无
    var priority: Int
    /// 从 #标签 中提取的标签
    var tags: [String]
    /// 原句（保留，写入备注）
    var originalText: String
    /// 解析出的时间描述，用于界面回显
    var timeDescription: String?

    init(
        title: String = "",
        dueDate: Date? = nil,
        hasTime: Bool = false,
        recurrence: RecurrenceSpec? = nil,
        priority: Int = 0,
        tags: [String] = [],
        originalText: String = "",
        timeDescription: String? = nil
    ) {
        self.title = title
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.recurrence = recurrence
        self.priority = priority
        self.tags = tags
        self.originalText = originalText
        self.timeDescription = timeDescription
    }
}

/// 重复规格，可直接映射到 EKRecurrenceRule
struct RecurrenceSpec: Equatable {
    enum Frequency: Equatable {
        case daily
        case weekly
        case monthly
        case yearly

        var calendarUnit: Calendar.Component {
            switch self {
            case .daily: return .day
            case .weekly: return .weekday
            case .monthly: return .month
            case .yearly: return .year
            }
        }
    }

    let frequency: Frequency
    /// 周几：1 = 周日, 2 = 周一 ... 7 = 周六（与 Calendar.component(.weekday) 一致）
    let weekdays: [Int]
    /// 间隔，默认 1
    let interval: Int

    static func daily(interval: Int = 1) -> RecurrenceSpec {
        RecurrenceSpec(frequency: .daily, weekdays: [], interval: interval)
    }

    static func weekly(_ weekdays: [Int], interval: Int = 1) -> RecurrenceSpec {
        RecurrenceSpec(frequency: .weekly, weekdays: weekdays, interval: interval)
    }

    static func monthly(interval: Int = 1) -> RecurrenceSpec {
        RecurrenceSpec(frequency: .monthly, weekdays: [], interval: interval)
    }

    static func yearly(interval: Int = 1) -> RecurrenceSpec {
        RecurrenceSpec(frequency: .yearly, weekdays: [], interval: interval)
    }
}
