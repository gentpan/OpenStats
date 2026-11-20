import Foundation
import Localization

public enum SafetyError: Error, Sendable, Equatable, CustomStringConvertible {
    case notAbsolute
    case traversal
    case controlCharacter
    case outsideAllowedRoots
    case isRoot
    case protectedName(String)
    case applicationSupportNotCache
    case notMacOSInstaller

    public var description: String {
        switch self {
        case .notAbsolute: tr("不是绝对路径")
        case .traversal: tr("路径包含 ..")
        case .controlCharacter: tr("路径包含控制字符")
        case .outsideAllowedRoots: tr("不在允许清理的目录内")
        case .isRoot: tr("不能删除清理目录本身")
        case .protectedName(let name): tr("受保护的项目：\(name)")
        case .applicationSupportNotCache: tr("Application Support 中只允许清理缓存目录")
        case .notMacOSInstaller: tr("应用程序文件夹里只允许清理 macOS 安装器")
        }
    }
}

/// 所有删除操作的唯一入口校验。默认拒绝，只放行白名单目录内的条目。
public struct SafetyGuard: Sendable {
    public let home: String
    /// 应用程序文件夹：只放行其中的 macOS 安装器
    public let applications: String
    /// 当前用户的临时目录：放行其中的直接子项（过期的临时文件）
    public let temporary: String?

    /// 相对家目录的允许根目录；条目必须位于其内部（不能是根目录本身）
    static let allowedRoots = [
        "Library/Caches",
        "Library/Logs",
        "Library/Application Support",
        "Library/Developer/Xcode/DerivedData",
        "Library/Developer/Xcode/Archives",
        "Library/Developer/CoreSimulator/Caches",
        "Library/Developer/Xcode/iOS DeviceSupport",
        "Library/Developer/Xcode/watchOS DeviceSupport",
        "Library/Developer/Xcode/tvOS DeviceSupport",
        "Library/Developer/Xcode/visionOS DeviceSupport",
        "Library/Developer/Xcode/Products",
        "Library/Developer/Xcode/UserData/IB Support",
        "Library/Developer/XCTestDevices",
        ".npm",
        "Downloads",
        ".Trash",
        // 大件数据：每台设备的备份、系统更新包、打开过的邮件附件副本、按模型分的下载
        "Library/Application Support/MobileSync/Backup",
        "Library/iTunes/iPhone Software Updates",
        "Library/iTunes/iPad Software Updates",
        "Library/iTunes/iPod Software Updates",
        "Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
        ".cache/huggingface/hub",
        ".lmstudio/models",
        ".cache/lm-studio/models",
        ".gradle/wrapper/dists",
        ".cache/torch/hub/checkpoints",
    ]

    /// 目录本身就可以整个清理的位置，以及它里面的内容。只列具体的工具缓存目录，不放行它们的上级（比如整个 ~/.cache），
    /// 其余目录（模型、Hugging Face、钩子缓存等）一律不碰
    static let allowedItems = [
        ".cache/vite", ".cache/webpack", ".cache/eslint", ".cache/prettier", ".cache/typescript", ".cache/node-gyp",
        ".cache/electron", ".node-gyp", ".cache/pip", ".cache/ruff", ".cache/mypy", ".pyenv/cache",
        ".cargo/registry/cache", ".cache/swift-package-manager",
        ".cache/uv", ".gradle/caches", ".bun/install/cache", "Library/pnpm/store", ".m2/repository",
    ]

    /// Application Support 内只允许删除这些名字的缓存目录（浏览器配置目录下）
    static let applicationSupportCacheNames: Set<String> = [
        "Code Cache", "GPUCache", "CacheStorage", "Cache", "CachedData", "cache2", "ShaderCache", "GrShaderCache",
        "DawnCache", "GraphiteDawnCache", "DawnGraphiteCache", "DawnWebGPUCache", "Application Cache",
    ]

    /// 路径任一段包含以下关键词即拒绝（小写匹配）
    static let protectedKeywords = [
        "keychain", "1password", "agilebits", "bitwarden", "lastpass", "dashlane", "enpass", "passwords",
        "tailscale", "wireguard", "clash", "surge", "shadowsocks", "v2ray", "nordvpn", "expressvpn", "networkextension",
        "mobile documents", "cloudkit", "cookies", "login data", "bookmarks", "history",
        "openstats",
    ]

