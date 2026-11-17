import AppKit
import DeskPetCore

/// 纯代码绘制的兜底宠物：没有安装任何宠物包时使用。
///
/// 完全用 Core Animation 图层绘制，**呼吸、眨眼、天线摆动、星星环绕都是 CA 动画**
/// （跑在 render server 上），进程本身不参与逐帧重绘 —— 实测比 SwiftUI `TimelineView`
/// + `Canvas` 每帧重画的方案省一个数量级的 CPU。
final class PetView: NSView {
    // MARK: - 状态

    var mood: PetMood = .idle {
        didSet {
            guard mood != oldValue else { return }
            applyMood()
        }
    }

    // MARK: - 图层

    private let petGroup = CALayer()
    private let groundShadow = CAShapeLayer()
    private let body = CAShapeLayer()
    private let highlight = CAShapeLayer()
    private let eyeLeft = CAShapeLayer()
    private let eyeRight = CAShapeLayer()
    private let glintLeft = CAShapeLayer()
    private let glintRight = CAShapeLayer()
    private let cheekLeft = CAShapeLayer()
    private let cheekRight = CAShapeLayer()
    private let mouth = CAShapeLayer()
    private let antennaStem = CAShapeLayer()
    private let antennaBall = CAShapeLayer()
    private let sparkleOrbit = CALayer()

    private var sparkles: [CAShapeLayer] = []
    private var zzz: [CATextLayer] = []
    private var sweats: [CAShapeLayer] = []

    // MARK: - 生命周期

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var isFlipped: Bool { false }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false

        for shape in [groundShadow, body, highlight, eyeLeft, eyeRight, glintLeft, glintRight,
                      cheekLeft, cheekRight, mouth, antennaStem, antennaBall] {
            shape.actions = ["position": NSNull(), "bounds": NSNull(), "path": NSNull(),
                             "fillColor": NSNull(), "opacity": NSNull()]
        }

        layer?.addSublayer(groundShadow)
        layer?.addSublayer(petGroup)

        petGroup.addSublayer(body)
        petGroup.addSublayer(highlight)
        petGroup.addSublayer(cheekLeft)
        petGroup.addSublayer(cheekRight)
        petGroup.addSublayer(eyeLeft)
        petGroup.addSublayer(eyeRight)
        eyeLeft.addSublayer(glintLeft)
        eyeRight.addSublayer(glintRight)
        petGroup.addSublayer(mouth)
        petGroup.addSublayer(antennaStem)
        petGroup.addSublayer(antennaBall)
        petGroup.addSublayer(sparkleOrbit)

        makeupDecorations()

        mouth.fillColor = nil
        mouth.lineCap = .round
        antennaStem.fillColor = nil
        antennaStem.lineCap = .round
        highlight.fillColor = NSColor.white.withAlphaComponent(0.20).cgColor
        cheekLeft.fillColor = NSColor.systemPink.withAlphaComponent(0.28).cgColor
        cheekRight.fillColor = NSColor.systemPink.withAlphaComponent(0.28).cgColor

        applyMood()
        startIdleAnimations()
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    // MARK: - 装饰层

