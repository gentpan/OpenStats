import Foundation
import Observation

public enum MenuBarItem: String, CaseIterable, Identifiable, Sendable {
    case cpu, memory, network, gpu, temperature, fan

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "内存"
        case .network: "网速"
        case .gpu: "GPU"
        case .temperature: "CPU 温度"
        case .fan: "风扇转速"
        }
    }

    var subtitle: String {
        switch self {
        case .cpu: "总占用"
        case .memory: "已用内存占比"
        case .network: "上传与下载速度"
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

public enum PanelTab: String, CaseIterable, Identifiable, Sendable {
    case overview, processes, thermal, keepAwake, cleaner

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "概览"
        case .processes: "进程"
        case .thermal: "散热"
        case .keepAwake: "防休眠"
        case .cleaner: "清理"
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
    /// 面板使用液态玻璃（半透明）背景；关闭时为浅色 / 深色实色背景
    public var panelGlass: Bool {
        didSet { defaults.set(panelGlass, forKey: Keys.panelGlass) }
    }
    /// 可再生的缓存也先移到废纸篓（可恢复，但不会立即释放空间）
    public var cleanPrefersTrash: Bool {
        didSet { defaults.set(cleanPrefersTrash, forKey: Keys.cleanPrefersTrash) }
    }

    public static let refreshOptions = [1, 2, 3, 5]
    public static let batteryFloorOptions = [10, 20, 30, 40]
    public static let fanSafetyOptions = [85, 90, 95, 100]

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
        panelGlass = defaults.bool(forKey: Keys.panelGlass)
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
        static let panelGlass = "panelGlass"
    }
}
