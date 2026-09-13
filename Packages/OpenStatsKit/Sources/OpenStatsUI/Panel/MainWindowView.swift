import AppKit
import Metrics
import SwiftUI

/// 主窗口：侧边栏、标题栏与页面在同一张底色上，不分栏着色，也不画分隔线。
/// 左侧切换页面，右侧是仪表盘、各指标详情与工具页；窗口宽高都可调整
public struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot

    public init() {}

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            MainSidebar()
                .frame(width: DS.Size.sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(alignment: .top) {
                    WindowDragArea().frame(height: DS.Size.windowHeader)
                }

            VStack(spacing: 0) {
                PageHeader()
                Group {
                    switch model.settings.panelTab {
                    case .overview: OverviewPage()
                    case .system: SystemInfoPage()
                    case .cpu: DetailPage { CPUPopover() }
                    case .gpu: DetailPage { GPUPopover() }
                    case .memory: DetailPage { MemoryPopover() }
                    case .disk: DiskPage()
                    case .network:
                        DetailPage {
                            NetworkPopover()
                            NetworkSettings()
                        }
                    case .thermal: ThermalPage()
                    case .processes: ProcessesPage()
                    case .keepAwake: KeepAwakePage()
                    case .cleaner: CleanerPage()
                    case .uninstaller: UninstallerPage()
                    case .settingsGeneral: SettingsTabPage { GeneralSettings() }
                    case .settingsMenuBar: SettingsTabPage { MenuBarSettings() }
                    case .settingsNotifications: SettingsTabPage { NotificationSettings() }
                    case .settingsHelper: SettingsTabPage { HelperSettings() }
                    case .settingsAbout: SettingsTabPage { AboutSettings() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: isSnapshot ? nil : .infinity, alignment: .top)
                // 截图时页面取自身高度：侧边栏更高时，多出的高度不能分给页面里可伸展的卡片
                .fixedSize(horizontal: false, vertical: isSnapshot)
            }
            .frame(minWidth: DS.Size.panelWidth, maxWidth: .infinity)
            .frame(maxHeight: isSnapshot ? nil : .infinity, alignment: .top)
        }
        .frame(width: isSnapshot ? DS.Size.sidebarWidth + DS.Size.panelWidth : nil)
        .fixedSize(horizontal: false, vertical: isSnapshot)
        .background(DS.Palette.background)
        // 内容延伸到透明标题栏下方，由顶栏高度留出红绿灯按钮的位置
        .ignoresSafeArea()
    }
}

/// 指标详情页：复用菜单栏弹窗的内容，显示全部区块
private struct DetailPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        PageScroll { content }
            .environment(\.isDetailPage, true)
    }
}

private struct MainSidebar: View {
    @Environment(AppModel.self) private var model

    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            // 三组导航加起来较高，窗口矮时侧边栏自己滚动，底部按钮始终可见
            if isSnapshot {
                navigation
            } else {
                ScrollView { navigation.overlayScrollers() }
                    .scrollBounceBehavior(.basedOnSize)
            }

            HStack(spacing: DS.Space.s1) {
                ThemeToggle()
                Spacer(minLength: 0)
                IconButton(systemName: "power", help: "退出 OpenStats") { model.quit() }
            }
            .padding(.leading, DS.Space.s2)
        }
        .padding(.leading, DS.Space.s1)
        .padding(.trailing, DS.Space.s3)
        // 顶部留出窗口红绿灯按钮的位置
        .padding(.top, DS.Size.windowHeader + DS.Space.s2)
        .padding(.bottom, DS.Space.s3)
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            group("监控", PanelTab.monitors)
            group("工具", PanelTab.tools)
            group("设置", PanelTab.settings)
        }
        .sidebarGlider()
        // 光条的发光向左溢出几个点，留出空间避免被滚动区域裁掉
        .padding(.leading, DS.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func badge(for tab: PanelTab) -> Tone? {
        switch tab {
        case .settingsAbout: model.updates.release != nil ? .primary : nil
        case .settingsHelper: model.helper.isReady && model.helper.isOutdated ? .warning : nil
        default: nil
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ tabs: [PanelTab]) -> some View {
        Text(title)
            .dsFont(.xs, weight: .medium)
            .foregroundStyle(DS.Palette.textTertiary)
            .padding(.horizontal, DS.Space.s2)
            .padding(.top, DS.Space.s2)
        ForEach(tabs) { tab in
            SidebarButton(title: tab.title, symbol: tab.symbol, isSelected: model.settings.panelTab == tab, badge: badge(for: tab)) {
                model.settings.panelTab = tab
            }
        }
    }
}

private struct PageHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        let tab = settings.panelTab

        HStack(spacing: DS.Space.s3) {
            // 拖动窗口的区域只覆盖标题和空白，按钮与开关不在拖动层上
            HStack(spacing: 0) {
                Text(tab.headerTitle)
                    .dsFont(.base, weight: .semibold)
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer(minLength: DS.Space.s3)
            }
            .frame(maxHeight: .infinity)
            .background(WindowDragArea())

            if model.keepAwake.isActive {
                Chip(text: "防休眠已开启", icon: "cup.and.saucer.fill", tone: .primary)
            }
            if tab == .memory { PurgeMemoryButton() }
            if let item = tab.menuBarItem {
                Text("在菜单栏显示").dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
                DSToggle(isOn: Binding(get: { settings.isEnabled(item) }, set: { settings.setEnabled(item, $0) }),
                         label: "在菜单栏显示\(item.title)")
            }
        }
        .padding(.horizontal, DS.Space.s3 + DS.Space.s1)
        .frame(height: DS.Size.windowHeader)
    }
}

/// 在浅色与深色之间切换；当前跟随系统时，切到与系统相反的那一种
private struct ThemeToggle: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        IconButton(systemName: isDark ? "sun.max" : "moon", help: isDark ? "切换到浅色" : "切换到深色") {
            model.settings.appearance = isDark ? .light : .dark
        }
    }
}

struct AppGlyph: View {
    var size: CGFloat = DS.Size.controlHeight

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
