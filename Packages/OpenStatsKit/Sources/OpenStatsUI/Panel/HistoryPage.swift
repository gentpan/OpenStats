import Localization
import Metrics
import SwiftUI

/// 历史：回看最近 1 小时、24 小时、7 天的 CPU、内存、网络、GPU、温度与功耗。鼠标移到图上查看某一时刻
struct HistoryPage: View {
    @Environment(AppModel.self) private var model
    @State private var hover = HistoryHover()
    @State private var confirmingClear = false

    var body: some View {
        @Bindable var settings = model.settings
        let history = model.history
        let points = history.points
        let end = Date()
        let start = history.rangeStart

        PageScroll {
            HStack(spacing: DS.Space.s3) {
                SegmentedControl(selection: Binding(get: { history.range }, set: { history.load($0) }),
                                 options: HistoryRecorder.Range.allCases.map { ($0, $0.title) })
                    .frame(width: DS.Size.sidebarWidth + DS.Space.s16)
                Spacer()
                HoverDateText(hover: hover, fallback: points.isEmpty ? "" : tr("每点 \(bucketTitle(history.range))"))
            }

            if !settings.historyEnabled {
                InfoBanner(icon: "pause.circle", text: tr("历史记录已关闭，下面是关闭前记录的数据。"), tone: .warning) {
                    Button(tr("开启")) { settings.historyEnabled = true }.buttonStyle(DSButtonStyle(kind: .primary))
                }
            }

            if points.isEmpty {
                Card {
                    Text(history.isQuerying ? tr("正在读取…") : tr("这段时间还没有记录。OpenStats 运行时每分钟记录一次，睡眠与锁屏期间不记录。"))
                        .dsFont(.sm)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            } else {
                HistoryChartCard(icon: "cpu", title: "CPU", points: points, start: start, end: end, hover: hover,
                                 series: [.init(label: tr("平均"), color: DS.Palette.data, value: \.cpu),
                                          .init(label: tr("峰值"), color: DS.Palette.data.opacity(0.35), value: \.cpuMax, filled: false)],
                                 maxValue: 1, format: { Format.percent($0) })
                HistoryChartCard(icon: "memorychip", title: tr("内存"), points: points, start: start, end: end, hover: hover,
                                 series: [.init(label: tr("已用"), color: DS.Palette.data, value: \.memory)],
                                 maxValue: 1, format: { Format.percent($0) },
                                 note: criticalNote(points))
                HistoryChartCard(icon: "network", title: tr("网络"), points: points, start: start, end: end, hover: hover,
                                 series: [.init(label: tr("下载"), color: Color(nsColor: DS.NetworkPalette.download), value: \.download),
                                          .init(label: tr("上传"), color: Color(nsColor: DS.NetworkPalette.upload), value: \.upload, filled: false)],
                                 maxValue: nil, format: { Format.menuBarRate($0) })
                HistoryChartCard(icon: "square.3.layers.3d", title: "GPU", points: points, start: start, end: end, hover: hover,
                                 series: [.init(label: tr("占用"), color: DS.Palette.data, value: \.gpu)],
                                 maxValue: 1, format: { Format.percent($0) },
                                 emptyNote: tr("只在菜单栏显示 GPU 或打开 GPU 相关页面时记录"))
                HistoryChartCard(icon: "thermometer.medium", title: tr("CPU 温度"), points: points, start: start, end: end, hover: hover,
                                 series: [.init(label: tr("最高"), color: DS.Palette.warning, value: \.temperature)],
                                 maxValue: nil, format: { Format.temperature($0, fahrenheit: settings.useFahrenheit) },
                                 emptyNote: tr("只在菜单栏显示温度、开启过热通知或打开温度页面时记录"))
                HistoryChartCard(icon: "bolt", title: tr("整机功耗"), points: points, start: start, end: end, hover: hover,
                                 series: [.init(label: tr("平均"), color: DS.Palette.warning, value: \.power)],
                                 maxValue: nil, format: { Format.watts($0) },
                                 emptyNote: tr("只在打开温度与风扇页面时记录"))
                if model.store.battery != nil {
                    HistoryChartCard(icon: "battery.75", title: tr("电池电量"), points: points, start: start, end: end, hover: hover,
                                     series: [.init(label: tr("电量"), color: DS.Palette.success, value: \.battery)],
                                     maxValue: 1, format: { Format.percent($0) },
                                     emptyNote: tr("只在菜单栏显示电池或打开电池页面时记录"))
                }
            }

            SettingsGroup(caption: tr("历史记录")) {
                GroupRow(showsDivider: false) {
                    SettingRow(title: tr("记录历史数据"), subtitle: tr("每分钟把主要指标的平均值与峰值写入本机数据库，保留 7 天，不上传")) {
                        DSToggle(isOn: $settings.historyEnabled, label: tr("记录历史数据"))
                    }
                }
                GroupRow {
                    SettingRow(title: tr("清除历史"), subtitle: tr("共 \(history.recordCount.formatted()) 条记录")) {
                        Button(tr("清除…")) { confirmingClear = true }
                            .buttonStyle(DSButtonStyle(kind: .secondary))
                            .disabled(history.recordCount == 0)
                    }
                }
            }
        }
        .task {
            // 页面打开期间每分钟补上新记录的一点
            history.load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if hover.date == nil { history.load() }
            }
        }
        .confirmationDialog(tr("清除全部历史记录？"), isPresented: $confirmingClear, titleVisibility: .visible) {
            Button(tr("清除"), role: .destructive) { history.clear() }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(tr("已记录的数据会从本机删除，无法恢复。"))
        }
    }

