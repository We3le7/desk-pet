# DeskPet 技术方案（v0.1，待确认）

> 桌面状态宠物 + 上班赚钱鼓励器。目标产物：一个双击可装的 `DeskPet.dmg`。
> 本文所有"已验证"标记均在本机 macOS 27.3 / M5 arm64 上实测过，命令与结果见 §15。

---

## 0. TL;DR 决策表

| 维度 | 结论 | 一句话理由 |
| --- | --- | --- |
| 语言/UI | Swift + AppKit 窗口层 + SwiftUI 内容层 | 本机只有 CLT，SwiftUI 可用但受宏限制（§2） |
| 工程形态 | SPM package + Makefile 组装 .app | 没有 Xcode，`xcodebuild archive` 不可用 |
| 第三方依赖 | 0（不用 Lottie / Sparkle / Charts） | 少一个依赖少一个坑，自绘矢量宠物足够 |
| 状态采集 | IOKit / Mach / sysctl 原生调用 | 全部零权限，不弹任何授权框 |
| 宠物素材 | **复用本机已有资产**（DSH `frames2d` / Codex atlas v2）+ 对外 `petpack` v1 规范（§7.3），app 不内置第三方美术，只留代码矢量兜底 | 109.5MB 素材不进 DMG；别人也能按格式上传自己的宠物 |
| 签名 | ad-hoc（`codesign -s -`） | 无 Developer ID 证书（§11.3） |
| 分发 | `make dmg` 产出 UDZO 镜像 | 已验证可挂载、可拖入 Applications |
| 最低系统 | macOS 14.0（Sonoma） | 覆盖足够广，且能用 `SMAppService` 开机自启 |
| 架构 | arm64 only | Intel Mac 止步 macOS 26；v1 不做 universal |
| 测试 | 自建 `DeskPetSelfTest` 可执行 + 手工验收清单 | CLT 里既无 XCTest 也无 Swift Testing（§2.3） |

---

## 1. 目标与非目标

### 1.1 目标

1. **桌面上的活物**：一个常驻桌面的小宠物，透明无边框、可拖动、切 Space / 全屏都不消失、不抢焦点。
2. **真实的系统状态**：CPU / 内存 / 电池 / 网络 / 磁盘 / 前台应用 / 热压力，映射成宠物的情绪和动作。
3. **上班鼓励器**：按你的薪资算出"每秒到账多少钱"，数字滚动 + 金币动画 + 里程碑庆祝。
4. **宠物可以换**：内置两套现有格式的直接读取（DSH / Codex 目录），并提供 `petpack` v1 规范——用户把自己的宠物按格式丢进来就能用，不用改代码（§7.3）。
5. **能给别人装**：`make dmg` 一条命令出镜像，别人拖进 Applications 就能用。
6. **不像个监控软件**：闲置 CPU < 1.5%、内存 < 60MB、有电池友好降频。

### 1.2 非目标（v1 明确不做）

- ❌ 温度 / 风扇转速 —— Apple Silicon 的 SMC 是闭源私有 API，`powermetrics` 要 sudo，做了也不准（§6.7）
- ❌ App Store 上架 / 沙箱
- ❌ 自动更新（Sparkle）、云同步、账号体系
- ❌ 多语言（先只做中文）
- ❌ 历史数据图表 / 长期统计落库
- ❌ Electron / Tauri 跨端

---

## 2. 环境事实（已实测，决定了三条硬约束）

| 探测 | 本机结果 | 方案影响 |
| --- | --- | --- |
| 系统 | macOS 27.3，arm64 | 可用新 API，但为分发设 `LSMinimumSystemVersion=14.0` |
| Swift | 6.4.2（swiftlang-6.4.2.1.9） | 用 `swift-tools-version:6.0` |
| Xcode | **未安装**，只有 `/Library/Developer/CommandLineTools` | ❗ 不能用 `.xcodeproj`，必须 SPM + 手工 bundle |
| SDK | MacOSX27.2.sdk | SwiftUI / AppKit 齐全 |
| 签名证书 | `security find-identity` → **0 valid identities** | ❗ 只能 ad-hoc，Gatekeeper 会拦 |
| hdiutil / iconutil / codesign | 均在 | DMG 链路可做 |
| create-dmg | 未安装 | 不依赖它，自己写脚本 |

### 2.1 ❗约束一：没有 Xcode → 只能 SPM

`xcodebuild` 直接报错 `requires Xcode`。因此放弃"新建 Xcode 工程 + archive 导出"，改为：

```
swift build -c release  →  手工组装 DeskPet.app  →  codesign  →  DMG
```

这条路**已经跑通**（§15.2）：SPM 编译出的可执行文件放进 `Contents/MacOS/`、写 `Info.plist`、配 icns，`codesign --sign -` 后能正常启动。

### 2.2 ❗约束二：SwiftUI 的 `@State` 是宏，CLT 里编译不过

实测报错：

```
error: external macro implementation type 'SwiftUIMacros.StateMacro'
       could not be found for macro 'State()'; plugin for module 'SwiftUIMacros' not found
```

`SwiftUIMacros` 插件随 Xcode 分发，CLT 只有 `libSwiftMacros.dylib`（Swift 自带宏），不包含 SwiftUI 宏。

**已验证可用**的替代写法（§15.3）：

| 写法 | CLT 下 |
| --- | --- |
| `@State` / `@Bindable` | ❌ 编译失败 |
| `@StateObject` / `@ObservedObject` / `@Environment` / `@Published` | ✅ 通过 |

⇒ **编码规范（必须写进 AGENTS.md）**：

- 视图状态一律走 `final class XxxStore: ObservableObject` + `@StateObject`（根）/ `@ObservedObject`（子）。
- 禁止 `@State`，禁止 `@Bindable`，绑定用 `Binding(get:set:)` 手写或 `store.binding(for:)` 辅助方法。
- 生成代码前先自查 `grep -n "@State\b"`，CI 脚本加一条 `make lint-macros`。

### 2.3 ❗约束三：CLT 没有测试框架

`swift test` 报 `unable to resolve module dependency: 'XCTest'`；`Testing.swiftmodule` 在 CLT 里也不存在。二者都只随 Xcode 提供。

⇒ 测试策略改为：

1. **纯函数核心抽成 `DeskPetCore` target**（无 AppKit 依赖），全部逻辑在此，可在无 UI 环境下跑。
2. **自建 `DeskPetSelfTest` 可执行**：零依赖断言（`expect()` 手写 + 退出码非 0 即失败），`swift run DeskPetSelfTest` 一条命令跑完，覆盖薪资计算、工时段判定、情绪阈值滞回、数字格式化。
3. **UI/窗口部分走手工验收清单**（§12 每个里程碑都有明确验收动作）。

这样既不引入依赖，也保住"改动行为必须同步测试"的底线。

---

## 3. 技术选型与理由

### 3.1 为什么是 Swift（而不是 Electron / Tauri）

| 方案 | 体积 | 闲置内存 | 系统指标获取 | 结论 |
| --- | --- | --- | --- | --- |
| Swift + AppKit/SwiftUI | ~3-5 MB | 30-60 MB | 原生 syscall，零权限 | ✅ 选它 |
| Electron | 120 MB+ | 250-400 MB | 要装 native helper / 调 `ps` | ❌ 一个"监控资源"的工具自己吃 400MB 很讽刺 |
| Tauri 2 | ~8 MB | 60-100 MB | 要写 Rust FFI 调 IOKit | ❌ 本机未装 Rust，迭代慢一倍 |

### 3.2 为什么 AppKit + SwiftUI 混合

