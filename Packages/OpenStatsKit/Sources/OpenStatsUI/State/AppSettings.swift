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
        case .cpu: "总占用，可附带迷你负载图"
        case .memory: "已用内存占比"
        case .network: "两行显示：绿点上传、蓝点下载"
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

    /// 百分比类指标可选择图形样式
    var supportsGaugeStyle: Bool { self == .cpu || self == .gpu || self == .memory }

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

public enum GaugeStyle: String, CaseIterable, Identifiable, Sendable {
    case value, bars, ring, pie, barsAndValue

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .value: "数字"
        case .bars: "柱状图"
        case .ring: "圆环"
        case .pie: "饼图"
        case .barsAndValue: "柱状+数字"
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
    /// CPU / GPU / 内存各自的菜单栏样式
    public var gaugeStyles: [MenuBarItem: GaugeStyle] {
        didSet {
            defaults.set(Dictionary(uniqueKeysWithValues: gaugeStyles.map { ($0.key.rawValue, $0.value.rawValue) }),
                         forKey: Keys.gaugeStyles)
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
        menuBarItems = Set(items ?? [.cpu])
        let storedStyles = defaults.dictionary(forKey: Keys.gaugeStyles) as? [String: String] ?? [:]
        gaugeStyles = Dictionary(uniqueKeysWithValues: storedStyles.compactMap { key, value in
            guard let item = MenuBarItem(rawValue: key), let style = GaugeStyle(rawValue: value) else { return nil }
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
    }

    /// 按固定顺序返回已启用的菜单栏项目
    var orderedMenuBarItems: [MenuBarItem] {
        MenuBarItem.allCases.filter(menuBarItems.contains)
    }

    func isEnabled(_ item: MenuBarItem) -> Bool { menuBarItems.contains(item) }

    func gaugeStyle(for item: MenuBarItem) -> GaugeStyle {
        gaugeStyles[item] ?? (item == .cpu ? .barsAndValue : .value)
    }

    func setGaugeStyle(_ style: GaugeStyle, for item: MenuBarItem) {
        gaugeStyles[item] = style
    }

    func setEnabled(_ item: MenuBarItem, _ enabled: Bool) {
        if enabled { menuBarItems.insert(item) } else { menuBarItems.remove(item) }
    }

    private enum Keys {
        static let menuBarItems = "menuBarItems"
        static let gaugeStyles = "gaugeStyles"
        static let refreshSeconds = "refreshSeconds"
        static let colorizeHighLoad = "colorizeHighLoad"
        static let useFahrenheit = "useFahrenheit"
        static let lidModeBatteryFloor = "lidModeBatteryFloor"
        static let fanSafetyTemperature = "fanSafetyTemperature"
        static let panelTab = "panelTab"
        static let appearance = "appearance"
        static let cleanPrefersTrash = "cleanPrefersTrash"
    }
}
