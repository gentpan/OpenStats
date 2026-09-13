import AppKit
import HelperShared
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, menuBar, network, thermal, helper, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .menuBar: "菜单栏"
        case .network: "网络"
        case .thermal: "散热与防休眠"
        case .helper: "辅助工具"
        case .about: "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .network: "network"
        case .thermal: "fan"
        case .helper: "lock.shield"
        case .about: "info.circle"
        }
    }
}

public struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var section: SettingsSection

    public init() {
        _section = State(initialValue: .general)
    }

    init(section: SettingsSection) {
        _section = State(initialValue: section)
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                ForEach(SettingsSection.allCases) { item in
                    SidebarButton(title: item.title, symbol: item.symbol, isSelected: item == section) { section = item }
                }
                Spacer()
            }
            .padding(.horizontal, DS.Space.s3)
            .padding(.top, DS.Size.windowHeader + DS.Space.s2)
            .padding(.bottom, DS.Space.s3)
            .frame(width: DS.Size.settingsSidebar)
            .frame(maxHeight: .infinity)
            .background(alignment: .top) {
                WindowDragArea().frame(height: DS.Size.windowHeader)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(section.title)
                    .dsFont(.base, weight: .semibold)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .padding(.horizontal, DS.Space.s3 + DS.Space.s1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: DS.Size.windowHeader)
                    .background(WindowDragArea())
                SettingsPage {
                    switch section {
                    case .general: GeneralSettings()
                    case .menuBar: MenuBarSettings()
                    case .network: NetworkSettings()
                    case .thermal: ThermalSettings()
                    case .helper: HelperSettings()
                    case .about: AboutSettings()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: DS.Size.settingsWidth, height: isSnapshot ? nil : DS.Size.settingsHeight)
        .fixedSize(horizontal: false, vertical: isSnapshot)
        .background(DS.Palette.background)
        .ignoresSafeArea()
        .onAppear {
            model.refreshLaunchAtLogin()
            model.helper.refreshStatus()
        }
    }
}

private struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let stack = VStack(alignment: .leading, spacing: DS.Space.s4) {
            content
        }
        .padding(.horizontal, DS.Space.s3 + DS.Space.s1)
        .padding(.bottom, DS.Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)

        if isSnapshot {
            stack
        } else {
            ScrollView { stack }
                .scrollIndicators(.automatic)
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    var caption: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let caption {
                Text(caption).dsFont(.xs, weight: .medium).foregroundStyle(DS.Palette.textSecondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
    }
}

/// 分组内的一行，自带内边距与分隔线
private struct GroupRow<Content: View>: View {
    var showsDivider = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider { HairlineDivider() }
            content
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, DS.Space.s3)
        }
    }
}

// MARK: - 通用

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings

        SettingsGroup {
            GroupRow(showsDivider: false) {
                SettingRow(title: "外观", subtitle: "面板与设置窗口的配色；菜单栏始终跟随系统") {
                    SegmentedControl(selection: $settings.appearance,
                                     options: AppearanceMode.allCases.map { ($0, $0.title) })
                        .frame(width: DS.Size.settingsSidebar + DS.Space.s12)
                }
            }
            GroupRow {
                SettingRow(title: "登录时启动", subtitle: model.launchAtLoginError ?? "开机后自动在菜单栏显示 OpenStats") {
                    DSToggle(isOn: Binding(get: { model.launchAtLoginEnabled },
                                           set: { model.setLaunchAtLogin($0) }),
                             label: "登录时启动")
                }
            }
            GroupRow {
                SettingRow(title: "刷新频率", subtitle: "只显示菜单栏时的采样间隔；打开弹窗或主窗口时固定为 1 秒") {
                    SegmentedControl(selection: $settings.refreshSeconds,
                                     options: AppSettings.refreshOptions.map { ($0, "\($0) 秒") })
                        .frame(width: DS.Size.settingsSidebar + DS.Space.s12)
                }
            }
            GroupRow {
                SettingRow(title: "温度单位") {
                    SegmentedControl(selection: $settings.useFahrenheit, options: [(false, "°C"), (true, "°F")])
                        .frame(width: DS.Size.settingsSidebar / 2 + DS.Space.s6)
                }
            }
        }
    }
}

// MARK: - 菜单栏

