import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petPanel: PetPanel?
    private var statusBar: StatusBarController?
    private var metrics: MetricsService?
    private var debugWindow: DebugWindowController?
    private let state = PetAppState()

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

        let metrics = MetricsService(state: state)
        metrics.bind(panel: panel, statusBar: statusBar)
        self.metrics = metrics
        metrics.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        metrics?.stop()
    }

    /// 关掉窗口不退出：这是个常驻工具，退出走菜单栏。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
