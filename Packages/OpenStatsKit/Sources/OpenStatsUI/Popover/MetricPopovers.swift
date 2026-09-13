import AppKit
import Metrics
import SMC
import SwiftUI

private let heroGauge = DS.Space.s12 + DS.Space.s2

extension View {
    /// 详情图表高度：弹窗里紧凑，主窗口里放大
    @MainActor
    func detailChartHeight(_ isDetailPage: Bool) -> CGFloat {
        isDetailPage ? DS.Size.chartHeight * 3 : DS.Size.chartHeight
    }
}

private func loadTone(_ value: Double) -> Tone {
    value >= 0.85 ? .error : value >= 0.6 ? .warning : .primary
}

// MARK: - CPU

struct CPUPopover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isDetailPage) private var isDetailPage

    var body: some View {
        let settings = model.settings
        let store = model.store
        let cpu = store.cpu
        let cores = Double(max(1, store.topology.logicalCores))

        CPUHero()

        ForEach(MenuBarItem.cpu.popoverSections.filter { isDetailPage || settings.isVisible($0) }) { section in
            switch section {
            case .cpuHeatmap:
                SectionCard(title: section.title, trailing: { HeatLegend() }) {
                    CoreHeatmap(topology: store.topology, history: store.coreHistory.elements,
                                columns: isDetailPage ? 60 : 36,
                                rowHeight: isDetailPage ? DS.Space.s2 : DS.Space.s1 - DS.Size.stroke)
                    Text("每行一个核心，每列一次采样，最新的在右边")
                        .dsFont(.xs)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            case .cpuClusters:
                SectionCard(title: section.title) {
                    ForEach(store.topology.clusters) { cluster in
                        let average = CoreClusterBars.average(of: cluster, perCore: cpu?.perCore ?? []) ?? 0
                        ShareRow(label: "\(cluster.name) · \(cluster.coreIndices.count) 核", value: Format.percent(average),
                                 fraction: average, color: DS.Palette.cluster(cluster.id))
                    }
                    if let busiest = busiestCore(store.topology, cpu?.perCore ?? []) {
                        InfoRow(label: "最忙的核心", text: busiest)
                    }
                }
            case .cpuLoadAverage:
                SectionCard(title: section.title, trailing: { Text(loadTrend(cpu?.loadAverage ?? [])) }) {
                    let averages = cpu?.loadAverage ?? []
                    ForEach(Array(["1 分钟", "5 分钟", "15 分钟"].enumerated()), id: \.offset) { index, label in
                        let value = averages[safe: index] ?? 0
                        ShareRow(label: label,
                                 value: "每核 \((value / cores).formatted(.number.precision(.fractionLength(2))))",
                                 fraction: value / cores, color: loadTone(value / cores).color)
                    }
                    Text("平均负载除以核心数：小于 1 表示任务不用排队，大于 1 表示有任务在等 CPU")
                        .dsFont(.xs)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .cpuApps:
                SectionCard(title: section.title, trailing: { Text("CPU") }) {
                    AppUsageList(apps: AppUsage.group(store.processes).sorted { $0.cpu > $1.cpu },
                                 rowCount: isDetailPage ? 10 : 6, metric: .cpu)
                }
            default:
                EmptyView()
            }
        }
    }

    private func busiestCore(_ topology: CPUTopology, _ perCore: [Double]) -> String? {
        guard let (index, value) = perCore.enumerated().max(by: { $0.element < $1.element }).map({ ($0.offset, $0.element) }),
              let cluster = topology.clusters.first(where: { $0.coreIndices.contains(index) }) else { return nil }
        return "\(cluster.name) #\(index + 1) · \(Format.percent(value))"
    }

    private func loadTrend(_ averages: [Double]) -> String {
        guard averages.count >= 3, averages[2] > 0 else { return "" }
        let change = averages[0] / averages[2]
        return change > 1.15 ? "负载在上升" : change < 0.85 ? "负载在下降" : "负载平稳"
    }
}

/// CPU 顶部：大号占用、状态、与 30 秒前相比的变化、温度余量，下面是走势线和用户 / 系统 / 空闲构成
private struct CPUHero: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.store
        let cpu = store.cpu
        let total = cpu?.total ?? 0
        let history = store.cpuTotal.elements
        let temperature = store.sensors?.temperature(.cpu)

        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            HStack(alignment: .center, spacing: DS.Space.s3) {
                HeroValue(value: cpu.map { "\(Int(($0.total * 100).rounded()))" } ?? "—", unit: "%", size: .xxl)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    StatusBadge(text: status(total), tone: total >= 0.85 ? .error : total >= 0.6 ? .warning : .success)
                    Text(verbatim: trend(history))
                        .dsFont(.xs)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .monospacedDigit()
                }
                Spacer(minLength: DS.Space.s2)
                if let temperature {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("温度余量").dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
                        Text(verbatim: "\(Int(max(0, 100 - temperature.maximum).rounded()))°C")
                            .dsFont(.base, weight: .semibold)
                            .monospacedDigit()
                            .foregroundStyle(Tone.forTemperature(temperature.maximum).color)
                        Text(verbatim: "当前 \(Format.temperature(temperature.maximum, fahrenheit: model.settings.useFahrenheit))")
                            .dsFont(.xs)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                    .help("离 100°C 还差多少度；越接近 0，越可能因过热降频")
                }
            }
            LineHistoryChart(values: history, height: DS.Space.s8)
            if let cpu {
                WaterlineBar(segments: [(cpu.user, DS.Palette.primary), (cpu.system, DS.Palette.secondary)],
                             total: 1, height: DS.Space.s2)
                HStack(spacing: DS.Space.s3) {
                    LegendItem(color: DS.Palette.primary, label: "用户", value: Format.percent(cpu.user))
                    LegendItem(color: DS.Palette.secondary, label: "系统", value: Format.percent(cpu.system))
                    LegendItem(color: DS.Palette.track, label: "空闲", value: Format.percent(max(0, 1 - cpu.total)))
                }
            }
        }
    }

    private func status(_ total: Double) -> String {
        total >= 0.85 ? "满载" : total >= 0.6 ? "繁忙" : total >= 0.25 ? "适中" : "空闲"
    }

    /// 与大约 30 秒前（第 15 个采样之前）相比的变化
    private func trend(_ history: [Double]) -> String {
        guard history.count > 15, let now = history.last else { return "正在收集走势…" }
        let before = history[history.count - 16]
        let delta = Int(((now - before) * 100).rounded())
        if abs(delta) < 3 { return "与 30 秒前持平" }
        return delta > 0 ? "比 30 秒前高 \(delta)%" : "比 30 秒前低 \(-delta)%"
    }
}

