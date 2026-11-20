import Localization
import Metrics
import SMC
import SwiftUI

/// 菜单栏合并为一个图标时点击弹出的面板：顶部一排标签切换“总览”与这台 Mac 上的各项。
/// 总览把所有指标、高占用进程与常用工具集中在一页；点标签看某一项的完整详情，与每项独立时的弹窗相同
struct CombinedPopoverView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = tabItems
        // 风扇与温度共用一个详情页；标签对应的项目在这台 Mac 上没有时回到总览
        let requested = model.combinedPopoverTab == .fan ? .temperature : model.combinedPopoverTab
        let tab = requested.flatMap { items.contains($0) ? $0 : nil }

        PopoverFrame(width: DS.Size.dashboardPopoverWidth) {
            VStack(spacing: DS.Space.s3) {
                PopoverHeader(item: tab, showsTitle: false)
                PopoverTabStrip(items: items, selection: tab) { model.combinedPopoverTab = $0 }
                if tab == nil { OverviewHeader() }
            }
        } content: {
            if let tab {
                PopoverDetail(item: tab).id(tab)
            } else {
                DashboardPopover()
            }
        }
    }

    /// 标签里列出全部项目（与菜单栏里开了哪些无关）；风扇并在“温度”里，没有电池的 Mac 不显示电池
    private var tabItems: [MenuBarItem] {
        MenuBarItem.allCases.filter { item in
            switch item {
            case .fan: false
            case .battery: model.store.battery != nil
            default: true
            }
        }
    }
}

// MARK: - 标签

/// 顶部标签：总览 + 各项，苹果标准分段样式（灰色底槽、各段等宽、选中段品牌蓝），名称在悬停提示里
private struct PopoverTabStrip: View {
    let items: [MenuBarItem]
    let selection: MenuBarItem?
    let select: (MenuBarItem?) -> Void
    @Namespace private var namespace

    private static var radius: CGFloat { DS.Radius.md - DS.Space.s1 / 2 }

    var body: some View {
        HStack(spacing: 0) {
            segment(nil, symbol: overviewSymbol, title: tr("总览"))
            ForEach(items) { item in
                segment(item, symbol: item.symbol, title: item.popoverTitle)
            }
        }
        .background(DS.Palette.track, in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selection)
    }

    private func segment(_ item: MenuBarItem?, symbol: String, title: String) -> some View {
        let selected = item == selection
        return Button { select(item) } label: {
            Image(systemName: symbol)
                .dsFont(.sm, weight: .medium)
                .foregroundStyle(selected ? DS.Palette.onPrimary : DS.Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: DS.Size.segmentHeight + DS.Space.s1)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                            .fill(DS.Palette.primary)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 总览的图标；主窗口“仪表盘”已经用了方格图标，这里换成仪表盘指针以示区别
private let overviewSymbol = "gauge.with.dots.needle.50percent"

// MARK: - 总览

/// 总览：顶部一行三个圆环（CPU、GPU、内存），下面一张两列卡片放电池、磁盘、网络与风扇，
/// 再往下是高占用进程与常用工具；看完整详情点对应的标题
private struct DashboardPopover: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            UsageRingsCard()
            MetersCard()
            TopProcessesCard()
            ToolsCard()
        }
        .padding(.top, DS.Space.s1)
        .padding(.bottom, DS.Space.s2)
        // 总览用实色卡片排版，不用弹窗详情的分隔线样式
        .environment(\.isPopover, false)
    }
}

// MARK: - 标题

