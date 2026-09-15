<div align="center">

<img src="Assets/icon.png" alt="OpenStats" width="112" height="112">

# OpenStats

**Your Mac at a glance — CPU, GPU, memory, network and temperatures in the menu bar, with fan control, keep-awake and one-click cleanup.**

[![Release](https://img.shields.io/badge/release-0.3.0-6ee02b)](https://getopenstats.com/#download)
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

Download [OpenStats 0.3.0](https://getopenstats.com/download/OpenStats-0.3.0.dmg) from the website
(signed with a Developer ID certificate and notarized by Apple), or install it with Homebrew:

```bash
brew install --cask gentpan/tap/openstats
```

Requires macOS 14 (Sonoma) or later.
Developed and tested on Apple Silicon. The interface is in Simplified Chinese.

## Recent updates

<!-- changelog:start -->
<!-- Generated from CHANGELOG.md by Scripts/sync_changelog.py. Do not edit by hand. -->

Latest release **0.3.0** (2026-09-15) · [full changelog](CHANGELOG.md) (kept in Chinese)

<details open>
<summary><b>2026-09-15</b> · 0.3.0 · 8 added · 14 changed · 3 fixed</summary>

**Added**

- 菜单栏新增“电池”项目：电量按九种风格显示（电量条、圆环、饼图、数字等），充电中带闪电，电量低于 20% 按“高负载时着色”变红。点击弹出电池详情：电量与剩余 / 充满时间、适配器功率、电池温度、最近 24 小时电量曲线、功耗、健康度与循环次数、已连接蓝牙设备的电量（AirPods 左右耳与充电盒、妙控键盘 / 鼠标 / 触控板），可跳到系统电池设置；主窗口也有对应的“电池”页，历史页多了电池电量曲线。没有电池的 Mac（mini、Studio、iMac）上这个项目改为显示电量最低的蓝牙设备，弹窗只列蓝牙设备。「设置 · 菜单栏」新增“蓝牙设备电量低时提示”：某个设备低于 20% 时在电池项目旁显示它的图标与电量。
- 网络详情“接口”区块右上角新增重置按钮：把开机后下载 / 上传归零、从现在起重新累计，标题旁标出起算时间，两行改叫“重置后下载 / 上传”；重启后自动回到开机后累计，右键按钮可随时改回。
- 磁盘页从展示页变成能动手的磁盘工具，新增四张卡片：- 空间占用：统计家目录里每个文件夹占多少，并列出最大的 20 个文件（应用、照片图库等按整体算一个）；可在访达中显示，家目录里、Library 之外的文件可以直接移到废纸篓。只读扫描，文件多时需要几十秒，可随时停止。- 文件系统检查：调用系统的 diskutil 对启动盘做一次只读检查，相当于“磁盘工具”的急救但不修改任何东西；记住上次检查的时间与结果，发现问题时提示去磁盘工具修复。- 本地快照：列出 Time Machine 留在本机的快照（它们计入“可清除”空间），可一键全部删除；辅助工具够新时由它执行，否则请求一次管理员授权。辅助工具协议升到第 4 版，已安装的旧版会提示重新安装。- 其他磁盘：列出外置硬盘、U 盘、镜像与网络共享的容量，可在访达中显示或直接推出；接入、拔出时自动刷新。
- 网络详情新增「IP 纯净度」区块：CleanIP.io 的纯净度评分与等级画成占满整行的 F 到 A+ 六段色带，分数在色带上方、得分处有标记，同一行右侧是 cleanip.io 字标，点了打开这个 IP 的完整报告；下面列出风险评分、命中的风险标记（VPN、代理、Tor、机房、滥用记录等）与一句评价。IP 地址区块用 cleanip.io 样式的徽章标出原生 / 广播、住宅 / 机房与运营商类型（ISP 等），徽章样式作为通用组件收进设计系统。
- 账号与设置同步（设置 · 账号与同步）：用 GitHub、Google 或 Apple 登录后，菜单栏项目与风格、刷新频率、外观与语言、详情弹窗的区块、连接探测、通知、快捷键、风扇安全温度、合盖电量下限会保存到 getopenstats.com，换一台 Mac 登录即自动恢复。设置改动 2 秒后上传，启动、唤醒与每 15 分钟检查一次云端；第一次登录时本机与云端都有内容且不同，会让你选用哪一份，之后以最后写入为准。登录走系统的授权窗口，令牌存在钥匙串，云端只保存邮箱、姓名与设置文档，可随时退出或删除云端数据。不登录时应用行为不变。
- CPU 走势时长可选 1 / 3 / 5 分钟：走势线上方一行小字切换，弹窗与主窗口共用；曲线按真实采样时间定位，最新一次采样固定在右边缘，睡眠等超过 10 秒没有采样的地方线条断开。
- 菜单栏新增“磁盘”项目：显示启动磁盘已用占比，八种风格都可用；点击弹出磁盘详情（容量与可用空间、读写速度、SSD 健康、读写最多的应用），区块可在设置里逐个隐藏。主窗口磁盘页右上角同样可以直接开关，“温度与风扇”页右上角现在有温度、风扇两个开关。
- CPU 详情新增“各核心占用”区块：主窗口里每个核心一个小圆环，中间写百分比，按“核心 1…N”编号并按类型分组，超过 60% 变橙、85% 变红；弹窗里是每核一根柱子的紧凑版，默认关闭，可在“设置 · 菜单栏”的 CPU 弹窗显示里打开。

**Changed**

- 公网 IP 的归属地改用 cleanip.io：去掉本地 MaxMind GeoLite2 数据库（含下载、导入、自动更新的整个“IP 归属地数据库”设置区块）；归属地、ASN、网络类型与纯净度都由这台 Mac 直接向 cleanip.io 查询、不经过我们的服务器，只发送公网地址。
- 「设置 · 菜单栏」每个显示项目下面多了一行“菜单栏风格”：给这一项单独选一种风格（默认跟随整体，菜单里标出整体现在是哪种），旁边是这一项按当前风格、实时读数画出的预览，改了立刻能看到。以前这个选择藏在开关旁一个没有说明的下拉里，不容易发现。温度、风扇只提供文字类的三种风格；原“风格”分组改名“整体风格”并加了说明。
- 菜单栏弹窗右上角的两个按钮：左边改为该指标自己的图标（网络是网络图标、磁盘是硬盘），点了直接进主窗口里这个指标的页面；右边的齿轮进总设置。
- 公网 IP 双栈支持：IPv4 与 IPv6 各自查询归属地与纯净度、各自缓存；两族都有时 IP 地址区块用胶囊开关切换 IPv4 / IPv6。纯净度区块的标题一行排开：地址族徽章（只有一族时不标）、置信度徽章（高绿、中灰、低黄）、完整报告链接，右侧是刷新按钮；IP 地址区块也有同样的刷新按钮，都是忽略缓存立即重查，查询进行中按钮变成系统的转圈。
- 公网 IP 的归属地结果保存在本机：点开网络详情立刻显示上次的结果，后台只向 Cloudflare 核对一下地址；地址没变且不满 7 天就不再查归属地，换了 IP、超过 7 天或点了刷新才重新查。
- 磁盘页与磁盘弹窗的“读取 / 写入”两组数值各占一半宽度，数字长短变化时位置不再左右挪动。
- 磁盘“读写最多的应用”与网络详情“高占用进程”改为稳定的 5 条榜单：按最近十几秒的平均速率排序和画条，数字仍是当前速率；刚安静下来的应用会在榜上停留几秒再退出，不再随每秒的波动忽隐忽现、上下乱跳。
- 磁盘页与磁盘弹窗的容量改为分段条：已用、可清除、可用三段按比例排在一条里，段内直接标名称与百分比，下方图例给出各自的容量；可清除是系统随时可以腾出的缓存，访达的“可用”把它算在内。
- 磁盘页“读写最多的应用”与 CPU、内存详情“按应用汇总”的排行条不再画灰色底槽，只保留代表相对占比的蓝色条。
- 「设置 · 菜单栏」的显示项目上方加了一条说明：按住 ⌘ 拖动可以调整菜单栏图标的顺序，新开启的项目由系统安排位置；各页面右上角的开关悬停时也有同样的提示。官网常见问题同步补充。
- 网络详情的 DNS 切换改为下拉菜单：“配置方式”一行直接是菜单，选 Cloudflare、Google 等预设立即切换，选“手动”展开输入框，自定义地址时旁边有铅笔按钮可再次修改；不再显示六个并排的按钮，省下两行。
- 主窗口的 CPU 走势图加上 0–100% 刻度与起点、中点、现在三个时间标签。
- CPU 详情的解释性文字不再常驻：热力图怎么看、每类核心是干什么的、平均负载怎么理解、按应用汇总为什么会超过 100%，都收进区块标题旁的 ⓘ，鼠标悬停 ⓘ 或卡片内容时才显示，界面上只留数据。
- 核心类型说人话：核心分工的悬停说明写明每类核心是干什么的（最快的处理重活、更省电的负责后台和轻量任务，系统自动分配）；各核心占用的分组标题、热力图的行标签都带上核心数量，热力图说明写明“每行一个核心（共 N 个），颜色越深越忙”；最忙的核心改为“核心 7（性能核）”这种统一编号。

**Fixed**

- 菜单栏弹窗的内容整体偏左、右边留白更宽：接了鼠标时系统默认常驻滚动条，滚动区域给它预留了一条宽度。现在应用内一律用浮层滚动条，内容占满整个弹窗宽度，主窗口页面同样处理。
- 网络详情里的归属地国旗画错：中国、乌兹别克斯坦等 63 面旗子的 SVG 用了嵌套引用，系统渲染器画成一大块白。现在国旗改为预先渲染好的 PNG，全部按参考图核对过。
- 各监控页右上角的“在菜单栏显示”开关点不动：页面的滚动区域会自动向上延伸到顶栏底下，把开关的点击截走了；现在顶栏盖在滚动区域之上，GPU、磁盘等页面的开关可以正常点击。

</details>

<details>
<summary><b>2026-09-14</b> · 0.3.0 · 2 added · 2 changed</summary>

**Added**

- 系统通知新增“CPU 持续高负载”：总占用持续 1 分钟高于设定值（70% / 80% / 90%）时提醒，点通知打开 CPU 详情。
- 菜单栏风格新增“折线历史”：最近 30 次采样（约 1 分钟）的走势折线，线下填淡色；设置里有示例预览。

**Changed**

- CPU 详情重新整理：顶部直接显示 CPU 温度（下方附离 100°C 的余量，不再把余量当主数值），走势线下标出最近 60 秒的峰值；核心热力图右侧加一根粗条画此刻各核心的占用；核心分工标出芯片型号，频率跟在占用后面用次要颜色显示；按应用汇总注明“以单核满载为 100%”，解释各应用相加为什么会超过顶部的总占用。
- 主窗口的 CPU 页：走势线加高并带 25% / 50% / 75% 参考线，核心分工与排队程度并排显示，不再整页单列拉长。

</details>

<details>
<summary><b>2026-09-13</b> · 0.3.0 · 13 added · 4 changed</summary>

**Added**

- 在线升级：启动时和之后每天检查官网版本清单，发现新版本时弹出版本号与更新摘要，可一键安装、以后再说或跳过此版本；下载后依次核对 sha256、包名与版本、开发者签名团队和 Apple 公证，任何一项不通过都放弃安装；旧版先备份再原地替换，失败自动还原，装完自动重启到新版。「设置 · 关于」与应用菜单里可以手动检查更新。
- 辅助工具版本检查：启动时核对正在运行的辅助工具版本；旧进程还在运行时先断开让它退出，由系统启动新版本，仍然旧时在风扇、合盖运行和辅助工具设置里提示“重新安装”，侧边栏对应项目显示提醒圆点；有新版本时“关于”旁同样显示圆点。
- 导出诊断信息（设置 · 关于）：把版本、系统与辅助工具状态、主要设置、最近 3 天的运行日志、清理记录和最近的崩溃报告打包成 zip，反馈问题时附上；自动去掉用户目录名、IP 与硬件地址，不含序列号。应用与辅助工具的关键操作和错误写入系统日志。
- 系统通知（设置 · 通知）：CPU 过热（持续 1 分钟高于设定温度）、内存压力严重（持续 30 秒）、磁盘空间不足（低于 10% 或 10 GB）、网络断开超过 20 秒（恢复后再提示）、电池最大容量低于 80%，逐项开关，默认关闭；同一状况持续期间只提醒一次并有冷却时间，点通知打开对应页面；可发送测试通知，通知被关闭时提示去系统设置打开。
- 功耗与频率：“温度与风扇”页和温度详情新增功耗，显示整机功耗走势、电源输入、电池充放电功率和 GPU 功耗（读 SMC 与系统能耗统计，不需要辅助工具）；CPU 详情的核心分工显示各类核心工作时的平均频率。读取能耗统计有一定开销，只在这些界面打开时每 2 秒读一次。
- 磁盘页（主窗口侧边栏“磁盘”）：启动磁盘容量、所有磁盘合计的实时读写速度与 60 秒走势、SSD 健康（通过系统自带的 NVMe SMART 接口读取剩余寿命、累计读写量、备用空间、温度、通电时间与次数、异常断电和介质错误，出现警告时提示备份）、读写磁盘最多的应用；磁盘空间不足的通知改为打开磁盘页。
- 卸载应用（主窗口工具分组）：列出“应用程序”里的第三方应用及其体积，选中或把应用拖进来后找出它留下的应用数据、缓存、偏好设置、沙盒容器、窗口状态、日志、网页数据和登录启动项，可逐项取消勾选；确认后连同应用一起移到废纸篓（可放回），并从程序坞移除图标。只匹配应用包名与同名目录，系统自带和 Apple 的应用不列出，正在运行时提示先退出。
- 启动项（主窗口工具分组）：列出当前用户、所有用户的 LaunchAgents 和系统 LaunchDaemons，显示所属应用、可执行文件、是否登录时运行 / 保持运行，以及运行中（PID）、已加载、已停用状态；当前用户的启动项可以直接停用或重新启用（写入 launchd 停用记录并卸载，不删除文件），其余只读并提供登录项设置入口。
- 历史（主窗口监控分组）：每分钟把 CPU 平均与峰值、内存与内存压力、网络上下行、GPU、CPU 最高温度和整机功耗写入本机 SQLite 数据库，保留 7 天；可回看最近 1 小时 / 24 小时 / 7 天，睡眠等没有记录的时段线条断开，内存压力严重的时段标红，鼠标移到图上查看那一刻的数值；可关闭记录或清除历史，数据不上传。
- 蓝牙设备电量：本机信息页列出已连接的键盘、鼠标、触控板和耳机的电量（AirPods 分左耳、右耳、充电盒），低于 20% 标红；通知里新增“蓝牙设备电量低”（低于 15%）。
- 全局快捷键（设置 · 通用）：可为显示 / 隐藏主窗口、打开进程页、开关防休眠、释放内存录制快捷键，在任何应用中都能用，不需要辅助功能权限；被其他应用占用时提示更换。
- 桌面小组件“系统概览”：小号显示 CPU、内存圆环与磁盘用量，中号显示 CPU、内存、磁盘、电池四个圆环和磁盘可用空间；在自己的沙盒进程里读取数据，主应用没开也能显示，刷新间隔由系统决定（几分钟一次）。
- 英文界面（设置 · 通用 · 语言）：跟随系统、简体中文、English 三选一，系统首选语言不是中文时默认显示英文；约 880 条界面文案、通知、错误提示和 Apple 智能解释的回答都有英文版本，日期按英文格式显示；切换后界面、菜单与菜单栏立即换成新语言，显示器、应用名称等由系统提供的文字在下次启动时切换。

**Changed**

- 连接探测更省电：打开网络详情时按设置的间隔探测；详情关闭、只在菜单栏显示网速时改为每 10 秒低频探测，并允许系统合并唤醒，也可以在设置里关闭后台探测。
- 进程页每 2 秒刷新一次（读取全系统进程需要启动 ps），其他页面仍为每秒。
- 菜单栏图标用 ⌘ 拖动调整的顺序会被记住，重启应用或切换显示项目后保持不变。
- 本机信息的电池卡片提供“电池设置”入口，用 macOS 自带的充电上限（80%–100%）；新款机型不再开放第三方写入 SMC 充电控制键，因此不另做一套充电限制。

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
- **Battery.** Charge level, time remaining, adapter wattage and battery temperature; a 24-hour charge curve; power draw; health and cycle count; the batteries of connected Bluetooth devices (AirPods, Magic Keyboard / Mouse / Trackpad). Macs without a battery show the Bluetooth devices only.

<p align="center">
  <img src="Assets/readme/popover-cpu-light.png" width="32%" alt="CPU popover">
  <img src="Assets/readme/popover-network-light.png" width="32%" alt="Network popover">
  <img src="Assets/readme/popover-memory-dark.png" width="32%" alt="Memory popover, dark">
</p>

**Main window** — a sidebar with Dashboard, This Mac, History, CPU, GPU, Memory, Disk, Network, Temperature & fans,
Battery, plus the Processes, Startup items, Keep awake, Clean and Uninstall tools; resizable in both directions. See [Cleanup](#cleanup).

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

## Uninstaller and startup items

- **Uninstall apps**: lists third-party apps in Applications with their size. Pick one or drop an app in, and OpenStats finds
  what it left in your Library — app data, caches, preferences, sandbox containers, saved window state, logs, web data and
  login items — each of which you can untick. Confirming moves everything, app included, to the Trash (restorable) and
  removes its Dock icon. Matching is by bundle identifier and same-named folders only; built-in and Apple apps are not
  listed, and running apps must be quit first.
- **Startup items**: lists LaunchAgents for the current user and all users, plus system LaunchDaemons, with the owning app,
  executable, whether it runs at login or is kept alive, and whether it is running, loaded or disabled. Your own items can
  be disabled or re-enabled in place (recorded in launchd's disabled list and unloaded, no files deleted); the rest are
  read-only, with a shortcut to the system Login Items settings.

<p align="center"><img src="Assets/readme/startup-items-light.png" width="600" alt="Startup items"></p>

## Your data

Metrics come from the kernel (`host_processor_info`, `host_statistics64`, `sysctl`), IOKit and the
SMC on your own Mac. Preferences live in the app's user defaults and contain nothing personal.
There is no analytics and no telemetry.

OpenStats only touches the network for two optional features, both of which can be turned off in
Settings → Network:

- **Public IP**: when you open network details, one request to Cloudflare `1.1.1.1` (ipify as fallback)
  for your public address, cached for 10 minutes. Location, ASN, network type and the cleanliness score
  come from `cleanip.io`, queried directly from each Mac with nothing but the public address and never
  through our servers; a result is kept for a week unless the address changes or you refresh.
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
