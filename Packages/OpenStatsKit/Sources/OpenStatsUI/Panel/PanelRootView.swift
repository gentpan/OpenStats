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
        RoundedRectangle(cornerRadius: DS.Radius.md)
            .fill(DS.Palette.primary)
            .frame(width: size, height: size)
            .overlay {
                PulseMark()
                    .stroke(DS.Palette.onPrimary,
                            style: StrokeStyle(lineWidth: size / DS.Space.s12 * DS.Space.s1, lineCap: .round, lineJoin: .round))
                    .padding(size * 0.22)
            }
            .accessibilityHidden(true)
    }
}

/// 应用标志折线，与 scripts/make-icon.swift 中的点位一致
struct PulseMark: Shape {
    static let points: [CGPoint] = [
        CGPoint(x: 0.00, y: 0.56), CGPoint(x: 0.26, y: 0.56), CGPoint(x: 0.36, y: 0.30),
        CGPoint(x: 0.50, y: 0.80), CGPoint(x: 0.62, y: 0.40), CGPoint(x: 0.70, y: 0.56),
        CGPoint(x: 1.00, y: 0.56),
    ]

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addLines(Self.points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) })
        }
    }
}
