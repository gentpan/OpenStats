import AppKit
import SwiftUI

/// 菜单栏下方的玻璃浮动面板。点击面板外部、按 Esc 或切换应用时关闭。
/// 高度按内容自动计算，屏幕放得下就不出现滚动。
@MainActor
final class StatusPanel: NSPanel {
    var onVisibilityChange: ((Bool) -> Void)?
    /// 开发调试用：固定面板，不因点击外部或失去焦点而收起
    var isPinned = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var anchor: NSRect = .zero
    private weak var anchorScreen: NSScreen?
    private var lastDismissal = Date.distantPast

    /// 面板隐藏时不保留 SwiftUI 视图，避免后台随数据刷新重绘
    private let makeContent: () -> NSView
    /// 平铺布局（不含滚动容器）的视图，只用来测量内容的自然高度
    private let makeMeasuringContent: () -> NSView
    private let usesGlass: () -> Bool

    init<Content: View, Measuring: View>(content: @escaping () -> Content, measuring: @escaping () -> Measuring,
                                         usesGlass: @escaping () -> Bool) {
        self.usesGlass = usesGlass
        makeContent = { NSHostingView(rootView: content()) }
        makeMeasuringContent = { NSHostingView(rootView: measuring()) }
        super.init(contentRect: NSRect(x: 0, y: 0, width: DS.Size.panelWidth, height: DS.Size.panelMinHeight),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        isMovable = false
    }

    override var canBecomeKey: Bool { true }

    func toggle(below anchor: NSRect, on screen: NSScreen?) {
        if isVisible {
            dismiss()
        } else if Date().timeIntervalSince(lastDismissal) > 0.3 {
            // 面板打开时点击菜单栏图标：按下时面板已因失焦关闭，松开时不应再次打开
            present(below: anchor, on: screen)
        }
    }

    func present(below anchor: NSRect, on screen: NSScreen?) {
        self.anchor = anchor
        anchorScreen = screen

        let content = makeContent()
        setFrame(targetFrame(), display: false)
        content.frame = NSRect(origin: .zero, size: frame.size)
        contentView = GlassBackdrop.make(containing: content, cornerRadius: DS.Radius.xl, glass: usesGlass())

        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
        installMonitors()
        onVisibilityChange?(true)
    }

    /// 切换标签页后重新计算高度，保持顶部对齐。
    /// 直接设置而不做窗口动画：动画期间 SwiftUI 会逐帧重排，看起来像抖动
    func refreshHeight() {
        guard isVisible else { return }
        let frame = targetFrame()
        guard abs(frame.height - self.frame.height) > 1 else { return }
        setFrame(frame, display: true)
        invalidateShadow()
    }

    func dismiss() {
        guard isVisible, !isPinned else { return }
        lastDismissal = Date()
        removeMonitors()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.orderOut(nil)
                self?.contentView = nil
                self?.alphaValue = 1
            }
        })
        onVisibilityChange?(false)
    }

    override func resignKey() {
        super.resignKey()
        // 弹出菜单时面板也会失去 key，稍后确认没有其他 key 窗口再关闭
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isVisible, !self.isKeyWindow, self.attachedSheet == nil else { return }
                if NSApp.keyWindow?.level == .popUpMenu { return }
                self.dismiss()
            }
        }
    }

    // MARK: 尺寸

    private func targetFrame() -> NSRect {
        let visible = (anchorScreen ?? NSScreen.main)?.visibleFrame ?? .zero
        let margin = DS.Space.s2
        let top = min(anchor.minY - DS.Size.panelGap, visible.maxY)
        let available = max(DS.Size.panelMinHeight, top - visible.minY - margin)

        let natural = makeMeasuringContent().fittingSize.height
        let height = min(max(natural, DS.Size.panelMinHeight), available)

        var x = anchor.midX - DS.Size.panelWidth / 2
        x = min(max(x, visible.minX + margin), visible.maxX - DS.Size.panelWidth - margin)
        return NSRect(x: x, y: top - height, width: DS.Size.panelWidth, height: height)
    }

    // MARK: 事件

    private func installMonitors() {
        removeMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            // Esc
            if event.keyCode == 53, event.window === self {
                MainActor.assumeIsolated { self?.dismiss() }
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}
