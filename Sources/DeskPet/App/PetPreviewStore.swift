import AppKit
import DeskPetCore
import Foundation

/// 宠物预览状态：缩略图缓存 + 当前悬停/选中的宠物。
@MainActor
final class PetPreviewStore: ObservableObject {
    static let shared = PetPreviewStore()

    /// key 为 pack.id，内置宠物用 `PetThumbnail.builtinKey`
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    /// 悬停中的宠物（用于预览区，nil 表示内置）
    @Published var hoveredID: String?
    @Published private(set) var loadedOnce = false

    private var loadingTask: Task<Void, Never>?

    func loadThumbnails(for packs: [PetPack]) {
        // 幂等：已经有缩略图的宠物不再重复解码。
        // ImageIO 会把图集整张（1536×2288 ≈ 14MB）缓存在进程里，重复解码几次就是几百 MB。
        let missing = packs.filter { thumbnails[$0.id] == nil }
        guard !missing.isEmpty || thumbnails[PetThumbnail.builtinKey] == nil else { return }
        loadingTask?.cancel()

        let size = CGSize(width: 56, height: 74)
        if thumbnails[PetThumbnail.builtinKey] == nil,
           let builtin = PetThumbnail.builtinImage(size: size) {
            thumbnails[PetThumbnail.builtinKey] = builtin
        }
        loadedOnce = true
        guard !missing.isEmpty else { return }

        loadingTask = Task { [weak self] in
            for pack in missing {
                guard !Task.isCancelled else { return }
                let id = pack.id
                let image = await Task.detached(priority: .utility) {
                    PetThumbnail.image(for: pack, size: size)
                }.value
                guard let self, !Task.isCancelled else { return }
                if let image {
                    self.thumbnails[id] = image
                }
            }
        }
    }

    func thumbnail(for id: String?) -> NSImage? {
        thumbnails[id ?? PetThumbnail.builtinKey]
    }
}
