import AppKit
import DeskPetCore
import SwiftUI

/// 把 `PetDisplayView` 包成 SwiftUI 视图，用于设置页里的动态预览。
struct PetPreviewView: NSViewRepresentable {
    let pack: PetPack?
    var mood: PetMood = .idle

    func makeNSView(context: Context) -> PetDisplayView {
        let view = PetDisplayView(frame: NSRect(x: 0, y: 0, width: 104, height: 136))
        view.reservesMoneyArea = false
        view.setMood(mood)
        view.setPack(pack)
        return view
    }

    func updateNSView(_ view: PetDisplayView, context: Context) {
        view.reservesMoneyArea = false
        view.setMood(mood)
        view.setPack(pack)   // 内部按 id 去重，重复调用不会重新解码
    }
}
