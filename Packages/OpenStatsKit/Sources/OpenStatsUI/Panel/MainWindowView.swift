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
        HStack(spacing: 0) {
            MainSidebar()
                .frame(width: DS.Size.settingsSidebar)
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
                    case .network: DetailPage { NetworkPopover() }
                    case .thermal: ThermalPage()
                    case .processes: ProcessesPage()
                    case .keepAwake: KeepAwakePage()
                    case .cleaner: CleanerPage()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: isSnapshot ? nil : .infinity, alignment: .top)
                // 截图时页面取自身高度：侧边栏更高时，多出的高度不能分给页面里可伸展的卡片
                .fixedSize(horizontal: false, vertical: isSnapshot)
            }
            .frame(minWidth: DS.Size.panelWidth, maxWidth: .infinity)
            .frame(maxHeight: isSnapshot ? nil : .infinity, alignment: .top)
        }
        .frame(width: isSnapshot ? DS.Size.settingsSidebar + DS.Size.panelWidth : nil)
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

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            group("监控", PanelTab.monitors)
            group("工具", PanelTab.tools)

            Spacer(minLength: DS.Space.s3)

            HStack(spacing: DS.Space.s1) {
                ThemeToggle()
                IconButton(systemName: "gearshape", help: "设置") { model.openSettings() }
                Spacer(minLength: 0)
                IconButton(systemName: "power", help: "退出 OpenStats") { model.quit() }
            }
        }
        .padding(.horizontal, DS.Space.s3)
        // 顶部留出窗口红绿灯按钮的位置
        .padding(.top, DS.Size.windowHeader + DS.Space.s2)
        .padding(.bottom, DS.Space.s3)
    }

    @ViewBuilder
    private func group(_ title: String, _ tabs: [PanelTab]) -> some View {
        Text(title)
            .dsFont(.xs, weight: .medium)
            .foregroundStyle(DS.Palette.textTertiary)
            .padding(.horizontal, DS.Space.s2)
            .padding(.top, DS.Space.s2)
        ForEach(tabs) { tab in
            SidebarButton(title: tab.title, symbol: tab.symbol, isSelected: model.settings.panelTab == tab) {
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
            Text(tab.title)
                .dsFont(.base, weight: .semibold)
                .foregroundStyle(DS.Palette.textPrimary)
            Spacer(minLength: DS.Space.s3)
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
        .background(WindowDragArea())
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
