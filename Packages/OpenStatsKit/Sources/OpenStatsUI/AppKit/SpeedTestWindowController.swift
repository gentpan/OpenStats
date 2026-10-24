import AppKit
import Localization
import SwiftUI

/// 网络测速窗口。关窗时停掉还在跑的测试，不让它继续占带宽
@MainActor
final class SpeedTestWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    private lazy var content = WindowContent { [model] in NSHostingView(rootView: SpeedTestWindowView().environment(model)) }
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
            model.speedTest.windowDidOpen()
            onVisibilityChange?(true)
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: DS.Size.speedTestWindowWidth,
                                                  height: DS.Size.speedTestWindowHeight),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = tr("网络测速")
        WindowChrome.apply(to: window)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = NSSize(width: DS.Size.panelWidth - DS.Space.s16, height: DS.Size.panelMinHeight * 1.5)
        // 第一次打开居中，之后沿用用户调整过的位置与大小
        if !window.setFrameUsingName("OpenStatsSpeedTestWindow") { window.center() }
        window.setFrameAutosaveName("OpenStatsSpeedTestWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        isVisible = false
        model.speedTest.windowDidClose()
        onVisibilityChange?(false)
        if let window { content.release(from: window) }
    }

    /// 被完全挡住、在别的桌面或应用被隐藏时暂停轮询，重新露出来时恢复
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard isVisible, let window else { return }
        model.speedTest.windowOcclusionChanged(visible: window.occlusionState.contains(.visible))
    }
}
