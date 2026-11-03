import Foundation
import Testing
@testable import Cleaner

private struct Rig {
    let root: URL
    let home: URL
    let system: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openstats-engine-\(UUID().uuidString)").resolvingSymlinksInPath()
        home = root.appendingPathComponent("home")
        system = root.appendingPathComponent("system")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
    }

    func cleanUp() {
        // 测试里会把某些目录改成不可读；先还原权限才删得掉
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        }
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func make(_ relative: String, in base: URL? = nil, directory: Bool = false, content: Data = Data("x".utf8)) throws -> URL {
        let url = (base ?? home).appendingPathComponent(relative)
        if directory {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url)
        }
        return url
    }

    func app(_ name: String = "Foo", id: String = "com.example.foo") throws -> InstalledApp {
        let url = try make("Applications/\(name).app/Contents/MacOS/\(name)")
        return InstalledApp(url: url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
                            name: name, bundleIdentifier: id, version: "1.0", teamIdentifier: nil)
    }

    func scan(_ app: InstalledApp, identity: AppUninstallIdentity? = nil, installed: [InstalledApp] = []) -> AppUninstallScan {
        AppUninstaller.scan(for: app, home: home.path, identity: identity ?? AppUninstallIdentity(app: app),
                            installed: installed, userCache: nil, systemRoot: system.path)
    }

    func relative(_ item: AppLeftover) -> String {
        let base = item.location == .system ? system.path : home.path
        return String(item.url.standardizedFileURL.path.dropFirst(base.count + 1))
    }
}

private func found(_ scan: AppUninstallScan, user: Bool = true) -> [String: AppLeftover] {
    Dictionary(uniqueKeysWithValues: scan.items.filter { ($0.location == .user) == user }
        .map { ($0.url.standardizedFileURL.path, $0) })
}

@Suite("卸载引擎")
struct AppUninstallEngineTests {
    // MARK: 群组名大小写（issue #4）

    @Test func groupContainersMatchRegardlessOfCase() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        let app = try rig.app("BaiduNetdisk_mac", id: "com.baidu.BaiduNetdisk-mac")
        // 包名是 …-mac，群组目录是 …-Mac；另一个工具能找到它们
        try rig.make("Library/Group Containers/group.com.baidu.BaiduNetdisk-Mac", directory: true)
        try rig.make("Library/Application Scripts/group.com.baidu.BaiduNetdisk-Mac", directory: true)
        try rig.make("Library/Group Containers/group.com.baidu.Unrelated", directory: true)

