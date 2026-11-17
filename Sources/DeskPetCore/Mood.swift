import Foundation

/// 宠物情绪。渲染层负责把它映射到具体宠物包的动画轨道。
public enum PetMood: String, Sendable, CaseIterable {
    case idle
    case busy
    case overheat
    case tired
    case charging
    case sleeping
    case celebrate
    case pet
    case slacking
}

/// 系统热压力等级，与 `ProcessInfo.ThermalState` 一一对应。
public enum Thermal: Int, Sendable, Comparable {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3

    public static func < (lhs: Thermal, rhs: Thermal) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 一次采样的输入信号。全部为值类型，可跨线程传递。
public struct MoodSignal: Sendable {
    /// CPU 占用率 0...1
    public var cpu: Double
    /// 内存压力 0...1（wired + compressed 占比）
    public var memoryPressure: Double
    public var thermal: Thermal
    /// 电池电量 0...1；无电池（台式机）时为 nil
    public var batteryLevel: Double?
    public var isCharging: Bool
    /// 当前本地时间的小时数 0...23
    public var hour: Int
    /// 是否处于工作时段（由 WorkSchedule 判定）
    public var isWorkingHours: Bool
    /// 网络空闲持续秒数（摸鱼检测用，v1 暂不参与判定）
    public var networkIdleSeconds: Double

    public init(
        cpu: Double,
        memoryPressure: Double = 0,
        thermal: Thermal = .nominal,
        batteryLevel: Double? = nil,
        isCharging: Bool = false,
        hour: Int = 12,
        isWorkingHours: Bool = true,
        networkIdleSeconds: Double = 0
    ) {
        self.cpu = cpu
        self.memoryPressure = memoryPressure
        self.thermal = thermal
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.hour = hour
        self.isWorkingHours = isWorkingHours
        self.networkIdleSeconds = networkIdleSeconds
    }
}

/// 情绪判定规则。带滞回与连续确认，避免宠物每秒抽搐。
///
/// 判定优先级（从高到低）：过热 → 低电 → 睡眠 → 忙碌 → 充电 → 空闲。
public struct MoodRules: Sendable {
    public struct Thresholds: Sendable {
        public var cpuBusyEnter: Double = 0.70
        public var cpuBusyExit: Double = 0.60
        /// 连续确认次数（1Hz 采样下即秒数）
        public var confirmTicks: Int = 3
        public var batteryTiredBelow: Double = 0.20
        public var sleepHourStart: Int = 23
        public var sleepHourEnd: Int = 7

        public init() {}
    }

    public var thresholds: Thresholds

    private var hotTicks = 0
    private var coolTicks = 0
    private var isBusy = false

    public init(thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
    }

    /// 输入一次采样，返回当前情绪。
    public mutating func mood(for signal: MoodSignal) -> PetMood {
        updateBusy(with: signal.cpu)

        if signal.thermal >= .serious {
            return .overheat
        }
        if !signal.isCharging, let level = signal.batteryLevel,
           level < thresholds.batteryTiredBelow {
            return .tired
        }
        if isSleepTime(hour: signal.hour) {
            return .sleeping
        }
        if isBusy {
            return .busy
        }
        if signal.isCharging {
            return .charging
        }
        return .idle
    }

    /// 当前是否处于忙碌态（供测试与调试面板读取）。
    public var busyState: Bool { isBusy }

    private mutating func updateBusy(with cpu: Double) {
        if cpu >= thresholds.cpuBusyEnter {
            hotTicks += 1
            coolTicks = 0
        } else if cpu <= thresholds.cpuBusyExit {
            coolTicks += 1
            hotTicks = 0
        }

        if !isBusy, hotTicks >= thresholds.confirmTicks {
            isBusy = true
        } else if isBusy, coolTicks >= thresholds.confirmTicks {
            isBusy = false
        }
    }

    private func isSleepTime(hour: Int) -> Bool {
        let start = thresholds.sleepHourStart
        let end = thresholds.sleepHourEnd
        if start <= end {
            return hour >= start && hour < end
        }
        return hour >= start || hour < end
    }
}
