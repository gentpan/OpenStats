import AppKit
import Localization
import SwiftUI

/// 升级提示窗口：显示新版本摘要与“一键安装”
@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    private lazy var content = WindowContent { [weak self, model] in
        NSHostingView(rootView: UpdatePromptView { self?.close() }.environment(model))
    }

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        if content.install(in: window), let view = window.contentView { window.setContentSize(view.fittingSize) }
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = tr("软件更新")
        WindowChrome.apply(to: window)
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    private func close() {
        window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let window { content.release(from: window) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 正在替换应用时不允许关闭，避免用户以为已取消
        ![.verifying, .installing].contains(model.updates.phase)
    }
}