    private func bucketTitle(_ range: HistoryRecorder.Range) -> String {
        range.bucket >= 60 * 60 ? tr("\(range.bucket / 3600) 小时") : tr("\(range.bucket / 60) 分钟")
    }

    private func criticalNote(_ points: [HistoryPoint]) -> String? {
        let critical = points.filter { ($0.pressure ?? 0) >= MemoryPressure.critical.rawValue }.count
        return critical > 0 ? tr("内存压力严重的时段：\(critical) 个（图上红色标记）") : nil
    }
}

/// 鼠标在历史图上指着的时刻。单独放在一个可观察对象里，只有光标、顶部时间与各卡片的读数读它，
/// 移动鼠标时整页和曲线都不重算
@MainActor @Observable
final class HistoryHover {
    var date: Date?
}

/// 顶部右侧：指着某一时刻时显示它，否则显示每点代表多长时间
private struct HoverDateText: View {
    let hover: HistoryHover
    let fallback: String

    var body: some View {
        Text(verbatim: hover.date.map { $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: L10n.locale)) } ?? fallback)
            .dsFont(.xs)
            .foregroundStyle(DS.Palette.textSecondary)
            .monospacedDigit()
    }
}

private struct HistoryChartCard: View {
    struct Series {
        let label: String
        let color: Color
        let value: KeyPath<HistoryPoint, Double?>
        var filled = true
    }

    let icon: String
    let title: String
    let points: [HistoryPoint]
    let start: Date
    let end: Date
    let hover: HistoryHover
    let series: [Series]
    let maxValue: Double?
    let format: (Double) -> String
    var note: String?
    var emptyNote: String?

