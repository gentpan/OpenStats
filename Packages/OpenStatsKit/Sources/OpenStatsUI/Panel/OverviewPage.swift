import AppKit
import Metrics
import SMC
import SwiftUI

struct OverviewPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PageScroll {
            HealthHeader()
            EqualHeightRow {
                CPUTile().frame(maxWidth: .infinity)
                GPUTile().frame(maxWidth: .infinity)
                MemoryTile().frame(maxWidth: .infinity)
            }
            EqualHeightRow {
                DiskTile().frame(maxWidth: .infinity)
                NetworkTile().frame(maxWidth: .infinity)
                FanTile().frame(maxWidth: .infinity)
            }
            EqualHeightRow {
                CoreLoadCard().frame(maxWidth: .infinity)
                if model.store.battery != nil {
                    BatteryCard().frame(width: DS.Size.tileWidth)
                }
            }
            EqualHeightRow {
                TopProcessesCard().frame(maxWidth: .infinity)
                QuickActionsCard().frame(width: DS.Size.tileWidth)
            }
        }
    }
}

/// 一行等高卡片
struct EqualHeightRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) { content }
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 健康度与徽章

struct HealthReport {
    let score: Int
    let summary: String
    let tone: Tone

    @MainActor
    init(store: MetricsStore) {
        var issues: [(penalty: Int, text: String)] = []
        if let cpu = store.cpu {
            if cpu.total >= 0.9 { issues.append((20, "CPU 负载很高")) } else if cpu.total >= 0.75 { issues.append((10, "CPU 负载偏高")) }
        }
        switch store.memory?.pressure {
        case .critical: issues.append((30, "内存压力严重"))
        case .warning: issues.append((15, "内存压力偏高"))
        default: break
        }
        if let hottest = store.sensors?.temperature(.cpu)?.maximum {
            if hottest >= DS.Thermal.hot { issues.append((20, "CPU 温度过高")) } else if hottest >= 85 { issues.append((10, "CPU 温度偏高")) }
        }
        if let disk = store.disk {
            if disk.usedFraction >= 0.95 { issues.append((15, "磁盘空间不足")) } else if disk.usedFraction >= 0.9 { issues.append((8, "磁盘空间偏紧")) }
        }
        if let health = store.battery?.health, health < 0.8 { issues.append((5, "电池健康度下降")) }

        score = max(0, 100 - issues.reduce(0) { $0 + $1.penalty })
        summary = issues.max { $0.penalty < $1.penalty }?.text ?? "各项指标正常"
        tone = score >= 85 ? .success : score >= 60 ? .warning : .error
    }
}

private struct HealthHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.store
        let report = HealthReport(store: store)

        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .center, spacing: DS.Space.s3) {
                Image(systemName: report.tone == .success ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: DS.TextSize.xl.rawValue, weight: .semibold))
                    .foregroundStyle(report.tone.color)
                Text(verbatim: "\(report.score)")
                    .dsFont(.xxl, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(report.summary)
                    .dsFont(.base, weight: .medium)
                    .foregroundStyle(DS.Palette.textSecondary)
                Spacer()
            }
            FlowLayout(spacing: DS.Space.s2) {
                Chip(text: chipName(store.topology.brand), icon: "apple.logo")
                Chip(text: Format.bytes(ProcessInfo.processInfo.physicalMemory).replacingOccurrences(of: ".0 ", with: " "))
                Chip(text: store.system.osVersion)
                if let boot = store.system.bootDate {
                    Chip(text: "已运行 " + Format.uptime(since: boot))
                }
                Chip(text: shortModel(store.system.modelName))
            }
        }
        .padding(.horizontal, DS.Space.s1)
    }

    /// “Apple M5 Max” → “M5 Max”，前面配 Apple 标志
    private func chipName(_ brand: String) -> String {
        brand.hasPrefix("Apple ") ? String(brand.dropFirst("Apple ".count)) : brand
    }

    /// “MacBook Pro (16-inch, M5 Max)” → “MacBook Pro 16 英寸”
    private func shortModel(_ name: String) -> String {
        guard let open = name.firstIndex(of: "(") else { return name }
        let base = name[..<open].trimmingCharacters(in: .whitespaces)
        let details = name[open...].dropFirst().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if let inch = details.first(where: { $0.hasSuffix("-inch") }) {
            return "\(base) \(inch.dropLast("-inch".count)) 英寸"
        }
        return base
    }
}

