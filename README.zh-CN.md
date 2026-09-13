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
所有数据都在你自己的 Mac 上读取。无需注册账号，没有统计上报。只有两项可关闭的网络功能会联网：打开网络详情时查询公网 IP，以及定时 ping 你选择的探测目标。

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

需要 macOS 14（Sonoma）或更高版本。在 Apple Silicon 上开发和测试。
界面为简体中文。

## 最近更新

<!-- changelog:start -->
<!-- 由 Scripts/sync_changelog.py 从 CHANGELOG.md 生成，请勿手改。 -->

尚未发布正式版本 · 开发中 **40** 项改动尚未发布 · [完整更新日志](CHANGELOG.md)

<details open>
<summary><b>2026-09-13</b> · 未发布 · 新增 27 · 样式 7 · 修复 6</summary>

**新增**

- 菜单栏显示 CPU、GPU、内存、网速、CPU 温度和风扇转速。
- 菜单栏风格：双行文字、单行文字、图标、圆环、饼图、柱状历史、电量条、状态圆点八种，整体选择一种统一套用，也可以给个别指标单独指定。设置里每种风格都有用示例数据画出的预览和说明，柱状历史注明是最近 10 次采样的变化。
- 网速有双行圆点、双行箭头、单行三种样式，绿色上传、蓝色下载，带完整单位。
- 鼠标悬停在菜单栏图标上显示完整读数。
- 菜单栏布局：每项独立（每个指标一个图标，点击弹出该项的窄详情）或合并为一个（点击打开主窗口）。每个详情里显示哪些区块可以在设置中逐个勾选。
- 详情弹窗：CPU（负载历史、各核心、处理器信息、高占用进程）、内存（使用历史、内存构成与释放内存、高占用进程）、GPU、温度与风扇（各组温度、风扇转速与快捷模式）。
- 网络详情：上下镜像的流量历史；连接探测格子（每 1 / 2 / 5 秒 ping 一次 Cloudflare、Google、阿里云、腾讯或路由器，显示延迟、抖动、丢包）；接口、物理地址、Wi-Fi 信号与速率、VPN / 代理；本地 IPv4 / IPv6、路由器、公网 IPv4 / IPv6，点击即可拷贝；归属地显示 SVG 国旗、城市、ASN 与网络运营方；各进程上传下载速率。
- DNS：显示正在使用的 DNS 与配置方式，一键刷新 DNS 缓存，一键切换为自动、Cloudflare、Google、腾讯 DNSPod、阿里云，或手动填写地址（逐个校验为 IPv4 / IPv6）。流量经过 VPN / 代理时提示 DNS 可能被接管。
- 主窗口：左侧边栏切换仪表盘、CPU、GPU、内存、网络、温度与风扇、进程、防休眠、清理；指标页右上角直接开关该项的菜单栏显示；宽度与高度都可调整，卡片按比例放大。打开主窗口时应用出现在程序坞中，关闭后回到仅菜单栏运行。
- CPU 详情：顶部是占用、状态（空闲 / 适中 / 繁忙 / 满载）、与 30 秒前相比的变化和温度余量，下面是走势线与用户 / 系统 / 空闲构成条；核心热力图（每行一个核心、每列一次采样）；核心分工（各类核心平均占用与最忙的核心）；排队程度（平均负载折算到每个核心，并提示负载在上升还是下降）；按应用汇总 CPU。
- 内存详情：顶部是还可用多少、压力状态与最近 60 秒的压力走势条；内存水位条（App / 联动 / 压缩 / 缓存 / 空闲）；压缩与交换（压缩省下的内存、压缩比、交换区用量与实时换入换出速率，持续写盘时提示）；按应用汇总内存（合并辅助进程，显示占已用内存的比例）。
- 用 Apple 智能解释进程：在进程上右键或点进程页的星形按钮，由系统自带的本机大模型说明它是什么、占用是否正常、能否退出；把路径、所属应用和签名方一起交给模型以减少猜测，全程不联网（需要 macOS 26 并开启 Apple 智能）。
- 进程显示应用的本地化名称（如“微信”）；按应用汇总时，同一应用的主进程与辅助进程合并计算。
- 仪表盘顶部是健康评分和芯片、内存、系统版本、运行时长、机型徽章，下面是 CPU 柱状历史、GPU 折线、内存面积图、磁盘、网络双线、风扇三列卡片，以及核心负载、电池环形图、高占用进程和快捷开关。
- CPU 按超级核、性能核、能效核分组显示各核心负载；内存口径与活动监视器一致，并显示内存压力；网速读取 64 位计数器，大流量下不会回绕。
- 温度与风扇：启动时枚举一次 SMC 键并按前缀归类，不按芯片型号硬编码，显示 CPU、GPU、内存、电池和掌托温度。
- 按界面需要分级采样：只显示菜单栏时只采集菜单栏用到的指标，打开详情或主窗口时按页面加采，锁屏、屏幕休眠和系统睡眠时暂停。
- 风扇调速：自动、降温、强冷、自定义四种模式。自定义模式下 CPU 达到安全温度会自动交还系统控制，应用退出或断开连接时风扇恢复自动。
- 防休眠：屏幕保持常亮、仅系统不休眠、合盖后继续运行，可设定持续时间；使用电池且电量低于下限时自动关闭合盖运行。
- 辅助工具：通过 SMAppService 注册，只提供设置风扇转速、切换合盖不睡眠、刷新 DNS、释放内存、为网络服务设置 DNS 几个固定操作（DNS 地址与服务名在辅助工具内再次校验）；运行时读取自己的签名团队，只接受同一团队签名的 OpenStats 调用；异常退出后下次开机自动恢复风扇与睡眠设置。
- 清理：扫描应用缓存、日志与崩溃报告、Chrome / Edge / Brave / Arc / Firefox / Safari 缓存、Xcode 编译缓存、模拟器缓存、npm 缓存、Xcode 归档、未完成的下载、安装包和废纸篓。按类别显示大小，可展开查看具体项目；清理前二次确认，操作写入 `~/Library/Logs/OpenStats/cleanup.log`。
- 清理的安全边界：只清理白名单目录，钥匙串、密码管理器、VPN、Cookie、历史记录一律不碰；正在运行的应用和浏览器自动跳过，执行前逐项重新校验。
- 系统维护：一键刷新 DNS 缓存、释放内存，已安装辅助工具时直接执行，否则请求一次管理员授权。
- 进程页按 CPU 或内存排序，辅助进程归并显示为所属应用。
- 设置窗口：外观、登录时启动、刷新频率、温度单位、菜单栏布局 / 显示项 / 样式 / 弹窗内容、连接探测与公网 IP 查询、风扇安全温度、合盖运行电量下限、辅助工具安装与卸载。
- 统一外观：浅色为白底蓝色、深色为黑底蓝色，主窗口、设置窗口与弹窗共用同一底色；侧边栏、标题栏与页面不分栏着色，红绿灯按钮与页面标题对齐；卡片为浅灰 / 深灰实色。侧边栏的太阳 / 月亮按钮一键切换，也可以跟随系统。
- 截图命令 `OpenStats --snapshot <目录>`：用本机实时数据渲染主窗口各页、详情弹窗、设置和菜单栏的浅色与深色截图，IP 与硬件地址替换为示例值。

