import Foundation
import Localization

/// “系统数据”里没有被上面各条规则说清楚的大块占用：按所属应用列出大的应用数据目录，再兜底列出其余的大目录。
/// 只看不删：这些目录里可能有聊天记录、项目、登录状态，删不删由用户在访达里自己决定
extension RuleCatalog {
    /// 应用数据目录超过这个大小才列出
    static let appDataThreshold: UInt64 = 200_000_000
    /// 其余目录超过这个大小才列出
    static let largeFolderThreshold: UInt64 = 500_000_000

    // MARK: 应用数据

    static let appData = appDataRule(threshold: appDataThreshold)

    static func appDataRule(threshold: UInt64) -> CleanRule { CleanRule(
        manual: "systemData.appData", category: .systemData, title: tr("应用数据"),
        detail: tr("Application Support、沙盒容器和共享容器里超过 200 MB 的目录，按所属应用列出"), symbol: "square.stack",
        advice: tr("这里是各应用自己的数据，可能有聊天记录、项目和登录状态，OpenStats 不会删除。还在用的应用请在应用里清理；标着“没找到对应的应用”的，确认不再需要后，可以在访达里移到废纸篓。")
    ) { env in
        let owners = AppOwnerIndex(apps: env.installedApps())
        var entries: [ManualEntry] = []
        func add(_ url: URL, identifier: String, location: AppDataLocation) {
            if Task.isCancelled { return }
            let size = CleanEngine.allocatedSize(of: url)
            guard size >= threshold else { return }
            entries.append(ManualEntry(url: url, title: owners.label(for: identifier, folder: url.lastPathComponent, location: location),
                                       size: size))
        }

        let support = env.home + "/Library/Application Support"
        for url in (try? childrenIfExists(of: support)) ?? [] where isDirectory(url) {
            // 设备备份由“iPhone / iPad 备份”单独列出
            guard !appSupportExplained.contains(url.lastPathComponent) else { continue }
            add(url, identifier: url.lastPathComponent, location: .applicationSupport)
        }
        // 其他应用的容器：没有完全磁盘访问权限时去量会让系统一个个弹授权框
        guard env.hasFullDiskAccess else { return entries }
        for url in (try? childrenIfExists(of: env.home + "/Library/Containers")) ?? [] where isDirectory(url) {
            let identifier = containerIdentifier(url) ?? url.lastPathComponent
            guard !containersExplained.contains(identifier) else { continue }
            add(url, identifier: identifier, location: .container)
        }
        for url in (try? childrenIfExists(of: env.home + "/Library/Group Containers")) ?? [] where isDirectory(url) {
            add(url, identifier: url.lastPathComponent, location: .groupContainer)
        }
        return entries
    } }

    static let appSupportExplained: Set<String> = ["MobileSync"]
    /// 邮件、信息在“储存空间”里各自单独计算，不算系统数据
    static let containersExplained: Set<String> = ["com.apple.mail", "com.apple.MobileSMS", "com.apple.iChat"]

