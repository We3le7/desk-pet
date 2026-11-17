import AppKit
import SwiftUI

/// 设置窗口（独立于宠物悬浮窗，可聚焦）。
@MainActor
final class SettingsWindowController {
    private let controller: EarningsController
    private var window: NSWindow?

    init(controller: EarningsController) {
        self.controller = controller
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingView(rootView: SettingsView(controller: controller))
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 380)

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