    private func makeupDecorations() {
        for index in 0..<3 {
            let text = CATextLayer()
            text.string = "z"
            text.fontSize = CGFloat(11 + index * 2)
            text.foregroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
            text.alignmentMode = .center
            text.contentsScale = window?.backingScaleFactor ?? 2
            text.opacity = 0
            petGroup.addSublayer(text)
            zzz.append(text)
        }

        for _ in 0..<2 {
            let drop = CAShapeLayer()
            drop.fillColor = NSColor(calibratedRed: 0.45, green: 0.72, blue: 1.0, alpha: 0.9).cgColor
            drop.opacity = 0
            petGroup.addSublayer(drop)
            sweats.append(drop)
        }

        for _ in 0..<5 {
            let star = CAShapeLayer()
            star.fillColor = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.25, alpha: 0.95).cgColor
            star.opacity = 0
            sparkleOrbit.addSublayer(star)
            sparkles.append(star)
        }
    }

    // MARK: - 布局

    private func layoutLayers() {
        let bounds = self.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }

        let bodyCenter = CGPoint(x: bounds.midX, y: bounds.height * 0.56)
        let bodySize = CGSize(width: bounds.width * 0.60, height: bounds.height * 0.46)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // 整个宠物组以身体中心为锚点做呼吸缩放
        petGroup.frame = bounds
        petGroup.anchorPoint = CGPoint(x: 0.5, y: 0.56)
        petGroup.position = CGPoint(x: bounds.midX, y: bounds.height * 0.56)
        petGroup.bounds = bounds

        groundShadow.frame = CGRect(
            x: bodyCenter.x - bodySize.width * 0.46,
            y: bodyCenter.y + bodySize.height * 0.46,
            width: bodySize.width * 0.92,
            height: bounds.height * 0.032
        )
        groundShadow.path = CGPath(ellipseIn: groundShadow.bounds, transform: nil)
        groundShadow.fillColor = NSColor.black.withAlphaComponent(0.15).cgColor

        body.frame = CGRect(
            x: bodyCenter.x - bodySize.width / 2,
            y: bodyCenter.y - bodySize.height / 2,
            width: bodySize.width,
            height: bodySize.height
        )
        body.path = CGPath(
            roundedRect: body.bounds,
            cornerWidth: bodySize.width * 0.40,
            cornerHeight: bodySize.width * 0.40,
            transform: nil
        )

        highlight.frame = CGRect(
            x: bodyCenter.x - bodySize.width * 0.24,
            y: bodyCenter.y + bodySize.height * 0.16,
            width: bodySize.width * 0.32,
            height: bodySize.height * 0.20
        )
        highlight.path = CGPath(ellipseIn: highlight.bounds, transform: nil)
        highlight.cornerRadius = 0

        let eyeRadius = bodySize.width * 0.058
        let eyeOffset = bodySize.width * 0.17
        let eyeY = bodyCenter.y - bodySize.height * 0.03

        for (eye, glint, sign) in [(eyeLeft, glintLeft, -1.0), (eyeRight, glintRight, 1.0)] {
            eye.bounds = CGRect(x: 0, y: 0, width: eyeRadius * 2, height: eyeRadius * 2)
            eye.position = CGPoint(x: bodyCenter.x + CGFloat(sign) * eyeOffset, y: eyeY)
            eye.path = CGPath(ellipseIn: eye.bounds, transform: nil)

            glint.bounds = CGRect(x: 0, y: 0, width: eyeRadius * 0.7, height: eyeRadius * 0.7)
            glint.position = CGPoint(x: eyeRadius * 0.85, y: eyeRadius * 1.15)
            glint.path = CGPath(ellipseIn: glint.bounds, transform: nil)
            glint.fillColor = NSColor.white.withAlphaComponent(0.88).cgColor
        }

        let cheekSize = CGSize(width: bodySize.width * 0.10, height: bodySize.width * 0.062)
        for (cheek, sign) in [(cheekLeft, -1.0), (cheekRight, 1.0)] {
            cheek.bounds = CGRect(origin: .zero, size: cheekSize)
            cheek.position = CGPoint(
                x: bodyCenter.x + CGFloat(sign) * bodySize.width * 0.27,
                y: eyeY - bodySize.height * 0.10
            )
            cheek.path = CGPath(ellipseIn: cheek.bounds, transform: nil)
        }

        mouth.bounds = CGRect(x: 0, y: 0, width: bodySize.width * 0.24, height: bodySize.height * 0.12)
        mouth.position = CGPoint(x: bodyCenter.x, y: eyeY - bodySize.height * 0.14)

        let antennaBase = CGPoint(x: bodyCenter.x, y: bodyCenter.y + bodySize.height * 0.50)
        let antennaTip = CGPoint(x: bodyCenter.x, y: bodyCenter.y + bodySize.height * 0.76)
        antennaStem.frame = CGRect(
            x: min(antennaBase.x, antennaTip.x),
            y: min(antennaBase.y, antennaTip.y),
            width: 1,
            height: abs(antennaTip.y - antennaBase.y)
        )
        let stemPath = CGMutablePath()
        stemPath.move(to: .zero)
        stemPath.addQuadCurve(to: CGPoint(x: 0, y: antennaStem.frame.height),
                              control: CGPoint(x: 0, y: antennaStem.frame.height * 0.55))
        antennaStem.path = stemPath
        antennaStem.position = CGPoint(x: antennaBase.x, y: antennaBase.y)
        antennaStem.bounds = CGRect(x: 0, y: 0, width: 1, height: antennaStem.frame.height)
        antennaStem.anchorPoint = CGPoint(x: 0.5, y: 0)

        let ballRadius = bodySize.width * 0.032
        antennaBall.bounds = CGRect(x: 0, y: 0, width: ballRadius * 2, height: ballRadius * 2)
        antennaBall.position = CGPoint(x: bodyCenter.x, y: antennaTip.y)
        antennaBall.path = CGPath(ellipseIn: antennaBall.bounds, transform: nil)

        buildMouthPath(bodySize: bodySize)
        layoutDecorations(bodyCenter: bodyCenter, bodySize: bodySize)

        CATransaction.commit()
    }

    private func layoutDecorations(bodyCenter: CGPoint, bodySize: CGSize) {
        for (index, text) in zzz.enumerated() {
            text.bounds = CGRect(x: 0, y: 0, width: 18, height: 16)
            text.position = CGPoint(
                x: bodyCenter.x + bodySize.width * 0.34 + CGFloat(index) * 12,
                y: bodyCenter.y + bodySize.height * 0.46 + CGFloat(index) * 14
            )
        }

        for (index, drop) in sweats.enumerated() {
            let radius: CGFloat = 3.4
            drop.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2.6)
            drop.position = CGPoint(
                x: bodyCenter.x - bodySize.width * 0.38 - CGFloat(index) * 9,
                y: bodyCenter.y + bodySize.height * 0.18 + CGFloat(index) * 13
            )
            let path = CGMutablePath()
            path.move(to: CGPoint(x: radius, y: radius * 2.6))
            path.addQuadCurve(to: CGPoint(x: radius * 2, y: radius * 0.9),
                              control: CGPoint(x: radius * 2.1, y: radius * 1.9))
            path.addArc(center: CGPoint(x: radius, y: radius * 0.9), radius: radius,
                        startAngle: 0, endAngle: .pi, clockwise: false)
            path.addQuadCurve(to: CGPoint(x: radius, y: radius * 2.6),
                              control: CGPoint(x: -radius * 0.1, y: radius * 1.9))
            path.closeSubpath()
            drop.path = path
        }

        sparkleOrbit.frame = CGRect(
            x: bodyCenter.x - bodySize.width * 0.85,
            y: bodyCenter.y - bodySize.height * 0.75,
            width: bodySize.width * 1.7,
            height: bodySize.height * 1.5
        )
        sparkleOrbit.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sparkleOrbit.position = bodyCenter

        let orbitRadius = sparkleOrbit.bounds.width * 0.44
        for (index, star) in sparkles.enumerated() {
            let angle = Double(index) / Double(sparkles.count) * 2 * .pi
            let size: CGFloat = 4
            star.bounds = CGRect(x: 0, y: 0, width: size * 2, height: size * 2)
            star.position = CGPoint(
                x: sparkleOrbit.bounds.midX + CGFloat(cos(angle)) * orbitRadius,
                y: sparkleOrbit.bounds.midY + CGFloat(sin(angle)) * orbitRadius * 0.8
            )
            star.path = starPath(size: size)
        }
    }

    private func starPath(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let points = 4
        for index in 0..<points * 2 {
            let angle = Double(index) * .pi / Double(points) - .pi / 2
            let radius = index.isMultiple(of: 2) ? size : size * 0.34
            let point = CGPoint(
                x: size + CGFloat(cos(angle)) * radius,
                y: size + CGFloat(sin(angle)) * radius
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func buildMouthPath(bodySize: CGSize) {
        let rect = mouth.bounds
        let path = CGMutablePath()
        switch mood {
        case .sleeping, .busy, .overheat:
            path.move(to: CGPoint(x: rect.midX - rect.width * 0.22, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.22, y: rect.midY))
        default:
            path.addArc(center: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.2),
                        radius: rect.width * 0.42,
                        startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
        }
        mouth.path = path
        mouth.lineWidth = max(1.2, bodySize.width * 0.008)
    }

    // MARK: - 动画

    private func startIdleAnimations() {
        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = 1.0
        breathe.toValue = 1.024
        breathe.duration = 1.7
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        petGroup.add(breathe, forKey: "breathe")

        let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
        blink.values = [1.0, 1.0, 0.12, 1.0, 1.0]
        blink.keyTimes = [0.0, 0.86, 0.89, 0.93, 1.0]
        blink.duration = 4.3
        blink.repeatCount = .infinity
        eyeLeft.add(blink, forKey: "blink")
        eyeRight.add(blink, forKey: "blink")

        let sway = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        sway.values = [-0.05, 0.05, -0.05]
        sway.keyTimes = [0.0, 0.5, 1.0]
        sway.duration = 2.6
        sway.repeatCount = .infinity
        sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        antennaStem.add(sway, forKey: "sway")
        antennaBall.add(sway, forKey: "sway")

        let orbit = CABasicAnimation(keyPath: "transform.rotation.z")
        orbit.fromValue = 0
        orbit.toValue = Double.pi * 2
        orbit.duration = 6
        orbit.repeatCount = .infinity
        sparkleOrbit.add(orbit, forKey: "orbit")
    }

    // MARK: - 情绪

    private func applyMood() {
        let palette = Palette(mood: mood)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        body.fillColor = palette.body.cgColor
        eyeLeft.fillColor = palette.eye.cgColor
        eyeRight.fillColor = palette.eye.cgColor
        cheekLeft.fillColor = palette.blush.cgColor
        cheekRight.fillColor = palette.blush.cgColor
        mouth.fillColor = nil
        mouth.strokeColor = palette.eye.cgColor
        antennaStem.strokeColor = palette.outline.cgColor
        antennaStem.lineWidth = 1.8
        antennaBall.fillColor = palette.accent.cgColor
        highlight.fillColor = NSColor.white.withAlphaComponent(0.20).cgColor
        for star in sparkles { star.fillColor = palette.accent.cgColor }

        // 装饰层显隐
        let showsZzz = mood == .sleeping
        let showsSweat = mood == .busy || mood == .overheat
        let showsSparkles = mood == .charging || mood == .celebrate || mood == .pet

        for (index, text) in zzz.enumerated() {
            text.opacity = showsZzz ? 1 : 0
            text.removeAllAnimations()
            guard showsZzz else { continue }
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1.0, 0.9, 0.0]
            fade.keyTimes = [0.0, 0.55, 1.0]
            fade.duration = 2.4
            fade.beginTime = CACurrentMediaTime() + Double(index) * 0.8
            fade.repeatCount = .infinity
            text.add(fade, forKey: "fade")
        }

        for (index, drop) in sweats.enumerated() {
            drop.opacity = showsSweat ? 1 : 0
            drop.removeAllAnimations()
            guard showsSweat else { continue }
            let slide = CABasicAnimation(keyPath: "position.y")
            slide.byValue = -9
            slide.duration = 1.1
            slide.autoreverses = true
            slide.repeatCount = .infinity
            slide.beginTime = CACurrentMediaTime() + Double(index) * 0.45
            drop.add(slide, forKey: "slide")
        }

        sparkleOrbit.opacity = showsSparkles ? 1 : 0
        if showsSparkles {
            for (index, star) in sparkles.enumerated() {
                let twinkle = CABasicAnimation(keyPath: "transform.scale")
                twinkle.fromValue = 0.6
                twinkle.toValue = 1.15
                twinkle.duration = 0.7
                twinkle.autoreverses = true
                twinkle.repeatCount = .infinity
                twinkle.beginTime = CACurrentMediaTime() + Double(index) * 0.12
                star.add(twinkle, forKey: "twinkle")
            }
        }

        buildMouthPath(bodySize: CGSize(width: bounds.width, height: bounds.height))
        applyMotionStyle()

        // 一次性情绪（庆祝/摸头）播一下弹跳
        if mood == .celebrate || mood == .pet {
            let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
            hop.values = [0, 14, 0]
            hop.keyTimes = [0.0, 0.4, 1.0]
            hop.duration = 0.55
            hop.timingFunction = CAMediaTimingFunction(name: .easeOut)
            petGroup.add(hop, forKey: "hop")
        }

        CATransaction.commit()
    }

    private func applyMotionStyle() {
        petGroup.removeAnimation(forKey: "jitter")

        switch mood {
        case .overheat:
            let jitter = CAKeyframeAnimation(keyPath: "transform.translation.x")
            jitter.values = [-1.6, 1.6, -1.4, 1.2, 0]
            jitter.duration = 0.22
            jitter.repeatCount = .infinity
            petGroup.add(jitter, forKey: "jitter")
        case .busy:
            let jitter = CAKeyframeAnimation(keyPath: "transform.translation.x")
            jitter.values = [-0.7, 0.7, 0]
            jitter.duration = 0.5
            jitter.repeatCount = .infinity
            petGroup.add(jitter, forKey: "jitter")
        default:
            break
        }
    }
}

// MARK: - 配色

private struct Palette {
    let body: NSColor
    let outline: NSColor
    let eye: NSColor
    let blush: NSColor
    let accent: NSColor

    init(mood: PetMood) {
        switch mood {
        case .idle:
            body = NSColor(calibratedRed: 0.55, green: 0.87, blue: 0.80, alpha: 1)
            outline = NSColor(calibratedRed: 0.24, green: 0.55, blue: 0.51, alpha: 1)
            eye = NSColor(calibratedRed: 0.13, green: 0.27, blue: 0.28, alpha: 1)
            blush = NSColor.systemPink.withAlphaComponent(0.32)
            accent = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.25, alpha: 1)
        case .busy:
            body = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.50, alpha: 1)
            outline = NSColor(calibratedRed: 0.62, green: 0.42, blue: 0.20, alpha: 1)
            eye = NSColor(calibratedRed: 0.35, green: 0.20, blue: 0.10, alpha: 1)
            blush = NSColor.systemRed.withAlphaComponent(0.30)
            accent = NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.55, alpha: 1)
        case .overheat:
            body = NSColor(calibratedRed: 1.0, green: 0.56, blue: 0.52, alpha: 1)
            outline = NSColor(calibratedRed: 0.60, green: 0.22, blue: 0.20, alpha: 1)
            eye = NSColor(calibratedRed: 0.38, green: 0.12, blue: 0.12, alpha: 1)
            blush = NSColor.systemRed.withAlphaComponent(0.36)
            accent = NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.5, alpha: 1)
        case .tired:
            body = NSColor(calibratedRed: 0.75, green: 0.76, blue: 0.82, alpha: 1)
            outline = NSColor(calibratedRed: 0.40, green: 0.42, blue: 0.50, alpha: 1)
            eye = NSColor(calibratedRed: 0.25, green: 0.26, blue: 0.33, alpha: 1)
            blush = NSColor.systemPink.withAlphaComponent(0.22)
            accent = NSColor(calibratedRed: 0.85, green: 0.85, blue: 0.92, alpha: 1)
        case .charging:
            body = NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.45, alpha: 1)
            outline = NSColor(calibratedRed: 0.63, green: 0.50, blue: 0.12, alpha: 1)
            eye = NSColor(calibratedRed: 0.33, green: 0.26, blue: 0.05, alpha: 1)
            blush = NSColor.systemOrange.withAlphaComponent(0.32)
            accent = NSColor(calibratedRed: 1.0, green: 0.70, blue: 0.12, alpha: 1)
        case .sleeping:
            body = NSColor(calibratedRed: 0.62, green: 0.64, blue: 0.86, alpha: 1)
            outline = NSColor(calibratedRed: 0.28, green: 0.30, blue: 0.52, alpha: 1)
            eye = NSColor(calibratedRed: 0.18, green: 0.19, blue: 0.35, alpha: 1)
            blush = NSColor.systemPink.withAlphaComponent(0.26)
            accent = NSColor(calibratedRed: 0.90, green: 0.88, blue: 1.0, alpha: 1)
        default:
            body = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.82, alpha: 1)
            outline = NSColor(calibratedRed: 0.62, green: 0.28, blue: 0.40, alpha: 1)
            eye = NSColor(calibratedRed: 0.35, green: 0.14, blue: 0.22, alpha: 1)
            blush = NSColor.systemPink.withAlphaComponent(0.36)
            accent = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.95, alpha: 1)
        }
    }
}
