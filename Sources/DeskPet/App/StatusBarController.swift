import AppKit
import DeskPetCore

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private weak var panel: PetPanel?

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

        let version = NSMenuItem(title: "DeskPet 0.1.0（M0）", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        let quit = NSMenuItem(title: "退出", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
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

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
