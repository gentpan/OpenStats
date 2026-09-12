import AppKit
import HelperShared
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, menuBar, thermal, helper, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .menuBar: "菜单栏"
        case .thermal: "散热与防休眠"
        case .helper: "辅助工具"
        case .about: "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
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
                    SidebarItem(section: item, isSelected: item == section) { section = item }
                }
                Spacer()
            }
            .padding(DS.Space.s3)
            .frame(width: DS.Size.settingsSidebar)
            .frame(maxHeight: .infinity)
            .background {
                if isSnapshot { DS.Palette.background } else { SidebarMaterial() }
            }

            Rectangle().fill(DS.Palette.border).frame(width: DS.Size.stroke)

            SettingsPage(title: section.title) {
                switch section {
                case .general: GeneralSettings()
                case .menuBar: MenuBarSettings()
                case .thermal: ThermalSettings()
                case .helper: HelperSettings()
                case .about: AboutSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: DS.Size.settingsWidth, height: isSnapshot ? nil : DS.Size.settingsHeight)
        .fixedSize(horizontal: false, vertical: isSnapshot)
        .onAppear {
            model.refreshLaunchAtLogin()
            model.helper.refreshStatus()
        }
    }
}

private struct SidebarItem: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: section.symbol)
                    .font(.system(size: DS.TextSize.sm.rawValue, weight: .medium))
                    .frame(width: DS.Size.iconStandalone)
                Text(section.title).dsFont(.sm, weight: isSelected ? .semibold : .regular)
                Spacer()
            }
            .foregroundStyle(isSelected ? DS.Palette.primary : DS.Palette.textPrimary)
            .padding(.horizontal, DS.Space.s2)
            .frame(height: DS.Size.controlHeight)
            .background(background, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if isSelected { return DS.Palette.primary.opacity(0.1) }
        return hovering ? DS.Palette.surfaceHover : .clear
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let stack = VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text(title).dsFont(.xl, weight: .semibold).foregroundStyle(DS.Palette.textPrimary)
            content
        }
        .padding(DS.Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)

        if isSnapshot {
            stack
        } else {
            ScrollView { stack }
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
            .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Palette.border, lineWidth: DS.Size.stroke))
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
                SettingRow(title: "刷新频率", subtitle: "面板收起时菜单栏的采样间隔；展开面板时固定为 1 秒") {
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

        SettingsGroup(caption: "显示项目") {
            ForEach(Array(MenuBarItem.allCases.enumerated()), id: \.element) { index, item in
                GroupRow(showsDivider: index > 0) {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        SettingRow(title: item.title, subtitle: item.subtitle, icon: item.symbol) {
                            DSToggle(isOn: Binding(get: { settings.isEnabled(item) },
                                                   set: { settings.setEnabled(item, $0) }),
                                     label: item.title)
                        }
                        if item.supportsGaugeStyle, settings.isEnabled(item) {
                            SegmentedControl(selection: Binding(get: { settings.gaugeStyle(for: item) },
                                                                set: { settings.setGaugeStyle($0, for: item) }),
                                             options: GaugeStyle.allCases.map { ($0, $0.title) })
                                .padding(.leading, DS.Size.iconStandalone + DS.Space.s3)
                        }
                    }
                }
            }
        }

        SettingsGroup(caption: "样式") {
            GroupRow(showsDivider: false) {
                SettingRow(title: "高负载时着色", subtitle: "CPU 超过 85% 时数值显示为红色，其余时间跟随菜单栏颜色") {
                    DSToggle(isOn: $settings.colorizeHighLoad, label: "高负载时着色")
                }
            }
        }
    }
}

private struct MenuBarPreview: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let image = MenuBarRenderer.image(for: model)
        VStack(spacing: DS.Space.s2) {
            preview(image: image, dark: false)
            preview(image: image, dark: true)
        }
    }

    private func preview(image: NSImage, dark: Bool) -> some View {
        let tinted = MenuBarRenderer.preview(image, dark: dark)
        return HStack {
            Spacer()
            Image(nsImage: tinted)
            Spacer()
        }
        .frame(height: DS.Size.controlHeight)
        .background(dark ? Color(nsColor: NSColor(hex: 0x1F2937)) : Color(nsColor: NSColor(hex: 0xE5E7EB)),
                    in: RoundedRectangle(cornerRadius: DS.Radius.md))
        .accessibilityLabel(dark ? "深色菜单栏预览" : "浅色菜单栏预览")
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
                    Text("它只做三件事").dsFont(.sm, weight: .medium).foregroundStyle(DS.Palette.textPrimary)
                    CapabilityLine(text: "设置风扇目标转速，或恢复系统自动控制")
                    CapabilityLine(text: "开启 / 关闭“合盖不睡眠”（等同 pmset disablesleep）")
                    CapabilityLine(text: "应用退出或断开连接时，自动恢复以上两项设置")
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
        if HelperConstants.teamIdentifier.isEmpty {
            InfoBanner(icon: "info.circle", text: "当前为开发构建：辅助工具只校验应用标识。正式发布前需使用 Developer ID 签名并填写 Team ID。", tone: .neutral)
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
                Text("轻量的 macOS 菜单栏系统监控：CPU、GPU、内存、网络、温度、风扇与防休眠。")
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