/// 总览标题：状态与评分一行，机器信息一行淡色小字（不再用一排胶囊）
private struct OverviewHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.store
        let report = HealthReport(store: store)

        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: report.tone == .success ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .dsFont(.lg, weight: .semibold)
                    .foregroundStyle(report.tone.color)
                Text(report.summary)
                    .dsFont(.base, weight: .semibold)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                Text(verbatim: tr("\(report.score) 分"))
                    .dsFont(.xs, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(report.tone.color)
                Spacer(minLength: 0)
            }
            Text(verbatim: machineLine(store))
                .dsFont(.xs)
                .foregroundStyle(DS.Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, DS.Space.s1)
    }

    private func machineLine(_ store: MetricsStore) -> String {
        let brand = store.topology.brand
        var parts = [brand.hasPrefix("Apple ") ? String(brand.dropFirst("Apple ".count)) : brand,
                     Format.capacity(ProcessInfo.processInfo.physicalMemory),
                     store.system.osVersion]
        if let boot = store.system.bootDate { parts.append(tr("已运行 ") + Format.uptime(since: boot, compact: true)) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - 圆环

private struct UsageRingsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.store
        let fahrenheit = model.settings.useFahrenheit
        let cpuTemperature = store.sensors?.temperature(.cpu)
        let gpuTemperature = store.sensors?.temperature(.gpu)
        let memory = store.memory

        Card(padding: DS.Space.s3, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                UsageRing(item: .cpu, title: "CPU", fraction: store.cpu?.total,
                          detail: cpuTemperature.map { Format.temperature($0.maximum, fahrenheit: fahrenheit) },
                          detailTone: cpuTemperature.map { Tone.forTemperatureText($0.maximum) } ?? .neutral)
                UsageRing(item: .gpu, title: "GPU", fraction: store.gpu?.utilization,
                          detail: gpuTemperature.map { Format.temperature($0.maximum, fahrenheit: fahrenheit) },
                          detailTone: gpuTemperature.map { Tone.forTemperatureText($0.maximum) } ?? .neutral)
                UsageRing(item: .memory, title: tr("内存"), fraction: memory?.usedFraction,
                          detail: memory.map { "\(Format.bytes($0.used)) / \(Format.bytes($0.total))" },
                          tone: memory.map(memoryTone))
            }
        }
    }


    /// 内存：用量与系统内存压力取更严重的一个。macOS 会把空闲内存拿来做缓存，
    /// 用量六七成很正常，所以阈值比 CPU 高：75% 变黄、90% 变红；压力告警时无论用量都跟着变色
    private func memoryTone(_ memory: MemoryUsage) -> Tone {
        let byUsage: Tone = memory.usedFraction >= 0.9 ? .error : memory.usedFraction >= 0.75 ? .warning : .success
        let byPressure = memory.pressure.tone
        let rank: (Tone) -> Int = { $0 == .error ? 2 : $0 == .warning ? 1 : 0 }
        return rank(byPressure) > rank(byUsage) ? byPressure : byUsage
    }
}

/// 圆环 + 名称 + 一行说明；点一下切到这一项的详情
private struct UsageRing: View {
    @Environment(AppModel.self) private var model
    let item: MenuBarItem
    let title: String
    let fraction: Double?
    var detail: String?
    var detailTone: Tone = .neutral
    /// 不给时按占用高低着色
    var tone: Tone?
    @Environment(\.isCompactText) private var isCompact
    @State private var hovering = false

