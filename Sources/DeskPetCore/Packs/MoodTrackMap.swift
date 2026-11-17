import Foundation

/// 情绪 → 动画轨道的映射。
///
/// 不同格式的轨道命名完全不同（DSH 用 `work`/`shy`，Codex 用 `running`/`waving`），
/// 这里给出候选列表，渲染层取第一个存在的轨道，全部缺失时再退回矢量宠物。
public enum MoodTrackMap {
    public static func candidates(for mood: PetMood, adapter: PetPack.Adapter) -> [String] {
        switch adapter {
        case .frames2d:
            switch mood {
            case .idle: return ["idle"]
            case .busy: return ["work", "idle"]
            case .overheat: return ["work-fail", "work", "idle"]
            case .tired: return ["idle"]
            case .charging: return ["idle"]
            case .sleeping: return ["sleeping", "sleep", "idle"]
            case .celebrate: return ["work-success", "work", "idle"]
            case .pet: return ["shy", "shy2", "shy3", "idle"]
            case .slacking: return ["idle"]
            }
        case .atlas:
            switch mood {
            case .idle: return ["idle"]
            case .busy: return ["running", "idle"]
            case .overheat: return ["failed", "idle"]
            case .tired: return ["idle"]
            case .charging: return ["idle"]
            // Codex 图集没有睡眠行，靠 idle 定格 + 装饰表现
            case .sleeping: return ["idle"]
            case .celebrate: return ["jumping", "idle"]
            case .pet: return ["waving", "idle"]
            case .slacking: return ["waiting", "idle"]
            }
        }
    }

    /// 一次性情绪（播完回落），影响是否循环。
    public static func isOneShot(_ mood: PetMood) -> Bool {
        switch mood {
        case .celebrate, .pet, .overheat: return true
        default: return false
        }
    }
}
