<div align="center">

<img src="Assets/icon.png" alt="OpenStats" width="112" height="112">

# OpenStats

**Your Mac at a glance — CPU, GPU, memory, network and temperatures in the menu bar, with fan control, keep-awake and one-click cleanup.**

[![Release](https://img.shields.io/badge/release-0.2.0-6ee02b)](https://getopenstats.com/#download)
[![Stars](https://img.shields.io/github/stars/gentpan/OpenStats?style=flat&color=f5c518&label=stars)](https://github.com/gentpan/OpenStats/stargazers)
[![Last commit](https://img.shields.io/github/last-commit/gentpan/OpenStats?color=black&label=last%20commit)](https://github.com/gentpan/OpenStats/commits/main)
[![Commit activity](https://img.shields.io/github/commit-activity/m/gentpan/OpenStats?color=black&label=commits)](https://github.com/gentpan/OpenStats/graphs/commit-activity)
[![CI](https://github.com/gentpan/OpenStats/actions/workflows/ci.yml/badge.svg)](https://github.com/gentpan/OpenStats/actions/workflows/ci.yml)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black)](https://getopenstats.com/#download)
[![License](https://img.shields.io/badge/license-MIT-black)](LICENSE)

OpenStats is a macOS menu-bar app that shows what your Mac is doing right now — per-core
CPU load, GPU, memory pressure, network speed, disk, battery, temperatures and fans — and
lets you act on it: spin the fans up, keep the Mac awake with the lid closed, clear caches.
Everything is read on your own Mac, and there is no telemetry. An account is optional: sign in with GitHub, Google or Apple to sync your preferences to other Macs; the cloud keeps only your email, name and the settings document. Beyond that, the only network traffic is optional and on demand: a public-IP lookup when you open network details, and a ping probe to a target you choose.

[Download](https://getopenstats.com/#download) ·
[Website](https://getopenstats.com) ·
[Changelog](CHANGELOG.md) ·
[Architecture](ARCHITECTURE.md)

**English** · [简体中文](README.zh-CN.md)

</div>

---

## Install

Download [OpenStats 0.2.0](https://getopenstats.com/download/OpenStats-0.2.0.dmg) from the website
(signed with a Developer ID certificate and notarized by Apple), or install it with Homebrew:

```bash
brew install --cask gentpan/tap/openstats
```

Requires macOS 14 (Sonoma) or later.
Developed and tested on Apple Silicon. The interface is in Simplified Chinese.

## Recent updates

<!-- changelog:start -->
<!-- Generated from CHANGELOG.md by Scripts/sync_changelog.py. Do not edit by hand. -->

Latest release **0.2.0** (2026-09-13) · **31** changes in development · [full changelog](CHANGELOG.md) (kept in Chinese)

<details open>
<summary><b>2026-09-15</b> · Unreleased · 1 changed · 1 fixed · 1 added</summary>

**Changed**

- 「设置 · 菜单栏」的显示项目上方加了一条说明：按住 ⌘ 拖动可以调整菜单栏图标的顺序，新开启的项目由系统安排位置；各页面右上角的开关悬停时也有同样的提示。官网常见问题同步补充。

**Fixed**

- 各监控页右上角的“在菜单栏显示”开关点不动：页面的滚动区域会自动向上延伸到顶栏底下，把开关的点击截走了；现在顶栏盖在滚动区域之上，GPU、磁盘等页面的开关可以正常点击。

**Added**

- 账号与设置同步（设置 · 账号与同步）：用 GitHub、Google 或 Apple 登录后，菜单栏项目与风格、刷新频率、外观与语言、详情弹窗的区块、连接探测、通知、快捷键、风扇安全温度、合盖电量下限会保存到 getopenstats.com，换一台 Mac 登录即自动恢复。设置改动 2 秒后上传，启动、唤醒与每 15 分钟检查一次云端；第一次登录时本机与云端都有内容且不同，会让你选用哪一份，之后以最后写入为准。登录走系统的授权窗口，令牌存在钥匙串，云端只保存邮箱、姓名与设置文档，可随时退出或删除云端数据。不登录时应用行为不变。

</details>

<details>
<summary><b>2026-09-15</b> · Unreleased · 3 added · 4 changed</summary>

**Added**

- CPU 走势时长可选 1 / 3 / 5 分钟：走势线上方一行小字切换，弹窗与主窗口共用；曲线按真实采样时间定位，最新一次采样固定在右边缘，睡眠等超过 10 秒没有采样的地方线条断开。
- 菜单栏新增“磁盘”项目：显示启动磁盘已用占比，八种风格都可用；点击弹出磁盘详情（容量与可用空间、读写速度、SSD 健康、读写最多的应用），区块可在设置里逐个隐藏。主窗口磁盘页右上角同样可以直接开关，“温度与风扇”页右上角现在有温度、风扇两个开关。
- CPU 详情新增“各核心占用”区块：主窗口里每个核心一个小圆环，中间写百分比，按“核心 1…N”编号并按类型分组，超过 60% 变橙、85% 变红；弹窗里是每核一根柱子的紧凑版，默认关闭，可在“设置 · 菜单栏”的 CPU 弹窗显示里打开。

**Changed**

- 卸载应用：去掉“同时从程序坞移除图标”开关，卸载时始终移除程序坞图标；应用列表的滚动条改为只在滚动时显示的细条（之前接了鼠标会显示一条粗的传统滚动条），升级说明里的滚动条同样修正。
- 主窗口的 CPU 走势图加上 0–100% 刻度与起点、中点、现在三个时间标签。
- CPU 详情的解释性文字不再常驻：热力图怎么看、每类核心是干什么的、平均负载怎么理解、按应用汇总为什么会超过 100%，都收进区块标题旁的 ⓘ，鼠标悬停 ⓘ 或卡片内容时才显示，界面上只留数据。
- 核心类型说人话：核心分工的悬停说明写明每类核心是干什么的（最快的处理重活、更省电的负责后台和轻量任务，系统自动分配）；各核心占用的分组标题、热力图的行标签都带上核心数量，热力图说明写明“每行一个核心（共 N 个），颜色越深越忙”；最忙的核心改为“核心 7（性能核）”这种统一编号。

</details>

<details>
<summary><b>2026-09-14</b> · Unreleased · 2 added · 2 changed</summary>

**Added**

- 系统通知新增“CPU 持续高负载”：总占用持续 1 分钟高于设定值（70% / 80% / 90%）时提醒，点通知打开 CPU 详情。
- 菜单栏风格新增“折线历史”：最近 30 次采样（约 1 分钟）的走势折线，线下填淡色；设置里有示例预览。

**Changed**

- CPU 详情重新整理：顶部直接显示 CPU 温度（下方附离 100°C 的余量，不再把余量当主数值），走势线下标出最近 60 秒的峰值；核心热力图右侧加一根粗条画此刻各核心的占用；核心分工标出芯片型号，频率跟在占用后面用次要颜色显示；按应用汇总注明“以单核满载为 100%”，解释各应用相加为什么会超过顶部的总占用。
- 主窗口的 CPU 页：走势线加高并带 25% / 50% / 75% 参考线，核心分工与排队程度并排显示，不再整页单列拉长。

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
  `ipapi.is` answers instead (anonymous, queried directly from each Mac, cached per IP for a day).
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
