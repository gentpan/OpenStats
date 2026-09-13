import AppKit
import Metrics
import SwiftUI

@MainActor
public final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private var menuBar: MenuBarController!
    private var mainWindow: MainWindowController!
    private var settingsWindow: NSWindow?
    private var workspaceObservers: [NSObjectProtocol] = []

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        menuBar = MenuBarController(model: model)
        mainWindow = MainWindowController(model: model)
        mainWindow.onVisibilityChange = { [weak self] _ in self?.updateActivationPolicy() }
        menuBar.update()

        model.openSettings = { [weak self] in self?.showSettings() }
        model.openMainWindow = { [weak self] tab in
            self?.menuBar.dismissPopovers()
            self?.mainWindow.show(tab: tab)
        }
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
        observeProbeSettings()
        applyAppearance()
        model.network.updateProbing(networkShown: model.networkShown)

        // 开发调试：--show-panel [cpu|memory|network|gpu|temperature|fan] 启动后展开并固定弹窗；--show-window 打开主窗口
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--show-panel") {
            let item = arguments.dropFirst(index + 1).first.flatMap(MenuBarItem.init(rawValue:)) ?? .network
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.menuBar.pinsNextPopover = true
                self?.menuBar.togglePopover(item)
            }
        }
        if arguments.contains("--show-window") {
            mainWindow.show(tab: nil)
        }
        // 开发调试：--explain-process <进程名> 打开进程页并用 Apple 智能解释该进程
        if let index = arguments.firstIndex(of: "--explain-process"), let name = arguments.dropFirst(index + 1).first {
            mainWindow.show(tab: .processes)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self else { return }
                let processes = self.model.store.processes
                guard let process = processes.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) ?? processes.first else { return }
                self.model.explainProcess(.init(process))
            }
        }

        let model = self.model
        Task { [weak self] in
            await model.hub.update(model.demand)
            await model.hub.start { [weak self] snapshot in
                model.handle(snapshot)
                self?.menuBar.refreshImages()
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        model.keepAwake.releaseForTermination()
        if model.fans.mode != .automatic || model.keepAwake.lidClosedActive {
            model.helper.restoreDefaultsSynchronously()
        }
    }

    /// 再次打开应用（访达或启动台）时显示主窗口
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindow.show(tab: nil) }
        return true
    }

    // MARK: 设置窗口

    private func showSettings() {
        menuBar.dismissPopovers()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: DS.Size.settingsWidth, height: DS.Size.settingsHeight),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "OpenStats 设置"
            WindowChrome.apply(to: window)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView().environment(model))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
        updateActivationPolicy()
    }

    public func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.updateActivationPolicy() }
    }

    /// 有窗口打开时显示在程序坞与 ⌘Tab 里，全部关闭后回到仅菜单栏
    private func updateActivationPolicy() {
        let hasWindow = mainWindow.isVisible || settingsWindow?.isVisible == true
        let policy: NSApplication.ActivationPolicy = hasWindow ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if hasWindow { NSApp.activate() }
    }

    // MARK: 观察

    /// 设置或可见内容变化时，更新采样范围、网络探测并重绘菜单栏
    private func observeModel() {
        withObservationTracking {
            _ = model.demand
            _ = model.settings.menuBarItems
            _ = model.settings.menuBarLayout
            _ = model.settings.menuBarStyle
            _ = model.settings.networkStyle
            _ = model.settings.styleOverrides
            _ = model.settings.colorizeHighLoad
            _ = model.settings.useFahrenheit
            _ = model.settings.hiddenPopoverSections
            _ = model.keepAwake.isActive
            _ = model.settings.appearance
            _ = model.networkShown
            _ = model.isNetworkDetailVisible
            _ = model.settings.probeEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.model.hub.update(self.model.demand)
                self.applyAppearance()
                self.menuBar.update()
                self.menuBar.refreshPopoverHeight()
                self.model.network.updateProbing(networkShown: self.model.networkShown)
                self.model.network.setDetailVisible(self.model.isNetworkDetailVisible)
                self.observeModel()
            }
        }
    }

    /// 探测目标、间隔变化时清空历史重新探测；关闭公网 IP 查询时清除已显示的结果
    private func observeProbeSettings() {
        withObservationTracking {
            _ = model.settings.probeTarget
            _ = model.settings.probeSeconds
            _ = model.settings.publicIPLookup
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.model.network.restartProbing()
                if !self.model.settings.publicIPLookup {
                    self.model.network.clearPublicAddresses()
                } else if self.model.isNetworkDetailVisible {
                    self.model.network.lookUpPublicAddresses()
                }
                self.observeProbeSettings()
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

    /// 屏幕休眠、系统睡眠、切换用户时暂停采样与探测；唤醒后重新下发风扇设置
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
                    self.menuBar.dismissPopovers()
                    self.model.network.setPaused(true, networkShown: self.model.networkShown)
                    Task { await self.model.hub.setPaused(true) }
                }
            })
        }
        for name in resumes {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.model.network.setPaused(false, networkShown: self.model.networkShown)
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