// MARK: - 内存

struct MemoryPopover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isDetailPage) private var isDetailPage

    var body: some View {
        let settings = model.settings
        let store = model.store
        let memory = store.memory

        MemoryHero()

        ForEach(MenuBarItem.memory.popoverSections.filter { isDetailPage || settings.isVisible($0) }) { section in
            switch section {
            case .memoryWaterline:
                SectionCard(title: section.title, trailing: { Text(verbatim: memory.map { Format.bytes($0.total) } ?? "") }) {
                    if let memory {
                        let parts: [(String, UInt64, Color)] = [
                            ("App", memory.app, DS.Palette.primary),
                            ("联动", memory.wired, DS.Palette.secondary),
                            ("压缩", memory.compressed, DS.Palette.warning),
                            ("缓存", memory.cached, DS.Palette.primarySoft),
                            ("空闲", memory.free, DS.Palette.track),
                        ]
                        WaterlineBar(segments: parts.map { (Double($0.1), $0.2) }, total: Double(memory.total))
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s3), GridItem(.flexible())], spacing: DS.Space.s2) {
                            ForEach(parts, id: \.0) { part in
                                HStack(spacing: DS.Space.s1) {
                                    RoundedRectangle(cornerRadius: DS.Radius.sm / 2).fill(part.2)
                                        .frame(width: DS.Size.barHeight, height: DS.Size.barHeight)
                                    Text(part.0).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
                                    Spacer(minLength: DS.Space.s1)
                                    Text(verbatim: Format.bytes(part.1)).dsFont(.xs, weight: .medium).monospacedDigit()
                                        .foregroundStyle(DS.Palette.textPrimary)
                                }
                            }
                        }
                    }
                }
            case .memoryCompression:
                SectionCard(title: section.title) {
                    if let memory {
                        InfoRow(label: "压缩为你省下") {
                            Text(verbatim: Format.bytes(memory.compressionSavings)).foregroundStyle(DS.Palette.success)
                        }
                        InfoRow(label: "压缩比", text: memory.compressionRatio.map { "\($0.formatted(.number.precision(.fractionLength(1))))×" } ?? "—")
                        InfoRow(label: "交换区", text: memory.swapTotal > 0
                                ? "\(Format.bytes(memory.swapUsed)) / \(Format.bytes(memory.swapTotal))" : "未使用")
                        InfoRow(label: "换入 / 换出", text: store.swapRate.map { "\(Format.menuBarRate($0.swapIn)) / \(Format.menuBarRate($0.swapOut))" } ?? "—")
                        if let rate = store.swapRate, rate.swapOut > 1024 * 1024 {
                            InfoBanner(icon: "exclamationmark.triangle.fill", text: "系统正在把内存写到磁盘，可能会变慢。可以关掉占用大的应用。", tone: .warning)
                        }
                    }
                }
            case .memoryApps:
                SectionCard(title: section.title, trailing: { Text("内存") }) {
                    AppUsageList(apps: AppUsage.group(store.processes).sorted { $0.memory > $1.memory },
                                 rowCount: isDetailPage ? 10 : 6, metric: .memory, total: memory?.used)
                }
            default:
                EmptyView()
            }
        }
    }
}

