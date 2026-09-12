import AppKit
import Metrics
import SwiftUI

@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private var panel: StatusPanel!
    private var settingsWindow: NSWindow?
    private var workspaceObservers: [NSObjectProtocol] = []

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpPanel()

        model.openSettings = { [weak self] in self?.showSettings() }
        model.quit = { NSApp.terminate(nil) }
        model.helper.refreshStatus()
        model.helper.onReconnect = { [weak self] in
            Task { [weak self] in
                await self?.model.fans.reapply()
                await self?.model.keepAwake.reapply()
            }
        }

        observeWorkspace()
        observeModel()
        applyAppearance()

        // 开发调试：启动后展开并固定面板，便于测量面板打开时的资源占用
        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.togglePanel()
                self?.panel.isPinned = true
            }
        }

        let model = self.model
        Task { [weak self] in
            await model.hub.update(model.demand)
            await model.hub.start { [weak self] snapshot in
                model.handle(snapshot)
                self?.refreshStatusItem()
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        model.keepAwake.releaseForTermination()
        if model.fans.mode != .automatic || model.keepAwake.lidClosedActive {
            model.helper.restoreDefaultsSynchronously()
        }
    }

    // MARK: 菜单栏

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        refreshStatusItem()
    }

    private func refreshStatusItem() {
        statusItem.button?.image = MenuBarRenderer.image(for: model)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        guard let button = statusItem.button, let window = button.window else { return }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        panel.toggle(below: frame, on: window.screen)
    }

    private func showContextMenu() {
        panel.dismiss()
        let menu = NSMenu()
        menu.addItem(withTitle: "打开面板", action: #selector(openPanelFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "设置…", action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 OpenStats", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPanelFromMenu() { togglePanel() }
    @objc private func openSettingsFromMenu() { showSettings() }

    // MARK: 面板

    private func setUpPanel() {
        let model = self.model
        panel = StatusPanel(content: { PanelRootView().environment(model) },
                            measuring: { PanelRootView().environment(model).environment(\.isSnapshot, true) })
        panel.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            self.model.isPanelVisible = visible
            self.statusItem.button?.highlight(visible)
            if visible {
                self.model.helper.refreshStatus()
                // 首次采样到进程、电池等数据后内容会变高，稍后重新计算一次
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.panel.refreshHeight() }
            }
        }
    }

    // MARK: 设置窗口

    private func showSettings() {
        panel.dismiss()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: DS.Size.settingsWidth, height: DS.Size.settingsHeight),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "OpenStats 设置"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView().environment(model))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: 观察

    /// 设置或面板状态变化时，更新采样范围并重绘菜单栏
    private func observeModel() {
        withObservationTracking {
            _ = model.demand
            _ = model.settings.menuBarItems
            _ = model.settings.gaugeStyles
            _ = model.settings.colorizeHighLoad
            _ = model.settings.useFahrenheit
            _ = model.keepAwake.isActive
            _ = model.settings.appearance
            _ = model.settings.panelTab
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.model.hub.update(self.model.demand)
                self.applyAppearance()
                self.panel.refreshHeight()
                self.refreshStatusItem()
                self.observeModel()
            }
        }
    }

    private func applyAppearance() {
        switch model.settings.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// 屏幕休眠、系统睡眠、切换用户时暂停采样；唤醒后重新下发风扇设置
    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let pauses: [Notification.Name] = [NSWorkspace.screensDidSleepNotification,
                                           NSWorkspace.willSleepNotification,
                                           NSWorkspace.sessionDidResignActiveNotification]
        let resumes: [Notification.Name] = [NSWorkspace.screensDidWakeNotification,
                                            NSWorkspace.didWakeNotification,
                                            NSWorkspace.sessionDidBecomeActiveNotification]
        for name in pauses {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.panel.dismiss()
                    Task { await self.model.hub.setPaused(true) }
                }
            })
        }
        for name in resumes {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task {
                        await self.model.hub.setPaused(false)
                        await self.model.fans.reapply()
                    }
                }
            })
        }
    }
}

public enum OpenStatsApplication {
    @MainActor
    public static func main() {
        let app = NSApplication.shared
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
            let path = CommandLine.arguments.dropFirst(index + 1).first ?? "snapshots"
            app.setActivationPolicy(.prohibited)
            Task {
                await SnapshotRenderer.run(outputDirectory: URL(fileURLWithPath: path))
                exit(0)
            }
            app.run()
            return
        }

        let controller = AppController()
        app.delegate = controller
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(controller) {
            app.run()
        }
    }
}
