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
        let temperature = store.sensors?.temperature(.cpu)

        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s3) {
                RingGauge(fraction: cpu?.total ?? 0, color: loadTone(cpu?.total ?? 0).color, size: heroGauge) {
                    Text(verbatim: cpu.map { Format.percent($0.total) } ?? "—")
                        .dsFont(.sm, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.textPrimary)
                }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    LegendItem(color: DS.Palette.primary, label: "用户", value: cpu.map { Format.percent($0.user) } ?? "—")
                    LegendItem(color: DS.Palette.secondary, label: "系统", value: cpu.map { Format.percent($0.system) } ?? "—")
                    LegendItem(color: DS.Palette.neutral300, label: "空闲",
                               value: cpu.map { Format.percent(max(0, 1 - $0.total)) } ?? "—")
                }
                Spacer(minLength: 0)
                if let temperature {
                    Chip(text: Format.temperature(temperature.maximum, fahrenheit: settings.useFahrenheit),
                         icon: "thermometer.medium", tone: Tone.forTemperature(temperature.maximum))
                }
            }
        }

        ForEach(MenuBarItem.cpu.popoverSections.filter { isDetailPage || settings.isVisible($0) }) { section in
            switch section {
            case .cpuHistory:
                SectionCard(title: section.title, trailing: { Text("最近 60 秒") }) {
                    BarHistoryChart(values: store.cpuTotal.elements, capacity: isDetailPage ? 60 : 40, height: detailChartHeight(isDetailPage))
                }
            case .cpuCores:
                SectionCard(title: section.title) {
                    CoreClusterBars(topology: store.topology, perCore: cpu?.perCore ?? [])
                }
            case .cpuDetails:
                SectionCard(title: section.title) {
                    InfoRow(label: "处理器", text: store.topology.brand)
                    InfoRow(label: "核心", text: coreSummary(store.topology))
                    InfoRow(label: "负载平均", text: cpu.map { loadAverage($0.loadAverage) } ?? "—")
                    if let boot = store.system.bootDate {
                        InfoRow(label: "已运行", text: Format.uptime(since: boot))
                    }
                }
            case .cpuProcesses:
                SectionCard(title: section.title, trailing: { Text("CPU") }) {
                    let processes = store.processes
                    ProcessList(count: processes.count) { index in
                        let process = processes[index]
                        HStack(spacing: DS.Space.s2) {
                            ProcessNameLabel(icon: AppIconCache.shared.image(for: process), name: process.displayName)
                            Text(verbatim: "\((process.cpu * 100).formatted(.number.precision(.fractionLength(1))))%")
                                .dsFont(.xs, weight: .medium)
                                .monospacedDigit()
                                .foregroundStyle(DS.Palette.textSecondary)
                        }
                    }
                }
            default:
                EmptyView()
            }
        }
    }

    private func coreSummary(_ topology: CPUTopology) -> String {
        let clusters = topology.clusters.map { "\($0.coreIndices.count) \($0.name)" }.joined(separator: " + ")
        return clusters.isEmpty ? "\(topology.logicalCores) 核" : "\(topology.logicalCores) 核（\(clusters)）"
    }

    private func loadAverage(_ values: [Double]) -> String {
        values.prefix(3).map { $0.formatted(.number.precision(.fractionLength(2))) }.joined(separator: " · ")
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

        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s3) {
                RingGauge(fraction: memory?.usedFraction ?? 0, color: pressureTone(memory?.pressure).color, size: heroGauge) {
                    Text(verbatim: memory.map { Format.percent($0.usedFraction) } ?? "—")
                        .dsFont(.sm, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.textPrimary)
                }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    HeroValue(value: memory.map { Format.bytes($0.used) } ?? "—", unit: memory.map { "/ \(Format.bytes($0.total))" }, size: .lg)
                    StatusBadge(text: "内存压力 \(memory?.pressure.title ?? "—")", tone: pressureTone(memory?.pressure))
                }
                Spacer(minLength: 0)
            }
        }

        ForEach(MenuBarItem.memory.popoverSections.filter { isDetailPage || settings.isVisible($0) }) { section in
            switch section {
            case .memoryHistory:
                SectionCard(title: section.title, trailing: { Text("最近 60 秒") }) {
                    LineHistoryChart(values: store.memoryHistory.elements, height: detailChartHeight(isDetailPage))
                }
            case .memoryBreakdown:
                SectionCard(title: section.title) {
                    if let memory {
                        MemoryBar(memory: memory)
                        LegendRow(color: DS.Palette.primary, label: "App 内存", value: Format.bytes(memory.app))
                        LegendRow(color: DS.Palette.secondary, label: "联动内存", value: Format.bytes(memory.wired))
                        LegendRow(color: DS.Palette.warning, label: "被压缩", value: Format.bytes(memory.compressed))
                        LegendRow(color: DS.Palette.neutral300, label: "缓存文件", value: Format.bytes(memory.cached))
                        LegendRow(color: DS.Palette.track, label: "交换空间", value: Format.bytes(memory.swapUsed))
                    }
                    PurgeMemoryRow()
                }
            case .memoryProcesses:
                SectionCard(title: section.title, trailing: { Text("内存") }) {
                    let processes = store.processes.sorted { $0.memory > $1.memory }
                    ProcessList(count: processes.count) { index in
                        let process = processes[index]
                        HStack(spacing: DS.Space.s2) {
                            ProcessNameLabel(icon: AppIconCache.shared.image(for: process), name: process.displayName)
                            Text(verbatim: Format.bytes(process.memory))
                                .dsFont(.xs, weight: .medium)
                                .monospacedDigit()
                                .foregroundStyle(DS.Palette.textSecondary)
                        }
                    }
                }
            default:
                EmptyView()
            }
        }
    }

    private func pressureTone(_ pressure: MemoryPressure?) -> Tone {
        switch pressure {
        case .normal: .success
        case .warning: .warning
        case .critical: .error
        case nil: .neutral
        }
    }
}

private struct LegendRow: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            RoundedRectangle(cornerRadius: DS.Radius.sm / 2).fill(color)
                .frame(width: DS.Size.barHeight, height: DS.Size.barHeight)
            Text(label).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: value).dsFont(.xs, weight: .medium).monospacedDigit().foregroundStyle(DS.Palette.textPrimary)
        }
    }
}

/// App / 联动 / 压缩三段堆叠条，剩余部分为可用
private struct MemoryBar: View {
    let memory: MemoryUsage

    var body: some View {
        GeometryReader { proxy in
            let total = max(1, Double(memory.total))
            let parts: [(UInt64, Color)] = [(memory.app, DS.Palette.primary), (memory.wired, DS.Palette.secondary),
                                            (memory.compressed, DS.Palette.warning)]
            HStack(spacing: DS.Size.stroke) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle().fill(part.1)
                        .frame(width: max(0, proxy.size.width * Double(part.0) / total - DS.Size.stroke))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .background(DS.Palette.track)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .frame(height: DS.Space.s3)
    }
}

private struct PurgeMemoryRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isDetailPage) private var isDetailPage

    var body: some View {
        let maintenance = model.maintenance
        HStack(spacing: DS.Space.s2) {
            Button(maintenance.running == .purgeMemory ? "正在释放…" : "释放内存") {
                Task { await maintenance.run(.purgeMemory) }
            }
            .buttonStyle(DSButtonStyle(kind: .secondary))
            .disabled(maintenance.running != nil)
            if let outcome = maintenance.outcomes[.purgeMemory] {
                Text(outcome.text)
                    .dsFont(.xs)
                    .foregroundStyle(outcome.isError ? DS.Palette.error : DS.Palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
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