    var body: some View {
        let hasData = series.contains { item in points.contains { $0[keyPath: item.value] != nil } }

        Card {
            CardHeader(icon: icon, title: title) {
                HistoryCardReading(points: points, series: series, format: format, summary: summary, hover: hover)
            }
            if hasData {
                TimeSeriesChart(points: points, start: start, end: end, series: series, maxValue: maxValue, hover: hover)
                    .frame(height: DS.Size.chartHeight * 2)
                HStack {
                    Text(verbatim: Self.moment(start))
                    Spacer()
                    Text(verbatim: Self.moment(start.addingTimeInterval(end.timeIntervalSince(start) / 2)))
                    Spacer()
                    Text(tr("现在"))
                }
                .dsFont(.xs)
                .foregroundStyle(DS.Palette.textTertiary)
                .monospacedDigit()
                if let note {
                    Text(note).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
                }
            } else {
                Text(emptyNote ?? tr("这段时间没有记录")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            }
        }
    }

    /// 没指着图时显示的平均与峰值
    private var summary: String? {
        let primary = series[0]
        let values = points.compactMap { $0[keyPath: primary.value] }
        guard !values.isEmpty else { return nil }
        let peakPoint = points.max { ($0[keyPath: primary.value] ?? -1) < ($1[keyPath: primary.value] ?? -1) }
        return tr("平均 \(format(values.reduce(0, +) / Double(values.count))) · 峰值 \(format(values.max() ?? 0))\(peakPoint.map { tr("（\(Self.moment($0.date))）") } ?? "")")
    }

    /// 同一天只显示时间，跨天带上日期
    static func moment(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: L10n.locale))
            : date.formatted(.dateTime.locale(L10n.locale).month(.abbreviated).day().hour().minute())
    }
}

/// 卡片右上角：指着某一时刻时显示那一点的各项读数，否则显示平均与峰值
private struct HistoryCardReading: View {
    let points: [HistoryPoint]
    let series: [HistoryChartCard.Series]
    let format: (Double) -> String
    let summary: String?
    let hover: HistoryHover

    var body: some View {
        if let date = hover.date,
           let point = points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) {
            HStack(spacing: DS.Space.s3) {
                ForEach(series.indices, id: \.self) { index in
                    legend(series[index], value: point[keyPath: series[index].value])
                }
            }
        } else if let summary {
            Text(verbatim: summary)
                .dsFont(.xs)
                .foregroundStyle(DS.Palette.textTertiary)
                .monospacedDigit()
        }
    }

    private func legend(_ item: HistoryChartCard.Series, value: Double?) -> some View {
        HStack(spacing: DS.Space.s1) {
            Circle().fill(item.color).frame(width: DS.Space.s2, height: DS.Space.s2)
            Text(verbatim: "\(item.label) \(value.map(format) ?? "—")")
                .dsFont(.xs, weight: .medium)
                .foregroundStyle(DS.Palette.textPrimary)
                .monospacedDigit()
        }
    }
}

/// 按时间定位的折线图：相邻两点间隔超过 3 个时间桶视为没有记录（睡眠、关机），线条断开。
/// 曲线用形状画（Canvas 一重绘就占住约 190 MB 图形内存），坐标先归一化到 0…1，与尺寸无关；
/// 鼠标光标是单独的一层，移动鼠标时曲线不重画
private struct TimeSeriesChart: View {
    let points: [HistoryPoint]
    let start: Date
    let end: Date
    let series: [HistoryChartCard.Series]
    let maxValue: Double?
    let hover: HistoryHover

    /// 一条曲线的若干段，点的坐标都在 0…1 之间（y 向下）
    private struct Layer {
        let color: Color
        let filled: Bool
        let segments: [[CGPoint]]
    }

