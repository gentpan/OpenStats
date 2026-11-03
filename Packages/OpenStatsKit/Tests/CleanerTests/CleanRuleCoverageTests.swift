import Foundation
import Testing
@testable import Cleaner

private struct Home {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("openstats-rules-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @discardableResult
    func make(_ relative: String, directory: Bool = false, age: TimeInterval = 3600) throws -> URL {
        let url = root.appendingPathComponent(relative)
        if directory {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0x41, count: 4096).write(to: url)
        }
        // 沿途新建的目录也要调老：最近 2 分钟改过的目录会被当成“正在使用”而跳过
        let date = Date().addingTimeInterval(-age)
        var current = url
        while current.path.count > root.path.count {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: current.path)
            current = current.deletingLastPathComponent()
        }
        return url
    }

    func environment(running: Set<String> = [], names: Set<String> = [], readable: Bool = true) -> CleanEnvironment {
        CleanEnvironment(home: root.path, runningBundleIdentifiers: { running }, runningAppsReadable: readable,
                         runningApplicationNames: { names })
    }

    func exists(_ relative: String) -> Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(relative).path) }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Suite("清理规则覆盖", .serialized)
struct CleanRuleCoverageTests {
    // MARK: Electron / Chromium 应用缓存

    private func seedElectronApps(_ home: Home) throws {
        try home.make("Library/Application Support/Slack/Code Cache/js/a")
        try home.make("Library/Application Support/Slack/GPUCache/b")
        try home.make("Library/Application Support/Slack/Cache/c")
        try home.make("Library/Application Support/Slack/Local Storage/leveldb/db")  // 登录状态与数据，不能碰
        try home.make("Library/Application Support/Slack/Cookies")
        try home.make("Library/Application Support/Code/Service Worker/CacheStorage/x")
        try home.make("Library/Application Support/Code/Code Cache/y")
        try home.make("Library/Application Support/Notes App/Cache/z")                 // 没有 Chromium 标志子目录：Cache 太通用，不认
        try home.make("Library/Application Support/Google/GPUCache/g")                 // 浏览器有自己的规则
    }

    @Test func listsOnlyKnownRegenerableFoldersOfChromiumApps() async throws {
        let home = try Home()
        defer { home.remove() }
        try seedElectronApps(home)

        let scan = try #require(await CleanEngine.scan([RuleCatalog.chromiumAppCaches], environment: home.environment()).first)
        let titles = Set(scan.items.map(\.title))
        #expect(titles == ["Slack › Code Cache", "Slack › GPUCache", "Slack › Cache", "Code › Code Cache", "Code › Service Worker/CacheStorage"])
    }

    @Test func cleaningNeverTouchesLoginStateOrOtherAppsData() async throws {
        let home = try Home()
        defer { home.remove() }
        try seedElectronApps(home)
        let environment = home.environment()
        let scans = await CleanEngine.scan([RuleCatalog.chromiumAppCaches], environment: environment)

        let report = await CleanEngine.clean(scans, selected: [RuleCatalog.chromiumAppCaches.id], preferTrash: false,
                                             environment: environment, log: nil)
        #expect(report.removedCount == 5)
        #expect(!home.exists("Library/Application Support/Slack/Code Cache"))
        #expect(!home.exists("Library/Application Support/Slack/Cache"))
        #expect(home.exists("Library/Application Support/Slack/Local Storage/leveldb/db"))
        #expect(home.exists("Library/Application Support/Slack/Cookies"))
        #expect(home.exists("Library/Application Support/Notes App/Cache/z"))
        #expect(home.exists("Library/Application Support/Google/GPUCache/g"))
    }