/// 内存顶部：可用多少、压力状态、最近一分钟的压力走势
private struct MemoryHero: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.store
        let memory = store.memory

        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            HStack(alignment: .center, spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("还可用").dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
                    HeroValue(value: memory.map { availableNumber($0.available) } ?? "—", unit: "GB", size: .xxl)
                }
                Spacer(minLength: DS.Space.s2)
                VStack(alignment: .trailing, spacing: DS.Space.s1) {
                    StatusBadge(text: "压力\(memory?.pressure.title ?? "—")", tone: tone(memory?.pressure))
                    Text(verbatim: memory.map { "已用 \(Format.bytes($0.used)) · \(Format.percent($0.usedFraction))" } ?? "")
                        .dsFont(.xs)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .monospacedDigit()
                }
            }
            PressureStrip(history: store.pressureHistory.elements)
            HStack {
                Text("压力走势").dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
                Spacer()
                Text("最近 60 秒").dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            }
        }
    }

    private func availableNumber(_ bytes: UInt64) -> String {
        (Double(bytes) / 1_073_741_824).formatted(.number.precision(.fractionLength(1)))
    }

    private func tone(_ pressure: MemoryPressure?) -> Tone {
        switch pressure {
        case .normal: .success
        case .warning: .warning
        case .critical: .error
        case nil: .neutral
        }
    }
}

// MARK: - 按应用汇总

/// 同一个应用的主进程与辅助进程合并计算
struct AppUsage: Identifiable {
    let id: String
    let name: String
    let bundlePath: String?
    var cpu: Double
    var memory: UInt64
    var processCount: Int
    /// 占用最高的那个进程，用于图标与 Apple 智能解释
    var representative: ProcessUsage

    @MainActor
    static func group(_ processes: [ProcessUsage]) -> [AppUsage] {
        var groups: [String: AppUsage] = [:]
        for process in processes {
            let key = process.appBundlePath ?? "pid-\(process.pid)"
            if var group = groups[key] {
                group.cpu += process.cpu
                group.memory += process.memory
                group.processCount += 1
                if process.memory > group.representative.memory { group.representative = process }
                groups[key] = group
            } else {
                let name = process.appBundlePath.map { AppNameCache.shared.name(forBundle: $0) } ?? process.displayName
                groups[key] = AppUsage(id: key, name: name, bundlePath: process.appBundlePath,
                                       cpu: process.cpu, memory: process.memory, processCount: 1, representative: process)
            }
        }
        return Array(groups.values)
    }
}

private struct AppUsageList: View {
    enum Metric { case cpu, memory }

    let apps: [AppUsage]
    let rowCount: Int
    let metric: Metric
    var total: UInt64?

