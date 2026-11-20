import Localization
import Metrics
import SwiftUI

/// ImageRenderer 无法渲染 ScrollView 等 AppKit 承载的控件，截图模式下改用平铺布局。
extension EnvironmentValues {
    @Entry var isSnapshot = false
    /// 在主窗口里显示指标详情：显示全部区块，图表更高
    @Entry var isDetailPage = false
    /// 菜单栏弹窗：区块去掉卡片底色，用细分隔线隔开，排得更紧凑
    @Entry var isPopover = false
    /// 菜单栏弹窗（含合并面板的总览）：文字用紧凑字号
    @Entry var isCompactText = false
    /// 菜单栏弹窗：滚动内容的实际高度比可视区域高出（负数为矮出）多少，交给面板调整窗口高度
    @Entry var reportPopoverOverflow: PopoverOverflowReporter? = nil
}

/// 菜单栏弹窗的高度回调。闭包无法比较，直接放进环境会让依赖它的视图每次刷新都失效；
/// 每个弹窗只在创建时设置一次、之后不变，所以包一层并视为恒等
struct PopoverOverflowReporter: Equatable {
    let report: @MainActor @Sendable (CGFloat) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

// MARK: - 卡片

struct Card<Content: View>: View {
    var padding: CGFloat = DS.Space.s4
    var spacing: CGFloat = DS.Space.s3
    @ViewBuilder var content: Content
    @Environment(\.isPopover) private var isPopover
    @Environment(\.isCompactText) private var isCompact

    var body: some View {
        if isPopover {
            // 菜单栏弹窗：不画卡片，区块顶上一条细分隔线，上下各留一点空，行距收紧
            VStack(alignment: .leading, spacing: min(spacing, DS.Space.s1 + DS.Space.s1 / 2)) {
                content
            }
            .padding(.vertical, DS.Space.s2)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .overlay(alignment: .top) { HairlineDivider() }
        } else {
            cardBody
        }
    }

    private var cardBody: some View {
        // 合并面板的总览：卡片内边距与行距收紧
        VStack(alignment: .leading, spacing: isCompact ? min(spacing, DS.Space.s1 + DS.Space.s1 / 2) : spacing) {
            content
        }
        .padding(isCompact ? min(padding, DS.Space.s2 + DS.Space.s1 / 2) : padding)
        // 在等高行里撑满高度，背景随之延伸
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }
}

struct CardHeader<Trailing: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: icon)
                .dsFont(.sm, weight: .medium)
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

/// 卡片标题右侧的小字说明
struct CardHeaderDetail: View {
    let text: String

    var body: some View {
        Text(text).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
    }
}

extension CardHeader where Trailing == CardHeaderDetail {
    init(icon: String, title: String, detail: String) {
        self.icon = icon
        self.title = title
        self.trailing = CardHeaderDetail(text: detail)
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
    var color: Color = DS.Palette.data
    var height: CGFloat = DS.Size.barHeight
    /// 占比类（容量、电量）画灰色底槽；排行类（按应用汇总）只画彩色条，底槽拉满一整行反而显得杂乱
    var showsTrack = true

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                if showsTrack {
                    RoundedRectangle(cornerRadius: DS.Radius.bar(height), style: .continuous).fill(DS.Palette.track)
                }
                RoundedRectangle(cornerRadius: DS.Radius.bar(height), style: .continuous)
                    .fill(color)
                    .frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
    }
}

/// 带图标的徽章（cleanip.io 样式）：浅色底、细边框、同色系文字，用于“原生 IP”“住宅 IP”“ISP”这类结论性标签
struct TagBadge: View {
    enum Tone { case success, warning, neutral, primary }

    var icon: String?
    let text: String
    var tone: Tone = .success
    /// 放在区块标题行里的小号：更窄的内边距
    var compact = false

