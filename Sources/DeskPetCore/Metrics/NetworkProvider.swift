import Darwin
import Foundation

/// 网络吞吐：`getifaddrs` 拿各接口的 `if_data` 字节计数，两次采样求速率。
///
/// 注意：`ifi_ibytes` / `ifi_obytes` 是 **32 位**计数，会在 4 GB 处回绕，
/// 因此做差时要按回绕处理，否则会出现巨大的负值。
public struct NetworkProvider: Sendable {
    public struct Sample: Sendable, Equatable {
        public var downloadBytesPerSecond: Double
        public var uploadBytesPerSecond: Double
    }

    private var previousIn: UInt64?
    private var previousOut: UInt64?
    private var previousTime: Date?

    public init() {}

    public mutating func sample(at date: Date = Date()) -> Sample {
        guard let counters = Self.readCounters() else {
            return Sample(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
        }

        defer {
            previousIn = counters.inBytes
            previousOut = counters.outBytes
            previousTime = date
        }

        guard let previousIn, let previousOut, let previousTime else {
            return Sample(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
        }

        let elapsed = max(date.timeIntervalSince(previousTime), 0.001)
        let inDelta = Self.delta(current: counters.inBytes, previous: previousIn)
        let outDelta = Self.delta(current: counters.outBytes, previous: previousOut)

        return Sample(
            downloadBytesPerSecond: Double(inDelta) / elapsed,
            uploadBytesPerSecond: Double(outDelta) / elapsed
        )
    }

    /// 处理 32 位计数回绕：当前值小于上次时，认为跨越了一次 2^32。
    private static func delta(current: UInt64, previous: UInt64) -> UInt64 {
        if current >= previous { return current - previous }
        return (current + (1 << 32)) - previous
    }

    private static func readCounters() -> (inBytes: UInt64, outBytes: UInt64)? {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let first = addressList else { return nil }
        defer { freeifaddrs(addressList) }

        var inBytes: UInt64 = 0
        var outBytes: UInt64 = 0

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let name = String(cString: interface.ifa_name)
            // 跳过回环与系统隧道接口，只统计真实网卡
            guard !name.hasPrefix("lo"), !name.hasPrefix("gif"), !name.hasPrefix("stf"),
                  !name.hasPrefix("utun"), !name.hasPrefix("awdl"), !name.hasPrefix("llw")
            else { continue }
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.ifa_data
            else { continue }

            let statistics = data.assumingMemoryBound(to: if_data.self).pointee
            inBytes += UInt64(statistics.ifi_ibytes)
            outBytes += UInt64(statistics.ifi_obytes)
        }

        return (inBytes, outBytes)
    }
}
