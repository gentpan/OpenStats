import Foundation
import Localization

/// 清理规则。目录清单参考了 Mole 的清理范围（仅参考范围，代码为独立实现）。
public enum RuleCatalog {
    public static func rules() -> [CleanRule] {
        [userCaches, logs] + browsers.map(browserRule) + [chromiumAppCaches]
            + [xcodeDerivedData, simulatorCaches, xcodeCaches, xcodeDeviceSupport, npmCache, frontendToolCaches, pythonToolCaches,
               rustDownloadCache, swiftPackageCache, xcodeArchives]
            + [incompleteDownloads, installers, trash]
    }

    // MARK: 系统

    /// 由其他规则单独处理，或清理后会影响系统功能的缓存目录
    static let excludedCacheNames: Set<String> = [
        "Google", "Firefox", "Microsoft Edge", "BraveSoftware", "Arc",
        "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
        "org.mozilla.firefox", "com.apple.Safari",
        "Vivaldi", "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "Chromium", "org.chromium.Chromium",
    ]

    static let userCaches = CleanRule(
        id: "system.caches", category: .system, title: tr("应用缓存"),
        detail: tr("~/Library/Caches 中各应用的缓存，删除后会按需重建"), symbol: "archivebox",
        checksOwnerApp: true
    ) { env in
        try children(of: env.home + "/Library/Caches").filter { url in
            let name = url.lastPathComponent
            return !name.hasPrefix("com.apple.") && !excludedCacheNames.contains(name)
        }
    }

    static let logs = CleanRule(
        id: "system.logs", category: .system, title: tr("应用日志与崩溃报告"),
        detail: tr("~/Library/Logs 中的日志和诊断报告"), symbol: "doc.text",
        checksOwnerApp: true
    ) { env in
        try children(of: env.home + "/Library/Logs")
    }

    // MARK: 浏览器

    struct Browser: Sendable {
        let id: String
        let name: String
        let bundleID: String
        /// ~/Library/Caches 下的整个缓存目录
        let cacheDirectories: [String]
        /// ~/Library/Application Support 下的用户数据目录（其中的配置目录含 Code Cache 等）
        let userDataDirectory: String?
    }

    static let browsers: [Browser] = [
        Browser(id: "chrome", name: "Chrome", bundleID: "com.google.Chrome",
                cacheDirectories: ["Google/Chrome"], userDataDirectory: "Google/Chrome"),
        Browser(id: "edge", name: "Edge", bundleID: "com.microsoft.edgemac",
                cacheDirectories: ["Microsoft Edge"], userDataDirectory: "Microsoft Edge"),
        Browser(id: "brave", name: "Brave", bundleID: "com.brave.Browser",
                cacheDirectories: ["BraveSoftware/Brave-Browser"], userDataDirectory: "BraveSoftware/Brave-Browser"),
        Browser(id: "arc", name: "Arc", bundleID: "company.thebrowser.Browser",
                cacheDirectories: ["Arc", "company.thebrowser.Browser"], userDataDirectory: "Arc/User Data"),
        Browser(id: "firefox", name: "Firefox", bundleID: "org.mozilla.firefox",
                cacheDirectories: [], userDataDirectory: nil),
        Browser(id: "safari", name: "Safari", bundleID: "com.apple.Safari",
                cacheDirectories: ["com.apple.Safari"], userDataDirectory: nil),
        Browser(id: "opera", name: "Opera", bundleID: "com.operasoftware.Opera",
                cacheDirectories: ["com.operasoftware.Opera"], userDataDirectory: nil),
        Browser(id: "vivaldi", name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi",
                cacheDirectories: ["Vivaldi", "com.vivaldi.Vivaldi"], userDataDirectory: "Vivaldi"),
        Browser(id: "chromium", name: "Chromium", bundleID: "org.chromium.Chromium",
                cacheDirectories: ["Chromium", "org.chromium.Chromium"], userDataDirectory: "Chromium"),
    ]

    /// Chromium 配置目录内可安全清理的缓存子目录
    static let chromiumProfileCaches = ["Code Cache", "GPUCache", "Service Worker/CacheStorage", "DawnCache", "GrShaderCache",
                                        "GraphiteDawnCache", "Application Cache"]

