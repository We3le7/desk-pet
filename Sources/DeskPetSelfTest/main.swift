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

// MARK: - 宠物包解析

print("PackParser")

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let jynDirectory = repoRoot.appendingPathComponent("Pets/jyn")

if FileManager.default.fileExists(atPath: jynDirectory.path) {
    do {
        let pack = try PackParser.parse(directory: jynDirectory)
        expectEqual(pack.id, "jyn", "解析出 id")
        expectEqual(pack.adapter, .frames2d, "识别为 frames2d")
        expect(pack.tracks.count >= 20, "轨道数 \(pack.tracks.count) ≥ 20")
        expectEqual(pack.license, "MIT", "保留许可信息")

        if let idle = pack.track(named: "idle") {
            expectEqual(idle.frames.count, 78, "idle 帧数")
            expectEqual(idle.durationsMs.first, 40, "文件名里的帧时长被解析")
            if case .file(let url) = idle.frames[0] {
                expect(url.pathExtension == "webp", "帧指向 webp 文件")
            } else {
                expect(false, "frames2d 的帧应为文件引用")
            }
        } else {
            expect(false, "存在 idle 轨道")
        }
    } catch {
        expect(false, "解析 jyn 失败：\(error)")
    }
} else {
    print("  (跳过：仓库里没有 Pets/jyn)")
}

// 图集包：构造一个最小 manifest 验证行表
do {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("deskpet-selftest-atlas", isDirectory: true)
    try? FileManager.default.removeItem(at: temp)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    let manifest = #"{"id":"probe","displayName":"探针","spriteVersionNumber":2,"spritesheetPath":"sheet.webp"}"#
    try manifest.write(to: temp.appendingPathComponent("pet.json"), atomically: true, encoding: .utf8)
    try Data([0x00]).write(to: temp.appendingPathComponent("sheet.webp"))

    let pack = try PackParser.parse(directory: temp)
    expectEqual(pack.adapter, .atlas, "识别为图集")
    expectEqual(pack.tracks.count, 11, "图集 11 行轨道")
    expectEqual(pack.track(named: "idle")?.frames.count, 6, "idle 行 6 帧")
    expectEqual(pack.track(named: "idle")?.durationsMs.first, 280, "idle 首帧 280ms")
    expectEqual(pack.track(named: "waving")?.durationsMs.last, 280, "waving 末帧 280ms")
    if case .cell(let row, let column) = pack.track(named: "jumping")!.frames[2] {
        expectEqual(row, 4, "jumping 在第 4 行")
        expectEqual(column, 2, "第 3 帧列号")
    } else {
        expect(false, "图集帧应为 cell 引用")
    }
} catch {
    expect(false, "解析图集探针失败：\(error)")
}

print("MoodTrackMap")
expectEqual(MoodTrackMap.candidates(for: .busy, adapter: .frames2d).first, "work", "DSH 忙碌对应 work")
expectEqual(MoodTrackMap.candidates(for: .busy, adapter: .atlas).first, "running", "图集忙碌对应 running")
expectEqual(MoodTrackMap.candidates(for: .pet, adapter: .frames2d).first, "shy", "DSH 摸头对应 shy")
expectEqual(MoodTrackMap.candidates(for: .sleeping, adapter: .atlas).first, "idle", "图集没有睡眠行，退回 idle")

// MARK: - 汇总

print("")
if failures == 0 {
    print("全部通过（\(checks) 项）")
    exit(0)
} else {
    print("失败 \(failures) / \(checks) 项")
    exit(1)
}