    var body: some View {
        let visible = Array(apps.prefix(rowCount))
        // 横条以列表里最大的一项为满格，比较谁占得多
        let peak = visible.map { metric == .cpu ? $0.cpu : Double($0.memory) }.max() ?? 1
        if visible.isEmpty {
            Text("正在统计…").dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
        }
        ForEach(visible) { app in
            let value = metric == .cpu ? app.cpu : Double(app.memory)
            VStack(spacing: DS.Space.s1) {
                HStack(spacing: DS.Space.s2) {
                    AppIconCache.shared.image(bundlePath: app.bundlePath)
                        .resizable()
                        .frame(width: DS.Size.iconInline, height: DS.Size.iconInline)
                    Text(verbatim: app.name)
                        .dsFont(.xs, weight: .medium)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                    if app.processCount > 1 {
                        Text(verbatim: "\(app.processCount) 个进程").dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
                    }
                    Spacer(minLength: DS.Space.s2)
                    Text(verbatim: valueText(app))
                        .dsFont(.xs, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                ProgressTrack(fraction: peak > 0 ? value / peak : 0, color: DS.Palette.primary, height: DS.Space.s1)
                    .padding(.leading, DS.Size.iconInline + DS.Space.s2)
            }
            .explainable(.init(app.representative))
        }
    }

    private func valueText(_ app: AppUsage) -> String {
        switch metric {
        case .cpu:
            return "\((app.cpu * 100).formatted(.number.precision(.fractionLength(1))))%"
        case .memory:
            guard let total, total > 0 else { return Format.bytes(app.memory) }
            return "\(Format.bytes(app.memory)) · \(Format.percent(Double(app.memory) / Double(total)))"
        }
    }
}

/// 标签 + 数值 + 横条
private struct ShareRow: View {
    let label: String
    let value: String
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(spacing: DS.Space.s1) {
            InfoRow(label: label, text: value)
            ProgressTrack(fraction: fraction, color: color, height: DS.Space.s1 + DS.Space.s1 / 2)
        }
    }
}

extension View {
    /// 进程行右键菜单：用 Apple 智能解释
    @ViewBuilder
    func explainable(_ subject: ProcessExplainer.Subject) -> some View {
        if ProcessExplainer.isSupported {
            ExplainableRow(subject: subject) { self }
        } else {
            self
        }
    }
}

private struct ExplainableRow<Content: View>: View {
    let subject: ProcessExplainer.Subject
    @ViewBuilder var content: Content
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        content
            .contentShape(Rectangle())
            .contextMenu(isSnapshot ? nil : ContextMenu {
                Button("用 Apple 智能解释") { model.explainProcess(subject) }
            })
    }
}

/// 标题栏里的“释放内存”：执行中显示进度，完成后短暂显示结果再恢复
struct PurgeMemoryButton: View {
    @Environment(AppModel.self) private var model
    @State private var result: MaintenanceController.Outcome?

    var body: some View {
        let maintenance = model.maintenance
        let running = maintenance.running == .purgeMemory
        Button {
            Task {
                await maintenance.run(.purgeMemory)
                result = maintenance.outcomes[.purgeMemory]
                try? await Task.sleep(for: .seconds(3))
                result = nil
            }
        } label: {
            HStack(spacing: DS.Space.s1) {
                if running {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: result == nil ? "wind" : result!.isError ? "exclamationmark.triangle" : "checkmark")
                }
                Text(running ? "正在释放…" : result?.text ?? "释放内存").lineLimit(1)
            }
            .foregroundStyle(result?.isError == true ? DS.Palette.error : result != nil ? DS.Palette.success : DS.Palette.textPrimary)
        }
        .buttonStyle(DSButtonStyle(kind: .secondary))
        .disabled(maintenance.running != nil)
        .help("清理可回收的缓存内存（需要管理员授权或辅助工具）")
    }
}

// MARK: - GPU