- **窗口层必须 AppKit**：`NSPanel` 才能精确控制 `.nonactivatingPanel`（不抢焦点）、`.borderless`、`level = .floating`、`collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`（全屏/Space 都可见）、`ignoresMouseEvents`（点击穿透）。SwiftUI 的 `WindowGroup` 做不到这些。
- **内容层用 SwiftUI**：宠物表情、数字滚动、金币粒子用声明式写起来快 3 倍，且 `Canvas` / `TimelineView` 自带动画时序。
- **兜底**：若 SwiftUI 在透明窗口上出现阴影发灰、模糊等渲染问题（历史常见），宠物本体退回 `CALayer` + `CAShapeLayer` 手绘，只保留设置面板用 SwiftUI。这条退路已确认可编译（§15.4），不会卡死。

**实测结论（M0 已验证，2026-11-17）**：这条"退路"其实是**正选**。宠物本体用 SwiftUI `TimelineView` + `Canvas` 逐帧重绘时，60fps 吃 **7.6%** CPU、压到 12fps 仍有 **2.6%**；改成纯 `CALayer` + CA 动画（呼吸、眨眼、摆动、星星环绕全部交给 render server）后降到 **0.27%**。

⇒ 硬规则：**宠物渲染层一律 Core Animation；SwiftUI 只用于设置面板这类不做持续动画的界面。**

### 3.3 为什么零依赖

- Lottie：宠物素材要设计稿，阻塞进度；且 SPM 拉包在本机网络下不一定顺。
- 不用 `Charts`：v1 不做历史图表。
- 不用 Sparkle：v1 手动下载新 dmg 即可。
- 图标：SF Symbols 直接用于菜单栏；app 图标用代码生成的首版（§11.2）。

---

## 4. 架构与数据流

```
                 ┌──────────────────────────────────────┐
  1 Hz 心跳 ───▶ │  MetricsSampler (serial queue)       │
                 │  ├ CPUProvider     host_processor_info│
                 │  ├ MemoryProvider  host_statistics64 │
                 │  ├ BatteryProvider IOPowerSources    │
                 │  ├ NetworkProvider getifaddrs(if_data)│
                 │  ├ DiskProvider    fileSystemAttrs    │
                 │  ├ FrontmostProvider NSWorkspace      │
                 │  └ ThermalProvider ProcessInfo        │
                 └──────────────┬───────────────────────┘
                                │ Snapshot (struct, 值类型)
                                ▼
                 ┌──────────────────────────┐     ┌────────────────────┐
                 │  PetStateMachine         │     │  EarningsEngine    │
                 │  指标 → Mood(带滞回)      │     │  薪资 → 每秒增量    │
                 └────────────┬─────────────┘     └─────────┬──────────┘
                              │                             │
                              └──────────┬──────────────────┘
                                         ▼
                            ┌────────────────────────┐
                            │  PetStore: Observable  │  (@MainActor)
                            │  Object（单一真相源）   │
                            └───────┬────────────────┘
                                    │ @ObservedObject
                     ┌──────────────┼───────────────┐
                     ▼              ▼               ▼
              PetView(悬浮窗)  MenuBarController  SettingsView
```

**关键设计**：

- 采集在后台串行队列，**只回主线程推一个不可变 `Snapshot`**，UI 无锁。
- `PetStore` 是唯一状态源，`@MainActor` 标注，所有 mutation 走主线程，规避 Swift 6 严格并发报错。
- 每个 Provider 是 `protocol MetricProvider { var id: String { get }; func sample() -> Value }`，可单独替换/关掉（设置里能勾"不采集网络"）。
- 采样与动画解耦：**采样 1 Hz，动画 30 fps**，动画插值用上一帧 + 目标值做平滑，避免 1Hz 数字跳变。

---

## 5. 目录结构

```
desk-pet/
├── Package.swift                  # 3 targets: DeskPetCore / DeskPet / DeskPetSelfTest
├── Makefile                       # build / app / sign / dmg / run / lint-macros / validate-sample / clean
├── AGENTS.md                      # 本项目约定（禁 @State、测试怎么跑、打包怎么发）
├── README.md                      # 给"别人"看的：安装、首次打开绕过 Gatekeeper、卸载
├── docs/
│   ├── PETPACK_SPEC.md            # 宠物包规范（给做宠物的人看，§7.3）
│   └── MAKE_YOUR_PET.md           # 三分钟做一个自己的宠物（含工具链 walkthrough）
├── Sources/
│   ├── DeskPetCore/               # 纯逻辑，无 AppKit，可测
│   │   ├── Models/{Snapshot.swift, Mood.swift, SalaryConfig.swift}
│   │   ├── Metrics/{Sampler.swift, CPU.swift, Memory.swift, Battery.swift,
│   │   │            Network.swift, Disk.swift, Frontmost.swift, Thermal.swift}
│   │   ├── Earnings/{Engine.swift, Formatter.swift, Milestone.swift}
│   │   ├── Packs/                 # 宠物包：解析 + 校验 + 修复（§7.3）
│   │   │   ├── PackSpec.swift         # petpack v1 schema 结构体
│   │   │   ├── PackValidator.swift    # 硬错误 / 警告分级校验
│   │   │   ├── PackDoctor.swift       # 自动修复：裁边、统一尺寸、补时长
│   │   │   ├── PackConverter.swift    # 图集 ⇄ 逐帧双向转换
│   │   │   ├── DshManifest.swift      # DSH frames2d 适配器
│   │   │   └── AtlasManifest.swift    # Codex atlas v2 适配器
│   │   └── Rules/{MoodRules.swift, WorkSchedule.swift}
│   ├── DeskPet/                   # App 层
│   │   ├── main.swift             # 先解析 CLI 参数（--validate-pack 等）再决定是否起 GUI
│   │   ├── App/{AppDelegate.swift, LoginItem.swift, StatusBarController.swift}
│   │   ├── Windows/{PetPanel.swift, SettingsWindow.swift}
│   │   ├── Store/{PetStore.swift, SettingsStore.swift}
│   │   ├── PetKit/                # 宠物渲染层（§7）
│   │   │   ├── PetPack.swift          # 统一接口：tracks / frames / durations
│   │   │   ├── DshPack.swift          # frames2d 逐帧目录 → PetPack
│   │   │   ├── AtlasPack.swift        # 1536×2288 图集切格子 → PetPack
│   │   │   ├── FrameCache.swift       # 预缩放 + LRU(2 轨) + 后台解码
│   │   │   ├── TrackPlayer.swift      # 按 manifest 时长/loop/fallback 推进
│   │   │   ├── PetPackImporter.swift  # 导入：文件夹 / zip / DSH / Codex / 单张图集
│   │   │   └── FallbackPetView.swift  # 代码矢量兜底宠物（Canvas）
│   │   ├── Views/{PetView.swift, CoinBurst.swift, MoneyCounter.swift,
│   │   │         SettingsView.swift, PetPickerView.swift, PetImportView.swift,
│   │   │         ValidationReportView.swift, DebugPanel.swift}
│   │   ├── Resources/
│   │   │   ├── Info.plist, AppIcon.icns
│   │   │   └── Templates/sample.petpack/   # 内置示例包（自绘，无版权风险）
│   │   └── CLI/{ValidatePack.swift, ConvertAtlas.swift, ExportTemplate.swift}
│   └── DeskPetSelfTest/main.swift  # 零依赖断言
├── scripts/{bundle.sh, sign.sh, dmg.sh, make-icon.sh, make-sample-pack.sh}
└── dist/                          # gitignore：DeskPet.app, DeskPet.dmg
```

> 为什么 `DeskPetCore` 单独成 target：它不 import AppKit，能被 SelfTest 直接链接，将来想加 iOS 端或改成 CLI 都不用重构。

---

