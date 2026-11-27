import Localization
import Metrics
import SwiftUI

// 面板每秒刷新，图表全部用形状（Shape）画，不用 Canvas：只要进程里有一个 Canvas 在反复重绘，
// SwiftUI 就会占住约 190 MB 图形内存（与 Canvas 的大小、数量、窗口大小都无关），形状没有这笔开销，也比 Swift Charts 轻得多。
// 同一种颜色的图形合成一个形状，一张图只有几层。刷新时不加隐式动画，避免每秒触发一次持续重绘。

/// 按尺寸生成路径的形状，图表的每一层都用它画
struct ChartPath: Shape {
    let build: @Sendable (CGSize) -> Path

    init(_ build: @escaping @Sendable (CGSize) -> Path) {
        self.build = build
    }

    func path(in rect: CGRect) -> Path {
        build(rect.size).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// 历史柱形图：每个采样一根柱子，空位画基线
struct BarHistoryChart: View {
    let values: [Double]
    var capacity: Int = 24
    var color: Color = DS.Palette.data
    var warnColor: Color = DS.Palette.warning
    var warnThreshold: Double = 0.8
    var height: CGFloat = DS.Size.chartHeight

    private enum Kind: Sendable { case empty, idle, normal, warn }

    var body: some View {
        let values = values, capacity = capacity, threshold = warnThreshold
        ZStack {
            ChartPath { Self.bars(.empty, values: values, capacity: capacity, threshold: threshold, in: $0) }.fill(DS.Palette.track)
            ChartPath { Self.bars(.idle, values: values, capacity: capacity, threshold: threshold, in: $0) }.fill(DS.Palette.neutral300)
            ChartPath { Self.bars(.normal, values: values, capacity: capacity, threshold: threshold, in: $0) }.fill(color)
            ChartPath { Self.bars(.warn, values: values, capacity: capacity, threshold: threshold, in: $0) }.fill(warnColor)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// 某一类柱子合成的路径：空位是一条基线，几乎为零的画成浅灰，超过阈值的用警告色
    nonisolated private static func bars(_ kind: Kind, values: [Double], capacity: Int, threshold: Double, in size: CGSize) -> Path {
        let gap = DS.Space.s1 / 2
        let barWidth = max(1, (size.width - gap * CGFloat(capacity - 1)) / CGFloat(capacity))
        let recent = values.suffix(capacity)
        let offset = capacity - recent.count
        let baseline = DS.Size.stroke * 2
        var path = Path()
        for index in 0..<capacity {
            let x = CGFloat(index) * (barWidth + gap)
            guard index >= offset else {
                if kind == .empty { path.addRect(CGRect(x: x, y: size.height - baseline, width: barWidth, height: baseline)) }
                continue
            }
            let value = min(1, max(0, recent[recent.startIndex + index - offset]))
            let current: Kind = value < 0.02 ? .idle : value >= threshold ? .warn : .normal
            guard current == kind else { continue }
            let barHeight = max(baseline, size.height * value)
            let rect = CGRect(x: x, y: size.height - barHeight, width: barWidth, height: barHeight)
            path.addPath(Path(roundedRect: rect, cornerRadius: min(DS.Radius.sm / 2, barWidth / 2), style: .continuous))
        }
        return path
    }
}

/// 图表里 25% / 50% / 75% 三条淡淡的参考线
struct ChartGrid: View {
    var body: some View {
        ChartPath { size in
            let usable = size.height - DS.Size.chartLine * 2
            var path = Path()
            for fraction in [0.25, 0.5, 0.75] {
                let y = (DS.Size.chartLine + usable * CGFloat(1 - fraction)).rounded()
                path.addRect(CGRect(x: 0, y: y, width: size.width, height: DS.Size.stroke))
            }
            return path
        }
        .fill(DS.Palette.border)
    }
}

/// 历史折线（可带实色半透明填充）
struct LineHistoryChart: View {
    let values: [Double]
    var capacity: Int = MetricsStore.historyCapacity
    var maxValue: Double = 1
    var color: Color = DS.Palette.data
    var filled = true
    /// 在 25% / 50% / 75% 画三条淡淡的参考线，图表较高时（主窗口）用来读数
    var grid = false
    var height: CGFloat = DS.Size.chartHeight

    nonisolated static let lineStyle = StrokeStyle(lineWidth: DS.Size.chartLine, lineCap: .round, lineJoin: .round)

    var body: some View {
        let values = values, capacity = capacity, maxValue = maxValue
        ZStack {
            if grid { ChartGrid() }
            if filled {
                ChartPath { size in
                    Self.path(values: values, capacity: capacity, maxValue: maxValue, in: size).map { Self.area(under: $0, in: size) } ?? Path()
                }
                .fill(color.opacity(0.14))
            }
            ChartPath { Self.path(values: values, capacity: capacity, maxValue: maxValue, in: $0) ?? Path() }
                .stroke(color, style: Self.lineStyle)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// 右对齐：最新的点在最右侧
    nonisolated static func path(values: [Double], capacity: Int, maxValue: Double, in size: CGSize) -> Path? {
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

    /// 折线与底边围成的面积
    nonisolated static func area(under line: Path, in size: CGSize) -> Path {
        var area = line
        area.addLine(to: CGPoint(x: size.width, y: size.height))
        area.addLine(to: CGPoint(x: line.boundingRect.minX, y: size.height))
        area.closeSubpath()
        return area
    }
}

/// 按时间定位的短期走势线：最新的采样固定在右边缘，往左按真实时间间隔铺开，
/// 采样间隔变化（后台 2 秒、打开详情后 1 秒）也不会把曲线拉伸；相邻采样间隔超过 10 秒（睡眠）线条断开
struct TimedLineChart: View {
    let points: [TimedValue]
    let duration: TimeInterval
    let end: Date
    var color: Color = DS.Palette.data
    /// 在 25% / 50% / 75% 画三条淡淡的参考线
    var grid = false
    var height: CGFloat = DS.Size.chartHeight

    nonisolated static let gapLimit: TimeInterval = 10

    var body: some View {
        let points = points, duration = duration, end = end
        ZStack {
            if grid { ChartGrid() }
            ChartPath { Self.paths(points, duration: duration, end: end, in: $0).area }
                .fill(color.opacity(0.14))
            ChartPath { Self.paths(points, duration: duration, end: end, in: $0).line }
                .stroke(color, style: LineHistoryChart.lineStyle)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// 各段折线与它们下方的面积，各自合成一条路径
    nonisolated static func paths(_ points: [TimedValue], duration: TimeInterval, end: Date, in size: CGSize) -> (line: Path, area: Path) {
        var line = Path()
        var area = Path()
        for segment in segments(points, duration: duration, end: end, in: size) {
            guard let first = segment.first, let last = segment.last else { continue }
            var piece = Path()
            piece.addLines(segment.count == 1 ? [first, CGPoint(x: first.x + DS.Size.stroke, y: first.y)] : segment)
            line.addPath(piece)
            piece.addLine(to: CGPoint(x: last.x, y: size.height))
            piece.addLine(to: CGPoint(x: first.x, y: size.height))
            piece.closeSubpath()
            area.addPath(piece)
        }
        return (line, area)
    }

    /// 落在 [end − duration, end] 内的采样换算成坐标（0 在下、1 在上），按间隔断开成若干段
    nonisolated static func segments(_ points: [TimedValue], duration: TimeInterval, end: Date, in size: CGSize) -> [[CGPoint]] {
        let start = end.addingTimeInterval(-duration)
        let inset = DS.Size.chartLine
        let usable = size.height - inset * 2
        var segments: [[CGPoint]] = []
        var previous: Date?
        for point in points where point.date >= start && point.date <= end {
            let location = CGPoint(x: size.width * CGFloat(point.date.timeIntervalSince(start) / max(duration, 1)),
                                   y: inset + usable * CGFloat(1 - min(1, max(0, point.value))))
            if let previous, point.date.timeIntervalSince(previous) <= gapLimit, !segments.isEmpty {
                segments[segments.count - 1].append(location)
            } else {
                segments.append([location])
            }
            previous = point.date
        }
        return segments
    }
}

/// 上传 / 下载双折线，按两者峰值归一化
struct DualLineChart: View {
    let upload: [Double]
    let download: [Double]
    var capacity: Int = MetricsStore.historyCapacity
    var height: CGFloat = DS.Size.chartHeight

    var body: some View {
        let peak = max(upload.max() ?? 0, download.max() ?? 0, 64 * 1024) * 1.1
        ZStack {
            layers(download, color: Color(nsColor: DS.NetworkPalette.download), peak: peak)
            layers(upload, color: Color(nsColor: DS.NetworkPalette.upload), peak: peak)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func layers(_ values: [Double], color: Color, peak: Double) -> some View {
        let capacity = capacity
        ChartPath { size in
            LineHistoryChart.path(values: values, capacity: capacity, maxValue: peak, in: size)
                .map { LineHistoryChart.area(under: $0, in: size) } ?? Path()
        }
        .fill(color.opacity(0.10))
        ChartPath { LineHistoryChart.path(values: values, capacity: capacity, maxValue: peak, in: $0) ?? Path() }
            .stroke(color, style: LineHistoryChart.lineStyle)
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

    nonisolated private static let barGap = DS.Space.s1 / 2
    nonisolated private static let groupGap = DS.Space.s3
    nonisolated private static let warnThreshold = 0.8

    nonisolated private static func barWidth(for width: CGFloat, clusters: [CPUCluster], total: Int) -> CGFloat {
        let gaps = CGFloat(total - clusters.count) * barGap + CGFloat(max(0, clusters.count - 1)) * groupGap
        return max(1, (width - gaps) / CGFloat(total))
    }

    var body: some View {
        let clusters = topology.clusters.sorted { ($0.coreIndices.first ?? 0) > ($1.coreIndices.first ?? 0) }
        let total = max(1, clusters.reduce(0) { $0 + $1.coreIndices.count })
        let perCore = perCore

        VStack(alignment: .leading, spacing: DS.Space.s1) {
            ZStack {
                ChartPath { Self.bars(clusters: clusters, perCore: perCore, total: total, in: $0, track: true) { _, _ in true } }
                    .fill(DS.Palette.track)
                if byCluster {
                    ForEach(clusters) { cluster in
                        let id = cluster.id
                        ChartPath { Self.bars(clusters: clusters, perCore: perCore, total: total, in: $0) { owner, _ in owner == id } }
                            .fill(DS.Palette.cluster(id))
                    }
                } else {
                    ChartPath { Self.bars(clusters: clusters, perCore: perCore, total: total, in: $0) { _, value in value < Self.warnThreshold } }
                        .fill(DS.Palette.data)
                    ChartPath { Self.bars(clusters: clusters, perCore: perCore, total: total, in: $0) { _, value in value >= Self.warnThreshold } }
                        .fill(DS.Palette.warning)
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
                                RoundedRectangle(cornerRadius: DS.Radius.sm / 2, style: .continuous).fill(DS.Palette.cluster(cluster.id))
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
        .accessibilityLabel(tr("各核心占用"))
    }

    /// 满足条件的核心合成一条路径：`track` 为真时是整根底槽，否则是按占用高度填充的部分
    nonisolated private static func bars(clusters: [CPUCluster], perCore: [Double], total: Int, in size: CGSize, track: Bool = false,
                             where include: (_ cluster: Int, _ value: Double) -> Bool) -> Path {
        let barWidth = barWidth(for: size.width, clusters: clusters, total: total)
        var path = Path()
        var x: CGFloat = 0
        for cluster in clusters {
            for index in cluster.coreIndices {
                let value = index < perCore.count ? min(1, max(0, perCore[index])) : 0
                if include(cluster.id, value) {
                    let height = track ? size.height : size.height * value
                    let rect = CGRect(x: x, y: size.height - height, width: barWidth, height: height)
                    path.addPath(Path(roundedRect: rect, cornerRadius: DS.Radius.sm / 2, style: .continuous))
                }
                x += barWidth + barGap
            }
            x += groupGap - barGap
        }
        return path
    }

    private func label(_ cluster: CPUCluster) -> String {
        "\(cluster.name) · \(cluster.coreIndices.count)"
    }
}

/// 核心热力图：每行一个核心（按类型分组，高性能档在上），每列一次采样，最新在右；
/// 最右侧单独一根粗条画此刻的占用，一眼能看出现在哪些核心在忙。
/// 颜色越深越忙，超过 85% 用警告色。深浅分成 20 档，每档合成一个形状
struct CoreHeatmap: View {
    let topology: CPUTopology
    let history: [[Double]]
    var columns = 40
    var rowHeight: CGFloat = DS.Space.s1 - DS.Size.stroke

    nonisolated private static let gap = DS.Size.stroke
    nonisolated private static let groupGap = DS.Space.s1
    nonisolated private static let nowWidth = DS.Space.s2
    nonisolated private static let nowGap = DS.Space.s1
    nonisolated private static let warnThreshold = 0.85
    nonisolated private static let steps = 20
    /// 还没有采样的格子与超过阈值的格子各占一档
    nonisolated private static let emptyLevel = -1
    nonisolated private static let warnLevel = Int.max

    var body: some View {
        // 先把属性复制成局部量：后面的闭包只捕获这两个值
        let columns = columns, rowHeight = rowHeight
        let clusters = topology.clusters.sorted { $0.id < $1.id }
        let height = clusters.reduce(CGFloat(0)) { $0 + CGFloat($1.coreIndices.count) * (rowHeight + Self.gap) }
            + CGFloat(max(0, clusters.count - 1)) * Self.groupGap
        // 每组核心自上而下的顺序，与左侧标签一致
        let rows = clusters.map { Array($0.coreIndices.reversed()) }
        let recent = Array(history.suffix(columns))
        let levels = Self.levels(rows: rows, recent: recent, columns: columns)

        HStack(alignment: .top, spacing: DS.Space.s2) {
            VStack(alignment: .leading, spacing: Self.groupGap) {
                ForEach(clusters) { cluster in
                    // 类型名后面带上核心数，与“各核心占用”里的分组标题一致
                    Text(verbatim: "\(cluster.name) · \(cluster.coreIndices.count)")
                        .dsFont(.xs)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                        .frame(height: CGFloat(cluster.coreIndices.count) * (rowHeight + Self.gap), alignment: .center)
                }
            }
            .fixedSize()

            ZStack {
                ForEach(levels, id: \.self) { level in
                    ChartPath { Self.cells(level: level, rows: rows, recent: recent, columns: columns, rowHeight: rowHeight, in: $0) }
                        .fill(Self.color(level: level))
                }
            }
            .frame(height: height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("核心热力图"))
    }

    static func color(_ value: Double?) -> Color {
        color(level: level(value))
    }

    nonisolated private static func level(_ value: Double?) -> Int {
        guard let value else { return emptyLevel }
        if value >= warnThreshold { return warnLevel }
        return Int((min(1, max(0, value)) * Double(steps)).rounded())
    }

    private static func color(level: Int) -> Color {
        switch level {
        case emptyLevel: DS.Palette.track
        case warnLevel: DS.Palette.warning
        default: DS.Palette.data.opacity(0.08 + 0.92 * Double(level) / Double(steps))
        }
    }

    /// 这次要画的所有深浅档
    nonisolated private static func levels(rows: [[Int]], recent: [[Double]], columns: Int) -> [Int] {
        let offset = columns - recent.count
        var levels = Set<Int>()
        for core in rows.joined() {
            for column in 0..<columns {
                levels.insert(level(column >= offset ? recent[column - offset][safe: core] : nil))
            }
            levels.insert(level(recent.last?[safe: core]))
        }
        return levels.sorted()
    }

    /// 某一档深浅的全部格子（含右侧此刻的粗条）合成一条路径
    nonisolated private static func cells(level target: Int, rows: [[Int]], recent: [[Double]], columns: Int, rowHeight: CGFloat,
                              in size: CGSize) -> Path {
        let gridWidth = size.width - nowWidth - nowGap
        let cellWidth = (gridWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let offset = columns - recent.count
        let latest = recent.last
        var path = Path()
        var y: CGFloat = 0
        for group in rows {
            for core in group {
                for column in 0..<columns {
                    let value = column >= offset ? recent[column - offset][safe: core] : nil
                    guard level(value) == target else { continue }
                    path.addRect(CGRect(x: CGFloat(column) * (cellWidth + gap), y: y, width: cellWidth, height: rowHeight))
                }
                if level(latest?[safe: core]) == target {
                    let now = CGRect(x: size.width - nowWidth, y: y, width: nowWidth, height: rowHeight)
                    path.addPath(Path(roundedRect: now, cornerRadius: DS.Radius.sm / 2, style: .continuous))
                }
                y += rowHeight + gap
            }
            y += groupGap
        }
        return path
    }
}

/// 热力图图例：低 → 高
struct HeatLegend: View {
    var body: some View {
        HStack(spacing: DS.Space.s1) {
            Text(tr("闲")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            ForEach([0.05, 0.3, 0.55, 0.8, 0.9], id: \.self) { value in
                RoundedRectangle(cornerRadius: DS.Radius.sm / 2, style: .continuous)
                    .fill(CoreHeatmap.color(value))
                    .frame(width: DS.Space.s2, height: DS.Space.s2)
            }
            Text(tr("忙")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
        }
    }
}

/// 水位条下面的图例：两列，每项是色块、名称与数值；内存水位与磁盘组成共用
struct WaterlineLegend: View {
    struct Item: Identifiable {
        let label: String
        let value: String
        let color: Color
        var help: String?

        var id: String { label }
    }

    let items: [Item]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s3), GridItem(.flexible())], spacing: DS.Space.s2) {
            ForEach(items) { item in
                HStack(spacing: DS.Space.s1) {
                    RoundedRectangle(cornerRadius: DS.Radius.bar(DS.Size.barHeight), style: .continuous).fill(item.color)
                        .frame(width: DS.Size.barHeight, height: DS.Size.barHeight)
                    Text(verbatim: item.label).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: DS.Space.s1)
                    UnitText(text: item.value, size: .xs).fixedSize()
                }
                .help(optional: item.help)
            }
        }
    }
}

/// 横向水位条：各段按大小依次排开，段与段之间留 1pt 缝
struct WaterlineBar: View {
    let segments: [(value: Double, color: Color)]
    let total: Double
    var height: CGFloat = DS.Space.s4 + DS.Space.s1

    var body: some View {
        let values = segments.map(\.value), total = total
        ZStack {
            Rectangle().fill(DS.Palette.track)
            ForEach(segments.indices, id: \.self) { index in
                ChartPath { Self.segment(index, values: values, total: total, in: $0) }
                    .fill(segments[index].color)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.bar(height), style: .continuous))
        .accessibilityHidden(true)
    }

    /// 第 `index` 段：排在前面各段之后，右侧让出 1pt 缝
    nonisolated private static func segment(_ index: Int, values: [Double], total: Double, in size: CGSize) -> Path {
        guard values[index] > 0 else { return Path() }
        let width = { (value: Double) in size.width * CGFloat(value / max(total, 1)) }
        let x = values[..<index].filter { $0 > 0 }.reduce(CGFloat(0)) { $0 + width($1) }
        return Path(CGRect(x: x, y: 0, width: max(0, width(values[index]) - DS.Size.stroke), height: size.height))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// 上下镜像的流量图：上半部分下载（读取）、下半部分上传（写入），与标题里“先下载、后上传”的顺序一致。
/// 两半用同一个比例尺（两者里更大的峰值），线的高低能直接比较
struct MirroredRateChart: View {
    let upload: [Double]
    let download: [Double]
    var capacity: Int = MetricsStore.historyCapacity
    var height: CGFloat = DS.Size.chartHeight

    /// 峰值太小时按 64 KB/s 缩放，避免空闲时的噪声被放大成满格
    nonisolated static let floor = 64.0 * 1024

    nonisolated private static let lineStyle = StrokeStyle(lineWidth: DS.Size.chartLine, lineJoin: .round)

    var body: some View {
        let peak = max(upload.max() ?? 0, download.max() ?? 0, Self.floor)
        ZStack {
            layers(download, peak: peak, color: Color(nsColor: DS.NetworkPalette.download), above: true)
            layers(upload, peak: peak, color: Color(nsColor: DS.NetworkPalette.upload), above: false)
            ChartPath { Path(CGRect(x: 0, y: $0.height / 2 - DS.Size.stroke / 2, width: $0.width, height: DS.Size.stroke)) }
                .fill(DS.Palette.border)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func layers(_ values: [Double], peak: Double, color: Color, above: Bool) -> some View {
        let capacity = capacity
        ChartPath { Self.paths(values, peak: peak, capacity: capacity, above: above, in: $0)?.area ?? Path() }
            .fill(color.opacity(0.14))
        ChartPath { Self.paths(values, peak: peak, capacity: capacity, above: above, in: $0)?.line ?? Path() }
            .stroke(color, style: Self.lineStyle)
    }

    /// 一半高度里的折线与它到中线的面积；下半部分向下翻转
    nonisolated private static func paths(_ values: [Double], peak: Double, capacity: Int, above: Bool,
                                          in size: CGSize) -> (line: Path, area: Path)? {
        let middle = size.height / 2
        guard var line = LineHistoryChart.path(values: values, capacity: capacity, maxValue: peak,
                                               in: CGSize(width: size.width, height: middle)) else { return nil }
        if !above {
            line = line.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: middle * 2))
        }
        var area = line
        area.addLine(to: CGPoint(x: size.width, y: middle))
        area.addLine(to: CGPoint(x: line.boundingRect.minX, y: middle))
        area.closeSubpath()
        return (line, area)
    }
}

/// 连接探测格子：一格一次探测，从左上到右下按时间排，最新的在最后一格。
/// 只表示通不通：通了是绿色，超时或不可达是红色，还没探测到的是灰色；
/// 探路由器时，路由器有回应但外网不通是橙色
struct ProbeGrid: View {
    let samples: [ProbeSample]
    var columns = 20
    var rows = 3

    private enum Kind: Sendable { case pending, reachable, routerOnly, failed }

    var body: some View {
        let capacity = columns * rows
        let results = samples.suffix(capacity).map { sample -> Kind in
            switch sample.state {
            case .reachable: .reachable
            case .routerOnly: .routerOnly
            case .failed: .failed
            }
        }
        let columns = columns, rows = rows
        ZStack {
            ChartPath { Self.cells(.pending, results: results, columns: columns, rows: rows, in: $0) }.fill(DS.Palette.track)
            ChartPath { Self.cells(.reachable, results: results, columns: columns, rows: rows, in: $0) }.fill(DS.Palette.success)
            ChartPath { Self.cells(.routerOnly, results: results, columns: columns, rows: rows, in: $0) }.fill(DS.Palette.warning)
            ChartPath { Self.cells(.failed, results: results, columns: columns, rows: rows, in: $0) }.fill(DS.Palette.error)
        }
        // 格子保持接近正方形，宽度随容器变化
        .aspectRatio(CGFloat(columns) / CGFloat(rows), contentMode: .fit)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement()
        .accessibilityLabel(tr("连接探测历史"))
    }

    nonisolated private static func cells(_ kind: Kind, results: [Kind], columns: Int, rows: Int, in size: CGSize) -> Path {
        let capacity = columns * rows
        let gap = DS.Space.s1 / 2
        let cellWidth = (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let cellHeight = (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        let offset = capacity - results.count
        var path = Path()
        for index in 0..<capacity {
            let current: Kind = index < offset ? .pending : results[index - offset]
            guard current == kind else { continue }
            let rect = CGRect(x: CGFloat(index % columns) * (cellWidth + gap),
                              y: CGFloat(index / columns) * (cellHeight + gap),
                              width: cellWidth, height: cellHeight)
            path.addPath(Path(roundedRect: rect, cornerRadius: DS.Radius.sm / 2, style: .continuous))
        }
        return path
    }
}

// MARK: - 评分色带

/// 0–100 分的六段色带：F、D、C、B、A、A+ 各占自己的分数区间，段内写等级，下方标刻度，
/// 得分处有一个带当前等级的小标记
struct ScoreBand: View {
    let score: Int
    var height: CGFloat = DS.Size.segmentHeight

    private static let markerHeight: CGFloat = DS.Size.iconStandalone + DS.Space.s1
    private static let tickHeight: CGFloat = DS.Space.s3

    var body: some View {
        let clamped = min(100, max(0, score))
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                VStack(spacing: DS.Space.s1 / 2) {
                    colorBands(width: width)
                    tickLabels(width: width)
                }
                .padding(.top, Self.markerHeight)
                scoreMarker(width: width, score: clamped)
            }
        }
        .frame(height: height + Self.markerHeight + Self.tickHeight + DS.Space.s1 / 2)
        .accessibilityLabel(tr("纯净度 \(clamped) 分"))
    }

    private func colorBands(width: CGFloat) -> some View {
        let bands = DS.Grade.bands
        return HStack(spacing: 1) {
            ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                let lower = index == 0 ? 0 : bands[index - 1].upper
                let segmentWidth = width * CGFloat(band.upper - lower) / 100
                ZStack {
                    Rectangle().fill(band.color)
                    if segmentWidth >= DS.Space.s6 {
                        Text(verbatim: band.grade)
                            .dsFont(.xs, weight: .semibold)
                            .foregroundStyle(DS.Palette.onPrimary)
                    }
                }
                .frame(width: max(0, segmentWidth - (index == bands.count - 1 ? 0 : 1)))
            }
        }
        .frame(height: height)
    }

    private func tickLabels(width: CGFloat) -> some View {
        // A 与 A+ 的分界太密，刻度上不标 95；弹窗那么窄时 85 也挤不下
        let ticks: [Int] = [0] + DS.Grade.bands.map(\.upper).filter {
            $0 != 95 && ($0 != 85 || width >= DS.Size.panelWidth / 2)
        }
        return ZStack(alignment: .topLeading) {
            ForEach(ticks, id: \.self) { tick in
                Text(verbatim: "\(tick)")
                    .dsFont(.xs)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .monospacedDigit()
                    .fixedSize()
                    .alignmentGuide(.leading) { dimensions in
                        // 0 靠左、100 靠右，其余居中对齐刻度
                        if tick == 0 { return 0 }
                        if tick == 100 { return dimensions.width - width }
                        return dimensions.width / 2 - width * CGFloat(tick) / 100
                    }
            }
        }
        .frame(width: width, height: Self.tickHeight, alignment: .topLeading)
    }

    /// 得分标记：气泡里写等级，尖角指向色带
    private func scoreMarker(width: CGFloat, score: Int) -> some View {
        let color = DS.Grade.color(for: score)
        let grade = DS.Grade.bands.first { score < $0.upper }?.grade ?? "A+"
        return VStack(spacing: 0) {
            Text(verbatim: grade)
                .dsFont(.xs, weight: .semibold)
                .foregroundStyle(DS.Palette.onPrimary)
                .padding(.horizontal, DS.Space.s1)
                .frame(height: DS.Size.iconInline)
                .background(color, in: BadgeShape())
            Triangle().fill(color).frame(width: DS.Space.s2, height: DS.Space.s1)
        }
        .fixedSize()
        .alignmentGuide(.leading) { dimensions in dimensions.width / 2 - width * CGFloat(score) / 100 }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
