import Foundation

/// 数值格式化。刻意不依赖 `ByteCountFormatter`（其输出随地区变化），
/// 保证自测断言稳定。
public enum Humanize {
    /// 1536 → "1.5 KB"，3_000_000 → "2.9 MB"
    public static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var amount = Double(value)
        var index = 0

        while amount >= 1024, index < units.count - 1 {
            amount /= 1024
            index += 1
        }

        if index == 0 {
            return "\(Int(amount)) B"
        }
        return String(format: "%.1f %@", amount, units[index])
    }

    /// 字节/秒 → "1.2 MB/s"
    public static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "0 B/s" }
        let capped = UInt64(min(bytesPerSecond, 1e15))
        return bytes(capped) + "/s"
    }

    /// 0.42 → "42%"
    public static func percent(_ value: Double) -> String {
        let clamped = min(max(value, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// 0.42 → "42.3%"
    public static func precisePercent(_ value: Double) -> String {
        let clamped = min(max(value, 0), 1)
        return String(format: "%.1f%%", clamped * 100)
    }
}