## 6. 系统指标采集规格

统一入口：`MetricsSampler`，`DispatchSourceTimer` 1 Hz，串行队列 `.utility`。每个指标带**采样耗时上限**（>50ms 记为告警并降级）。

| # | 指标 | API | 计算方式 | 坑 |
| --- | --- | --- | --- | --- |
| 6.1 | CPU 使用率 | `host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO)` | 保存上次 tick，求各核 `(user+system+nice)/(total)` 的 Δ 平均；同时拿到每核值算 P/E 负载 | 返回的数组要 `vm_deallocate`，否则每秒泄漏 |
| 6.2 | 内存 | `host_statistics64(HOST_VM_INFO64)` → `vm_statistics64` | `used = (active + wired + compressed) × pageSize`；`pressure` 用 `(wired+compressed)/total` | 别用 `ProcessInfo.physicalMemory - free`，macOS 的 free 极低会永远告警 |
| 6.3 | 电池 | `IOPSCopyPowerSourcesInfo` + `IOPSGetPowerSourceDescription` | 取 `Current Capacity` / `Is Charging` / `Time to Empty` | 台式机无电池 → 返回 nil，宠物要能"无电池模式" |
| 6.4 | 网络速率 | `getifaddrs` → `ifa_data` 的 `if_data.ifi_ibytes/ifi_obytes` | en0 两次采样差值 ÷ Δt，转 KB/s | 要跳过 `lo0`；Wi-Fi 切网时计数会重置，需判负归零 |
| 6.5 | 磁盘 | `FileManager.default.attributesOfFileSystem(forPath: "/")` | `free/total` | — |
| 6.6 | 前台应用 | `NSWorkspace.shared.frontmostApplication` | bundleID + localizedName | 需要 `NSWorkspace.didActivateApplicationNotification` 而不是轮询 |
| 6.7 | 温度/热压力 | `ProcessInfo.processInfo.thermalState` + `isLowPowerModeEnabled` | 枚举 `.nominal/.fair/.serious/.critical` | **不做真实温度**：SMC 私有 API（`IOHIDEventSystemClient` 拿 AppleSMC）无公开文档、系统升级即失效，不放进 v1 |
| 6.8 | 亮屏/睡眠 | `NSWorkspace.willSleep/didWake` 通知 | 睡眠时停采样、停动画 | 否则合盖后仍占 CPU（电池杀手） |

**权限成本：0**。以上全部是公开 API，不触发任何 TCC 授权弹窗。这是选原生 Swift 的最大收益——Electron 方案想拿网络字节数就得装 root helper。

---

## 7. 宠物：形象、情绪与动作

### 7.1 形象来源：复用本机已有宠物资产（已探测，两套格式）

本机 `~/.codex/pets/` 与 `~/.dsh/pets/` 已经躺着完整的宠物动画资产，**不需要再画美术**。

| 格式 | 位置 | 结构 | 体量 | 语义 |
| --- | --- | --- | --- | --- |
| **DSH `frames2d`（v2）** | `~/.dsh/pets/jyn/` | `pet.json` + `thumb/<track>/{id}-<track>-<n>_<ms>.webp` 逐帧文件 | 22 track / 1542 帧 / **109.5 MB**，单帧 512×683，默认 40ms | 自带 `tracks`（loop/fallback）、`skins`（3 套皮肤 + 各自 idle/clickActions/gameplayTracks）、`gameplay`（hunger/mood/energy/affection 数值） |
| **Codex atlas v2** | `~/.codex/pets/{codepeng,forgefox,trumpchibi,xichibi}/` | `pet.json` + 单张 `spritesheet.webp` | 1536×2288，8 列 × 11 行，cell **192×208** | 行 0-8 = idle / running-right / running-left / waving / jumping / failed / waiting / running / review，**每行帧时长写死**（见 §7.2）；行 9-10 = 16 个朝向 |

关键结论：

1. **两套都不大改代码就能吃**——都是"manifest + 帧序列"，抽象成 `PetPack` 接口即可。
2. **不打包进 app**：109.5 MB 塞进 DMG 会让镜像从 5 MB 变 110 MB，且 `trumpchibi` 之类有肖像/版权风险。默认从磁盘读用户已装的宠物，app 本体保持 ~5 MB。
3. **必须留兜底**：别人机器上没有 `~/.dsh/pets`，首次启动要有形象 → 保留"代码宠物"作为 fallback。**已实现**（`Sources/DeskPet/Views/PetView.swift`）：纯 `CALayer`/`CAShapeLayer` 画圆角身体 + 眼睛，9 种情绪各一套配色与装饰（zzz / 汗滴 / 星星），动画全走 CA。
4. WebP 解码**不需要第三方库**：`sips` 能直接读 `spritesheet.webp` 与帧文件 ⇒ ImageIO 支持 WebP ⇒ `NSImage(contentsOf:)` 可用（已实测）。

### 7.2 情绪 → 动画轨道映射

`PetMood`（§7.2.2）是应用层的语义，渲染层负责映射到具体格式的轨道：

| `PetMood` | DSH `frames2d` track | Codex v2 row | 备注 |
| --- | --- | --- | --- |
| `.idle` | `idle`（皮肤则用 `skins[].idleTrack`） | `idle` | 默认循环 |
| `.busy` | `work` | `running` | CPU 高 | 
| `.sleeping` | `sleeping` | *无* → 取 `idle` 首帧定格 + 叠加 zzz | Codex 格式缺睡眠态，需补视觉装饰 |
| `.celebrate` | `work-success` | `jumping` | 里程碑，一次性不循环 |
| `.overheat` | `work-fail` | `failed` | 过热/内存告急 |
| `.pet`（摸头） | `shy`/`shy2`/`shy3`，或按 `skins[].clickActions` 的 `probability` 随机 | `waving` | 一次性，`fallback` 回 idle |
| `.slacking`（摸鱼） | `idle` + 语速更慢 | `waiting` | 可选关 |
| `.review` | `idle` | `review` | 里程碑后的"验收"姿态，可省略 |

实现要点：`tracks[name].loop == false` 时播完按 `fallback` 字段回落；`probability` 走加权随机（manifest 里 `0.3/0.3333` 这类值直接用）。

#### 7.2.1 帧时长怎么来

- DSH：文件名后缀就是帧时长（`..._40.webp` = 40ms），`defaultFrameMs` 兜底。
- Codex：每行时长在 contract 里写死（如行 0 = `280,110,110,140,140,320`ms），最后用 `contentTransition` 外的方式按表逐帧推进，不按固定 fps 播。

#### 7.2.2 情绪判定（带滞回，防抖）

| 触发条件（持续 N 秒） | Mood | 表现 |
| --- | --- | --- |
| CPU > 70% 持续 30s | `.busy` | 切 `work` / `running` |
| 内存压力 > 85% 持续 60s | `.stuffy` | `work` + 喘气装饰 |
| 热压力 `.serious` 以上 | `.hot` | `work-fail` + 汗滴 |
| 电池 < 20% 且未充电 | `.tired` | 降速 idle + zzz |
| 充电中 | `.charging` | idle + 闪电装饰 |
| 工作时段内网络 < 5 KB/s 持续 5min | `.slacking` | `waiting`（可关） |
| 非工作时段 / 深夜 23:00-7:00 | `.sleeping` | `sleeping` / 定格 idle |
| 达成赚钱里程碑 | `.celebrate`（临时 3s） | `work-success` / `jumping` |
| 其他 | `.idle` | 循环 idle + 随机眨眼 |

**滞回**：进入与退出阈值差 ≥10%（CPU 70% 进、60% 出），连续 3 次采样确认，避免宠物每秒抽搐。

