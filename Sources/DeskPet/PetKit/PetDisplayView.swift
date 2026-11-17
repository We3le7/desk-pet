import AppKit
import DeskPetCore

/// 宠物显示宿主：装了宠物包就播帧动画，没装就退回代码绘制的矢量宠物。
final class PetDisplayView: NSView {
    private let vectorView = PetView(frame: .zero)
    private let frameView = PetFrameView(frame: .zero)

    private(set) var pack: PetPack?
    private var currentMood: PetMood = .idle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(vectorView)
        addSubview(frameView)
        frameView.isHidden = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        vectorView.frame = bounds
        frameView.frame = bounds
    }

    func setPack(_ pack: PetPack?) {
        self.pack = pack
        frameView.setPack(pack)
        let usingFrames = pack != nil
        frameView.isHidden = !usingFrames
        vectorView.isHidden = usingFrames
        if usingFrames {
            frameView.mood = currentMood
        }
    }

    func setMood(_ mood: PetMood) {
        guard mood != currentMood else { return }
        currentMood = mood
        vectorView.mood = mood
        frameView.mood = mood
    }
}
