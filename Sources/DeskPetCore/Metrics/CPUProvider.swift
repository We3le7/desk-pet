import Darwin
import Foundation

/// CPU 占用率：读 `host_processor_info` 的 tick 计数，求两次采样的差值。
/// 首次采样没有基准，返回 0。
public struct CPUProvider: Sendable {
    private var previous: [UInt32]?

    public init() {
        previous = nil
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        if result == KERN_SUCCESS, let info {
            // 注意：infoCount = CPU 数 × CPU_STATE_MAX(4)，不是 CPU 数
            previous = Self.flatten(info, count: Int(infoCount))
            Self.deallocate(info, count: Int(infoCount))
        }
    }

    /// 返回全核平均占用率 0...1。
    public mutating func sample() -> Double {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return 0 }
        defer { Self.deallocate(info, count: Int(infoCount)) }

        let current = Self.flatten(info, count: Int(infoCount))
        defer { previous = current }

        guard let previous, previous.count == current.count else { return 0 }

        var totalDelta: Double = 0
        var busyDelta: Double = 0
        var index = 0
        while index < current.count {
            let user = Double(current[index].wrappingSubtract(previous[index]))
            let system = Double(current[index + 1].wrappingSubtract(previous[index + 1]))
            let idle = Double(current[index + 2].wrappingSubtract(previous[index + 2]))
            let nice = Double(current[index + 3].wrappingSubtract(previous[index + 3]))

            busyDelta += user + system + nice
            totalDelta += user + system + nice + idle
            index += 4
        }

        guard totalDelta > 0 else { return 0 }
        return min(max(busyDelta / totalDelta, 0), 1)
    }

    private static func flatten(_ info: processor_info_array_t, count: Int) -> [UInt32] {
        var values = [UInt32]()
        values.reserveCapacity(count)
        for index in 0..<count {
            values.append(UInt32(bitPattern: info[index]))
        }
        return values
    }

    private static func deallocate(_ info: processor_info_array_t, count: Int) {
        vm_deallocate(
            mach_task_self_,
            vm_address_t(UInt(bitPattern: info)),
            vm_size_t(count * MemoryLayout<integer_t>.stride)
        )
    }
}

private extension UInt32 {
    /// tick 计数会回绕，用截断减法求增量。
    func wrappingSubtract(_ other: UInt32) -> UInt32 {
        self &- other
    }
}