struct GPUPopover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isDetailPage) private var isDetailPage

    var body: some View {
        let settings = model.settings
        let store = model.store
        let gpu = store.gpu
        let temperature = store.sensors?.temperature(.gpu)

        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s3) {
                RingGauge(fraction: gpu?.utilization ?? 0, color: loadTone(gpu?.utilization ?? 0).color, size: heroGauge) {
                    Text(verbatim: gpu.map { Format.percent($0.utilization) } ?? "—")
                        .dsFont(.sm, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.textPrimary)
                }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(verbatim: gpu?.name ?? "GPU")
                        .dsFont(.sm, weight: .semibold)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                    Text(verbatim: gpu?.coreCount.map { "\($0) 核图形处理器" } ?? "图形处理器")
                        .dsFont(.xs)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                Spacer(minLength: 0)
                if let temperature {
                    Chip(text: Format.temperature(temperature.maximum, fahrenheit: settings.useFahrenheit),
                         icon: "thermometer.medium", tone: Tone.forTemperature(temperature.maximum))
                }
            }
        }

        ForEach(MenuBarItem.gpu.popoverSections.filter { isDetailPage || settings.isVisible($0) }) { section in
            switch section {
            case .gpuHistory:
                SectionCard(title: section.title, trailing: { Text("最近 60 秒") }) {
                    LineHistoryChart(values: store.gpuHistory.elements, color: DS.Palette.secondary, height: detailChartHeight(isDetailPage))
                }
            case .gpuDetails:
                SectionCard(title: section.title) {
                    InfoRow(label: "型号", text: gpu?.name ?? "—")
                    InfoRow(label: "核心数", text: gpu?.coreCount.map(String.init) ?? "—")
                    InfoRow(label: "平均温度", text: temperature.map { Format.temperature($0.average, fahrenheit: settings.useFahrenheit) } ?? "—")
                    InfoRow(label: "最高温度", text: temperature.map { Format.temperature($0.maximum, fahrenheit: settings.useFahrenheit) } ?? "—")
                }
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - 温度与风扇

struct ThermalPopover: View {
    let item: MenuBarItem
    @Environment(AppModel.self) private var model
    @Environment(\.isDetailPage) private var isDetailPage

    var body: some View {
        let settings = model.settings
        let store = model.store
        let cpu = store.sensors?.temperature(.cpu)
        let fans = store.sensors?.fans ?? []

        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            HStack(alignment: .center, spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text("CPU 最高").dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
                    HeroValue(value: cpu.map { Format.temperature($0.maximum, fahrenheit: settings.useFahrenheit) } ?? "—")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text("风扇").dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
                    HeroValue(value: store.fastestFan.map { Int($0.current).formatted() } ?? "—", unit: fans.isEmpty ? nil : "RPM")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        ForEach(item.popoverSections.filter { isDetailPage || settings.isVisible($0) }) { section in
            switch section {
            case .thermalSensors:
                SectionCard(title: section.title, trailing: { Text("最高 / 平均") }) {
                    let temperatures = store.sensors?.temperatures ?? []
                    if temperatures.isEmpty {
                        Text("正在读取传感器…").dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
                    }
                    ForEach(temperatures) { summary in
                        VStack(spacing: DS.Space.s1) {
                            InfoRow(label: summary.group.title) {
                                Text(verbatim: "\(Format.temperature(summary.maximum, fahrenheit: settings.useFahrenheit)) / \(Format.temperature(summary.average, fahrenheit: settings.useFahrenheit))")
                            }
                            ProgressTrack(fraction: summary.maximum / DS.Thermal.scaleMax,
                                          color: Tone.forTemperature(summary.maximum).color,
                                          height: DS.Space.s1)
                        }
                    }
                }
            case .thermalFans:
                SectionCard(title: section.title, trailing: { Text(fanStatusText(fans: fans, mode: model.fans.mode)) }) {
                    if fans.isEmpty {
                        Text("未检测到风扇").dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
                    } else {
                        ForEach(fans) { fan in
                            VStack(spacing: DS.Space.s1) {
                                InfoRow(label: "风扇 \(fan.id + 1)", text: Format.rpm(fan.current))
                                ProgressTrack(fraction: fan.maximum > 0 ? fan.current / fan.maximum : 0, height: DS.Space.s1)
                            }
                        }
                        HStack(spacing: DS.Space.s1) {
                            ForEach([FanController.Mode.automatic, .cooling, .maximum]) { mode in
                                ChipButton(title: mode.title, isSelected: model.fans.mode == mode) {
                                    model.requestFanMode(mode)
                                }
                            }
                        }
                    }
                }
            default:
                EmptyView()
            }
        }
    }
}

/// 固件只记录“手动 / 自动”，无法区分是谁设置的：OpenStats 未下发时即为其他程序（如 Stats、Mole）
@MainActor
func fanStatusText(fans: [FanState], mode: FanController.Mode) -> String {
    if fans.isEmpty { return "未检测到风扇" }
    guard fans.contains(where: \.isManual) else { return "由 macOS 调节" }
    return mode == .automatic ? "其他程序手动控制" : "OpenStats 控制中"
}