    public init(home: String = NSHomeDirectory(), applications: String = "/Applications", temporary: String? = nil) {
        self.home = (home as NSString).standardizingPath
        self.applications = (applications as NSString).standardizingPath
        self.temporary = temporary.map(Self.withoutPrivatePrefix)
    }

    /// /private/var/folders 与 /var/folders 是同一个地方；标准化有时去掉 /private 有时不去，统一成短的写法再比较
    static func withoutPrivatePrefix(_ path: String) -> String {
        var standardized = (path as NSString).standardizingPath
        for prefix in ["/private/var/", "/private/tmp/"] where standardized.hasPrefix(prefix) {
            standardized = String(standardized.dropFirst("/private".count))
        }
        return standardized
    }

    public func validate(_ url: URL) throws {
        let raw = url.path
        guard raw.hasPrefix("/") else { throw SafetyError.notAbsolute }
        guard !url.pathComponents.contains("..") else { throw SafetyError.traversal }
        guard !raw.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw SafetyError.controlCharacter
        }
        try check(path: (raw as NSString).standardizingPath)
        // 解析符号链接（含父目录）后再检查一次：只会更严格，不会因此放行
        let resolved = url.resolvingSymlinksInPath().path
        if resolved != raw {
            try check(path: resolved)
        }
    }

    private func checkProtectedKeywords(in components: [Substring]) throws {
        for component in components {
            let lower = component.lowercased()
            if let keyword = Self.protectedKeywords.first(where: { lower.contains($0) }) {
                throw SafetyError.protectedName(keyword)
            }
        }
    }

    private func check(path: String) throws {
        // 应用程序文件夹的直接子项：只认 macOS 安装器
        if (path as NSString).deletingLastPathComponent == applications {
            guard Self.isMacOSInstaller(URL(fileURLWithPath: path)) else { throw SafetyError.notMacOSInstaller }
            return
        }

        let homePrefix = home + "/"
        guard path.hasPrefix(homePrefix) else {
            try checkTemporary(path: path)
            return
        }
        let relative = String(path.dropFirst(homePrefix.count))

        // 具体的工具缓存目录：目录本身与里面的内容都可以，但路径上任何一段都不能带受保护的关键词
        if Self.allowedItems.contains(where: { relative == $0 || relative.hasPrefix($0 + "/") }) {
            try checkProtectedKeywords(in: relative.split(separator: "/"))
            return
        }

        // 取最长的匹配：MobileSync/Backup 在 Application Support 里面，要按更具体的那条判断
        guard let root = Self.allowedRoots.filter({ relative == $0 || relative.hasPrefix($0 + "/") }).max(by: { $0.count < $1.count }) else {
            throw SafetyError.outsideAllowedRoots
        }
        guard relative != root else { throw SafetyError.isRoot }

        let inside = relative.dropFirst(root.count + 1)
        try checkProtectedKeywords(in: inside.split(separator: "/"))

        if root == "Library/Application Support" {
            let leaf = (path as NSString).lastPathComponent
            guard Self.applicationSupportCacheNames.contains(leaf) else { throw SafetyError.applicationSupportNotCache }
        }
    }

    /// 临时目录（不在家目录里时）：只放行直接子项，不放行临时目录本身和更深的内容
    private func checkTemporary(path: String) throws {
        guard let temporary else { throw SafetyError.outsideAllowedRoots }
        let candidate = Self.withoutPrivatePrefix(path)
        guard candidate != temporary else { throw SafetyError.isRoot }
        guard candidate.hasPrefix(temporary + "/") else { throw SafetyError.outsideAllowedRoots }
        let inside = candidate.dropFirst(temporary.count + 1)
        guard !inside.contains("/") else { throw SafetyError.outsideAllowedRoots }
        try checkProtectedKeywords(in: [inside])
    }

    /// “安装 macOS …”应用：文件名是 Install macOS / Install OS X 开头的 .app，包名是苹果安装助理的
    static func isMacOSInstaller(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard url.pathExtension == "app", name.hasPrefix("Install macOS ") || name.hasPrefix("Install OS X ") else { return false }
        let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        return (info?["CFBundleIdentifier"] as? String)?.hasPrefix("com.apple.InstallAssistant") == true
    }
}
