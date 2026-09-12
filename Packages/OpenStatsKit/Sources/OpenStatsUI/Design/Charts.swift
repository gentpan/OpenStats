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
                        context.fill(Path(roundedRect: fill, cornerRadius: DS.Radius.sm / 2),
                                     with: .color(value >= 0.8 ? DS.Palette.warning : DS.Palette.primary))
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
                        Text(verbatim: "\(cluster.name) · \(cluster.coreIndices.count)")
                            .dsFont(.xs)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .lineLimit(1)
                            .frame(width: count * barWidth + (count - 1) * Self.barGap, alignment: .leading)
                    }
                }
            }
            .frame(height: DS.TextSize.xs.rawValue * 1.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("各核心负载")
    }
}