// MARK: - 指标卡片

private func loadLevel(_ value: Double) -> String {
    value < 0.3 ? "低负载" : value < 0.7 ? "中等负载" : "高负载"
}

private func splitRate(_ text: String) -> (String, String) {
    let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
    return (parts.first ?? text, parts.count > 1 ? parts[1] : "")
}

private struct CPUTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.store
        let total = store.cpu?.total ?? 0
        let temperature = store.sensors?.temperature(.cpu)
        let load = store.cpu?.loadAverage.first.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—"

        MetricTile(icon: "cpu", title: "CPU",
                   chip: temperature.map { Format.temperature($0.maximum, fahrenheit: model.settings.useFahrenheit) },
                   chipTone: temperature.map { Tone.forTemperature($0.maximum) } ?? .neutral,
                   value: store.cpu == nil ? "—" : "\(Int((total * 100).rounded()))", unit: "%") {
            BarHistoryChart(values: store.cpuTotal.elements, capacity: 20, height: DS.Size.tileChart)
        } footer: {
            Text(verbatim: "\(loadLevel(total)) · 负载 \(load)/\(store.topology.logicalCores)")
        }
    }
}

private struct GPUTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.store
        let utilization = store.gpu?.utilization ?? 0
        let temperature = store.sensors?.temperature(.gpu)

        MetricTile(icon: "display", title: "GPU",
                   chip: temperature.map { Format.temperature($0.maximum, fahrenheit: model.settings.useFahrenheit) },
                   chipTone: temperature.map { Tone.forTemperature($0.maximum) } ?? .neutral,
                   value: store.gpu == nil ? "—" : "\(Int((utilization * 100).rounded()))", unit: "%") {
            LineHistoryChart(values: store.gpuHistory.elements, capacity: 30, color: DS.Palette.secondary, height: DS.Size.tileChart)
        } footer: {
            Text(verbatim: [loadLevel(utilization), store.gpu?.coreCount.map { "\($0) 核" }].compactMap { $0 }.joined(separator: " · "))
        }
    }
}

private struct MemoryTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let memory = model.store.memory

        MetricTile(icon: "memorychip", title: "内存",
                   chip: memory.map { "压力 \($0.pressure.title)" },
                   chipTone: memory.map { tone($0.pressure) } ?? .neutral,
                   value: memory.map { "\(Int(($0.usedFraction * 100).rounded()))" } ?? "—", unit: "%") {
            LineHistoryChart(values: model.store.memoryHistory.elements, capacity: 30, height: DS.Size.tileChart)
        } footer: {
            Text(verbatim: memory.map { "\(Format.bytes($0.used)) / \(Format.bytes($0.total))" } ?? "—")
        }
    }

    private func tone(_ pressure: MemoryPressure) -> Tone {
        switch pressure {
        case .normal: .success
        case .warning: .warning
        case .critical: .error
        }
    }
}

private struct DiskTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let disk = model.store.disk

        MetricTile(icon: "internaldrive", title: "磁盘",
                   chip: disk.map { Format.bytes($0.total, base: .decimal).replacingOccurrences(of: ".0 ", with: " ") },
                   value: disk.map { "\(Int(($0.usedFraction * 100).rounded()))" } ?? "—", unit: "%") {
            VStack {
                Spacer()
                ProgressTrack(fraction: disk?.usedFraction ?? 0,
                              color: (disk?.usedFraction ?? 0) > 0.9 ? DS.Palette.warning : DS.Palette.primary,
                              height: DS.Space.s3)
                Spacer()
            }
        } footer: {
            Text(verbatim: disk.map { "可用 \(Format.bytes($0.available, base: .decimal))" } ?? "—")
        }
    }
}

