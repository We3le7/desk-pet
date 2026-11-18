import Foundation

/// 薪资配置。全部金额都按**税后到账**口径，避免"看起来很多但拿不到"。
public struct SalaryConfig: Sendable, Equatable, Codable {
    /// 税后月薪（元）
    public var monthlyNet: Double
    /// 月均工作日（法定折算 21.75）
    public var workdaysPerMonth: Double
    /// 每日工时（小时）
    public var hoursPerDay: Double
    /// 年终额外月数（13 薪填 1，14 薪填 2）；填 0 表示不参与折算
    public var extraMonthsPerYear: Double
    /// 工作日起始分钟数（09:30 = 570）
    public var startMinuteOfDay: Int
    /// 工作日结束分钟数（19:00 = 1140）
    public var endMinuteOfDay: Int
    /// 午休扣除（分钟），0 表示不扣
    public var lunchBreakMinutes: Int
    /// Calendar weekday：1 = 周日 … 7 = 周六
    public var weekdays: Set<Int>

    public init(
        monthlyNet: Double = 21000,
        workdaysPerMonth: Double = 21.75,
        hoursPerDay: Double = 8,
        extraMonthsPerYear: Double = 0,
        startMinuteOfDay: Int = 9 * 60 + 30,
        endMinuteOfDay: Int = 19 * 60,
        lunchBreakMinutes: Int = 0,
        weekdays: Set<Int> = [2, 3, 4, 5, 6]
    ) {
        self.monthlyNet = monthlyNet
        self.workdaysPerMonth = workdaysPerMonth
        self.hoursPerDay = hoursPerDay
        self.extraMonthsPerYear = extraMonthsPerYear
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.lunchBreakMinutes = lunchBreakMinutes
        self.weekdays = weekdays
    }

    /// 把年终摊到每月的等效月薪
    public var effectiveMonthly: Double {
        guard extraMonthsPerYear > 0 else { return monthlyNet }
        return monthlyNet * (12 + extraMonthsPerYear) / 12
    }

    /// 每秒到账（元）。按**合同时薪**折算：月薪 ÷ (月工作日 × 日工时 × 3600)。
    /// 也就是说在岗越久赚得越多，而不是"把月薪均摊到在岗窗口"。
    public var perSecond: Double {
        let monthSeconds = workdaysPerMonth * hoursPerDay * 3600
        guard monthSeconds > 0 else { return 0 }
        return effectiveMonthly / monthSeconds
    }

    /// 在岗窗口的分钟数；下班早于上班视为**跨零点**（夜班），起止相同视为 0
    public var windowMinutes: Int {
        let diff = endMinuteOfDay - startMinuteOfDay
        if diff > 0 { return diff }
        if diff == 0 { return 0 }
        return diff + 24 * 60
    }

    /// 在岗窗口的秒数（扣掉午休）
    public var windowSeconds: Double {
        let minutes = max(windowMinutes - lunchBreakMinutes, 0)
        return Double(minutes) * 60
    }

    /// 归一化：分钟对齐到 5 分钟刻度、限制在 0…1439，避免"设置里显示 30、实际按 32 算"。
    public func normalized() -> SalaryConfig {
        var copy = self
        copy.startMinuteOfDay = Self.snap(copy.startMinuteOfDay)
        copy.endMinuteOfDay = Self.snap(copy.endMinuteOfDay)
        if copy.monthlyNet.isFinite {
            copy.monthlyNet = max(copy.monthlyNet, 0)
        }
        if copy.hoursPerDay.isFinite {
            copy.hoursPerDay = min(max(copy.hoursPerDay, 0.5), 24)
        }
        if copy.workdaysPerMonth.isFinite {
            copy.workdaysPerMonth = min(max(copy.workdaysPerMonth, 1), 31)
        }
        copy.lunchBreakMinutes = max(copy.lunchBreakMinutes, 0)
        return copy
    }

    private static func snap(_ minutes: Int) -> Int {
        let clamped = min(max(minutes, 0), 23 * 60 + 55)
        return (Int((Double(clamped) / 5).rounded()) * 5).clamped(to: 0...(23 * 60 + 55))
    }

    /// 在岗一整天能赚多少
    public var perDay: Double { perSecond * windowSeconds }

    /// 每小时到账
    public var perHour: Double { perSecond * 3600 }

    /// 默认值对应的量级说明（设置面板展示用）
    public var summary: String {
        String(
            format: "每秒 ¥%.3f · 每小时 ¥%.1f · 每天 ¥%.0f",
            perSecond, perHour, perDay
        )
    }
}


private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
