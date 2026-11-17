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
    private var moneyLayersReady = false

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
        vectorView.frame = bounds
        frameView.frame = bounds
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