#### 7.2.3 帧缓存与解码（这是本项目最大的性能风险）

1542 帧 × 512×683 全解码 ≈ 1542 × 1.4 MB ≈ **2.1 GB**，绝不能全加载。策略：

1. **预缩放**：首次加载把该 track 的帧按当前显示尺寸（默认 180×240 @2x → 360×480）用 `CGContext` 高质量缩一次，结果缓存在内存（360×480×4B ≈ 690 KB/帧，idle 78 帧 ≈ 54 MB —— 仍偏大，故默认缩到 1x 显示尺寸 180×240 ≈ 173 KB/帧，78 帧 ≈ 13.5 MB）。
2. **只留当前 track + 一个预取 track**，切情绪时异步换、LRU 上限 2 个 track。
3. **解码在串行后台队列**，`NSImage`/`CGImage` 回主线程前先转好，避免掉帧。
4. 窗口缩放（⌘+滚轮）时**不重新解码**，改缩放 CGImage 采样（最多模糊一点），松手 500ms 后按新尺寸重建缓存。
5. 内存数字要写进验收：加载 idle track 后 RSS 增量 < 30 MB。

#### 7.2.4 资产合规（必须写进 README）

- `jyn`：`license: MIT`，`author: 11726`，来源 `dsh-market.com` —— 可再分发，但**必须保留版权与许可声明**。
- `codepeng`（"以本人照片为基础"）、`forgefox`、`xichibi`：`pet.json` **无 license 字段** ⇒ 视为不可再分发。
- `trumpchibi`：真人形象 ⇒ 一律不打包。

⇒ 决策：**app 不内置任何第三方宠物**，只内置"代码矢量兜底宠物"。想给别人一只完整宠物，就让对方自己装，或用 `.petpack` 导入（§7.2.5）。

#### 7.2.5 导入入口

三种来源都走同一个导入器（细节见 §7.3.6）：已装的 DSH 目录、已装的 Codex 目录、用户自制的 `petpack`（文件夹 / zip）。落盘位置统一为 `~/Library/Application Support/DeskPet/pets/<id>/`，校验通过后出现在列表里。

### 7.3 自定义宠物：`petpack` v1 规范（用户按格式上传即可）

目标：**任何人按格式丢一个文件夹/zip 进来就能用自己的宠物，不用改代码、不用等我们发版**。同时把已装的两套格式当成内置适配器，省掉"必须先转换"的门槛。

#### 7.3.1 四条设计原则

1. **声明式，零脚本**：包里只有 `pet.json` + 图片。不执行任何用户代码，不解析 SVG / 动画 GIF。
2. **一个规范、三种适配器**：`adapter: "deskpet" | "dsh" | "codex-atlas"`。后两者直接吃现有目录，前者是给用户自己做的。
3. **最少 1 条 `idle` 就能用**：不等用户做满 22 条轨道，缺的轨全部有降级策略（§7.3.4）。
4. **可离线自检**：`DeskPet --validate-pack <path>`，用户在导入前就知道哪张图不合格。

#### 7.3.2 两种目录形态

```
my-pet/                      # 形态 A：逐帧（推荐，最灵活）
├── pet.json
└── frames/
    ├── idle/000.webp 001.webp 002.webp …
    └── work/000.webp 001.webp …

my-pet/                      # 形态 B：单张图集（最省事）
├── pet.json                 # { "adapter": "codex-atlas", … }
└── spritesheet.webp         # 1536×2288，8×11 网格
```

两种都可以**再 zip 成 `.petpack` 文件**（本质是 zip），拖进 app 即可。

#### 7.3.3 `pet.json` 最小可用示例

```json
{
  "schemaVersion": 1,
  "id": "my-pet",
  "displayName": "我的宠物",
  "author": "xpeng",
  "license": "MIT",
  "description": "一句话描述",
  "adapter": "deskpet",
  "canvas": { "width": 512, "height": 683, "anchor": "bottom-center" },
  "tracks": {
    "idle":  { "dir": "frames/idle",  "durationMs": 80, "loop": true },
    "work":  { "dir": "frames/work",  "durationMs": 60, "loop": true },
    "sleep": { "dir": "frames/sleep", "durationMs": 120, "loop": true },
    "pet":   { "dir": "frames/shy",   "loop": false, "fallback": "idle" }
  },
  "moodMap": { "busy": "work", "sleeping": "sleep", "celebrate": "work", "pet": "pet" }
}
```

| 字段 | 必填 | 约束 / 默认 |
| --- | --- | --- |
| `schemaVersion` | ✅ | 只接受 `1`，其他版本明确拒绝并提示升级 |
| `id` | ✅ | `^[a-z0-9][a-z0-9-]{1,39}$`，同时是落盘目录名 |
| `displayName` | ✅ | ≤ 40 字符 |
| `adapter` | ✅ | `deskpet` / `dsh` / `codex-atlas` |
| `canvas` | ✅ | `width/height`（≤2048）+ `anchor`（`bottom-center` 默认 / `center`） |
| `tracks` | ✅ | 至少含 `idle`；`dir` 或 `frames[]` 二选一 |
| `tracks.*.loop` | — | 默认 `true`；`false` 播完回落 `fallback` |
| `tracks.*.durationMs` | — | 默认 80ms；优先于文件名/图集里的时长 |
| `moodMap` | — | 缺省用内置映射（§7.2 的表） |
| `skins` | — | 可选，结构与 `tracks` 同级，用于多皮肤 |
| `license` / `author` | — | 强烈建议填，导入后展示在宠物详情里 |

#### 7.3.4 内容要求与缺失降级

| 要求 | 值 | 超限处理 |
| --- | --- | --- |
| 图片格式 | WebP（推荐）/ PNG | 其他格式硬错误 |
| 背景 | 透明 | 不透明 → 警告 |
| 单帧尺寸 | ≤ 2048×2048，且全 pack 一致 | 不一致 → 警告 + 自动 padding 到最大画布 |
| 帧数 | 单轨 ≤ 400，总计 ≤ 3000 | 超限硬错误 |
| 解压后体积 | ≤ 500 MB、≤ 8000 文件 | 超限硬错误 |
| 命名 | `frames/` 下按数字升序，或 `frames[]` 显式给顺序 | 非法命名警告 + 按字典序兜底 |

**缺轨道怎么降级**（用户只交 1 条 idle 也能跑）：

| 缺的轨 | 降级 |
| --- | --- |
| `work` | 用 `idle` 以 1.3× 速播放（有"更忙"的观感） |
| `sleep` | `idle` 首帧定格 + 叠加 zzz 装饰（§7.2 已支持） |
| `pet`（摸头） | 用 `idle` 加一次挤压回弹（代码补间） |
| `celebrate` | `idle` + 金币粒子，不改帧 |

#### 7.3.5 三级校验

| 级别 | 典型问题 | 行为 |
| --- | --- | --- |
| **硬错误** | 缺 `pet.json`、JSON 语法错、无 `idle` 轨、图片解码失败、`id` 非法、路径穿越、可执行文件 | 拒绝导入，报告可一键复制发给作者 |
| **警告** | 缺 `work`/`sleep`、画布尺寸不一致、单帧时长 > 2000ms、alpha 全透明、主体贴边（裁边会切到） | 允许导入，列表标黄，给"一键修复"（`PackDoctor`） |
| **信息** | 有 `skins`、有 16 向、含 `gameplay` 配置 | 展示在宠物详情里 |

#### 7.3.6 导入流程

