import Metrics
import SwiftUI

/// ImageRenderer 无法渲染 ScrollView 等 AppKit 承载的控件，截图模式下改用平铺布局。
extension EnvironmentValues {
    @Entry var isSnapshot = false
    /// 在主窗口里显示指标详情：显示全部区块，图表更高
    @Entry var isDetailPage = false
}

// MARK: - 卡片

struct Card<Content: View>: View {
    var padding: CGFloat = DS.Space.s4
    var spacing: CGFloat = DS.Space.s3
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(padding)
        // 在等高行里撑满高度，背景随之延伸
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
    }
}

struct CardHeader<Trailing: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: icon)
                .font(.system(size: DS.TextSize.sm.rawValue, weight: .medium))
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(width: DS.Size.iconInline, height: DS.Size.iconInline)
            Text(title)
                .dsFont(.sm, weight: .semibold)
                .foregroundStyle(DS.Palette.textPrimary)
            Spacer(minLength: DS.Space.s2)
            trailing
        }
    }
}

extension CardHeader where Trailing == Text {
    init(icon: String, title: String, detail: String) {
        self.icon = icon
        self.title = title
        self.trailing = Text(detail).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
    }
}

struct HairlineDivider: View {
    var body: some View {
        Rectangle().fill(DS.Palette.border).frame(height: DS.Size.stroke)
    }
}

// MARK: - 图例

struct LegendItem: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: DS.Space.s1) {
            Circle().fill(color).frame(width: DS.Size.barHeight, height: DS.Size.barHeight)
            Text(label).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
            Text(value).dsFont(.xs, weight: .semibold).monospacedDigit().foregroundStyle(DS.Palette.textPrimary)
        }
        .lineLimit(1)
    }
}

// MARK: - 进度条

struct ProgressTrack: View {
    let fraction: Double
    var color: Color = DS.Palette.primary
    var height: CGFloat = DS.Size.barHeight

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Palette.track)
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(color)
                    .frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - 徽标

enum Tone {
    case neutral, primary, success, warning, error

    var color: Color {
        switch self {
        case .neutral: DS.Palette.textSecondary
        case .primary: DS.Palette.primary
        case .success: DS.Palette.success
        case .warning: DS.Palette.warning
        case .error: DS.Palette.error
        }
    }

    static func forTemperature(_ celsius: Double) -> Tone {
        celsius >= DS.Thermal.hot ? .error : celsius >= DS.Thermal.warm ? .warning : .primary
    }
}

struct StatusBadge: View {
    let text: String
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: DS.Space.s1) {
            Circle().fill(tone.color).frame(width: DS.Space.s2 - DS.Space.s1 / 2, height: DS.Space.s2 - DS.Space.s1 / 2)
            Text(text).dsFont(.xs, weight: .medium).foregroundStyle(tone.color)
        }
        .padding(.horizontal, DS.Space.s2)
        .padding(.vertical, DS.Space.s1 / 2)
        .background(tone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
        .lineLimit(1)
    }
}

// MARK: - 按钮

struct DSButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        DSButtonBody(configuration: configuration, kind: kind)
    }
}

private struct DSButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: DSButtonStyle.Kind
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .dsFont(.sm, weight: .medium)
            .foregroundStyle(foreground)
            .padding(.horizontal, DS.Space.s3)
            .frame(height: DS.Size.controlHeight)
            .background(background, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Palette.border, lineWidth: DS.Size.stroke)
                }
            }
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(DS.Motion.quick, value: hovering)
    }

    private var active: Bool { hovering || configuration.isPressed }

    private var foreground: Color {
        switch kind {
        case .primary: DS.Palette.onPrimary
        case .secondary: DS.Palette.textPrimary
        case .ghost: DS.Palette.primary
        }
    }

    private var background: Color {
        switch kind {
        case .primary: active ? DS.Palette.primaryHover : DS.Palette.primary
        case .secondary: active ? DS.Palette.surfaceHover : DS.Palette.elevated
        case .ghost: active ? DS.Palette.surfaceHover : .clear
        }
    }
}

struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: DS.TextSize.sm.rawValue, weight: .medium))
                .foregroundStyle(hovering ? DS.Palette.primary : DS.Palette.textSecondary)
                .frame(width: DS.Size.controlHeight, height: DS.Size.controlHeight)
                .background(hovering ? DS.Palette.surfaceHover : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - 侧边栏

struct SidebarButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: symbol)
                    .font(.system(size: DS.TextSize.sm.rawValue, weight: .medium))
                    .frame(width: DS.Size.iconStandalone)
                Text(title).dsFont(.sm, weight: isSelected ? .semibold : .regular)
                Spacer()
            }
            .foregroundStyle(isSelected ? DS.Palette.onPrimary : DS.Palette.textPrimary)
            .padding(.horizontal, DS.Space.s2)
            .frame(height: DS.Size.controlHeight)
            .background(background, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected { return DS.Palette.primary }
        return hovering ? DS.Palette.surfaceHover : .clear
    }
}

// MARK: - 分段控件

struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .dsFont(.sm, weight: selected ? .semibold : .regular)
                        .foregroundStyle(selected ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: DS.Size.segmentHeight)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: DS.Radius.md - DS.Space.s1)
                                    .fill(DS.Palette.elevated)
                                    .dsShadow(DS.Shadow.level1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(DS.Space.s1)
        .background(DS.Palette.track, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        .animation(DS.Motion.quick, value: selection)
    }
}

// MARK: - 开关

struct DSToggle: View {
    @Binding var isOn: Bool
    var label: String = ""

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? DS.Palette.primary : DS.Palette.neutral300)
                Circle()
                    .fill(DS.Palette.onPrimary)
                    .frame(width: DS.Size.switchKnob, height: DS.Size.switchKnob)
                    .dsShadow(DS.Shadow.level1)
                    .padding(DS.Space.s1)
            }
            .frame(width: DS.Size.switchWidth, height: DS.Size.switchHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(DS.Motion.quick, value: isOn)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "开" : "关")
    }
}

// MARK: - 复选框

struct DSCheckbox: View {
    let isOn: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(isOn ? DS.Palette.primary : Color.clear)
                .overlay {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: DS.TextSize.xs.rawValue - DS.Space.s1 / 2, weight: .bold))
                            .foregroundStyle(DS.Palette.onPrimary)
                    } else {
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .strokeBorder(DS.Palette.neutral300, lineWidth: DS.Size.chartLine)
                    }
                }
                .frame(width: DS.Size.iconInline, height: DS.Size.iconInline)
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - 单选行

struct RadioRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? DS.Palette.primary : DS.Palette.neutral300, lineWidth: DS.Size.chartLine)
                    if isSelected {
                        Circle().fill(DS.Palette.primary).frame(width: DS.Space.s2, height: DS.Space.s2)
                    }
                }
                .frame(width: DS.Size.iconInline, height: DS.Size.iconInline)
                .padding(.top, DS.Space.s1 / 2)

                VStack(alignment: .leading, spacing: DS.Space.s1 / 2) {
                    Text(title).dsFont(.sm, weight: .medium).foregroundStyle(DS.Palette.textPrimary)
                    Text(subtitle).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 设置行

struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String?
    var icon: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: DS.TextSize.base.rawValue))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .frame(width: DS.Size.iconStandalone, height: DS.Size.iconStandalone)
            }
            VStack(alignment: .leading, spacing: DS.Space.s1 / 2) {
                Text(title).dsFont(.sm, weight: .medium).foregroundStyle(DS.Palette.textPrimary)
                if let subtitle {
                    Text(subtitle).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.Space.s4)
            control
        }
    }
}

// MARK: - 提示条

struct InfoBanner<Action: View>: View {
    let icon: String
    let text: String
    var tone: Tone = .primary
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            Image(systemName: icon)
                .font(.system(size: DS.TextSize.sm.rawValue, weight: .semibold))
                .foregroundStyle(tone.color)
                .frame(width: DS.Size.iconInline)
            Text(text)
                .dsFont(.xs)
                .foregroundStyle(DS.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            action
        }
        .padding(DS.Space.s3)
        .background(tone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.md))
    }
}

extension InfoBanner where Action == EmptyView {
    init(icon: String, text: String, tone: Tone = .primary) {
        self.init(icon: icon, text: text, tone: tone) { EmptyView() }
    }
}

