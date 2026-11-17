# DeskPet · 桌面状态宠物 + 上班鼓励器

一个常驻 macOS 桌面的小宠物：它读你的 CPU / 内存 / 电池 / 网络状态并做出反应，同时把"上班"这件事换算成**每秒到账多少钱**，用数字滚动和金币动画陪你熬过工时。

> 当前状态：**M0 已完成**（可运行的悬浮宠物 + 菜单栏 + 打包链路），正在做 M1 系统指标采集。
> 设计与规范见 [`docs/TECH_PLAN.md`](docs/TECH_PLAN.md)。

## 它长什么样

- 透明无边框的悬浮宠物，可拖动、切 Space 不消失、全屏也看得见、不抢焦点
- 情绪由真实系统状态驱动：CPU 飙高就流汗，充电就冒闪电，深夜就睡着
- 下方一行每秒滚动的收入数字，达成里程碑时金币炸开
- 菜单栏常驻，随时暂停、隐藏金额（防同事围观）、换宠物

## 宠物

支持用户自己的宠物形象，按 [`petpack` v1 规范](docs/PETPACK_SPEC.md)（待补充）放进来即可，最少一条 `idle` 轨道就能用。

两种已有格式**开箱即读**，不需要转换：

| 格式 | 位置 |
| --- | --- |
| DSH 宠物（逐帧 `frames2d`） | `~/.dsh/pets/<id>/` |
| Codex 宠物（1536×2288 图集） | `~/.codex/pets/<id>/` |

仓库内附带一只默认宠物 **鲸鱼娘（jyn）**，MIT 许可，来源与归属见 [`NOTICE.md`](NOTICE.md)。

## 开发

```bash
make run       # 构建并启动
make test      # 零依赖自测（MoodRules 等纯逻辑）
make ui-check  # 离屏渲染自检（不透明像素 + 情绪配色差异）
make perf      # 采样 30s 的 CPU / 内存
make dmg       # 产出 dist/DeskPet.dmg
```

实测（M5 MacBook Air / macOS 27.3）：闲置 **CPU 0.27%**、内存 footprint **16 MB**、app 包体 164 KB。
宠物动画全部走 Core Animation，进程不做逐帧重绘 —— 早期用 SwiftUI 逐帧方案的对比数据见 `docs/TECH_PLAN.md` §3.2。

> 需要 macOS 14+ 与 Command Line Tools（**不需要完整 Xcode**）。
> 由于本机仅有 CLT，工程用 SPM + 手工组装 `.app`，细节见 `docs/TECH_PLAN.md` §2。

首次打开会被 Gatekeeper 拦（未做公证），右键 → 打开即可。

## 文档

| 文档 | 内容 |
| --- | --- |
| [`docs/TECH_PLAN.md`](docs/TECH_PLAN.md) | 技术方案：选型、架构、指标采集、打包、里程碑、风险 |
| `docs/PETPACK_SPEC.md` | 宠物包规范（实现时落地） |
| `docs/MAKE_YOUR_PET.md` | 三分钟做一个自己的宠物（实现时落地） |

## License

代码 MIT，见 [`LICENSE`](LICENSE)。内置宠物素材另有归属，见 [`NOTICE.md`](NOTICE.md)。
