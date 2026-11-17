import AppKit
import SwiftUI

/// 设置窗口（独立于宠物悬浮窗，可聚焦）。
@MainActor
final class SettingsWindowController {
    private let controller: EarningsController
    private let appearance: AppearanceStore
    private let catalog: PetsCatalog
    private let ui: SettingsUIState
    private var window: NSWindow?

    init(controller: EarningsController, appearance: AppearanceStore, catalog: PetsCatalog, ui: SettingsUIState) {
        self.controller = controller
        self.appearance = appearance
        self.catalog = catalog
        self.ui = ui
    }

    /// 打开设置并切到指定标签页
    func show(tab: SettingsTab? = nil) {
        if let tab { ui.tab = tab }
        show()
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingView(rootView: SettingsView(
            controller: controller,
            appearance: appearance,
            catalog: catalog,
            ui: ui
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 600)

        let window = NSWindow(
            contentRect: hosting.bounds,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DeskPet 设置"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