    var body: some View {
        HStack(spacing: DS.Space.s1) {
            if let icon {
                Image(systemName: icon)
                    .dsFont(.sm, weight: .semibold)
                    .frame(width: DS.Size.iconInline, height: DS.Size.iconInline)
            }
            Text(text).dsFont(.xs, weight: .semibold)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, compact ? DS.Space.s1 : DS.Space.s3)
        .padding(.vertical, compact ? DS.Space.s1 / 2 : DS.Space.s1)
        .background(fill, in: BadgeShape())
        .overlay(BadgeShape().strokeBorder(border, lineWidth: DS.Size.stroke))
        .lineLimit(1)
        .fixedSize()
    }

    private var foreground: Color {
        switch tone {
        case .success: DS.Badge.successText
        case .warning: DS.Badge.warningText
        case .neutral: DS.Badge.neutralText
        case .primary: DS.Palette.primary
        }
    }

    private var fill: Color {
        switch tone {
        case .success: DS.Badge.successFill
        case .warning: DS.Badge.warningFill
        case .neutral: DS.Badge.neutralFill
        case .primary: DS.Palette.primary.opacity(0.10)
        }
    }

    private var border: Color {
        switch tone {
        case .success: DS.Badge.successBorder
        case .warning: DS.Badge.warningBorder
        case .neutral: DS.Badge.neutralBorder
        case .primary: DS.Palette.primary.opacity(0.30)
        }
    }
}

/// cleanip.io 的字标：黑色部分按文字色着色（随深浅色变化），圆环与 “.io” 保持品牌绿。
/// 画布已裁到字形边缘，指定的高度就是字形实际高度，不留上下空白
struct CleanIPLogo: View {
    var height: CGFloat = DS.Size.iconInline

    var body: some View {
        // 字标画布已裁到字形边缘：600 × 98
        let width = height * 600 / 98
        ZStack {
            if let ink = LogoCache.shared.image(named: "cleanip-ink", template: true) {
                Image(nsImage: ink).resizable().foregroundStyle(DS.Palette.textPrimary)
            }
            if let green = LogoCache.shared.image(named: "cleanip-green", template: false) {
                Image(nsImage: green).resizable()
            }
        }
        .frame(width: width, height: height)
        // 字母落在画布 y = 78 处（下面是 p 的下伸部分）：与文字按基线对齐时对齐这条线，字标才和文字在同一水平线上
        .alignmentGuide(.firstTextBaseline) { $0.height * 78 / 98 }
        .alignmentGuide(.lastTextBaseline) { $0.height * 78 / 98 }
        .accessibilityLabel("cleanip.io")
    }
}

/// 可点击的 cleanip.io 字标：点了打开链接，悬停时略微变淡
struct CleanIPLink: View {
    static let site = URL(string: "https://cleanip.io")!
    var height: CGFloat = DS.Size.iconInline
    var url = CleanIPLink.site
    var help = "cleanip.io"
    @State private var hovering = false

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            CleanIPLogo(height: height)
                .opacity(hovering ? 0.7 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DS.Motion.quick, value: hovering)
        .help(help)
    }
}

/// 小号切换：底槽是一条灰色超椭圆圆角条，选中项是一块蓝色圆角块滑过去（与底槽同心），文字随之变白
struct PillSwitch<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .dsFont(.xs, weight: .semibold)
                        .foregroundStyle(selected ? DS.Palette.onPrimary : DS.Palette.textSecondary)
                        .padding(.horizontal, DS.Space.s2)
                        .frame(height: DS.Size.segmentHeight - DS.Space.s1)
                        .background {
                            if selected {
                                ControlShape(nestedPadding: DS.Space.s1 / 2).fill(DS.Palette.primary)
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .contentShape(ControlShape(nestedPadding: DS.Space.s1 / 2))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Space.s1 / 2)
        .background(DS.Palette.track, in: ControlShape())
        .animation(DS.Motion.quick, value: selection)
        .fixedSize()
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

    /// 占用类数值（CPU、GPU、单个核心）的颜色：60% 起变黄、85% 起变红；正常时的颜色由场景决定
    static func forLoad(_ value: Double, normal: Tone) -> Tone {
        value >= 0.85 ? .error : value >= 0.6 ? .warning : normal
    }

    /// 温度文字的颜色：正常时用普通文字色，只在偏高变黄、过热变红，颜色只用来提醒（条形图仍用 forTemperature）
    static func forTemperatureText(_ celsius: Double) -> Tone {
        let tone = forTemperature(celsius)
        return tone == .primary ? .neutral : tone
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
        .background(tone.color.opacity(0.12), in: BadgeShape())
        .lineLimit(1)
    }
}

