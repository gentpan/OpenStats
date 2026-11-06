import Foundation
import Localization

public enum CleanCategory: String, Sendable, CaseIterable, Identifiable {
    case system, browser, apps, large, developer, downloads, trash

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: tr("系统")
        case .browser: tr("浏览器")
        case .apps: tr("Electron 应用")
        case .large: tr("大件数据")
        case .developer: tr("开发者")
        case .downloads: tr("下载")
        case .trash: tr("废纸篓")
        }
    }
}

public enum DeletionPolicy: Sendable {
    /// 可再生的缓存与日志：直接删除，空间立即释放
    case delete
    /// 用户文件（安装包、未完成下载）：移到废纸篓，可恢复
    case trash
}

public enum SkipReason: Sendable, Equatable, Hashable {
    case appRunning(String)
    case needsFullDiskAccess
    case recentlyModified
    case protected

    public var title: String {
        switch self {
        case .appRunning(let name): tr("\(name) 正在运行")
        case .needsFullDiskAccess: tr("需要完全磁盘访问权限")
        case .recentlyModified: tr("刚刚被使用")
        case .protected: tr("受保护")
        }
    }
}

/// 扫描所需的外部环境，便于在测试中替换
public struct CleanEnvironment: Sendable {
    public var home: String
    public var runningBundleIdentifiers: @Sendable () -> Set<String>
    /// 读到的运行列表是否可信。读不到时（例如列表是空的）按“可能在运行”处理，相关条目不删
    public var runningAppsReadable: Bool
    /// 运行中应用的各种名字（小写），用来认出 Application Support 里以应用名命名的目录属于谁
    public var runningApplicationNames: @Sendable () -> Set<String>
    public var now: @Sendable () -> Date
    /// 移到废纸篓的执行方式；测试里换成桩，免得真的动用户的废纸篓
    public var trasher: any Trasher
    /// 应用程序文件夹里 root 拥有的条目（例如 macOS 安装器）要走能请求管理员授权的废纸篓；没有就和 trasher 一样
    public var interactiveTrasher: (any Trasher)?
    /// 有没有“完全磁盘访问权限”。没有时，要读其他应用容器的规则整条跳过：去读会让系统一个个弹授权框
    public var hasFullDiskAccess: Bool
    /// 应用程序文件夹；测试里换成临时目录
    public var applications: String
    /// 模拟器设备与运行时的清单（来自 simctl）；测试里换成固定数据，默认不读
    public var simulators: @Sendable () -> SimulatorInventory?

    public init(home: String = NSHomeDirectory(),
                runningBundleIdentifiers: @escaping @Sendable () -> Set<String>,
                runningAppsReadable: Bool = true,
                runningApplicationNames: @escaping @Sendable () -> Set<String> = { [] },
                now: @escaping @Sendable () -> Date = Date.init,
                trasher: any Trasher = FileManagerTrasher(),
                interactiveTrasher: (any Trasher)? = nil,
                hasFullDiskAccess: Bool = false,
                applications: String = "/Applications",
                simulators: @escaping @Sendable () -> SimulatorInventory? = { nil }) {
        self.home = home
        self.runningBundleIdentifiers = runningBundleIdentifiers
        self.runningAppsReadable = runningAppsReadable
        self.runningApplicationNames = runningApplicationNames
        self.now = now
        self.trasher = trasher
        self.interactiveTrasher = interactiveTrasher
        self.hasFullDiskAccess = hasFullDiskAccess
        self.applications = applications
        self.simulators = simulators
    }
}

/// 仅提示的规则列出的一项：大小可以由工具报告（模拟器运行时不在家目录里，量不到），没有就按磁盘占用算
public struct ManualEntry: Sendable {
    public let url: URL
    public let title: String?
    public let size: UInt64?

    public init(url: URL, title: String? = nil, size: UInt64? = nil) {
        self.url = url
        self.title = title
        self.size = size
    }
}