    static func browserRule(_ browser: Browser) -> CleanRule {
        CleanRule(
            id: "browser.\(browser.id)", category: .browser, title: tr("\(browser.name) 缓存"),
            detail: tr("网页缓存与脚本缓存，不涉及 Cookie、历史记录和密码"), symbol: "globe",
            blockingApps: [(browser.bundleID, browser.name)], minimumAge: 0
        ) { env in
            let fileManager = FileManager.default
            var urls = browser.cacheDirectories
                .map { URL(fileURLWithPath: env.home + "/Library/Caches/" + $0) }
            // 浏览器缓存目录本身属于 ~/Library/Caches 的子目录，逐个校验可读性
            urls = try urls.filter { url in
                guard fileManager.fileExists(atPath: url.path) else { return false }
                _ = try children(of: url.path)
                return true
            }

            if browser.id == "firefox" {
                let profiles = (try? children(of: env.home + "/Library/Caches/Firefox/Profiles")) ?? []
                urls += profiles.map { $0.appendingPathComponent("cache2") }
                    .filter { fileManager.fileExists(atPath: $0.path) }
            }

            if let userData = browser.userDataDirectory {
                let base = env.home + "/Library/Application Support/" + userData
                let profiles = ((try? children(of: base)) ?? []).filter(isChromiumProfile)
                for profile in profiles {
                    urls += chromiumProfileCaches
                        .map { profile.appendingPathComponent($0) }
                        .filter { fileManager.fileExists(atPath: $0.path) }
                }
            }
            return urls
        }
    }

