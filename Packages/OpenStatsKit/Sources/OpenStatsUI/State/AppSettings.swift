import Foundation
import Observation

public enum MenuBarItem: String, CaseIterable, Identifiable, Sendable {
    case cpu, memory, network, gpu, temperature, fan

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "内存"
        case .network: "网络"
        case .gpu: "GPU"
        case .temperature: "CPU 温度"
        case .fan: "风扇转速"
        }
    }

    var subtitle: String {
        switch self {
        case .cpu: "总占用"
        case .memory: "已用内存占比"
        case .network: "上传与下载速度、IP 地址、DNS"
        case .gpu: "GPU 占用"
        case .temperature: "CPU 核心最高温度"
        case .fan: "转速最高的风扇"
        }
    }

    /// 菜单栏上方的小标签
    var menuBarLabel: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "RAM"
        case .network: "NET"
        case .gpu: "GPU"
        case .temperature: "TEMP"
        case .fan: "FAN"
        }
    }

    /// 详情弹窗标题
    var popoverTitle: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "内存"
        case .network: "网络"
        case .gpu: "GPU"
        case .temperature: "温度"
        case .fan: "风扇"
        }
    }

    /// 点击该项弹出的详情里可以显示的内容，按显示顺序排列
    var popoverSections: [PopoverSection] {
        switch self {
        case .cpu: [.cpuHeatmap, .cpuClusters, .cpuLoadAverage, .cpuApps]
        case .memory: [.memoryWaterline, .memoryCompression, .memoryApps]
        case .network: [.networkHistory, .networkProbe, .networkInterface, .networkAddresses, .networkDNS, .networkProcesses]
        case .gpu: [.gpuHistory, .gpuDetails]
        case .temperature: [.thermalSensors, .thermalFans, .thermalPower]
        case .fan: [.thermalFans, .thermalSensors, .thermalPower]
        }
    }

    /// 可以单独指定风格的指标（网速有自己的样式）
    var supportsStyleOverride: Bool { self != .network }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "arrow.up.arrow.down"
        case .gpu: "square.3.layers.3d"
        case .temperature: "thermometer.medium"
        case .fan: "fan"
        }
    }
}

/// 详情弹窗里可以单独隐藏的区块
public enum PopoverSection: String, CaseIterable, Identifiable, Sendable {
    case cpuHeatmap, cpuClusters, cpuLoadAverage, cpuApps
    case memoryWaterline, memoryCompression, memoryApps
    case networkHistory, networkProbe, networkInterface, networkAddresses, networkDNS, networkProcesses
    case gpuHistory, gpuDetails
    case thermalSensors, thermalFans, thermalPower

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .cpuHeatmap: "核心热力图"
        case .cpuClusters: "核心分工"
        case .cpuLoadAverage: "排队程度"
        case .cpuApps, .memoryApps: "按应用汇总"
        case .networkProcesses: "高占用进程"
        case .memoryWaterline: "内存水位"
        case .memoryCompression: "压缩与交换"
        case .networkHistory: "流量历史"
        case .networkProbe: "连接探测"
        case .networkInterface: "接口"
        case .networkAddresses: "IP 地址"
        case .networkDNS: "DNS"
        case .gpuHistory: "使用历史"
        case .gpuDetails: "显卡信息"
        case .thermalSensors: "温度"
        case .thermalFans: "风扇"
        case .thermalPower: "功耗"
        }
    }
}

/// 菜单栏布局
public enum MenuBarLayout: String, CaseIterable, Identifiable, Sendable {
    /// 每个指标一个图标，点击弹出该项详情
    case separate
    /// 所有指标合成一个图标，点击打开主窗口
    case combined

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .separate: "每项独立"
        case .combined: "合并为一个"
        }
    }
}