**样式**

- 内存详情的“释放内存”移到标题栏，执行中与完成后在按钮上显示进度和结果；主窗口内存页顶栏同样提供。
- 主窗口默认 1072×720、设置窗口默认 920×720，两者都可自由调整大小；滚动条改为浮层样式，只在滚动时出现。
- 菜单栏字号缩小并统一：两行布局为 7pt 标签加 10pt 数值，单行布局 11pt，网速两行 9pt；每种风格内部只用一套字号，指标之间留出更宽的间距。
- 柱状历史去掉满高的灰色底槽，只保留一条淡基线，负载起伏更清楚。
- 面板加宽为三列布局，高度按内容自动计算，常见屏幕上不需要滚动。
- 更换应用图标，面板左上角和关于页使用同一图标。
- 首次启动默认在菜单栏显示 CPU、内存与网速。

**修复**

- 深色菜单栏上 CPU、RAM 小标签颜色过深，几乎看不清。
- 面板打开后高度会再调整一次、内容轻微回弹，看起来在抖动；面板打开时点击菜单栏图标关闭，会立刻又被打开。
- 风扇被其他程序设为手动模式时，误显示为由 OpenStats 控制。
- 风扇转速、PID 等数字出现千分位分隔符，例如 1,350 RPM。
- 关闭液态玻璃后点击菜单栏图标，面板看起来打不开：面板内容被放大成两倍，窗口里只显示空白的一角。
- 面板第一次打开时高度偏小：打开瞬间温度、风扇、进程等数据还没采集，现在启动时先完整采集一次。

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
  <img src="Assets/readme/overview-dark.png" width="49%" alt="主窗口仪表盘（深色）">
  <img src="Assets/readme/overview-light.png" width="49%" alt="主窗口仪表盘（浅色）">
