import Foundation

/// 一次完整采样的结果。值类型，可跨线程传递。
public struct SystemSnapshot: Sendable, Equatable {
    public var timestamp: Date

    /// 全核 CPU 占用率 0...1
    public var cpuUsage: Double
    /// 内存已用字节（active + wired + compressed）
    public var memoryUsedBytes: UInt64
    /// 物理内存总量
    public var memoryTotalBytes: UInt64
    /// 内存压力 0...1（(wired + compressed) / total）
    public var memoryPressure: Double

    public var thermal: Thermal
    public var isLowPowerMode: Bool

    /// 电池电量 0...1；无电池设备为 nil
    public var batteryLevel: Double?
    /// 是否正在充电（插电但充满时为 false）
    public var isCharging: Bool
    /// 是否接着电源
    public var isOnAC: Bool

    public var downloadBytesPerSecond: Double
    public var uploadBytesPerSecond: Double

    public var diskFreeBytes: UInt64
    public var diskTotalBytes: UInt64

    /// 前台应用名（由 App 层填，Core 不依赖 AppKit）
    public var frontmostApp: String?

    public init(
        timestamp: Date = Date(),
        cpuUsage: Double = 0,
        memoryUsedBytes: UInt64 = 0,
        memoryTotalBytes: UInt64 = 0,
        memoryPressure: Double = 0,
        thermal: Thermal = .nominal,
        isLowPowerMode: Bool = false,
        batteryLevel: Double? = nil,
        isCharging: Bool = false,
        isOnAC: Bool = false,
        downloadBytesPerSecond: Double = 0,
        uploadBytesPerSecond: Double = 0,
        diskFreeBytes: UInt64 = 0,
        diskTotalBytes: UInt64 = 0,
        frontmostApp: String? = nil
    ) {
        self.timestamp = timestamp
        self.cpuUsage = cpuUsage
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryPressure = memoryPressure
        self.thermal = thermal
        self.isLowPowerMode = isLowPowerMode
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.isOnAC = isOnAC
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.diskFreeBytes = diskFreeBytes
        self.diskTotalBytes = diskTotalBytes
        self.frontmostApp = frontmostApp
    }
}