    @Test func anAppThatIsRunningIsLeftAloneIdentifiedByItsName() async throws {
        let home = try Home()
        defer { home.remove() }
        try seedElectronApps(home)

        // 目录叫 Slack，运行中应用的名字里有 slack：Slack 的条目跳过，VS Code（目录名 Code）照常
        let scan = try #require(await CleanEngine.scan([RuleCatalog.chromiumAppCaches],
                                                       environment: home.environment(names: ["slack", "finder"])).first)
        #expect(Set(scan.items.map(\.title)) == ["Code › Code Cache", "Code › Service Worker/CacheStorage"])
        #expect(scan.skippedCount == 3)
    }

    @Test func anUnreadableRunningListSkipsEveryAppCache() async throws {
        let home = try Home()
        defer { home.remove() }
        try seedElectronApps(home)

        let scan = try #require(await CleanEngine.scan([RuleCatalog.chromiumAppCaches],
                                                       environment: home.environment(readable: false)).first)
        #expect(scan.items.isEmpty)
        #expect(scan.skippedCount == 5)
    }

    // MARK: 浏览器

    @Test func moreBrowsersAreCoveredAndNotCleanedTwice() async throws {
        let ids = Set(RuleCatalog.browsers.map(\.id))
        #expect(ids.isSuperset(of: ["opera", "vivaldi", "chromium"]))

        let home = try Home()
        defer { home.remove() }
        try home.make("Library/Caches/Vivaldi/Default/Cache/a")
        try home.make("Library/Caches/com.operasoftware.Opera/b")
        try home.make("Library/Caches/com.example.other/c")
        // 通用缓存规则不处理浏览器，免得它们运行时被清
        let generic = try #require(await CleanEngine.scan([RuleCatalog.userCaches], environment: home.environment()).first)
        #expect(generic.items.map(\.url.lastPathComponent) == ["com.example.other"])
        // 浏览器自己的规则：运行时整条跳过
        let vivaldi = try #require(RuleCatalog.browsers.first { $0.id == "vivaldi" })
        let blocked = try #require(await CleanEngine.scan([RuleCatalog.browserRule(vivaldi)],
                                                          environment: home.environment(running: ["com.vivaldi.Vivaldi"])).first)
        #expect(blocked.blocked == .appRunning("Vivaldi"))
    }

    // MARK: 开发工具链

    @Test func developerToolCachesAreNotSelectedByDefault() {
        let developer = RuleCatalog.rules().filter { $0.category == .developer }
        let optIn = ["developer.xcodeCaches", "developer.deviceSupport", "developer.frontendCaches", "developer.pythonCaches",
                     "developer.cargoCache", "developer.swiftPackageCache"]
        for id in optIn {
            let rule = developer.first { $0.id == id }
            #expect(rule != nil, "缺少规则 \(id)")
            #expect(rule?.selectedByDefault == false, "\(id) 应当默认不勾选")
        }
        #expect(RuleCatalog.chromiumAppCaches.selectedByDefault)  // 应用缓存本身可再生，默认勾选；运行中的应用会被跳过
    }

    @Test func deviceSupportKeepsTheNewestVersionsOfEachDevice() async throws {
        let home = try Home()
        defer { home.remove() }
        for (name, age) in [("17.0 (21A)", 400_000.0), ("17.2 (21C)", 300_000), ("17.4 (21E)", 200_000), ("18.0 (22A)", 100_000)] {
            try home.make("Library/Developer/Xcode/iOS DeviceSupport/\(name)/Symbols/a", age: age)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)],
                                                  ofItemAtPath: home.root.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport/\(name)").path)
        }
        try home.make("Library/Developer/Xcode/watchOS DeviceSupport/10.0/a", age: 100_000)  // 只有一个版本：不动

        let scan = try #require(await CleanEngine.scan([RuleCatalog.xcodeDeviceSupport], environment: home.environment()).first)
        #expect(Set(scan.items.map(\.url.lastPathComponent)) == ["17.0 (21A)", "17.2 (21C)"])  // 最新的 17.4 和 18.0 保留
        #expect(scan.items.first?.title.hasPrefix("iOS DeviceSupport › ") == true)
    }

    @Test func xcodeRulesAreBlockedWhileXcodeRuns() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.make("Library/Caches/com.apple.dt.Xcode/a")
        try home.make("Library/Developer/Xcode/Products/p/b")

        let blocked = try #require(await CleanEngine.scan([RuleCatalog.xcodeCaches], environment: home.environment(running: ["com.apple.dt.Xcode"])).first)
        #expect(blocked.blocked == .appRunning("Xcode"))
        let idle = try #require(await CleanEngine.scan([RuleCatalog.xcodeCaches], environment: home.environment()).first)
        #expect(Set(idle.items.map(\.url.lastPathComponent)) == ["com.apple.dt.Xcode", "p"])
    }

    @Test func toolCachesListOnlyTheSpecificFoldersAndLeaveTheRestOfDotCacheAlone() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.make(".cache/vite/a")
        try home.make(".cache/webpack/b")
        try home.make(".cache/huggingface/hub/model.bin")  // 模型：不碰
        try home.make(".cache/pre-commit/c")
        try home.make(".cargo/registry/cache/index/x.crate")
        try home.make(".cargo/registry/src/index/y/lib.rs")  // 已解压的源码：不碰
        let environment = home.environment()

        let frontend = try #require(await CleanEngine.scan([RuleCatalog.frontendToolCaches], environment: environment).first)
        #expect(Set(frontend.items.map(\.url.lastPathComponent)) == ["vite", "webpack"])
        let cargo = try #require(await CleanEngine.scan([RuleCatalog.rustDownloadCache], environment: environment).first)
        #expect(cargo.items.map(\.url.path) == [home.root.path + "/.cargo/registry/cache"])

        let scans = frontend.items.isEmpty ? [] : [frontend, cargo]
        _ = await CleanEngine.clean(scans, selected: [frontend.id, cargo.id], preferTrash: false, environment: environment, log: nil)
        #expect(!home.exists(".cache/vite"))
        #expect(!home.exists(".cargo/registry/cache"))
        #expect(home.exists(".cache/huggingface/hub/model.bin"))
        #expect(home.exists(".cache/pre-commit/c"))
        #expect(home.exists(".cargo/registry/src/index/y/lib.rs"))
    }

    // MARK: 安全守卫

    @Test func safetyGuardAllowsOnlyTheSpecificNewLocations() throws {
        let guardian = SafetyGuard(home: "/Users/tester")
        func url(_ relative: String) -> URL { URL(fileURLWithPath: "/Users/tester/" + relative) }
        for allowed in [".cache/vite", ".cache/vite/deps/a", ".node-gyp", ".cargo/registry/cache", ".cache/swift-package-manager/x",
                        "Library/Developer/Xcode/iOS DeviceSupport/17.0 (21A)", "Library/Developer/XCTestDevices/UUID",
                        "Library/Application Support/Slack/DawnCache"] {
            try guardian.validate(url(allowed))
        }
        for denied in [".cache", ".cache/huggingface", ".cache/pre-commit", ".cargo", ".cargo/registry/src", ".cargo/bin",
                       ".ssh/id_rsa", ".config/gh", "Library/Developer/Xcode/iOS DeviceSupport",
                       "Library/Application Support/Slack/Local Storage"] {
            #expect(throws: SafetyError.self, "\(denied)") { try guardian.validate(url(denied)) }
        }
    }
}
