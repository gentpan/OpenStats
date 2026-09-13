import AppKit
import SwiftUI

/// 弹窗窗口的底板：圆角裁切的普通容器，背景由 SwiftUI 内容绘制
@MainActor
enum PanelContainer {
    /// 容器必须从内容的尺寸开始：若从 0 开始，窗口把它撑满时自动调整会把内容再放大一倍
    static func make(containing content: NSView, cornerRadius: CGFloat) -> NSView {
        let container = NSView(frame: content.frame)
        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)
        return container
    }
}

/// 内容铺满标题栏后，标题栏区域由 SwiftUI 接收点击；放在顶栏背后，按住空白处可以拖动窗口
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}
