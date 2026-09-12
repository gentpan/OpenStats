import AppKit
import Metrics
import SwiftUI

public struct PanelRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            PanelHeader()
                .padding(DS.Space.s3)

            HairlineDivider()

            Group {
                switch model.settings.panelTab {
                case .overview: OverviewPage()
                case .processes: ProcessesPage()
                case .thermal: ThermalPage()
                case .keepAwake: KeepAwakePage()
                case .cleaner: CleanerPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: isSnapshot ? nil : .infinity, alignment: .top)
        }
        .frame(width: DS.Size.panelWidth)
        .frame(maxHeight: isSnapshot ? nil : .infinity, alignment: .top)
        .fixedSize(horizontal: false, vertical: isSnapshot)
        .background {
            // 开启液态玻璃时由窗口底板提供背景，否则画浅色 / 深色实色背景
            if isSnapshot || !model.settings.panelGlass {
                RoundedRectangle(cornerRadius: DS.Radius.xl).fill(DS.Palette.background)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.xl).strokeBorder(DS.Palette.border, lineWidth: DS.Size.stroke)
        }
    }
}

private struct PanelHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings

        HStack(spacing: DS.Space.s3) {
            AppGlyph()
            VStack(alignment: .leading, spacing: 0) {
                Text("OpenStats")
                    .dsFont(.base, weight: .semibold)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text("状态栏监控")
                    .dsFont(.xs)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .fixedSize()

            Spacer(minLength: DS.Space.s3)

            SegmentedControl(selection: $settings.panelTab,
                             options: PanelTab.allCases.map { ($0, $0.title) })
                .frame(width: DS.Size.tabsWidth)

            Spacer(minLength: DS.Space.s3)

            HStack(spacing: DS.Space.s1) {
                if model.keepAwake.isActive {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: DS.TextSize.sm.rawValue, weight: .semibold))
                        .foregroundStyle(DS.Palette.primary)
                        .frame(width: DS.Size.controlHeight)
                        .help("防休眠已开启")
                }
                ThemeToggle()
                IconButton(systemName: "gearshape", help: "设置") { model.openSettings() }
                IconButton(systemName: "power", help: "退出 OpenStats") { model.quit() }
            }
        }
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
