import AppKit
import Localization
import SwiftUI

/// 出口与分流窗口。打开期间检测器盯着网络环境，关闭后停止
@MainActor
final class EgressWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    private lazy var content = WindowContent { [model] in NSHostingView(rootView: EgressWindowView().environment(model)) }
    var onVisibilityChange: ((Bool) -> Void)?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    /// windowWillClose 时窗口还算可见，所以自己记开关状态
    private(set) var isVisible = false

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        content.install(in: window)
        if !isVisible {
            isVisible = true
            model.egress.windowDidOpen()
            onVisibilityChange?(true)
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: DS.Size.egressWindowWidth, height: DS.Size.egressWindowHeight),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = tr("出口与分流")
        WindowChrome.apply(to: window)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = NSSize(width: DS.Size.panelWidth - DS.Space.s16, height: DS.Size.panelMinHeight * 1.5)
        // 第一次打开居中，之后沿用用户调整过的位置与大小
        if !window.setFrameUsingName("OpenStatsEgressWindow") { window.center() }
        window.setFrameAutosaveName("OpenStatsEgressWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        isVisible = false
        model.egress.windowDidClose()
        onVisibilityChange?(false)
        if let window { content.release(from: window) }
    }

    /// 被完全挡住、在别的桌面或应用被隐藏时暂停轮询，重新露出来时恢复
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard isVisible, let window else { return }
        model.egress.windowOcclusionChanged(visible: window.occlusionState.contains(.visible))
    }
}
