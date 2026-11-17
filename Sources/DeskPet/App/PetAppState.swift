import AppKit
import DeskPetCore
import Foundation

/// UI 的唯一状态源。@MainActor 隔离，所有变更走主线程。
@MainActor
final class PetAppState: ObservableObject {
    @Published var snapshot: SystemSnapshot?
    @Published var mood: PetMood = .idle

    var cpuText: String {
        guard let snapshot else { return "—" }
        return Humanize.precisePercent(snapshot.cpuUsage)
    }

    var memoryText: String {
        guard let snapshot else { return "—" }
        return "\(Humanize.bytes(snapshot.memoryUsedBytes)) / \(Humanize.bytes(snapshot.memoryTotalBytes))"
            + "（压力 \(Humanize.percent(snapshot.memoryPressure))）"
    }

    var batteryText: String {
        guard let snapshot else { return "—" }
        guard let level = snapshot.batteryLevel else { return "无电池（台式机）" }
        let percent = Humanize.percent(level)
        if snapshot.isCharging { return "\(percent) · 充电中" }
        return snapshot.isOnAC ? "\(percent) · 已接电源" : "\(percent) · 电池供电"
    }

    var networkText: String {
        guard let snapshot else { return "—" }
        return "↓ \(Humanize.rate(snapshot.downloadBytesPerSecond))   ↑ \(Humanize.rate(snapshot.uploadBytesPerSecond))"
    }

    var diskText: String {
        guard let snapshot else { return "—" }
        return "\(Humanize.bytes(snapshot.diskFreeBytes)) 可用 / \(Humanize.bytes(snapshot.diskTotalBytes))"
    }

    var thermalText: String {
        guard let snapshot else { return "—" }
        let thermal: String
        switch snapshot.thermal {
        case .nominal: thermal = "正常"
        case .fair: thermal = "偏热"
        case .serious: thermal = "很热"
        case .critical: thermal = "过热"
        }
        return snapshot.isLowPowerMode ? "\(thermal) · 低电量模式" : thermal
    }

    var frontmostText: String { snapshot?.frontmostApp ?? "—" }

    var moodText: String {
        switch mood {
        case .idle: return "idle · 空闲"
        case .busy: return "busy · 忙碌"
        case .overheat: return "overheat · 过热"
        case .tired: return "tired · 疲惫"
        case .charging: return "charging · 充电"
        case .sleeping: return "sleeping · 睡觉"
        case .celebrate: return "celebrate · 庆祝"
        case .pet: return "pet · 被摸头"
        case .slacking: return "slacking · 摸鱼"
        }
    }

    var updatedAtText: String {
        guard let snapshot else { return "尚未采样" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: snapshot.timestamp)
    }
}

/// 指标采集 → 情绪判定 → 推给窗口与菜单栏。
/// 前台应用只在切换时更新：`NSWorkspace` 的每次查询都会走一次 XPC，1Hz 轮询太浪费。
@MainActor
final class FrontmostTracker {
    private(set) var name: String?
    private var observer: NSObjectProtocol?  // 进程生命周期内不注销

    init() {
        name = NSWorkspace.shared.frontmostApplication?.localizedName
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let localizedName = app?.localizedName
            Task { @MainActor in
                self?.name = localizedName
            }
        }
    }

}

@MainActor
final class MetricsService {
    private let state: PetAppState
    private var sampler: MetricsSampler?
    private var rules = MoodRules()
    private var schedule = WorkSchedule()

    private weak var panel: PetPanel?
    private weak var statusBar: StatusBarController?
    private let frontmost = FrontmostTracker()
    private let isDebugLogging = ProcessInfo.processInfo.environment["DESKPET_DEBUG"] == "1"
    private let logTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init(state: PetAppState) {
        self.state = state
    }

    func bind(panel: PetPanel, statusBar: StatusBarController) {
        self.panel = panel
        self.statusBar = statusBar
    }

    func start() {
        let env = ProcessInfo.processInfo.environment
        let interval = env["DESKPET_INTERVAL"].flatMap(Double.init) ?? 1.0
        let config = MetricsSampler.Config(interval: interval)
        let sampler = MetricsSampler(config: config) { [weak self] snapshot in
            Task { @MainActor in
                self?.handle(snapshot)
            }
        }
        self.sampler = sampler
        sampler.start()
    }

    func stop() {
        sampler?.stop()
        sampler = nil
    }

    private func handle(_ snapshot: SystemSnapshot) {
        var snapshot = snapshot
        snapshot.frontmostApp = frontmost.name

        let signal = MoodSignal.make(from: snapshot, schedule: schedule)
        let mood = rules.mood(for: signal)

        state.snapshot = snapshot
        if state.mood != mood {
            state.mood = mood
        }

        if isDebugLogging {
            print(String(
                format: "[%@] cpu=%5.1f%%  mem=%@  net=%@  mood=%@",
                logTimeFormatter.string(from: snapshot.timestamp),
                snapshot.cpuUsage * 100,
                Humanize.bytes(snapshot.memoryUsedBytes),
                Humanize.rate(snapshot.downloadBytesPerSecond),
                mood.rawValue
            ))
            fflush(stdout)
        }

        panel?.updateMood(mood)
        statusBar?.update(snapshot: snapshot, mood: mood)
    }
}