```
拖入（文件夹 / .petpack / 单张图集）
   │
   ├─ zip → ditto -xk 解压到 tmp/（不跟随符号链接）
   ├─ PackValidator：结构 → 解码 → 规格 → 安全，四项
   ├─ 有硬错误 → 报告页（红色可复制），结束
   ├─ 有警告 → 报告页（黄色）+「PackDoctor 一键修」
   └─ 通过 → 落盘 ~/Library/Application Support/DeskPet/pets/<id>/
              → 列表出现缩略图 → 点一下即切换并预览播放
```

`PackDoctor` 能自动做的四件事：`trim` 裁 alpha 包围盒、`pad` 统一画布、`fill-duration` 补默认时长、`synth-work` 由 idle 生成 work 轨。**它只写自己的数据目录，不碰用户原件**（原件留在原地，报告里给"另存为"路径）。

#### 7.3.7 随 app 一起给的自助工具

```bash
# 1. 校验（导入前自查，也可接进自己的 CI）
DeskPet --validate-pack ~/Downloads/my-pet.petpack

# 2. 图集 → 逐帧（想把生成图集手改的人用）
DeskPet --convert --atlas spritesheet.webp --out my-pet/ --fps 8

# 3. 导出可编辑模板（含 6 帧自绘 idle + 全字段注释 + 占位轨道）
DeskPet --export-template ~/Desktop/my-pet/
```

模板包里直接写清楚"替换 `frames/idle/*.webp` 即可"，配合 `docs/MAKE_YOUR_PET.md` 一页教程（含用 `sips`/`ffmpeg` 批量导出帧的命令）。

#### 7.3.8 安全边界（app 未签名分发，必须防）

- 不执行包内任何内容；不解压符号链接/硬链接；解压后逐项校验路径仍在目标根内（zip slip）。
- 图片只经 ImageIO 解码，**不解析 SVG、不解析动画 GIF**（防解码炸弹），并设像素上限。
- v1 不做"从 URL 导入"，避免成为任意下载器；v2 若要加，加域名白名单 + 哈希展示。

#### 7.3.9 与现有生态的关系

| 场景 | 做法 |
| --- | --- |
| 已装 DSH 宠物（`~/.dsh/pets/x`） | 直接在列表里选，不需要转换（`adapter: dsh`） |
| 已装 Codex 宠物（`~/.codex/pets/x`） | 直接在列表里选（`adapter: codex-atlas`） |
| 想手改某只宠物 | `--convert` 切成逐帧再改，改完仍可直接用 |
| 想分享给别人 | 把目录 zip 成 `.petpack` 发出去，对方拖进 app 即可 |

### 7.4 交互

| 操作 | 行为 |
| --- | --- |
| 拖动 | 移动窗口；松手吸附最近屏幕边缘（阈值 20pt） |
| 单击 | 摸头：好感度 +1（当日上限 20），触发爱心粒子 |
| 双击 | 展开/收起"今日面板"（金额、时长、指标卡片） |
| 右键 | 菜单：暂停鼓励器 / 点击穿透 / 隐藏数字（老板键）/ 设置 / 退出 |
| ⌘ + 滚轮 | 缩放宠物 60%~200% |
| ⌘⇧H | 全局快捷键：隐藏/显示金额（防同事围观） |

窗口记忆：`x/y/size/screenUUID` 存 UserDefaults，屏幕拔插后校验位置是否仍在可见区域，否则拉回主屏右下角。

---

## 8. 上班鼓励器（EarningsEngine）

### 8.1 计算公式

```
等效月薪 = 税后月薪 × (12 + 年终额外月数) / 12
每秒收入 = 等效月薪 / (月均工作日 × 每日工时 × 3600)      # 合同时薪口径
今日金额 = clamp(现在 - 上班时间, 0, 下班 - 上班) 的秒数 × 每秒收入 - 午休扣除
```

> 注意口径：每秒收入按**合同时薪**（8h/天）折算，而累加窗口是**实际在岗**（09:30–19:00 = 9.5h）。
> 所以在岗一整天到账 = 9.5h × 时薪，比"一天工资"多约 19% —— 因为待在工位这件事本身就在计钱。

默认值（可在设置里全改）：

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| 税后月薪 | 21,000 | 以实发到账为准，不要填税前 |
| 年终月份数 | 2 | 摊进每秒，可选关闭 |
| 月均工作日 | 21.75 | 法定折算值 |
| 每日工时 | 8 | 含午休就填 8，不含填 9 |
| 工作时段 | 09:30–19:00 | 只在区间内累加 |

算出来的量级（用于校验观感，不是工资建议）：

- 时薪 ≈ 120.7 元/h
- **每秒 ≈ 0.0335 元**（约 3 分钱/秒）
- 每分钟 ≈ 2.0 元，**在岗一天（9.5h）≈ 1,147 元**

⇒ "每秒 3 分钱"这个量级刚好——**数字位数少、滚动明显、不至于看起来像假数据**。如果时薪太高（每秒 > 1 元），默认走"每 100ms 滚动 3 位小数"，并自动切换到"每分钟到账"模式。

### 8.2 累加规则

- 只在 `[上斑时间, 下班时间]` 且 `工作日`（默认周一~周五，可勾选调休日）内累加。
- 中间**不扣午休**（v1 简化，设置里可选"扣除午休 90min"）。
- 应用退出/系统睡眠：**按时间戳补算**（记录 `lastTickAt` + `accumulated`，重启后补上睡眠期间的差值，但睡眠期间标记为"离线不计"可选）。
- 手动暂停：`暂停` 时数字变灰并停止累加（摸鱼时用）。
- 加班：下班后若仍在前台工作，可选"加班 1.5x 计入"，v1 只做开关不做倍率配置。

### 8.3 视觉表现

| 元素 | 实现 |
| --- | --- |
| 主数字 | `¥ 12.34`，等宽数字字体（`.monospacedDigit()`），逐位滚动用 `contentTransition(.numericText())` + `withAnimation(.snappy)` |
| 今日累计 | 次行小字 `今日 ¥ 966.00 / 8.0h` |
| 进度环 | 距离下一个整十元（¥970）的环，`Circle().trim` 动画 |
| 金币粒子 | `CoinBurst`：达成里程碑时 8~12 个小圆从宠物底部抛物线飞出，`TimelineView(.animation)` 驱动，2s 后自动清理对象池 |
| 里程碑 | 每 ¥50 一次小庆祝，每 ¥500 一次大庆祝（抖动 + 换表情 3s + 音效可选） |
| 老板键 | ⌘⇧H 数字替换为 `***`，同时暂停动画 |

---

## 9. 窗口与并发规格

```swift
final class PetPanel: NSPanel {
    // styleMask: [.borderless, .nonactivatingPanel]
    // isOpaque = false, backgroundColor = .clear, hasShadow = false
    // level = .floating
    // collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    // hidesOnDeactivate = false
    // override canBecomeKey/canBecomeMain = false  → 永不抢焦点
}
```

- 设置窗口用普通 `NSWindow`（可聚焦、有标题栏），与 PetPanel 分离。
- `NSApplication.setActivationPolicy(.accessory)` + `LSUIElement=1` → 不占 Dock、不进 ⌘Tab。
- 点击穿透：`ignoresMouseEvents = true`（右键菜单可切换），穿透时宠物变半透明提示。
- **拖拽**：`mouseDown` 记录偏移，`mouseDragged` 改 `frame.origin`，`mouseUp` 吸附。不用 `isMovableByWindowBackground`（会和点击事件打架）。

### 9.1 并发模型（Swift 6 严格模式）

- `MetricsSampler` 在专用 serial queue；provider 的 C 指针运算全部在该队列内。
- `Snapshot` 是 `struct Sendable`，跨线程只传值。
- `PetStore` 标 `@MainActor`，`Timer` 用 `AsyncStream`/`DispatchSourceTimer` 汇入主线程。
- 所有 UI 类型 `@MainActor`，避免 Swift 6 报 `sending` 错误。

