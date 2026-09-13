import AppKit
import HelperShared
import Metrics
import SwiftUI

/// 主窗口里的设置页：与其他页面同样的滚动容器，打开时刷新登录项与辅助工具状态
struct SettingsTabPage<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: Content

    var body: some View {
        PageScroll { content }
            .onAppear {
                model.refreshLaunchAtLogin()
                model.helper.refreshStatus()
            }
    }
}

struct SettingsGroup<Content: View>: View {
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
struct GroupRow<Content: View>: View {
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

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings

        SettingsGroup {
            GroupRow(showsDivider: false) {
                SettingRow(title: "外观", subtitle: "主窗口与弹窗的配色；菜单栏始终跟随系统") {
                    SegmentedControl(selection: $settings.appearance,
                                     options: AppearanceMode.allCases.map { ($0, $0.title) })
                        .frame(width: DS.Size.sidebarWidth + DS.Space.s12)
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
                        .frame(width: DS.Size.sidebarWidth + DS.Space.s12)
                }
            }
            GroupRow {
                SettingRow(title: "温度单位") {
                    SegmentedControl(selection: $settings.useFahrenheit, options: [(false, "°C"), (true, "°F")])
                        .frame(width: DS.Size.sidebarWidth / 2 + DS.Space.s6)
                }
            }
        }
    }
}

// MARK: - 菜单栏

struct MenuBarSettings: View {
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
                        .frame(width: DS.Size.sidebarWidth + DS.Space.s6)
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
                .frame(width: DS.Size.sidebarWidth + DS.Space.s6)
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

struct NetworkSettings: View {
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
                        .frame(width: DS.Size.sidebarWidth)
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
                SettingRow(title: "查询公网 IP",
                           subtitle: model.geo.isAvailable
                               ? "打开网络详情时向 Cloudflare（1.1.1.1）或 ipify 查询一次公网地址；归属地与 ASN 在本机数据库里查，10 分钟内不重复请求"
                               : "打开网络详情时查询公网地址；本地数据库还没准备好时，归属地与 ASN 暂由 ipinfo.io 在线查询") {
                    DSToggle(isOn: $settings.publicIPLookup, label: "查询公网 IP")
                }
            }
        }

        GeoDatabaseSettings()

        InfoBanner(icon: "lock.shield", text: "修改 DNS 需要管理员权限：已安装辅助工具时直接修改，否则每次弹出系统授权框。", tone: .neutral)
    }
}

/// IP 归属地数据库（MaxMind GeoLite2）
private struct GeoDatabaseSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        let geo = model.geo

        SettingsGroup(caption: "IP 归属地数据库") {
            GroupRow(showsDivider: false) {
                SettingRow(title: geo.isAvailable ? "本地 MaxMind GeoLite2" : "尚未下载",
                           subtitle: geo.isAvailable
                               ? "国家、城市与 ASN 在本机查询，不经过任何在线服务"
                               : "下载后归属地查询完全离线；数据库由 OpenStats 官网每周同步 MaxMind 的最新版本") {
                    StatusBadge(text: geo.isAvailable ? "离线查询" : "在线查询", tone: geo.isAvailable ? .success : .neutral)
                }
            }
            ForEach(geo.installed.values.sorted { $0.edition < $1.edition }, id: \GeoDatabaseController.Installed.edition) { database in
                GroupRow {
                    SettingRow(title: title(database.edition), subtitle: "版本 \(database.build) · \(Format.bytes(UInt64(database.size), base: .decimal))") {
                        Text(database.edition).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
                    }
                }
            }
            GroupRow {
                SettingRow(title: "包含城市数据", subtitle: "显示城市名称，数据库约 60 MB；关闭时只下载国家库（约 9 MB）") {
                    DSToggle(isOn: $settings.geoIncludeCity, label: "包含城市数据")
                }
            }
            GroupRow {
                SettingRow(title: "自动更新", subtitle: geo.lastChecked.map { "每 3 天检查一次 · 上次检查 \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "每 3 天检查一次") {
                    DSToggle(isOn: $settings.geoAutoUpdate, label: "自动更新")
                }
            }
            GroupRow {
                HStack(spacing: DS.Space.s2) {
                    Button(geo.isUpdating ? "正在更新…" : geo.isAvailable ? "立即检查更新" : "下载数据库") {
                        Task { await geo.update() }
                    }
                    .buttonStyle(DSButtonStyle(kind: .primary))
                    .disabled(geo.isUpdating)
                    Button("从文件导入…") { importFile() }
                        .buttonStyle(DSButtonStyle(kind: .secondary))
                    if geo.isAvailable {
                        Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([geo.directory]) }
                            .buttonStyle(DSButtonStyle(kind: .ghost))
                    }
                    Spacer()
                }
            }
            if let message = geo.message {
                GroupRow {
                    Text(message.text).dsFont(.xs).foregroundStyle(message.isError ? DS.Palette.error : DS.Palette.success)
                }
            }
        }

        Text(GeoDatabaseController.attribution)
            .dsFont(.xs)
            .foregroundStyle(DS.Palette.textTertiary)
    }

    private func title(_ edition: String) -> String {
        if edition.hasSuffix("-City") { return "城市库" }
        if edition.hasSuffix("-Country") { return "国家库" }
        if edition.hasSuffix("-ASN") { return "ASN 库" }
        return edition
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "mmdb") ?? .data]
        panel.allowsMultipleSelection = true
        panel.message = "选择 GeoLite2 City / Country / ASN 的 .mmdb 文件"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { model.geo.importDatabase(from: url) }
    }
}

// MARK: - 散热与防休眠

/// 放在“温度与风扇”页底部
struct FanSafetySettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings

        SettingsGroup(caption: "风扇设置") {
            GroupRow(showsDivider: false) {
                SettingRow(title: "安全温度", subtitle: "自定义转速时，CPU 达到该温度自动恢复系统控制") {
                    SegmentedControl(selection: $settings.fanSafetyTemperature,
                                     options: AppSettings.fanSafetyOptions.map { ($0, "\($0)°C") })
                        .frame(width: DS.Size.sidebarWidth + DS.Space.s12)
                }
            }
        }
    }
}

/// 放在“防休眠”页底部
struct LidBatterySettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings

        SettingsGroup(caption: "合盖运行设置") {
            GroupRow(showsDivider: false) {
                SettingRow(title: "电量下限", subtitle: "使用电池且电量低于该值时，自动关闭合盖运行") {
                    SegmentedControl(selection: $settings.lidModeBatteryFloor,
                                     options: AppSettings.batteryFloorOptions.map { ($0, "\($0)%") })
                        .frame(width: DS.Size.sidebarWidth + DS.Space.s12)
                }
            }
        }
    }
}

// MARK: - 辅助工具

struct HelperSettings: View {
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

struct AboutSettings: View {
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
