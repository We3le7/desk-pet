import Foundation

/// 把磁盘上的宠物目录解析成 `PetPack`。
///
/// 支持两种已有格式，都不需要用户先做转换：
/// 1. **DSH `frames2d`**（`~/.dsh/pets/<id>/pet.json` + `thumb/<track>/*.webp`）
/// 2. **Codex atlas v2**（`~/.codex/pets/<id>/pet.json` + `spritesheet.webp`，1536×2288，8×11，cell 192×208）
public enum PackParser {
    public enum ParseError: Error, CustomStringConvertible {
        case notADirectory(URL)
        case missingManifest(URL)
        case invalidJSON(String)
        case unsupportedVersion(String)
        case emptyPack(String)

        public var description: String {
            switch self {
            case .notADirectory(let url): return "不是目录：\(url.path)"
            case .missingManifest(let url): return "缺少 pet.json：\(url.path)"
            case .invalidJSON(let detail): return "pet.json 解析失败：\(detail)"
            case .unsupportedVersion(let detail): return "不支持的版本：\(detail)"
            case .emptyPack(let detail): return "宠物包为空：\(detail)"
            }
        }
    }

    public static func parse(directory: URL) throws -> PetPack {
        let manifestURL = directory.appendingPathComponent("pet.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ParseError.missingManifest(directory)
        }

        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw ParseError.invalidJSON(error.localizedDescription)
        }