---

## 10. 性能与功耗预算

| 项 | 目标 | 手段 |
| --- | --- | --- |
| 闲置 CPU | < 1.5%（**实测 0.57%**：采样 0.20% + 状态栏约 0.3%） | 宠物渲染走 CA 动画（§3.2）；采样 1Hz 低电量降 3s；状态栏文字纯按时间节流 5s |
| 内存（无宠物） | < 40 MB（**实测 footprint 16 MB**） | 零依赖、快照值类型、粒子对象池上限 24 |
| 内存（加载宠物） | 目标 < 30 MB，**实测 +54 MB（未达标）** | 已做预跳帧 + 预缩放 + 单轨缓存；剩余开销来自 ImageIO 解码缓冲与 CA 纹理，见 §15.8 与 M5 跟进项 |
| 首次切 track 延迟 | < 120 ms | 后台队列解码 + 预取下一个可能 track（按调色板优先级） |
| 电池 | 低电量模式自动降级 | `isLowPowerModeEnabled` → 采样 3s、动画 8fps、停粒子 |
| 屏幕睡眠/合盖 | 完全停摆 | 监听 `willSleep`，`DispatchSourceTimer` suspend |
| 采样耗时 | < 50ms/次 | 每 provider 计时，超时告警并本次跳过 |
| 自测 | `scripts/perf.sh` 用 `ps -o %cpu,rss` 每 10s 采样 60s | 不依赖 Xcode 的 Instruments |

---

## 11. 打包与分发流水线

### 11.1 Makefile 目标

```make
make build    # swift build -c release --product DeskPet
make test     # swift run -c release DeskPetSelfTest
make app      # 组装 dist/DeskPet.app（二进制 + Info.plist + AppIcon.icns）
make sign     # codesign --force --sign - --options runtime dist/DeskPet.app
make dmg      # dist/DeskPet.dmg（含 Applications 软链 + 背景图）
make verify   # codesign -dv / spctl -a / hdiutil verify + 挂载检查
make run      # 直接启动 dist 里的 app（开发用）
make clean
```

`Info.plist` 关键键（已验证可启动）：

```xml
CFBundleExecutable      DeskPet
CFBundleIdentifier      com.xpeng.deskpet      <!-- 固定，影响偏好与登录项 -->
CFBundleName            DeskPet
CFBundlePackageType     APPL
CFBundleShortVersionString 0.1.0
CFBundleVersion         1
CFBundleIconFile        AppIcon
LSMinimumSystemVersion  14.0
LSUIElement             true                  <!-- 不占 Dock -->
NSHighResolutionCapable true
```

### 11.2 图标与包体

不需要设计工具：先用 `scripts/make-icon.sh` 生成一张 1024 的渐变底 + 宠物几何图形（`swift` 脚本画或 `sips` 合成），`iconutil` 打 icns（已验证 `sips → iconset → icns` 链路可用）。后续想换美术稿只替换 `Sources/DeskPet/Resources/AppIcon.icns`。

**包体预算**：不含第三方宠物素材，app ≈ 5 MB（含 `sample.petpack` 模板约 200 KB）、DMG ≈ 3 MB（UDZO 压缩）。宠物素材全部运行时从磁盘读，`make dmg` 之后要做一次"包里不该有 webp"的断言：`find dist/DeskPet.app -name "*.webp" | wc -l` 必须为 0。

### 11.3 ❗分发的现实（必须写进 README）

实测：ad-hoc 签名的 app，`spctl -a -vvv` 结果是 **`rejected`**（`source=no usable signature`）。别人从网上下载后：

- **首次打开会被 Gatekeeper 拦**："无法打开，因为无法验证开发者"。
- 解法（免费）：Finder 里**右键 → 打开**，或终端 `xattr -dr com.apple.quarantine /Applications/DeskPet.app`。
- 想真正做到"双击无感安装"，必须走 Apple Developer Program（$99/年）：
  `Developer ID Application` 证书 → `codesign --options runtime` → `xcrun notarytool submit --wait` → `xcrun stapler staple`。

⇒ 方案里准备两套流水线：`make sign` 默认 ad-hoc（免费路径），`make notarize` 预留（有证书后填 `DEVELOPER_ID` 环境变量即可启用）。**v1 按 ad-hoc 交付，README 顶部写清"首次右键打开"。**

### 11.4 DMG 布局

- 用 `hdiutil create -srcfolder … -format UDZO`（已验证）。macOS 27 会打一条 deprecation 警告，提示改用 `diskutil image create from`；脚本里做 fallback：先试 `diskutil image create from`，失败回退 `hdiutil`。
- 美化：先做可写镜像 → 挂载 → 放入 `DeskPet.app` + `Applications → /Applications` 软链 + `.background/background.png` → AppleScript 设置 Finder 图标视图位置与窗口尺寸 → 转 UDZO。这步在 CI/无 GUI 环境可能失败，v1 允许"朴素版镜像"（只有 app + Applications 软链），美化作为 M4 的加分项。

### 11.5 安装后行为

- 首次启动弹一个 3 页引导：① 认识宠物 ② 填薪资 ③ 是否开机自启。
- 开机自启用 `SMAppService.mainApp.register()`（macOS 13+，无需权限、不弹框）。
- 卸载：拖到废纸篓 + `~/Library/Preferences/com.xpeng.deskpet.plist` 与 `~/Library/Application Support/DeskPet/`（README 写明）。

---

## 12. 里程碑与验收（每个都能独立跑起来）

| 里程碑 | 内容 | 估时 | 验收标准（可执行） |
| --- | --- | --- | --- |
| **M0 空壳** ✅ | SPM 工程 + Makefile + `PetPanel` + 菜单栏 + 代码宠物（CA 动画）+ 拖动吸边 + 位置记忆 | 0.5d | ✅ `make run` 出现悬浮宠物；拖动/吸边正常；`make ui-check` 离屏渲染通过；CPU 0.27% / footprint 16 MB；退出无残留 |
| **M1 采集** ✅ | 7 个 Provider + 1Hz 采样器 + 情绪接线 + 调试面板 + `--metrics-once` / `--bench-metrics` | 1d | ✅ 数值与 `top`/`vm_stat`/`pmset`/`df` 对得上（见 §15.7）；CPU 0.57%（目标 <1.5%）；60 秒 RSS 平稳 67.7 MB 无增长；现场压测 8 个 `yes` → 3 秒内 `idle→busy`，停止后 4 秒回 `idle` |
| **M2 宠物** ✅ | `PetKit` 双格式解析（DSH `frames2d` + Codex atlas v2）+ `FrameCache` 预跳帧解码 + CA 关键帧播放 + 情绪映射 + 菜单选宠物 + 兜底矢量宠物 | 2.5d | ✅ ① `jyn` 播 idle（26 帧/3120ms）；✅ ② 压测 3 秒切 `work` 轨；✅ ③ 切换命中缓存 0ms、首次解码约 120ms；⚠️ ④ 内存增量约 54 MB（**未达 30 MB 目标**，原因见 §15.8）；✅ ⑤ 无宠物包时退回矢量宠物；✅ ⑥ Codex 图集可播 |
| **M3 赚钱** ✅ | `EarningsEngine`（按在岗秒数计钱）+ 8Hz 金额标签 + 金币粒子 + 里程碑 + 设置面板 + 老板键 ⌘⇧H | 1d | ✅ 改配置即时重算；✅ 09:29→09:31 恰好从 0 开始累加（单测）；✅ 暂停冻结、⌘⇧H 注册成功；✅ `SelfTest` 84 项全绿；✅ CPU 0.53% |
| **M2.5 自定义宠物包** | `petpack` v1 校验器 + `PackDoctor` + `PackConverter` + CLI 三件套 + 导入 UI + 模板包 + `docs/PETPACK_SPEC.md` | 1.5d | ① 自己造一个只有 6 帧 idle 的最小包，能导入并正常播放；② 缺 `work` 轨时自动降速复用 idle；③ 塞一张 PNG 进去当帧 → 硬错误且提示可读；④ zip slip 包（`../evil`）被拒；⑤ `--validate-pack` 对 3 类坏包给出正确分级；⑥ `--export-template` 导出的模板改一张图就能跑 |
| **M4 分发** | icns + DMG + 引导页 + 开机自启 + README | 1d | 断网环境下把 dmg 拷到另一台 Mac，挂载→拖入→右键打开→能跑；重启后自启生效；卸载干净 |
| **M5 打磨** | 低电降频、睡眠停摆、崩溃恢复（保持窗口位置）、`perf.sh` 报告 | 1d | 合盖 8 小时后电量无明显掉电；`perf.sh` 60s 均值 CPU < 1.5% |

