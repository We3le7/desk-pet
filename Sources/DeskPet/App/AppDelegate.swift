import AppKit
import DeskPetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petPanel: PetPanel?
    private var statusBar: StatusBarController?
    private var metrics: MetricsService?
    private var debugWindow: DebugWindowController?
    private let state = PetAppState()
    private let catalog = PetsCatalog()
    private let settingsUI = SettingsUIState()
    private var earnings: EarningsController?
    private var settingsWindow: SettingsWindowController?
    private var hotKey: HotKeyManager?
    private let appearance = AppearanceStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = PetPanel()
        panel.orderFrontRegardless()
        petPanel = panel

        let statusBar = StatusBarController(panel: panel)
        self.statusBar = statusBar

        let debugWindow = DebugWindowController(state: state)
        self.debugWindow = debugWindow
        statusBar.onToggleDebugPanel = { [weak debugWindow] in
            debugWindow?.toggle()
        }

        let earnings = EarningsController()
        earnings.bind(panel: panel)
        earnings.onMilestone = { [weak panel] _, isBig in
            panel?.burstCoins(isBig: isBig)
        }
        self.earnings = earnings
        earnings.start()

        let settingsWindow = SettingsWindowController(
            controller: earnings,
            appearance: appearance,
            catalog: catalog,
            ui: settingsUI
        )
        self.settingsWindow = settingsWindow

        catalog.onSelect = { [weak panel, weak statusBar] pack in
            panel?.setPack(pack)
            statusBar?.updatePetTitle(pack?.displayName ?? "内置")
        }
        catalog.reload()

        // 外观：显示 / 大小 / 轮播
        panel.setVisible(appearance.isPetVisible)
        appearance.onVisibilityChange = { [weak panel] visible in
            panel?.setVisible(visible)
        }
        panel.setPetScale(appearance.petScale)
        panel.setRotationEnabled(appearance.rotateActions)
        appearance.onScaleChange = { [weak panel] scale in
            panel?.setPetScale(scale)
        }
        appearance.onRotationChange = { [weak panel] enabled in
            panel?.setRotationEnabled(enabled)
        }

        // 单击宠物 = 弹出与菜单栏相同的菜单（不是直接开设置）
        panel.onClick = { [weak panel, weak statusBar] point in
            guard let panel, let contentView = panel.contentView else { return }
            statusBar?.popUpMenu(at: point, in: contentView)
        }

        statusBar.onOpenPetSettings = { [weak settingsWindow] in
            settingsWindow?.show(tab: .pet)
        }
        statusBar.onTogglePause = { [weak earnings] in earnings?.togglePause() }
        statusBar.onToggleMoney = { [weak earnings] in earnings?.toggleMoneyVisibility() }
        statusBar.onOpenSettings = { [weak settingsWindow] in
            settingsWindow?.show(tab: .earnings)
        }

        hotKey = HotKeyManager { [weak earnings] in
            earnings?.toggleMoneyVisibility()
        }
        hotKey?.register()

        if ProcessInfo.processInfo.environment["DESKPET_CHECK_INPUT"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak settingsWindow] in
                settingsWindow?.show(tab: .earnings)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    settingsWindow?.diagnoseKeyboardFocus()
                }
            }
        }

        if let tabEnv = ProcessInfo.processInfo.environment["DESKPET_OPEN_SETTINGS"] {
            let tab: SettingsTab = tabEnv == "earnings" ? .earnings : .pet
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak settingsWindow] in
                print("[demo] 打开设置 \(tab)")
                fflush(stdout)
                settingsWindow?.show(tab: tab)
            }
        }

        if ProcessInfo.processInfo.environment["DESKPET_DEMO_COINS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak panel] in
                print("[demo] 触发金币动画")
                fflush(stdout)
                panel?.burstCoins(isBig: true)
            }
        }

        let metrics = MetricsService(state: state)
        metrics.bind(panel: panel, statusBar: statusBar)
        self.metrics = metrics
        metrics.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        metrics?.stop()
        earnings?.stop()
    }

    /// 关掉窗口不退出：这是个常驻工具，退出走菜单栏。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