        let scan = rig.scan(app)
        let names = Set(scan.items.map { rig.relative($0) })
        #expect(names.contains("Library/Group Containers/group.com.baidu.BaiduNetdisk-Mac"))
        #expect(names.contains("Library/Application Scripts/group.com.baidu.BaiduNetdisk-Mac"))
        #expect(!names.contains("Library/Group Containers/group.com.baidu.Unrelated"))
        let group = try #require(scan.items.first { $0.url.path.contains("Group Containers/group.com.baidu.BaiduNetdisk") })
        #expect(group.requiresReview)  // 共享容器默认保留
        #expect(group.evidence?.basis == .bundleIdentifier)
    }

    @Test func signedApplicationGroupsMatchRegardlessOfCase() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        let app = try rig.app()
        try rig.make("Library/Group Containers/group.com.vendor.shared", directory: true)
        let identity = AppUninstallIdentity(identifiers: [app.bundleIdentifier], names: [app.name],
                                            applicationGroups: ["group.com.vendor.Shared"])

        let item = try #require(rig.scan(app, identity: identity).items.first { $0.url.lastPathComponent == "group.com.vendor.shared" })
        #expect(item.evidence?.basis == .applicationGroup)
        #expect(item.requiresReview)
    }

    // MARK: 证据

    @Test func everyLeftoverSaysWhyItWasClaimed() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        let app = try rig.app()
        try rig.make("Library/Caches/com.example.foo", directory: true)
        try rig.make("Library/Application Support/Foo", directory: true)
        try rig.make("Library/Application Support/Vendor/com.example.foo", directory: true)

        let scan = rig.scan(app)
        let items = found(scan)
        let cache = try #require(items[rig.home.appendingPathComponent("Library/Caches/com.example.foo").path])
        #expect(cache.evidence == .init(basis: .bundleIdentifier, matched: "com.example.foo"))
        #expect(!cache.requiresReview)
        let byName = try #require(items[rig.home.appendingPathComponent("Library/Application Support/Foo").path])
        #expect(byName.evidence?.basis == .name)
        #expect(byName.requiresReview)  // 只按名字认领的默认保留
        let nested = try #require(items[rig.home.appendingPathComponent("Library/Application Support/Vendor/com.example.foo").path])
        #expect(nested.evidence?.basis == .vendorFolder)
    }

    // MARK: 新增的位置与归属证明

    @Test func findsPluginsServicesAndAutosaves() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        let app = try rig.app()
        try rig.make("Library/Input Methods/Foo.app", directory: true)
        try rig.make("Library/Services/Foo.workflow", directory: true)
        try rig.make("Library/Input Methods/com.example.foo.app", directory: true)
        try rig.make("Library/Autosave Information/com.example.foo", directory: true)
        try rig.make("Library/SyncedPreferences/com.example.foo.plist")
        try rig.make("Library/Services/Other.workflow", directory: true)

        let names = Set(rig.scan(app).items.map { rig.relative($0) })
        #expect(names.isSuperset(of: ["Library/Input Methods/Foo.app", "Library/Services/Foo.workflow",
                                      "Library/Input Methods/com.example.foo.app", "Library/Autosave Information/com.example.foo",
                                      "Library/SyncedPreferences/com.example.foo.plist"]))
        #expect(!names.contains("Library/Services/Other.workflow"))
        let byName = try #require(rig.scan(app).items.first { rig.relative($0) == "Library/Input Methods/Foo.app" })
        #expect(byName.requiresReview)  // 只凭名字
        let byID = try #require(rig.scan(app).items.first { rig.relative($0) == "Library/Input Methods/com.example.foo.app" })
        #expect(!byID.requiresReview)  // 凭包名
        let autosave = try #require(rig.scan(app).items.first { rig.relative($0) == "Library/Autosave Information/com.example.foo" })
        #expect(autosave.requiresReview)  // 可能有没保存的文档
    }

    @Test func launchAgentsAreClaimedOnlyWhenTheyRunProgramsInsideTheApp() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        let app = try rig.app()
        func plist(_ name: String, program: String) throws {
            let data = try PropertyListSerialization.data(fromPropertyList: ["Label": name, "ProgramArguments": [program]], format: .xml, options: 0)
            try rig.make("Library/LaunchAgents/\(name).plist", content: data)
        }
        try plist("unrelated.name.helper", program: app.url.path + "/Contents/MacOS/helper")
        try plist("other.vendor.agent", program: "/usr/local/bin/other")

        let scan = rig.scan(app)
        let claimed = try #require(scan.items.first { $0.url.lastPathComponent == "unrelated.name.helper.plist" })
        #expect(claimed.evidence?.basis == .launchAgentProgram)
        #expect(!scan.items.contains { $0.url.lastPathComponent == "other.vendor.agent.plist" })
    }

    @Test func nativeMessagingManifestsMustPointIntoTheApp() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        let app = try rig.app()
        func manifest(_ name: String, path: String) throws {
            let json = try JSONSerialization.data(withJSONObject: ["name": name, "path": path])
            try rig.make("Library/Application Support/Google/Chrome/NativeMessagingHosts/\(name).json", content: json)
        }
        try manifest("com.mine", path: app.url.path + "/Contents/MacOS/host")
        try manifest("com.theirs", path: "/Applications/Other.app/Contents/MacOS/host")

        let names = Set(rig.scan(app).items.map(\.url.lastPathComponent))
        #expect(names.contains("com.mine.json"))
        #expect(!names.contains("com.theirs.json"))
    }

    // MARK: 系统级只读预览

    @Test func systemLevelLeftoversArePreviewedButNeverDeletable() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        let app = try rig.app()
        try rig.make("Library/LaunchDaemons/com.example.foo.helper.plist", in: rig.system)
        try rig.make("Library/PrivilegedHelperTools/com.example.foo.helper", in: rig.system)
        try rig.make("private/var/db/receipts/com.example.foo.bom", in: rig.system)
        try rig.make("Library/Application Support/com.example.foo/data", in: rig.system)
        try rig.make("Library/Application Support/Vendor/Foo/data", in: rig.system)  // 只凭名字，不认领
        try rig.make("Library/LaunchDaemons/com.other.thing.plist", in: rig.system)

        let scan = rig.scan(app)
        let system = scan.items.filter { $0.location == .system }
        let names = Set(system.map { rig.relative($0) })
        #expect(names == ["Library/LaunchDaemons/com.example.foo.helper.plist", "Library/PrivilegedHelperTools/com.example.foo.helper",
                          "private/var/db/receipts/com.example.foo.bom", "Library/Application Support/com.example.foo"])
        #expect(system.allSatisfy { $0.requiresReview })  // 系统级一律不预选
        #expect(Set(system.map(\.kind)) == [.launchAgents, .helpers, .receipts, .support])

        // 系统级条目通不过卸载的范围校验：即使有人误把它交给删除入口也不会被删
        for item in system {
            #expect(throws: AppUninstallError.self) { try AppUninstaller.validateLeftover(item.url, for: app, scan: scan, home: rig.home.path) }
        }
    }

    // MARK: 诊断

    @Test func recordsWhatWasReadAndWhatWasMissing() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        let app = try rig.app()
        try rig.make("Library/Application Support/Other", directory: true)
        try rig.make("Library/Caches/com.example.foo", directory: true)

        let directories = Dictionary(uniqueKeysWithValues: rig.scan(app).diagnostics.directories.map { ($0.path, $0.state) })
        #expect(directories[rig.home.appendingPathComponent("Library/Application Support").path] == .listed(1))
        #expect(directories[rig.home.appendingPathComponent("Library/Containers").path] == .missing)
    }

    @Test(.disabled(if: getuid() == 0, "以 root 运行时 chmod 000 不会拒绝访问"))
    func unreadableDirectoriesAreReportedNotTreatedAsMissing() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        let app = try rig.app()
        try rig.make("Library/Preferences/com.example.foo.plist")
        try rig.make("Library/Application Support/x/y", directory: true)
        let library = rig.home.appendingPathComponent("Library")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: library.path)

        let scan = rig.scan(app)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: library.path)
        // 以前这会被当成“目录不存在”而悄悄跳过，页面上只剩应用本体且没有任何提示
        #expect(!scan.unreadableDirectories.isEmpty)
        let denied = scan.diagnostics.directories.filter { if case .denied = $0.state { true } else { false } }
        #expect(!denied.isEmpty)
        #expect(scan.diagnosticReport(app: app, home: rig.home.path).contains("系统拒绝访问"))
    }

    @Test func symlinkedCandidatesAreRejectedWithAReason() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        let app = try rig.app()
        let elsewhere = try rig.make("Elsewhere/data", directory: false)
        let link = rig.home.appendingPathComponent("Library/Caches/com.example.foo")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: elsewhere)

        let scan = rig.scan(app)
        #expect(!scan.items.contains { $0.url.lastPathComponent == "com.example.foo" })
        let rejection = try #require(scan.diagnostics.rejections.first { $0.path.hasSuffix("com.example.foo") })
        #expect(rejection.reason.contains("符号链接"))
        #expect(scan.diagnosticReport(app: app, home: rig.home.path).contains("没有列入结果"))
    }

    @Test func reportIsReadableAndHidesTheHomePath() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        let app = try rig.app()
        try rig.make("Library/Caches/com.example.foo", directory: true)

        let report = rig.scan(app).diagnosticReport(app: app, home: rig.home.path, header: ["OpenStats 测试"])
        #expect(report.hasPrefix("OpenStats 测试"))
        #expect(report.contains("com.example.foo"))
        #expect(report.contains("~/Library/Caches/com.example.foo"))
        #expect(report.contains("包名 com.example.foo"))
        #expect(!report.contains(rig.home.path))  // 家目录统一写成 ~，包括应用自己的位置
    }

    // MARK: 兄弟应用与报告安全

    @Test func dataOfAnotherInstalledAppWhoseIdentifierExtendsOursIsNotClaimed() throws {
        // 卸载 Chrome 不能把 Chrome Canary 的数据当成自己的并预选
        let rig = try Rig()
        defer { rig.cleanUp() }
        let app = try rig.app("Chrome", id: "com.example.chrome")
        let canary = InstalledApp(url: rig.home.appendingPathComponent("Applications/Chrome Canary.app"), name: "Chrome Canary",
                                  bundleIdentifier: "com.example.chrome.canary", version: nil, teamIdentifier: nil)
        try rig.make("Library/Caches/com.example.chrome", directory: true)
        try rig.make("Library/Caches/com.example.chrome.canary", directory: true)
        try rig.make("Library/Preferences/com.example.chrome.canary.plist")
        try rig.make("Library/Preferences/com.example.chrome.plist")
        // 不是已安装应用的派生名（比如自己的辅助组件）照常认领
        try rig.make("Library/Caches/com.example.chrome.helper", directory: true)

        let scan = rig.scan(app, installed: [app, canary])
        let names = Set(scan.items.map { rig.relative($0) })
        #expect(names.isSuperset(of: ["Library/Caches/com.example.chrome", "Library/Preferences/com.example.chrome.plist",
                                      "Library/Caches/com.example.chrome.helper"]))
        #expect(!names.contains("Library/Caches/com.example.chrome.canary"))
        #expect(!names.contains("Library/Preferences/com.example.chrome.canary.plist"))
        // 不是悄悄丢掉：诊断里写明了原因
        let rejection = try #require(scan.diagnostics.rejections.first { $0.path.hasSuffix("com.example.chrome.canary") })
        #expect(rejection.reason.contains("另一个已安装的应用"))
    }

    @Test func fileNamesCannotForgeLinesInTheDiagnosticReport() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        let app = try rig.app()
        // 名字以包名开头（会被匹配），又带换行（通不过路径检查，进入“被丢弃”清单）
        let nasty = "com.example.foo.x\n  [caches] ~/Library/Caches/Fake  <- forged"
        try rig.make("Library/Caches/\(nasty)", directory: true)

        let report = rig.scan(app).diagnosticReport(app: app, home: rig.home.path)
        #expect(!report.contains("\n  [caches] ~/Library/Caches/Fake"))  // 伪造不出新的一行
        #expect(report.contains("\\x0A"))  // 换行被转义显示
    }

    @Test func evidenceInTheReportAlsoHidesTheHomePath() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        let app = try rig.app()  // 应用在 home/Applications 下，启动项指向它的路径会带上家目录
        let data = try PropertyListSerialization.data(fromPropertyList: ["ProgramArguments": [app.url.path + "/Contents/MacOS/helper"]],
                                                      format: .xml, options: 0)
        try rig.make("Library/LaunchAgents/unrelated.helper.plist", content: data)

        let report = rig.scan(app).diagnosticReport(app: app, home: rig.home.path)
        #expect(report.contains("启动项指向本应用"))
        #expect(!report.contains(rig.home.path))
    }

    @Test func explainsWhyTheLeftoverScanWasSkipped() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        let app = try rig.app()
        try rig.make("Library/Caches/com.example.foo", directory: true)
        let twin = InstalledApp(url: rig.home.appendingPathComponent("Applications/Other/Foo.app"), name: "Foo",
                                bundleIdentifier: "com.example.foo", version: nil, teamIdentifier: nil)

        let scan = rig.scan(app, installed: [app, twin])
        #expect(scan.items.count == 1)  // 只有应用本体
        #expect(scan.diagnostics.skippedReason?.contains("其他安装副本") == true)
        #expect(scan.diagnosticReport(app: app, home: rig.home.path).contains("没有扫描残留"))
    }
}
