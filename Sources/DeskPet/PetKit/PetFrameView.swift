import AppKit
import DeskPetCore

/// 用 CAKeyframeAnimation 播帧的宠物视图。
///
/// 逐帧动画交给 Core Animation 的 render server（`contents` 离散关键帧），
/// 进程自己只在切轨道时干活，不参与逐帧重绘。
final class PetFrameView: NSView {
    private let imageLayer = CALayer()
    private let cache = FrameCache()
    private var pack: PetPack?
    private var generation = 0
    private var currentTrackName: String?

    /// 解码倍率：原生 2× 会让每帧约 1.1MB、单轨 40MB+；
    /// 1.5× 肉眼几乎看不出差别，内存直接减半。
    private var decodeScale: CGFloat {
        let override = ProcessInfo.processInfo.environment["DESKPET_DECODE_SCALE"].flatMap(Double.init)
        return (window?.backingScaleFactor ?? 2) * CGFloat(override ?? 0.75)
    }

    var mood: PetMood = .idle {
        didSet {
            guard mood != oldValue else { return }
            applyMood()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(imageLayer)
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .linear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var isFlipped: Bool { false }

    private var lastLayoutSize: CGSize = .zero

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()

        // 只有尺寸真的变了才重解码；否则每次 layout 都会重新解一遍
        guard bounds.size != lastLayoutSize else { return }
        lastLayoutSize = bounds.size
        if pack != nil { applyMood(force: true) }
    }

    // MARK: - 对外

    func setPack(_ pack: PetPack?) {
        self.pack = pack
        generation += 1
        imageLayer.removeAllAnimations()
        imageLayer.contents = nil
        currentTrackName = nil
        guard let pack else { return }
        applyMood(force: true)
        prefetchBusyTrack(pack: pack)
    }

    // MARK: - 播放

    private func applyMood(force: Bool = false) {
        guard let pack else { return }
        let candidates = MoodTrackMap.candidates(for: mood, adapter: pack.adapter)
        guard let track = pack.firstTrack(among: candidates) else {
            imageLayer.removeAllAnimations()
            imageLayer.contents = nil
            return
        }

        if !force, currentTrackName == track.name { return }
        currentTrackName = track.name

        let key = "\(pack.id)#\(track.name)"
        let scale = decodeScale
        let target = bounds.size
        guard target.width > 1, target.height > 1 else { return }

        generation += 1
        let token = generation

        Task { @MainActor [weak self] in
            guard let self else { return }
            let loaded = await self.cache.load(
                key: key, pack: pack, track: track, targetSize: target, scale: scale
            )
            guard token == self.generation, let loaded else { return }
            self.play(loaded: loaded, track: track, pack: pack)
        }
    }

    /// 预取"忙碌"轨：从 idle 切到 work 是最常见的转换，提前解好就没有切换延迟。
    private func prefetchBusyTrack(pack: PetPack) {
        let candidates = MoodTrackMap.candidates(for: .busy, adapter: pack.adapter)
        guard let track = pack.firstTrack(among: candidates),
              currentTrackName != track.name
        else { return }

        let key = "\(pack.id)#\(track.name)"
        let scale = decodeScale
        let target = bounds.size
        guard target.width > 1, target.height > 1 else { return }

        Task { @MainActor [weak self] in
            _ = await self?.cache.load(key: key, pack: pack, track: track, targetSize: target, scale: scale)
        }
    }

    private func play(loaded: FrameCache.Loaded, track: PetTrack, pack: PetPack) {
        guard !loaded.frames.isEmpty else { return }

        if ProcessInfo.processInfo.environment["DESKPET_DEBUG"] == "1" {
            let loopText = track.loop ? "loop" : "once"
            let sub = loaded.didSubsample ? " subsampled" : ""
            print("[pet] play \(pack.id)#\(track.name)  \(loaded.frames.count) 帧  "
                  + "\(loaded.durationsMs.reduce(0, +))ms  \(loopText)\(sub)  "
                  + "\(String(format: "%.1f", Double(loaded.bytes) / 1024 / 1024))MB")
            fflush(stdout)
        }

        let totalMs = max(loaded.durationsMs.reduce(0, +), 40)
        let duration = Double(totalMs) / 1000.0

        var keyTimes: [NSNumber] = [0]
        var running = 0
        for ms in loaded.durationsMs.dropLast() {
            running += ms
            keyTimes.append(NSNumber(value: Double(running) / Double(totalMs)))
        }
        keyTimes.append(NSNumber(value: 1.0))

        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = loaded.frames
        animation.keyTimes = keyTimes
        animation.calculationMode = .discrete
        animation.duration = duration
        animation.repeatCount = track.loop ? .infinity : 1
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both
        animation.beginTime = CACurrentMediaTime()

        // 播完回落（`loop == false` 的轨道，例如摸头 / 庆祝）
        if !track.loop, let fallbackName = track.fallback,
           let fallback = pack.track(named: fallbackName) {
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, let pack = self.pack else { return }
                self.currentTrackName = fallbackName
                let key = "\(pack.id)#\(fallback.name)"
                let scale = self.decodeScale
                let token = self.generation
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let loaded = await self.cache.load(
                        key: key, pack: pack, track: fallback,
                        targetSize: self.bounds.size, scale: scale
                    )
                    guard token == self.generation, let loaded else { return }
                    self.play(loaded: loaded, track: fallback, pack: pack)
                }
            }
            CATransaction.commit()
        }

        imageLayer.contents = loaded.frames.last
        imageLayer.add(animation, forKey: "frames")
    }
}
