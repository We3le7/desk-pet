import AppKit
import DeskPetCore

/// 宠物显示宿主：装了宠物包就播帧动画，没装就退回代码绘制的矢量宠物。
final class PetDisplayView: NSView {
    private let vectorView = PetView(frame: .zero)
    private let frameView = PetFrameView(frame: .zero)

    private(set) var pack: PetPack?
    private var currentMood: PetMood = .idle

    // 金额标签
    let moneyPillLayer = CAShapeLayer()
    let moneyTextLayer = CATextLayer()
    var coinLayers: [CAEmitterLayer] = []
    /// 每秒 "+¥0.03" 用的复用图层
    private lazy var floatTextLayer: CATextLayer = {
        let text = CATextLayer()
        text.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        text.fontSize = 11
        text.foregroundColor = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.35, alpha: 1).cgColor
        text.alignmentMode = .center
        text.contentsScale = 2
        text.opacity = 0
        return text
    }()
    private var moneyLayersReady = false
    /// 预览场景不需要预留金额区
    var reservesMoneyArea = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(vectorView)
        addSubview(frameView)
        frameView.isHidden = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func layout() {
        super.layout()
        // 宠物区在金额区之上，两者不再重叠
        let moneyHeight = reservesMoneyArea ? PetPanel.moneyAreaHeight : 0
        let petArea = CGRect(
            x: 0,
            y: moneyHeight,
            width: bounds.width,
            height: max(bounds.height - moneyHeight, 1)
        )
        vectorView.frame = petArea
        frameView.frame = petArea
        layoutMoneyLayers()
    }

    func ensureMoneyLayers() {
        guard !moneyLayersReady, let host = layer else { return }
        moneyLayersReady = true

        moneyPillLayer.fillColor = NSColor.black.withAlphaComponent(0.42).cgColor
        moneyTextLayer.alignmentMode = .center
        moneyTextLayer.foregroundColor = NSColor.white.cgColor
        moneyTextLayer.font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        moneyTextLayer.fontSize = 15
        moneyTextLayer.truncationMode = .none
        moneyTextLayer.contentsScale = window?.backingScaleFactor ?? 2

        host.addSublayer(moneyPillLayer)
        host.addSublayer(moneyTextLayer)
        layoutMoneyLayers()
    }

    private func layoutMoneyLayers() {
        guard moneyLayersReady else { return }
        let width = min(bounds.width - 12, 178)
        let height: CGFloat = 26
        let rect = CGRect(
            x: bounds.midX - width / 2,
            y: 10,
            width: width,
            height: height
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        moneyPillLayer.path = CGPath(roundedRect: rect, cornerWidth: height / 2,
                                     cornerHeight: height / 2, transform: nil)
        moneyPillLayer.frame = bounds
        moneyTextLayer.frame = CGRect(x: rect.minX, y: rect.minY + 5, width: rect.width, height: 17)
        moneyTextLayer.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }

    func setPack(_ pack: PetPack?) {
        // SwiftUI 每次刷新都会调到这里；同一只宠物不要重复解码
        guard pack?.id != self.pack?.id else { return }
        self.pack = pack
        frameView.setPack(pack)
        let usingFrames = pack != nil
        frameView.isHidden = !usingFrames
        vectorView.isHidden = usingFrames
        if usingFrames {
            frameView.mood = currentMood
        }
    }

    func setRotationEnabled(_ enabled: Bool) {
        frameView.setRotationEnabled(enabled)
    }

    func setMood(_ mood: PetMood) {
        guard mood != currentMood else { return }
        currentMood = mood
        vectorView.mood = mood
        frameView.mood = mood
    }
}

// MARK: - 金额标签与金币

extension PetDisplayView {
    /// 宠物下方的今日到账金额（CATextLayer，避免 SwiftUI 每秒重绘）。
    func setMoneyText(_ text: String) {
        ensureMoneyLayers()
        moneyTextLayer.string = text
    }

    func setMoneyVisible(_ visible: Bool) {
        ensureMoneyLayers()
        moneyPillLayer.opacity = visible ? 1 : 0
        moneyTextLayer.opacity = visible ? 1 : 0
    }

    /// 每秒到账特效：金额脉冲 + 浮起的 +¥0.03。
    func playMoneyTick(delta: Double) {
        guard delta > 0, moneyLayersReady else { return }

        // 1) 金额脉冲
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1.0, 1.08, 1.0]
        pulse.keyTimes = [0, 0.35, 1]
        pulse.duration = 0.34
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        moneyTextLayer.add(pulse, forKey: "pulse")

        // 2) 浮起的小票（复用同一层，避免每秒新建图层/重排）
        let text = floatTextLayer
        text.string = Self.deltaText(delta)
        text.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        text.fontSize = 11
        text.foregroundColor = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.35, alpha: 1).cgColor
        text.alignmentMode = .center
        text.contentsScale = window?.backingScaleFactor ?? 2
        let startY = PetPanel.moneyAreaHeight - 6
        text.frame = CGRect(x: bounds.midX - 40, y: startY, width: 80, height: 14)
        if text.superlayer == nil { layer?.addSublayer(text) }

        let rise = CAKeyframeAnimation(keyPath: "position.y")
        rise.values = [startY + 7, startY + 26]
        rise.duration = 0.95
        rise.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1.0, 1.0, 0.0]
        fade.keyTimes = [0, 0.55, 1]
        fade.duration = 0.95
        let group = CAAnimationGroup()
        group.animations = [rise, fade]
        group.duration = 0.95
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        text.add(group, forKey: "float")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak text] in
            // 只淡出，不销毁：下一拍继续复用
            text?.opacity = 0
        }
    }

    static func deltaText(_ delta: Double) -> String {
        if delta < 0.1 {
            return String(format: "+¥%.3f", delta)
        }
        return String(format: "+¥%.2f", delta)
    }

    /// 里程碑金币：CAEmitterLayer 发射一轮后自动停。
    func burstCoins(isBig: Bool) {
        let layer = CAEmitterLayer()
        layer.emitterPosition = CGPoint(x: bounds.midX, y: bounds.height * 0.35)
        layer.emitterShape = .point

        let cell = CAEmitterCell()
        cell.contents = Self.coinImage
        cell.birthRate = Float(isBig ? 26 : 14)
        cell.lifetime = 1.1
        cell.lifetimeRange = 0.3
        cell.velocity = 190
        cell.velocityRange = 70
        cell.emissionRange = .pi / 3
        cell.yAcceleration = -420
        cell.spin = 3
        cell.spinRange = 4
        cell.scale = 0.9
        cell.scaleRange = 0.35
        layer.emitterCells = [cell]

        self.layer?.addSublayer(layer)
        coinLayers.append(layer)

        DispatchQueue.main.asyncAfter(deadline: .now() + (isBig ? 0.35 : 0.2)) {
            layer.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            layer.removeFromSuperlayer()
            self?.coinLayers.removeAll { $0 === layer }
        }
    }

    private static let coinImage: CGImage? = {
        let size = 18
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 1, y: 1, width: 16, height: 16)
        context.setFillColor(NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.22, alpha: 1).cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(NSColor(calibratedRed: 0.85, green: 0.58, blue: 0.05, alpha: 1).cgColor)
        context.setLineWidth(1.4)
        context.strokeEllipse(in: rect)
        context.setFillColor(NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.6, alpha: 0.9).cgColor)
        context.fillEllipse(in: CGRect(x: 5, y: 9, width: 4, height: 3))
        return context.makeImage()
    }()
}