    /// 沙盒容器的目录名可能是随机的 UUID；真实的包名写在容器管理器留下的元数据里
    static func containerIdentifier(_ url: URL) -> String? {
        let metadata = url.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
        guard let size = (try? metadata.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size < 1_000_000,
              let info = NSDictionary(contentsOf: metadata) else { return nil }
        return info["MCMMetadataIdentifier"] as? String
    }

    // MARK: 其余大目录

    static let largeFolders = largeFoldersRule(threshold: largeFolderThreshold)

    static func largeFoldersRule(threshold: UInt64, shared: String = "/Users/Shared") -> CleanRule { CleanRule(
        manual: "systemData.largeFolders", category: .systemData, title: tr("其他大目录"),
        detail: tr("资源库、家目录里的隐藏目录和“共享”文件夹中，超过 500 MB、上面没有归类的目录"), symbol: "folder.badge.questionmark",
        advice: tr("这些目录不在上面的任何一类里，OpenStats 不会删除它们。点名字可以在访达中查看；确定不再需要时，请用对应的工具或手动移到废纸篓。")
    ) { env in
        var entries: [ManualEntry] = []
        for url in largeFolderCandidates(home: env.home, shared: shared) {
            if Task.isCancelled { break }
            let size = CleanEngine.allocatedSize(of: url)
            guard size >= threshold else { continue }
            entries.append(ManualEntry(url: url, title: largeFolderLabel(url, home: env.home, shared: shared), size: size))
        }
        return entries
    } }

    /// 相对家目录：已经由别的规则或“应用数据”说清楚的，或者属于用户数据、本来就不算系统数据的
    static let largeFolderSkipped: Set<String> = [
        "Library/Caches", "Library/Logs", "Library/Application Support", "Library/Containers", "Library/Group Containers",
        "Library/Mail", "Library/Messages", "Library/Mobile Documents", "Library/CloudStorage", "Library/Safari",
        "Library/Calendars", "Library/Accounts", "Library/Keychains", "Library/Cookies", "Library/HomeKit",
        "Library/Suggestions", "Library/IdentityServices", "Library/Biome", "Library/Daemon Containers",
        "Library/PersonalizationPortrait", "Library/Reminders", "Library/Photos", "Library/Android/sdk/system-images",
        "Library/iTunes", "Library/pnpm",
        "Library/Developer/Xcode/DerivedData", "Library/Developer/Xcode/Archives", "Library/Developer/Xcode/Products",
        "Library/Developer/Xcode/iOS DeviceSupport", "Library/Developer/Xcode/watchOS DeviceSupport",
        "Library/Developer/Xcode/tvOS DeviceSupport", "Library/Developer/Xcode/visionOS DeviceSupport",
        "Library/Developer/CoreSimulator/Caches", "Library/Developer/XCTestDevices",
        ".Trash", ".npm", ".gradle", ".m2", ".lmstudio", ".ollama", ".colima", ".lima", ".tart", ".bun", ".node-gyp",
        ".cache/huggingface", ".cache/lm-studio", ".cache/torch", ".cache/pip", ".cache/uv", ".cache/ruff", ".cache/mypy",
        ".cache/vite", ".cache/webpack", ".cache/eslint", ".cache/prettier", ".cache/typescript", ".cache/node-gyp",
        ".cache/electron", ".cache/swift-package-manager", ".android/avd",
    ]

    /// 这些目录本身太笼统，往下展开一层分别看
    static let largeFolderExpanded: Set<String> = [
        "Library/Developer", "Library/Developer/Xcode", "Library/Developer/CoreSimulator", "Library/Android", "Library/Android/sdk",
        ".cache", ".android",
    ]

    /// 要量的目录：资源库的子目录、家目录里的隐藏目录、~/go，以及“共享”文件夹的子目录
    static func largeFolderCandidates(home: String, shared: String = "/Users/Shared") -> [URL] {
        let manager = FileManager.default
        var results: [URL] = []
        func visit(_ relative: String) {
            guard !largeFolderSkipped.contains(relative) else { return }
            let url = URL(fileURLWithPath: home + "/" + relative)
            guard let status = FileIdentity.status(of: url.path), status.isDirectory, !status.isSymbolicLink else { return }
            if largeFolderExpanded.contains(relative) {
                for name in (try? manager.contentsOfDirectory(atPath: url.path)) ?? [] { visit(relative + "/" + name) }
            } else {
                results.append(url)
            }
        }
        for name in (try? manager.contentsOfDirectory(atPath: home + "/Library")) ?? [] { visit("Library/" + name) }
        for name in (try? manager.contentsOfDirectory(atPath: home)) ?? [] where name.hasPrefix(".") { visit(name) }
        visit("go")
        for url in (try? children(of: shared)) ?? [] {
            if let status = FileIdentity.status(of: url.path), status.isDirectory, !status.isSymbolicLink { results.append(url) }
        }
        return results
    }

    /// 常见目录说清楚是什么，其余显示位置
    static let largeFolderNames: [String: String] = [
        "Library/Metadata": tr("Spotlight 等系统索引"),
        "Library/Developer/CoreSimulator/Devices": tr("模拟器设备的数据"),
        "Library/Developer/CoreSimulator/Volumes": tr("模拟器系统版本"),
        "Library/Developer/Xcode/UserData": tr("Xcode 用户数据与预览"),
        "Library/Developer/DeveloperDiskImages": tr("Xcode 设备调试镜像"),
        ".rustup": tr("Rust 工具链（rustup）"),
        ".cargo": tr("Rust 包与工具（cargo）"),
        ".nvm": tr("Node.js 版本（nvm）"),
        ".pyenv": tr("Python 版本（pyenv）"),
        ".rbenv": tr("Ruby 版本（rbenv）"),
        ".sdkman": tr("Java 等工具版本（SDKMAN）"),
        ".conda": tr("Conda 环境"),
        ".vscode": tr("VS Code 扩展"),
        ".cursor": tr("Cursor 扩展"),
        ".docker": tr("Docker 配置与插件"),
        ".local": tr("~/.local（pipx、uv 等装的工具）"),
        ".deno": tr("Deno 缓存"),
        "Library/Android/sdk/ndk": tr("Android NDK"),
        "Library/Android/sdk/emulator": tr("Android 模拟器程序"),
        "go": tr("Go 模块与工具（~/go）"),
    ]

    static func largeFolderLabel(_ url: URL, home: String, shared: String = "/Users/Shared") -> String {
        let path = SafetyGuard.withoutPrivatePrefix(url.path)
        if path.hasPrefix(SafetyGuard.withoutPrivatePrefix(shared) + "/") { return tr("共享 › \(url.lastPathComponent)") }
        let homePath = SafetyGuard.withoutPrivatePrefix(home)
        guard path.hasPrefix(homePath + "/") else { return path }
        let relative = String(path.dropFirst(homePath.count + 1))
        let location = "~/" + relative
        guard let name = largeFolderNames[relative] else { return location }
        return name + " · " + location
    }
}

// MARK: - 归属

enum AppDataLocation {
    case applicationSupport, container, groupContainer

