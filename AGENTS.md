# DeskPet · Agent 约定

> 本项目是个人 macOS 桌面小工具，独立于 data-web 工作仓库。以下约定对任何在此目录工作的 Agent 生效。

## 语言

- 简体中文回复；代码、命令、标识符、commit message 保持英文。
- 文档统一放 `docs/`，正文中文。

## 环境事实（已验证，别重新踩）

| 事实 | 影响 |
| --- | --- |
| 本机只有 Command Line Tools，**无 Xcode** | 不能用 `.xcodeproj` / `xcodebuild archive`；用 SPM + `scripts/bundle.sh` 手工组装 `.app` |
| CLT 缺 `SwiftUIMacros`，`@State` 编译不过 | **禁止 `@State` / `@Bindable`**；状态用 `ObservableObject` + `@StateObject` / `@ObservedObject`（已验证可编） |
| CLT 没有 XCTest、也没有 Swift Testing | 测试写成 `Sources/DeskPetSelfTest` 的可执行，`make test` 跑，退出码非 0 即失败 |
| 无 Developer ID 证书 | 只能 ad-hoc 签名；DMG 首次打开需右键，README 必须写清 |

## 硬约束（MUST / MUST NOT）

- **MUST NOT** 提交 `dist/`、`.build/`、任何 `*.dmg`。
- **MUST NOT** 把没有 `license` 字段的宠物素材入库（见 `NOTICE.md`）。
- **MUST NOT** 在 `Pets/` 下放可执行文件、脚本、符号链接。
- **MUST** 改动行为时同步更新 `Sources/DeskPetSelfTest` 的断言。
- **MUST** 修改 `docs/TECH_PLAN.md` 里的"环境事实"时，先在本机复验，不凭记忆写。
- **MUST NOT** 用 SwiftUI `TimelineView` + `Canvas` 之类**逐帧重绘**的方式渲染常驻 UI：实测 7.6% CPU。持续动画一律用 Core Animation（`CALayer` + `CABasicAnimation`/`CAKeyframeAnimation`），改完跑 `make perf` 复测，目标 CPU < 1%。
- **MUST** 限制 `NSStatusItem.button.title` 的更新频率（纯按时间节流 ≥5s）：每次更新约 18ms，1Hz 更新会让 CPU 从 0.2% 涨到 2%。
- **MUST NOT** 在高频路径里用 `String(format: "%s", swiftString)`：`%s` 只接受 C 字符串，传 Swift `String` 会段错误；用 `%@`。
- **MUST** 改完渲染相关代码跑 `make ui-check`（离屏渲染自检：不透明像素数 + 情绪配色差异），因为 Agent 看不到屏幕。
- 宠物包格式变更 **MUST** 同步更新 `docs/PETPACK_SPEC.md` 与 `schemaVersion`。

## 命令

```bash
make run              # 构建 + 启动
make test             # 零依赖自测
make app              # 组装 dist/DeskPet.app
make dmg              # 产出 dist/DeskPet.dmg
make lint-macros      # 检查是否误用 @State
make ui-check         # 离屏渲染自检
make validate-sample  # 校验内置示例宠物包
```

## 目录

| 路径 | 用途 |
| --- | --- |
| `Sources/DeskPetCore/` | 纯逻辑（指标、赚钱、宠物包解析/校验），不 import AppKit，可测 |
| `Sources/DeskPet/` | App 层（窗口、渲染、UI、CLI） |
| `Sources/DeskPetSelfTest/` | 零依赖断言 |
| `Pets/` | 随仓库分发的宠物（当前仅 `jyn`），各自许可见 `NOTICE.md` |
| `docs/` | 技术方案与规范 |
| `scripts/` | 构建/打包/校验脚本 |
