import AppKit
import Localization
import Metrics
import SwiftUI

/// 点击菜单栏单个指标弹出的窄详情。区块可在设置中逐个隐藏
struct PopoverRootView: View {
    let item: MenuBarItem

    var body: some View {
        PopoverFrame {
            PopoverHeader(item: item)
        } content: {
            PopoverDetail(item: item)
        }
    }
}

/// 菜单栏弹窗的外框：顶部标题栏与底部快捷开关固定，中间的内容可滚动
struct PopoverFrame<Header: View, Content: View>: View {
    var width: CGFloat = DS.Size.popoverWidth
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, DS.Space.s3)
                .padding(.vertical, DS.Space.s2)

            PageScroll { content }
                .frame(maxWidth: .infinity, maxHeight: isSnapshot ? nil : .infinity, alignment: .top)
                .environment(\.isPopover, true)
        }
        .frame(width: width)
        .frame(maxHeight: isSnapshot ? nil : .infinity, alignment: .top)
        .fixedSize(horizontal: false, vertical: isSnapshot)
        .panelBackground(DS.Palette.background, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous).strokeBorder(DS.Palette.border, lineWidth: DS.Size.stroke)
        }
        .environment(\.isCompactText, true)
    }
}

/// 某一项的详情内容，每项独立时的弹窗与合并时的弹窗共用
struct PopoverDetail: View {
    let item: MenuBarItem

    var body: some View {
        switch item {
        case .cpu: CPUPopover()
        case .memory: MemoryPopover()
        case .network: NetworkPopover()
        case .gpu: GPUPopover()
        case .disk: DiskPopover()
        case .temperature, .fan: ThermalPopover(item: item)
        case .battery: BatteryPopover()
        }
    }
}

/// 弹窗顶栏：左边是 OpenStats 的心跳线标志，每项独立的弹窗在后面写上这一项；右边是风扇、防休眠与跳转按钮。
/// `item` 为空时是合并面板的总览，跳转按钮打开主窗口的仪表盘
struct PopoverHeader: View {
    let item: MenuBarItem?
    /// 合并面板下方已有标签栏写明当前项，这里不再重复
    var showsTitle = true
    @Environment(AppModel.self) private var model

    var body: some View {
        let page = item.map(PanelTab.init(item:)) ?? .overview

        HStack(spacing: DS.Space.s2) {
            BrandMark()
                .stroke(DS.Palette.primary, style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                .frame(width: DS.Size.iconStandalone, height: DS.Size.iconInline * 0.75)
                .accessibilityHidden(true)
            if showsTitle, let item {
                Text(item.popoverTitle)
                    .dsFont(.base, weight: .semibold)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            // 按钮之间排得紧一些：内存弹窗多一颗释放内存
            HStack(spacing: DS.Space.s1) {
                if item == .memory { PurgeMemoryButton() }
                PopoverHeaderToggles()
                // 倒数第二颗用该页自己的图标，点进主窗口里它的页面；最右的齿轮进总设置
                MiniIconButton(systemName: page.symbol, help: tr("在主窗口打开“\(page.title)”")) { model.openMainWindow(page) }
                MiniIconButton(systemName: "gearshape", help: tr("设置")) { model.openSettings() }
            }
        }
    }
}

/// OpenStats 标志：App 图标里那条脉搏折线，不带图标的白底
struct BrandMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, vertex) in DS.Brand.pulse.enumerated() {
            let point = CGPoint(x: rect.minX + vertex.x * rect.width, y: rect.minY + vertex.y * rect.height)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

// MARK: - 共用组件

/// 弹窗里的一个区块：小标题 + 内容。
/// 解释性文字不常驻界面：给 `hint` 后标题旁出现一个很淡的 ⓘ，鼠标悬停在 ⓘ 或卡片内容上才显示说明，看一遍就够的人不用一直看着它
struct SectionCard<Trailing: View, Content: View>: View {
    let title: String
    var hint: String?
    /// 紧跟标题之后的小附件，例如数据来源的 logo
    var titleAccessory: AnyView?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                Text(title)
                    .dsFont(.xs, weight: .semibold)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                if let titleAccessory {
                    titleAccessory
                }
                if let hint {
                    Image(systemName: "info.circle")
                        .dsFont(.xs, weight: .medium)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .help(hint)
                        .accessibilityLabel(hint)
                }
                Spacer(minLength: DS.Space.s2)
                trailing
                    .dsFont(.xs)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
            }
            content
                .help(optional: hint)
        }
    }
}

extension SectionCard where Trailing == EmptyView {
    init(title: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, hint: hint, trailing: { EmptyView() }, content: content)
    }
}

extension View {
    /// 有说明时才挂悬停提示
    @ViewBuilder
    func help(optional text: String?) -> some View {
        if let text { help(text) } else { self }
    }
}

/// 弹窗里默认收起的区块：只占一行，左边标题、右边摘要，点一下展开
struct CollapsedSection: View {
    let title: String
    let summary: String
    var summaryColor: Color = DS.Palette.textPrimary
    let expand: () -> Void

