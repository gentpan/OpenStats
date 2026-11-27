import Darwin
import Foundation
import Localization

/// 一个可以卸载的应用
public struct InstalledApp: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let bundleIdentifier: String
    public let version: String?
    /// 签名团队（可能未读取）；共享容器通过真实应用组或容器记录识别。
    public let teamIdentifier: String?

    public init(url: URL, name: String, bundleIdentifier: String, version: String?, teamIdentifier: String?) {
        self.url = url
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.teamIdentifier = teamIdentifier
    }
}

/// 应用留下的文件
public struct AppLeftover: Sendable, Identifiable, Hashable {
    public enum Kind: String, Sendable, CaseIterable {
        case application, support, caches, preferences, containers, savedState, logs, webData, launchAgents
        case extensions, helpers, receipts

        public var title: String {
            switch self {
            case .application: tr("应用本体")
            case .support: tr("应用数据")
            case .caches: tr("缓存")
            case .preferences: tr("偏好设置")
            case .containers: tr("沙盒容器")
            case .savedState: tr("窗口状态")
            case .logs: tr("日志与崩溃报告")
            case .webData: tr("网页数据")
            case .launchAgents: tr("启动项与后台服务")
            case .extensions: tr("插件与扩展")
            case .helpers: tr("特权助手")
            case .receipts: tr("安装回执")
            }
        }
    }

    /// 用户级的可以移到废纸篓；系统级（/Library 等）只提示，需要管理员权限，这里不会删除
    public enum Location: String, Sendable {
        case user, system
    }

    public var id: String { url.path }
    public let url: URL
    public let kind: Kind
    public let size: UInt64
    /// 共享容器或仅按名称识别的数据，默认保留，由用户逐项选择。
    public let requiresReview: Bool
    /// 为什么认为它属于这个应用；界面悬停和诊断里显示
    public let evidence: Evidence?
    /// 扫描时的身份；移到废纸篓前对不上就放弃
    public let identity: FileIdentity?
    public let location: Location

    public init(url: URL, kind: Kind, size: UInt64, requiresReview: Bool = false,
                evidence: Evidence? = nil, identity: FileIdentity? = nil, location: Location = .user) {
        self.url = url
        self.kind = kind
        self.size = size
        self.requiresReview = requiresReview
        self.evidence = evidence
        self.identity = identity
        self.location = location
    }

    /// 认领这个文件的依据
    public struct Evidence: Sendable, Hashable {
        public enum Basis: String, Sendable {
            case bundleIdentifier, componentIdentifier, applicationGroup, containerMetadata
            case name, vendorFolder, launchAgentProgram, nativeManifest, crashReport, knownPath
        }

        public let basis: Basis
        /// 命中的标识或名称
        public let matched: String

        public init(basis: Basis, matched: String) {
            self.basis = basis
            self.matched = matched
        }

        public var summary: String {
            switch basis {
            case .bundleIdentifier: tr("包名 \(matched)")
            case .componentIdentifier: tr("内嵌组件 \(matched)")
            case .applicationGroup: tr("应用组 \(matched)")
            case .containerMetadata: tr("容器记录里的归属 \(matched)")
            case .name: tr("名称 \(matched)")
            case .vendorFolder: tr("厂商目录下的 \(matched)")
            case .launchAgentProgram: tr("启动项指向本应用：\(matched)")
            case .nativeManifest: tr("原生消息清单指向本应用：\(matched)")
            case .crashReport: tr("崩溃报告 \(matched)")
            case .knownPath: tr("已知位置 \(matched)")
            }
        }
    }
}

/// 扫描未能读取的目录单独返回，避免把不完整扫描显示为“只有应用本体”。
public struct AppUninstallScan: Sendable {
    public let items: [AppLeftover]
    public let unreadableDirectories: [URL]
    public let otherInstalledCopies: [URL]
    let identity: AppUninstallIdentity
    let applicationURL: URL
    public internal(set) var diagnostics = AppScanDiagnostics()
}

public struct AppInstallationCheck: Sendable {
    public let otherInstalledCopies: [URL]
    public let unreadableDirectories: [URL]
    public var preservesSharedData: Bool { !otherInstalledCopies.isEmpty || !unreadableDirectories.isEmpty }
}

public enum AppUninstallError: Error, Sendable, Equatable, CustomStringConvertible {
    case systemApp
    case running
    case notAnApp
    case unsafePath(String)

    public var description: String {
        switch self {
        case .systemApp: tr("系统自带的应用不能卸载")
        case .running: tr("应用正在运行，请先退出")
        case .notAnApp: tr("不是应用程序")
        case .unsafePath(let path): tr("不在可卸载的位置：\(path)")
        }
    }
}