    static func isChromiumProfile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard name == "Default" || name.hasPrefix("Profile ") || name == "Guest Profile" else { return false }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("Preferences").path)
    }

    // MARK: 应用缓存

    /// Chromium 内核应用在目录里会有这些缓存子目录；有其中之一，才说明这是个 Chromium / Electron 应用
    static let chromiumMarkers = ["Code Cache", "GPUCache", "DawnCache", "GrShaderCache", "GraphiteDawnCache",
                                  "DawnGraphiteCache", "DawnWebGPUCache"]
    /// 确认是 Chromium 应用之后，同一目录里这些也是可再生的缓存。单独存在时不认：`Cache` 这个名字太通用
    static let chromiumCompanions = ["Cache", "CachedData", "Service Worker/CacheStorage"]
    /// 浏览器有自己的规则（按配置目录逐个处理），不在这条通用规则里重复处理
    static let browserSupportFolders: Set<String> = ["google", "microsoft edge", "bravesoftware", "arc", "firefox", "vivaldi",
                                                     "opera software", "com.operasoftware.opera", "chromium"]

    /// Application Support 下以应用名命名的目录里的 Chromium / Electron 缓存（Slack、Discord、VS Code、Cursor、Notion 等）。
    /// 只清已知可再生的缓存子目录，登录状态、Cookie、本地数据库都不在里面；对应的应用在运行时整项跳过
    static let chromiumAppCaches = CleanRule(
        id: "apps.chromiumCaches", category: .apps, title: tr("网页内核缓存"),
        detail: tr("Slack、Discord、VS Code、Cursor 等应用的网页、脚本与着色器缓存，不碰登录状态和数据"), symbol: "macwindow",
        ownerName: applicationSupportOwner, itemLabel: applicationSupportLabel
    ) { env in
        let fileManager = FileManager.default
        func exists(_ url: URL) -> Bool { fileManager.fileExists(atPath: url.path) }
        var urls: [URL] = []
        for directory in try childrenIfExists(of: env.home + "/Library/Application Support") {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  !browserSupportFolders.contains(directory.lastPathComponent.lowercased()) else { continue }
            let markers = chromiumMarkers.map { directory.appendingPathComponent($0) }.filter(exists)
            guard !markers.isEmpty else { continue }
            urls += markers
            urls += chromiumCompanions.map { directory.appendingPathComponent($0) }.filter(exists)
        }
        return urls
    }

    /// Application Support 下一个条目属于哪个应用文件夹：`.../Application Support/<应用>/...` 里的 <应用>
    static func applicationSupportOwner(_ url: URL) -> String? {
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "Application Support"), index + 1 < parts.count else { return nil }
        return parts[index + 1]
    }

    /// “Slack › Cache”：带上所属应用，清单里才看得出是谁的
    static func applicationSupportLabel(_ url: URL) -> String {
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "Application Support"), index + 2 < parts.count else { return url.lastPathComponent }
        return parts[index + 1] + " › " + parts[(index + 2)...].joined(separator: "/")
    }

    // MARK: 开发者

    static let xcodeDerivedData = CleanRule(
        id: "developer.derivedData", category: .developer, title: tr("Xcode 编译缓存"),
        detail: tr("DerivedData，下次编译时自动重建"), symbol: "hammer",
        blockingApps: [("com.apple.dt.Xcode", "Xcode")]
    ) { env in
        try childrenIfExists(of: env.home + "/Library/Developer/Xcode/DerivedData")
    }

    static let simulatorCaches = CleanRule(
        id: "developer.simulatorCaches", category: .developer, title: tr("模拟器缓存"),
        detail: tr("CoreSimulator 的动态库与运行时缓存"), symbol: "iphone",
        blockingApps: [("com.apple.iphonesimulator", tr("模拟器"))]
    ) { env in
        try childrenIfExists(of: env.home + "/Library/Developer/CoreSimulator/Caches")
    }

    static let npmCache = CleanRule(
        id: "developer.npm", category: .developer, title: tr("npm 缓存"),
        detail: tr("~/.npm/_cacache，安装依赖时自动重新下载"), symbol: "shippingbox"
    ) { env in
        let path = env.home + "/.npm/_cacache"
        return FileManager.default.fileExists(atPath: path) ? [URL(fileURLWithPath: path)] : []
    }

    static let xcodeArchives = CleanRule(
        id: "developer.archives", category: .developer, title: tr("Xcode 归档"),
        detail: tr("打包生成的 .xcarchive，删除后无法重新符号化旧版本崩溃日志"), symbol: "archivebox.fill",
        selectedByDefault: false, policy: .trash, minimumAge: 0
    ) { env in
        try childrenIfExists(of: env.home + "/Library/Developer/Xcode/Archives")
    }

    // 以下开发工具缓存默认都不勾选：它们会让下一次构建或安装变慢，由用户自己决定
    // MARK: 开发者（Xcode）

    static let xcodeCaches = CleanRule(
        id: "developer.xcodeCaches", category: .developer, title: tr("Xcode 其他缓存"),
        detail: tr("Xcode 的缓存、Products、Interface Builder 缓存与 XCTest 设备，需要时会重新生成"), symbol: "wrench.and.screwdriver",
        selectedByDefault: false, blockingApps: [("com.apple.dt.Xcode", "Xcode"), ("com.apple.iphonesimulator", tr("模拟器"))]
    ) { env in
        var urls: [URL] = []
        let cache = env.home + "/Library/Caches/com.apple.dt.Xcode"
        if FileManager.default.fileExists(atPath: cache) { urls.append(URL(fileURLWithPath: cache)) }
        for relative in ["Library/Developer/Xcode/Products", "Library/Developer/Xcode/UserData/IB Support", "Library/Developer/XCTestDevices"] {
            urls += try childrenIfExists(of: env.home + "/" + relative)
        }
        return urls
    }

    /// 每种设备只保留最新的这么多个版本
    static let deviceSupportKeepCount = 2

    static let xcodeDeviceSupport = CleanRule(
        id: "developer.deviceSupport", category: .developer, title: tr("Xcode 设备支持文件（旧版本）"),
        detail: tr("连接设备时生成的符号文件，每个 1–3 GB。每种设备保留最新的 \(deviceSupportKeepCount) 个版本，再连接设备时会重新生成"),
        symbol: "iphone.gen3", selectedByDefault: false, blockingApps: [("com.apple.dt.Xcode", "Xcode")],
        itemLabel: { $0.deletingLastPathComponent().lastPathComponent + " › " + $0.lastPathComponent }
    ) { env in
        var urls: [URL] = []
        for platform in ["iOS", "watchOS", "tvOS", "visionOS"] {
            let versions = try childrenIfExists(of: env.home + "/Library/Developer/Xcode/\(platform) DeviceSupport")
            // 按修改时间新的在前：直接读目录项，不用会缓存的 URL 资源值
            let newestFirst = versions.sorted {
                (FileIdentity.modificationDate(of: $0.path) ?? .distantPast) > (FileIdentity.modificationDate(of: $1.path) ?? .distantPast)
            }
            urls += newestFirst.dropFirst(deviceSupportKeepCount)
        }
        return urls
    }

    // MARK: 开发者（其他工具链）

    /// 家目录下这些具体的缓存目录，存在的列出来
    static func existingItems(_ relatives: [String], home: String) -> [URL] {
        relatives.map { URL(fileURLWithPath: home + "/" + $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 清单里显示相对家目录的位置，例如 ~/.cache/vite
    static func homeRelativeLabel(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    static let frontendToolCaches = CleanRule(
        id: "developer.frontendCaches", category: .developer, title: tr("前端构建缓存"),
        detail: tr("~/.cache 下的 vite、webpack、eslint、prettier、typescript、node-gyp、electron，以及 ~/.node-gyp"),
        symbol: "shippingbox", selectedByDefault: false, itemLabel: homeRelativeLabel
    ) { env in
        existingItems([".cache/vite", ".cache/webpack", ".cache/eslint", ".cache/prettier", ".cache/typescript",
                       ".cache/node-gyp", ".cache/electron", ".node-gyp"], home: env.home)
    }

    static let pythonToolCaches = CleanRule(
        id: "developer.pythonCaches", category: .developer, title: tr("Python 工具缓存"),
        detail: tr("pip、ruff、mypy 的缓存与 pyenv 的下载缓存；虚拟环境和已安装的版本不动"),
        symbol: "chevron.left.forwardslash.chevron.right", selectedByDefault: false, itemLabel: homeRelativeLabel
    ) { env in
        existingItems([".cache/pip", ".cache/ruff", ".cache/mypy", ".pyenv/cache"], home: env.home)
    }

    static let rustDownloadCache = CleanRule(
        id: "developer.cargoCache", category: .developer, title: tr("Rust 下载缓存"),
        detail: tr("~/.cargo/registry/cache 里下载的 .crate 压缩包；已解压的源码、索引和工具链不动"),
        symbol: "gearshape.2", selectedByDefault: false, itemLabel: homeRelativeLabel
    ) { env in
        existingItems([".cargo/registry/cache"], home: env.home)
    }

    static let swiftPackageCache = CleanRule(
        id: "developer.swiftPackageCache", category: .developer, title: tr("Swift 包缓存"),
        detail: tr("~/.cache/swift-package-manager，下次解析依赖时重新下载"),
        symbol: "swift", selectedByDefault: false, itemLabel: homeRelativeLabel
    ) { env in
        existingItems([".cache/swift-package-manager"], home: env.home)
    }

    // MARK: 下载

    static let incompleteDownloads = CleanRule(
        id: "downloads.incomplete", category: .downloads, title: tr("未完成的下载"),
        detail: tr("超过 1 天未更新的 .crdownload / .part / .download"), symbol: "arrow.down.circle",
        policy: .trash, minimumAge: 86_400
    ) { env in
        try childrenIfExists(of: env.home + "/Downloads")
            .filter { ["crdownload", "part", "download"].contains($0.pathExtension.lowercased()) }
    }

    static let installers = CleanRule(
        id: "downloads.installers", category: .downloads, title: tr("安装包"),
        detail: tr("下载目录中的 .dmg / .pkg / .xip / .iso，移到废纸篓"), symbol: "shippingbox.fill",
        selectedByDefault: false, policy: .trash, minimumAge: 0
    ) { env in
        try childrenIfExists(of: env.home + "/Downloads")
            .filter { ["dmg", "pkg", "xip", "iso"].contains($0.pathExtension.lowercased()) }
    }

    // MARK: 废纸篓

    static let trash = CleanRule(
        id: "trash", category: .trash, title: tr("清空废纸篓"),
        detail: tr("永久删除废纸篓中的内容，无法恢复"), symbol: "trash",
        selectedByDefault: false, minimumAge: 0
    ) { env in
        try childrenIfExists(of: env.home + "/.Trash")
    }

    // MARK: 工具

    /// 列出目录的直接子项（不含隐藏文件）；无权限时抛出 CleanerAccessError
    static func children(of path: String) throws -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path),
                                                               includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles])
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            throw CleanerAccessError.permissionDenied
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EPERM) {
            throw CleanerAccessError.permissionDenied
        }
    }

    static func childrenIfExists(of path: String) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        return try children(of: path)
    }
}

public enum CleanerAccessError: Error, Sendable {
    case permissionDenied
}
