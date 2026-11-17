import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petPanel: PetPanel?
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = PetPanel()
        panel.orderFrontRegardless()
        petPanel = panel

        statusBar = StatusBarController(panel: panel)
    }

    /// 关掉窗口不退出：这是个常驻工具，退出走菜单栏。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