/// 根据应用与内嵌组件的标识、容器元数据和明确路径查找残留；共享候选默认保留。
public enum AppUninstaller {
    public static func applicationDirectories(home: String = NSHomeDirectory()) -> [URL] {
        [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: home).appendingPathComponent("Applications")]
    }

    /// /Applications 与 ~/Applications 下的应用（含一层子文件夹），按名称排序
    public static func installedApps(home: String = NSHomeDirectory(), excluding excludedIdentifiers: Set<String> = []) -> [InstalledApp] {
        var unreadable: [URL] = []
        return installedApps(home: home, excluding: excludedIdentifiers, unreadable: &unreadable)
    }

    private static func installedApps(home: String, excluding excludedIdentifiers: Set<String> = [], unreadable: inout [URL]) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        let manager = FileManager.default
        func entries(_ directory: URL) -> [URL] {
            do {
                return try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            } catch {
                let failure = error as NSError
                if failure.domain != NSCocoaErrorDomain || failure.code != NSFileReadNoSuchFileError { unreadable.append(directory) }
                return []
            }
        }
        for directory in applicationDirectories(home: home) {
            for entry in entries(directory) {
                if entry.pathExtension == "app" {
                    if let app = app(at: entry) { apps.append(app) }
                } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    apps += entries(entry).filter { $0.pathExtension == "app" }.compactMap(app(at:))
                }
            }
        }
        return apps
            .filter { !excludedIdentifiers.contains($0.bundleIdentifier) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func app(at url: URL) -> InstalledApp? {
        guard url.pathExtension == "app", let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return nil }
        let name = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApp(url: url, name: name, bundleIdentifier: identifier,
                            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                            teamIdentifier: nil)
    }

    /// 系统自带与 Apple 的应用不允许卸载
    public static func validate(_ app: InstalledApp, home: String = NSHomeDirectory()) throws {
        let path = app.url.resolvingSymlinksInPath().path
        guard app.url.pathExtension == "app" else { throw AppUninstallError.notAnApp }
        if (try? app.url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw AppUninstallError.unsafePath(path) }
        if path.hasPrefix("/System/") || app.bundleIdentifier.hasPrefix("com.apple.") { throw AppUninstallError.systemApp }
        let original = app.url.standardizedFileURL.path
        let homeApplications = URL(fileURLWithPath: home).resolvingSymlinksInPath()
            .appendingPathComponent("Applications").resolvingSymlinksInPath().path + "/"
        // /Applications 和 home 以下的 Applications 不能通过解析可替换的根目录来扩大白名单。
        let applications = URL(fileURLWithPath: "/Applications")
        let inSystemApplications = original.hasPrefix("/Applications/")
            && isDirectoryWithoutSymlink(applications)
            && path.caseInsensitiveCompare(original) == .orderedSame
            && isUnredirected(app.url.deletingLastPathComponent(), home: applications.path)
        let inHomeApplications = path.hasPrefix(homeApplications) && isUnredirected(app.url, home: home)
        guard inSystemApplications || inHomeApplications else { throw AppUninstallError.unsafePath(path) }
    }

    /// `systemRoot` 是系统级残留预览读取的根；默认就是真实的 `/`，测试里换成临时目录
    public static func leftovers(for app: InstalledApp, home: String = NSHomeDirectory(),
                                 systemRoot: String = "/") -> [AppLeftover] {
        scan(for: app, home: home, systemRoot: systemRoot).items
    }

    public static func scan(for app: InstalledApp, home: String = NSHomeDirectory(),
                            systemRoot: String = "/") -> AppUninstallScan {
        var unreadable: [URL] = []
        let installed = installedApps(home: home, unreadable: &unreadable)
        return scan(for: app, home: home, identity: AppUninstallIdentity(app: app),
                    installed: installed, userCache: userCacheDirectory(home: home), userTemp: userTempDirectory(home: home),
                    unreadableInstallations: unreadable, systemRoot: systemRoot)
    }

    public static func otherInstalledCopies(of app: InstalledApp, home: String = NSHomeDirectory()) -> [URL] {
        checkOtherInstallations(of: app, home: home).otherInstalledCopies
    }

    public static func checkOtherInstallations(of app: InstalledApp, home: String = NSHomeDirectory()) -> AppInstallationCheck {
        var unreadable: [URL] = []
        let installed = installedApps(home: home, unreadable: &unreadable)
        return AppInstallationCheck(otherInstalledCopies: otherInstalledCopies(of: app, in: installed), unreadableDirectories: unreadable)
    }

    private static func otherInstalledCopies(of app: InstalledApp, in installed: [InstalledApp]) -> [URL] {
        installed.filter {
            $0.bundleIdentifier.caseInsensitiveCompare(app.bundleIdentifier) == .orderedSame
                && $0.url.resolvingSymlinksInPath().path != app.url.resolvingSymlinksInPath().path
        }.map(\.url)
    }

    /// 测试用：不读真实的系统目录
    static func leftovers(for app: InstalledApp, home: String, identity: AppUninstallIdentity,
                          systemRoot: String = "/nonexistent-openstats-system-root") -> [AppLeftover] {
        scan(for: app, home: home, identity: identity, installed: [], userCache: nil, systemRoot: systemRoot).items
    }

    static func scan(for app: InstalledApp, home: String, identity: AppUninstallIdentity,
                     installed: [InstalledApp], userCache: URL?, userTemp: URL? = nil, unreadableInstallations: [URL] = [],
                     systemRoot: String = "/") -> AppUninstallScan {
        let library = URL(fileURLWithPath: home).appendingPathComponent("Library")
        let manager = FileManager.default
        var results: [AppLeftover] = []
        var unreadable: Set<URL> = []
        var diagnostics = AppScanDiagnostics()
        var rootPaths: Set<String> = []
        var notedDirectories: Set<String> = []
        let copies = otherInstalledCopies(of: app, in: installed)

        func matches(_ name: String) -> Bool {
            identity.identifiers.contains { matchesIdentifier(name, $0) }
        }

        func auxiliaryMatch(_ name: String) -> Bool {
            matches(name) && !matchesIdentifier(name, app.bundleIdentifier)
        }

        /// 命中了哪个标识：优先报应用自己的包名，其次是内嵌组件
        func identifierEvidence(_ name: String) -> AppLeftover.Evidence? {
            let ordered = [app.bundleIdentifier] + identity.identifiers.sorted()
            guard let id = ordered.first(where: { matchesIdentifier(name, $0) }) else { return nil }
            let own = id.caseInsensitiveCompare(app.bundleIdentifier) == .orderedSame
            return AppLeftover.Evidence(basis: own ? .bundleIdentifier : .componentIdentifier, matched: id)
        }

        func nameEvidence(_ name: String) -> AppLeftover.Evidence { .init(basis: .name, matched: name) }

        // 诊断：只记“要紧的”目录——扫描根的读取情况，以及任何读不了的目录
        func note(_ directory: URL, _ state: AppScanDiagnostics.State) {
            switch state {
            case .listed, .missing: guard rootPaths.contains(directory.path) else { return }
            default: break
            }
            guard notedDirectories.insert(directory.path).inserted else { return }
            diagnostics.directories.append(.init(path: directory.path, state: state))
        }

        func reject(_ path: String, _ reason: String) {
            guard !diagnostics.rejections.contains(where: { $0.path == path }) else { return }
            diagnostics.rejections.append(.init(path: path, reason: reason))
        }

        /// 名字属于另一个已安装的应用：它的包名是本应用包名的延伸（com.google.Chrome.canary 之于 com.google.Chrome）。
        /// 前缀匹配会把它当成本应用的派生名，但那其实是别的应用的数据
        func ownerAmongOtherInstalledApps(_ name: String) -> InstalledApp? {
            installed.first { other in
                other.bundleIdentifier.count > app.bundleIdentifier.count
                    && other.bundleIdentifier.lowercased().hasPrefix(app.bundleIdentifier.lowercased() + ".")
                    && !identity.identifiers.contains(other.bundleIdentifier)
                    && matchesIdentifier(name, other.bundleIdentifier)
            }
        }

        func add(_ url: URL, _ kind: AppLeftover.Kind, review: Bool = false, evidence: AppLeftover.Evidence? = nil) {
            let path = url.standardizedFileURL.path
            if let basis = evidence?.basis, basis == .bundleIdentifier || basis == .componentIdentifier,
               let owner = ownerAmongOtherInstalledApps(url.lastPathComponent) {
                reject(path, "属于另一个已安装的应用：\(owner.name)（\(owner.bundleIdentifier)）")
                return
            }
            var information = stat()
            guard path.withCString({ stat($0, &information) }) == 0 else {
                let code = errno
                // 目录里列出了这个名字却读不到它：系统拒绝，或是悬空的链接；不存在则是固定位置没有这个文件，不算
                if code != ENOENT && code != ENOTDIR { reject(path, "无法访问（\(AppScanDiagnostics.message(for: code))）") }
                return
            }
            do {
                try validateLeftover(url, for: app, home: home, userCache: userCache, userTemp: userTemp, identity: identity)
            } catch {
                reject(path, redirectionFailure(url, home: home) ?? "未通过路径检查（不在允许扫描的目录里，或名字属于共享目录）")
                return
            }
            guard !results.contains(where: { path.hasPrefix($0.url.standardizedFileURL.path + "/") }) else { return }
            if let index = results.firstIndex(where: { $0.url.standardizedFileURL.path == path }) {
                if review && !results[index].requiresReview {
                    let item = results[index]
                    results[index] = AppLeftover(url: item.url, kind: item.kind, size: item.size, requiresReview: true,
                                                 evidence: item.evidence, identity: item.identity)
                }
                return
            }
            var requiresReview = review
            results.removeAll { item in
                if item.url.standardizedFileURL.path.hasPrefix(path + "/") { requiresReview = requiresReview || item.requiresReview; return true }
                return false
            }
            results.append(AppLeftover(url: url, kind: kind, size: CleanEngine.allocatedSize(of: url), requiresReview: requiresReview,
                                       evidence: evidence, identity: FileIdentity.capture(url)))
        }

        /// 列出目录。读不了的（权限、链接）记入诊断与“无法读取”；不存在的不算问题。
        /// `track` 为假时是试探性的探测（例如逐个厂商目录找原生消息清单），读不了也不打扰用户
        func children(_ directory: URL, base: String, track: Bool = true) -> [URL] {
            var information = stat()
            guard directory.path.withCString({ stat($0, &information) }) == 0 else {
                let code = errno
                if code == ENOENT || code == ENOTDIR {
                    note(directory, .missing)
                } else if track {
                    note(directory, .denied(AppScanDiagnostics.message(for: code)))
                    unreadable.insert(directory)
                }
                return []
            }
            if let failure = redirectionFailure(directory, home: base) {
                if track {
                    note(directory, .redirected(failure))
                    unreadable.insert(directory)
                }
                return []
            }
            do {
                let names = try manager.contentsOfDirectory(atPath: directory.path).sorted()
                note(directory, .listed(names.count))
                return names.map { directory.appendingPathComponent($0) }
            } catch {
                if track {
                    note(directory, .failed(error.localizedDescription))
                    unreadable.insert(directory)
                }
                return []
            }
        }

        func entries(_ relative: String) -> [URL] {
            let directory = library.appendingPathComponent(relative)
            rootPaths.insert(directory.path)
            // 保留调用方的 home 路径写法；FileManager 的 URL 形式可能把 /var 转成 /private/var。
            return children(directory, base: home)
        }

        func scan(_ relative: String, _ kind: AppLeftover.Kind, names: Bool = false, review: Bool = false) {
            for entry in entries(relative) {
                let name = entry.lastPathComponent
                let byIdentifier = matches(name)
                let named = names && identity.matchesName(name)
                if byIdentifier || named {
                    add(entry, kind, review: review || auxiliaryMatch(name) || (named && !byIdentifier),
                        evidence: byIdentifier ? identifierEvidence(name) : nameEvidence(name))
                }
            }
        }

        /// 只深入厂商目录一层，选择匹配的应用子项，保留厂商目录本身。
        func scanNested(_ relative: String, _ kind: AppLeftover.Kind) {
            for parent in entries(relative) {
                guard (try? parent.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      !results.contains(where: { $0.url == parent }), isUnredirected(parent, home: home) else { continue }
                for child in children(parent, base: home) where matches(child.lastPathComponent) {
                    add(child, kind, review: auxiliaryMatch(child.lastPathComponent),
                        evidence: .init(basis: .vendorFolder, matched: parent.lastPathComponent + "/" + child.lastPathComponent))
                }
            }
        }

        /// 读 plist（≤1MB），失败返回 nil
        func propertyList(at url: URL, maximumBytes: Int = 1_048_576) -> [String: Any]? {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, let size = values.fileSize, size <= maximumBytes,
                  let data = try? Data(contentsOf: url) else { return nil }
            return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        }

        /// 启动项里实际要运行的程序路径
        func launchProgram(_ plist: [String: Any]) -> String? {
            if let program = plist["Program"] as? String { return program }
            return (plist["ProgramArguments"] as? [String])?.first
        }

        add(app.url, .application)
        // 剩余副本仍使用相同数据：此次只移除所选本体。
        guard copies.isEmpty, unreadableInstallations.isEmpty else {
            if !copies.isEmpty { diagnostics.skippedReason = "检测到相同应用的其他安装副本，共用数据会保留，只移除所选本体" }
            else { diagnostics.skippedReason = "读不了某个应用目录，无法确认没有其他安装副本，只移除所选本体" }
            var skipped = AppUninstallScan(items: results, unreadableDirectories: unreadableInstallations, otherInstalledCopies: copies,
                                           identity: identity, applicationURL: app.url)
            skipped.diagnostics = diagnostics
            return skipped
        }
        scan("Application Support", .support, names: true)
        scan("Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments", .support)
        scan("Application Support/CrashReporter", .logs)
        scan("Caches", .caches, names: true)
        scan("Caches/org.sparkle-project.Sparkle", .caches)
        scan("Caches/SentryCrash", .caches)
        // Sentry 的目录使用 CFBundleName 而非包名；同名数据可能共用，默认不选。
        for entry in entries("Caches/SentryCrash") where identity.matchesName(entry.lastPathComponent) {
            add(entry, .caches, review: true, evidence: nameEvidence(entry.lastPathComponent))
        }
        scanNested("Application Support", .support)
        scanNested("Caches", .caches)
        scanNested("Logs", .logs)
        scan("HTTPStorages", .caches)
        scan("Preferences", .preferences)
        for entry in entries("Preferences") where entry.pathExtension.lowercased() == "plist"
            && identity.matchesName(entry.deletingPathExtension().lastPathComponent) {
            add(entry, .preferences, review: !matches(entry.lastPathComponent), evidence: nameEvidence(entry.lastPathComponent))
        }
        scan("Preferences/ByHost", .preferences)
        scan("SyncedPreferences", .preferences)
        // 自动保存可能含还没保存的文档，默认保留
        scan("Autosave Information", .support, review: true)
        for entry in entries("Containers") {
            let owner = containerIdentifier(at: entry, home: home)
            if let owner {
                if identity.identifiers.contains(where: { $0.caseInsensitiveCompare(owner) == .orderedSame }) {
                    add(entry, .containers, review: owner.caseInsensitiveCompare(app.bundleIdentifier) != .orderedSame,
                        evidence: .init(basis: .containerMetadata, matched: owner))
                }
            } else if matches(entry.lastPathComponent) {
                add(entry, .containers, review: auxiliaryMatch(entry.lastPathComponent), evidence: identifierEvidence(entry.lastPathComponent))
            }
        }
        scan("Application Scripts", .containers)

        // 应用组：签名里声明的，或名字里带着本应用包名的。比较不区分大小写：
        // 组名与包名的大小写常不一致（group.com.baidu.BaiduNetdisk-Mac 对 com.baidu.BaiduNetdisk-mac）
        let signedGroups = Set(identity.applicationGroups.map { $0.lowercased() })
        let loweredIdentifiers = identity.identifiers.map { $0.lowercased() }
        for relative in ["Group Containers", "Application Scripts"] {
            for entry in entries(relative) {
                let name = entry.lastPathComponent
                let lowered = name.lowercased()
                let owner = containerIdentifier(at: entry, home: home)
                let evidence: AppLeftover.Evidence?
                if signedGroups.contains(lowered) {
                    evidence = .init(basis: .applicationGroup, matched: name)
                } else if let owner, signedGroups.contains(owner.lowercased()) {
                    evidence = .init(basis: .applicationGroup, matched: owner)
                } else if let id = loweredIdentifiers.first(where: {
                    lowered.hasSuffix("." + $0) || lowered == "group." + $0 || lowered.hasPrefix("group." + $0 + ".")
                }) {
                    evidence = .init(basis: .bundleIdentifier, matched: id)
                } else {
                    evidence = nil
                }
                if let evidence { add(entry, .containers, review: true, evidence: evidence) }
            }
        }

        scan("Saved Application State", .savedState)
        for entry in entries("Saved Application State") where entry.pathExtension.lowercased() == "savedstate"
            && identity.matchesName(entry.deletingPathExtension().lastPathComponent) {
            add(entry, .savedState, review: !matches(entry.lastPathComponent), evidence: nameEvidence(entry.lastPathComponent))
        }
        scan("Logs", .logs, names: true)
        for (relative, extensions) in [("Application Support/CrashReporter", Set(["plist"])),
                                       ("Logs/DiagnosticReports", Set(["ips", "crash", "spin", "diag"]))] {
            for entry in entries(relative) where extensions.contains(entry.pathExtension.lowercased())
                && identity.matchesReportName(entry.deletingPathExtension().lastPathComponent) {
                add(entry, .logs, review: !matches(entry.lastPathComponent),
                    evidence: .init(basis: .crashReport, matched: entry.lastPathComponent))
            }
        }
        scan("WebKit", .webData)
        scan("WebKit/com.apple.WebKit.WebContent", .webData)
        scan("Caches/com.apple.nsurlsessiond/Downloads", .caches)
        scan("Cookies", .webData)
        scan("LaunchAgents", .launchAgents)
        // 名字与包名无关的启动项：只有内容明确指向本应用里的程序才认领
        for entry in entries("LaunchAgents") where entry.pathExtension.lowercased() == "plist" {
            guard let plist = propertyList(at: entry), let program = launchProgram(plist),
                  program.hasPrefix(app.url.path + "/") else { continue }
            add(entry, .launchAgents, evidence: .init(basis: .launchAgentProgram, matched: program))
        }

        // 插件、服务、输入法、屏保等：以包名命名的直接认领，仅名字相同的默认保留
        for location in bundleLocations {
            for entry in entries(location.relative) where location.extensions.contains(entry.pathExtension.lowercased()) {
                let stem = entry.deletingPathExtension().lastPathComponent
                if matches(stem) {
                    add(entry, .extensions, evidence: identifierEvidence(stem))
                } else if identity.matchesName(stem) {
                    add(entry, .extensions, review: true, evidence: nameEvidence(entry.lastPathComponent))
                }
            }
        }

        // 浏览器的原生消息清单：只认领清单里的程序路径指向本应用的
        for vendor in entries("Application Support") {
            guard (try? vendor.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            var hostDirectories = [vendor.appendingPathComponent("NativeMessagingHosts")]
            hostDirectories += children(vendor, base: home, track: false).map { $0.appendingPathComponent("NativeMessagingHosts") }
            for directory in hostDirectories {
                for manifest in children(directory, base: home, track: false) where manifest.pathExtension.lowercased() == "json" {
                    guard let values = try? manifest.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                          values.isRegularFile == true, let size = values.fileSize, size <= 65_536,
                          let data = try? Data(contentsOf: manifest),
                          let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                          let target = json["path"] as? String, target.hasPrefix(app.url.path + "/") else { continue }
                    add(manifest, .extensions, evidence: .init(basis: .nativeManifest, matched: target))
                }
            }
        }

        for path in knownPaths(for: app.bundleIdentifier) {
            add(URL(fileURLWithPath: home).appendingPathComponent(path.relative), path.kind, review: path.review,
                evidence: .init(basis: .knownPath, matched: path.relative))
        }
        if let userCache {
            if isDirectoryWithoutSymlink(userCache) {
                for entry in children(userCache, base: userCache.path) where matches(entry.lastPathComponent) {
                    add(entry, .caches, review: auxiliaryMatch(entry.lastPathComponent), evidence: identifierEvidence(entry.lastPathComponent))
                }
            } else if manager.fileExists(atPath: userCache.path) {
                unreadable.insert(userCache)
            }
        }
        // 临时目录（/var/folders/…/T）：应用用 mkstemp 之类建的文件常是“.包名.随机后缀”，去掉开头的点再按包名认领
        if let userTemp {
            if isDirectoryWithoutSymlink(userTemp) {
                for entry in children(userTemp, base: userTemp.path) {
                    let stem = temporaryStem(entry.lastPathComponent)
                    guard matches(stem) else { continue }
                    if let owner = ownerAmongOtherInstalledApps(stem) {
                        reject(entry.standardizedFileURL.path, "属于另一个已安装的应用：\(owner.name)（\(owner.bundleIdentifier)）")
                        continue
                    }
                    add(entry, .caches, review: auxiliaryMatch(stem), evidence: identifierEvidence(stem))
                }
            } else if manager.fileExists(atPath: userTemp.path) {
                unreadable.insert(userTemp)
            }
        }

        // 系统级残留：只读预览。需要管理员权限，这里不删除，只告诉用户它们在哪里
        let systemRootURL = URL(fileURLWithPath: systemRoot)
        func systemChildren(_ relative: String) -> [URL] {
            let directory = systemRootURL.appendingPathComponent(relative)
            rootPaths.insert(directory.path)
            // 系统目录的上层（/Library、/private/var 等）本来就由系统保护，其中 /var 还是个系统别名；
            // 这里只确认目录本身不是被换成了链接
            return children(directory, base: directory.deletingLastPathComponent().path)
        }
        func addSystem(_ url: URL, _ kind: AppLeftover.Kind, _ evidence: AppLeftover.Evidence) {
            let path = url.standardizedFileURL.path
            guard FileIdentity.status(of: path) != nil,
                  !results.contains(where: { $0.url.standardizedFileURL.path == path }) else { return }
            results.append(AppLeftover(url: url, kind: kind, size: CleanEngine.allocatedSize(of: url), requiresReview: true,
                                       evidence: evidence, identity: FileIdentity.capture(url), location: .system))
        }
        for (relative, kind) in [("Library/Application Support", AppLeftover.Kind.support), ("Library/Caches", .caches),
                                 ("Library/Logs", .logs), ("Library/Preferences", .preferences)] {
            for entry in systemChildren(relative) {
                let name = entry.lastPathComponent
                if matches(name) {
                    if let evidence = identifierEvidence(name) { addSystem(entry, kind, evidence) }
                } else if relative != "Library/Preferences", (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    // 厂商目录下的应用子目录
                    for child in children(entry, base: systemRoot, track: false) where matches(child.lastPathComponent) {
                        addSystem(child, kind, .init(basis: .vendorFolder, matched: name + "/" + child.lastPathComponent))
                    }
                }
            }
        }
        for relative in ["Library/LaunchAgents", "Library/LaunchDaemons"] {
            for entry in systemChildren(relative) where entry.pathExtension.lowercased() == "plist" {
                if matches(entry.lastPathComponent), let evidence = identifierEvidence(entry.lastPathComponent) {
                    addSystem(entry, .launchAgents, evidence)
                } else if let plist = propertyList(at: entry), let program = launchProgram(plist), program.hasPrefix(app.url.path + "/") {
                    addSystem(entry, .launchAgents, .init(basis: .launchAgentProgram, matched: program))
                }
            }
        }
        for entry in systemChildren("Library/PrivilegedHelperTools") where matches(entry.lastPathComponent) {
            if let evidence = identifierEvidence(entry.lastPathComponent) { addSystem(entry, .helpers, evidence) }
        }
        for relative in ["Library/Receipts", "private/var/db/receipts"] {
            for entry in systemChildren(relative) where matches(entry.lastPathComponent) {
                if let evidence = identifierEvidence(entry.lastPathComponent) { addSystem(entry, .receipts, evidence) }
            }
        }
        for entry in systemChildren("Users/Shared") {
            let name = entry.lastPathComponent
            if name.count >= 5, identity.matchesName(name) { addSystem(entry, .support, nameEvidence(name)) }
        }

        var completed = AppUninstallScan(items: results, unreadableDirectories: unreadable.sorted { $0.path < $1.path },
                                         otherInstalledCopies: [], identity: identity, applicationURL: app.url)
        completed.diagnostics = diagnostics
        return completed
    }

    private static func containerIdentifier(at directory: URL, home: String) -> String? {
        let metadata = directory.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
        guard isUnredirected(metadata, home: home),
              let values = try? metadata.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= 1_048_576,
              let data = try? Data(contentsOf: metadata),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["MCMMetadataIdentifier"] as? String
    }

    private static func knownPaths(for identifier: String) -> [(relative: String, kind: AppLeftover.Kind, review: Bool)] {
        switch identifier.lowercased() {
        case "com.microsoft.vscode":
            [("Library/Application Support/Code", .support, false), (".vscode", .support, false), (".vscode-shared", .support, true)]
        case "com.microsoft.vscodeinsiders":
            [("Library/Application Support/Code - Insiders", .support, false), (".vscode-insiders", .support, false), (".vscode-shared", .support, true)]
        case "company.thebrowser.browser":
            [("Library/Application Support/Arc", .support, false), ("Library/Caches/Arc", .caches, false)]
        case "com.google.chrome":
            [("Library/Application Support/Google/Chrome", .support, false), ("Library/Caches/Google/Chrome", .caches, false)]
        case "ai.opencode.desktop":
            // 桌面版与命令行可能共用这些目录，由用户确认后选择。
            [(".config/opencode", .support, true), (".cache/opencode", .caches, true)]
        default: []
        }
    }

    private static let libraryRoots = ["Application Support", "Caches", "HTTPStorages", "Preferences", "Containers",
                                       "Application Scripts", "Group Containers", "Saved Application State", "Logs", "WebKit", "Cookies", "LaunchAgents",
                                       "Services", "Workflows", "QuickLook", "Internet Plug-Ins", "Audio", "PreferencePanes", "Input Methods",
                                       "Screen Savers", "Frameworks", "Contextual Menu Items", "Spotlight", "ColorPickers",
                                       "Address Book Plug-Ins", "Accessibility", "Autosave Information", "SyncedPreferences"]

    /// 以名字或包名命名的插件、服务、输入法等：位置与扩展名
    static let bundleLocations: [(relative: String, extensions: Set<String>)] = [
        ("Services", ["workflow"]), ("Workflows", ["workflow"]), ("QuickLook", ["qlgenerator"]),
        ("Internet Plug-Ins", ["plugin"]), ("Audio/Plug-Ins/Components", ["component"]), ("Audio/Plug-Ins/VST", ["vst"]),
        ("Audio/Plug-Ins/VST3", ["vst3"]), ("PreferencePanes", ["prefpane"]), ("Input Methods", ["app"]),
        ("Screen Savers", ["saver"]), ("Frameworks", ["framework"]), ("Contextual Menu Items", ["plugin"]),
        ("Spotlight", ["mdimporter"]), ("ColorPickers", ["colorpicker"]), ("Address Book Plug-Ins", ["bundle"]),
        ("Accessibility", ["bundle"]),
    ]
    private static let sharedNames: Set<String> = ["dock", "addressbook", "mobilesync", "callhistorydb", "knowledge", "icloud",
                                                   "clouddocs", "accounts", "google", "microsoft", "mozilla", "jetbrains", "adobe", "bravesoftware", "opera software",
                                                   "steam", "objective-see", "apple", "crashreporter", "sentrycrash", "org.sparkle-project.sparkle", "com.apple.sharedfilelist",
                                                   "com.apple.webkit.webcontent", "com.apple.nsurlsessiond"]

    /// 在扫描和回收前重查：只允许固定目录内的应用条目，拒绝共享根及 home 以下的符号链接重定向。
    public static func validateLeftover(_ url: URL, for app: InstalledApp, home: String = NSHomeDirectory()) throws {
        try validateLeftover(url, for: app, home: home, userCache: userCacheDirectory(home: home), userTemp: userTempDirectory(home: home))
    }

    /// 保留扫描时从真实 bundle 收集的组件身份；本体已移入废纸篓后仍可重试这些候选。
    public static func validateLeftover(_ url: URL, for app: InstalledApp, scan: AppUninstallScan, home: String = NSHomeDirectory()) throws {
        try validateLeftover(url, for: app, scan: scan, home: home, userCache: userCacheDirectory(home: home),
                             userTemp: userTempDirectory(home: home))
    }

    static func validateLeftover(_ url: URL, for app: InstalledApp, scan: AppUninstallScan, home: String, userCache: URL?,
                                 userTemp: URL? = nil) throws {
        guard scan.applicationURL.standardizedFileURL.path == app.url.standardizedFileURL.path,
              scan.items.contains(where: { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }) else {
            throw AppUninstallError.unsafePath(url.path)
        }
        try validateLeftover(url, for: app, home: home, userCache: userCache, userTemp: userTemp, identity: scan.identity)
    }

    static func validateLeftover(_ url: URL, for app: InstalledApp, home: String, userCache: URL?, userTemp: URL? = nil,
                                 identity: AppUninstallIdentity? = nil) throws {
        let path = url.standardizedFileURL.path
        guard !url.pathComponents.contains(".."), !path.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw AppUninstallError.unsafePath(path)
        }
        if url.standardizedFileURL == app.url.standardizedFileURL {
            try validate(app, home: home)
            return
        }
        let base = URL(fileURLWithPath: home).standardizedFileURL.path
        if let userCache, url.deletingLastPathComponent().standardizedFileURL.path == userCache.standardizedFileURL.path,
           isDirectoryWithoutSymlink(userCache),
           isUnredirected(url, home: userCache.path),
           (identity ?? AppUninstallIdentity(app: app)).identifiers.contains(where: { matchesIdentifier(url.lastPathComponent, $0) }) {
            return
        }
        if let userTemp, url.deletingLastPathComponent().standardizedFileURL.path == userTemp.standardizedFileURL.path,
           isDirectoryWithoutSymlink(userTemp),
           isUnredirected(url, home: userTemp.path),
           (identity ?? AppUninstallIdentity(app: app)).identifiers
               .contains(where: { matchesIdentifier(temporaryStem(url.lastPathComponent), $0) }) {
            return
        }
        guard path.hasPrefix(base + "/"), isUnredirected(url, home: home) else { throw AppUninstallError.unsafePath(path) }
        let relative = String(path.dropFirst(base.count + 1))
        if knownPaths(for: app.bundleIdentifier).contains(where: { $0.relative == relative }) { return }
        guard let root = libraryRoots.first(where: { relative.hasPrefix("Library/" + $0 + "/") }) else { throw AppUninstallError.unsafePath(path) }
        let inside = String(relative.dropFirst(("Library/" + root + "/").count))
        if !inside.contains("/"), sharedNames.contains(inside.lowercased()) { throw AppUninstallError.unsafePath(path) }
        if relative == "Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments"
            || relative == "Library/Preferences/ByHost" || relative == "Library/Logs/DiagnosticReports"
            || relative == "Library/Caches/com.apple.nsurlsessiond/Downloads"
            || relative == "Library/WebKit/com.apple.WebKit.WebContent" { throw AppUninstallError.unsafePath(path) }
    }

    static func isUnredirected(_ url: URL, home: String) -> Bool {
        redirectionFailure(url, home: home) == nil
    }

    /// nil 表示从可信根往下每一层都是真实目录项；否则说明哪一层有问题
    static func redirectionFailure(_ url: URL, home: String) -> String? {
        let suppliedHome = URL(fileURLWithPath: home).standardizedFileURL
        let path = url.standardizedFileURL.path
        let roots = [suppliedHome, suppliedHome.resolvingSymlinksInPath().standardizedFileURL]
        func contains(_ root: URL) -> Bool {
            root.path == "/" ? true : path == root.path || path.hasPrefix(root.path + "/")
        }
        guard let originalHome = roots.first(where: contains) else { return "不在 \(home) 之下" }
        let relative = originalHome.path == "/" ? String(path.dropFirst()) : String(path.dropFirst(originalHome.path.count + 1))
        var current = originalHome
        // APFS 解析路径会规范实际大小写，不能用字符串相等判定符号链接。
        // 从可信 home 向下逐级 lstat，允许大小写规范化，拒绝任何层级的真实链接。
        for component in relative.split(separator: "/") {
            current.appendPathComponent(String(component))
            var information = stat()
            guard current.path.withCString({ lstat($0, &information) }) == 0 else {
                return "无法读取 \(component)（\(AppScanDiagnostics.message(for: errno))）"
            }
            guard information.st_mode & S_IFMT != S_IFLNK else { return "\(component) 是符号链接" }
        }
        return nil
    }

    /// URL 的资源属性可能缓存旧值；路径重查直接读取当前目录项。
    static func isDirectoryWithoutSymlink(_ url: URL) -> Bool {
        var information = stat()
        return url.path.withCString({ lstat($0, &information) }) == 0 && information.st_mode & S_IFMT == S_IFDIR
    }

    /// 由系统提供当前用户的 /var/folders/.../C 路径；不扫描其他用户或整个临时根。
    private static func userCacheDirectory(home: String) -> URL? {
        darwinUserDirectory(_CS_DARWIN_USER_CACHE_DIR, named: "C", home: home)
    }

    /// 当前用户的 /var/folders/.../T：不在沙盒里的进程共用的临时目录
    private static func userTempDirectory(home: String) -> URL? {
        darwinUserDirectory(_CS_DARWIN_USER_TEMP_DIR, named: "T", home: home)
    }

    /// 临时文件的名字去掉开头的点：“.com.example.app.y62PA3” 按 “com.example.app.y62PA3” 匹配包名
    static func temporaryStem(_ name: String) -> String {
        name.hasPrefix(".") ? String(name.dropFirst()) : name
    }

    private static func darwinUserDirectory(_ key: Int32, named name: String, home: String) -> URL? {
        guard URL(fileURLWithPath: home).resolvingSymlinksInPath().path
            == URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path else { return nil }
        let length = confstr(key, nil, 0)
        guard length > 1, length < 4096 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(key, &buffer, length) == length else { return nil }
        let directory = buffer.withUnsafeBufferPointer { pointer in
            pointer.baseAddress.map { URL(fileURLWithPath: String(cString: $0)).standardizedFileURL }
        }
        guard let directory else { return nil }
        let path = directory.path
        let canonical: URL
        if path.hasPrefix("/var/folders/") {
            canonical = URL(fileURLWithPath: "/private" + path)
        } else {
            canonical = directory
        }
        let anchor = URL(fileURLWithPath: "/private/var/folders")
        guard canonical.lastPathComponent == name, canonical.path.hasPrefix(anchor.path + "/"),
              isDirectoryWithoutSymlink(anchor),
              isUnredirected(canonical, home: anchor.path) else { return nil }
        var information = stat()
        guard canonical.path.withCString({ lstat($0, &information) }) == 0,
              information.st_mode & S_IFMT == S_IFDIR, information.st_uid == geteuid() else { return nil }
        return canonical
    }

    /// 名字等于包名，或是包名后接“.”的派生名（com.example.app.plist、com.example.app.savedState、com.example.app.helper）
    static func matchesIdentifier(_ name: String, _ identifier: String) -> Bool {
        guard !identifier.isEmpty else { return false }
        let lowered = name.lowercased()
        let id = identifier.lowercased()
        return lowered == id || lowered.hasPrefix(id + ".")
    }

    // MARK: 程序坞

    /// 从程序坞的 persistent-apps 中去掉指向该应用的图标，返回是否有改动（调用方随后重启程序坞）
    public static func removingDockTile(for appURL: URL, from tiles: [[String: Any]]) -> [[String: Any]]? {
        let target = appURL.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let filtered = tiles.filter { tile in
            guard let data = tile["tile-data"] as? [String: Any],
                  let file = data["file-data"] as? [String: Any],
                  let string = file["_CFURLString"] as? String else { return true }
            let path = (URL(string: string)?.path ?? string).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return path != target
        }
        return filtered.count == tiles.count ? nil : filtered
    }
}
