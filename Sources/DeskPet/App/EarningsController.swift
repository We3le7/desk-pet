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
            engine.config = config
            persistConfig()
            recompute(notify: false)
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
        let loaded = Self.loadConfig(from: defaults)
        self.config = loaded
        self.engine = EarningsEngine(config: loaded)
        self.amount = engine.amount(at: Date())
        self.lastTickSecond = Int(Date().timeIntervalSince1970)
        self.lastTotalAtSecond = self.amount.total
    }

    func bind(panel: PetPanel) {
        self.panel = panel
        applyVisibility()
        updateLabel()
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
        recompute(notify: false)
    }

    func toggleMoneyVisibility() {
        isMoneyVisible.toggle()
    }

    // MARK: - 刷新

    private func recompute(notify: Bool) {
        let now = Date()
        let next = engine.amount(at: now)
        let previous = amount

        amount = next
        isPaused = next.isPaused
        updateLabel()

        // 每秒一次的跳动特效
        let second = Int(now.timeIntervalSince1970)
        if second != lastTickSecond {
            let delta = next.total - lastTotalAtSecond
            lastTickSecond = second
            lastTotalAtSecond = next.total
            if delta > 0, !next.isPaused, isMoneyVisible,
               ProcessInfo.processInfo.environment["DESKPET_NO_TICK"] != "1" {
                panel?.playMoneyTick(delta: delta)
                if ProcessInfo.processInfo.environment["DESKPET_DEBUG"] == "1" {
                    print("[money] +\(String(format: "%.4f", delta)) → \(MoneyFormat.yuan(next.total))")
                    fflush(stdout)
                }
            }
        }

        guard notify, next.total > previous.total + 0.0001 else { return }
        let milestones = tracker.crossed(from: previous.total, to: next.total)
        guard let last = milestones.last else { return }
        let isBig = milestones.count > 1 || tracker.isBig(last)
        onMilestone?(last, isBig)
    }

    private func updateLabel() {
        let text: String
        if isPaused {
            text = MoneyFormat.yuan(amount.total) + " · 暂停"
        } else {
            text = MoneyFormat.yuan(amount.total)
        }
        panel?.setMoneyText(isMoneyVisible ? text : "***")
    }

    private func applyVisibility() {
        panel?.setMoneyVisible(isMoneyVisible)
        updateLabel()
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