// MARK: - 滑块（自绘，保证截图与界面风格一致）

struct DSSlider: View {
    @Binding var value: Double           // 0...1
    var onEditingEnded: () -> Void = {}

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let knob = DS.Size.switchKnob
            let x = (width - knob) * min(1, max(0, value))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Palette.track)
                    .frame(height: DS.Space.s1 + DS.Space.s1 / 2)
                RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Palette.primary)
                    .frame(width: x + knob / 2, height: DS.Space.s1 + DS.Space.s1 / 2)
                Circle()
                    .fill(DS.Palette.elevated)
                    .overlay(Circle().strokeBorder(DS.Palette.primary, lineWidth: DS.Size.chartLine))
                    .frame(width: knob, height: knob)
                    .dsShadow(DS.Shadow.level1)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        value = min(1, max(0, (gesture.location.x - knob / 2) / max(1, width - knob)))
                    }
                    .onEnded { _ in onEditingEnded() }
            )
        }
        .frame(height: DS.Size.segmentHeight)
        .accessibilityElement()
        .accessibilityValue(Format.percent(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.1)
            case .decrement: value = max(0, value - 0.1)
            @unknown default: break
            }
            onEditingEnded()
        }
    }
}

// MARK: - 滚动容器

struct PageScroll<Content: View>: View {
    @Environment(\.isSnapshot) private var isSnapshot
    @ViewBuilder var content: Content

    var body: some View {
        let stack = VStack(alignment: .leading, spacing: DS.Space.s3) { content }
            .padding(DS.Space.s3)
        if isSnapshot {
            stack
        } else {
            // 内容放得下时不回弹，避免点击时整页轻微抖动
            ScrollView { stack.overlayScrollers() }
                .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - 徽章 / 标签

struct Chip: View {
    let text: String
    var icon: String?
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: DS.Space.s1) {
            if let icon {
                Image(systemName: icon).font(.system(size: DS.TextSize.xs.rawValue, weight: .semibold))
            }
            Text(verbatim: text).dsFont(.xs, weight: .medium).monospacedDigit()
        }
        .foregroundStyle(tone == .neutral ? DS.Palette.textSecondary : tone.color)
        .padding(.horizontal, DS.Space.s2)
        .padding(.vertical, DS.Space.s1 / 2)
        .background(tone == .neutral ? DS.Palette.track : tone.color.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: DS.Radius.sm))
        .lineLimit(1)
        .fixedSize()
    }
}

/// 可点击的小标签，用于风扇模式等快捷切换
struct ChipButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .dsFont(.xs, weight: isSelected ? .semibold : .medium)
                .foregroundStyle(isSelected ? DS.Palette.primary : DS.Palette.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: DS.Size.segmentHeight)
                .background(background, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .strokeBorder(isSelected ? DS.Palette.primary.opacity(0.4) : DS.Palette.border, lineWidth: DS.Size.stroke))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected { return DS.Palette.primary.opacity(0.12) }
        return hovering ? DS.Palette.surfaceHover : .clear
    }
}

/// 自动换行排列（徽章行）
struct FlowLayout: Layout {
    var spacing: CGFloat = DS.Space.s2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if proposedWidth > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - 指标小卡片

struct MetricTile<Chart: View, Footer: View>: View {
    let icon: String
    let title: String
    var chip: String?
    var chipTone: Tone = .neutral
    let value: String
    var unit: String?
    @ViewBuilder var chart: Chart
    @ViewBuilder var footer: Footer

    var body: some View {
        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: icon)
                    .font(.system(size: DS.TextSize.xs.rawValue, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSecondary)
                Text(title)
                    .dsFont(.xs, weight: .semibold)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s1)
                if let chip { Chip(text: chip, tone: chipTone) }
            }
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1 / 2) {
                Text(verbatim: value)
                    .dsFont(.xl, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.textPrimary)
                if let unit {
                    Text(verbatim: unit).dsFont(.xs, weight: .medium).foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            chart
                .frame(height: DS.Size.tileChart)
            footer
                .font(.system(size: DS.TextSize.xs.rawValue))
                .foregroundStyle(DS.Palette.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}
