import Foundation

/// 纯本地中文自然语义解析器（零依赖、离线可用）
///
/// 支持：
/// - 相对日期：今天 / 明天 / 后天 / 大后天 / 下周一 / 这周五 / 周五
/// - 绝对日期：3月15日 / 3/15 / 2026-03-15
/// - 相对时间：30分钟后 / 2小时后 / 3天后
/// - 时刻：上午9点 / 下午3点 / 晚上8点半 / 14:30 / 9点45
/// - 重复：每天 / 每周一三五 / 每周五 / 每月15号 / 每年
/// - 优先级：紧急 / 急 / !!! / 重要
/// - 标签：#工作
enum NaturalLanguageParser {

    // MARK: - 对外入口

    /// 解析一句话，now 可注入以便单元测试
    static func parse(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> ParseResult {
        var text = normalize(raw)
        var result = ParseResult(originalText: raw)

        // 1. 标签（先摘掉，避免干扰时间识别）
        let tags = extractTags(&text)
        result.tags = tags

        // 2. 优先级
        result.priority = extractPriority(&text)

        // 3. "明早"等复合词先展开为标准形式
        expandCompoundDayWords(&text)

        // 4. 重复规则（在绝对日期之前，因为"每周五"含"五"）
        let recurrence = extractRecurrence(&text)
        result.recurrence = recurrence

        // 4. 时间：相对时长 > 绝对日期 > 相对日期
        var date: Date?
        var hasTime = false
        var timeDesc: String?

        if let relative = extractRelativeDuration(&text, now: now, calendar: calendar) {
            date = relative.date
            hasTime = true
            timeDesc = relative.description
        } else {
            var base: Date?
            var baseDesc = ""
            if let absolute = extractAbsoluteDate(&text, now: now, calendar: calendar) {
                base = absolute.date
                baseDesc = absolute.description
            } else if let relativeDay = extractRelativeDay(&text, now: now, calendar: calendar) {
                base = relativeDay.date
                baseDesc = relativeDay.description
            }

            if let clock = extractClock(&text) {
                hasTime = true
                if let baseDate = base {
                    date = mergeClock(clock, into: baseDate, calendar: calendar)
                } else {
                    date = calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: now)
                    if let d = date, d < now {
                        date = calendar.date(byAdding: .day, value: 1, to: d)
                    }
                }
                timeDesc = baseDesc.isEmpty ? clock.description : baseDesc + " " + clock.description
            } else if let baseDate = base {
                date = baseDate
                timeDesc = baseDesc
            }
        }

        // 重复规则需要时间锚点：若有 weekday（如每周五），锚定到最近的那个周几；否则锚定今天
        // 注意：即使 clock 分支已临时算出今天的日期，重复规则也要覆盖它
        if let recur = recurrence {
            let clock = extractClockFromRaw(raw)
            let hour = clock?.hour ?? 9
            let minute = clock?.minute ?? 0
            hasTime = true

            if recur.frequency == .weekly, let firstWeekday = recur.weekdays.first {
                // 找到 >= 今天的最近目标周几
                let today = startOfDay(now, calendar: calendar)
                var candidate = today
                for _ in 0..<7 {
                    if calendar.component(.weekday, from: candidate) == firstWeekday {
                        break
                    }
                    candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
                }
                date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: candidate)
                if let d = date, d < now {
                    date = calendar.date(byAdding: .day, value: 7, to: d)
                }
            } else {
                var anchor = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
                if anchor < now {
                    anchor = calendar.date(byAdding: .day, value: 1, to: anchor) ?? anchor
                }
                date = anchor
            }
        }

        // 时段词兜底：如"这周五下午交方案"，孤立"下午"没被时钟正则消费，补默认时刻
        if let baseDate = date, !hasTime {
            let period = detectLonePeriod(in: text)
            let defaultHour: Int
            switch period {
            case "早上", "上午": defaultHour = 9
            case "中午": defaultHour = 12
            case "下午": defaultHour = 15
            case "晚上", "傍晚", "夜里": defaultHour = 20
            case "凌晨": defaultHour = 6
            default: defaultHour = -1
            }
            if defaultHour > 0 {
                date = calendar.date(bySettingHour: defaultHour, minute: 0, second: 0, of: baseDate)
                hasTime = true
                timeDesc = (timeDesc ?? "") + " \(defaultHour):00"
            }
        }

