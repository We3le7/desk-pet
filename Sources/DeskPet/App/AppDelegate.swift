import AppKit
import DeskPetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petPanel: PetPanel?
    private var statusBar: StatusBarController?
    private var metrics: MetricsService?
    private var debugWindow: DebugWindowController?
    private let state = PetAppState()
    private var packs: [PetPack] = []
    private static let selectedPackKey = "pet.selected.id"

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

        statusBar.onSelectPack = { [weak self] id in
            self?.selectPack(id: id)
        }
        loadPacks()

        let metrics = MetricsService(state: state)
        metrics.bind(panel: panel, statusBar: statusBar)
        self.metrics = metrics
        metrics.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        metrics?.stop()
    }

    // MARK: - 宠物包

    /// 解析宠物包要扫上千个文件，放后台做，避免拖慢启动。
    private func loadPacks() {
        Task.detached(priority: .userInitiated) { [weak self] in
            let packs = PetLibrary().discover()
            await MainActor.run {
                guard let self else { return }
                self.packs = packs
                let storedID = UserDefaults.standard.string(forKey: Self.selectedPackKey)
                if let storedID, packs.contains(where: { $0.id == storedID }) {
                    self.selectPack(id: storedID, persist: false)
                } else {
                    UserDefaults.standard.removeObject(forKey: Self.selectedPackKey)
                    self.petPanel?.setPack(nil)
                }
                self.statusBar?.rebuildPetSubmenu(
                    packs: packs.map {
                        PetPackDescriptor(
                            id: $0.id,
                            displayName: $0.displayName,
                            adapter: $0.adapter,
                            root: $0.root,
                            trackCount: $0.tracks.count,
                            detail: $0.license ?? "\($0.tracks.count) 轨"
                        )
                    },
                    selectedID: storedID
                )
            }
        }
    }

    private func selectPack(id: String?, persist: Bool = true) {
        if let id, let pack = packs.first(where: { $0.id == id }) {
            petPanel?.setPack(pack)
            if persist {
                UserDefaults.standard.set(id, forKey: Self.selectedPackKey)
            }
        } else {
            petPanel?.setPack(nil)
            if persist {
                UserDefaults.standard.removeObject(forKey: Self.selectedPackKey)
            }
        }
        statusBar?.rebuildPetSubmenu(
            packs: packs.map {
                PetPackDescriptor(
                    id: $0.id,
                    displayName: $0.displayName,
                    adapter: $0.adapter,
                    root: $0.root,
                    trackCount: $0.tracks.count,
                    detail: $0.license ?? "\($0.tracks.count) 轨"
                )
            },
            selectedID: id
        )
    }

    /// 关掉窗口不退出：这是个常驻工具，退出走菜单栏。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