public struct CleanRule: Sendable, Identifiable {
    public let id: String
    public let category: CleanCategory
    public let title: String
    public let detail: String
    public let symbol: String
    public let selectedByDefault: Bool
    public let policy: DeletionPolicy
    /// 这些应用运行时整条规则跳过（例如浏览器）
    public let blockingApps: [(bundleID: String, name: String)]
    /// 条目名为反向域名（如 com.foo.bar）时，对应应用运行中则跳过该条目
    public let checksOwnerApp: Bool
    /// 最近修改过的条目视为正在使用
    public let minimumAge: TimeInterval
    /// 条目所属应用的文件夹名；对应应用在运行就跳过该条目（Application Support 里以应用名命名的目录）
    let ownerName: (@Sendable (URL) -> String?)?
    /// 清单里条目的显示名；默认是文件名，嵌套条目需要带上所属应用，例如“Slack › Cache”
    let itemLabel: (@Sendable (URL) -> String)?
    /// 要读其他应用的容器或系统保护的位置：没有完全磁盘访问权限时整条跳过，不去触发系统授权框
    public let requiresFullDiskAccess: Bool
    /// 不由我们删、只列出大小并说明怎么处理（例如要用 Docker、Ollama 自己的命令删）。非 nil 即“仅提示”
    public let manualAdvice: String?
    /// 列出候选条目（顶层文件或目录）
    let locate: @Sendable (CleanEnvironment) throws -> [URL]
    /// 仅提示的规则用它列出条目，不经过删除判断
    let inventory: (@Sendable (CleanEnvironment) throws -> [ManualEntry])?

    init(id: String, category: CleanCategory, title: String, detail: String, symbol: String,
         selectedByDefault: Bool = true, policy: DeletionPolicy = .delete,
         blockingApps: [(bundleID: String, name: String)] = [], checksOwnerApp: Bool = false,
         minimumAge: TimeInterval = 120, requiresFullDiskAccess: Bool = false,
         ownerName: (@Sendable (URL) -> String?)? = nil,
         itemLabel: (@Sendable (URL) -> String)? = nil,
         locate: @escaping @Sendable (CleanEnvironment) throws -> [URL]) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.selectedByDefault = selectedByDefault
        self.policy = policy
        self.blockingApps = blockingApps
        self.checksOwnerApp = checksOwnerApp
        self.minimumAge = minimumAge
        self.requiresFullDiskAccess = requiresFullDiskAccess
        self.ownerName = ownerName
        self.itemLabel = itemLabel
        self.locate = locate
        manualAdvice = nil
        inventory = nil
    }

    /// 仅提示：显示占用和处理办法，永远不会被勾选、不会进删除入口
    init(manual id: String, category: CleanCategory, title: String, detail: String, symbol: String, advice: String,
         requiresFullDiskAccess: Bool = false,
         inventory: @escaping @Sendable (CleanEnvironment) throws -> [ManualEntry]) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.symbol = symbol
        selectedByDefault = false
        policy = .trash
        blockingApps = []
        checksOwnerApp = false
        minimumAge = 0
        self.requiresFullDiskAccess = requiresFullDiskAccess
        ownerName = nil
        itemLabel = nil
        locate = { _ in [] }
        manualAdvice = advice
        self.inventory = inventory
    }

    public var isManual: Bool { manualAdvice != nil }
}

public struct CleanItem: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let size: UInt64
    /// 扫描时记下的身份；清理前对不上就放弃，防止预览之后路径被换成了别的东西
    public let identity: FileIdentity?
    /// 清单里显示的名字
    public let title: String

    init(url: URL, size: UInt64, identity: FileIdentity? = nil, title: String? = nil) {
        self.url = url
        self.size = size
        self.identity = identity
        self.title = title ?? url.lastPathComponent
    }
}

public struct RuleScan: Sendable, Identifiable {
    public var id: String { rule.id }
    public let rule: CleanRule
    /// 按大小降序
    public let items: [CleanItem]
    public let skippedCount: Int
    /// 整条规则被阻止的原因（浏览器运行中、缺少权限）
    public let blocked: SkipReason?

    public var totalSize: UInt64 { items.reduce(0) { $0 + $1.size } }
    /// 仅提示的规则不可清理，只显示
    public var isCleanable: Bool { blocked == nil && !items.isEmpty && !rule.isManual }
}

public struct CleanReport: Sendable {
    public var freedBytes: UInt64 = 0
    public var removedCount = 0
    public var skippedCount = 0
    public var failures: [String] = []
    /// 移到废纸篓的大小（不会立即释放）
    public var trashedBytes: UInt64 = 0
}