// MARK: - 按钮

/// 按钮与切换控件的外形：超椭圆圆角（连续曲率），半径随控件高度取，不是两头全圆的胶囊。
/// 设计规则是 CSS `corner-shape: squircle` 下“半径约为高度的 0.46 倍”；连续曲率圆角同样半径下更圆，
/// 再乘 0.54 后视觉一致：32pt 高的按钮约 8pt。
/// `nestedPadding` 用于嵌在另一个控件里的选中块：按外层的高度取半径再减去两者之间的内边距，保持同心
/// 徽章、小标签、复选框这类小元素的外形：超椭圆圆角，半径约为高度的三分之一。
/// 比按钮（ControlShape）更圆一些，小尺寸下也看得出超椭圆的弧度，但又不是两头全圆的胶囊
struct BadgeShape: InsettableShape {
    private var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: inset, dy: inset)
        return RoundedRectangle(cornerRadius: box.height * 0.32, style: .continuous).path(in: box)
    }

    func inset(by amount: CGFloat) -> BadgeShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}

struct ControlShape: InsettableShape {
    var nestedPadding: CGFloat = 0
    private var inset: CGFloat = 0

    init(nestedPadding: CGFloat = 0) {
        self.nestedPadding = nestedPadding
    }

    static func radius(height: CGFloat) -> CGFloat {
        height * 0.46 * 0.54
    }

    func path(in rect: CGRect) -> Path {
        let outer = rect.height + nestedPadding * 2
        let radius = max(0, Self.radius(height: outer) - nestedPadding - inset)
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .path(in: rect.insetBy(dx: inset, dy: inset))
    }

    func inset(by amount: CGFloat) -> ControlShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}

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
            .background(background, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).strokeBorder(DS.Palette.border, lineWidth: DS.Size.stroke)
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
                .dsFont(.sm, weight: .medium)
                .foregroundStyle(hovering ? DS.Palette.primary : DS.Palette.textSecondary)
                .frame(width: DS.Size.controlHeight, height: DS.Size.controlHeight)
                .outlinedCircle(hovering: hovering)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

extension View {
    /// 图标按钮的底：一圈细描边的圆钮，悬停时垫一层淡底；`isOn` 为真时（开关类按钮打开）填成强调色
    func outlinedCircle(hovering: Bool, isOn: Bool = false) -> some View {
        background(isOn ? DS.Palette.primary : hovering ? DS.Palette.surfaceHover : .clear, in: Circle())
            .overlay {
                if !isOn { Circle().strokeBorder(DS.Palette.border, lineWidth: DS.Size.stroke) }
            }
    }
}

// MARK: - 侧边栏