private struct NetworkTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.store
        let rate = store.network
        let total = splitRate(Format.menuBarRate((rate?.downloadBytesPerSecond ?? 0) + (rate?.uploadBytesPerSecond ?? 0)))

        MetricTile(icon: "network", title: "网络",
                   chip: store.networkInterface.map { shortInterface($0) },
                   value: rate == nil ? "—" : total.0, unit: rate == nil ? nil : total.1) {
            DualLineChart(upload: store.uploadHistory.elements, download: store.downloadHistory.elements,
                          capacity: 30, height: DS.Size.tileChart)
        } footer: {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: "arrow.up").foregroundStyle(Color(nsColor: DS.NetworkPalette.upload))
                Text(verbatim: rate.map { Format.menuBarRate($0.uploadBytesPerSecond) } ?? "—")
                Image(systemName: "arrow.down").foregroundStyle(Color(nsColor: DS.NetworkPalette.download))
                Text(verbatim: rate.map { Format.menuBarRate($0.downloadBytesPerSecond) } ?? "—")
            }
            .fontWeight(.medium)
        }
    }

    private func shortInterface(_ info: NetworkInterfaceInfo) -> String {
        info.displayName == "VPN 隧道" ? "VPN" : info.displayName
    }
}

private struct FanTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let fans = model.store.sensors?.fans ?? []
        let fastest = model.store.fastestFan
        let isManual = fans.contains(where: \.isManual)
        // 以最高转速为 100%，比“最低到最高”的区间比例更直观
        let average = fans.isEmpty ? 0 : fans.map { $0.maximum > 0 ? $0.current / $0.maximum : 0 }.reduce(0, +) / Double(fans.count)

        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: "fan").font(.system(size: DS.TextSize.xs.rawValue, weight: .semibold))
                Text("风扇").dsFont(.xs, weight: .semibold)
                Spacer(minLength: DS.Space.s1)
                if !fans.isEmpty { Chip(text: "转速 \(Format.percent(average))") }
            }
            .foregroundStyle(DS.Palette.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1 / 2) {
                Text(verbatim: fastest.map { Int($0.current).formatted() } ?? "—")
                    .dsFont(.xl, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(verbatim: "RPM").dsFont(.xs, weight: .medium).foregroundStyle(DS.Palette.textSecondary)
            }

            Text(fanStatus(fans: fans, isManual: isManual))
                .dsFont(.xs)
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(height: DS.Size.tileChart / 2, alignment: .center)

            HStack(spacing: DS.Space.s1) {
                ForEach([FanController.Mode.automatic, .cooling, .maximum]) { mode in
                    ChipButton(title: mode.title, isSelected: model.fans.mode == mode) {
                        model.requestFanMode(mode)
                    }
                }
            }
            .disabled(fans.isEmpty)
        }
    }
}

extension FanTile {
    /// 固件只记录“手动 / 自动”，无法区分是谁设置的：OpenStats 未下发时即为其他程序（如 Stats、Mole）
    fileprivate func fanStatus(fans: [FanState], isManual: Bool) -> String {
        if fans.isEmpty { return "未检测到风扇" }
        guard isManual else { return "由 macOS 调节" }
        return model.fans.mode == .automatic ? "其他程序手动控制" : "OpenStats 控制中"
    }
}

// MARK: - 核心负载

private struct CoreLoadCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cpu = model.store.cpu
        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: "square.grid.3x3.fill").font(.system(size: DS.TextSize.xs.rawValue, weight: .semibold))
                Text("核心负载").dsFont(.xs, weight: .semibold)
                Spacer()
                LegendItem(color: DS.Palette.primary, label: "用户", value: cpu.map { Format.percent($0.user) } ?? "—")
                LegendItem(color: DS.Palette.secondary, label: "系统", value: cpu.map { Format.percent($0.system) } ?? "—")
            }
            .foregroundStyle(DS.Palette.textSecondary)
            CoreClusterBars(topology: model.store.topology, perCore: cpu?.perCore ?? [], barHeight: DS.Space.s12 + DS.Space.s4)
        }
    }
}

