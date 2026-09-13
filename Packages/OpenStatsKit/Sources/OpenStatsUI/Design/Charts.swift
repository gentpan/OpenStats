import Metrics
import SwiftUI

// 面板每秒刷新，图表全部用 Canvas 直接绘制：比 Swift Charts 轻得多，也能被 ImageRenderer 截图。
// 刷新时不加隐式动画，避免每秒触发一次持续重绘。

/// 历史柱形图：每个采样一根柱子，空位画基线
struct BarHistoryChart: View {
    let values: [Double]
    var capacity: Int = 24
    var color: Color = DS.Palette.primary
    var warnColor: Color = DS.Palette.warning
    var warnThreshold: Double = 0.8
    var height: CGFloat = DS.Size.chartHeight

    var body: some View {
        Canvas { context, size in
            let gap = DS.Space.s1 / 2
            let barWidth = max(1, (size.width - gap * CGFloat(capacity - 1)) / CGFloat(capacity))
            let recent = values.suffix(capacity)
            let offset = capacity - recent.count
            let baseline = DS.Size.stroke * 2

            for index in 0..<capacity {
                let x = CGFloat(index) * (barWidth + gap)
                guard index >= offset else {
                    context.fill(Path(CGRect(x: x, y: size.height - baseline, width: barWidth, height: baseline)),
                                 with: .color(DS.Palette.track))
                    continue
                }
                let value = min(1, max(0, recent[recent.startIndex + index - offset]))
                let barHeight = max(baseline, size.height * value)
                let rect = CGRect(x: x, y: size.height - barHeight, width: barWidth, height: barHeight)
                let fill = value >= warnThreshold ? warnColor : color
                context.fill(Path(roundedRect: rect, cornerRadius: min(DS.Radius.sm / 2, barWidth / 2)),
                             with: .color(value < 0.02 ? DS.Palette.neutral300 : fill))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// 历史折线（可带实色半透明填充）
struct LineHistoryChart: View {
    let values: [Double]
    var capacity: Int = MetricsStore.historyCapacity
    var maxValue: Double = 1
    var color: Color = DS.Palette.primary
    var filled = true
    var height: CGFloat = DS.Size.chartHeight

    var body: some View {
        Canvas { context, size in
            let line = LineHistoryChart.path(values: values, capacity: capacity, maxValue: maxValue, in: size)
            guard let line else { return }
            if filled {
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: area.boundingRect.minX, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .color(color.opacity(0.14)))
            }
            context.stroke(line, with: .color(color),
                           style: StrokeStyle(lineWidth: DS.Size.chartLine, lineCap: .round, lineJoin: .round))
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// 右对齐：最新的点在最右侧
    static func path(values: [Double], capacity: Int, maxValue: Double, in size: CGSize) -> Path? {
        let recent = Array(values.suffix(capacity))
        guard recent.count > 1 else { return nil }
        let step = size.width / CGFloat(max(1, capacity - 1))
        let inset = DS.Size.chartLine
        let usable = size.height - inset * 2
        let peak = max(maxValue, .leastNonzeroMagnitude)
        var path = Path()
        for (index, value) in recent.enumerated() {
            let x = size.width - CGFloat(recent.count - 1 - index) * step
            let y = inset + usable * (1 - CGFloat(min(1, max(0, value / peak))))
            index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

/// 上传 / 下载双折线，按两者峰值归一化
struct DualLineChart: View {
    let upload: [Double]
    let download: [Double]
    var capacity: Int = MetricsStore.historyCapacity
    var height: CGFloat = DS.Size.chartHeight

    var body: some View {
        Canvas { context, size in
            let peak = max(upload.max() ?? 0, download.max() ?? 0, 64 * 1024)
            let style = StrokeStyle(lineWidth: DS.Size.chartLine, lineCap: .round, lineJoin: .round)
            let series: [([Double], Color)] = [(download, Color(nsColor: DS.NetworkPalette.download)),
                                               (upload, Color(nsColor: DS.NetworkPalette.upload))]
            for (values, color) in series {
                guard let line = LineHistoryChart.path(values: values, capacity: capacity, maxValue: peak * 1.1, in: size) else { continue }
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: area.boundingRect.minX, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .color(color.opacity(0.10)))
                context.stroke(line, with: .color(color), style: style)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// 环形进度（饼图风格），中间可放图标或文字
struct RingGauge<Center: View>: View {
    let fraction: Double
    var color: Color = DS.Palette.success
    var lineWidth: CGFloat = DS.Space.s1 + DS.Space.s1 / 2
    var size: CGFloat = DS.Space.s12 + DS.Space.s4
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle().stroke(DS.Palette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
    }
}

/// 每个核心一根竖条，按性能档分组（高性能档在左）
struct CoreClusterBars: View {
    let topology: CPUTopology
    let perCore: [Double]
    var barHeight: CGFloat = DS.Size.coreBarHeight
    /// 按核心类型着色（各类核心的平均占用显示在详细信息里）
    var byCluster = false

    static func average(of cluster: CPUCluster, perCore: [Double]) -> Double? {
        let values = cluster.coreIndices.compactMap { $0 < perCore.count ? perCore[$0] : nil }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static let barGap = DS.Space.s1 / 2
    private static let groupGap = DS.Space.s3

    private static func barWidth(for width: CGFloat, clusters: [CPUCluster], total: Int) -> CGFloat {
        let gaps = CGFloat(total - clusters.count) * barGap + CGFloat(max(0, clusters.count - 1)) * groupGap
        return max(1, (width - gaps) / CGFloat(total))
    }

    var body: some View {
        let clusters = topology.clusters.sorted { ($0.coreIndices.first ?? 0) > ($1.coreIndices.first ?? 0) }
        let total = max(1, clusters.reduce(0) { $0 + $1.coreIndices.count })

        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Canvas { context, size in
                var x: CGFloat = 0
                let barWidth = Self.barWidth(for: size.width, clusters: clusters, total: total)
                for cluster in clusters {
                    for index in cluster.coreIndices {
                        let value = index < perCore.count ? min(1, max(0, perCore[index])) : 0
                        let track = CGRect(x: x, y: 0, width: barWidth, height: size.height)
                        context.fill(Path(roundedRect: track, cornerRadius: DS.Radius.sm / 2), with: .color(DS.Palette.track))
                        let fillHeight = size.height * value
                        let fill = CGRect(x: x, y: size.height - fillHeight, width: barWidth, height: fillHeight)
                        let color = byCluster ? DS.Palette.cluster(cluster.id) : value >= 0.8 ? DS.Palette.warning : DS.Palette.primary
                        context.fill(Path(roundedRect: fill, cornerRadius: DS.Radius.sm / 2), with: .color(color))
                        x += barWidth + Self.barGap
                    }
                    x += Self.groupGap - Self.barGap
                }
            }
            .frame(height: barHeight)

            // 标签宽度与上方柱组一致
            GeometryReader { proxy in
                let barWidth = Self.barWidth(for: proxy.size.width, clusters: clusters, total: total)
                HStack(spacing: Self.groupGap) {
                    ForEach(clusters) { cluster in
                        let count = CGFloat(cluster.coreIndices.count)
                        HStack(spacing: DS.Space.s1) {
                            if byCluster {
                                RoundedRectangle(cornerRadius: DS.Radius.sm / 2).fill(DS.Palette.cluster(cluster.id))
                                    .frame(width: DS.Size.barHeight, height: DS.Size.barHeight)
                            }
                            Text(verbatim: label(cluster))
                                .dsFont(.xs)
                                .foregroundStyle(DS.Palette.textTertiary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                            .frame(width: count * barWidth + (count - 1) * Self.barGap, alignment: .leading)
                    }
                }
            }
            .frame(height: DS.TextSize.xs.rawValue * 1.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("各核心负载")
    }

    private func label(_ cluster: CPUCluster) -> String {
        "\(cluster.name) · \(cluster.coreIndices.count)"
    }
}

/// 分段圆环：各段首尾相接（内存的 App / 联动 / 压缩），剩余为底槽
struct SegmentedRing<Center: View>: View {
    let segments: [(fraction: Double, color: Color)]
    var lineWidth: CGFloat = DS.Space.s2
    var size: CGFloat = DS.Space.s16
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle().stroke(DS.Palette.track, lineWidth: lineWidth)
            ForEach(Array(ranges.enumerated()), id: \.offset) { _, range in
                Circle()
                    .trim(from: range.start, to: range.end)
                    .stroke(range.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            center
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
    }

    private var ranges: [(start: Double, end: Double, color: Color)] {
        var start = 0.0
        return segments.map { segment in
            let end = min(1, start + max(0, segment.fraction))
            defer { start = end }
            return (start, end, segment.color)
        }
    }
}

/// 内存压力仪表：半圆弧分正常、偏高、严重三段，指针指向当前档位
struct PressureGauge: View {
    let pressure: MemoryPressure?
    var width: CGFloat = DS.Space.s16

    var body: some View {
        VStack(spacing: DS.Space.s1) {
            Canvas { context, size in
                let lineWidth = DS.Space.s2 - DS.Space.s1 / 2
                let radius = min(size.width / 2, size.height) - lineWidth / 2
                let center = CGPoint(x: size.width / 2, y: size.height - DS.Space.s1)
                // 角度从左（0°）经过顶部到右（180°）
                func point(_ degrees: Double, _ r: CGFloat) -> CGPoint {
                    let radians = degrees * .pi / 180
                    return CGPoint(x: center.x - r * cos(radians), y: center.y - r * sin(radians))
                }
                let bands: [(Double, Double, Color)] = [(0, 58, DS.Palette.success), (62, 118, DS.Palette.warning), (122, 180, DS.Palette.error)]
                for (start, end, color) in bands {
                    var arc = Path()
                    arc.move(to: point(start, radius))
                    for step in stride(from: start, through: end, by: 2) { arc.addLine(to: point(step, radius)) }
                    context.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
                let angle: Double = switch pressure {
                case .warning: 90
                case .critical: 150
                default: 30
                }
                var needle = Path()
                needle.move(to: center)
                needle.addLine(to: point(angle, radius * 0.72))
                context.stroke(needle, with: .color(DS.Palette.textPrimary),
                               style: StrokeStyle(lineWidth: DS.Size.chartLine * 2, lineCap: .round))
                let dot = DS.Space.s1 + DS.Space.s1 / 2
                context.fill(Path(ellipseIn: CGRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot)),
                             with: .color(DS.Palette.textPrimary))
            }
            .frame(width: width, height: width / 2 + DS.Space.s1)
            Text(pressure.map { "压力\($0.title)" } ?? "—")
                .dsFont(.xs, weight: .semibold)
                .foregroundStyle(DS.Palette.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("内存压力 \(pressure?.title ?? "未知")")
    }
}

/// 上下镜像的流量图：上半部分上传、下半部分下载，各自按自己的峰值缩放
struct MirroredRateChart: View {
    let upload: [Double]
    let download: [Double]
    var capacity: Int = MetricsStore.historyCapacity
    var height: CGFloat = DS.Size.chartHeight

    /// 峰值太小时按 64 KB/s 缩放，避免空闲时的噪声被放大成满格
    static let floor = 64.0 * 1024

    var body: some View {
        Canvas { context, size in
            let middle = size.height / 2
            let half = CGSize(width: size.width, height: middle)
            let series: [([Double], Color, Bool)] = [
                (upload, Color(nsColor: DS.NetworkPalette.upload), true),
                (download, Color(nsColor: DS.NetworkPalette.download), false),
            ]
            for (values, color, above) in series {
                let peak = max(values.max() ?? 0, Self.floor)
                guard var line = LineHistoryChart.path(values: values, capacity: capacity, maxValue: peak, in: half) else { continue }
                if !above {
                    // 下半部分：向下翻转
                    line = line.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: middle * 2))
                }
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: middle))
                area.addLine(to: CGPoint(x: line.boundingRect.minX, y: middle))
                area.closeSubpath()
                context.fill(area, with: .color(color.opacity(0.14)))
                context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: DS.Size.chartLine, lineJoin: .round))
            }
            context.fill(Path(CGRect(x: 0, y: middle - DS.Size.stroke / 2, width: size.width, height: DS.Size.stroke)),
                         with: .color(DS.Palette.border))
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// 连接探测格子：按时间从左到右、从上到下排列，最新的一格在末尾。
/// 绿色正常，橙色延迟偏高，红色超时，灰色尚无数据
struct ProbeGrid: View {
    let samples: [ProbeSample]
    var columns = 20
    var rows = 3
    var slowThreshold: Double = 200

    var body: some View {
        let capacity = columns * rows
        let recent = Array(samples.suffix(capacity))
        Canvas { context, size in
            let gap = DS.Space.s1 / 2
            let cellWidth = (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let cellHeight = (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            let offset = capacity - recent.count
            for index in 0..<capacity {
                let rect = CGRect(x: CGFloat(index % columns) * (cellWidth + gap),
                                  y: CGFloat(index / columns) * (cellHeight + gap),
                                  width: cellWidth, height: cellHeight)
                let color: Color
                if index < offset {
                    color = DS.Palette.track
                } else if let latency = recent[index - offset].latency {
                    color = latency >= slowThreshold ? DS.Palette.warning : DS.Palette.success
                } else {
                    color = DS.Palette.error
                }
                context.fill(Path(roundedRect: rect, cornerRadius: DS.Radius.sm / 2), with: .color(color))
            }
        }
        // 格子保持接近正方形，宽度随容器变化
        .aspectRatio(CGFloat(columns) / CGFloat(rows), contentMode: .fit)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement()
        .accessibilityLabel("连接探测历史")
    }
}
