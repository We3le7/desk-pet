import Foundation

/// 某一时刻的收益快照。
public struct EarningsAmount: Sendable, Equatable {
    /// 今日累计（元）
    public var total: Double
    /// 每秒到账（元）
    public var perSecond: Double
    /// 今天已工作秒数
    public var workedSeconds: Double
    /// 是否处于工作时段
    public var isWorking: Bool
    /// 是否处于暂停
    public var isPaused: Bool

    public init(
        total: Double = 0,
        perSecond: Double = 0,
        workedSeconds: Double = 0,
        isWorking: Bool = false,
        isPaused: Bool = false
    ) {
        self.total = total
        self.perSecond = perSecond
        self.workedSeconds = workedSeconds
        self.isWorking = isWorking
        self.isPaused = isPaused
    }
}

/// 上班鼓励器引擎。
///
/// 刻意**不累加**：金额 = 今日已工作秒数 × 每秒工资。
/// 这样跨上班边界、系统休眠、进程重启都不会漂移，也不会重复计钱。
public struct EarningsEngine: Sendable {
    public var config: SalaryConfig
    public private(set) var isPaused: Bool
    /// 暂停时冻结的金额
    private var frozen: EarningsAmount?

    public init(config: SalaryConfig = SalaryConfig()) {
        self.config = config
        self.isPaused = false
        self.frozen = nil
    }

    // MARK: - 查询

    public func amount(at date: Date, calendar: Calendar = .current) -> EarningsAmount {
        if isPaused, var snapshot = frozen {
            snapshot.isPaused = true
            return snapshot
        }

        let worked = workedSecondsToday(at: date, calendar: calendar)
        return EarningsAmount(
            total: worked * config.perSecond,
            perSecond: config.perSecond,
            workedSeconds: worked,
            isWorking: worked > 0,
            isPaused: false
        )
    }

    /// 今天已经工作的秒数。
    /// 支持跨零点班次（22:00–06:00）；不在窗口内返回 0。
    public func workedSecondsToday(at date: Date, calendar: Calendar = .current) -> Double {
        let components = calendar.dateComponents([.weekday, .hour, .minute, .second], from: date)
        guard let weekday = components.weekday, config.weekdays.contains(weekday),
              let hour = components.hour,
              let minute = components.minute
        else { return 0 }

        let second = components.second ?? 0
        let nowSeconds = Double(hour * 3600 + minute * 60 + second)
        let startSeconds = Double(config.startMinuteOfDay * 60)
        let endSeconds = Double(config.endMinuteOfDay * 60)
        let windowSeconds = config.windowSeconds
        guard windowSeconds > 0 else { return 0 }

        // 语义：班前 0 → 班中按已过时间 → 班后封顶为整个窗口（下班后仍应看得到今天的总额）
        let elapsed: Double
        if endSeconds > startSeconds {
            guard nowSeconds >= startSeconds else { return 0 }
            elapsed = nowSeconds - startSeconds
        } else {
            if nowSeconds >= startSeconds {
                elapsed = nowSeconds - startSeconds
            } else if nowSeconds < endSeconds {
                elapsed = nowSeconds + 24 * 3600 - startSeconds
            } else {
                elapsed = windowSeconds   // 夜班已结束
            }
        }

        let worked = min(max(elapsed, 0), windowSeconds)
        let lunchSeconds = Double(config.lunchBreakMinutes * 60)
        return max(worked - min(lunchSeconds, worked), 0)
    }

    // MARK: - 暂停

    public mutating func pause(at date: Date, calendar: Calendar = .current) {
        guard !isPaused else { return }
        frozen = amount(at: date, calendar: calendar)
        isPaused = true
    }

    public mutating func resume() {
        isPaused = false
        frozen = nil
    }

    public mutating func togglePause(at date: Date, calendar: Calendar = .current) {
        if isPaused {
            resume()
        } else {
            pause(at: date, calendar: calendar)
        }
    }
}

/// 里程碑：每跨过一个整十元就抖一下，每 500 元大庆祝一次。
public struct MilestoneTracker: Sendable {
    public var step: Double
    public var bigStep: Double
    private var lastValue: Double

    public init(step: Double = 50, bigStep: Double = 500) {
        self.step = step
        self.bigStep = bigStep
        self.lastValue = 0
    }

    /// 返回从 old 到 new 之间跨过的里程碑金额（升序）。
    public mutating func crossed(from old: Double, to new: Double) -> [Double] {
        guard new > old else {
            lastValue = new
            return []
        }
        let first = Int(floor(old / step)) + 1
        let last = Int(floor(new / step))
        lastValue = new
        guard last >= first else { return [] }
        return (first...last).map { Double($0) * step }
    }

    /// 是否属于大里程碑（500 的整数倍）
    public func isBig(_ milestone: Double) -> Bool {
        bigStep > 0 && abs(milestone.truncatingRemainder(dividingBy: bigStep)) < 0.0001
    }
}

/// 金额格式化。自测断言依赖稳定输出，所以不用 NumberFormatter。
public enum MoneyFormat {
    /// 1234.5678 → "¥1,234.57"
    public static func yuan(_ value: Double) -> String {
        let negative = value < 0
        let amount = abs(value)
        let rounded = (amount * 100).rounded() / 100
        let integerPart = floor(rounded)
        let fraction = Int(((rounded - integerPart) * 100).rounded())
        let grouped = groupThousands(Int(integerPart))
        return "\(negative ? "-" : "")¥\(grouped).\(String(format: "%02d", fraction))"
    }

    /// 每秒到账：低于 0.1 元时给三位小数，否则两位
    public static func perSecond(_ value: Double) -> String {
        if value < 0.1 {
            return String(format: "¥%.3f/秒", value)
        }
        return String(format: "¥%.2f/秒", value)
    }

    private static func groupThousands(_ value: Int) -> String {
        let digits = String(value)
        guard digits.count > 3 else { return digits }
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 {
                result.append(",")
            }
            result.append(character)
        }
        return result
    }
}
