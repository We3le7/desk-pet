import Foundation

/// 磁盘容量与热压力/低电量模式。都是廉价调用，1Hz 采样无压力。
public struct DiskProvider: Sendable {
    public struct Sample: Sendable, Equatable {
        public var freeBytes: UInt64
        public var totalBytes: UInt64
    }

    public init() {}

    public func sample() -> Sample {
        let path = NSHomeDirectory()
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path),
              let free = attributes[.systemFreeSize] as? NSNumber,
              let total = attributes[.systemSize] as? NSNumber
        else {
            return Sample(freeBytes: 0, totalBytes: 0)
        }
        return Sample(freeBytes: free.uint64Value, totalBytes: total.uint64Value)
    }
}

/// 热压力与低电量模式。
public struct ThermalProvider: Sendable {
    public struct Sample: Sendable, Equatable {
        public var thermal: Thermal
        public var isLowPowerMode: Bool
    }

    public init() {}

    public func sample() -> Sample {
        let info = ProcessInfo.processInfo
        let thermal: Thermal
        switch info.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .nominal
        }
        return Sample(thermal: thermal, isLowPowerMode: info.isLowPowerModeEnabled)
    }
}