    var body: some View {
        Card {
            Button(action: expand) {
                HStack(spacing: DS.Space.s2) {
                    Text(title)
                        .dsFont(.xs, weight: .semibold)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: DS.Space.s2)
                    Text(verbatim: summary)
                        .dsFont(.xs, weight: .medium)
                        .foregroundStyle(summaryColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .dsFont(.xs, weight: .semibold)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .frame(height: DS.Size.segmentHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tr("展开\(title)"))
        }
    }
}

extension View {
    /// 弹窗里可收起区块的收起按钮，放在标题栏最右边
    func collapseButton(_ section: PopoverSection, settings: AppSettings) -> some View {
        HStack(spacing: DS.Space.s1) {
            self
            MiniIconButton(systemName: "chevron.up", help: tr("收起")) {
                withAnimation(DS.Motion.quick) { settings.setExpanded(section, false) }
            }
        }
    }
}

/// 左侧标签、右侧数值的一行
struct InfoRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            Text(label)
                .dsFont(.xs)
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize()
            Spacer(minLength: 0)
            value
                .dsFont(.xs, weight: .medium)
                .foregroundStyle(DS.Palette.textPrimary)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

extension InfoRow where Value == Text {
    init(label: String, text: String) {
        self.label = label
        self.value = Text(verbatim: text)
    }
}

/// 点击拷贝的数值（IP、MAC 地址）
struct CopyableText: View {
    let text: String
    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        } label: {
            Text(verbatim: copied ? tr("已拷贝") : text)
                .foregroundStyle(copied ? DS.Palette.success : hovering ? DS.Palette.primary : DS.Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tr("点击拷贝"))
        .disabled(text == "—")
    }
}

/// 区块标题栏里的小图标按钮
struct MiniIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .dsFont(.xs, weight: .semibold)
                .foregroundStyle(hovering ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                .frame(width: DS.Size.segmentHeight, height: DS.Size.segmentHeight)
                .outlinedCircle(hovering: hovering)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 弹窗顶栏右侧的风扇与防休眠小圆钮，和设置按钮排在一起（原来是底部两块快捷开关，挪上来省出空间）。
/// 风扇：点一下换下一档（自动 → 降温 → 强冷 → 自动），图标颜色表示当前档位；没有风扇的 Mac 不显示。
/// 防休眠：点一下下拉出时长、屏幕与合盖运行，开着时圆钮填成强调色
struct PopoverHeaderToggles: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !(model.store.sensors?.fans.isEmpty ?? true) {
            FanCycleButton()
        }
        KeepAwakeHeaderButton()
    }
}

private struct FanCycleButton: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    private static let cycle: [FanController.Mode] = [.automatic, .cooling, .maximum]

    var body: some View {
        let mode = model.fans.mode
        let next = Self.next(after: mode)
        let help = tr("风扇：\(mode.title)，点一下切到“\(next.title)”")

        Button { model.requestFanMode(next) } label: {
            Image(systemName: mode == .automatic ? "fan" : "fan.fill")
                .dsFont(.xs, weight: .semibold)
                .foregroundStyle(color(mode))
                .symbolEffect(.bounce, value: mode)
                .frame(width: DS.Size.segmentHeight, height: DS.Size.segmentHeight)
                .outlinedCircle(hovering: hovering)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
        .task { await model.fans.loadFansIfNeeded() }
    }

    private func color(_ mode: FanController.Mode) -> Color {
        switch mode {
        case .automatic: hovering ? DS.Palette.textPrimary : DS.Palette.textSecondary
        case .cooling, .custom: DS.Palette.data
        case .maximum: DS.Palette.warning
        }
    }

    private static func next(after mode: FanController.Mode) -> FanController.Mode {
        guard let index = cycle.firstIndex(of: mode) else { return .automatic }
        return cycle[(index + 1) % cycle.count]
    }
}

private struct KeepAwakeHeaderButton: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false
    @State private var showsMenu = false

    var body: some View {
        let keepAwake = model.keepAwake
        let help = tr("防休眠：\(status)，点一下选择时长")

        Button { showsMenu.toggle() } label: {
            Image(systemName: keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .dsFont(.xs, weight: .semibold)
                .foregroundStyle(keepAwake.isActive ? DS.Palette.onPrimary
                                 : hovering ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                .frame(width: DS.Size.segmentHeight, height: DS.Size.segmentHeight)
                .outlinedCircle(hovering: hovering, isOn: keepAwake.isActive)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
        .popover(isPresented: $showsMenu, arrowEdge: .bottom) {
            KeepAwakeQuickMenu().environment(model)
        }
    }

    /// 开启时显示结束时间而不是倒计时：不用每分钟刷新。合盖运行开着时写在前面
    private var status: String {
        let keepAwake = model.keepAwake
        guard keepAwake.isActive else { return tr("按系统休眠") }
        let until = keepAwake.endDate.map { tr("\($0.formatted(date: .omitted, time: .shortened)) 结束") } ?? tr("不限时")
        return keepAwake.lidClosedActive ? "\(tr("合盖运行")) · \(until)" : until
    }
}

/// 区块标题栏右侧的一组小图标按钮，彼此留一点间距
struct HeaderActionGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: DS.Space.s1) {
            content
        }
    }
}