/// 连接探测的目标
public enum ProbeTarget: String, CaseIterable, Identifiable, Sendable {
    case cloudflare, google, aliyun, tencent, gateway

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .cloudflare: "Cloudflare（1.1.1.1）"
        case .google: "Google（8.8.8.8）"
        case .aliyun: "阿里云（223.5.5.5）"
        case .tencent: "腾讯（119.29.29.29）"
        case .gateway: "路由器（网关）"
        }
    }

    /// 网关地址随网络变化，由调用方传入
    func address(router: String?) -> String? {
        switch self {
        case .cloudflare: "1.1.1.1"
        case .google: "8.8.8.8"
        case .aliyun: "223.5.5.5"
        case .tencent: "119.29.29.29"
        case .gateway: router
        }
    }
}

/// 菜单栏风格：一种风格统一套用到所有指标，风格内部的排版保持一致
public enum MenuBarStyle: String, CaseIterable, Identifiable, Sendable {
    case stacked, inline, icon, ring, pie, history, meter, dot

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .stacked: "双行文字"
        case .inline: "单行文字"
        case .icon: "图标"
        case .ring: "圆环"
        case .pie: "饼图"
        case .history: "柱状历史"
        case .meter: "电量条"
        case .dot: "状态圆点"
        }
    }

    var detail: String {
        switch self {
        case .stacked: "小标签在上、数值在下，最紧凑"
        case .inline: "标签与数值同一行，最易读"
        case .icon: "用系统图标代替文字标签"
        case .ring: "圆环表示当前占用比例"
        case .pie: "饼图表示当前占用比例"
        case .history: "10 根柱子是最近 10 次采样（约 20 秒）的变化"
        case .meter: "竖向电量条表示当前占用比例"
        case .dot: "绿色正常、橙色偏高（60% 以上）、红色很高（85% 以上）"
        }
    }
}

public enum NetworkMenuStyle: String, CaseIterable, Identifiable, Sendable {
    case dots, arrows, inline

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .dots: "双行圆点"
        case .arrows: "双行箭头"
        case .inline: "单行"
        }
    }
}

public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

/// 主窗口侧边栏的页面
public enum PanelTab: String, CaseIterable, Identifiable, Sendable {
    case overview, system, history, cpu, gpu, memory, disk, network, thermal, processes, keepAwake, cleaner, uninstaller, startupItems
    case settingsGeneral, settingsMenuBar, settingsNotifications, settingsHelper, settingsAbout

    public var id: String { rawValue }

    static let monitors: [PanelTab] = [.overview, .system, .history, .cpu, .gpu, .memory, .disk, .network, .thermal]
    static let tools: [PanelTab] = [.processes, .startupItems, .keepAwake, .cleaner, .uninstaller]
    static let settings: [PanelTab] = [.settingsGeneral, .settingsMenuBar, .settingsNotifications, .settingsHelper, .settingsAbout]

    var isSettings: Bool { Self.settings.contains(self) }

    /// 页面顶栏的标题：设置页带上分组名
    var headerTitle: String { isSettings ? "设置 · \(title)" : title }

    var title: String {
        switch self {
        case .overview: "仪表盘"
        case .system: "本机信息"
        case .history: "历史"
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "内存"
        case .disk: "磁盘"
        case .network: "网络"
        case .thermal: "温度与风扇"
        case .processes: "进程"
        case .keepAwake: "防休眠"
        case .cleaner: "清理"
        case .uninstaller: "卸载应用"
        case .startupItems: "启动项"
        case .settingsGeneral: "通用"
        case .settingsMenuBar: "菜单栏"
        case .settingsNotifications: "通知"
        case .settingsHelper: "辅助工具"
        case .settingsAbout: "关于"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .system: "laptopcomputer"
        case .history: "clock.arrow.circlepath"
        case .cpu: "cpu"
        case .gpu: "square.3.layers.3d"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .thermal: "fan"
        case .processes: "list.bullet.rectangle"
        case .keepAwake: "cup.and.saucer"
        case .cleaner: "sparkles"
        case .uninstaller: "trash"
        case .startupItems: "power"
        case .settingsGeneral: "gearshape"
        case .settingsMenuBar: "menubar.rectangle"
        case .settingsNotifications: "bell.badge"
        case .settingsHelper: "lock.shield"
        case .settingsAbout: "info.circle"
        }
    }

