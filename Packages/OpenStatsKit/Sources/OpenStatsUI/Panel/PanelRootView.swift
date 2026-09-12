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
            // 实际面板由窗口的液态玻璃底板提供背景；平铺（测量 / 截图）模式使用实色
            if isSnapshot {
                RoundedRectangle(cornerRadius: DS.Radius.xl).fill(DS.Palette.background)
            }
        }
        .overlay {
            if isSnapshot {
                RoundedRectangle(cornerRadius: DS.Radius.xl).strokeBorder(DS.Palette.border, lineWidth: DS.Size.stroke)
            }
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

            if model.keepAwake.isActive {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: DS.TextSize.sm.rawValue, weight: .semibold))
                    .foregroundStyle(DS.Palette.primary)
                    .help("防休眠已开启")
            }
            IconButton(systemName: "gearshape", help: "设置") { model.openSettings() }
            IconButton(systemName: "power", help: "退出 OpenStats") { model.quit() }
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
