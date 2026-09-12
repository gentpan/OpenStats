import AppKit
import Metrics

/// 菜单栏图标自绘：每次刷新只生成一张小图，避免在菜单栏里重建 SwiftUI 视图
@MainActor
enum MenuBarRenderer {
    /// 菜单栏只有 22pt 高，字号与基线对齐 Stats 的迷你样式：标签 7pt 细体、数值 12pt 常规、网速两行 9pt 细体
    private enum Metrics {
        @MainActor static let labelFont = NSFont.systemFont(ofSize: 7, weight: .light)
        @MainActor static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        @MainActor static let networkFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .light)
        static let upperBaseline: CGFloat = 12       // 上行基线（距底部）
        static let lowerBaseline: CGFloat = 1        // 下行基线
        static let symbolSize: CGFloat = 11
        static let itemGap = DS.Space.s3
        static let innerGap = DS.Space.s1
        static let barCount = 10
        static let barWidth: CGFloat = 2
        static let barGap: CGFloat = 1
        static let chartHeight: CGFloat = 16
        static let smallChartHeight: CGFloat = 9
        static let gaugeDiameter: CGFloat = 14
        static let ringWidth: CGFloat = 2.5
        static let networkDot: CGFloat = 6
        static let trackAlpha: CGFloat = 0.25
        static let highLoad = 0.85
    }

    private struct Segment {
        let width: CGFloat
        let draw: (NSRect) -> Void
    }

    static func image(for model: AppModel) -> NSImage {
        let settings = model.settings
        let height = NSStatusBar.system.thickness

        var segments: [Segment] = []
        if model.keepAwake.isActive {
            segments.append(symbolSegment("cup.and.saucer.fill"))
        }
        var usesColor = false
        for item in settings.orderedMenuBarItems {
            let (segment, colored) = self.segment(for: item, model: model)
            segments.append(segment)
            usesColor = usesColor || colored
        }
        if segments.isEmpty {
            segments.append(symbolSegment("waveform.path.ecg"))
        }

        let totalWidth = segments.reduce(0) { $0 + $1.width } + CGFloat(segments.count - 1) * Metrics.itemGap
        let image = NSImage(size: NSSize(width: ceil(totalWidth), height: height), flipped: false) { rect in
            var x: CGFloat = 0
            for segment in segments {
                segment.draw(NSRect(x: x, y: 0, width: segment.width, height: rect.height))
                x += segment.width + Metrics.itemGap
            }
            return true
        }
        // 模板图自动适配浅色 / 深色菜单栏；含彩色元素时保留真实颜色，文字用 labelColor 跟随外观
        image.isTemplate = !usesColor
        image.accessibilityDescription = accessibilityText(for: model)
        return image
    }

    /// 设置页预览用：按指定的浅色 / 深色菜单栏外观绘制
    static func preview(_ image: NSImage, dark: Bool) -> NSImage {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        return NSImage(size: image.size, flipped: false) { rect in
            let draw = {
                image.draw(in: rect)
                if image.isTemplate {
                    (dark ? NSColor.white : NSColor.black).set()
                    rect.fill(using: .sourceAtop)
                }
            }
            if let appearance { appearance.performAsCurrentDrawingAppearance(draw) } else { draw() }
            return true
        }
    }

    // MARK: 各指标

    private static func segment(for item: MenuBarItem, model: AppModel) -> (Segment, colored: Bool) {
        let store = model.store
        let settings = model.settings
        switch item {
        case .cpu, .gpu, .memory:
            let value: Double?
            let history: [Double]
            switch item {
            case .cpu: (value, history) = (store.cpu?.total, store.cpuTotal.elements)
            case .gpu: (value, history) = (store.gpu?.utilization, store.gpuHistory.elements)
            default: (value, history) = (store.memory?.usedFraction, store.memoryHistory.elements)
            }
            let alert = settings.colorizeHighLoad && (value ?? 0) >= Metrics.highLoad
            return (gaugeSegment(label: item.menuBarLabel, value: value, history: history,
                                 style: settings.gaugeStyle(for: item), alert: alert), alert)
        case .network:
            return (networkSegment(store.network), true)
        case .temperature:
            let text = store.sensors?.temperature(.cpu).map { reading -> String in
                let celsius = reading.maximum
                let degrees = settings.useFahrenheit ? celsius * 9 / 5 + 32 : celsius
                return "\(Int(degrees.rounded()))°"
            } ?? "—"
            return (stackedSegment(label: item.menuBarLabel, value: text, sample: "100°"), false)
        case .fan:
            let text = store.fastestFan.map { "\(Int($0.current))" } ?? "—"
            return (stackedSegment(label: item.menuBarLabel, value: text, sample: "8888"), false)
        }
    }

    private static func gaugeSegment(label: String, value: Double?, history: [Double], style: GaugeStyle, alert: Bool) -> Segment {
        let text = value.map { Format.percent($0) } ?? "—"
        let fraction = value ?? 0
        let stacked = stackedSegment(label: label, value: text, sample: "100%", alert: alert)
        switch style {
        case .value:
            return stacked
        case .bars:
            return barsWithLabel(label: label, history: history, alert: alert)
        case .barsAndValue:
            return combine([barsSegment(history: history, height: Metrics.chartHeight, alert: alert), stacked])
        case .ring:
            return combine([ringSegment(fraction: fraction, alert: alert), stacked])
        case .pie:
            return combine([pieSegment(fraction: fraction, alert: alert), stacked])
        }
    }

    // MARK: 基础片段

    private static func foreground(_ alert: Bool) -> NSColor {
        alert ? .systemRed : .labelColor
    }

    /// 颜色必须保持动态（labelColor），在绘制时才按菜单栏外观解析；
    /// 提前调用 withAlphaComponent 会按应用外观固定颜色，深色菜单栏上就会发黑
    private static var labelAttributes: [NSAttributedString.Key: Any] {
        [.font: Metrics.labelFont, .foregroundColor: NSColor.labelColor]
    }

    /// 上方小标签、下方数值，右对齐
    private static func stackedSegment(label: String, value: String, sample: String, alert: Bool = false) -> Segment {
        let labelAttributes = labelAttributes
        let valueAttributes: [NSAttributedString.Key: Any] = [.font: Metrics.valueFont, .foregroundColor: foreground(alert)]
        let width = ceil([
            (label as NSString).size(withAttributes: labelAttributes).width,
            (value as NSString).size(withAttributes: valueAttributes).width,
            (sample as NSString).size(withAttributes: valueAttributes).width,
        ].max() ?? 0)

        return Segment(width: width) { rect in
            drawText(label, attributes: labelAttributes, rightEdge: rect.maxX, baseline: rect.minY + Metrics.upperBaseline)
            drawText(value, attributes: valueAttributes, rightEdge: rect.maxX, baseline: rect.minY + Metrics.lowerBaseline)
        }
    }

    /// 以基线定位（与 Stats 相同的 draw(with:) 方式），右对齐
    private static func drawText(_ text: String, attributes: [NSAttributedString.Key: Any],
                                 rightEdge: CGFloat, baseline: CGFloat) {
        let string = NSAttributedString(string: text, attributes: attributes)
        let width = string.size().width
        string.draw(with: NSRect(x: rightEdge - width, y: baseline, width: width, height: 0))
    }

    private static func barsSegment(history: [Double], height: CGFloat, alert: Bool) -> Segment {
        let recent = Array(history.suffix(Metrics.barCount))
        let padded = Array(repeating: 0, count: Metrics.barCount - recent.count) + recent
        let width = CGFloat(Metrics.barCount) * Metrics.barWidth + CGFloat(Metrics.barCount - 1) * Metrics.barGap
        return Segment(width: width) { rect in
            let baseline = rect.midY - height / 2
            for (index, value) in padded.enumerated() {
                let x = rect.minX + CGFloat(index) * (Metrics.barWidth + Metrics.barGap)
                NSColor.labelColor.withAlphaComponent(Metrics.trackAlpha).setFill()
                NSBezierPath(rect: NSRect(x: x, y: baseline, width: Metrics.barWidth, height: height)).fill()
                foreground(alert && value >= Metrics.highLoad).setFill()
                NSBezierPath(rect: NSRect(x: x, y: baseline, width: Metrics.barWidth,
                                          height: height * min(1, max(0, value)))).fill()
            }
        }
    }

    /// 柱状图模式：上方小标签，下方矮柱
    private static func barsWithLabel(label: String, history: [Double], alert: Bool) -> Segment {
        let labelAttributes = labelAttributes
        let bars = barsSegment(history: history, height: Metrics.smallChartHeight, alert: alert)
        let width = max(bars.width, ceil((label as NSString).size(withAttributes: labelAttributes).width))
        return Segment(width: width) { rect in
            drawText(label, attributes: labelAttributes, rightEdge: rect.maxX, baseline: rect.minY + Metrics.upperBaseline)
            // 矮柱放在标签下方的区域内
            let area = NSRect(x: rect.maxX - bars.width, y: rect.minY, width: bars.width,
                              height: Metrics.upperBaseline - 1)
            bars.draw(area)
        }
    }

    private static func ringSegment(fraction: Double, alert: Bool) -> Segment {
        Segment(width: Metrics.gaugeDiameter) { rect in
            let inset = Metrics.ringWidth / 2
            let circle = NSRect(x: rect.minX + inset, y: rect.midY - Metrics.gaugeDiameter / 2 + inset,
                                width: Metrics.gaugeDiameter - Metrics.ringWidth,
                                height: Metrics.gaugeDiameter - Metrics.ringWidth)
            let track = NSBezierPath(ovalIn: circle)
            track.lineWidth = Metrics.ringWidth
            NSColor.labelColor.withAlphaComponent(Metrics.trackAlpha).setStroke()
            track.stroke()

            let clamped = min(1, max(0, fraction))
            guard clamped > 0 else { return }
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: circle.midX, y: circle.midY), radius: circle.width / 2,
                          startAngle: 90, endAngle: 90 - 360 * clamped, clockwise: true)
            arc.lineWidth = Metrics.ringWidth
            arc.lineCapStyle = .round
            foreground(alert).setStroke()
            arc.stroke()
        }
    }

    private static func pieSegment(fraction: Double, alert: Bool) -> Segment {
        Segment(width: Metrics.gaugeDiameter) { rect in
            let circle = NSRect(x: rect.minX, y: rect.midY - Metrics.gaugeDiameter / 2,
                                width: Metrics.gaugeDiameter, height: Metrics.gaugeDiameter)
            NSColor.labelColor.withAlphaComponent(Metrics.trackAlpha).setFill()
            NSBezierPath(ovalIn: circle).fill()

            let clamped = min(1, max(0, fraction))
            guard clamped > 0 else { return }
            let center = NSPoint(x: circle.midX, y: circle.midY)
            let wedge = NSBezierPath()
            wedge.move(to: center)
            wedge.appendArc(withCenter: center, radius: circle.width / 2,
                            startAngle: 90, endAngle: 90 - 360 * clamped, clockwise: true)
            wedge.close()
            foreground(alert).setFill()
            wedge.fill()
        }
    }

    private static func symbolSegment(_ name: String) -> Segment {
        let configuration = NSImage.SymbolConfiguration(pointSize: Metrics.symbolSize, weight: .medium)
            .applying(.init(paletteColors: [.labelColor]))
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        let size = symbol?.size ?? NSSize(width: Metrics.symbolSize, height: Metrics.symbolSize)
        return Segment(width: ceil(size.width)) { rect in
            symbol?.draw(in: NSRect(x: rect.minX, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        }
    }

    /// 两行：上传（绿点）在上，下载（蓝点）在下，数值右对齐
    private static func networkSegment(_ rate: NetworkRate?) -> Segment {
        let attributes: [NSAttributedString.Key: Any] = [.font: Metrics.networkFont, .foregroundColor: NSColor.labelColor]
        let rows: [(String, NSColor)] = [
            (rate.map { Format.menuBarRate($0.uploadBytesPerSecond) } ?? "— KB/s", DS.NetworkPalette.upload),
            (rate.map { Format.menuBarRate($0.downloadBytesPerSecond) } ?? "— KB/s", DS.NetworkPalette.download),
        ]
        let sampleWidth = ("999 KB/s" as NSString).size(withAttributes: attributes).width
        let textWidth = ceil(rows.map { ($0.0 as NSString).size(withAttributes: attributes).width }.reduce(sampleWidth, max))
        let width = Metrics.networkDot + Metrics.innerGap + textWidth

        return Segment(width: width) { rect in
            let capHeight = Metrics.networkFont.capHeight
            for (index, row) in rows.enumerated() {
                let baseline = rect.minY + (index == 0 ? Metrics.upperBaseline : Metrics.lowerBaseline + 1)
                row.1.setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.minX, y: baseline + capHeight / 2 - Metrics.networkDot / 2,
                                            width: Metrics.networkDot, height: Metrics.networkDot)).fill()
                drawText(row.0, attributes: attributes, rightEdge: rect.maxX, baseline: baseline)
            }
        }
    }

    private static func combine(_ parts: [Segment], gap: CGFloat = Metrics.innerGap) -> Segment {
        let width = parts.reduce(0) { $0 + $1.width } + CGFloat(max(0, parts.count - 1)) * gap
        return Segment(width: width) { rect in
            var x = rect.minX
            for part in parts {
                part.draw(NSRect(x: x, y: rect.minY, width: part.width, height: rect.height))
                x += part.width + gap
            }
        }
    }

    private static func accessibilityText(for model: AppModel) -> String {
        let cpu = model.store.cpu.map { "CPU \(Format.percent($0.total))" } ?? "CPU"
        return "OpenStats，\(cpu)"
    }
}