        let raw: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ParseError.invalidJSON("顶层不是对象")
            }
            raw = object
        } catch let error as ParseError {
            throw error
        } catch {
            throw ParseError.invalidJSON(error.localizedDescription)
        }

        // Codex 图集：有 spriteVersionNumber
        if let version = raw["spriteVersionNumber"] as? Int {
            guard version == 2 else {
                throw ParseError.unsupportedVersion("spriteVersionNumber=\(version)，仅支持 2")
            }
            return try parseAtlas(raw: raw, directory: directory)
        }

        // DSH 逐帧：有 petManifestVersion + frames2d
        if let version = raw["petManifestVersion"] as? Int {
            guard version == 2 else {
                throw ParseError.unsupportedVersion("petManifestVersion=\(version)，仅支持 2")
            }
            return try parseFrames2D(raw: raw, directory: directory)
        }

        throw ParseError.unsupportedVersion("无法识别的 pet.json 格式（既不是 frames2d 也不是 atlas）")
    }

    // MARK: - DSH frames2d

    private static func parseFrames2D(raw: [String: Any], directory: URL) throws -> PetPack {
        guard let frames2d = raw["frames2d"] as? [String: Any] else {
            throw ParseError.invalidJSON("缺少 frames2d")
        }

        let id = (raw["id"] as? String) ?? directory.lastPathComponent
        let displayName = (raw["displayName"] as? String) ?? id
        let detail = raw["description"] as? String
        let author = raw["author"] as? String
        let license = raw["license"] as? String
        let defaultFrameMs = (frames2d["defaultFrameMs"] as? Int) ?? 40
        let framesDirName = (frames2d["dir"] as? String) ?? "thumb"
        let framesRoot = directory.appendingPathComponent(framesDirName)

        let trackConfigs = (frames2d["tracks"] as? [String: Any]) ?? [:]
        var tracks: [String: PetTrack] = [:]

        // 轨道既可能显式声明，也可能只有目录存在
        var candidateNames = Set(trackConfigs.keys)
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: framesRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            for entry in entries where (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                candidateNames.insert(entry.lastPathComponent)
            }
        }

        for name in candidateNames {
            let config = trackConfigs[name] as? [String: Any] ?? [:]
            let directoryURL = framesRoot.appendingPathComponent(name)
            guard let frames = try? loadFrames(in: directoryURL, defaultFrameMs: defaultFrameMs),
                  !frames.frames.isEmpty
            else { continue }

            tracks[name] = PetTrack(
                name: name,
                frames: frames.frames,
                durationsMs: frames.durations,
                loop: (config["loop"] as? Bool) ?? true,
                fallback: config["fallback"] as? String
            )
        }

        guard !tracks.isEmpty else {
            throw ParseError.emptyPack("\(framesRoot.path) 下没有找到可用帧")
        }

        return PetPack(
            id: id,
            displayName: displayName,
            detail: detail,
            author: author,
            license: license,
            adapter: .frames2d,
            root: directory,
            tracks: tracks
        )
    }

    /// 逐帧目录：文件名形如 `<anything>-<index>_<durationMs>.webp`
    static func loadFrames(
        in directory: URL,
        defaultFrameMs: Int
    ) throws -> (frames: [PetFrameRef], durations: [Int]) {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "webp" || $0.pathExtension.lowercased() == "png" }

        guard !contents.isEmpty else { return ([], []) }

        var entries: [(index: Int, duration: Int, url: URL)] = []
        for url in contents {
            let name = url.deletingPathExtension().lastPathComponent
            let parts = name.split(separator: "_")
            let duration = parts.count >= 2 ? Int(parts[parts.count - 1]) ?? defaultFrameMs : defaultFrameMs
            let index: Int
            if let range = name.range(of: "-[0-9]+_", options: .regularExpression) {
                let digits = name[range].dropLast().dropFirst()
                index = Int(digits) ?? 0
            } else {
                index = entries.count
            }
            entries.append((index, duration, url))
        }

        entries.sort { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.url.lastPathComponent < rhs.url.lastPathComponent
        }

        return (entries.map { .file($0.url) }, entries.map { max($0.duration, 10) })
    }

    // MARK: - Codex atlas v2

    private static func parseAtlas(raw: [String: Any], directory: URL) throws -> PetPack {
        let id = (raw["id"] as? String) ?? directory.lastPathComponent
        let displayName = (raw["displayName"] as? String) ?? id
        let detail = raw["description"] as? String
        let sheetName = (raw["spritesheetPath"] as? String) ?? "spritesheet.webp"
        let sheetURL = directory.appendingPathComponent(sheetName)

        guard FileManager.default.fileExists(atPath: sheetURL.path) else {
            throw ParseError.emptyPack("缺少图集文件 \(sheetURL.lastPathComponent)")
        }

        // 图集规格来自 codex-pet-contract：1536×2288 = 8 列 × 11 行，cell 192×208
        let columns = 8
        let rows = 11
        let cellSize = CGSize(width: 192, height: 208)

        var tracks: [String: PetTrack] = [:]
        for (row, spec) in atlasRowSpecs.enumerated() {
            let frames = (0..<spec.frameCount).map { column in
                PetFrameRef.cell(row: row, column: column)
            }
            tracks[spec.name] = PetTrack(
                name: spec.name,
                frames: frames,
                durationsMs: spec.durations,
                loop: true,
                fallback: spec.fallback
            )
        }

        return PetPack(
            id: id,
            displayName: displayName,
            detail: detail,
            author: raw["author"] as? String,
            license: raw["license"] as? String,
            adapter: .atlas,
            root: directory,
            tracks: tracks,
            spriteSheet: sheetURL,
            cellSize: cellSize,
            columns: columns,
            rows: rows
        )
    }

    struct AtlasRowSpec {
        let name: String
        let frameCount: Int
        let durations: [Int]
        let fallback: String?
    }

    /// 行语义与逐帧时长来自 `~/.codex/skills/hatch-pet/references/animation-rows.md`
    static let atlasRowSpecs: [AtlasRowSpec] = [
        .init(name: "idle", frameCount: 6, durations: [280, 110, 110, 140, 140, 320], fallback: nil),
        .init(name: "running-right", frameCount: 8, durations: [120, 120, 120, 120, 120, 120, 120, 220], fallback: "idle"),
        .init(name: "running-left", frameCount: 8, durations: [120, 120, 120, 120, 120, 120, 120, 220], fallback: "idle"),
        .init(name: "waving", frameCount: 4, durations: [140, 140, 140, 280], fallback: "idle"),
        .init(name: "jumping", frameCount: 5, durations: [140, 140, 140, 140, 280], fallback: "idle"),
        .init(name: "failed", frameCount: 8, durations: [140, 140, 140, 140, 140, 140, 140, 240], fallback: "idle"),
        .init(name: "waiting", frameCount: 6, durations: [150, 150, 150, 150, 150, 260], fallback: "idle"),
        .init(name: "running", frameCount: 6, durations: [120, 120, 120, 120, 120, 220], fallback: "idle"),
        .init(name: "review", frameCount: 6, durations: [150, 150, 150, 150, 150, 280], fallback: "idle"),
        .init(name: "look-a", frameCount: 8, durations: Array(repeating: 200, count: 8), fallback: "idle"),
        .init(name: "look-b", frameCount: 8, durations: Array(repeating: 200, count: 8), fallback: "idle"),
    ]
}