/// 侧边栏的一项。选中态的底块由容器上的 `sidebarGlider()` 画，切换时滑过去
struct SidebarButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    /// 需要注意时在右侧显示一个圆点（有新版本、辅助工具需要重新安装）
    var badge: Tone?
    let action: () -> Void
    @State private var hovering = false
    /// 每次被选中加一，触发图标轻跳一下
    @State private var selectCount = 0

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s2 + DS.Space.s1 / 2) {
                Image(systemName: symbol)
                    .dsFont(.sm, weight: .medium)
                    .frame(width: DS.Size.iconStandalone)
                    .symbolEffect(.bounce, value: selectCount)
                Text(title).dsFont(.sm, weight: isSelected ? .semibold : .regular)
                Spacer()
                if let badge {
                    Circle().fill(badge.color).frame(width: DS.Space.s2, height: DS.Space.s2)
                        .accessibilityLabel(tr("需要注意"))
                }
            }
            .foregroundStyle(isSelected ? DS.Palette.sidebarSelectedText
                             : hovering ? DS.Palette.textPrimary : DS.Palette.textSecondary)
            .padding(.leading, DS.Space.s3)
            .padding(.trailing, DS.Space.s2)
            .frame(height: DS.Size.sidebarRowHeight)
            .background {
                // 悬停时垫一层淡淡的底；选中项的底由 sidebarGlider 画
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Palette.surfaceHover)
                    .opacity(hovering && !isSelected ? 1 : 0)
            }
            .contentShape(Rectangle())
            .animation(DS.Motion.quick, value: isSelected)
            .animation(DS.Motion.quick, value: hovering)
        }
        .buttonStyle(SidebarPressStyle())
        .onHover { hovering = $0 }
        .onChange(of: isSelected) { _, selected in
            if selected { selectCount += 1 }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .anchorPreference(key: SidebarRowsKey.self, value: .bounds) { [SidebarRow(isSelected: isSelected, bounds: $0)] }
    }
}

/// 侧边栏按下时略微缩小，松开回弹
private struct SidebarPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct SidebarRow {
    let isSelected: Bool
    let bounds: Anchor<CGRect>
}

struct SidebarRowsKey: PreferenceKey {
    static let defaultValue: [SidebarRow] = []
    static func reduce(value: inout [SidebarRow], nextValue: () -> [SidebarRow]) { value += nextValue() }
}

extension View {
    /// 放在包含 SidebarButton 的容器上，画出选中态：选中项垫一块超椭圆圆角的底块，切换时滑过去。
    /// 三个主题结构一致，底块与文字的颜色由 sidebarSelected / sidebarSelectedText 决定
    func sidebarGlider() -> some View {
        backgroundPreferenceValue(SidebarRowsKey.self) { rows in
            GeometryReader { proxy in
                if let selected = rows.first(where: \.isSelected).map({ proxy[$0.bounds] }) {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Palette.sidebarSelected)
                        .frame(width: selected.width, height: selected.height)
                        .offset(x: selected.minX, y: selected.minY)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
                }
            }
            .allowsHitTesting(false)
        }
    }
}


// MARK: - 分段控件

/// 分段切换（苹果标准样式，与系统设置一致）：一条灰色圆角底槽，各段等宽铺满，
/// 选中的一段是实心品牌蓝、白字，切换时蓝块滑过去
struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @Namespace private var namespace

    private static var radius: CGFloat { DS.Radius.md - DS.Space.s1 / 2 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .dsFont(.sm)
                        .foregroundStyle(selected ? DS.Palette.onPrimary : DS.Palette.textPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, DS.Space.s2)
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
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background(DS.Palette.track, in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selection)
    }
}

// MARK: - 开关

struct DSToggle: View {
    @Binding var isOn: Bool
    var label: String = ""
    var body: some View {
        // 自绘开关：三个主题同一个样子，颜色跟随主题
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous).fill(isOn ? DS.Palette.primary : DS.Palette.neutral300)
                Circle()
                    .fill(DS.Palette.onPrimary)
                    .frame(width: DS.Size.switchKnob, height: DS.Size.switchKnob)
                    .dsShadow(DS.Shadow.level1)
                    .padding(DS.Space.s1)
            }
            .frame(width: DS.Size.switchWidth, height: DS.Size.switchHeight)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(DS.Motion.quick, value: isOn)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? tr("开") : tr("关"))
    }
}

// MARK: - 复选框

