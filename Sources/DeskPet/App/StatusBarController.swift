import AppKit
import DeskPetCore

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private weak var panel: PetPanel?
    private var moodItem: NSMenuItem?
    private var lastTitleUpdate: Date = .distantPast
    private var lastTitle: String = ""
    private var lastMood: PetMood?
    var onToggleDebugPanel: (() -> Void)?

    init(panel: PetPanel) {
        self.panel = panel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "pawprint.fill",
                accessibilityDescription: "DeskPet"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "DeskPet · 桌面状态宠物"
        }

        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let show = NSMenuItem(title: "显示宠物", action: #selector(showPet(_:)), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let clickThrough = NSMenuItem(
            title: "点击穿透",
            action: #selector(toggleClickThrough(_:)),
            keyEquivalent: ""
        )
        clickThrough.target = self
        clickThrough.state = (panel?.ignoresMouseEvents ?? false) ? .on : .off
        menu.addItem(clickThrough)

        let recenter = NSMenuItem(title: "回到右下角", action: #selector(resetPosition(_:)), keyEquivalent: "")
        recenter.target = self
        menu.addItem(recenter)

        menu.addItem(.separator())

        let debug = NSMenuItem(title: "指标面板…", action: #selector(showDebugPanel(_:)), keyEquivalent: "d")
        debug.target = self
        menu.addItem(debug)

        let mood = NSMenuItem(title: "情绪：—", action: nil, keyEquivalent: "")
        mood.isEnabled = false
        moodItem = mood
        menu.addItem(mood)

        menu.addItem(.separator())

        let version = NSMenuItem(title: "DeskPet 0.1.0（M1）", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        let quit = NSMenuItem(title: "退出", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    /// 状态栏显示 CPU 占用与情绪。文字更新节流到 5 秒：菜单栏重排比想象中贵。
    func update(snapshot: SystemSnapshot, mood: PetMood) {
        let cpu = Humanize.percent(snapshot.cpuUsage)
        let title = " \(cpu)"

        if moodItem?.title != "情绪：\(mood.rawValue) · CPU \(cpu)" {
            moodItem?.title = "情绪：\(mood.rawValue) · CPU \(cpu)"
        }

        if ProcessInfo.processInfo.environment["DESKPET_NO_STATUSBAR_TEXT"] == "1" { return }

        // 菜单栏改文字要经 MenuBarAgent 重排布局，实测每次约 18ms；
        // 必须**纯按时间**节流，不能用「文字变了才更新」——CPU 每秒都在变，那等于没节流。
        let now = Date()
        let moodChanged = mood != lastMood
        guard moodChanged || now.timeIntervalSince(lastTitleUpdate) >= 5 else { return }
        lastTitleUpdate = now
        lastTitle = title
        statusItem.button?.title = title
        statusItem.button?.imagePosition = .imageLeading
        _ = lastMood
        lastMood = mood
    }

    @objc private func showPet(_ sender: Any?) {
        panel?.orderFrontRegardless()
    }

    @objc private func toggleClickThrough(_ sender: Any?) {
        guard let panel else { return }
        panel.toggleClickThrough(nil)
        if let item = sender as? NSMenuItem {
            item.state = panel.ignoresMouseEvents ? .on : .off
        }
    }

    @objc private func resetPosition(_ sender: Any?) {
        panel?.resetPosition(nil)
    }

    @objc private func showDebugPanel(_ sender: Any?) {
        onToggleDebugPanel?()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
