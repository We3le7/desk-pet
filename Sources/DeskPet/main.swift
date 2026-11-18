import AppKit
import SwiftUI
import DeskPetCore

// CLI 参数优先于 GUI：方便脚本与 CI 调用（M2.5 会补全 --validate-pack 等）
let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--version") {
    print("DeskPet 0.1.0")
    exit(0)
}

// 打印当前收益快照（可与手算对数）
if arguments.contains("--earnings-once") {
    let config = SalaryConfig()
    let engine = EarningsEngine(config: config)
    let now = Date()
    let amount = engine.amount(at: now)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    print("上班鼓励器快照  \(formatter.string(from: now))")
    print("  \(config.summary)")
    print("  今日已工作 \(Int(amount.workedSeconds)) 秒")
    print("  今日已到账 \(MoneyFormat.yuan(amount.total))")
    print("  工作时段   \(amount.isWorking ? "是" : "否")")
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
      DeskPet --earnings-once          打印当前收益快照
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

    // 金额标签：渲染带金额的显示宿主，检查底部条带是否出现像素
    let labelPixels = renderMoneyLabel()
    if labelPixels < 200 {
        print("  FAIL 金额标签几乎没画出像素（\(labelPixels)）")
        failures += 1
    } else {
        print("  ok   金额标签可见（底部条带 \(labelPixels) 个不透明像素）")
    }

    // 宠物区与金额区不重叠：不写金额时，底部 48pt 应该几乎全透明
    let bandPixels = renderEmptyMoneyBand()
    if bandPixels > 200 {
        print("  FAIL 宠物压到了金额区（底部 \(bandPixels) 个像素）")
        failures += 1
    } else {
        print("  ok   宠物区与金额区不重叠（底部仅 \(bandPixels) 个像素）")
    }

    let earningsTab = renderSettingsPanel(tab: .earnings)
    if earningsTab.pixels < 3000 {
        print("  FAIL 设置面板「上班鼓励器」几乎没画出内容（\(earningsTab.pixels)）")
        failures += 1
    } else {
        print("  ok   设置面板「上班鼓励器」可渲染（\(earningsTab.pixels) 个不透明像素）")
    }

    // 时间选择器：上班/下班各一组，每组小时 24 项 + 分钟 12 项
    if earningsTab.comboItemCounts.sorted() == [12, 12, 24, 24] {
        print("  ok   时间选择器就位（\(earningsTab.comboItemCounts.sorted()) 项）")
    } else {
        print("  FAIL 时间选择器异常（发现 \(earningsTab.comboItemCounts)）")
        failures += 1
    }

    // 宠物标签页：显示开关 / 大小滑杆 / 皮肤列表
    let petTab = renderSettingsPanel(tab: .pet)
    if petTab.pixels < 3000 {
        print("  FAIL 设置面板「宠物」几乎没画出内容（\(petTab.pixels)）")
        failures += 1
    } else {
        print("  ok   设置面板「宠物」可渲染（\(petTab.pixels) 个不透明像素）")
    }
    if petTab.sliderCount >= 1 {
        print("  ok   宠物标签页含大小滑杆（\(petTab.sliderCount) 个）")
    } else {
        print("  FAIL 宠物标签页缺少大小滑杆")
        failures += 1
    }
    if petTab.previewCount >= 1 {
        print("  ok   预览区就位（\(petTab.previewCount) 个动态预览视图）")
    } else {
        print("  FAIL 预览区缺失")
        failures += 1
    }
    if petTab.thumbnailCount >= 2 {
        print("  ok   缩略图已生成（\(petTab.thumbnailCount) 张，含内置宠物）")
    } else {
        print("  FAIL 缩略图没生成（\(petTab.thumbnailCount) 张）")
        failures += 1
    }
    if petTab.packRowCount >= 2 {
        print("  ok   皮肤列表就位（\(petTab.packRowCount) 行，含内置宠物）")
    } else {
        print("  FAIL 皮肤列表为空（\(petTab.packRowCount) 行）")
        failures += 1
    }

    print(failures == 0 ? "自检通过" : "自检失败")
    return failures == 0 ? 0 : 1
}