    var body: some View {
        let value = fraction ?? 0
        let color = (tone ?? Tone.forLoad(value, normal: .success)).color

        Button { model.combinedPopoverTab = item } label: {
            VStack(spacing: DS.Space.s1) {
                RingGauge(fraction: value, color: color, lineWidth: DS.Space.s1 + DS.Space.s1 / 2, size: DS.Space.s12 + DS.Space.s2) {
                    // 数字为主；百分号只有数字一半大、常规字重、淡色，贴在数字右下
                    HStack(alignment: .firstTextBaseline, spacing: DS.Size.stroke) {
                        Text(verbatim: fraction.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
                            .dsFont(.lg)
                            .monospacedDigit()
                            .foregroundStyle(DS.Palette.textPrimary)
                        if fraction != nil {
                            Text(verbatim: "%")
                                .font(.system(size: DS.TextSize.lg.points(compact: isCompact) / 2, weight: .regular))
                                .foregroundStyle(DS.Palette.textSecondary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                Text(verbatim: title)
                    .dsFont(.xs, weight: .semibold)
                    .foregroundStyle(hovering ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                UnitText(text: detail ?? " ", size: .sm,
                         color: detailTone == .neutral ? DS.Palette.textSecondary : detailTone.color)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tr("查看\(title)详情"))
    }
}

// MARK: - 电池、磁盘、网络、风扇

/// 两行两列，中间用细线隔开。上面一行是“装了多少”的量（电池 | 磁盘），用同高的条；
/// 下面一行是随时间变的量（网络 | 风扇），用走势曲线，上下两两对应。
/// 每格两行文字：标题行（图标、名称、右侧徽章），数值行；图形在最底下
private struct MetersCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.store

        Card(padding: DS.Space.s3, spacing: 0) {
            // 卡片在面板里会收紧行距，这里自己控制两行之间的空隙和分隔线
            VStack(spacing: DS.Space.s3) {
                pair { batteryCell(store) } trailing: { diskCell(store) }
                HairlineDivider()
                pair { networkCell(store) } trailing: { fanCell(store) }
            }
        }
    }

    private func pair<Leading: View, Trailing: View>(@ViewBuilder _ leading: () -> Leading,
                                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        // 两列严格等宽、等高，中间一条细竖线
        WeightedRow(spacing: DS.Space.s2 * 2 + DS.Size.stroke) {
            leading()
            trailing()
        }
        .overlay { Rectangle().fill(DS.Palette.border).frame(width: DS.Size.stroke) }
    }

    // MARK: 容量

    @ViewBuilder
    private func batteryCell(_ store: MetricsStore) -> some View {
        if let battery = store.battery {
            let tone = battery.tone
            MeterCell(item: .battery, icon: healthSymbol(battery.health), title: tr("电池"),
                      badge: battery.health.map { tr("健康度 \(Format.percent($0))") }) {
                HStack(spacing: DS.Space.s1) {
                    Text(verbatim: Format.percent(battery.level))
                        .dsFont(.sm)
                        .monospacedDigit()
                        .foregroundStyle(tone.color)
                        .fixedSize()
                    // 接着电源时像系统电池图标一样带一个闪电
                    if battery.isPluggedIn {
                        Image(systemName: "bolt.fill").dsFont(.xs, weight: .semibold).foregroundStyle(tone.color)
                    }
                    Spacer(minLength: DS.Space.s2)
                    secondary(batteryDetail(battery))
                }
            } graphic: {
                ProgressTrack(fraction: battery.level, color: tone.color, height: Self.barHeight)
            }
            .help(battery.health.map { tr("电池健康 \(Format.percent($0))：图标里的电量格子代表健康度") } ?? "")
        } else {
            // 没有电池的 Mac：换成 CPU 温度，条以温度刻度上限为满
            let temperature = store.sensors?.temperature(.cpu)
            let tone = temperature.map { Tone.forTemperature($0.maximum) } ?? .neutral
            MeterCell(item: .temperature, icon: "thermometer.medium", title: tr("温度"), badge: "CPU") {
                primary(temperature.map { Format.temperature($0.maximum, fahrenheit: model.settings.useFahrenheit) } ?? "—")
            } graphic: {
                ProgressTrack(fraction: (temperature?.maximum ?? 0) / DS.Thermal.scaleMax,
                              color: tone == .error || tone == .warning ? tone.color : DS.Palette.success, height: Self.barHeight)
            }
        }
    }

    /// 接电源时写充电功率，否则写状态（剩余时间等）；后面跟循环次数
    private func batteryDetail(_ battery: BatteryStatus) -> String {
        var parts: [String] = []
        if let watts = battery.adapterWatts, battery.isPluggedIn { parts.append("\(watts)W") } else { parts.append(battery.stateText) }
        if let cycles = battery.cycleCount { parts.append(tr("循环 \(cycles) 次")) }
        return parts.joined(separator: " · ")
    }

    /// 标题前的电池图标用格子多少表示健康度：满格是 100%，健康度越低格子越少
    private func healthSymbol(_ health: Double?) -> String {
        guard let health else { return "battery.100percent" }
        return switch health {
        case 0.9...: "battery.100percent"
        case 0.7..<0.9: "battery.75percent"
        case 0.45..<0.7: "battery.50percent"
        case 0.2..<0.45: "battery.25percent"
        default: "battery.0percent"
        }
    }

    private func diskCell(_ store: MetricsStore) -> some View {
        let disk = store.disk
        return MeterCell(item: .disk, icon: "internaldrive", title: tr("磁盘"),
                         badge: disk.map { Format.capacity($0.total, base: .decimal) }) {
            HStack(spacing: DS.Space.s1) {
                secondary(tr("可用"))
                // 用量超过 90% 时可用空间变成警示色
                UnitText(text: disk.map { Format.bytes($0.available, base: .decimal) } ?? "—",
                         color: (disk?.usedFraction ?? 0) > 0.9 ? DS.Palette.warning : DS.Palette.textPrimary)
                    .fixedSize()
                Spacer(minLength: DS.Space.s2)
                secondary(disk.map { tr("已用 \(Format.percent($0.usedFraction))") })
            }
        } graphic: {
            // 与详情页同样的组成水位条，高度与左边电池条一致；各项写在悬停提示里
            let items = disk.map(DiskComposition.items) ?? []
            WaterlineBar(segments: items.map { (Double($0.bytes), $0.color) }, total: Double(disk?.total ?? 1), height: Self.barHeight)
                .help(items.map { "\($0.label) \(Format.bytes($0.bytes, base: .decimal))" }.joined(separator: "\n"))
        }
    }

    // MARK: 曲线

    private func networkCell(_ store: MetricsStore) -> some View {
        let rate = store.network
        return MeterCell(item: .network, icon: "network", title: tr("网络"), badge: store.networkInterface?.displayName) {
            // 下载靠左、上传靠右，一行写完，中间留足空隙
            HStack(spacing: DS.Space.s2) {
                rateLabel("arrow.down", color: DS.NetworkPalette.download, value: rate?.downloadBytesPerSecond)
                Spacer(minLength: DS.Space.s2)
                rateLabel("arrow.up", color: DS.NetworkPalette.upload, value: rate?.uploadBytesPerSecond)
            }
        } graphic: {
            DualLineChart(upload: store.uploadHistory.elements, download: store.downloadHistory.elements,
                          capacity: 30, height: Self.curveHeight)
        }
    }

    private func fanCell(_ store: MetricsStore) -> some View {
        let fans = store.sensors?.fans ?? []
        let fastest = store.fastestFan
        // 以最高转速为 100%
        let share = fastest?.fraction
        return MeterCell(item: .temperature, icon: "fan", title: tr("风扇"), badge: nil) {
            HStack(spacing: DS.Space.s1) {
                if let fastest, fastest.isStarting {
                    primary(tr("启动中…"))
                } else {
                    UnitText(text: fastest.map { "\(Int($0.current).formatted()) RPM" } ?? "—").fixedSize()
                }
                Spacer(minLength: DS.Space.s2)
                secondary(share.map { tr("转速 \(Format.percent($0))") })
            }
        } accessory: {
            FanModeMenu(selection: model.fans.mode) { model.requestFanMode($0) }
                .disabled(fans.isEmpty)
        } graphic: {
            LineHistoryChart(values: store.fanHistory.elements, capacity: 30, color: DS.Palette.data, height: Self.curveHeight)
        }
    }

    /// 电池进度条与磁盘水位条同高
    private static let barHeight = DS.Space.s2 + DS.Space.s1 / 2
    private static let curveHeight = DS.Space.s4 + DS.Space.s1

    private func rateLabel(_ symbol: String, color: NSColor, value: Double?) -> some View {
        HStack(spacing: DS.Space.s1 / 2) {
            Image(systemName: symbol).dsFont(.xs, weight: .semibold).foregroundStyle(Color(nsColor: color))
            UnitText(text: value.map { Format.menuBarRate($0) } ?? "—")
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func primary(_ text: String) -> some View {
        Text(verbatim: text)
            .dsFont(.sm)
            .monospacedDigit()
            .foregroundStyle(DS.Palette.textPrimary)
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private func secondary(_ text: String?) -> some View {
        if let text {
            Text(verbatim: text)
                .dsFont(.xs)
                .monospacedDigit()
                .foregroundStyle(DS.Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

/// 风扇档位下拉菜单：标题行右侧一个淡蓝色小胶囊，写着当前档位
struct FanModeMenu: View {
    let selection: FanController.Mode
    let select: (FanController.Mode) -> Void
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        if isSnapshot {
            label
        } else {
            Menu {
                ForEach([FanController.Mode.automatic, .cooling, .maximum]) { mode in
                    Toggle(mode.title, isOn: Binding(get: { selection == mode }, set: { if $0 { select(mode) } }))
                }
            } label: {
                label
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(tr("风扇档位"))
        }
    }

    private var label: some View {
        HStack(spacing: DS.Size.stroke) {
            Text(selection.title).dsFont(.xs, weight: .semibold)
            Image(systemName: "chevron.down").dsFont(.xs, weight: .semibold).imageScale(.small)
        }
        .foregroundStyle(DS.Palette.primary)
        .padding(.horizontal, DS.Space.s1 + DS.Space.s1 / 2)
        .frame(height: CellBadge.height)
        .background(DS.Palette.primary.opacity(0.12), in: BadgeShape())
        .fixedSize()
    }
}

/// 标题行右侧的小徽章（容量、电池健康、网络接口）；与风扇档位菜单同高、同圆角
private struct CellBadge: View {
    let text: String
    static let height = DS.Space.s4 + DS.Space.s1 / 2

    var body: some View {
        Text(verbatim: text)
            .dsFont(.xs, weight: .medium)
            .monospacedDigit()
            .foregroundStyle(DS.Palette.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.s1 + DS.Space.s1 / 2)
            .frame(height: Self.height)
            .background(DS.Palette.track, in: BadgeShape())
            .fixedSize()
    }
}

/// 卡片里的一格：标题行（图标、名称、徽章或附件）、数值行，图形在最底下；点名称进对应详情
private struct MeterCell<Value: View, Accessory: View, Graphic: View>: View {
    @Environment(AppModel.self) private var model
    let item: MenuBarItem
    let icon: String
    let title: String
    var badge: String?
    @ViewBuilder var value: Value
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var graphic: Graphic
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s1) {
                Button { model.combinedPopoverTab = item } label: {
                    HStack(spacing: DS.Space.s1) {
                        Image(systemName: icon)
                            .dsFont(.xs, weight: .semibold)
                            .foregroundStyle(DS.Palette.textSecondary)
                            .frame(width: DS.Size.iconInline)
                        Text(verbatim: title)
                            .dsFont(.sm, weight: .semibold)
                            .foregroundStyle(hovering ? DS.Palette.primary : DS.Palette.textPrimary)
                            .fixedSize()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .help(tr("查看\(title)详情"))
                Spacer(minLength: 0)
                if let badge { CellBadge(text: badge) }
                accessory
            }
            // 有没有徽章，标题行都一样高，左右两格的数值行才对得齐
            .frame(height: DS.Size.segmentHeight - DS.Space.s1)
            value
            Spacer(minLength: 0)
            graphic
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

extension MeterCell where Accessory == EmptyView {
    init(item: MenuBarItem, icon: String, title: String, badge: String?,
         @ViewBuilder value: () -> Value, @ViewBuilder graphic: () -> Graphic) {
        self.init(item: item, icon: icon, title: title, badge: badge, value: value, accessory: { EmptyView() }, graphic: graphic)
    }
}

/// 常用工具：摄像头与麦克风占用、清理入口，以及累计清理记录（防休眠在面板底部的快捷开关里）
private struct ToolsCard: View {
    @Environment(AppModel.self) private var model
    @State private var media = MediaUsage()

    var body: some View {
        let tally = model.cleanupTally

        Card(padding: DS.Space.s3, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: media.camera ? "video.fill" : "video")
                    .foregroundStyle(media.camera ? DS.Palette.success : DS.Palette.textSecondary)
                    .help(media.camera ? tr("摄像头使用中") : tr("摄像头未在使用"))
                Image(systemName: media.microphone ? "mic.fill" : "mic")
                    .foregroundStyle(media.microphone ? DS.Palette.warning : DS.Palette.textSecondary)
                    .help(media.microphone ? tr("麦克风使用中") : tr("麦克风未在使用"))
                Text(mediaText)
                    .dsFont(.xs, weight: .medium)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                ToolButton(icon: "sparkles", title: tr("清理"), isOn: false) {
                    model.openMainWindow(.cleaner)
                }
            }
            .dsFont(.sm, weight: .medium)

            HairlineDivider()

            HStack(spacing: DS.Space.s1) {
                Image(systemName: "clock.arrow.circlepath").dsFont(.xs, weight: .semibold)
                Text(tr("清理记录")).dsFont(.xs, weight: .semibold)
            }
            .foregroundStyle(DS.Palette.textSecondary)

            HStack(alignment: .top, spacing: DS.Space.s3) {
                stat(Format.bytes(tally.freedBytes, base: .decimal), label: tr("已清理"))
                stat("\(tally.uninstalledApps)", label: tr("已卸载"))
                stat("\(tally.optimizations)", label: tr("已优化"))
            }
        }
        .task {
            // 读设备状态很快，面板打开期间每 2 秒刷新一次
            while !Task.isCancelled {
                media = MediaUsageSampler.sample()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var mediaText: String {
        switch (media.camera, media.microphone) {
        case (true, true): tr("摄像头、麦克风使用中")
        case (true, false): tr("摄像头使用中")
        case (false, true): tr("麦克风使用中")
        case (false, false): tr("未在使用")
        }
    }

    private func stat(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1 / 2) {
            Text(verbatim: value)
                .dsFont(.lg)
                .monospacedDigit()
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 防休眠的浮出菜单（弹窗底部快捷开关的小箭头）：上面两行时长格子（1h 2h 4h / 8h 12h ∞），选一个就按这个时长开启；
/// 下面切换屏幕是否保持常亮、合盖后是否继续运行；开启时底部显示结束时间与关闭按钮
struct KeepAwakeQuickMenu: View {
    @Environment(AppModel.self) private var model

    private static let durations: [KeepAwakeController.Duration] = [.hour1, .hours2, .hours4, .hours8, .hours12, .unlimited]
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: DS.Space.s1), count: 3)

    var body: some View {
        let keepAwake = model.keepAwake

        VStack(alignment: .leading, spacing: DS.Space.s3) {
            LazyVGrid(columns: Self.columns, spacing: DS.Space.s1) {
                ForEach(Self.durations) { duration in
                    let selected = keepAwake.isActive && keepAwake.duration == duration
                    Button {
                        keepAwake.setDuration(duration)
                        if !keepAwake.isActive { Task { await keepAwake.start() } }
                    } label: {
                        Text(verbatim: duration.shortTitle)
                            .dsFont(.base, weight: selected ? .semibold : .regular)
                            .foregroundStyle(selected ? DS.Palette.onPrimary : DS.Palette.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: DS.Size.controlHeight)
                            .background(selected ? DS.Palette.primary : DS.Palette.track,
                                        in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(duration.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            SegmentedControl(selection: Binding(get: { keepAwake.mode }, set: { keepAwake.setMode($0) }),
                             options: KeepAwakeController.Mode.allCases.map { ($0, $0.shortTitle) })
                .help(keepAwake.mode.subtitle)

            // 打开时一并开启防休眠；没装辅助工具时跳到主窗口的防休眠页引导安装
            HStack(spacing: DS.Space.s2) {
                Text(tr("合盖后继续运行"))
                    .dsFont(.sm)
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer(minLength: DS.Space.s2)
                DSToggle(isOn: Binding(get: { keepAwake.lidClosedRequested }, set: { model.requestLidMode($0) }),
                         label: tr("合盖后继续运行"))
            }

            if keepAwake.isActive {
                HStack {
                    Group {
                        if let end = keepAwake.endDate {
                            Text(tr("\(end.formatted(date: .omitted, time: .shortened)) 结束"))
                        } else {
                            Text(tr("一直保持，直到手动关闭"))
                        }
                    }
                    .dsFont(.xs)
                    .foregroundStyle(DS.Palette.textSecondary)
                    Spacer(minLength: DS.Space.s2)
                    Button(tr("关闭防休眠")) { Task { await keepAwake.setActive(false) } }
                        .dsFont(.xs, weight: .semibold)
                        .buttonStyle(.plain)
                        .foregroundStyle(DS.Palette.error)
                }
            }
        }
        .padding(DS.Space.s3)
        .frame(width: DS.Size.sidebarWidth + DS.Space.s6)
        .environment(\.isCompactText, true)
    }
}

/// 工具卡片里的文字按钮：图标加名称，开启时用品牌色
private struct ToolButton: View {
    let icon: String
    let title: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .dsFont(.xs, weight: .semibold)
                .foregroundStyle(isOn || hovering ? DS.Palette.primary : DS.Palette.textSecondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
