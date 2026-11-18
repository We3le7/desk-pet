import AppKit
import Carbon.HIToolbox
import DeskPetCore
import Foundation

/// 上班鼓励器控制器：按 8Hz 刷新金额标签，跨里程碑时触发金币。
@MainActor
final class EarningsController: ObservableObject {
    @Published private(set) var amount: EarningsAmount
    @Published private(set) var isPaused = false
    @Published var isMoneyVisible = true {
        didSet { applyVisibility() }
    }
    @Published var config: SalaryConfig {
        didSet {
            let normalized = config.normalized()
            if normalized != config {
                config = normalized
                return
            }
            engine.config = config
            persistConfig()
            recompute(notify: false, forcePublish: true)
        }
    }

    /// 里程碑回调：(金额, 是否大里程碑)
    var onMilestone: ((Double, Bool) -> Void)?

    private var engine: EarningsEngine
    private var tracker = MilestoneTracker()
    private var lastTickSecond = 0
    private var lastTotalAtSecond: Double = 0
    private var timer: DispatchSourceTimer?
    private weak var panel: PetPanel?
    private let defaults: UserDefaults

    private static let configKey = "earnings.config"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = Self.loadConfig(from: defaults).normalized()
        self.config = loaded
        self.engine = EarningsEngine(config: loaded)
        self.amount = engine.amount(at: Date())
        self.lastTickSecond = Int(Date().timeIntervalSince1970)
        self.lastTotalAtSecond = self.amount.total
    }

    func bind(panel: PetPanel) {
        self.panel = panel
        applyVisibility()
        updateLabel(amount: amount)
    }

    func start() {
        let hz = ProcessInfo.processInfo.environment["DESKPET_LABEL_HZ"].flatMap(Double.init) ?? 5
        let interval = max(Int(1000.0 / max(hz, 1)), 100)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(interval), leeway: .milliseconds(30))
        timer.setEventHandler { [weak self] in
            self?.recompute(notify: true)
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func togglePause() {
        let now = Date()
        engine.togglePause(at: now)
        isPaused = engine.isPaused
        recompute(notify: false, forcePublish: true)
    }

    func toggleMoneyVisibility() {
        isMoneyVisible.toggle()
    }

    // MARK: - 刷新

    private func recompute(notify: Bool, forcePublish: Bool = false) {
        let now = Date()
        let next = engine.amount(at: now)
        let previous = amount

        // 标签按 5Hz 直接改 CATextLayer，不走 SwiftUI
        updateLabel(amount: next)

        let second = Int(now.timeIntervalSince1970)
        let secondChanged = second != lastTickSecond

        // 只在整秒变化时才 publish：否则 SwiftUI 设置页每秒重建 5 次，
        // 输入框和选择器的编辑状态会被冲掉。
        if secondChanged || forcePublish {
            amount = next
        }
        if isPaused != next.isPaused {
            isPaused = next.isPaused
        }

        guard secondChanged else { return }

        let delta = next.total - lastTotalAtSecond
        lastTickSecond = second
        lastTotalAtSecond = next.total
        guard notify, delta > 0, !next.isPaused, isMoneyVisible,
              ProcessInfo.processInfo.environment["DESKPET_NO_TICK"] != "1"
        else { return }

        panel?.playMoneyTick(delta: delta)
        if ProcessInfo.processInfo.environment["DESKPET_DEBUG"] == "1" {
            print("[money] +\(String(format: "%.4f", delta)) → \(MoneyFormat.yuan(next.total))")
            fflush(stdout)
        }

        guard next.total > previous.total + 0.0001 else { return }
        let milestones = tracker.crossed(from: previous.total, to: next.total)
        guard let last = milestones.last else { return }
        let isBig = milestones.count > 1 || tracker.isBig(last)
        onMilestone?(last, isBig)
    }

    private func updateLabel(amount value: EarningsAmount) {
        let text: String
        if value.isPaused {
            text = MoneyFormat.yuan(value.total) + " · 暂停"
        } else {
            text = MoneyFormat.yuan(value.total)
        }
        panel?.setMoneyText(isMoneyVisible ? text : "***")
    }

    private func applyVisibility() {
        panel?.setMoneyVisible(isMoneyVisible)
        updateLabel(amount: amount)
    }

    // MARK: - 持久化

    private func persistConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Self.configKey)
    }

    private static func loadConfig(from defaults: UserDefaults) -> SalaryConfig {
        guard let data = defaults.data(forKey: configKey),
              let config = try? JSONDecoder().decode(SalaryConfig.self, from: data)
        else {
            return SalaryConfig()
        }
        return config
    }
}