合计 ≈ 8.5 个工作日（我的执行速度下会更集中在 2-3 轮内）。M2 变重是因为要同时吃两套宠物格式；M2.5 是「用户上传自定义宠物」这一层，独立于渲染，可以先做渲染再回头补。

---

## 13. 风险登记

| 风险 | 概率 | 影响 | 缓解 |
| --- | --- | --- | --- |
| 无证书 → 别人打不开 | **必然** | 高 | README 首屏写"右键→打开"；预留 `make notarize`；必要时买 $99 证书 |
| CLT 宏限制扩散（未来用到别的 SwiftUI 宏） | 中 | 中 | `make lint-macros` 拦住；宠物本体有 AppKit/CALayer 退路 |
| 透明面板阴影/模糊渲染异常 | 中 | 中 | 先跑 M0 验证；异常则 `CALayer` 方案 |
| 每秒动画耗电（笔记本关键） | 中 | 中 | 12fps 空闲档 + 睡眠停摆 + 实测 `perf.sh` |
| 采集泄漏（Mach 数组未释放） | 中 | 高 | 每次采样后 `vm_deallocate`；1 小时内存曲线必须平 |
| 宠物帧解码吃内存/CPU（1542 帧 × 512×683 ≈ 2.1 GB 全解码） | **高** | 高 | 预缩放到显示尺寸 + 只留 2 个 track + 后台解码，见 §7.2.3；M2 直接量化验收 |
| 宠物素材再分发侵权（codex 四只无 license，含真人形象） | 中 | 高 | app 不内置任何第三方素材；README 写清"素材由用户自备"；MIT 的 jyn 若内置须保留声明 |
| Codex 格式缺"睡眠"行，无法表现睡觉 | 中 | 低 | 定格 idle 首帧 + 叠加 zzz 装饰，README 说明格式差异 |
| 用户上传的包千奇百怪（尺寸/帧数/命名不一致） | **高** | 中 | 三级校验（§7.3.5）+ 缺轨降级 + `PackDoctor` 一键修；硬限制写进规范 |
| 恶意/畸形包（zip slip、解码炸弹、超大包） | 中 | 高 | 不跟随符号链接、逐项校验路径、只走 ImageIO 且限像素、体积/文件数硬上限（§7.3.8） |
| 规范定太严 → 用户做不出来；太松 → 什么都进 | 中 | 中 | 「最少 1 条 idle 就能用」是硬底线，其余全部可缺省；模板包 + 一页教程兜底 |
| macOS 27 新系统 API 变动 | 低 | 中 | 只用公开 API；不碰私有 SMC |
| DMG 美化在无 GUI 环境失败 | 中 | 低 | 允许朴素版镜像，美化可后补 |
| 分发到 Intel Mac 无法运行 | 确定 | 低 | README 标注"仅 Apple Silicon" |

---

## 14. 决策状态

| # | 决策点 | 选项 | 状态 / 建议 |
| --- | --- | --- | --- |
| 1 | **项目位置** | ① `~/desk-pet`（已建）② 放进 data-web 工作区 | 待定 → 建议 ① |
| 2 | **宠物形象** | 复用本机已有资产 / 代码矢量 / 像素画 | ✅ **已定：复用 `~/.dsh/pets` 与 `~/.codex/pets`**，代码矢量只作兜底 |
| 3 | **默认宠物** | ① 首次启动自动选 `~/.dsh/pets` 里最新装的一只（现在是 `jyn`）② 让你在设置里手选 | 建议 ① + 设置可改 |
| 4 | **皮肤** | `jyn` 有 3 套皮肤（暗夜鎏金 / 蓝海霓裳 / 冰晶公主），带独立 idle 与点击动作 | 建议先只跑默认皮肤，皮肤切换放 M5 |
| 5 | **要不要继承 `gameplay`**（亲密度/饿/心情/喂食） | ① 完全不碰，只做"状态宠物 + 赚钱" ② 把 DSH 的 hunger/mood/energy/affection 也跑起来 | 建议 ①，v1 别扩散范围；`pet.json` 里已有配置，将来加不难 |
| 6 | **签名** | ① 只做 ad-hoc（免费，首次右键打开）② 买 $99 证书做真·双击安装 | 待定 → 建议 ① |
| 7 | **薪资默认值** | ① 预置你的数字（税后 21,000 / 21.75 天 / 8h / 09:30-19:00）② 全空引导手填 | 待定 → 建议 ①+②结合 |
| 8 | **宠物包规范** | ✅ **已定：`petpack` v1，用户按格式上传（§7.3）**，最少 1 条 idle 即可用，内置 DSH / Codex 两个适配器 | 待你确认三处细节 → |
| 8a | 导入入口 | ① 文件夹 + zip ② 只文件夹（更安全更简单） | 建议 ①，zip 用 `ditto` 解压并做 zip slip 校验 |
| 8b | 是否要"从 URL 导入" | ① v1 不做 ② 做 | 建议 ①，避免变成任意下载器 |
| 8c | 是否强制填 `author`/`license` | ① 选填但导入时展示 ② 必填 | 建议 ①（必填会劝退，但缺失时在列表里标灰提示） |

---

## 15. 验证记录（本机实测）

### 15.1 工具链

```
macOS 27.3 (26C5035r) arm64
Apple Swift 6.4.2 / SDK MacOSX27.2 / 仅 CommandLineTools
security find-identity -v -p codesigning → 0 valid identities found
hdiutil / iconutil / codesign 均在；create-dmg 未安装
```

### 15.2 SPM → .app → ad-hoc → DMG 全链路

```
swift build -c release                     ✅ 产出可执行文件
组装 Contents/MacOS + Info.plist + icns     ✅
sips → iconset → iconutil                  ✅ ICNS_OK
codesign --force --sign -                  ✅ Signature=adhoc
spctl -a -vvv -t exec                      ⚠️ rejected（预期，无证书）
可执行文件直接运行                          ✅ exit=124（timeout 杀掉，说明常驻未崩）
hdiutil create -format UDZO                ✅ 171K dmg，挂载可见 A.app
```

### 15.3 SwiftUI 宏矩阵

```
@State                                   ❌ plugin for module 'SwiftUIMacros' not found
@StateObject/@ObservedObject/@Environment/@Published  ✅ 编译通过
```

### 15.4 AppKit 退路

`NSPanel(.borderless,.nonactivatingPanel)` + `NSStatusItem` + `.accessory` 策略单独编译运行 ✅，证明纯 AppKit 方案可用。

### 15.5 测试框架

