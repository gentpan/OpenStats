import Foundation
import Metrics
import Observation
import ServiceManagement
import SMC

/// 应用状态总入口，注入到所有 SwiftUI 视图
@MainActor
@Observable
public final class AppModel {
    public let settings: AppSettings
    public let store: MetricsStore
    public let helper: HelperClient
    public let fans: FanController
    public let keepAwake: KeepAwakeController
    @ObservationIgnored public let hub = MetricsHub()

    public var isPanelVisible = false
    public private(set) var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    public private(set) var launchAtLoginError: String?

    @ObservationIgnored var openSettings: () -> Void = {}
    @ObservationIgnored var quit: () -> Void = {}

    public init(settings: AppSettings = AppSettings()) {
        let store = MetricsStore()
        let helper = HelperClient()
        self.settings = settings
        self.store = store
        self.helper = helper
        fans = FanController(helper: helper, store: store, settings: settings)
        keepAwake = KeepAwakeController(helper: helper, settings: settings)
    }

    /// 根据当前可见内容决定采集范围
    var demand: MetricsDemand {
        var demand = MetricsDemand()
        let tab = settings.panelTab
        let panel = isPanelVisible
        let menu = settings.menuBarItems

        demand.interval = panel ? .seconds(1) : .seconds(settings.refreshSeconds)
        demand.memory = true
        demand.network = true
        demand.gpu = (panel && tab == .overview) || menu.contains(.gpu)
        demand.disk = panel && tab == .overview
        demand.battery = (panel && (tab == .overview || tab == .keepAwake)) || keepAwake.lidClosedActive
        demand.processes = panel && (tab == .processes || tab == .overview)

        var groups = Set<TemperatureGroup>()
        if panel && tab == .overview { groups.formUnion([.cpu, .gpu]) }
        if panel && tab == .thermal { groups.formUnion(TemperatureGroup.allCases) }
        if menu.contains(.temperature) || fans.mode != .automatic { groups.insert(.cpu) }
        demand.temperatures = groups
        demand.fans = (panel && (tab == .thermal || tab == .overview)) || menu.contains(.fan) || fans.mode != .automatic
        return demand
    }

    func refreshLaunchAtLogin() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }

    /// 概览页快捷切换风扇：未安装辅助工具时跳到散热页引导安装
    func requestFanMode(_ mode: FanController.Mode) {
        guard helper.isReady else {
            settings.panelTab = .thermal
            return
        }
        Task { await fans.select(mode) }
    }

    /// 概览页快捷开关合盖运行：同时开启防休眠
    func requestLidMode(_ enabled: Bool) {
        guard helper.isReady else {
            settings.panelTab = .keepAwake
            return
        }
        Task {
            await keepAwake.setLidClosed(enabled)
            if enabled, !keepAwake.isActive { await keepAwake.start() }
        }
    }

    func handle(_ snapshot: MetricsSnapshot) {
        store.apply(snapshot)
        fans.evaluateSafety()
        keepAwake.evaluateBattery(store.battery)
    }
}
