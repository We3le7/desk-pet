import AppKit
import DeskPetCore

// CLI 参数优先于 GUI：方便脚本与 CI 调用（M2.5 会补全 --validate-pack 等）
let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--version") {
    print("DeskPet 0.1.0")
    exit(0)
}

// 检查某个宠物包：轨道映射 + 首帧解码统计（我看不到屏幕，用像素统计代替肉眼）
if let index = arguments.firstIndex(of: "--check-pack") {
    let id = arguments.count > index + 1 ? arguments[index + 1] : "jyn"
    exit(runPackCheck(id: id))
}

// 列出本机可用的宠物包
if arguments.contains("--list-pets") {
    let library = PetLibrary()
    let packs = library.discover()
    if packs.isEmpty {
        print("未发现宠物包（搜索：~/.dsh/pets、~/.codex/pets、Application Support/DeskPet/pets）")
    } else {
        print("发现 \(packs.count) 个宠物包：")
        for pack in packs {
            print("  \(pack.id.padding(toLength: 14, withPad: " ", startingAt: 0))"
                  + " \(pack.adapter.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0))"
                  + " \(String(format: "%2d", pack.tracks.count)) 轨"
                  + "  \(pack.displayName)"
                  + "  [\(pack.license ?? "无许可声明")]")
        }
    }
    exit(0)
}

// 各 Provider 耗时基准（优化采样频率用）
if let index = arguments.firstIndex(of: "--bench-metrics") {
    let iterations = arguments.count > index + 1 ? (Int(arguments[index + 1]) ?? 20) : 20
    let filter = arguments.count > index + 2 ? arguments[index + 2] : nil
    runMetricsBench(iterations: iterations, filter: filter)
    exit(0)
}

// 采一次指标并打印（用于与 top / vm_stat / pmset 对数）
if arguments.contains("--metrics-once") {
    printMetricsOnce()
    exit(0)
}

