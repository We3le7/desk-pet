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

// MARK: - 上班鼓励器

print("SalaryConfig")

let salary = SalaryConfig()
expect(abs(salary.perSecond - 0.033525) < 0.0001, "默认每秒约 0.0335 元（实际 \(salary.perSecond)）")
expect(abs(salary.perHour - 120.69) < 0.5, "默认时薪约 120.7 元")
expect(abs(salary.perDay - 1146.6) < 5, "在岗一天约 1146 元（9.5h 窗口）")

let withBonus = SalaryConfig(extraMonthsPerYear: 1)
expect(abs(withBonus.effectiveMonthly - 22750) < 0.01, "13 薪折算等效月薪 22750")
expect(withBonus.perSecond > salary.perSecond, "摊入年终后每秒更高")

let longShift = SalaryConfig(startMinuteOfDay: 9 * 60, endMinuteOfDay: 21 * 60)
expect(longShift.perSecond == salary.perSecond, "在岗窗口变长不影响每秒工资")
expect(longShift.perDay > salary.perDay, "但一天能赚更多")

print("EarningsEngine")

var calendar2 = Calendar(identifier: .gregorian)
calendar2.timeZone = TimeZone(identifier: "Asia/Shanghai")!
@MainActor func day(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
    var c = DateComponents()
    c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return calendar2.date(from: c)!
}

let engine = EarningsEngine()
expectEqual(engine.workedSecondsToday(at: day(2026, 11, 18, 9, 29), calendar: calendar2), 0, "09:29 还没开始赚")
expectEqual(engine.workedSecondsToday(at: day(2026, 11, 18, 9, 31), calendar: calendar2), 60, "09:31 已工作 60 秒")
expectEqual(engine.workedSecondsToday(at: day(2026, 11, 18, 19, 30), calendar: calendar2), 9.5 * 3600, "19:30 封顶在岗窗口")
expectEqual(engine.workedSecondsToday(at: day(2026, 11, 21, 12, 0), calendar: calendar2), 0, "周六不赚钱")

let noon = engine.amount(at: day(2026, 11, 18, 12, 0), calendar: calendar2)
expect(abs(noon.workedSeconds - 2.5 * 3600) < 1, "12:00 已工作 2.5 小时")
expect(abs(noon.total - 2.5 * 3600 * salary.perSecond) < 0.01, "金额 = 秒数 × 每秒工资")
expect(noon.isWorking, "工作时段标记为 working")

var paused = EarningsEngine()
paused.pause(at: day(2026, 11, 18, 12, 0), calendar: calendar2)
let frozenTotal = paused.amount(at: day(2026, 11, 18, 12, 0), calendar: calendar2).total
let laterTotal = paused.amount(at: day(2026, 11, 18, 13, 0), calendar: calendar2).total
expectEqual(laterTotal, frozenTotal, "暂停后金额冻结")
expect(paused.amount(at: day(2026, 11, 18, 13, 0), calendar: calendar2).isPaused, "暂停状态可查询")
paused.resume()
expect(paused.amount(at: day(2026, 11, 18, 13, 0), calendar: calendar2).total > frozenTotal, "恢复后按真实时间继续增长")

print("MilestoneTracker")

var tracker = MilestoneTracker(step: 50, bigStep: 500)
expectEqual(tracker.crossed(from: 49, to: 51), [50], "跨过 50")
expectEqual(tracker.crossed(from: 480, to: 1010), [500, 550, 600, 650, 700, 750, 800, 850, 900, 950, 1000], "一次跨多个里程碑")
expectEqual(tracker.crossed(from: 100, to: 100), [], "金额不变不触发")
expectEqual(tracker.crossed(from: 120, to: 100), [], "金额倒退不触发")
expect(tracker.isBig(500), "500 是大里程碑")
expect(!tracker.isBig(550), "550 不是")

print("MoneyFormat")