private struct MenuBarSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings

        MenuBarPreview()

        SettingsGroup(caption: "布局") {
            GroupRow(showsDivider: false) {
                SettingRow(title: "菜单栏图标",
                           subtitle: settings.menuBarLayout == .separate
                               ? "每个指标一个图标，点击弹出该项详情"
                               : "所有指标合成一个图标，点击打开主窗口") {
                    SegmentedControl(selection: $settings.menuBarLayout,
                                     options: MenuBarLayout.allCases.map { ($0, $0.title) })
                        .frame(width: DS.Size.settingsSidebar + DS.Space.s6)
                }
            }
        }

        SettingsGroup(caption: "风格") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s3), GridItem(.flexible(), spacing: DS.Space.s3)],
                      spacing: DS.Space.s3) {
                ForEach(MenuBarStyle.allCases) { style in
                    StyleCard(style: style, isSelected: settings.menuBarStyle == style) {
                        settings.menuBarStyle = style
                    }
                }
            }
            .padding(DS.Space.s3)
        }

        SettingsGroup(caption: "显示项目") {
            ForEach(Array(MenuBarItem.allCases.enumerated()), id: \.element) { index, item in
                GroupRow(showsDivider: index > 0) {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        SettingRow(title: item.title, subtitle: item.subtitle, icon: item.symbol) {
                            HStack(spacing: DS.Space.s3) {
                                if settings.isEnabled(item) {
                                    itemStylePicker(item)
                                }
                                DSToggle(isOn: Binding(get: { settings.isEnabled(item) },
                                                       set: { settings.setEnabled(item, $0) }),
                                         label: item.title)
                            }
                        }
                        if settings.isEnabled(item), settings.menuBarLayout == .separate {
                            PopoverSectionPicker(item: item)
                        }
                    }
                }
            }
        }

        SettingsGroup(caption: "其他") {
            GroupRow(showsDivider: false) {
                SettingRow(title: "高负载时着色", subtitle: "占用超过 85% 时数值与图形显示为红色") {
                    DSToggle(isOn: $settings.colorizeHighLoad, label: "高负载时着色")
                }
            }
        }
    }

    /// 网速有自己的三种样式；其他指标可以单独指定风格，默认跟随整体
    @ViewBuilder
    private func itemStylePicker(_ item: MenuBarItem) -> some View {
        @Bindable var settings = model.settings
        if item == .network {
            SegmentedControl(selection: $settings.networkStyle,
                             options: NetworkMenuStyle.allCases.map { ($0, $0.title) })
                .frame(width: DS.Size.settingsSidebar + DS.Space.s6)
        } else {
            Picker("风格", selection: Binding(get: { settings.styleOverrides[item] },
                                             set: { settings.setStyleOverride($0, for: item) })) {
                Text("跟随整体").tag(MenuBarStyle?.none)
                Divider()
                ForEach(MenuBarStyle.allCases) { style in
                    Text(style.title).tag(MenuBarStyle?.some(style))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// 选择该项详情弹窗里显示哪些区块
private struct PopoverSectionPicker: View {
    @Environment(AppModel.self) private var model
    let item: MenuBarItem

    var body: some View {
        let settings = model.settings
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            Text("弹窗显示")
                .dsFont(.xs)
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize()
            FlowLayout(spacing: DS.Space.s1) {
                ForEach(item.popoverSections) { section in
                    let visible = settings.isVisible(section)
                    SectionToggleChip(title: section.title, isOn: visible) {
                        settings.setVisible(section, !visible)
                    }
                }
            }
        }
        .padding(.leading, DS.Size.iconStandalone + DS.Space.s3)
    }
}

private struct SectionToggleChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: isOn ? "checkmark" : "plus")
                    .font(.system(size: DS.TextSize.xs.rawValue - DS.Space.s1 / 2, weight: .bold))
                Text(title).dsFont(.xs, weight: .medium)
            }
            .foregroundStyle(isOn ? DS.Palette.primary : DS.Palette.textSecondary)
            .padding(.horizontal, DS.Space.s2)
            .frame(height: DS.Size.segmentHeight)
            .background(isOn ? DS.Palette.primary.opacity(0.12) : hovering ? DS.Palette.surfaceHover : .clear,
                        in: RoundedRectangle(cornerRadius: DS.Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(isOn ? DS.Palette.primary.opacity(0.4) : DS.Palette.border, lineWidth: DS.Size.stroke))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct StyleCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let style: MenuBarStyle
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let sample = MenuBarRenderer.image(reading: .sample, items: [.cpu, .memory, .gpu],
                                           style: { _ in style }, networkStyle: model.settings.networkStyle,
                                           colorizeHighLoad: false, fahrenheit: model.settings.useFahrenheit)
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                // 预览按原尺寸显示，超出卡片宽度时等比缩小，保证各卡片对齐
                Image(nsImage: MenuBarRenderer.preview(sample, dark: colorScheme == .dark))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: sample.size.width, maxHeight: sample.size.height)
                    .padding(.horizontal, DS.Space.s2)
                    .frame(maxWidth: .infinity)
                    .frame(height: DS.Size.controlHeight + DS.Space.s2)
                    .background(DS.Palette.track, in: RoundedRectangle(cornerRadius: DS.Radius.sm))

                HStack(spacing: DS.Space.s1) {
                    Text(style.title).dsFont(.sm, weight: .semibold).foregroundStyle(DS.Palette.textPrimary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: DS.TextSize.sm.rawValue))
                            .foregroundStyle(DS.Palette.primary)
                    }
                }
                Text(style.detail)
                    .dsFont(.xs)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: DS.TextSize.xs.rawValue * 3, alignment: .topLeading)
            }
            .padding(DS.Space.s2)
            .background(hovering && !isSelected ? DS.Palette.surfaceHover : Color.clear,
                        in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(isSelected ? DS.Palette.primary : DS.Palette.border,
                              lineWidth: isSelected ? DS.Size.chartLine : DS.Size.stroke))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct MenuBarPreview: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let image = MenuBarRenderer.image(for: model)
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("当前效果（实时数据）").dsFont(.xs, weight: .medium).foregroundStyle(DS.Palette.textSecondary)
            HStack(spacing: DS.Space.s3) {
                preview(image: image, dark: false)
                preview(image: image, dark: true)
            }
        }
    }

    private func preview(image: NSImage, dark: Bool) -> some View {
        HStack {
            Spacer()
            Image(nsImage: MenuBarRenderer.preview(image, dark: dark))
            Spacer()
        }
        .frame(height: DS.Size.controlHeight + DS.Space.s2)
        .background(dark ? Color(nsColor: NSColor(hex: 0x1F2937)) : Color(nsColor: NSColor(hex: 0xE5E7EB)),
                    in: RoundedRectangle(cornerRadius: DS.Radius.md))
        .accessibilityLabel(dark ? "深色菜单栏预览" : "浅色菜单栏预览")
    }
}