// MARK: - 电池

private struct BatteryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let battery = model.store.battery {
            let tone: Tone = battery.level < 0.2 ? .error : battery.isCharging ? .primary : .success
            Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s1) {
                    Image(systemName: battery.isCharging ? "battery.100.bolt" : "battery.75")
                        .font(.system(size: DS.TextSize.xs.rawValue, weight: .semibold))
                    Text("电池").dsFont(.xs, weight: .semibold)
                    Spacer(minLength: DS.Space.s1)
                    if let health = battery.health {
                        Chip(text: "健康 \(Format.percent(health))", tone: health < 0.8 ? .warning : .neutral)
                    }
                }
                .foregroundStyle(DS.Palette.textSecondary)

                HStack(alignment: .center, spacing: DS.Space.s2) {
                    VStack(alignment: .leading, spacing: DS.Space.s1 / 2) {
                        Text(verbatim: Format.percent(battery.level))
                            .dsFont(.xl, weight: .semibold)
                            .monospacedDigit()
                            .foregroundStyle(DS.Palette.textPrimary)
                        Text(stateText(battery))
                            .dsFont(.xs, weight: .medium)
                            .foregroundStyle(DS.Palette.textSecondary)
                        if let watts = battery.adapterWatts, battery.isPluggedIn {
                            Label { Text(verbatim: "\(watts)W") } icon: { Image(systemName: "bolt.fill") }
                                .dsFont(.xs, weight: .medium)
                                .foregroundStyle(DS.Palette.warning)
                        }
                    }
                    Spacer(minLength: 0)
                    RingGauge(fraction: battery.level, color: tone.color, size: DS.Space.s12 + DS.Space.s2) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: DS.TextSize.sm.rawValue, weight: .medium))
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                }

                Text(verbatim: detailText(battery))
                    .dsFont(.xs)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private func stateText(_ battery: BatteryStatus) -> String {
        if battery.isCharging { return "充电中" }
        if battery.isPluggedIn { return battery.isFullyCharged ? "已充满" : "电源供电" }
        return "电池供电"
    }

    private func detailText(_ battery: BatteryStatus) -> String {
        var parts: [String] = []
        if let minutes = battery.minutesRemaining {
            parts.append(battery.isCharging ? "\(Format.duration(minutes: minutes))后充满" : "剩余 \(Format.duration(minutes: minutes))")
        }
        if let cycles = battery.cycleCount { parts.append("循环 \(cycles) 次") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 高占用进程

private struct TopProcessesCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    private static let rowCount = 5

    var body: some View {
        let processes = Array(model.store.processes.prefix(Self.rowCount))

        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: "chart.bar.fill").font(.system(size: DS.TextSize.xs.rawValue, weight: .semibold))
                Text("高占用进程").dsFont(.xs, weight: .semibold)
                Spacer()
                Text("CPU").dsFont(.xs, weight: .medium).frame(width: DS.Size.valueColumn, alignment: .trailing)
                Text("内存").dsFont(.xs, weight: .medium).frame(width: DS.Size.valueColumn, alignment: .trailing)
                Color.clear.frame(width: DS.Size.iconInline)
            }
            .foregroundStyle(DS.Palette.textSecondary)

            // 数据到达前用等高占位行，避免面板高度变化
            ForEach(0..<max(0, Self.rowCount - processes.count), id: \.self) { _ in
                PlaceholderLine()
                    .frame(height: DS.TextSize.sm.rawValue * 1.25)
            }
            ForEach(processes) { process in
                HStack(spacing: DS.Space.s2) {
                    AppIconCache.shared.image(for: process)
                        .resizable()
                        .frame(width: DS.Size.iconInline, height: DS.Size.iconInline)
                    Text(process.displayName)
                        .dsFont(.sm, weight: .medium)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                    Text(verbatim: cpuText(process.cpu))
                        .dsFont(.sm, weight: .medium)
                        .foregroundStyle(cpuTone(process.cpu).color)
                        .frame(width: DS.Size.valueColumn, alignment: .trailing)
                    Text(verbatim: Format.bytes(process.memory))
                        .dsFont(.sm)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .frame(width: DS.Size.valueColumn, alignment: .trailing)
                    moreButton(process)
                }
                .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func moreButton(_ process: ProcessUsage) -> some View {
        let icon = Image(systemName: "ellipsis")
            .font(.system(size: DS.TextSize.xs.rawValue, weight: .bold))
            .foregroundStyle(DS.Palette.textTertiary)
            .frame(width: DS.Size.iconInline)
        if isSnapshot {
            icon
        } else {
            Menu {
                if let path = process.appBundlePath ?? process.executablePath {
                    Button("在访达中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                }
                Button("拷贝 PID \(String(process.pid))") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(String(process.pid), forType: .string)
                }
                Divider()
                Button("查看全部进程") { model.settings.panelTab = .processes }
            } label: {
                icon
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: DS.Size.iconInline)
        }
    }

    private func cpuText(_ value: Double) -> String {
        "\((value * 100).formatted(.number.precision(.fractionLength(1))))%"
    }

    private func cpuTone(_ value: Double) -> Tone {
        value >= 0.8 ? .error : value >= 0.5 ? .warning : .neutral
    }
}

// MARK: - 快捷开关

private struct QuickActionsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let keepAwake = model.keepAwake
        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: "switch.2").font(.system(size: DS.TextSize.xs.rawValue, weight: .semibold))
                Text("快捷开关").dsFont(.xs, weight: .semibold)
            }
            .foregroundStyle(DS.Palette.textSecondary)

            QuickAction(icon: "cup.and.saucer", activeIcon: "cup.and.saucer.fill", title: "防休眠",
                        detail: keepAwake.isActive ? "已开启" : "关闭", isActive: keepAwake.isActive) {
                Task { await keepAwake.setActive(!keepAwake.isActive) }
            }
            QuickAction(icon: "laptopcomputer", activeIcon: "laptopcomputer", title: "合盖运行",
                        detail: keepAwake.lidClosedActive ? "已开启" : "关闭", isActive: keepAwake.lidClosedActive) {
                model.requestLidMode(!keepAwake.lidClosedRequested)
            }
            QuickAction(icon: "fan", activeIcon: "fan.fill", title: "散热模式",
                        detail: model.fans.mode.title, isActive: model.fans.mode != .automatic) {
                model.settings.panelTab = .thermal
            }
        }
    }
}

private struct QuickAction: View {
    let icon: String
    let activeIcon: String
    let title: String
    let detail: String
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: isActive ? activeIcon : icon)
                    .font(.system(size: DS.TextSize.sm.rawValue, weight: .medium))
                    .frame(width: DS.Size.iconStandalone)
                Text(title).dsFont(.sm, weight: .medium).lineLimit(1)
                Spacer(minLength: DS.Space.s1)
                Text(detail).dsFont(.xs).foregroundStyle(isActive ? DS.Palette.primary : DS.Palette.textTertiary)
            }
            .foregroundStyle(isActive ? DS.Palette.primary : DS.Palette.textPrimary)
            .padding(.horizontal, DS.Space.s2)
            .frame(maxWidth: .infinity)
            .frame(height: DS.Size.controlHeight)
            .background(background, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var background: Color {
        if isActive { return DS.Palette.primary.opacity(0.12) }
        return hovering ? DS.Palette.surfaceHover : DS.Palette.track
    }
}

struct PlaceholderLine: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.sm)
            .fill(DS.Palette.track)
            .frame(height: DS.Size.barHeight)
    }
}
