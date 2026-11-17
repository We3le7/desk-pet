import AppKit
import SwiftUI

/// 指标调试面板窗口。独立于宠物悬浮窗，可聚焦、可关闭。
@MainActor
final class DebugWindowController {
    private let state: PetAppState
    private var window: NSWindow?

    init(state: PetAppState) {
        self.state = state
    }

    func toggle() {
        if let window, window.isVisible {
            window.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingView(rootView: DebugPanelView(state: state))
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: 320)

        let window = NSWindow(
            contentRect: hosting.bounds,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DeskPet 指标"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.level = NSWindow.Level.floating
        return window
    }
}