// MARK: - 网络

private struct NetworkSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings

        SettingsGroup(caption: "连接探测") {
            GroupRow(showsDivider: false) {
                SettingRow(title: "定时探测网络", subtitle: "用 ping 测量延迟与丢包，在网络详情里以格子显示；只在菜单栏显示网络项或打开网络详情时运行") {
                    DSToggle(isOn: $settings.probeEnabled, label: "定时探测网络")
                }
            }
            GroupRow {
                SettingRow(title: "探测间隔") {
                    SegmentedControl(selection: $settings.probeSeconds,
                                     options: AppSettings.probeOptions.map { ($0, "\($0) 秒") })
                        .frame(width: DS.Size.settingsSidebar)
                }
            }
            .disabled(!settings.probeEnabled)
            GroupRow {
                SettingRow(title: "探测目标", subtitle: "国内网络建议选阿里云或腾讯；选路由器只检测本地连接") {
                    Picker("探测目标", selection: $settings.probeTarget) {
                        ForEach(ProbeTarget.allCases) { target in
                            Text(target.title).tag(target)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .disabled(!settings.probeEnabled)
        }

        SettingsGroup(caption: "公网 IP") {
            GroupRow(showsDivider: false) {
                SettingRow(title: "查询公网 IP", subtitle: "打开网络详情时向 ipinfo.io 查询公网地址、归属地与 ASN，IPv6 与回退使用 Cloudflare / ipify；10 分钟内不重复请求") {
                    DSToggle(isOn: $settings.publicIPLookup, label: "查询公网 IP")
                }
            }
        }

        InfoBanner(icon: "lock.shield", text: "修改 DNS 需要管理员权限：已安装辅助工具时直接修改，否则每次弹出系统授权框。", tone: .neutral)
    }
}

// MARK: - 散热与防休眠

private struct ThermalSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings

        SettingsGroup(caption: "风扇") {
            GroupRow(showsDivider: false) {
                SettingRow(title: "安全温度", subtitle: "自定义转速时，CPU 达到该温度自动恢复系统控制") {
                    SegmentedControl(selection: $settings.fanSafetyTemperature,
                                     options: AppSettings.fanSafetyOptions.map { ($0, "\($0)°C") })
                        .frame(width: DS.Size.settingsSidebar + DS.Space.s12)
                }
            }
        }

        SettingsGroup(caption: "合盖运行") {
            GroupRow(showsDivider: false) {
                SettingRow(title: "电量下限", subtitle: "使用电池且电量低于该值时，自动关闭合盖运行") {
                    SegmentedControl(selection: $settings.lidModeBatteryFloor,
                                     options: AppSettings.batteryFloorOptions.map { ($0, "\($0)%") })
                        .frame(width: DS.Size.settingsSidebar + DS.Space.s12)
                }
            }
        }
    }
}

