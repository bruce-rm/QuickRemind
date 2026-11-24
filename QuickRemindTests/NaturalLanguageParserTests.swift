import XCTest
@testable import QuickRemind

final class NaturalLanguageParserTests: XCTestCase {

    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar = cal
        // 固定基准时间：2026-11-23 周一 12:00
        var comps = DateComponents()
        comps.year = 2026; comps.month = 11; comps.day = 23
        comps.hour = 12; comps.minute = 0
        now = cal.date(from: comps)!
    }

    private func hm(_ date: Date?) -> String {
        guard let date else { return "nil" }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return "\(c.hour!):\(String(format: "%02d", c.minute!))"
    }

    private func ymd(_ date: Date?) -> String {
        guard let date else { return "nil" }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    // MARK: - 相对日期 + 时刻

    func testTomorrowAfternoon() {
        let r = NaturalLanguageParser.parse("明天下午三点交报告", now: now, calendar: calendar)
        XCTAssertEqual(r.title, "交报告")
        XCTAssertEqual(ymd(r.dueDate), "2026-11-24")
        XCTAssertEqual(hm(r.dueDate), "15:0")
        XCTAssertTrue(r.hasTime)
    }

    func testDayAfterTomorrowMorning() {
        let r = NaturalLanguageParser.parse("后天上午10点开会", now: now, calendar: calendar)
        XCTAssertEqual(r.title, "开会")
        XCTAssertEqual(ymd(r.dueDate), "2026-11-25")
        XCTAssertEqual(hm(r.dueDate), "10:0")
    }

    func testTonight() {
        let r = NaturalLanguageParser.parse("今晚8点打电话给妈妈", now: now, calendar: calendar)
        XCTAssertEqual(r.title, "打电话给妈妈")
        XCTAssertEqual(ymd(r.dueDate), "2026-11-23")
        XCTAssertEqual(hm(r.dueDate), "20:0")
    }

    func testHourAndHalf() {
        let r = NaturalLanguageParser.parse("明早八点半晨跑", now: now, calendar: calendar)
        XCTAssertEqual(r.title, "晨跑")
        XCTAssertEqual(hm(r.dueDate), "8:30")
    }

    func test24HourClock() {
        let r = NaturalLanguageParser.parse("明天 14:30 项目评审", now: now, calendar: calendar)
        XCTAssertEqual(r.title, "项目评审")
        XCTAssertEqual(hm(r.dueDate), "14:30")
    }

    // MARK: - 相对时长

    func testMinutesLater() {
        let r = NaturalLanguageParser.parse("30分钟后吃药", now: now, calendar: calendar)
        XCTAssertEqual(r.title, "吃药")
        XCTAssertEqual(hm(r.dueDate), "12:30")
    }

    func testHalfHourLater() {
        let r = NaturalLanguageParser.parse("半小时后看火", now: now, calendar: calendar)
        XCTAssertEqual(r.title, "看火")
        XCTAssertEqual(hm(r.dueDate), "12:30")
    }

    func testHoursLaterChinese() {
        let r = NaturalLanguageParser.parse("两小时后交表", now: now, calendar: calendar)
        XCTAssertEqual(r.title, "交表")
        XCTAssertEqual(hm(r.dueDate), "14:0")
    }

    // MARK: - 周几

    func testNextMonday() {
        let r = NaturalLanguageParser.parse("下周一 9:00 周会", now: now, calendar: calendar)
        XCTAssertEqual(r.title, "周会")
        XCTAssertEqual(ymd(r.dueDate), "2026-11-30")
        XCTAssertEqual(hm(r.dueDate), "9:0")
    }

    func testThisFriday() {
        let r = NaturalLanguageParser.parse("这周五下午交方案", now: now, calendar: calendar)
        XCTAssertEqual(r.title, "交方案")
        XCTAssertEqual(ymd(r.dueDate), "2026-11-27")
        XCTAssertEqual(hm(r.dueDate), "15:0")
    }

    // MARK: - 绝对日期

    func testMonthDay() {
        let r = NaturalLanguageParser.parse("12月25日 上午10点 送礼物", now: now, calendar: calendar)
        XCTAssertEqual(r.title, "送礼物")
        XCTAssertEqual(ymd(r.dueDate), "2026-12-25")
        XCTAssertEqual(hm(r.dueDate), "10:0")
    }

    // MARK: - 重复

    func testEveryDay() {
        let r = NaturalLanguageParser.parse("每天 7点半 晨跑", now: now, calendar: calendar)
        XCTAssertEqual(r.title, "晨跑")
        XCTAssertEqual(r.recurrence?.frequency, .daily)
        XCTAssertEqual(hm(r.dueDate), "7:30")
    }

    func testEveryWeekMultiDays() {
        let r = NaturalLanguageParser.parse("每周一三五 9点 健身", now: now, calendar: calendar)
        XCTAssertEqual(r.title, "健身")
        XCTAssertEqual(r.recurrence?.frequency, .weekly)
        XCTAssertEqual(r.recurrence?.weekdays, [2, 4, 6])
        // 首个 weekday=周一，9:00 相对基准 12:00 已过，顺延一周
        XCTAssertEqual(ymd(r.dueDate), "2026-11-30")
    }

    func testEveryWeekSingleDay() {
        let r = NaturalLanguageParser.parse("每周五 18:00 周报", now: now, calendar: calendar)
        XCTAssertEqual(r.title, "周报")
        XCTAssertEqual(r.recurrence?.weekdays, [6])
        // 首次触发锚定到最近的周五（2026-11-27）
        XCTAssertEqual(ymd(r.dueDate), "2026-11-27")
        XCTAssertEqual(hm(r.dueDate), "18:0")
    }

    // MARK: - 优先级与标签

    func testUrgent() {
        let r = NaturalLanguageParser.parse("紧急 明天交税", now: now, calendar: calendar)
        XCTAssertEqual(r.priority, 1)
        XCTAssertEqual(r.title, "交税")
    }

    func testExclamationMarks() {
        let r = NaturalLanguageParser.parse("交电费!!! 明天", now: now, calendar: calendar)
        XCTAssertEqual(r.priority, 1)
        XCTAssertEqual(r.title, "交电费")
    }

    func testTag() {
        let r = NaturalLanguageParser.parse("明天 #工作 对齐需求", now: now, calendar: calendar)
        XCTAssertEqual(r.tags, ["工作"])
        XCTAssertEqual(r.title, "对齐需求")
    }

    // MARK: - 无时间

    func testNoDate() {
        let r = NaturalLanguageParser.parse("买牛奶", now: now, calendar: calendar)
        XCTAssertEqual(r.title, "买牛奶")
        XCTAssertNil(r.dueDate)
    }

    func testFullWidthDigits() {
        let r = NaturalLanguageParser.parse("明天下午３点交报告", now: now, calendar: calendar)
        XCTAssertEqual(r.title, "交报告")
        XCTAssertEqual(hm(r.dueDate), "15:0")
    }
}