/// 渲染一个带金额的显示宿主，统计窗口底部 30pt 内的不透明像素。
@MainActor
func renderMoneyLabel() -> Int {
    let size = CGSize(width: 200, height: 260)
    let scale: CGFloat = 2
    let width = Int(size.width * scale)
    let height = Int(size.height * scale)

    let view = PetDisplayView(frame: NSRect(origin: .zero, size: size))
    view.setMoneyText("¥1,234.56")
    view.layoutSubtreeIfNeeded()

    if ProcessInfo.processInfo.environment["DESKPET_DEBUG"] == "1" {
        print("  [debug] layer=\(view.layer != nil) sublayers=\(view.layer?.sublayers?.count ?? -1) "
              + "pillPath=\(view.moneyPillLayer.path != nil) "
              + "text=\(String(describing: view.moneyTextLayer.string))")
    }

    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
    ) else { return 0 }

    context.scaleBy(x: scale, y: scale)
    view.layer?.render(in: context)
    guard let data = context.data else { return 0 }

    let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
    var opaque = 0
    // 只看底部 36pt（标签所在区域）。注意 bitmap 内存第一行是**顶部**，所以要扫最后的行。
    let band = Int(36 * scale)
    for y in (height - band)..<height {
        for x in 0..<width {
            let index = (y * width + x) * 4
            if buffer[index] > 12 { opaque += 1 }
        }
    }
    return opaque
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


/// 离屏渲染设置面板，确认表单能正常布局出内容。
@MainActor
func renderSettingsPanel(tab: SettingsTab) -> (pixels: Int, comboItemCounts: [Int], sliderCount: Int, packRowCount: Int, previewCount: Int, thumbnailCount: Int) {
    let controller = EarningsController()
    let appearance = AppearanceStore()
    let catalog = PetsCatalog()
    if tab == .pet {
        // 让宠物包列表与缩略图都加载出来，才能验证皮肤行与预览
        catalog.reload()
        RunLoop.current.run(until: Date().addingTimeInterval(0.9))
        PetPreviewStore.shared.loadThumbnails(for: catalog.packs)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
    }
    let root: AnyView
    switch tab {
    case .earnings:
        root = AnyView(EarningsSettingsView(controller: controller))
    case .pet:
        root = AnyView(PetSettingsView(appearance: appearance, catalog: catalog))
    }
    let hosting = NSHostingView(rootView: root)
    let size = CGSize(width: 400, height: 580)
    hosting.frame = NSRect(origin: .zero, size: size)
    hosting.layoutSubtreeIfNeeded()

    let combos = collectComboBoxes(in: hosting)
    let itemCounts = combos.map { $0.numberOfItems }

    let scale: CGFloat = 1
    let width = Int(size.width * scale)
    let height = Int(size.height * scale)
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
    ) else { return (0, [], 0, 0, 0, 0) }

    // 目录色（catalog color）不能直接取分量，先转到 sRGB
    let background = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? NSColor.white
    context.setFillColor(background.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    hosting.layer?.render(in: context)
    guard let data = context.data else { return (0, [], 0, 0, 0, 0) }

    let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
    var differing = 0
    let backgroundRed = Int(background.redComponent * 255)
    for index in stride(from: 0, to: width * height * 4, by: 4) {
        // 文字/控件像素与纯背景不同就算"画出来了"
        if abs(Int(buffer[index + 1]) - backgroundRed) > 12 { differing += 1 }
    }
    let sliderCount = collectViews(in: hosting, ofType: NSSlider.self)
    // 皮肤行是 SwiftUI Button，无法从 AppKit 视图树数出来，改用目录行数 + 像素双重校验
    let packRowCount = tab == .pet ? (catalog.packs.count + 1) : 0
    let previewCount = collectViews(in: hosting, ofType: PetDisplayView.self)
    let thumbnailCount = tab == .pet ? PetPreviewStore.shared.thumbnails.count : 0
    return (differing, itemCounts, sliderCount, packRowCount, previewCount, thumbnailCount)
}

@MainActor
func collectViews<T: NSView>(in view: NSView, ofType: T.Type) -> Int {
    var count = (view is T) ? 1 : 0
    for subview in view.subviews {
        count += collectViews(in: subview, ofType: ofType)
    }
    return count
}

func collectComboBoxes(in view: NSView) -> [NSComboBox] {
    var found: [NSComboBox] = []
    if let combo = view as? NSComboBox { found.append(combo) }
    for subview in view.subviews {
        found.append(contentsOf: collectComboBoxes(in: subview))
    }
    return found
}


/// 不写金额文本时，窗口底部 48pt（金额区）应几乎透明 —— 用来守住"宠物不许压到金额区"。
@MainActor
func renderEmptyMoneyBand() -> Int {
    let size = PetPanel.defaultSize
    let scale: CGFloat = 2
    let width = Int(size.width * scale)
    let height = Int(size.height * scale)

    let view = PetDisplayView(frame: NSRect(origin: .zero, size: size))
    view.layoutSubtreeIfNeeded()

    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
    ) else { return 0 }

    context.scaleBy(x: scale, y: scale)
    view.layer?.render(in: context)
    guard let data = context.data else { return 0 }

    let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
    let band = Int(PetPanel.moneyAreaHeight * scale)
    var opaque = 0
    for y in (height - band)..<height {
        for x in 0..<width {
            if buffer[(y * width + x) * 4] > 12 { opaque += 1 }
        }
    }
    return opaque
}
