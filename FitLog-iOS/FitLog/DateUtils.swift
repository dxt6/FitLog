import Foundation

/// 日期工具：全部基于 Calendar 手工计算，无 Locale/Formatter 缓存问题。
enum DateUtils {

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // 周一为一周第一天
        return c
    }()

    private static let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    // MARK: - 基础转换（字符串格式 yyyy-MM-dd）

    static func todayStr() -> String { toStr(Date()) }

    static func toStr(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func fromStr(_ s: String) -> Date {
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        var c = DateComponents()
        c.year = parts[0]
        c.month = parts[1]
        c.day = parts[2]
        return calendar.date(from: c) ?? Date()
    }

    // MARK: - 显示

    /// "8月10日"
    static func display(_ s: String) -> String {
        let c = calendar.dateComponents([.month, .day], from: fromStr(s))
        return "\(c.month ?? 0)月\(c.day ?? 0)日"
    }

    /// "2026年8月10日 周一"
    static func displayFull(_ s: String) -> String {
        let d = fromStr(s)
        let c = calendar.dateComponents([.year, .month, .day, .weekday], from: d)
        let wd = weekdayNames[mondayFirstIndex(weekday: c.weekday ?? 1) - 1]
        return "\(c.year ?? 0)年\(c.month ?? 0)月\(c.day ?? 0)日 \(wd)"
    }

    // MARK: - 日期运算

    static func plusDays(_ s: String, _ n: Int) -> String {
        guard let d = calendar.date(byAdding: .day, value: n, to: fromStr(s)) else { return s }
        return toStr(d)
    }

    /// b - a 的整天数。
    static func daysBetween(_ a: String, _ b: String) -> Int {
        let da = calendar.startOfDay(for: fromStr(a))
        let db = calendar.startOfDay(for: fromStr(b))
        return calendar.dateComponents([.day], from: da, to: db).day ?? 0
    }

    // MARK: - 月历辅助

    /// 该日期所在月份的第一天。
    static func firstOfMonth(_ s: String) -> String {
        let d = fromStr(s)
        var c = calendar.dateComponents([.year, .month], from: d)
        c.day = 1
        return toStr(calendar.date(from: c) ?? d)
    }

    /// 该日期所在月份的天数。
    static func lengthOfMonth(_ s: String) -> Int {
        calendar.range(of: .day, in: .month, for: fromStr(s))?.count ?? 30
    }

    /// "2026年8月" 形式的月份标题。
    static func yearMonthLabel(_ s: String) -> String {
        let c = calendar.dateComponents([.year, .month], from: fromStr(s))
        return "\(c.year ?? 0)年\(c.month ?? 0)月"
    }

    /// 在月份上加减 n 个月，返回该月第一天字符串。
    static func plusMonths(_ s: String, _ n: Int) -> String {
        let first = firstOfMonth(s)
        guard let d = calendar.date(byAdding: .month, value: n, to: fromStr(first)) else { return first }
        var c = calendar.dateComponents([.year, .month], from: d)
        c.day = 1
        return toStr(calendar.date(from: c) ?? d)
    }

    /// 星期几（周一=1 … 周日=7），用于月历按周一对齐。
    static func weekdayMondayFirst(_ s: String) -> Int {
        let wd = calendar.component(.weekday, from: fromStr(s))
        return mondayFirstIndex(weekday: wd)
    }

    /// 取日期中的"日"（1-31）。
    static func dayOfMonth(_ s: String) -> Int {
        calendar.component(.day, from: fromStr(s))
    }

    /// 系统 weekday（周日=1 … 周六=7）→ 周一为第一列的下标（周一=1 … 周日=7）。
    private static func mondayFirstIndex(weekday: Int) -> Int {
        ((weekday + 5) % 7) + 1
    }
}