    var body: some View {
        let span = max(1, end.timeIntervalSince(start))
        let bucket = points.count > 1 ? Self.medianGap(points) : 60
        let peak = maxValue ?? max(series.flatMap { item in points.compactMap { $0[keyPath: item.value] } }.max() ?? 0, 1) * 1.15
        let layers = series.reversed().map { item in
            Layer(color: item.color, filled: item.filled,
                  segments: Self.segments(points, value: item.value, start: start, span: span, bucket: bucket, peak: peak))
        }
        // 内存压力严重的时段：起点与宽度占整段时间的比例
        let showsPressure = series.contains { $0.value == \HistoryPoint.memory }
        let pressure = showsPressure
            ? points.filter { ($0.pressure ?? 0) >= MemoryPressure.critical.rawValue }.map { CGFloat($0.date.timeIntervalSince(start) / span) }
            : []
        let pressureWidth = CGFloat(bucket / span)

        GeometryReader { proxy in
            ZStack {
                // 网格：上中下三条
                ChartPath { size in
                    var grid = Path()
                    for fraction in [0.0, 0.5, 1.0] {
                        grid.move(to: CGPoint(x: 0, y: size.height * fraction))
                        grid.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                    }
                    return grid
                }
                .stroke(DS.Palette.track, lineWidth: DS.Size.stroke)

                if !pressure.isEmpty {
                    ChartPath { size in
                        var path = Path()
                        for x in pressure {
                            path.addRect(CGRect(x: x * size.width, y: 0, width: max(DS.Size.stroke * 2, size.width * pressureWidth), height: size.height))
                        }
                        return path
                    }
                    .fill(DS.Palette.error.opacity(0.15))
                }

                ForEach(layers.indices, id: \.self) { index in
                    let layer = layers[index]
                    let segments = layer.segments
                    if layer.filled {
                        ChartPath { Self.areaPath(segments, in: $0) }.fill(layer.color.opacity(0.12))
                    }
                    ChartPath { Self.linePath(segments, in: $0) }
                        .stroke(layer.color, style: StrokeStyle(lineWidth: DS.Size.chartLine, lineJoin: .round))
                }

                HistoryCursor(hover: hover, start: start, span: span)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hover.date = start.addingTimeInterval(span * Double(max(0, min(1, location.x / max(1, proxy.size.width)))))
                case .ended:
                    hover.date = nil
                }
            }
        }
    }

    /// 相邻点的典型间隔，即时间桶大小
    private static func medianGap(_ points: [HistoryPoint]) -> TimeInterval {
        let gaps = zip(points.dropFirst(), points).map { $0.date.timeIntervalSince($1.date) }.sorted()
        return gaps.isEmpty ? 60 : gaps[gaps.count / 2]
    }

    /// 某一项的取值按时间断开成若干段，坐标归一化到 0…1
    private static func segments(_ points: [HistoryPoint], value: KeyPath<HistoryPoint, Double?>, start: Date, span: TimeInterval,
                                 bucket: TimeInterval, peak: Double) -> [[CGPoint]] {
        var segments: [[CGPoint]] = []
        var previous: Date?
        for point in points {
            guard let reading = point[keyPath: value] else { previous = nil; continue }
            let location = CGPoint(x: point.date.timeIntervalSince(start) / span, y: 1 - min(1, reading / peak))
            if let previous, point.date.timeIntervalSince(previous) <= bucket * 3, !segments.isEmpty {
                segments[segments.count - 1].append(location)
            } else {
                segments.append([location])
            }
            previous = point.date
        }
        return segments
    }

    nonisolated private static func linePath(_ segments: [[CGPoint]], in size: CGSize) -> Path {
        var path = Path()
        for segment in segments {
            let points = segment.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            path.addLines(points.count == 1 ? [points[0], CGPoint(x: points[0].x + DS.Size.stroke, y: points[0].y)] : points)
        }
        return path
    }

    nonisolated private static func areaPath(_ segments: [[CGPoint]], in size: CGSize) -> Path {
        var path = Path()
        for segment in segments {
            guard let first = segment.first, let last = segment.last else { continue }
            var piece = Path()
            piece.addLines(segment.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
            piece.addLine(to: CGPoint(x: last.x * size.width, y: size.height))
            piece.addLine(to: CGPoint(x: first.x * size.width, y: size.height))
            piece.closeSubpath()
            path.addPath(piece)
        }
        return path
    }
}

/// 鼠标指着的时刻画一条竖线；只有这一层随鼠标移动重画
private struct HistoryCursor: View {
    let hover: HistoryHover
    let start: Date
    let span: TimeInterval

    var body: some View {
        if let date = hover.date {
            GeometryReader { proxy in
                Rectangle()
                    .fill(DS.Palette.textTertiary)
                    .frame(width: DS.Size.stroke)
                    .offset(x: CGFloat(date.timeIntervalSince(start) / span) * proxy.size.width - DS.Size.stroke / 2)
            }
            .allowsHitTesting(false)
        }
    }
}
