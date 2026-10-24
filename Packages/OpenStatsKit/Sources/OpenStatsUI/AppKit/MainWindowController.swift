import AppKit
import SwiftUI

/// 主窗口。应用默认只在菜单栏运行，窗口开着也不占程序坞；设置里打开“在程序坞显示图标”后才出现在程序坞与 ⌘Tab 中
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    private lazy var content = WindowContent { [model] in NSHostingView(rootView: MainWindowView().environment(model)) }
    /// 从打开到关闭之间为真。应用被隐藏时 `window.isVisible` 也是假，不能拿它判断窗口还开没开着
    private var isOpen = false
    var onVisibilityChange: ((Bool) -> Void)?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    var isVisible: Bool { window?.isVisible == true }
    /// 登录窗口等系统面板挂靠用
    var nsWindow: NSWindow? { window }

    func close() {
        window?.performClose(nil)
    }

    func show(tab: PanelTab?) {
        if let tab { model.settings.panelTab = tab }
        let window = self.window ?? makeWindow()
        self.window = window
        content.install(in: window)
        if !window.isVisible {
            window.setFrame(initialFrame(for: window), display: false)
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        isOpen = true
        model.isMainWindowVisible = true
        onVisibilityChange?(true)
    }

    private func makeWindow() -> NSWindow {
        let width = DS.Size.mainWindowMinWidth
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width - DS.Size.panelWidth + DS.Size.windowDefaultContentWidth,
                                                  height: DS.Size.panelMinHeight * 2),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.title = "OpenStats"
        WindowChrome.apply(to: window)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = NSSize(width: width, height: DS.Size.panelMinHeight * 1.5)
        // 默认尺寸调大后换一个保存名，旧的小窗口尺寸不再沿用
        window.setFrameAutosaveName("OpenStatsMainWindow.v2")
        return window
    }

    /// 首次打开时按仪表盘内容高度确定窗口大小，之后沿用用户调整过的尺寸
    private func initialFrame(for window: NSWindow) -> NSRect {
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        if window.frame.height > DS.Size.panelMinHeight * 2, visible.intersects(window.frame) {
            return window.frame
        }
        let measuring = NSHostingView(rootView: MainWindowView().environment(model).environment(\.isSnapshot, true))
        let height = min(measuring.fittingSize.height, visible.height - DS.Space.s12)
        // 至少 720pt 高（屏幕放得下时），页面较短也不会开成一个小窗口
        let size = NSSize(width: min(window.frame.width, visible.width - DS.Space.s12),
                          height: min(max(height, DS.Size.windowDefaultHeight), visible.height - DS.Space.s12))
        return NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    func windowWillClose(_ notification: Notification) {
        isOpen = false
        model.isMainWindowVisible = false
        onVisibilityChange?(false)
        if let window { content.release(from: window) }
    }

    func windowDidMiniaturize(_ notification: Notification) {
        model.isMainWindowVisible = false
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        model.isMainWindowVisible = true
    }

    /// 窗口被其他窗口完全挡住、切到别的桌面、应用被隐藏（⌘H）或锁屏时，按“没在看”处理，
    /// 采样回到菜单栏需要的范围，网络页的探测与进程流量统计也随之停下；重新露出来时恢复
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard isOpen, let window, !window.isMiniaturized else { return }
        let visible = window.occlusionState.contains(.visible)
        if model.isMainWindowVisible != visible { model.isMainWindowVisible = visible }
    }
}

/// 窗口里的 SwiftUI 内容只在窗口开着时存在：关窗后拆掉，下次打开再建。
/// 只把窗口藏起来的话，整棵视图树仍随每次采样重算，页面里的 `.task` 循环也不会结束（`onDisappear` 不触发）。
/// 窗口对象本身（位置、大小、工具栏）一直留着
@MainActor
final class WindowContent {
    private let make: @MainActor () -> NSView
    /// 装进窗口的那个视图，只由窗口持有，拆掉后自动变成 nil。新建的窗口自带一个空的 contentView，不能按“有没有内容”判断
    private weak var installed: NSView?

    init(_ make: @escaping @MainActor () -> NSView) {
        self.make = make
    }

    /// 打开窗口前调用：还没装或已经拆掉就新建。返回是否新建了内容
    @discardableResult
    func install(in window: NSWindow) -> Bool {
        if let installed, window.contentView === installed { return false }
        let view = make()
        window.contentView = view
        installed = view
        return true
    }

    /// `windowWillClose` 里调用：等窗口真正收起后再拆，关闭过程中不闪空白；这期间又打开了就不拆
    func release(from window: NSWindow) {
        DispatchQueue.main.async { [weak window, weak self] in
            guard let window, !window.isVisible, !window.isMiniaturized else { return }
            window.contentView = nil
            self?.installed = nil
        }
    }
}

/// OpenStats 窗口的统一外观：透明标题栏，内容铺满整个窗口，底色与页面一致
@MainActor
enum WindowChrome {
    static func apply(to window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .dsBackground
        // 空的标准工具栏让标题栏与顶栏同高（52pt），红绿灯按钮与页面标题、右上角按钮对齐
        let toolbar = NSToolbar(identifier: "OpenStats.\(window.title)")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

}
