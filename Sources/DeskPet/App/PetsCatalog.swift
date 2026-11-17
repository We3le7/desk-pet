import AppKit
import DeskPetCore
import Foundation

/// 宠物包目录：负责发现本机宠物包、记住当前选中项，并通知外部刷新。
@MainActor
final class PetsCatalog: ObservableObject {
    @Published private(set) var packs: [PetPack] = []
    @Published private(set) var selectedID: String?

    /// 选中项变化时回调（nil 表示使用内置矢量宠物）
    var onSelect: ((PetPack?) -> Void)?

    private let defaults: UserDefaults
    private static let selectedKey = "pet.selected.id"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedID = defaults.string(forKey: Self.selectedKey)
    }

    /// 解析宠物包要扫上千个文件，放后台做。
    func reload() {
        let stored = selectedID
        let defaults = defaults
        Task {
            let discovered = await Task.detached(priority: .userInitiated) {
                PetLibrary().discover()
            }.value

            self.packs = discovered
            if let stored, discovered.contains(where: { $0.id == stored }) {
                self.selectedID = stored
            } else {
                self.selectedID = nil
                defaults.removeObject(forKey: Self.selectedKey)
            }
            self.onSelect?(self.currentPack)
        }
    }

    var currentPack: PetPack? {
        guard let selectedID else { return nil }
        return packs.first { $0.id == selectedID }
    }

    var selectedName: String {
        currentPack?.displayName ?? "内置（代码绘制）"
    }

    func select(_ id: String?) {
        if let id, packs.contains(where: { $0.id == id }) {
            selectedID = id
            defaults.set(id, forKey: Self.selectedKey)
        } else {
            selectedID = nil
            defaults.removeObject(forKey: Self.selectedKey)
        }
        onSelect?(currentPack)
    }
}