// 离屏渲染自检：确认宠物图层真的画出了像素（当前模型无法看图，用像素统计代替肉眼）
if arguments.contains("--self-check-ui") {
    exit(runUISelfCheck())
}

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    DeskPet 0.1.0 — 桌面状态宠物 + 上班鼓励器

    用法：
      DeskPet                 启动（常驻菜单栏 + 桌面悬浮宠物）
      DeskPet --version       打印版本
      DeskPet --help          显示帮助

    规划中的命令：
      DeskPet --validate-pack <path>   校验宠物包
      DeskPet --convert ...            图集转逐帧
      DeskPet --export-template <dir>  导出宠物模板
      DeskPet --self-check-ui          离屏渲染自检（开发用）
      DeskPet --metrics-once           采一次系统指标并打印（开发/校验用）
      DeskPet --bench-metrics [n]      各 Provider 耗时基准（开发用）
      DeskPet --list-pets              列出本机可用的宠物包
      DeskPet --check-pack <id>        解码并统计某个宠物包（开发用）
    """)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()


// MARK: - 离屏渲染自检

/// 把宠物视图渲染到 bitmap，统计不透明像素与平均色，验证「画了东西」且「情绪影响配色」。
@MainActor
func runUISelfCheck() -> Int32 {
    func render(mood: PetMood) -> (opaque: Int, color: (Double, Double, Double)) {
        let size = CGSize(width: 240, height: 300)
        let scale: CGFloat = 2
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)

        let view = PetView(frame: NSRect(origin: .zero, size: size))
        view.mood = mood
        view.layoutSubtreeIfNeeded()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return (0, (0, 0, 0)) }

        context.scaleBy(x: scale, y: scale)
        view.layer?.render(in: context)

        guard let data = context.data else { return (0, (0, 0, 0)) }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var opaque = 0
        var sumR = 0.0, sumG = 0.0, sumB = 0.0
        for index in stride(from: 0, to: width * height * 4, by: 4) {
            let alpha = Double(buffer[index])
            guard alpha > 12 else { continue }
            opaque += 1
            sumR += Double(buffer[index + 1])
            sumG += Double(buffer[index + 2])
            sumB += Double(buffer[index + 3])
        }
        guard opaque > 0 else { return (0, (0, 0, 0)) }
        return (opaque, (sumR / Double(opaque), sumG / Double(opaque), sumB / Double(opaque)))
    }

    let idle = render(mood: .idle)
    let busy = render(mood: .busy)
    let total = Int(240 * 2 * 300 * 2)

    print("离屏渲染自检")
    print("  idle  不透明像素 \(idle.opaque) / \(total)  \(String(format: "%.1f", 100 * Double(idle.opaque) / Double(total)))%")
    print("  busy  不透明像素 \(busy.opaque) / \(total)  \(String(format: "%.1f", 100 * Double(busy.opaque) / Double(total)))%")

    var failures = 0
    if idle.opaque < 1000 {
        print("  FAIL 几乎没画出东西（< 1000 像素）")
        failures += 1
    } else {
        print("  ok   idle 有可见内容")
    }

    let colorDelta = abs(idle.color.0 - busy.color.0) + abs(idle.color.1 - busy.color.1)
        + abs(idle.color.2 - busy.color.2)
    if colorDelta < 8 {
        print(String(format: "  FAIL 情绪未影响配色（平均色差 %.1f）", colorDelta))
        failures += 1
    } else {
        print(String(format: "  ok   情绪影响配色（平均色差 %.1f）", colorDelta))
    }

    print(failures == 0 ? "自检通过" : "自检失败")
    return failures == 0 ? 0 : 1
}


// MARK: - 单次采样打印

func printMetricsOnce() {
    let sampler = MetricsSampler { _ in }
    let snapshot = sampler.sampleOnce()

    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    print("DeskPet 指标快照  \(formatter.string(from: snapshot.timestamp))")
    print("  CPU        \(Humanize.precisePercent(snapshot.cpuUsage))")
    print("  内存       \(Humanize.bytes(snapshot.memoryUsedBytes)) / \(Humanize.bytes(snapshot.memoryTotalBytes))"
          + "  压力 \(Humanize.percent(snapshot.memoryPressure))")
    print("  电池       \(snapshot.batteryLevel.map(Humanize.percent) ?? "无电池")"
          + "  充电:\(snapshot.isCharging ? "是" : "否")  电源:\(snapshot.isOnAC ? "AC" : "电池")")
    print("  网络       ↓ \(Humanize.rate(snapshot.downloadBytesPerSecond))  ↑ \(Humanize.rate(snapshot.uploadBytesPerSecond))")
    print("  磁盘       \(Humanize.bytes(snapshot.diskFreeBytes)) 可用 / \(Humanize.bytes(snapshot.diskTotalBytes))")
    print("  热压力     \(snapshot.thermal)  低电量模式:\(snapshot.isLowPowerMode ? "开" : "关")")
    print("")
    print("RAW cpu=\(String(format: "%.4f", snapshot.cpuUsage))"
          + " mem_used=\(snapshot.memoryUsedBytes)"
          + " mem_total=\(snapshot.memoryTotalBytes)"
          + " pressure=\(String(format: "%.4f", snapshot.memoryPressure))"
          + " battery=\(snapshot.batteryLevel.map { String(format: "%.3f", $0) } ?? "nil")"
          + " charging=\(snapshot.isCharging)"
          + " ac=\(snapshot.isOnAC)"
          + " rx=\(Int(snapshot.downloadBytesPerSecond))"
          + " tx=\(Int(snapshot.uploadBytesPerSecond))"
          + " disk_free=\(snapshot.diskFreeBytes)"
          + " disk_total=\(snapshot.diskTotalBytes)")
}


// MARK: - Provider 耗时基准

func runMetricsBench(iterations: Int, filter: String? = nil) {
    func measure(_ label: String, _ body: () -> Void) {
        // 预热一次，避免首调用开销影响
        body()
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { body() }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        let perCall = elapsed / Double(iterations)
        print(String(format: "  %@ %7.3f ms/次", label.padding(toLength: 8, withPad: " ", startingAt: 0), perCall))
    }

    print("Provider 耗时基准（\(iterations) 次）")
    var cpu = CPUProvider()
    let memory = MemoryProvider()
    let battery = BatteryProvider()
    var network = NetworkProvider()
    let disk = DiskProvider()
    let thermal = ThermalProvider()

    let names = ["CPU", "内存", "电池", "网络", "磁盘", "热压力"]
    if filter == nil || filter == "CPU" { measure("CPU") { _ = cpu.sample() } }
    if filter == nil || filter == "内存" { measure("内存") { _ = memory.sample() } }
    if filter == nil || filter == "电池" { measure("电池") { _ = battery.sample() } }
    if filter == nil || filter == "网络" { measure("网络") { _ = network.sample() } }
    if filter == nil || filter == "磁盘" { measure("磁盘") { _ = disk.sample() } }
    if filter == nil || filter == "热压力" { measure("热压力") { _ = thermal.sample() } }
    _ = names
}


// MARK: - 宠物包检查

@MainActor
func runPackCheck(id: String) -> Int32 {
    guard let pack = PetLibrary().load(id: id) else {
        print("未找到宠物包：\(id)")
        return 1
    }

    print("宠物包 \(pack.id) · \(pack.displayName)")
    print("  适配器   \(pack.adapter.rawValue)")
    print("  轨道数   \(pack.tracks.count)")
    print("  许可     \(pack.license ?? "无声明")  作者 \(pack.author ?? "未知")")
    print("  路径     \(pack.root.path)")
    print("")
    print("情绪 → 轨道映射：")

    var failures = 0
    for mood in [PetMood.idle, .busy, .sleeping, .pet, .celebrate, .overheat] {
        let candidates = MoodTrackMap.candidates(for: mood, adapter: pack.adapter)
        if let track = pack.firstTrack(among: candidates) {
            let loopText = track.loop ? "循环" : "一次性"
            print("  \(mood.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) → "
                  + "\(track.name.padding(toLength: 12, withPad: " ", startingAt: 0))"
                  + "\(String(format: "%3d", track.frames.count)) 帧 "
                  + "\(track.totalDurationMs) ms  \(loopText)")
        } else {
            print("  \(mood.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) → 无可用轨道")
            failures += 1
        }
    }

    guard let idle = pack.firstTrack(among: ["idle"]) else {
        print("\n❌ 没有 idle 轨道")
        return 1
    }

    // 按窗口尺寸（240×300 内的 160×213）在 2× 下解码
    let target = CGSize(width: 160, height: 213)
    let started = DispatchTime.now().uptimeNanoseconds
    guard let loaded = FrameCache.inspect(pack: pack, track: idle, targetSize: target, scale: 2) else {
        print("\n❌ 首帧解码失败")
        return 1
    }
    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000

    print("")
    print("idle 解码结果：")
    print("  帧数     \(loaded.frames.count)\(loaded.didSubsample ? "（已按内存预算跳帧采样）" : "")")
    print("  内存     \(String(format: "%.1f", Double(loaded.bytes) / 1024 / 1024)) MB")
    print("  耗时     \(String(format: "%.0f", elapsedMs)) ms（含解码全部帧）")

    guard let first = loaded.frames.first else { return 1 }
    print("  单帧尺寸 \(first.width)×\(first.height) px")

    let stats = pixelStats(of: first)
    print("  不透明像素 \(String(format: "%.1f", stats.opaqueRatio * 100))%")
    print("  平均色   RGB(\(Int(stats.color.0)), \(Int(stats.color.1)), \(Int(stats.color.2)))")

    if stats.opaqueRatio < 0.01 {
        print("\n❌ 几乎全透明，可能解错了文件")
        failures += 1
    }
    if loaded.frames.count < 2 {
        print("\n⚠️ 帧数少于 2，动画会退化成静态图")
        failures += 1
    }

    print(failures == 0 ? "\n✅ 检查通过" : "\n❌ 有 \(failures) 项问题")

    // 诊断用：保持存活，方便从外部看内存构成
    if let hold = ProcessInfo.processInfo.environment["DESKPET_HOLD_SECONDS"].flatMap(Double.init) {
        print("(保持 \(Int(hold)) 秒，pid=\(ProcessInfo.processInfo.processIdentifier))")
        fflush(stdout)
        Thread.sleep(forTimeInterval: hold)
    }

    return failures == 0 ? 0 : 1
}

@MainActor
func pixelStats(of image: CGImage) -> (opaqueRatio: Double, color: (Double, Double, Double)) {
    let width = image.width
    let height = image.height
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
    ) else { return (0, (0, 0, 0)) }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = context.data else { return (0, (0, 0, 0)) }
    let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

    var opaque = 0
    var sumR = 0.0, sumG = 0.0, sumB = 0.0
    for index in stride(from: 0, to: width * height * 4, by: 4) {
        let alpha = Double(buffer[index])
        guard alpha > 12 else { continue }
        opaque += 1
        sumR += Double(buffer[index + 1])
        sumG += Double(buffer[index + 2])
        sumB += Double(buffer[index + 3])
    }
    guard opaque > 0 else { return (0, (0, 0, 0)) }
    let count = Double(opaque)
    return (Double(opaque) / Double(width * height), (sumR / count, sumG / count, sumB / count))
}