// MARK: - 辅助工具

private struct HelperSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let helper = model.helper

        SettingsGroup {
            GroupRow(showsDivider: false) {
                SettingRow(title: "OpenStats 辅助工具", subtitle: "以系统权限运行的后台服务，只接受本应用的请求", icon: "lock.shield") {
                    StatusBadge(text: helper.status.title, tone: tone(helper.status))
                }
            }
            GroupRow {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text("它只做这几件事").dsFont(.sm, weight: .medium).foregroundStyle(DS.Palette.textPrimary)
                    CapabilityLine(text: "设置风扇目标转速，或恢复系统自动控制")
                    CapabilityLine(text: "开启 / 关闭“合盖不睡眠”（等同 pmset disablesleep）")
                    CapabilityLine(text: "刷新 DNS 缓存、释放内存、为网络服务设置 DNS 服务器")
                    CapabilityLine(text: "应用退出或断开连接时，自动恢复风扇与睡眠设置")
                }
            }
            GroupRow {
                HStack(spacing: DS.Space.s2) {
                    switch helper.status {
                    case .notInstalled:
                        Button("安装辅助工具") { helper.install() }
                            .buttonStyle(DSButtonStyle(kind: .primary))
                    case .requiresApproval:
                        Button("打开登录项设置") { helper.openLoginItemsSettings() }
                            .buttonStyle(DSButtonStyle(kind: .primary))
                        Button("卸载") { Task { await helper.uninstall() } }
                            .buttonStyle(DSButtonStyle(kind: .secondary))
                    case .enabled:
                        Button("卸载辅助工具") { Task { await helper.uninstall() } }
                            .buttonStyle(DSButtonStyle(kind: .secondary))
                    case .unavailable:
                        EmptyView()
                    }
                    Button("刷新状态") { helper.refreshStatus() }
                        .buttonStyle(DSButtonStyle(kind: .ghost))
                    Spacer()
                }
                .disabled(helper.isWorking)
            }
        }

        if case .unavailable(let reason) = helper.status {
            InfoBanner(icon: "exclamationmark.triangle.fill", text: reason, tone: .error)
        }
        if let error = helper.lastError {
            InfoBanner(icon: "exclamationmark.triangle.fill", text: error, tone: .error)
        }
        if let team = CodeSigningInfo.currentTeamIdentifier() {
            InfoBanner(icon: "checkmark.seal", text: "已使用 Developer ID 签名（团队 \(team)），辅助工具只接受同一团队签名的 OpenStats。", tone: .success)
        } else {
            InfoBanner(icon: "info.circle", text: "当前为临时签名的开发构建，辅助工具只能校验应用标识。使用 Developer ID 证书构建后会自动启用团队校验。", tone: .neutral)
        }
    }

    private func tone(_ status: HelperClient.Status) -> Tone {
        switch status {
        case .enabled: .success
        case .requiresApproval: .warning
        case .notInstalled: .neutral
        case .unavailable: .error
        }
    }
}

private struct CapabilityLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Image(systemName: "checkmark")
                .font(.system(size: DS.TextSize.xs.rawValue, weight: .bold))
                .foregroundStyle(DS.Palette.success)
            Text(text).dsFont(.sm).foregroundStyle(DS.Palette.textSecondary)
        }
    }
}

// MARK: - 关于

private struct AboutSettings: View {
    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        SettingsGroup {
            GroupRow(showsDivider: false) {
                HStack(spacing: DS.Space.s4) {
                    AppGlyph(size: DS.Space.s12)
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text("OpenStats").dsFont(.lg, weight: .semibold).foregroundStyle(DS.Palette.textPrimary)
                        Text(verbatim: "版本 \(version)\(build.map { "（\($0)）" } ?? "")")
                            .dsFont(.sm)
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                    Spacer()
                }
            }
            GroupRow {
                Text("轻量的 macOS 菜单栏系统监控：CPU、GPU、内存、网络、温度、风扇、防休眠与清理。")
                    .dsFont(.sm)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }

        SettingsGroup(caption: "致谢") {
            GroupRow(showsDivider: false) {
                SettingRow(title: "exelban/stats", subtitle: "SMC 通信与 Apple Silicon 风扇解锁流程移植自该项目 · MIT License") {
                    Button("查看") {
                        if let url = URL(string: "https://github.com/exelban/stats") { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(DSButtonStyle(kind: .secondary))
                }
            }
        }
    }
}
