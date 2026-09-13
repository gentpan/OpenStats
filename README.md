<div align="center">

<img src="Assets/icon.png" alt="OpenStats" width="112" height="112">

# OpenStats

**Your Mac at a glance — CPU, GPU, memory, network and temperatures in the menu bar, with fan control, keep-awake and one-click cleanup.**

[![Release](https://img.shields.io/github/v/release/gentpan/OpenStats?color=6ee02b&label=release)](https://github.com/gentpan/OpenStats/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/gentpan/OpenStats/total?color=6ee02b&label=downloads)](https://github.com/gentpan/OpenStats/releases)
[![Stars](https://img.shields.io/github/stars/gentpan/OpenStats?style=flat&color=f5c518&label=stars)](https://github.com/gentpan/OpenStats/stargazers)
[![Last commit](https://img.shields.io/github/last-commit/gentpan/OpenStats?color=black&label=last%20commit)](https://github.com/gentpan/OpenStats/commits/main)
[![Commit activity](https://img.shields.io/github/commit-activity/m/gentpan/OpenStats?color=black&label=commits)](https://github.com/gentpan/OpenStats/graphs/commit-activity)
[![CI](https://github.com/gentpan/OpenStats/actions/workflows/ci.yml/badge.svg)](https://github.com/gentpan/OpenStats/actions/workflows/ci.yml)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black)](https://github.com/gentpan/OpenStats/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-black)](LICENSE)

OpenStats is a macOS menu-bar app that shows what your Mac is doing right now — per-core
CPU load, GPU, memory pressure, network speed, disk, battery, temperatures and fans — and
lets you act on it: spin the fans up, keep the Mac awake with the lid closed, clear caches.
Everything is read on your own Mac. No account, no telemetry. The only network traffic is optional and on demand: a public-IP lookup when you open network details, and a ping probe to a target you choose.

[Download](https://github.com/gentpan/OpenStats/releases/latest) ·
[Website](https://getopenstats.com) ·
[Changelog](CHANGELOG.md) ·
[Architecture](ARCHITECTURE.md)

**English** · [简体中文](README.zh-CN.md)

</div>

---

## Install

OpenStats has not had a release yet. The first one will be a `.dmg` on
[Releases](https://github.com/gentpan/OpenStats/releases/latest), signed with a Developer ID
certificate and notarized by Apple, followed by a Homebrew cask. Until then, build it from
source — see [Build & run](#build--run).

Requires macOS 14 (Sonoma) or later.
Developed and tested on Apple Silicon. The interface is in Simplified Chinese.

## Recent updates

<!-- changelog:start -->
<!-- Generated from CHANGELOG.md by Scripts/sync_changelog.py. Do not edit by hand. -->

Not released yet · **46** changes in development · [full changelog](CHANGELOG.md) (kept in Chinese)

<details open>
<summary><b>2026-09-13</b> · Unreleased · 30 added · 10 style · 6 fixed</summary>

**Added**

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
- IP 归属地改为本地 MaxMind GeoLite2 数据库查询：自己实现 .mmdb 读取器（不依赖第三方库），国家、城市与 ASN 完全离线查；数据库由官网服务器每周二、周五用 MaxMind 账号同步，应用每 3 天检查清单、下载并按 sha256 校验后替换，也可以从文件导入；设置中可选是否包含城市库（约 60 MB）；数据库就绪前暂用 ipinfo.io 在线查询，网络详情里标明数据来源。
- 本机信息页：机型图与名称、系统版本与版号、芯片与各类核心、内存与图形、存储用量、电池健康与循环次数、每台显示器的尺寸 / 原生分辨率 / 显示分辨率 / 刷新率、机型标识符、序列号（默认遮住，点眼睛图标显示，截图时始终遮住）与启动时间。
- 进程管理器（主窗口“进程”页）：包括 root 与其他用户的系统进程（通过系统自带的 ps 读取，不需要辅助工具）；列出 CPU、CPU 时间、内存、线程、唤醒次数、磁盘读写与用户，点列标题排序；可搜索名称、PID 或用户，筛选全部 / 我的 / 系统，切换按进程或按应用合并；选中后显示路径与详情，可在访达中显示、用 Apple 智能解释、退出或强制退出（二次确认，系统进程与 loginwindow 等禁止结束）；底部汇总用户 / 系统 / 空闲与全系统进程数、线程数。
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

**Style**

- 主窗口与设置窗口的侧边栏选中样式：左侧一条两端渐隐的细线，选中项有发光的蓝色光条，切换时带回弹地滑过去，右侧拖出渐淡的蓝色高亮；不再整块填蓝。
- 仪表盘“快捷开关”改为开关样式：防休眠、合盖运行、散热模式各一行，右侧开关，下面一行小字说明当前状态。
- 进程表按窗口宽度自动隐藏次要列，窄窗口里名称列不会被挤没。
- 内存详情的“释放内存”移到标题栏，执行中与完成后在按钮上显示进度和结果；主窗口内存页顶栏同样提供。
- 主窗口默认 1072×720、设置窗口默认 920×720，两者都可自由调整大小；滚动条改为浮层样式，只在滚动时出现。
- 菜单栏字号缩小并统一：两行布局为 7pt 标签加 10pt 数值，单行布局 11pt，网速两行 9pt；每种风格内部只用一套字号，指标之间留出更宽的间距。
- 柱状历史去掉满高的灰色底槽，只保留一条淡基线，负载起伏更清楚。
- 面板加宽为三列布局，高度按内容自动计算，常见屏幕上不需要滚动。
- 更换应用图标，面板左上角和关于页使用同一图标。
- 首次启动默认在菜单栏显示 CPU、内存与网速。

**Fixed**

- 深色菜单栏上 CPU、RAM 小标签颜色过深，几乎看不清。
- 面板打开后高度会再调整一次、内容轻微回弹，看起来在抖动；面板打开时点击菜单栏图标关闭，会立刻又被打开。
- 风扇被其他程序设为手动模式时，误显示为由 OpenStats 控制。
- 风扇转速、PID 等数字出现千分位分隔符，例如 1,350 RPM。
- 关闭液态玻璃后点击菜单栏图标，面板看起来打不开：面板内容被放大成两倍，窗口里只显示空白的一角。
- 面板第一次打开时高度偏小：打开瞬间温度、风扇、进程等数据还没采集，现在启动时先完整采集一次。

</details>

<!-- changelog:end -->

## Activity

<p align="center">
  <img src="Assets/readme/activity.svg" alt="Commits per day over the last 26 weeks" width="760">
</p>

<p align="center">
  <a href="https://star-history.com/#gentpan/OpenStats&Date">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=gentpan/OpenStats&type=Date&theme=dark">
      <img alt="Star history" src="https://api.star-history.com/svg?repos=gentpan/OpenStats&type=Date" width="760">
    </picture>
  </a>
</p>

## At a glance

<p align="center">
  <img src="Assets/readme/overview-dark.png" width="49%" alt="Main window dashboard, dark">
  <img src="Assets/readme/overview-light.png" width="49%" alt="Main window dashboard, light">
</p>

## Where the numbers show

**Menu bar**
- Eight styles, chosen once for every metric: two-line text, one-line text, icons, rings,
  pies, history bars, level meters and status dots. Any metric can be given its own style;
  Settings previews each one with sample data and says what the shape means.
- Network speed in two rows with dots or arrows, or on one line — green for upload, blue for
  download, always with its unit (`KB/s`, `MB/s`, `GB/s`).
- Small and consistent type: 7 pt labels over 10 pt figures, 11 pt on one line, 9 pt for
  network speed. Figures are fixed-width, so the bar does not jitter. Hover for every reading.

<p align="center"><img src="Assets/readme/menubar-dark.png" width="600" alt="Menu bar"></p>

**Detail popovers** — each metric gets its own menu-bar item; click it for a narrow popover.
Choose which sections each popover shows in Settings. `Esc` closes it.
- **CPU.** Usage with a status and 30-second change, thermal headroom; a per-core heatmap; load by core type;
  queueing (load average per core, rising or falling); usage summed by app.
- **Memory.** What is still available with a pressure timeline; a waterline bar; memory saved by compression and
  live swap I/O; usage summed by app.
- **Network.** Traffic history; a connection-probe grid (latency, jitter, loss); interface,
  Wi-Fi signal, VPN / proxy; local and public IPv4 / IPv6 with a flag, region and ASN; DNS flush
  and one-click switching to Cloudflare, Google, Tencent, Alibaba Cloud or manual servers;
  per-process traffic.
- **GPU**, **Temperature & fans.** History, sensor groups, fan speeds and quick modes.

<p align="center">
  <img src="Assets/readme/popover-cpu-light.png" width="32%" alt="CPU popover">
  <img src="Assets/readme/popover-network-light.png" width="32%" alt="Network popover">
  <img src="Assets/readme/popover-memory-dark.png" width="32%" alt="Memory popover, dark">
</p>

**Main window** — a sidebar with Dashboard, CPU, GPU, Memory, Network, Temperature & fans,
Processes, Keep awake and Clean; resizable in both directions. See [Cleanup](#cleanup).

**Ask Apple Intelligence about a process** — right-click a process you don't recognise and the on-device
model explains what it is, whether its usage looks normal and whether it is safe to quit. No third-party AI and
no network; requires macOS 26 with Apple Intelligence turned on. Answers can be wrong — check before you quit anything.

White and blue in light mode, black and blue in dark mode — one look across windows and popovers,
switched with one click or following the system.

<p align="center">
  <img src="Assets/readme/thermal-dark.png" width="49%" alt="Temperature & fans">
  <img src="Assets/readme/keepawake-light.png" width="49%" alt="Keep awake">
</p>

## Fans and sleep

| Fan mode | What it does |
|---|---|
| Auto | Hands the fans back to macOS |
| Cool | Holds them at 60% between minimum and maximum speed |
| Max | Full speed |
| Custom | A slider, anywhere in the fan's range |

In Custom, the fans are handed back to macOS the moment the CPU reaches the safety
temperature (95 °C by default). Quitting OpenStats, or the app crashing, restores automatic
control. Running with the lid closed switches itself off on battery below a floor you choose.

Both need system privileges, provided by a small helper registered with `SMAppService` and
approved once in System Settings → General → Login Items. The helper offers a fixed set of
operations — set a fan's target speed, return fans to auto, toggle `pmset disablesleep`,
flush the DNS cache, purge memory — and **never runs arbitrary commands**. It checks the
caller's code signature, restores fans and sleep when the app disconnects, and after an
unclean exit restores them at the next boot.

## Cleanup

- **What it scans.** App caches, logs and crash reports, browser caches (Chrome, Edge,
  Brave, Arc, Firefox, Safari), Xcode DerivedData, simulator caches, the npm cache, Xcode
  archives, unfinished downloads, installers and the Trash.
- **Review first.** Sizes by category, every rule expandable to its items, a second click to
  confirm. Caches and logs are deleted outright so the space comes back at once; downloads go
  to the Trash. One switch sends everything to the Trash instead.
- **Safety.** Only allow-listed folders are ever touched. Keychains, password managers,
  VPNs, cookies and history are off limits. Caches of running apps are skipped, browsers must
  be quit first, and every item is checked again right before it goes. Each action is logged
  to `~/Library/Logs/OpenStats/cleanup.log`.
- **Maintenance.** Flush the DNS cache and purge memory — through the helper if it is
  installed, otherwise after a one-time administrator prompt.

<p align="center"><img src="Assets/readme/cleaner-light.png" width="600" alt="Cleanup"></p>

## Your data

Metrics come from the kernel (`host_processor_info`, `host_statistics64`, `sysctl`), IOKit and the
SMC on your own Mac. Preferences live in the app's user defaults and contain nothing personal.
There is no analytics and no telemetry.

OpenStats only touches the network for two optional features, both of which can be turned off in
Settings → Network:

- **Public IP**: when you open network details, one request to Cloudflare `1.1.1.1` (ipify as fallback)
  for your public address, cached for 10 minutes. Region and ASN are looked up on the Mac in a MaxMind
  GeoLite2 database downloaded from `getopenstats.com` and verified by sha256; until it is downloaded,
  `ipinfo.io` answers instead.
- **Connection probe**: an ICMP ping to the target you pick (Cloudflare, Google, Alibaba Cloud,
  Tencent or your router) every 1, 2 or 5 seconds, only while the network item is in the menu bar
  or network details are open.

Process explanations run entirely on device through Apple Intelligence; process details never leave the Mac.

## Build & run

Requires macOS 14+, **Xcode 26 or later** (CommandLineTools
alone lacks the SwiftUI macro plugins) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
make run                  # generate the project, build Debug and launch
make install              # build Release, install into /Applications and launch
make test                 # unit tests: metrics, SMC decoding, cleanup safety
make open                 # generate the project and open it in Xcode
```

The app is a menu-bar agent, so there is little to screenshot. Render the surfaces with
live data instead:

```bash
build/DerivedData/Build/Products/Debug/OpenStats.app/Contents/MacOS/OpenStats --snapshot ./snapshots
```

Glass and vibrancy exist only on screen. To measure the panel while it is open, launch with
`--show-panel`, which opens the panel and pins it.

After editing `CHANGELOG.md`, run `python3 Scripts/sync_changelog.py` to refresh the recent
updates above and the activity chart.

## Distribution

Developer ID only, not the App Store — the sandbox forbids talking to the SMC, reading other
apps' caches and installing a privileged helper, which is most of the feature set.

| What you have | What others get |
|---|---|
| Nothing | Ad-hoc signature — runs on your Mac only. Others see *"OpenStats is damaged"*. |
| Developer ID certificate | Hardened runtime. Others see *"Apple cannot check it for malicious software"*. |
| Certificate + notarization | Gatekeeper accepts it — the normal *"downloaded from the internet"* prompt. |

`make build` and `make install` sign with the first Developer ID Application certificate in
the keychain and fall back to ad-hoc without one. The helper reads its own team at run time
and accepts only callers signed by the same team.

```bash
make release                          # sign, notarize, staple, build the DMG and a Homebrew cask
NOTARY_PROFILE=OpenStats make release # use another notarytool keychain profile
SKIP_NOTARIZE=1 make release          # an unnotarized DMG for testing on this Mac only
```

`Scripts/release.sh` refuses to produce a DMG that Gatekeeper would still reject.

## Architecture

- `Packages/OpenStatsKit/Sources/SMC` — SMC reads and writes, fan control, temperature
  sensor discovery.
- `Packages/OpenStatsKit/Sources/Metrics` — samplers for CPU, memory, network, GPU, disk,
  battery, processes and sensors, and `MetricsHub`, which samples only what is on screen.
- `Packages/OpenStatsKit/Sources/Cleaner` — cleanup rules, the safety guard, scanning and
  cleaning.
- `Packages/OpenStatsKit/Sources/HelperShared` — the XPC protocol and maintenance commands.
- `Packages/OpenStatsKit/Sources/OpenStatsUI` — design tokens, the panel, settings and the
  menu-bar renderer.
- `Helper/` — the privileged helper and its launchd plist. `App/` — the entry point.

More in [ARCHITECTURE.md](ARCHITECTURE.md). Every change to the app is logged, dated, in
[CHANGELOG.md](CHANGELOG.md).

## Acknowledgements

OpenStats builds on these open-source projects. Thank you.

| Project | Author | License | What OpenStats took |
|---|---|---|---|
| [Stats](https://github.com/exelban/stats) | Serhiy Mytrovtsiy | MIT | SMC access, the Apple Silicon fan unlock sequence and the menu-bar mini widget metrics |
| [Mole](https://github.com/tw93/Mole) | tw93 | GPL-3.0 | Which folders are worth cleaning and which must never be touched; the cleaner is an independent Swift implementation and contains no Mole code |
| [QuotaBar](https://github.com/gentpan/quotabar) | GiantAccel, LLC | MIT | This README's layout, the changelog sync and the activity chart |

Details in [ThirdPartyNotices.md](ThirdPartyNotices.md).

OpenStats is an independent third-party app. It is not affiliated with, endorsed by, or
sponsored by Apple or any other company it mentions. Their names and logos belong to their
respective owners.

## License

MIT — see [LICENSE](LICENSE).
