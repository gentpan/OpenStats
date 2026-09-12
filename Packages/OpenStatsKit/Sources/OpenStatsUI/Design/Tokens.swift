import AppKit
import SwiftUI

/// 设计 token。界面里的颜色、字号、间距、圆角一律从这里取值。
public enum DS {}

// MARK: - 颜色

extension DS {
    enum Palette {
        // 品牌色（单个视图内不超过 3 种）
        static let primary = Color.dynamic(light: 0x2563EB, dark: 0x3B82F6)
        static let primaryHover = Color.dynamic(light: 0x1D4ED8, dark: 0x2563EB)   // 加深约 10%
        static let secondary = Color.dynamic(light: 0x0D9488, dark: 0x2DD4BF)

        // 语义色
        static let success = Color.dynamic(light: 0x16A34A, dark: 0x22C55E)
        static let warning = Color.dynamic(light: 0xD97706, dark: 0xF59E0B)
        static let error = Color.dynamic(light: 0xDC2626, dark: 0xF87171)

        // 文字
        static let textPrimary = Color.dynamic(light: 0x111827, dark: 0xF3F4F6)
        static let textSecondary = Color.dynamic(light: 0x6B7280, dark: 0x9CA3AF)
        static let textTertiary = Color.dynamic(light: 0x9CA3AF, dark: 0x6B7280)
        static let onPrimary = Color.dynamic(light: 0xFFFFFF, dark: 0xFFFFFF)

        // 中性色（背景为实色，截图与不支持玻璃效果时使用）
        static let background = Color.dynamic(light: 0xF8F9FA, dark: 0x111315)
        // 卡片与控件使用半透明色，叠在液态玻璃上仍能透出背景
        static let surface = Color.dynamic(light: 0xFFFFFF, lightAlpha: 0.72, dark: 0x2A2D33, darkAlpha: 0.55)
        static let surfaceHover = Color.dynamic(light: 0x000000, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.07)
        static let border = Color.dynamic(light: 0x000000, lightAlpha: 0.07, dark: 0xFFFFFF, darkAlpha: 0.09)
        static let track = Color.dynamic(light: 0x000000, lightAlpha: 0.06, dark: 0xFFFFFF, darkAlpha: 0.10)
        static let neutral300 = Color.dynamic(light: 0xD1D5DB, dark: 0x3F434A)
    }
}

extension DS {
    /// 网速配色：上传绿、下载蓝，面板与菜单栏保持一致
    enum NetworkPalette {
        static let upload = NSColor.dynamic(light: 0x16A34A, dark: 0x22C55E)
        static let download = NSColor.dynamic(light: 0x2563EB, dark: 0x3B82F6)
    }
}

extension Color {
    static func dynamic(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: .dynamic(light: light, lightAlpha: lightAlpha, dark: dark, darkAlpha: darkAlpha))
    }
}

extension NSColor {
    static func dynamic(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

// MARK: - 字号 / 间距 / 圆角 / 尺寸

extension DS {
    enum TextSize: CGFloat {
        case xs = 12, sm = 14, base = 16, lg = 20, xl = 24, xxl = 32
    }

    enum Space {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s6: CGFloat = 24
        static let s8: CGFloat = 32
        static let s12: CGFloat = 48
        static let s16: CGFloat = 64
    }

    /// 层级：控件 < 卡片 < 面板/窗口
    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16   // 玻璃面板
    }

    enum Size {
        static let iconInline: CGFloat = 16
        static let iconStandalone: CGFloat = 20
        static let controlHeight: CGFloat = 32
        static let segmentHeight: CGFloat = 24
        static let switchWidth: CGFloat = 40
        static let switchHeight: CGFloat = 24
        static let switchKnob: CGFloat = 16
        static let barHeight: CGFloat = 8
        static let coreBarHeight: CGFloat = 32
        static let chartHeight: CGFloat = 48
        static let tileChart: CGFloat = 40
        static let stroke: CGFloat = 1
        static let chartLine: CGFloat = 1.5
        static let panelWidth: CGFloat = 640
        static let panelMinHeight: CGFloat = 320
        static let panelGap: CGFloat = 4
        static let tabsWidth: CGFloat = 340
        /// 三列卡片的单列宽度：(面板宽 - 两侧内边距 - 两个列间距) / 3
        static let tileWidth: CGFloat = (panelWidth - Space.s3 * 4) / 3
        static let settingsWidth: CGFloat = 720
        static let settingsHeight: CGFloat = 520
        static let settingsSidebar: CGFloat = 192
        static let valueColumn: CGFloat = 64
        static let labelColumn: CGFloat = 48
    }

    enum Shadow {
        struct Level {
            let color: Color
            let radius: CGFloat
            let y: CGFloat
        }

        static let level1 = Level(color: .black.opacity(0.08), radius: 3, y: 1)
    }

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.15)
    }

    /// 温度阈值（°C），用于着色
    enum Thermal {
        static let warm: Double = 80
        static let hot: Double = 95
        static let scaleMax: Double = 110
    }
}

// MARK: - 修饰器

extension View {
    func dsFont(_ size: DS.TextSize, weight: Font.Weight = .regular) -> some View {
        font(.system(size: size.rawValue, weight: weight))
    }

}

extension Text {
    func dsFont(_ size: DS.TextSize, weight: Font.Weight = .regular) -> Text {
        font(.system(size: size.rawValue, weight: weight))
    }
}

extension View {
    func dsShadow(_ level: DS.Shadow.Level) -> some View {
        shadow(color: level.color, radius: level.radius, x: 0, y: level.y)
    }
}
