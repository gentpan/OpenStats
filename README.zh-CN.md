<div align="center">

<img src="Assets/icon.png" alt="OpenStats" width="112" height="112">

# OpenStats

**Mac 的状态，抬眼就看见——CPU、GPU、内存、网络与温度常驻菜单栏，还能调风扇、防休眠、一键清理。**

[![Release](https://img.shields.io/github/v/release/gentpan/OpenStats?color=6ee02b&label=%E7%89%88%E6%9C%AC)](https://github.com/gentpan/OpenStats/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/gentpan/OpenStats/total?color=6ee02b&label=%E4%B8%8B%E8%BD%BD)](https://github.com/gentpan/OpenStats/releases)
[![Stars](https://img.shields.io/github/stars/gentpan/OpenStats?style=flat&color=f5c518&label=%E6%98%9F%E6%A0%87)](https://github.com/gentpan/OpenStats/stargazers)
[![Last commit](https://img.shields.io/github/last-commit/gentpan/OpenStats?color=black&label=%E6%9C%80%E8%BF%91%E6%8F%90%E4%BA%A4)](https://github.com/gentpan/OpenStats/commits/main)
[![Commit activity](https://img.shields.io/github/commit-activity/m/gentpan/OpenStats?color=black&label=%E6%8F%90%E4%BA%A4)](https://github.com/gentpan/OpenStats/graphs/commit-activity)
[![CI](https://github.com/gentpan/OpenStats/actions/workflows/ci.yml/badge.svg)](https://github.com/gentpan/OpenStats/actions/workflows/ci.yml)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black)](https://github.com/gentpan/OpenStats/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-black)](LICENSE)

OpenStats 是一款 macOS 菜单栏应用，实时显示 Mac 正在做什么：各核心 CPU 负载、GPU、内存压力、
网速、磁盘、电池、温度和风扇，并且可以直接处理：给风扇提速、合盖后继续运行、清理缓存。
所有数据都在你自己的 Mac 上读取。无需注册账号，没有统计上报，完全不联网。

[下载](https://github.com/gentpan/OpenStats/releases/latest) ·
[官网](https://getopenstats.com) ·
[更新日志](CHANGELOG.md) ·
[架构说明](ARCHITECTURE.md)

[English](README.md) · **简体中文**

</div>

---

## 安装

OpenStats 还没有发布正式版本。第一个版本会在 [Releases](https://github.com/gentpan/OpenStats/releases/latest)
提供 `.dmg`，使用 Developer ID 证书签名并经过 Apple 公证，之后提供 Homebrew cask。
在此之前请从源码构建，见[构建与运行](#构建与运行)。

需要 macOS 14（Sonoma）或更高版本；macOS 26 起面板使用液态玻璃。在 Apple Silicon 上开发和测试。
界面为简体中文。

## 最近更新

<!-- changelog:start -->
<!-- 由 Scripts/sync_changelog.py 从 CHANGELOG.md 生成，请勿手改。 -->

尚未发布正式版本 · 开发中 **23** 项改动尚未发布 · [完整更新日志](CHANGELOG.md)

<details open>
<summary><b>2026-09-13</b> · 未发布 · 新增 15 · 样式 4 · 修复 4</summary>

**新增**

- 菜单栏显示 CPU、GPU、内存、网速、CPU 温度和风扇转速。CPU、GPU、内存可以分别选择数字、柱状图、圆环、饼图、柱状图加数字五种样式；网速两行显示，绿点上传、蓝点下载，带完整单位。
- 下拉面板分为概览、进程、散热、防休眠、清理五页。概览页顶部是健康评分和芯片、内存、系统版本、运行时长、机型徽章，下面是 CPU 柱状历史、GPU 折线、内存面积图、磁盘、网络双线、风扇三列卡片，以及核心负载、电池环形图、高占用进程和快捷开关。
- CPU 按超级核、性能核、能效核分组显示各核心负载；内存口径与活动监视器一致，并显示内存压力；网速读取 64 位计数器，大流量下不会回绕。
- 温度与风扇：启动时枚举一次 SMC 键并按前缀归类，不按芯片型号硬编码，显示 CPU、GPU、内存、电池和掌托温度。
- 按界面需要分级采样：面板收起时只采集菜单栏用到的指标，锁屏、屏幕休眠和系统睡眠时暂停。
- 风扇调速：自动、降温、强冷、自定义四种模式。自定义模式下 CPU 达到安全温度会自动交还系统控制，应用退出或断开连接时风扇恢复自动。
- 防休眠：屏幕保持常亮、仅系统不休眠、合盖后继续运行，可设定持续时间；使用电池且电量低于下限时自动关闭合盖运行。
- 辅助工具：通过 SMAppService 注册，只提供设置风扇转速、切换合盖不睡眠、刷新 DNS、释放内存几个固定操作，并校验调用方签名；异常退出后下次开机自动恢复风扇与睡眠设置。
- 清理：扫描应用缓存、日志与崩溃报告、Chrome / Edge / Brave / Arc / Firefox / Safari 缓存、Xcode 编译缓存、模拟器缓存、npm 缓存、Xcode 归档、未完成的下载、安装包和废纸篓。按类别显示大小，可展开查看具体项目；清理前二次确认，操作写入 `~/Library/Logs/OpenStats/cleanup.log`。
- 清理的安全边界：只清理白名单目录，钥匙串、密码管理器、VPN、Cookie、历史记录一律不碰；正在运行的应用和浏览器自动跳过，执行前逐项重新校验。
- 系统维护：一键刷新 DNS 缓存、释放内存，已安装辅助工具时直接执行，否则请求一次管理员授权。
- 进程页按 CPU 或内存排序，辅助进程归并显示为所属应用。
- 设置窗口：外观、登录时启动、刷新频率、温度单位、菜单栏显示项与样式、风扇安全温度、合盖运行电量下限、辅助工具安装与卸载。
- 外观可选跟随系统、浅色、深色；macOS 26 起面板使用液态玻璃。
- 截图命令 `OpenStats --snapshot <目录>`：用本机实时数据渲染面板、设置和菜单栏的浅色与深色截图。

**样式**

- 菜单栏字号对齐常见菜单栏监控工具：标签 7pt 细体、数值 12pt 常规、网速 9pt 细体，指标之间留出更宽的间距。
- 面板加宽为三列布局，高度按内容自动计算，常见屏幕上不需要滚动。
- 更换应用图标，面板左上角和关于页使用同一图标。
- 首次启动默认在菜单栏显示 CPU、内存与网速。

**修复**

- 深色菜单栏上 CPU、RAM 小标签颜色过深，几乎看不清。
- 面板打开后高度会再调整一次、内容轻微回弹，看起来在抖动；面板打开时点击菜单栏图标关闭，会立刻又被打开。
- 风扇被其他程序设为手动模式时，误显示为由 OpenStats 控制。
- 风扇转速、PID 等数字出现千分位分隔符，例如 1,350 RPM。

</details>

<!-- changelog:end -->

## 活跃度

<p align="center">
  <img src="Assets/readme/activity.zh.svg" alt="近 26 周每天的提交数" width="760">
</p>

<p align="center">
  <a href="https://star-history.com/#gentpan/OpenStats&Date">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=gentpan/OpenStats&type=Date&theme=dark">
      <img alt="星标历史" src="https://api.star-history.com/svg?repos=gentpan/OpenStats&type=Date" width="760">
    </picture>
  </a>
</p>

## 界面一览

<p align="center">
  <img src="Assets/readme/overview-dark.png" width="49%" alt="概览（深色）">
  <img src="Assets/readme/overview-light.png" width="49%" alt="概览（浅色）">
</p>

## 数据显示在哪里

**菜单栏**
- CPU、GPU、内存可以分别选择数字、柱状图、圆环、饼图、柱状图加数字五种样式，另外还能显示网速、
  CPU 温度和转速最高的风扇。
- 网速两行显示：绿点上传、蓝点下载，始终带单位（`KB/s`、`MB/s`、`GB/s`）。
- 标签 7pt、数值 12pt，与常见的菜单栏监控工具一致；数值等宽，刷新时菜单栏不抖动。

<p align="center"><img src="Assets/readme/menubar-dark.png" width="600" alt="菜单栏"></p>

**面板**——点击菜单栏图标打开。
- **概览**：健康评分，芯片、内存、系统版本、运行时长、机型徽章；CPU 柱状历史、GPU 折线、内存、
  磁盘、网络、风扇三列卡片；按超级核、性能核、能效核分组的核心负载；电池环形图；高占用进程和快捷开关。
- **进程**：按 CPU 或内存排序，辅助进程归并到所属应用。
- **散热**：CPU、GPU、内存、电池、掌托温度，以及风扇。
- **防休眠**：屏幕保持常亮、仅系统不休眠、合盖后继续运行，可定时或不限时。
- **清理**：扫描、预览、清理，见[清理](#清理)。

面板高度按内容自动计算，常见屏幕上不需要滚动；按 `Esc` 关闭。外观可选浅色、深色或跟随系统。

<p align="center">
  <img src="Assets/readme/thermal-dark.png" width="49%" alt="散热">
  <img src="Assets/readme/keepawake-light.png" width="49%" alt="防休眠">
</p>

## 风扇与睡眠

| 风扇模式 | 行为 |
|---|---|
| 自动 | 交还 macOS 温控 |
| 降温 | 固定在最低到最高转速之间的 60% |
| 强冷 | 最高转速 |
| 自定义 | 用滑块在风扇转速范围内自由设定 |

自定义模式下，CPU 一旦达到安全温度（默认 95°C）就交还系统控制。退出 OpenStats 或应用崩溃时，
风扇恢复自动。合盖运行在使用电池且电量低于你设定的下限时自动关闭。

这两项需要系统权限，由一个通过 `SMAppService` 注册的小型辅助工具完成，首次使用时在
“系统设置 › 通用 › 登录项”中批准一次。辅助工具只提供固定的几个操作：设置风扇目标转速、恢复自动、
切换 `pmset disablesleep`、刷新 DNS 缓存、释放内存，**不执行任意命令**。它会校验调用方的代码签名，
应用断开连接时恢复风扇与睡眠设置；异常退出后，下次开机也会恢复。

## 清理

- **扫描范围**：应用缓存、日志与崩溃报告、浏览器缓存（Chrome、Edge、Brave、Arc、Firefox、Safari）、
  Xcode 编译缓存、模拟器缓存、npm 缓存、Xcode 归档、未完成的下载、安装包和废纸篓。
- **先预览**：按类别显示大小，每条规则可展开查看具体项目，清理前再确认一次。缓存与日志直接删除，
  空间立即释放；下载目录的内容移到废纸篓。也可以一键改为全部先移到废纸篓。
- **安全**：只处理白名单目录。钥匙串、密码管理器、VPN、Cookie、历史记录一律不碰。正在运行的应用的缓存
  会跳过，浏览器需要先退出，删除前每一项都会再校验一次。所有操作记录在 `~/Library/Logs/OpenStats/cleanup.log`。
- **系统维护**：刷新 DNS 缓存、释放内存。已安装辅助工具时直接执行，否则请求一次管理员授权。

<p align="center"><img src="Assets/readme/cleaner-light.png" width="600" alt="清理"></p>

## 你的数据

OpenStats **不发起任何网络连接**。指标来自本机的内核接口（`host_processor_info`、`host_statistics64`、
`sysctl`）、IOKit 与 SMC。偏好设置保存在应用自己的 user defaults 中，不含个人信息。没有任何统计与上报。

## 构建与运行

需要 macOS 14+、**完整的 Xcode**（CommandLineTools 不含 SwiftUI 宏插件）以及
[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
brew install xcodegen
make run                  # 生成工程，编译 Debug 并启动
make install              # 编译 Release，安装到 /Applications 并启动
make test                 # 单元测试：指标采集、SMC 编解码、清理安全边界
make open                 # 生成工程并用 Xcode 打开
```

菜单栏应用没什么可截图的窗口，可以用本机实时数据渲染各个界面：

```bash
build/DerivedData/Build/Products/Debug/OpenStats.app/Contents/MacOS/OpenStats --snapshot ./snapshots
```

玻璃与半透明效果只在屏幕上存在。需要测量面板打开时的资源占用，用 `--show-panel` 启动，面板会自动展开并固定。

修改 `CHANGELOG.md` 后运行 `python3 Scripts/sync_changelog.py`，更新上方的“最近更新”和活跃度图。

## 分发

只走 Developer ID，不上 App Store——沙盒不允许访问 SMC、读取其他应用的缓存、安装特权辅助工具，
而这正是大部分功能。

| 你拥有的 | 别人打开时看到的 |
|---|---|
| 什么都没有 | ad-hoc 签名，只能在你自己的 Mac 上运行。别人会看到 *“OpenStats 已损坏”*。 |
| Developer ID 证书 | 启用 Hardened Runtime。别人会看到 *“Apple 无法检查其是否包含恶意软件”*。 |
| 证书 + 公证 | Gatekeeper 放行，只有常规的 *“从互联网下载”* 提示。 |

发布前请在 `HelperShared/HelperProtocol.swift` 中填写 Team ID，让辅助工具只接受由该团队签名的调用方。

## 架构

- `Packages/OpenStatsKit/Sources/SMC`——SMC 读写、风扇控制、温度传感器发现。
- `Packages/OpenStatsKit/Sources/Metrics`——CPU、内存、网络、GPU、磁盘、电池、进程、传感器的采集器，
  以及只采集屏幕上需要的指标的 `MetricsHub`。
- `Packages/OpenStatsKit/Sources/Cleaner`——清理规则、安全守卫、扫描与执行。
- `Packages/OpenStatsKit/Sources/HelperShared`——XPC 协议与系统维护命令。
- `Packages/OpenStatsKit/Sources/OpenStatsUI`——设计 token、面板、设置窗口、菜单栏绘制。
- `Helper/`——特权辅助工具及其 launchd 配置；`App/`——应用入口。

更多内容见 [ARCHITECTURE.md](ARCHITECTURE.md)。应用的每一项改动都按日期记录在 [CHANGELOG.md](CHANGELOG.md)。

## 致谢

OpenStats 基于以下开源项目，谢谢。

| 项目 | 作者 | 许可证 | OpenStats 借鉴了什么 |
|---|---|---|---|
| [Stats](https://github.com/exelban/stats) | Serhiy Mytrovtsiy | MIT | SMC 访问、Apple Silicon 风扇解锁流程、菜单栏迷你样式的字号参数 |
| [Mole](https://github.com/tw93/Mole) | tw93 | GPL-3.0 | 哪些目录值得清理、哪些绝对不能碰；清理模块为独立的 Swift 实现，不含 Mole 代码 |
| [QuotaBar](https://github.com/gentpan/quotabar) | GiantAccel, LLC | MIT | 本 README 的版式、更新日志同步与活跃度图脚本 |

详见 [ThirdPartyNotices.md](ThirdPartyNotices.md)。

OpenStats 是独立的第三方应用，与 Apple 及文中提到的其他公司没有隶属、认可或赞助关系。相关名称与标志归各自所有者所有。

## 许可证

MIT，见 [LICENSE](LICENSE)。
