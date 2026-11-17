import AppKit
import DeskPetCore
import ImageIO

/// 帧解码与缓存。
///
/// 关键约束：鲸鱼娘的 idle 有 78 帧、单帧 512×683，全部按 2× 解码约 42 MB。
/// 所以这里做两件事：
/// 1. **预缩放**：用 ImageIO 直接解到目标像素尺寸，不经过全尺寸解码；
/// 2. **预算裁剪**：超出内存预算时按整数步长跳帧，并把被跳过的帧时长累加，
///    保证动画总时长不变（只是帧率降低）。
@MainActor
final class FrameCache {
    struct Loaded: @unchecked Sendable {
        var frames: [CGImage]
        var durationsMs: [Int]
        var bytes: Int
        var didSubsample: Bool
    }

    struct Request: Sendable {
        let pack: PetPack
        let track: PetTrack
        let targetSize: CGSize
        let scale: CGFloat
        let budgetBytes: Int
    }

    private let budgetBytes: Int
    private let maxTracks: Int

    private var store: [String: Loaded] = [:]
    private var recency: [String] = []
    /// 同一轨道的并发请求要复用同一个解码任务，否则会重复解码、重复占内存
    private var pending: [String: Task<Loaded?, Never>] = [:]

    init(budgetBytes: Int? = nil, maxTracks: Int = 2) {
        let overrideMB = ProcessInfo.processInfo.environment["DESKPET_FRAME_BUDGET_MB"].flatMap(Double.init)
        self.budgetBytes = budgetBytes ?? Int((overrideMB ?? 12) * 1024 * 1024)
        let tracksOverride = ProcessInfo.processInfo.environment["DESKPET_FRAME_MAX_TRACKS"].flatMap(Int.init)
        self.maxTracks = tracksOverride ?? maxTracks
    }

    /// 已缓存的帧（同步）。
    func cached(key: String) -> Loaded? {
        guard let loaded = store[key] else { return nil }
        touch(key)
        return loaded
    }

    /// 异步解码一条轨道：命中缓存直接返回，否则在后台解。
    func load(key: String, pack: PetPack, track: PetTrack, targetSize: CGSize, scale: CGFloat) async -> Loaded? {
        if let hit = cached(key: key) { return hit }
        if let pendingTask = pending[key] { return await pendingTask.value }

        let request = Request(
            pack: pack,
            track: track,
            targetSize: targetSize,
            scale: scale,
            budgetBytes: budgetBytes
        )
        let task = Task.detached(priority: .userInitiated) {
            Self.decode(request)
        }
        pending[key] = task
        let loaded = await task.value
        pending[key] = nil

        if let loaded {
            store[key] = loaded
            touch(key)
            evictIfNeeded()
        }
        return loaded
    }

    /// 诊断用：同步解码一条轨道（CLI 检查宠物包时用）。
    nonisolated static func inspect(
        pack: PetPack,
        track: PetTrack,
        targetSize: CGSize,
        scale: CGFloat,
        budgetBytes: Int = 12 * 1024 * 1024
    ) -> Loaded? {
        decode(Request(pack: pack, track: track, targetSize: targetSize, scale: scale, budgetBytes: budgetBytes))
    }

    // MARK: - 解码（后台）

