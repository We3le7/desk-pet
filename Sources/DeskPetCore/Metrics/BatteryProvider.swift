import Foundation
import IOKit.ps

/// 电池与供电状态。台式机没有电池，返回 level = nil。
public struct BatteryProvider: Sendable {
    public struct Sample: Sendable, Equatable {
        public var level: Double?
        public var isCharging: Bool
        public var isOnAC: Bool
    }

    public init() {}

    public func sample() -> Sample {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty
        else {
            return Sample(level: nil, isCharging: false, isOnAC: false)
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int
            let maximum = description[kIOPSMaxCapacityKey] as? Int
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let state = description[kIOPSPowerSourceStateKey] as? String

            var level: Double?
            if let current, let maximum, maximum > 0 {
                level = min(max(Double(current) / Double(maximum), 0), 1)
            }

            return Sample(
                level: level,
                isCharging: charging,
                isOnAC: state == kIOPSACPowerValue
            )
        }

        return Sample(level: nil, isCharging: false, isOnAC: false)
    }
}
