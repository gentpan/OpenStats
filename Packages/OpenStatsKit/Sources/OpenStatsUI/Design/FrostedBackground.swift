import AppKit
import SwiftUI

// MARK: - 深色磨砂

/// 系统毛玻璃材质，模糊窗口背后的桌面。固定深色外观、始终保持激活态，窗口失焦也不变成实色
struct FrostedMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension DS {
    enum Frosted {
        /// 叠在毛玻璃上的一层近黑：底层（侧栏与外圈）要比内容区更深，只隐约透出背后桌面的颜色，
        /// 背后是白色窗口时也不会泛灰
        static let windowTint = Color(nsColor: NSColor(hex: 0x050506)).opacity(0.9)
        /// 弹窗整块是深色毛玻璃，上面的卡片是更亮的半透明白
        static let popoverTint = Color(nsColor: NSColor(hex: 0x050506)).opacity(0.66)
        /// 离屏截图拍不出材质时的近似实色
        static let snapshotFill = Color(nsColor: NSColor(hex: 0x0E0E10))
    }
}

/// 深色磨砂的底板：系统毛玻璃上叠一层近黑。离屏截图拍不出材质，画近似的实色
struct FrostedBackdrop: View {
    let tint: Color
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        if isSnapshot {
            DS.Frosted.snapshotFill
        } else {
            ZStack {
                FrostedMaterial()
                tint
            }
        }
    }
}

extension View {
    /// 弹窗与主窗口的底板：深色磨砂主题下是毛玻璃加一层暗色，其他主题填 `solid` 实色
    func panelBackground<S: Shape>(_ solid: Color, in shape: S) -> some View {
        modifier(PanelBackground(solid: solid, shape: shape))
    }
}

private struct PanelBackground<S: Shape>: ViewModifier {
    let solid: Color
    let shape: S

    func body(content: Content) -> some View {
        content.background {
            if DS.isFrosted {
                FrostedBackdrop(tint: DS.Frosted.popoverTint).clipShape(shape)
            } else {
                shape.fill(solid)
            }
        }
    }
}
