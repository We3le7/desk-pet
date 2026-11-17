import Foundation

/// 工作时段。默认周一至周五 09:30–19:00。
public struct WorkSchedule: Sendable, Equatable {
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int
    /// `Calendar`  weekday：1 = 周日，2 = 周一 … 7 = 周六
    public var workdays: Set<Int>

    public init(
        startHour: Int = 9,
        startMinute: Int = 30,
        endHour: Int = 19,
        endMinute: Int = 0,
        workdays: Set<Int> = [2, 3, 4, 5, 6]
    ) {
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.workdays = workdays
    }

    public func isWorking(at date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday,
              let hour = components.hour,
              let minute = components.minute,
              workdays.contains(weekday)
        else { return false }

        let now = hour * 60 + minute
        let start = startHour * 60 + startMinute
        let end = endHour * 60 + endMinute

        if start <= end {
            return now >= start && now < end
        }
        // 跨零点的工作时段（例如夜班 22:00–06:00）
        return now >= start || now < end
    }
}

public extension MoodSignal {
    /// 把一次系统采样折算成情绪判定所需的信号。
    static func make(
        from snapshot: SystemSnapshot,
        schedule: WorkSchedule,
        calendar: Calendar = .current
    ) -> MoodSignal {
        let hour = calendar.component(.hour, from: snapshot.timestamp)
        return MoodSignal(
            cpu: snapshot.cpuUsage,
            memoryPressure: snapshot.memoryPressure,
            thermal: snapshot.thermal,
            batteryLevel: snapshot.batteryLevel,
            isCharging: snapshot.isCharging,
            hour: hour,
            isWorkingHours: schedule.isWorking(at: snapshot.timestamp, calendar: calendar),
            networkIdleSeconds: 0
        )
    }
}