    var title: String {
        switch self {
        case .applicationSupport: "Application Support"
        case .container: tr("沙盒容器")
        case .groupContainer: tr("共享容器")
        }
    }
}

/// 按包名或应用名认出数据目录属于哪个已安装的应用
struct AppOwnerIndex {
    /// nil 表示没有读到已安装应用的清单：认不出时只显示目录名，不说“没找到对应的应用”
    private let byIdentifier: [String: String]?
    private let byName: [String: String]

    init(apps: [InstalledApp]?) {
        guard let apps else {
            byIdentifier = nil
            byName = [:]
            return
        }
        var identifiers: [String: String] = [:]
        var names: [String: String] = [:]
        for app in apps {
            identifiers[app.bundleIdentifier.lowercased()] = app.name
            names[app.name.lowercased()] = app.name
            names[app.url.deletingPathExtension().lastPathComponent.lowercased()] = app.name
        }
        byIdentifier = identifiers
        byName = names
    }

    enum Owner: Equatable {
        case app(String)
        case system
        /// 看起来是包名，但这台 Mac 上没有这个应用
        case missing
        case unknown
    }

    func owner(of identifier: String, location: AppDataLocation) -> Owner {
        var candidate = identifier
        if location == .groupContainer {
            // group.com.foo.bar 或 TEAMID.com.foo.bar
            if candidate.lowercased().hasPrefix("group.") {
                candidate = String(candidate.dropFirst("group.".count))
            } else if let dot = candidate.firstIndex(of: "."), candidate.distance(from: candidate.startIndex, to: dot) == 10,
                      candidate[..<dot].allSatisfy({ $0.isUppercase || $0.isNumber }) {
                candidate = String(candidate[candidate.index(after: dot)...])
            }
        }
        let lower = candidate.lowercased()
        if lower.hasPrefix("com.apple.") || lower.hasPrefix("systemgroup.com.apple.") { return .system }
        let isReverseDNS = AppUninstallIdentity.validIdentifier(candidate) != nil && candidate.split(separator: ".").count >= 3
        guard let byIdentifier else { return .unknown }

        if isReverseDNS {
            if let name = byIdentifier[lower] { return .app(name) }
            // 应用的扩展、助手的包名在应用包名后面再加一段；共享容器的组名常是应用包名的前缀
            if let match = byIdentifier.first(where: { lower.hasPrefix($0.key + ".") || $0.key.hasPrefix(lower + ".") }) {
                return .app(match.value)
            }
            // 共享容器的组名可以随意起，认不出不代表应用不在
            return location == .groupContainer ? .unknown : .missing
        }
        if let name = byName[lower] { return .app(name) }
        return .unknown
    }

    /// “微信 › 沙盒容器”“macOS › com.apple.xxx”“com.foo.bar · 没找到对应的应用”
    func label(for identifier: String, folder: String, location: AppDataLocation) -> String {
        switch owner(of: identifier, location: location) {
        case .app(let name): name + " › " + location.title
        case .system: "macOS › " + identifier
        case .missing: identifier + " · " + tr("没找到对应的应用")
        case .unknown: location.title + " › " + (identifier == folder ? folder : identifier)
        }
    }
}
