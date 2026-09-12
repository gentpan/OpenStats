import AppKit
import SwiftUI

// 液态玻璃：macOS 26 起使用系统 Liquid Glass，更早的系统退回毛玻璃材质。
// 截图模式无法捕获窗口背后的模糊，统一改用实色。

extension View {
    @ViewBuilder
    func dsGlass<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}

/// 面板窗口的底板，SwiftUI 内容放在其中。
/// 默认是圆角裁切的普通容器，由 SwiftUI 画实色背景；开启玻璃时使用系统液态玻璃或毛玻璃
@MainActor
enum GlassBackdrop {
    /// 容器必须从内容的尺寸开始：若从 0 开始，窗口把它撑满时自动调整会把内容再放大一倍
    static func make(containing content: NSView, cornerRadius: CGFloat, glass: Bool) -> NSView {
        guard glass else {
            let container = NSView(frame: content.frame)
            container.wantsLayer = true
            container.layer?.cornerRadius = cornerRadius
            container.layer?.cornerCurve = .continuous
            container.layer?.masksToBounds = true
            content.autoresizingMask = [.width, .height]
            container.addSubview(content)
            return container
        }
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: content.frame)
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView(frame: content.frame)
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.masksToBounds = true
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        return effect
    }
}

/// 设置窗口侧边栏的半透明背景
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
