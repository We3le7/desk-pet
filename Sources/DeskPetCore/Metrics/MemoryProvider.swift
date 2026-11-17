import Darwin
import Foundation

/// 内存用量与压力。
///
/// 只用 `free` 判断会永远告警（macOS 会把空闲内存拿去做缓存），
/// 这里用 `active + wired + compressed` 算已用，用 `(wired + compressed) / total` 算压力。
public struct MemoryProvider: Sendable {
    public struct Sample: Sendable, Equatable {
        public var usedBytes: UInt64
        public var totalBytes: UInt64
        public var pressure: Double
    }

    public init() {}

    public func sample() -> Sample {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let total = ProcessInfo.processInfo.physicalMemory

        guard result == KERN_SUCCESS else {
            return Sample(usedBytes: 0, totalBytes: total, pressure: 0)
        }

        let pageBytes = UInt64(pageSize)
        let active = UInt64(stats.active_count) * pageBytes
        let wired = UInt64(stats.wire_count) * pageBytes
        let compressed = UInt64(stats.compressor_page_count) * pageBytes
        let used = active + wired + compressed

        let pressure: Double
        if total > 0 {
            pressure = min(Double(wired + compressed) / Double(total), 1)
        } else {
            pressure = 0
        }

        return Sample(usedBytes: used, totalBytes: total, pressure: pressure)
    }
}