</p>

## 数据显示在哪里

**菜单栏**
- 八种风格整体选择、统一套用：双行文字、单行文字、图标、圆环、饼图、柱状历史、电量条、状态圆点；
  也可以给个别指标单独指定。设置里每种风格都有示例预览，并说明图形代表什么。
- 网速可选双行圆点、双行箭头或单行：绿色上传、蓝色下载，始终带单位（`KB/s`、`MB/s`、`GB/s`）。
- 字号小而统一：两行布局 7pt 标签加 10pt 数值，单行 11pt，网速 9pt；数值等宽，刷新时菜单栏不抖动。
  鼠标悬停显示完整读数。

<p align="center"><img src="Assets/readme/menubar-dark.png" width="600" alt="菜单栏"></p>

**详情弹窗**——每个指标一个菜单栏图标，点击弹出该项的窄详情，显示哪些区块可在设置里勾选；按 `Esc` 关闭。
- **CPU**：占用与状态、与 30 秒前的变化、温度余量；核心热力图；核心分工；排队程度（每核平均负载与趋势）；按应用汇总。
- **内存**：还可用多少与压力走势；内存水位条；压缩省下的内存与交换区读写；按应用汇总。
- **网络**：流量历史；连接探测格子（延迟、抖动、丢包）；接口、Wi-Fi 信号、VPN / 代理；本地与公网 IPv4 / IPv6，
  归属地国旗、ASN；DNS 一键刷新，一键切换 Cloudflare、Google、腾讯、阿里云或手动填写；各进程流量。
- **GPU**、**温度与风扇**：使用历史、各组温度、风扇转速与快捷模式。

<p align="center">
  <img src="Assets/readme/popover-cpu-light.png" width="32%" alt="CPU 详情弹窗">
  <img src="Assets/readme/popover-network-light.png" width="32%" alt="网络详情弹窗">
  <img src="Assets/readme/popover-memory-dark.png" width="32%" alt="内存详情弹窗（深色）">
</p>

**主窗口**——左侧边栏切换仪表盘、CPU、GPU、内存、网络、温度与风扇、进程、防休眠、清理，宽高都可调整。
仪表盘有健康评分、芯片与系统徽章、三列指标卡片、核心负载、电池、高占用进程和快捷开关；清理见[清理](#清理)。

**用 Apple 智能解释进程**——看不懂的进程右键「用 Apple 智能解释」，由系统自带的本机大模型说明它是什么、占用是否正常、能否退出。
不接入第三方 AI，不联网；需要 macOS 26 并开启 Apple 智能，回答可能不准确，结束进程前请自行确认。

浅色为白底蓝色、深色为黑底蓝色，窗口与弹窗统一外观，可一键切换或跟随系统。

<p align="center">
  <img src="Assets/readme/thermal-dark.png" width="49%" alt="温度与风扇">
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

指标来自本机的内核接口（`host_processor_info`、`host_statistics64`、`sysctl`）、IOKit 与 SMC。
偏好设置保存在应用自己的 user defaults 中，不含个人信息。没有任何统计与上报。

只有两项可选功能会联网，都可以在“设置 → 网络”中关闭：

- **公网 IP**：打开网络详情时向 `ipinfo.io` 请求一次公网地址、归属地与 ASN（IPv6 与回退使用 Cloudflare `1.1.1.1` / ipify），10 分钟内不重复请求。
- **连接探测**：每 1、2 或 5 秒向你选择的目标（Cloudflare、Google、阿里云、腾讯或路由器）发送一次 ICMP ping，只在菜单栏显示网络项或打开网络详情时运行。

用 Apple 智能解释进程完全在本机完成，进程信息不会离开这台 Mac。

## 构建与运行

需要 macOS 14+、**Xcode 26 或更高版本**（仅有 CommandLineTools 时缺少 SwiftUI 宏插件）以及
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

`make build` 与 `make install` 会自动使用钥匙串里的第一个 Developer ID Application 证书签名，没有证书时退回 ad-hoc。
辅助工具在运行时读取自己的签名团队，只接受同一团队签名的调用方。

```bash
make release                          # 签名、公证、装订，生成 DMG 与 Homebrew cask
NOTARY_PROFILE=OpenStats make release # 使用其他 notarytool 钥匙串凭据
SKIP_NOTARIZE=1 make release          # 生成未公证的 DMG，仅供本机测试
```

`Scripts/release.sh` 会拒绝生成 Gatekeeper 仍会拒绝的 DMG。

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
