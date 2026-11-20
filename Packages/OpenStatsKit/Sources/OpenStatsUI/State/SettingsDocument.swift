import Foundation
import Localization

/// 同步到云端的设置文档：只含偏好，不含本机状态（当前页签、辅助工具安装状态、历史库）。
/// 枚举以原始值保存，字段全部可选：旧版本读到新字段会忽略，新版本读到旧文档不会解码失败；
/// 应用时逐项校验，不认识的值跳过
public struct SettingsDocument: Codable, Equatable, Sendable {
    public var schema: Int? = 1
    public var menuBarItems: [String]?
    public var menuBarOrder: [String]?
    public var menuBarStyle: String?
    public var networkStyle: String?
    public var styleOverrides: [String: String]?
    public var refreshSeconds: Int?
    public var colorizeHighLoad: Bool?
    public var menuBarItemSpacing: Int?
    public var cpuSharePerCore: Bool?
    public var bluetoothLowBatteryInMenuBar: Bool?
    public var useFahrenheit: Bool?
    public var menuBarTemperatureAverage: Bool?
    public var mergeTemperatureFan: Bool?
    public var rankingRows: Int?
    public var lidModeBatteryFloor: Int?
    public var fanSafetyTemperature: Int?
    public var appearance: String?
    public var showDockIcon: Bool?
    public var menuBarLayout: String?
    public var hiddenPopoverSections: [String]?
    public var probeEnabled: Bool?
    public var probeInBackground: Bool?
    public var probeTarget: String?
    public var publicIPLookup: Bool?
    public var enabledAlerts: [String]?
    public var alertCPUTemperature: Int?
    public var alertCPULoad: Int?
    public var language: String?
    public var hotKeys: [String: HotKey]?
    public var historyEnabled: Bool?
    public var autoCheckUpdates: Bool?
    public var cleanPrefersTrash: Bool?
    // 监控大屏的开关和端口不在文档里：它们决定这台 Mac 是否、在哪个端口对网络开放，不能让别的设备的设置悄悄替你改

    public init() {}
}

extension SettingsDocument {
    /// 账号页“同步的内容”那段说明里提到的字段。新增同步字段时在这里登记，并改 AccountSettings 里的说明；
    /// SettingsDocumentTests 会检查文档里的字段有没有漏登记
    static let describedFields: Set<String> = [
        // 菜单栏项目、顺序与风格
        "menuBarItems", "menuBarOrder", "menuBarStyle", "networkStyle", "styleOverrides", "menuBarLayout",
        "menuBarItemSpacing", "colorizeHighLoad", "menuBarTemperatureAverage", "mergeTemperatureFan",
        // 刷新频率、外观、语言、温度单位、程序坞图标
        "refreshSeconds", "appearance", "language", "useFahrenheit", "showDockIcon",
        // 详情弹窗的区块与排行条数
        "hiddenPopoverSections", "rankingRows",
        // 连接探测与公网 IP 查询
        "probeEnabled", "probeInBackground", "probeTarget", "publicIPLookup",
        // 通知与蓝牙低电量提示
        "enabledAlerts", "alertCPUTemperature", "alertCPULoad", "bluetoothLowBatteryInMenuBar",
        // 快捷键
        "hotKeys",
        // 风扇安全温度、合盖电量下限
        "fanSafetyTemperature", "lidModeBatteryFloor",
        // 几个开关：CPU 整机/单核、记录历史数据、自动检查更新、缓存先移到废纸篓
        "cpuSharePerCore", "historyEnabled", "autoCheckUpdates", "cleanPrefersTrash",
    ]
}

extension AppSettings {
    /// 当前设置导出成文档。读取这里列出的每一项也就登记了观察，SyncController 借此得知设置变化
    public func exportDocument() -> SettingsDocument {
        var doc = SettingsDocument()
        doc.menuBarItems = menuBarItems.map(\.rawValue).sorted()
        doc.menuBarOrder = menuBarOrder.map(\.rawValue)
        doc.menuBarStyle = menuBarStyle.rawValue
        doc.networkStyle = networkStyle.rawValue
        doc.styleOverrides = Dictionary(uniqueKeysWithValues: styleOverrides.map { ($0.key.rawValue, $0.value.rawValue) })
        doc.refreshSeconds = refreshSeconds
        doc.colorizeHighLoad = colorizeHighLoad
        doc.menuBarItemSpacing = menuBarItemSpacing
        doc.cpuSharePerCore = cpuSharePerCore
        doc.bluetoothLowBatteryInMenuBar = bluetoothLowBatteryInMenuBar
        doc.useFahrenheit = useFahrenheit
        doc.menuBarTemperatureAverage = menuBarTemperatureAverage
        doc.mergeTemperatureFan = mergeTemperatureFan
        doc.rankingRows = rankingRows
        doc.lidModeBatteryFloor = lidModeBatteryFloor
        doc.fanSafetyTemperature = fanSafetyTemperature
        doc.appearance = appearance.rawValue
        doc.showDockIcon = showDockIcon
        doc.menuBarLayout = menuBarLayout.rawValue
        doc.hiddenPopoverSections = hiddenPopoverSections.map(\.rawValue).sorted()
        doc.probeEnabled = probeEnabled
        doc.probeInBackground = probeInBackground
        doc.probeTarget = probeTarget.rawValue
        doc.publicIPLookup = publicIPLookup
        doc.enabledAlerts = enabledAlerts.map(\.rawValue).sorted()
        doc.alertCPUTemperature = alertCPUTemperature
        doc.alertCPULoad = alertCPULoad
        doc.language = language.rawValue
        doc.hotKeys = Dictionary(uniqueKeysWithValues: hotKeys.map { ($0.key.rawValue, $0.value) })
        doc.historyEnabled = historyEnabled
        doc.autoCheckUpdates = autoCheckUpdates
        doc.cleanPrefersTrash = cleanPrefersTrash
        return doc
    }