expectEqual(MoneyFormat.yuan(0), "¥0.00", "零值格式")
expectEqual(MoneyFormat.yuan(1234.5678), "¥1,234.57", "千分位与四舍五入")
expectEqual(MoneyFormat.yuan(999.999), "¥1,000.00", "进位到千位")
expectEqual(MoneyFormat.yuan(12.3), "¥12.30", "补两位小数")
expectEqual(MoneyFormat.perSecond(0.0334), "¥0.033/秒", "小额每秒三位小数")
expectEqual(MoneyFormat.perSecond(0.0335), "¥0.034/秒", "小额四舍五入到三位")
expectEqual(MoneyFormat.perSecond(1.2), "¥1.20/秒", "大额每秒两位小数")

// MARK: - 时间设置边界

print("时间设置")

// 分钟必须对齐到 5 分钟刻度（否则"设置里显示 30、实际按 32 算"）
let odd = SalaryConfig(startMinuteOfDay: 9 * 60 + 32, endMinuteOfDay: 18 * 60 + 58).normalized()
expectEqual(odd.startMinuteOfDay, 9 * 60 + 30, "上班时间对齐到 5 分钟刻度")
expectEqual(odd.endMinuteOfDay, 19 * 60, "下班时间对齐到 5 分钟刻度")

let clamped = SalaryConfig(startMinuteOfDay: -30, endMinuteOfDay: 3000).normalized()
expectEqual(clamped.startMinuteOfDay, 0, "越界时间被夹到 0")
expect(clamped.endMinuteOfDay <= 23 * 60 + 55, "越界时间被夹到当日上限")

// 跨零点夜班
let nightEarnings = EarningsEngine(config: SalaryConfig(
    monthlyNet: 21000,
    startMinuteOfDay: 22 * 60,
    endMinuteOfDay: 6 * 60
))
expectEqual(nightEarnings.config.windowSeconds, 8 * 3600, "夜班窗口 8 小时")
expectEqual(nightEarnings.workedSecondsToday(at: day(2026, 11, 18, 23, 0), calendar: calendar2), 3600, "夜班 23:00 已工作 1 小时")
expectEqual(nightEarnings.workedSecondsToday(at: day(2026, 11, 18, 5, 0), calendar: calendar2), 7 * 3600, "夜班 05:00 已工作 7 小时")
expectEqual(nightEarnings.workedSecondsToday(at: day(2026, 11, 18, 7, 0), calendar: calendar2), 8 * 3600, "夜班 07:00 已下班，但仍显示整晚总额")
expectEqual(nightEarnings.workedSecondsToday(at: day(2026, 11, 18, 12, 0), calendar: calendar2), 8 * 3600, "夜班中午仍显示整晚总额")
expectEqual(nightEarnings.workedSecondsToday(at: day(2026, 11, 18, 21, 0), calendar: calendar2), 8 * 3600, "夜班 21:00 仍显示昨晚整晚（新班次 22:00 才开始）")
expectEqual(nightEarnings.workedSecondsToday(at: day(2026, 11, 18, 22, 30), calendar: calendar2), 1800, "夜班 22:30 新班次重新计起")

// 起止相同 = 没有在岗窗口
let zeroWindow = SalaryConfig(startMinuteOfDay: 9 * 60, endMinuteOfDay: 9 * 60)
expectEqual(zeroWindow.windowSeconds, 0, "起止相同窗口为 0")
expectEqual(EarningsEngine(config: zeroWindow).workedSecondsToday(at: day(2026, 11, 18, 10, 0), calendar: calendar2), 0, "窗口为 0 时不赚钱")

// 午休扣除后不会为负
let lunch = EarningsEngine(config: SalaryConfig(lunchBreakMinutes: 90))
let early = lunch.workedSecondsToday(at: day(2026, 11, 18, 10, 0), calendar: calendar2)
expectEqual(early, 0, "上班半小时内扣完午休仍为 0")

// MARK: - 汇总

print("")
if failures == 0 {
    print("全部通过（\(checks) 项）")
    exit(0)
} else {
    print("失败 \(failures) / \(checks) 项")
    exit(1)
}
