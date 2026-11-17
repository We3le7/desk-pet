import Foundation

/// 发现本机可用的宠物包。
public struct PetLibrary: Sendable {
    public var searchPaths: [URL]

    public init(searchPaths: [URL] = PetLibrary.defaultSearchPaths) {
        self.searchPaths = searchPaths
    }

    /// 依次是：DeskPet 自有目录 → DSH 宠物 → Codex 宠物
    public static var defaultSearchPaths: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/DeskPet/pets"),
            home.appendingPathComponent(".dsh/pets"),
            home.appendingPathComponent(".codex/pets"),
        ]
    }

    /// 扫描所有搜索目录。解析失败的包会被跳过（不会让整个列表失败）。
    public func discover() -> [PetPack] {
        var packs: [PetPack] = []
        var seen = Set<String>()

        for root in searchPaths {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey]
            ) else { continue }

            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                guard let pack = try? PackParser.parse(directory: entry) else { continue }
                guard !seen.contains(pack.id) else { continue }
                seen.insert(pack.id)
                packs.append(pack)
            }
        }

        return packs
    }

    public func load(id: String) -> PetPack? {
        discover().first { $0.id == id }
    }
}