    /// 把文档套用到当前设置。只改有变化的项，避免无谓地触发持久化与界面重建
    public func apply(_ doc: SettingsDocument) {
        func assign<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>, _ value: T?) {
            guard let value, self[keyPath: keyPath] != value else { return }
            self[keyPath: keyPath] = value
        }
        func option(_ value: Int?, in options: [Int]) -> Int? {
            value.flatMap { options.contains($0) ? $0 : nil }
        }

        assign(\.menuBarItems, doc.menuBarItems.map { Set($0.compactMap(MenuBarItem.init(rawValue:))) })
        if let order = doc.menuBarOrder { setMenuBarOrder(order.compactMap(MenuBarItem.init(rawValue:))) }
        assign(\.menuBarStyle, doc.menuBarStyle.flatMap(MenuBarStyle.init(rawValue:)))
        assign(\.networkStyle, doc.networkStyle.flatMap(NetworkMenuStyle.init(rawValue:)))
        assign(\.styleOverrides, doc.styleOverrides.map { overrides in
            Dictionary(uniqueKeysWithValues: overrides.compactMap { key, value in
                guard let item = MenuBarItem(rawValue: key), let style = MenuBarStyle(rawValue: value) else { return nil }
                return (item, style)
            })
        })
        assign(\.refreshSeconds, option(doc.refreshSeconds, in: Self.refreshOptions))
        assign(\.colorizeHighLoad, doc.colorizeHighLoad)
        assign(\.menuBarItemSpacing, option(doc.menuBarItemSpacing, in: Self.menuBarSpacingOptions))
        assign(\.cpuSharePerCore, doc.cpuSharePerCore)
        assign(\.bluetoothLowBatteryInMenuBar, doc.bluetoothLowBatteryInMenuBar)
        assign(\.useFahrenheit, doc.useFahrenheit)
        assign(\.menuBarTemperatureAverage, doc.menuBarTemperatureAverage)
        assign(\.mergeTemperatureFan, doc.mergeTemperatureFan)
        assign(\.rankingRows, option(doc.rankingRows, in: Self.rankingRowOptions))
        assign(\.lidModeBatteryFloor, option(doc.lidModeBatteryFloor, in: Self.batteryFloorOptions))
        assign(\.fanSafetyTemperature, option(doc.fanSafetyTemperature, in: Self.fanSafetyOptions))
        assign(\.appearance, doc.appearance.flatMap(AppearanceMode.init(rawValue:)))
        assign(\.showDockIcon, doc.showDockIcon)
        assign(\.menuBarLayout, doc.menuBarLayout.flatMap(MenuBarLayout.init(rawValue:)))
        assign(\.hiddenPopoverSections, doc.hiddenPopoverSections.map { Set($0.compactMap(PopoverSection.init(rawValue:))) })
        assign(\.probeEnabled, doc.probeEnabled)
        assign(\.probeInBackground, doc.probeInBackground)
        assign(\.probeTarget, doc.probeTarget.flatMap(ProbeTarget.init(rawValue:)))
        assign(\.publicIPLookup, doc.publicIPLookup)
        assign(\.enabledAlerts, doc.enabledAlerts.map { Set($0.compactMap(AlertKind.init(rawValue:))) })
        assign(\.alertCPUTemperature, option(doc.alertCPUTemperature, in: Self.alertTemperatureOptions))
        assign(\.alertCPULoad, option(doc.alertCPULoad, in: Self.alertLoadOptions))
        assign(\.language, doc.language.flatMap(AppLanguage.init(rawValue:)))
        assign(\.hotKeys, doc.hotKeys.map { stored in
            Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
                HotKeyAction(rawValue: key).map { ($0, value) }
            })
        })
        assign(\.historyEnabled, doc.historyEnabled)
        assign(\.autoCheckUpdates, doc.autoCheckUpdates)
        assign(\.cleanPrefersTrash, doc.cleanPrefersTrash)
    }

    /// 出厂设置对应的文档：用一个空的 defaults 域构造一次即可，不会写盘
    public static func defaultDocument() -> SettingsDocument {
        let name = "com.openstats.defaults-probe"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return AppSettings(defaults: defaults).exportDocument()
    }
}