    nonisolated private static func decode(_ request: Request) -> Loaded? {
        let targetSize = request.targetSize
        let scale = request.scale
        let pixelWidth = max(Int(targetSize.width * scale), 16)
        let pixelHeight = max(Int(targetSize.height * scale), 16)
        let maxPixel = max(pixelWidth, pixelHeight)

        let sheet = request.pack.adapter == .atlas ? loadSheet(request.pack) : nil

        // 先按内存预算决定跳帧步长，只解码保留下来的帧。
        // 若先全解 78 帧再丢弃，malloc 会把峰值留在堆里（实测多占 40MB+）。
        let totalFrames = request.track.frames.count
        guard totalFrames > 0 else { return nil }

        let bytesPerFrame = max(pixelWidth * pixelHeight * 4, 1)
        let maxFrames = max(request.budgetBytes / bytesPerFrame, 2)
        let step = max(Int((Double(totalFrames) / Double(maxFrames)).rounded(.up)), 1)

        var indices: [Int] = []
        var selectedDurations: [Int] = []
        var accumulated = 0
        for index in 0..<totalFrames {
            let duration = index < request.track.durationsMs.count ? max(request.track.durationsMs[index], 10) : 80
            accumulated += duration
            if index % step == 0 {
                indices.append(index)
                selectedDurations.append(accumulated)
                accumulated = 0
            }
        }
        if accumulated > 0, let last = selectedDurations.indices.last {
            selectedDurations[last] += accumulated
        }

        let selectedIndices = indices
        let count = selectedIndices.count
        guard count > 0 else { return nil }

        // 并行解码：每个 position 只写自己的槽位，互不重叠
        let box = FrameBox(count: count)
        DispatchQueue.concurrentPerform(iterations: count) { position in
            autoreleasepool {
                let ref = request.track.frames[selectedIndices[position]]
                box.images[position] = decodeImage(ref, sheet: sheet, maxPixel: maxPixel)
            }
        }

        var images: [CGImage] = []
        images.reserveCapacity(count)
        for position in 0..<count {
            guard let image = box.images[position] else { continue }
            images.append(image)
        }
        guard !images.isEmpty else { return nil }

        return Loaded(
            frames: images,
            durationsMs: selectedDurations,
            bytes: images.count * bytesPerFrame,
            didSubsample: step > 1
        )
    }

    nonisolated private static func decodeImage(_ ref: PetFrameRef, sheet: CGImage?, maxPixel: Int) -> CGImage? {
        switch ref {
        case .file(let url):
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                // 不要 ShouldCacheImmediately：那会把整张原图（512×683）也留在 ImageIO 缓存里，
                // 26 帧就会多占几十 MB。
                kCGImageSourceShouldCache: false,
            ]
            guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            // 关键：缩略图可能仍引用原图那 512×683 的缓冲（26 帧就是 36MB）。
            // 重画到自有 bitmap，确保每帧只占目标尺寸的内存。
            return materialize(thumb)

        case .cell(let row, let column):
            guard let sheet else { return nil }
            let cell = cellSize(for: sheet)
            let rect = CGRect(
                x: CGFloat(column) * cell.width,
                y: CGFloat(row) * cell.height,
                width: cell.width,
                height: cell.height
            )
            return sheet.cropping(to: rect)
        }
    }

    /// 把图像重画进一块紧凑的 bitmap，切断对原始解码缓冲的引用。
    nonisolated private static func materialize(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    nonisolated private static func loadSheet(_ pack: PetPack) -> CGImage? {
        guard let url = pack.spriteSheet else { return nil }
        if let hit = AtlasSheetCache.shared.image(for: url) { return hit }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        AtlasSheetCache.shared.insert(image, for: url)
        return image
    }

    nonisolated static func cellSize(for sheet: CGImage) -> CGSize {
        // Codex 图集固定 8 列 × 11 行
        CGSize(width: CGFloat(sheet.width) / 8, height: CGFloat(sheet.height) / 11)
    }

    // MARK: - LRU

    private func touch(_ key: String) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private func evictIfNeeded() {
        while recency.count > maxTracks, let oldest = recency.first {
            recency.removeFirst()
            store[oldest] = nil
        }
    }
}


/// 并行解码的槽位容器。每个 position 只被一个 worker 写入，互不重叠。
private final class FrameBox: @unchecked Sendable {
    var images: [CGImage?]
    init(count: Int) { images = Array(repeating: nil, count: count) }
}

/// 图集整张只解一次，跨调用共享。
private final class AtlasSheetCache: @unchecked Sendable {
    static let shared = AtlasSheetCache()

    private let lock = NSLock()
    private var store: [String: CGImage] = [:]

    func image(for url: URL) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return store[url.path]
    }

    func insert(_ image: CGImage, for url: URL) {
        lock.lock()
        store[url.path] = image
        lock.unlock()
    }
}
