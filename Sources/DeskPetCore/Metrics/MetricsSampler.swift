import Foundation

/// 1Hz 指标采样器。
///
/// 所有系统调用都在独立串行队列上执行（Mach / IOKit 调用都不是零成本），
/// 结果以不可变 `SystemSnapshot` 交给回主线程的调用方。
public final class MetricsSampler: @unchecked Sendable {
    public struct Config: Sendable {
        /// 采样间隔，默认 1 秒
        public var interval: TimeInterval
        /// 低电量模式下放慢采样
        public var lowPowerInterval: TimeInterval

        public init(interval: TimeInterval = 1.0, lowPowerInterval: TimeInterval = 3.0) {
            self.interval = interval
            self.lowPowerInterval = lowPowerInterval
        }
    }

    public typealias SnapshotHandler = @Sendable (SystemSnapshot) -> Void

    private let queue = DispatchQueue(label: "com.we3le7.deskpet.metrics", qos: .utility)
    private let config: Config
    private let onSnapshot: SnapshotHandler

    private var timer: DispatchSourceTimer?
    private var cpu: CPUProvider
    private var memory = MemoryProvider()
    private var battery = BatteryProvider()
    private var network = NetworkProvider()
    private let disk = DiskProvider()
    private let thermal = ThermalProvider()

    public init(config: Config = Config(), onSnapshot: @escaping SnapshotHandler) {
        self.config = config
        self.onSnapshot = onSnapshot
        self.cpu = CPUProvider()
    }

    // MARK: - 生命周期

    public func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            let interval = self.config.interval
            timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(200))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let snapshot = self.collect()
                self.onSnapshot(snapshot)
                self.adjustCadenceIfNeeded(snapshot)
            }
            self.timer = timer
            timer.resume()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    /// 低电量时把采样放慢，减少唤醒。
    private var isCadenceSlow = false
    private func adjustCadenceIfNeeded(_ snapshot: SystemSnapshot) {
        let shouldSlow = snapshot.isLowPowerMode
        guard shouldSlow != isCadenceSlow else { return }
        isCadenceSlow = shouldSlow
        let interval = shouldSlow ? config.lowPowerInterval : config.interval
        timer?.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(300))
    }

    // MARK: - 采样

    /// 同步采一次（CLI 与自测用）。
    /// CPU 与网络都需要两次读数才有意义，所以先完整采一次建立基准，再采第二次。
    public func sampleOnce(warmUp: TimeInterval = 0.35) -> SystemSnapshot {
        queue.sync { _ = collect() }
        Thread.sleep(forTimeInterval: warmUp)
        return queue.sync { collect() }
    }

    private func collect() -> SystemSnapshot {
        let cpuUsage = cpu.sample()
        let memorySample = memory.sample()
        let batterySample = battery.sample()
        let networkSample = network.sample()
        let diskSample = disk.sample()
        let thermalSample = thermal.sample()

        return SystemSnapshot(
            timestamp: Date(),
            cpuUsage: cpuUsage,
            memoryUsedBytes: memorySample.usedBytes,
            memoryTotalBytes: memorySample.totalBytes,
            memoryPressure: memorySample.pressure,
            thermal: thermalSample.thermal,
            isLowPowerMode: thermalSample.isLowPowerMode,
            batteryLevel: batterySample.level,
            isCharging: batterySample.isCharging,
            isOnAC: batterySample.isOnAC,
            downloadBytesPerSecond: networkSample.downloadBytesPerSecond,
            uploadBytesPerSecond: networkSample.uploadBytesPerSecond,
            diskFreeBytes: diskSample.freeBytes,
            diskTotalBytes: diskSample.totalBytes,
            frontmostApp: nil
        )
    }
}
