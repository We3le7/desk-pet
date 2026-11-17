import Foundation
import DeskPetCore

// 极简断言框架：本机 CLT 没有 XCTest / Swift Testing，故自带。
// 用法：swift run DeskPetSelfTest，退出码非 0 即失败。

var failures = 0
var checks = 0

@MainActor
func expect(_ condition: Bool, _ message: String) {
    checks += 1
    if condition {
        print("  ok   \(message)")
    } else {
        failures += 1
        print("  FAIL \(message)")
    }
}

@MainActor
func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    expect(lhs == rhs, "\(message)（实际 \(lhs)，期望 \(rhs)）")
}

// MARK: - MoodRules

print("MoodRules")

var rules = MoodRules()
expectEqual(rules.mood(for: MoodSignal(cpu: 0.10, hour: 12)), .idle, "低 CPU 空闲")

// 连续 3 次超过进入阈值才变 busy
expectEqual(rules.mood(for: MoodSignal(cpu: 0.75, hour: 12)), .idle, "第一次超阈值仍为 idle（未确认）")
expectEqual(rules.mood(for: MoodSignal(cpu: 0.75, hour: 12)), .idle, "第二次超阈值仍为 idle（未确认）")
expectEqual(rules.mood(for: MoodSignal(cpu: 0.75, hour: 12)), .busy, "连续三次超阈值进入 busy")

// 滞回：跌到退出阈值以上、进入阈值以下时不应立刻退出
expectEqual(rules.mood(for: MoodSignal(cpu: 0.65, hour: 12)), .busy, "回落到 0.65 仍在滞回区，保持 busy")
expectEqual(rules.mood(for: MoodSignal(cpu: 0.50, hour: 12)), .busy, "首次跌破退出阈值仍 busy")
expectEqual(rules.mood(for: MoodSignal(cpu: 0.50, hour: 12)), .busy, "第二次跌破退出阈值仍 busy")
expectEqual(rules.mood(for: MoodSignal(cpu: 0.50, hour: 12)), .idle, "连续三次跌破退出阈值回到 idle")

// 优先级
var overheat = MoodRules()
expectEqual(
    overheat.mood(for: MoodSignal(cpu: 0.95, thermal: .serious, hour: 12)),
    .overheat,
    "热压力升高时过热优先于忙碌"
)

var tired = MoodRules()
expectEqual(
    tired.mood(for: MoodSignal(cpu: 0.10, batteryLevel: 0.10, isCharging: false, hour: 12)),
    .tired,
    "低电且未充电为 tired"
)
expectEqual(
    tired.mood(for: MoodSignal(cpu: 0.10, batteryLevel: 0.10, isCharging: true, hour: 12)),
    .charging,
    "低电但正在充电时优先展示 charging"
)

var night = MoodRules()
expectEqual(night.mood(for: MoodSignal(cpu: 0.05, hour: 2)), .sleeping, "凌晨 2 点睡觉")
expectEqual(night.mood(for: MoodSignal(cpu: 0.05, hour: 23)), .sleeping, "23 点睡觉")
expectEqual(night.mood(for: MoodSignal(cpu: 0.05, hour: 7)), .idle, "7 点起床")
expectEqual(night.mood(for: MoodSignal(cpu: 0.05, hour: 8)), .idle, "8 点清醒")

var deskTop = MoodRules()
expectEqual(deskTop.mood(for: MoodSignal(cpu: 0.05, batteryLevel: nil, hour: 12)), .idle, "无电池设备不受低电影响")

// MARK: - Humanize

print("Humanize")

expectEqual(Humanize.bytes(512), "512 B", "字节格式化：小于 1KB")
expectEqual(Humanize.bytes(1536), "1.5 KB", "字节格式化：KB")
expectEqual(Humanize.bytes(3 * 1024 * 1024), "3.0 MB", "字节格式化：MB")
expectEqual(Humanize.bytes(3 * 1024 * 1024 * 1024), "3.0 GB", "字节格式化：GB")
expectEqual(Humanize.rate(0), "0 B/s", "速率为 0")
expectEqual(Humanize.rate(2048), "2.0 KB/s", "速率格式化")
expectEqual(Humanize.percent(0.423), "42%", "百分比取整")
expectEqual(Humanize.precisePercent(0.4231), "42.3%", "百分比一位小数")
expectEqual(Humanize.percent(1.4), "100%", "百分比上限截断")
expectEqual(Humanize.percent(-0.2), "0%", "百分比下限截断")

// MARK: - WorkSchedule

print("WorkSchedule")

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!

@MainActor
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return calendar.date(from: components)!
}

let schedule = WorkSchedule()  // 默认 09:30-19:00，周一到周五

expect(schedule.isWorking(at: date(2026, 11, 18, 10, 0), calendar: calendar), "周三 10:00 在工作时段")
expect(!schedule.isWorking(at: date(2026, 11, 18, 9, 29), calendar: calendar), "周三 09:29 还没上班")
expect(schedule.isWorking(at: date(2026, 11, 18, 9, 30), calendar: calendar), "周三 09:30 整点算上班")
expect(schedule.isWorking(at: date(2026, 11, 18, 18, 59), calendar: calendar), "周三 18:59 还在上班")
expect(!schedule.isWorking(at: date(2026, 11, 18, 19, 0), calendar: calendar), "周三 19:00 已下班")
expect(!schedule.isWorking(at: date(2026, 11, 21, 10, 0), calendar: calendar), "周六 10:00 不上班")
expect(!schedule.isWorking(at: date(2026, 11, 22, 10, 0), calendar: calendar), "周日 10:00 不上班")

let nightShift = WorkSchedule(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0)
expect(nightShift.isWorking(at: date(2026, 11, 18, 23, 0), calendar: calendar), "夜班 23:00 在班")
expect(nightShift.isWorking(at: date(2026, 11, 18, 5, 59), calendar: calendar), "夜班 05:59 在班")
expect(!nightShift.isWorking(at: date(2026, 11, 18, 6, 0), calendar: calendar), "夜班 06:00 下班")

// MARK: - 汇总

print("")
if failures == 0 {
    print("全部通过（\(checks) 项）")
    exit(0)
} else {
    print("失败 \(failures) / \(checks) 项")
    exit(1)
}