```
swift test        ❌ unable to resolve module dependency: 'XCTest'
Testing.swiftmodule 在 CLT 中不存在
⇒ 改用零依赖 SelfTest 可执行
```

### 15.6 宠物资产探测（本机）

```
~/.codex/pets/{codepeng, forgefox, trumpchibi, xichibi}/
  spritesheet.webp  1536×2288（8 列 × 11 行，cell 192×208），1.6-2.3 MB
  pet.json          spriteVersionNumber 2，无 license 字段         → 不可再分发

~/.dsh/pets/jyn/
  pet.json          petManifestVersion 2 / renderer frames2d / author 11726 / license MIT
  thumb/            22 track / 1542 帧 / 单帧 512×683 / 默认 40ms / 合计 109.5 MB
  skins             3 套（暗夜鎏金 / 蓝海霓裳 / 冰晶公主），各带 idleTrack + clickActions
  gameplay          hunger / mood / energy / affection 四维数值（v1 不启用）

~/.codex/skills/hatch-pet/references/
  codex-pet-contract.md   图集规格与朝向说明
  animation-rows.md       11 行语义 + 每行逐帧时长表

sips -g pixelWidth ~/.codex/pets/codepeng/spritesheet.webp   ✅ 能读
⇒ ImageIO 支持 WebP ⇒ NSImage 直接加载，无需第三方解码库
```

### 15.7 M1 指标校准与性能实测（2026-11-17）

**数值对照**（同一时刻，DeskPet vs 系统工具）：

| 指标 | DeskPet | 系统工具 | 判定 |
| --- | --- | --- | --- |
| CPU | 30.2% | `top` user 22.98% + sys 10.17% = 33.2% | ✅ 采样窗口不同，量级一致 |
| 内存 | 22.0 GB / 32 GB | `vm_stat` active+wired+compressed = 21.7 GB | ✅ 差 < 2% |
| 电池 | 80% · AC · 未充电 | `pmset -g batt` → 80%; AC attached; not charging | ✅ 完全一致 |
| 磁盘 | 141.0 GB 可用 / 460.4 GB | `df -h /` → 141Gi avail / 460Gi | ✅ 一致 |
| 网络 | ↓30.5 KB/s ↑19.4 KB/s | 无同窗口基准，靠回绕处理与多次采样稳定性验证 | ⚠️ 定性可信 |
| 热压力 | fair | `ProcessInfo.thermalState` | ✅ 直接映射 |

**Provider 单位耗时**（`--bench-metrics 50`）：

| Provider | ms/次 |
| --- | --- |
| CPU（host_processor_info） | 0.011 |
| 内存（host_statistics64） | 0.003 |
| 电池（IOPowerSources） | 0.119 |
| 网络（getifaddrs） | 0.045 |
| 磁盘（attributesOfFileSystem） | 0.010 |
| 热压力（ProcessInfo） | 0.000 |

合计约 0.19 ms/次，1Hz 采样本身只占 **0.20%** CPU。

**踩到并修掉的三个坑**：

1. **CPU tick 数组长度**：`host_processor_info` 的 `infoCount = CPU 数 × 4`，按 CPU 数读会越界崩溃（`Trace/BPT trap: 5`）。已在 §6.1 修正。
2. **状态栏文字更新的真实成本**：每次改 `NSStatusItem.button.title` 约 **18 ms**（要经 MenuBarAgent 重排）。最初写成"文字变了就更新"，等于每秒更新一次，CPU 从 0.2% 涨到 **2.07%**；改成纯按时间节流 5 秒后回到 **0.57%**。
3. **`String(format:)` 的 `%s`**：传 Swift `String` 会段错误（`%s` 只吃 C 字符串），改用 `%@`。

**CPU 归因实验**（30 秒窗口）：

| 配置 | CPU |
| --- | --- |
| 1Hz 采样 + 状态栏每秒更新 | 2.07% |
| 1Hz 采样 + 状态栏文字关闭 | 0.20% |
| 5s 采样 + 状态栏文字关闭 | 0.33%（噪声区间） |
| 5s 采样 + 状态栏每秒更新 | 0.30% |
| **1Hz 采样 + 状态栏 5s 节流（最终）** | **0.57%** |

### 15.8 M2 宠物渲染实测（2026-11-17）

**解析（`--list-pets`，5 个包，0.37s）**

| 包 | 适配器 | 轨道 | 说明 |
| --- | --- | --- | --- |
| `jyn` | frames2d | 22 | 逐帧 webp，单帧 512×683，40ms/帧，MIT |
| `codepeng` / `forgefox` / `trumpchibi` / `xichibi` | atlas | 11 | 1536×2288 图集，8×11，cell 192×208 |

**解码（`--check-pack jyn`）**

| 阶段 | 结果 |
| --- | --- |
| 串行解码 78 帧 | 1794 ms |
| 并行解码（`concurrentPerform`） | **123 ms**（39 帧 @319×426） |
| Codex 图集 6 帧 | 14 ms |

**播放**：`CAKeyframeAnimation(keyPath: "contents")` + `calculationMode = .discrete`，动画跑在 render server，进程不做逐帧重绘。

**内存归因实验**（footprint，30 秒稳态）

| 配置 | footprint | 说明 |
| --- | --- | --- |
| 矢量宠物（无包） | 19 MB | 基线 |
| 跳过播放（只加载包） | 18 MB | 排除解析开销 |
| 鲸鱼娘 idle 26 帧 @1.5× | 72–80 MB | 帧数据本身仅 11.6 MB |
| 预算 8 MB → 16 帧 | 54 MB | 降帧只线性影响 |
| 预算 4 MB → 3 帧 | 64 MB | **几乎不降，说明主因不是帧数** |

结论：`footprint` 里 Malloc Small 约 40–59 MB、CG Raster 12 MB、CoreAnimation 12 MB。每帧实际占用约 1.5 MB，接近原图 512×683 的未压缩大小 —— 即 **ImageIO 在解码时保留了全尺寸缓冲**，即使已用 `kCGImageSourceShouldCache: false` 并重画进紧凑 bitmap。

**跟进项（M5）**：把逐帧 webp 在导入时转成 **HEVC（带 alpha）视频**，用 `AVPlayerLayer` 播放，内存可降到个位数 MB；或改为按需解码 + 环形缓冲（换 CPU 换内存）。当前保留帧方案，因为它是唯一不改素材、不改格式就能播现有宠物包的做法。

### 15.9 M3 上班鼓励器实测（2026-11-17）

**算法校验**（`--earnings-once` vs 手算）

| 项 | DeskPet | 手算 |
| --- | --- | --- |
| 每秒 | ¥0.034 | 0.033525 元 |
| 已工作秒数 | 27129 | 27129 |
| 今日到账 | ¥909.50 | ¥909.51（浮点四舍五入差） |

**交互验证**

| 项 | 结果 |
| --- | --- |
| ⌘⇧H 全局热键 | `RegisterEventHotKey` 返回 `noErr`，日志确认注册成功 |
| 金币动画 | `DESKPET_DEMO_COINS=1` 触发后进程存活，无异常 |
| 金额标签离屏自检 | 底部条带 17,996 个不透明像素 |
| 设置面板离屏自检 | 8,292 个不透明像素（表单确实布局出来了） |
| CPU（8Hz 刷新 + 1Hz 采样 + 帧动画） | **0.53%** |
| 内存 footprint | 68 MB（帧动画占用为主，见 §15.8） |

**实现要点**：金额不累加而是"按在岗秒数 × 每秒工资"直接算出来 —— 睡眠、休眠、重启都不会漂移，也好写断言。刷新用 8Hz 的 `DispatchSourceTimer` 直接改 `CATextLayer.string`，不走 SwiftUI，避免每秒重排视图。
