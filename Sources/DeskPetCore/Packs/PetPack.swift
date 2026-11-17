import Foundation

/// 一帧的引用：逐帧包指向文件，图集包指向网格坐标。
public enum PetFrameRef: Sendable, Equatable {
    case file(URL)
    case cell(row: Int, column: Int)
}

/// 一条动画轨道。
public struct PetTrack: Sendable, Equatable {
    public var name: String
    public var frames: [PetFrameRef]
    /// 与 frames 一一对应的帧时长（毫秒）
    public var durationsMs: [Int]
    public var loop: Bool
    public var fallback: String?

    public init(
        name: String,
        frames: [PetFrameRef],
        durationsMs: [Int],
        loop: Bool = true,
        fallback: String? = nil
    ) {
        self.name = name
        self.frames = frames
        self.durationsMs = durationsMs
        self.loop = loop
        self.fallback = fallback
    }

    public var totalDurationMs: Int {
        durationsMs.reduce(0, +)
    }
}

/// 宠物包：解析后的统一表示，渲染层只认这个。
public struct PetPack: Sendable {
    public enum Adapter: String, Sendable, Equatable {
        /// 用户自制 / DSH 逐帧目录
        case frames2d
        /// Codex 1536×2288 图集
        case atlas
    }

    public var id: String
    public var displayName: String
    public var detail: String?
    public var author: String?
    public var license: String?
    public var adapter: Adapter
    public var root: URL
    public var tracks: [String: PetTrack]

    /// 图集包专用
    public var spriteSheet: URL?
    public var cellSize: CGSize?
    public var columns: Int
    public var rows: Int

    public init(
        id: String,
        displayName: String,
        detail: String? = nil,
        author: String? = nil,
        license: String? = nil,
        adapter: Adapter,
        root: URL,
        tracks: [String: PetTrack],
        spriteSheet: URL? = nil,
        cellSize: CGSize? = nil,
        columns: Int = 0,
        rows: Int = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.detail = detail
        self.author = author
        self.license = license
        self.adapter = adapter
        self.root = root
        self.tracks = tracks
        self.spriteSheet = spriteSheet
        self.cellSize = cellSize
        self.columns = columns
        self.rows = rows
    }

    public var trackNames: [String] { tracks.keys.sorted() }

    public func track(named name: String) -> PetTrack? { tracks[name] }

    /// 按候选顺序找第一条存在的轨道，找不到返回 nil（渲染层再退回矢量宠物）。
    public func firstTrack(among candidates: [String]) -> PetTrack? {
        for name in candidates {
            if let track = tracks[name], !track.frames.isEmpty {
                return track
            }
        }
        return nil
    }
}

/// 宠物包的来源与简述，用于菜单列表。
public struct PetPackDescriptor: Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var adapter: PetPack.Adapter
    public var root: URL
    public var trackCount: Int
    public var detail: String?

    public init(
        id: String,
        displayName: String,
        adapter: PetPack.Adapter,
        root: URL,
        trackCount: Int,
        detail: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.adapter = adapter
        self.root = root
        self.trackCount = trackCount
        self.detail = detail
    }
}
