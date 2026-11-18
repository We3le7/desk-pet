import AppKit
import DeskPetCore
import ImageIO

/// 宠物缩略图：列表里每行用一张静态小图，避免把整条轨道都解出来。
enum PetThumbnail {
    static let builtinKey = "__builtin__"

    /// 取某只宠物的 idle 首帧，缩到指定尺寸。
    static func image(for pack: PetPack, size: CGSize, scale: CGFloat = 2) -> NSImage? {
        guard let track = pack.firstTrack(among: MoodTrackMap.candidates(for: .idle, adapter: pack.adapter)),
              let ref = track.frames.first
        else { return nil }

        let targetWidth = max(Int(size.width * scale), 8)
        let targetHeight = max(Int(size.height * scale), 8)

        guard let cgImage = decodeFirstFrame(ref, pack: pack, maxPixel: max(targetWidth, targetHeight)) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: size)
    }

    /// 内置矢量宠物的缩略图：直接离屏渲染 PetView。
    @MainActor
    static func builtinImage(size: CGSize, mood: PetMood = .idle) -> NSImage? {
        let view = PetView(frame: NSRect(origin: .zero, size: size))
        view.mood = mood
        view.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.scaleBy(x: scale, y: scale)
        view.layer?.render(in: context)
        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: size)
    }

    private static func decodeFirstFrame(_ ref: PetFrameRef, pack: PetPack, maxPixel: Int) -> CGImage? {
        switch ref {
        case .file(let url):
            let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
                  let full = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
            else { return nil }
            return downsample(full, maxPixel: maxPixel)

        case .cell(let row, let column):
            guard let url = pack.spriteSheet,
                  let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let sheet = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
            else { return nil }
            let cellWidth = sheet.width / 8
            let cellHeight = sheet.height / 11
            let rect = CGRect(
                x: column * cellWidth,
                y: row * cellHeight,
                width: cellWidth,
                height: cellHeight
            )
            guard let cell = sheet.cropping(to: rect) else { return nil }
            return downsample(cell, maxPixel: maxPixel)
        }
    }

    private static func downsample(_ image: CGImage, maxPixel: Int) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let ratio = min(Double(maxPixel) / Double(max(width, height)), 1.0)
        let targetWidth = max(Int(Double(width) * ratio), 1)
        let targetHeight = max(Int(Double(height) * ratio), 1)
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }
}