/// 区块标题栏里的刷新按钮：查询进行中换成系统的转圈，查完自动变回图标
struct RefreshButton: View {
    var loading: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        ZStack {
            if loading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(tr("正在查询…"))
            } else {
                MiniIconButton(systemName: "arrow.clockwise", help: help, action: action)
            }
        }
        .frame(width: DS.Size.segmentHeight, height: DS.Size.segmentHeight)
        .animation(DS.Motion.quick, value: loading)
    }
}

/// 详情弹窗顶部的统一版式，七个弹窗共用：左边一个主数值（常规字重，单位缩小变淡，与总览圆环的百分号一致），
/// 上面一行小标签、下面一行说明；右边最多三行“标签 数值”的次要读数，右对齐
struct PopoverHero: View {
    let label: String
    let value: String
    var valueColor: Color = DS.Palette.textPrimary
    /// 为 false 时整串同一字号（电池电量的百分号不缩小）
    var splitsUnit = true
    var caption: String?
    var captionTone: Tone = .neutral
    var stats: [HeroStat] = []

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: DS.Space.s1 / 2) {
                Text(verbatim: label).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary).lineLimit(1)
                Group {
                    if splitsUnit {
                        UnitText(text: value, size: .xxl, color: valueColor)
                    } else {
                        Text(verbatim: value).dsFont(.xxl).monospacedDigit().foregroundStyle(valueColor).lineLimit(1)
                    }
                }
                .fixedSize()
                if let caption {
                    Text(verbatim: caption)
                        .dsFont(.xs)
                        .monospacedDigit()
                        .foregroundStyle(captionTone == .neutral ? DS.Palette.textSecondary : captionTone.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: DS.Space.s2)
            if !stats.isEmpty {
                VStack(alignment: .trailing, spacing: DS.Space.s1) {
                    ForEach(stats) { stat in
                        HStack(spacing: DS.Space.s1) {
                            Text(verbatim: stat.label).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary).lineLimit(1)
                            UnitText(text: stat.value, size: .sm, color: stat.tone == .neutral ? DS.Palette.textPrimary : stat.tone.color)
                                .fixedSize()
                        }
                        .help(optional: stat.help)
                    }
                }
            }
        }
    }
}

/// macOS 自己报告的热状态：比读传感器更权威，偏高及以上表示系统已经在限制性能降温
enum ThermalStateInfo {
    @MainActor
    static var current: (title: String, tone: Tone) {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: (tr("正常"), .neutral)
        case .fair: (tr("偏高"), .warning)
        case .serious: (tr("严重"), .error)
        case .critical: (tr("危急"), .error)
        @unknown default: (tr("未知"), .neutral)
        }
    }

    static let help = tr("macOS 报告的热状态：偏高及以上时，系统会降低性能来降温")
}

/// 顶部右侧的一行次要读数
struct HeroStat: Identifiable {
    let label: String
    let value: String
    var tone: Tone = .neutral
    var help: String?

    var id: String { label }
}

/// 固定行数的进程列表，数据不足时用占位行，弹窗高度保持不变
struct ProcessList<Row: View>: View {
    let count: Int
    var rowCount = 5
    var emptyText = tr("正在统计…")
    /// 不满一页时写在第一个空行里的说明，免得空着几行像没加载完
    var restText: String?
    @ViewBuilder var row: (Int) -> Row

    var body: some View {
        if count == 0 {
            Text(emptyText)
                .dsFont(.xs)
                .foregroundStyle(DS.Palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.rowHeight)
            ForEach(1..<rowCount, id: \.self) { _ in
                Color.clear.frame(height: Self.rowHeight)
            }
        } else {
            ForEach(0..<min(count, rowCount), id: \.self) { index in
                row(index).frame(height: Self.rowHeight)
            }
            ForEach(0..<max(0, rowCount - count), id: \.self) { index in
                if index == 0, let restText {
                    Text(restText)
                        .dsFont(.xs)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: Self.rowHeight)
                } else {
                    Color.clear.frame(height: Self.rowHeight)
                }
            }
        }
    }

    /// 与同类应用的进程行高相近（约 18～22pt）
    static var rowHeight: CGFloat { DS.Size.iconInline + DS.Space.s1 / 2 }
}

struct ProcessNameLabel: View {
    let icon: Image
    let name: String

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            icon.resizable().frame(width: DS.Size.iconInline, height: DS.Size.iconInline)
            Text(verbatim: name)
                .dsFont(.xs, weight: .medium)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
        }
    }
}