struct DSCheckbox: View {
    let isOn: Bool
    /// 只选了其中一部分：显示横线，点一下全选
    var isMixed = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            BadgeShape()
                .fill(isOn ? DS.Palette.primary : Color.clear)
                .overlay {
                    if isOn {
                        Image(systemName: isMixed ? "minus" : "checkmark")
                            .font(.system(size: DS.TextSize.xs.rawValue - DS.Space.s1 / 2, weight: .bold))
                            .foregroundStyle(DS.Palette.onPrimary)
                    } else {
                        BadgeShape()
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
                    .dsFont(.base)
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
                .dsFont(.sm, weight: .semibold)
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
        .background(tone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
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
                Capsule(style: .continuous).fill(DS.Palette.track)
                    .frame(height: DS.Space.s1 + DS.Space.s1 / 2)
                Capsule(style: .continuous).fill(DS.Palette.primary)
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
    @Environment(\.isPopover) private var isPopover
    @Environment(\.reportPopoverOverflow) private var reportOverflow
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        // 弹窗里区块之间靠分隔线隔开，不再额外留间距
        let stack = VStack(alignment: .leading, spacing: isPopover ? 0 : DS.Space.s3) { content }
            .padding(.horizontal, DS.Space.s3)
            .padding(.bottom, isPopover ? DS.Space.s1 : DS.Space.s3)
        if isSnapshot {
            stack
        } else {
            // 内容放得下时不回弹，避免点击时整页轻微抖动
            ScrollView {
                stack
                    .overlayScrollers()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        contentHeight = height
                        report()
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                viewportHeight = height
                report()
            }
        }
    }

    /// 弹窗里内容高度一变（数据刷新、展开收起），就让面板把窗口调到正好放下；屏幕放不下时才出现滚动
    private func report() {
        guard let reportOverflow, contentHeight > 0, viewportHeight > 0 else { return }
        reportOverflow.report(contentHeight - viewportHeight)
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
                Image(systemName: icon).dsFont(.xs, weight: .semibold)
            }
            Text(verbatim: text).dsFont(.xs, weight: .medium).monospacedDigit()
        }
        .foregroundStyle(tone == .neutral ? DS.Palette.textSecondary : tone.color)
        .padding(.horizontal, DS.Space.s2)
        .padding(.vertical, DS.Space.s1 / 2)
        .background(tone == .neutral ? DS.Palette.track : tone.color.opacity(0.12),
                    in: BadgeShape())
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
                .background(background, in: BadgeShape())
                .overlay(BadgeShape()
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
                    .dsFont(.xs, weight: .semibold)
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
                .dsFont(.xs)
                .foregroundStyle(DS.Palette.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

// MARK: - 数值与单位

/// 数字按给定字号显示，单位（KB/s、RPM、TB、GB、°C 等）缩小、常规字重、颜色更淡，与圆环里的百分号一致。
/// 传入格式化好的整串文字，按“数字 / 非数字”自动拆开，例如“1.7 TB”“40.3 GB / 64.0 GB”“52°C”
struct UnitText: View {
    let text: String
    var size: DS.TextSize = .base
    var color: Color = DS.Palette.textPrimary
    /// 不给时用数字颜色的淡一些的版本
    var unitColor: Color?
    @Environment(\.isCompactText) private var compact

    /// 单位相对数字的大小
    static let unitScale: CGFloat = 0.62

    var body: some View {
        let points = size.points(compact: compact)
        Self.runs(text).reduce(Text(verbatim: "")) { result, run in
            result + (run.isNumber
                ? Text(verbatim: run.text).font(.system(size: points)).foregroundStyle(color)
                : Text(verbatim: run.text).font(.system(size: points * Self.unitScale)).foregroundStyle(unitColor ?? color.opacity(0.6)))
        }
        .monospacedDigit()
        .lineLimit(1)
    }

    /// 连续的数字（含小数点、千分位逗号、负号、占位的“—”）为一段，其余为单位段。
    /// 整串没有数字时（“正常”“未使用”）是一个词而不是单位，整串按数字的字号显示
    static func runs(_ text: String) -> [(text: String, isNumber: Bool)] {
        guard text.contains(where: \.isNumber) else { return [(text, true)] }
        var runs: [(text: String, isNumber: Bool)] = []
        for character in text {
            let isNumber = character.isNumber || ".,-—".contains(character)
            if let last = runs.last, last.isNumber == isNumber {
                runs[runs.count - 1].text.append(character)
            } else {
                runs.append((String(character), isNumber))
            }
        }
        return runs
    }
}