    /// 页面对应的菜单栏项目，页面右上角可直接开关
    var menuBarItem: MenuBarItem? {
        switch self {
        case .cpu: .cpu
        case .gpu: .gpu
        case .memory: .memory
        case .network: .network
        case .thermal: .temperature
        default: nil
        }
    }

    init(item: MenuBarItem) {
        switch item {
        case .cpu: self = .cpu
        case .gpu: self = .gpu
        case .memory: self = .memory
        case .network: self = .network
        case .temperature, .fan: self = .thermal
        }
    }
}

/// UserDefaults 持久化的偏好设置
@MainActor
@Observable
public final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    public var menuBarItems: Set<MenuBarItem> {
        didSet { defaults.set(menuBarItems.map(\.rawValue).sorted(), forKey: Keys.menuBarItems) }
    }
    public var menuBarStyle: MenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle) }
    }
    public var networkStyle: NetworkMenuStyle {
        didSet { defaults.set(networkStyle.rawValue, forKey: Keys.networkStyle) }
    }
    /// 个别指标单独指定的风格；未指定的跟随 menuBarStyle
    public var styleOverrides: [MenuBarItem: MenuBarStyle] {
        didSet {
            defaults.set(Dictionary(uniqueKeysWithValues: styleOverrides.map { ($0.key.rawValue, $0.value.rawValue) }),
                         forKey: Keys.styleOverrides)
        }
    }
    public var refreshSeconds: Int {
        didSet { defaults.set(refreshSeconds, forKey: Keys.refreshSeconds) }
    }
    public var colorizeHighLoad: Bool {
        didSet { defaults.set(colorizeHighLoad, forKey: Keys.colorizeHighLoad) }
    }
    public var useFahrenheit: Bool {
        didSet { defaults.set(useFahrenheit, forKey: Keys.useFahrenheit) }
    }
    /// 电量低于该值时自动关闭“合盖运行”
    public var lidModeBatteryFloor: Int {
        didSet { defaults.set(lidModeBatteryFloor, forKey: Keys.lidModeBatteryFloor) }
    }
    /// 自定义风扇模式下 CPU 达到该温度时恢复系统控制
    public var fanSafetyTemperature: Int {
        didSet { defaults.set(fanSafetyTemperature, forKey: Keys.fanSafetyTemperature) }
    }
    public var panelTab: PanelTab {
        didSet { defaults.set(panelTab.rawValue, forKey: Keys.panelTab) }
    }
    public var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    public var menuBarLayout: MenuBarLayout {
        didSet { defaults.set(menuBarLayout.rawValue, forKey: Keys.menuBarLayout) }
    }
    /// 用户在详情弹窗里隐藏的区块
    public var hiddenPopoverSections: Set<PopoverSection> {
        didSet { defaults.set(hiddenPopoverSections.map(\.rawValue).sorted(), forKey: Keys.hiddenPopoverSections) }
    }
    public var probeEnabled: Bool {
        didSet { defaults.set(probeEnabled, forKey: Keys.probeEnabled) }
    }
    /// 网络详情关闭时，菜单栏显示网络项期间继续低频探测
    public var probeInBackground: Bool {
        didSet { defaults.set(probeInBackground, forKey: Keys.probeInBackground) }
    }
    public var probeSeconds: Int {
        didSet { defaults.set(probeSeconds, forKey: Keys.probeSeconds) }
    }
    public var probeTarget: ProbeTarget {
        didSet { defaults.set(probeTarget.rawValue, forKey: Keys.probeTarget) }
    }
    /// 打开网络详情时查询公网 IP（会访问 Cloudflare / ipify）
    public var publicIPLookup: Bool {
        didSet { defaults.set(publicIPLookup, forKey: Keys.publicIPLookup) }
    }
    /// 本地归属地库包含城市数据（GeoLite2-City，体积约为国家库的 7 倍）
    public var geoIncludeCity: Bool {
        didSet { defaults.set(geoIncludeCity, forKey: Keys.geoIncludeCity) }
    }
    /// 定期从官网检查归属地数据库更新
    public var geoAutoUpdate: Bool {
        didSet { defaults.set(geoAutoUpdate, forKey: Keys.geoAutoUpdate) }
    }
    /// 打开了系统通知的状况
    public var enabledAlerts: Set<AlertKind> {
        didSet { defaults.set(enabledAlerts.map(\.rawValue).sorted(), forKey: Keys.enabledAlerts) }
    }
    /// CPU 过热提醒的温度（摄氏度）
    public var alertCPUTemperature: Int {
        didSet { defaults.set(alertCPUTemperature, forKey: Keys.alertCPUTemperature) }
    }
    /// 每分钟把主要指标写入本机历史库
    public var historyEnabled: Bool {
        didSet { defaults.set(historyEnabled, forKey: Keys.historyEnabled) }
    }
    /// 启动时与每天检查一次新版本
    public var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: Keys.autoCheckUpdates) }
    }
    /// 可再生的缓存也先移到废纸篓（可恢复，但不会立即释放空间）
    public var cleanPrefersTrash: Bool {
        didSet { defaults.set(cleanPrefersTrash, forKey: Keys.cleanPrefersTrash) }
    }

    public static let refreshOptions = [1, 2, 3, 5]
    public static let probeOptions = [1, 2, 5]
    public static let batteryFloorOptions = [10, 20, 30, 40]
    public static let fanSafetyOptions = [85, 90, 95, 100]
    public static let alertTemperatureOptions = [85, 90, 95, 100]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let items = defaults.stringArray(forKey: Keys.menuBarItems)?.compactMap(MenuBarItem.init(rawValue:))
        menuBarItems = Set(items ?? [.cpu, .memory, .network])
        menuBarStyle = defaults.string(forKey: Keys.menuBarStyle).flatMap(MenuBarStyle.init(rawValue:)) ?? .stacked
        networkStyle = defaults.string(forKey: Keys.networkStyle).flatMap(NetworkMenuStyle.init(rawValue:)) ?? .dots
        let storedOverrides = defaults.dictionary(forKey: Keys.styleOverrides) as? [String: String] ?? [:]
        styleOverrides = Dictionary(uniqueKeysWithValues: storedOverrides.compactMap { key, value in
            guard let item = MenuBarItem(rawValue: key), let style = MenuBarStyle(rawValue: value) else { return nil }
            return (item, style)
        })
        refreshSeconds = Self.refreshOptions.contains(defaults.integer(forKey: Keys.refreshSeconds))
            ? defaults.integer(forKey: Keys.refreshSeconds) : 2
        colorizeHighLoad = defaults.bool(forKey: Keys.colorizeHighLoad)
        useFahrenheit = defaults.bool(forKey: Keys.useFahrenheit)
        lidModeBatteryFloor = Self.batteryFloorOptions.contains(defaults.integer(forKey: Keys.lidModeBatteryFloor))
            ? defaults.integer(forKey: Keys.lidModeBatteryFloor) : 20
        fanSafetyTemperature = Self.fanSafetyOptions.contains(defaults.integer(forKey: Keys.fanSafetyTemperature))
            ? defaults.integer(forKey: Keys.fanSafetyTemperature) : 95
        panelTab = defaults.string(forKey: Keys.panelTab).flatMap(PanelTab.init(rawValue:)) ?? .overview
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppearanceMode.init(rawValue:)) ?? .system
        cleanPrefersTrash = defaults.bool(forKey: Keys.cleanPrefersTrash)
        menuBarLayout = defaults.string(forKey: Keys.menuBarLayout).flatMap(MenuBarLayout.init(rawValue:)) ?? .separate
        hiddenPopoverSections = Set(defaults.stringArray(forKey: Keys.hiddenPopoverSections)?.compactMap(PopoverSection.init(rawValue:)) ?? [])
        probeEnabled = defaults.object(forKey: Keys.probeEnabled) as? Bool ?? true
        probeInBackground = defaults.object(forKey: Keys.probeInBackground) as? Bool ?? true
        probeSeconds = Self.probeOptions.contains(defaults.integer(forKey: Keys.probeSeconds))
            ? defaults.integer(forKey: Keys.probeSeconds) : 2
        probeTarget = defaults.string(forKey: Keys.probeTarget).flatMap(ProbeTarget.init(rawValue:)) ?? .cloudflare
        publicIPLookup = defaults.object(forKey: Keys.publicIPLookup) as? Bool ?? true
        geoIncludeCity = defaults.bool(forKey: Keys.geoIncludeCity)
        geoAutoUpdate = defaults.object(forKey: Keys.geoAutoUpdate) as? Bool ?? true
        autoCheckUpdates = defaults.object(forKey: Keys.autoCheckUpdates) as? Bool ?? true
        historyEnabled = defaults.object(forKey: Keys.historyEnabled) as? Bool ?? true
        enabledAlerts = Set(defaults.stringArray(forKey: Keys.enabledAlerts)?.compactMap(AlertKind.init(rawValue:)) ?? [])
        alertCPUTemperature = Self.alertTemperatureOptions.contains(defaults.integer(forKey: Keys.alertCPUTemperature))
            ? defaults.integer(forKey: Keys.alertCPUTemperature) : 95
    }

    /// 按固定顺序返回已启用的菜单栏项目
    var orderedMenuBarItems: [MenuBarItem] {
        MenuBarItem.allCases.filter(menuBarItems.contains)
    }

    func isEnabled(_ item: MenuBarItem) -> Bool { menuBarItems.contains(item) }

    func style(for item: MenuBarItem) -> MenuBarStyle {
        styleOverrides[item] ?? menuBarStyle
    }

    /// nil 表示跟随整体风格
    func setStyleOverride(_ style: MenuBarStyle?, for item: MenuBarItem) {
        styleOverrides[item] = style
    }

    func isVisible(_ section: PopoverSection) -> Bool { !hiddenPopoverSections.contains(section) }

    func setVisible(_ section: PopoverSection, _ visible: Bool) {
        if visible { hiddenPopoverSections.remove(section) } else { hiddenPopoverSections.insert(section) }
    }

    func setEnabled(_ item: MenuBarItem, _ enabled: Bool) {
        if enabled { menuBarItems.insert(item) } else { menuBarItems.remove(item) }
    }

    private enum Keys {
        static let menuBarItems = "menuBarItems"
        static let menuBarStyle = "menuBarStyle"
        static let networkStyle = "networkStyle"
        static let styleOverrides = "styleOverrides"
        static let refreshSeconds = "refreshSeconds"
        static let colorizeHighLoad = "colorizeHighLoad"
        static let useFahrenheit = "useFahrenheit"
        static let lidModeBatteryFloor = "lidModeBatteryFloor"
        static let fanSafetyTemperature = "fanSafetyTemperature"
        static let panelTab = "panelTab"
        static let appearance = "appearance"
        static let cleanPrefersTrash = "cleanPrefersTrash"
        static let menuBarLayout = "menuBarLayout"
        static let hiddenPopoverSections = "hiddenPopoverSections"
        static let probeEnabled = "probeEnabled"
        static let probeSeconds = "probeSeconds"
        static let probeInBackground = "probeInBackground"
        static let probeTarget = "probeTarget"
        static let publicIPLookup = "publicIPLookup"
        static let geoIncludeCity = "geoIncludeCity"
        static let geoAutoUpdate = "geoAutoUpdate"
        static let autoCheckUpdates = "autoCheckUpdates"
        static let historyEnabled = "historyEnabled"
        static let enabledAlerts = "enabledAlerts"
        static let alertCPUTemperature = "alertCPUTemperature"
    }
}