        // 剥离残留的孤立时段词（如"这周五下午交方案"里的"下午"）
        stripLonePeriodWords(&text)

        result.dueDate = date
        result.hasTime = hasTime
        result.timeDescription = timeDesc

        // 5. 清洗标题
        result.title = cleanTitle(text)

        return result
    }

    // MARK: - 归一化

    private static func normalize(_ s: String) -> String {
        var t = s
        // 全角数字 / 冒号 / 斜杠 → 半角
        let mapping: [Character: Character] = [
            "０": "0", "１": "1", "２": "2", "３": "3", "４": "4",
            "５": "5", "６": "6", "７": "7", "８": "8", "９": "9",
            "：": ":", "／": "/", "－": "-", "。": " ", "，": " ", "、": " "
        ]
        t = String(t.map { mapping[$0] ?? $0 })
        // 合并多余空格
        while t.contains("  ") {
            t = t.replacingOccurrences(of: "  ", with: " ")
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 复合词展开

    /// "明早"→"明天 早上"，"明晚"→"明天 晚上"，"今晚"→"今天 晚上" 等
    private static func expandCompoundDayWords(_ text: inout String) {
        let pairs: [(String, String)] = [
            ("明早", "明天 早上"),
            ("明晚", "明天 晚上"),
            ("今晚", "今天 晚上"),
            ("今早", "今天 早上"),
            ("后天早", "后天 早上"),
            ("大后天早", "大后天 早上")
        ]
        // 长词优先，避免"后天早"被"明早"类短词干扰
        for (word, replacement) in pairs.sorted(by: { $0.0.count > $1.0.count }) {
            text = text.replacingOccurrences(of: word, with: replacement)
        }
    }

    /// 检测残留的孤立时段词
    private static func detectLonePeriod(in text: String) -> String? {
        for word in ["凌晨", "早上", "上午", "中午", "下午", "傍晚", "晚上", "夜里"] {
            if text.contains(word) { return word }
        }
        return nil
    }

    /// 剥离未被时钟正则消费的孤立时段词
    private static func stripLonePeriodWords(_ text: inout String) {
        for word in ["上午", "下午", "中午", "早上", "晚上", "傍晚", "凌晨", "夜里"] {
            text = text.replacingOccurrences(of: word, with: " ")
        }
        text = text.replacingOccurrences(of: "  ", with: " ")
        text = text.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - 标签

    private static func extractTags(_ text: inout String) -> [String] {
        let pattern = "#([^\\s#]+)"
        let matches = matchAll(pattern, in: text)
        guard !matches.isEmpty else { return [] }
        let tags = matches.compactMap { m in
            captured(m, in: text, group: 1).map { String($0) }
        }
        for m in matches.reversed() {
            removeRange(m.range, from: &text)
        }
        return tags
    }

    // MARK: - 优先级

    private static func extractPriority(_ text: inout String) -> Int {
        let keywords = ["紧急", "重要", "急件", "加急", "!!!", "！！"]
        for kw in keywords where text.contains(kw) {
            text = text.replacingOccurrences(of: kw, with: " ")
            return 1
        }
        // "!" 连续 3 个以上
        if let range = text.range(of: #"!{3,}"#, options: .regularExpression) {
            text.removeSubrange(range)
            return 1
        }
        return 0
    }

    // MARK: - 重复规则

    private static func extractRecurrence(_ text: inout String) -> RecurrenceSpec? {
        // 每天 / 每日 / 天天
        if let r = text.range(of: "(每天|每日|天天)", options: .regularExpression) {
            text.removeSubrange(r)
            return .daily()
        }

        // 每周 / 每星期 / 每礼拜 + 周几序列（可带分隔符）
        // 注意：周几只收中文字符，不收阿拉伯数字，否则会误吞 "18:00" 的 "1"
        let weeklyPattern = "(每(周|星期|礼拜))\\s*([一二三四五六日天、,和\\s]+)"
        if let m = firstMatch(weeklyPattern, in: text) {
            let dayString = captured(m, in: text, group: 3) ?? ""
            let weekdays = parseWeekdayList(dayString)
            if !weekdays.isEmpty {
                removeRange(m.range, from: &text)
                return .weekly(weekdays)
            }
        }

        // 每月 N 号/日
        let monthlyPattern = "每月\\s*([0-9]{1,2}|[一二三四五六七八九十]+)\\s*[号日]"
        if let m = firstMatch(monthlyPattern, in: text) {
            if let day = captured(m, in: text, group: 1).flatMap({ chineseNumber($0) }) {
                removeRange(m.range, from: &text)
                return .monthly()
            }
        }

        // 每年
        if let r = text.range(of: "每年", options: .regularExpression) {
            text.removeSubrange(r)
            return .yearly()
        }

        return nil
    }

    private static func parseWeekdayList(_ s: String) -> [Int] {
        var result: [Int] = []
        for ch in s {
            let n: Int?
            switch ch {
            case "一", "1": n = 2
            case "二", "2": n = 3
            case "三", "3": n = 4
            case "四", "4": n = 5
            case "五", "5": n = 6
            case "六", "6": n = 7
            case "日", "天", "7": n = 1
            default: n = nil
            }
            if let n, !result.contains(n) { result.append(n) }
        }
        return result.sorted()
    }

    // MARK: - 相对时长

    private static func extractRelativeDuration(
        _ text: inout String, now: Date, calendar: Calendar
    ) -> (date: Date, description: String)? {
        let pattern = "([0-9]+|半|[一两二三四五六七八九十]+)\\s*(分钟|小时|个小时|天|周)\\s*(后|之后|以后)"
        guard let m = firstMatch(pattern, in: text),
              let numStr = captured(m, in: text, group: 1),
              let unitStr = captured(m, in: text, group: 2) else { return nil }

        let component: Calendar.Component
        let unitName: String
        switch unitStr {
        case "分钟": component = .minute; unitName = "分钟"
        case "小时", "个小时": component = .hour; unitName = "小时"
        case "天": component = .day; unitName = "天"
        case "周": component = .weekOfYear; unitName = "周"
        default: return nil
        }

        let finalValue: Int
        if numStr == "半" {
            // "半小时后" = 30 分钟；"半分钟后"不常见，按 30 秒无意义，统一 30 分钟
            finalValue = 30
        } else if let n = chineseNumber(numStr) {
            finalValue = n
        } else {
            return nil
        }
        let actualComponent: Calendar.Component = (numStr == "半") ? .minute : component

        guard let date = calendar.date(byAdding: actualComponent, value: finalValue, to: now) else { return nil }
        removeRange(m.range, from: &text)
        return (date, "\(numStr)\(unitName)后")
    }

    // MARK: - 绝对日期

    private static func extractAbsoluteDate(
        _ text: inout String, now: Date, calendar: Calendar
    ) -> (date: Date, description: String)? {
        // 2026-03-15
        let isoPattern = "([0-9]{4})[-/]([0-9]{1,2})[-/]([0-9]{1,2})"
        if let m = firstMatch(isoPattern, in: text),
           let y = captured(m, in: text, group: 1).flatMap({ Int($0) }),
           let mo = captured(m, in: text, group: 2).flatMap({ Int($0) }),
           let d = captured(m, in: text, group: 3).flatMap({ Int($0) }) {
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.year = y; comps.month = mo; comps.day = d
            if let date = calendar.date(from: comps) {
                removeRange(m.range, from: &text)
                return (date, "\(y)年\(mo)月\(d)日")
            }
        }

        // 3月15日 / 3/15
        let cnPattern = "([0-9]{1,2})\\s*[月/]\\s*([0-9]{1,2})\\s*[号日]?"
        if let m = firstMatch(cnPattern, in: text),
           let mo = captured(m, in: text, group: 1).flatMap({ Int($0) }),
           let d = captured(m, in: text, group: 2).flatMap({ Int($0) }) {
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.month = mo; comps.day = d
            if var date = calendar.date(from: comps), date < startOfDay(now, calendar: calendar) {
                comps.year = (comps.year ?? 0) + 1
                date = calendar.date(from: comps) ?? date
            }
            if let date = calendar.date(from: comps) {
                removeRange(m.range, from: &text)
                return (date, "\(mo)月\(d)日")
            }
        }

        // 15号 / 15日（当月）
        let dayOnlyPattern = "([0-9]{1,2})\\s*[号日]"
        if let m = firstMatch(dayOnlyPattern, in: text),
           let d = captured(m, in: text, group: 1).flatMap({ Int($0) }), d <= 31 {
            var comps = calendar.dateComponents([.year, .month], from: now)
            comps.day = d
            if var date = calendar.date(from: comps), date < startOfDay(now, calendar: calendar) {
                comps.month = (comps.month ?? 0) + 1
                if comps.month! > 12 { comps.month = 1; comps.year = (comps.year ?? 0) + 1 }
            }
            if let date = calendar.date(from: comps) {
                removeRange(m.range, from: &text)
                return (date, "\(d)号")
            }
        }

        return nil
    }

    // MARK: - 相对日期

    private static func extractRelativeDay(
        _ text: inout String, now: Date, calendar: Calendar
    ) -> (date: Date, description: String)? {
        let today = startOfDay(now, calendar: calendar)

        // 今天 / 今晚 / 明天 / 明晚 / 后天 / 大后天
        let simple: [(String, Int, String)] = [
            ("大后天", 3, "大后天"),
            ("后天", 2, "后天"),
            ("明天", 1, "明天"),
            ("明日", 1, "明天"),
            ("明晚", 1, "明晚"),
            ("今晚", 0, "今晚"),
            ("今天", 0, "今天"),
            ("今日", 0, "今天")
        ]
        for (keyword, offset, desc) in simple where text.contains(keyword) {
            text = text.replacingOccurrences(of: keyword, with: " ")
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return (date, desc)
        }

        // 下周一 / 下个星期一
        let nextWeekPattern = "下(个)?(周|星期|礼拜)([一二三四五六日天])"
        if let m = firstMatch(nextWeekPattern, in: text),
           let dayChar = captured(m, in: text, group: 3).first,
           let weekday = weekdayNumber(dayChar) {
            let date = nextWeekday(weekday, from: today, calendar: calendar, nextWeek: true)
            removeRange(m.range, from: &text)
            return (date, "下周\(dayChar)")
        }

        // 这周五 / 本周五 / 周五
        let thisWeekPattern = "(这|本)?(周|星期|礼拜)([一二三四五六日天])"
        if let m = firstMatch(thisWeekPattern, in: text),
           let dayChar = captured(m, in: text, group: 3).first,
           let weekday = weekdayNumber(dayChar) {
            let date = nextWeekday(weekday, from: today, calendar: calendar, nextWeek: false)
            removeRange(m.range, from: &text)
            return (date, "周\(dayChar)")
        }

        return nil
    }

    private static func weekdayNumber(_ ch: Character) -> Int? {
        switch ch {
        case "一": return 2
        case "二": return 3
        case "三": return 4
        case "四": return 5
        case "五": return 6
        case "六": return 7
        case "日", "天": return 1
        default: return nil
        }
    }

    private static func nextWeekday(
        _ target: Int, from date: Date, calendar: Calendar, nextWeek: Bool
    ) -> Date {
        let current = calendar.component(.weekday, from: date)
        var delta = (target - current + 7) % 7
        if nextWeek {
            delta = delta == 0 ? 7 : delta + 7
        } else if delta == 0 {
            // "周五" 在周五当天，视为今天
            delta = 0
        }
        return calendar.date(byAdding: .day, value: delta, to: date) ?? date
    }

    // MARK: - 时刻

    private struct Clock {
        let hour: Int
        let minute: Int

        var description: String {
            String(format: "%02d:%02d", hour, minute)
        }
    }

    private static func extractClock(_ text: inout String) -> Clock? {
        guard let m = firstMatch(clockPattern, in: text),
              let clock = clockFromMatch(m, in: text) else { return nil }
        removeRange(m.range, from: &text)
        return clock
    }

    private static func extractClockFromRaw(_ raw: String) -> Clock? {
        guard let m = firstMatch(clockPattern, in: raw),
              let clock = clockFromMatch(m, in: raw) else { return nil }
        return clock
    }

    private static let clockPattern =
        "(上午|早上|早晨|凌晨|中午|下午|傍晚|晚上|夜里|晚)?\\s*" +
        "([0-9]{1,2}|[一二三四五六七八九十]{1,3})\\s*[点:：]\\s*" +
        "([0-9]{1,2}|[一二三四五六七八九十]{1,3})?\\s*分?\\s*(半)?"

    private static func clockFromMatch(_ m: NSTextCheckingResult, in text: String) -> Clock? {
        let period = captured(m, in: text, group: 1)
        guard let hourStr = captured(m, in: text, group: 2),
              var hour = chineseNumber(hourStr) else { return nil }
        let minuteStr = captured(m, in: text, group: 3)
        let isHalf = captured(m, in: text, group: 4) != nil

        var minute = minuteStr.flatMap { chineseNumber($0) } ?? 0
        if isHalf { minute = 30 }

        // 12 小时制修正
        if let p = period {
            switch p {
            case "下午", "傍晚", "晚上", "夜里", "晚":
                if hour < 12 { hour += 12 }
            case "中午":
                if hour < 11 { hour += 12 }
            case "凌晨":
                if hour == 12 { hour = 0 }
            default:
                if hour == 12 { hour = 0 } // 上午12点 → 0点
            }
        }

        guard hour >= 0, hour <= 23, minute >= 0, minute <= 59 else { return nil }
        return Clock(hour: hour, minute: minute)
    }

    private static func mergeClock(_ clock: Clock, into base: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: base) ?? base
    }

    // MARK: - 标题清洗

    private static func cleanTitle(_ s: String) -> String {
        var t = s
        let prefixes = ["提醒我", "记得", "帮我", "要", "去"]
        for p in prefixes {
            if t.hasPrefix(p) { t = String(t.dropFirst(p.count)) }
        }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: ":,，。！!?？、 "))

        // "周五前交方案" 这类残留的方向词
        t = t.replacingOccurrences(of: #"^\s*(前|之前|之前)\s*"#, with: "", options: .regularExpression)

        if t.isEmpty { t = "新提醒" }
        return t
    }

    // MARK: - 工具

    private static func startOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    private static func chineseNumber(_ s: String) -> Int? {
        if let n = Int(s) { return n }
        if s.isEmpty { return nil }

        let digitMap: [Character: Int] = [
            "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]

        if s == "十" { return 10 }
        if s.contains("十") {
            let parts = s.split(separator: "十", omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let tens = parts[0].isEmpty ? 1 : (digitMap[parts[0].first!] ?? 0)
            let ones = parts[1].isEmpty ? 0 : (digitMap[parts[1].first!] ?? 0)
            return tens * 10 + ones
        }

        guard s.count == 1, let v = digitMap[s.first!] else { return nil }
        return v
    }

    private static func matchAll(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
    }

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        matchAll(pattern, in: text).first
    }

    private static func captured(_ m: NSTextCheckingResult, in text: String, group: Int) -> String? {
        guard group < m.numberOfRanges else { return nil }
        let r = m.range(at: group)
        guard r.location != NSNotFound else { return nil }
        return (text as NSString).substring(with: r)
    }

    private static func removeRange(_ nsRange: NSRange, from text: inout String) {
        guard let range = Range(nsRange, in: text) else { return }
        text.removeSubrange(range)
        text = text.replacingOccurrences(of: "  ", with: " ")
        text = text.trimmingCharacters(in: .whitespaces)
    }
}
