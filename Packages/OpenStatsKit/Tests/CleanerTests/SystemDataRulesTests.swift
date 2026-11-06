import Foundation
import os
import Testing
@testable import Cleaner

/// 记录被移到废纸篓的路径，不真的动用户的废纸篓
private final class RecordingTrasher: Trasher, @unchecked Sendable {
    private let trashed = OSAllocatedUnfairLock(initialState: [URL]())
    var urls: [URL] { trashed.withLock { $0 } }

    func trash(_ url: URL) async throws -> URL? {
        trashed.withLock { $0.append(url) }
        return nil
    }
}

private struct Fixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("openstats-sysdata-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var applications: String { root.path + "/Applications" }

    @discardableResult
    func file(_ relative: String, contents: Data = Data(repeating: 0x41, count: 4096), age: TimeInterval = 7200) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url)
        try backdate(url, by: age)
        return url
    }

    func plist(_ relative: String, _ values: [String: Any], age: TimeInterval = 7200) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        try file(relative, contents: data, age: age)
    }

    /// 把条目和沿途新建的目录都调老：最近改过的会被当成“正在使用”
    func backdate(_ url: URL, by age: TimeInterval) throws {
        let date = Date().addingTimeInterval(-age)
        var current = url
        while current.path.count > root.path.count {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: current.path)
            current = current.deletingLastPathComponent()
        }
    }

    func environment(running: Set<String> = [], names: Set<String> = [], fullDiskAccess: Bool = true,
                     trasher: any Trasher = RecordingTrasher(), simulators: SimulatorInventory? = nil) -> CleanEnvironment {
        CleanEnvironment(home: root.path, runningBundleIdentifiers: { running }, runningApplicationNames: { names },
                         trasher: trasher, hasFullDiskAccess: fullDiskAccess, applications: applications,
                         simulators: { simulators })
    }

    func exists(_ relative: String) -> Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(relative).path) }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private func scan(_ rule: CleanRule, _ environment: CleanEnvironment) async throws -> RuleScan {
    try #require(await CleanEngine.scan([rule], environment: environment).first)
}

@Suite("系统数据规则", .serialized)
struct SystemDataRulesTests {
    // MARK: 设备备份

    private func seedBackups(_ fixture: Fixture) throws {
        let date = ISO8601DateFormatter().date(from: "2026-10-02T12:00:00Z")!
        try fixture.plist("Library/Application Support/MobileSync/Backup/00008110-AAAA/Info.plist",
                          ["Device Name": "Peter 的 iPhone", "Last Backup Date": date])
        try fixture.file("Library/Application Support/MobileSync/Backup/00008110-AAAA/Manifest.db")
        try fixture.plist("Library/Application Support/MobileSync/Backup/00008027-BBBB/Info.plist", ["Device Name": "iPad"])
        try fixture.file("Library/Application Support/MobileSync/Backup/stray.txt")                  // 不是备份目录
        try fixture.file("Library/Application Support/MobileSync/Backup/00008110-CCCC/Manifest.db")  // 没有 Info.plist，认不出是谁的
    }

    @Test func listsEachDeviceBackupByDeviceNameAndDate() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try seedBackups(fixture)

        let result = try await scan(RuleCatalog.deviceBackups, fixture.environment())
        let titles = Set(result.items.map(\.title))
        #expect(titles.count == 2)
        #expect(titles.contains("iPad"))
        #expect(titles.contains { $0.hasPrefix("Peter 的 iPhone · 2026-10-0") })
        #expect(RuleCatalog.deviceBackups.selectedByDefault == false)
        #expect(RuleCatalog.deviceBackups.policy == .trash)
    }

    @Test func deviceBackupsNeedFullDiskAccessAndAreNotProbedWithoutIt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try seedBackups(fixture)

        let result = try await scan(RuleCatalog.deviceBackups, fixture.environment(fullDiskAccess: false))
        #expect(result.blocked == .needsFullDiskAccess)
        #expect(result.items.isEmpty)
    }

    @Test func excludedBackupsStayAndOnlyTheChosenOneGoesToTheTrash() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try seedBackups(fixture)
        let trasher = RecordingTrasher()
        let environment = fixture.environment(trasher: trasher)
        let result = try await scan(RuleCatalog.deviceBackups, environment)
        let keep = try #require(result.items.first { $0.title == "iPad" })

        // 用户偏好“直接删除”也不影响：备份规则本身就是移到废纸篓
        let report = await CleanEngine.clean([result], selected: [result.id], excluded: [keep.id], preferTrash: false,
                                             environment: environment, log: nil)
        #expect(report.removedCount == 1)
        #expect(report.freedBytes == 0)
        #expect(trasher.urls.map(\.lastPathComponent) == ["00008110-AAAA"])
    }

    @Test func backupBeingWrittenIsLeftAlone() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.plist("Library/Application Support/MobileSync/Backup/00008110-LIVE/Info.plist", ["Device Name": "iPhone"], age: 60)

        let result = try await scan(RuleCatalog.deviceBackups, fixture.environment())
        #expect(result.items.isEmpty)
        #expect(result.skippedCount == 1)
    }

    // MARK: 系统更新包与安装器

    @Test func firmwareRuleListsOnlyIPSWFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("Library/iTunes/iPhone Software Updates/iPhone17,1_26.1_Restore.ipsw")
        try fixture.file("Library/iTunes/iPad Software Updates/iPad16,3_26.0_Restore.ipsw")
        try fixture.file("Library/iTunes/iPhone Software Updates/notes.txt")
        try fixture.file("Library/iTunes/iTunes Library.itl")

        let result = try await scan(RuleCatalog.deviceFirmware, fixture.environment())
        #expect(Set(result.items.map(\.url.lastPathComponent)) == ["iPhone17,1_26.1_Restore.ipsw", "iPad16,3_26.0_Restore.ipsw"])
    }

    private func makeApp(_ fixture: Fixture, _ name: String, bundleID: String) throws {
        try fixture.plist("Applications/\(name).app/Contents/Info.plist", ["CFBundleIdentifier": bundleID])
        try fixture.file("Applications/\(name).app/Contents/SharedSupport/SharedSupport.dmg")
    }

    @Test func installerRuleOnlyTakesApplesMacOSInstallers() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try makeApp(fixture, "Install macOS Sequoia", bundleID: "com.apple.InstallAssistant.macOSSequoia")
        try makeApp(fixture, "Install macOS Fake", bundleID: "com.example.fake")       // 名字像，包名不是苹果的
        try makeApp(fixture, "Safari Helper", bundleID: "com.apple.InstallAssistant.x") // 包名像，名字不是
        let trasher = RecordingTrasher()
        let environment = fixture.environment(trasher: trasher)

        let result = try await scan(RuleCatalog.macOSInstallers, environment)
        #expect(result.items.map(\.title) == ["Install macOS Sequoia"])

        let report = await CleanEngine.clean([result], selected: [result.id], preferTrash: false, environment: environment, log: nil)
        #expect(report.removedCount == 1)
        #expect(trasher.urls.map(\.lastPathComponent) == ["Install macOS Sequoia.app"])
    }

    @Test func runningInstallerIsNotTouched() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try makeApp(fixture, "Install macOS Sequoia", bundleID: "com.apple.InstallAssistant.macOSSequoia")

        let result = try await scan(RuleCatalog.macOSInstallers, fixture.environment(names: ["install macos sequoia"]))
        #expect(result.items.isEmpty)
        #expect(result.skippedCount == 1)
    }

    @Test func applicationsRequestsUseTheApplicationsFolderAsBaseAndMayAskForAuthorization() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let environment = fixture.environment()
        let installer = URL(fileURLWithPath: fixture.applications + "/Install macOS Sequoia.app")
        let request = CleanEngine.request(for: installer, rule: RuleCatalog.macOSInstallers, identity: nil, mode: .trash, size: 0,
                                          environment: environment)
        #expect(request.base.path == fixture.applications)
        #expect(request.route == .interactive)

        let cache = URL(fileURLWithPath: fixture.root.path + "/Library/Caches/x")
        let other = CleanEngine.request(for: cache, rule: RuleCatalog.userCaches, identity: nil, mode: .permanent, size: 0,
                                        environment: environment)
        #expect(other.base.path == fixture.root.path)
        #expect(other.route == .standard)
    }

    // MARK: 本地模型

    @Test func aiModelsAreListedPerModelAndLeaveTheRestOfTheCacheAlone() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file(".cache/huggingface/hub/models--meta-llama--Llama-3-8B/blobs/abc")
        try fixture.file(".cache/huggingface/hub/datasets--squad/blobs/def")
        try fixture.file(".cache/huggingface/hub/.locks/models--meta-llama--Llama-3-8B/abc.lock")
        try fixture.file(".cache/huggingface/hub/version.txt")
        try fixture.file(".cache/huggingface/token")
        try fixture.file(".lmstudio/models/lmstudio-community/Qwen3-8B-GGUF/model.gguf")
        try fixture.file(".lmstudio/models/README.md")

        let result = try await scan(RuleCatalog.aiModels, fixture.environment())
        #expect(Set(result.items.map(\.title)) == ["Hugging Face › meta-llama/Llama-3-8B", "Hugging Face › 数据集 squad",
                                                   "LM Studio › lmstudio-community/Qwen3-8B-GGUF"])

        let blocked = try await scan(RuleCatalog.aiModels, fixture.environment(names: ["lm studio"]))
        #expect(blocked.items.map(\.title).allSatisfy { $0.hasPrefix("Hugging Face") })
        #expect(blocked.skippedCount == 1)
    }

    @Test func ollamaModelsAreOnlyReportedWithTheirManifestSizes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        func manifest(_ sizes: [Int]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["config": ["size": 100], "layers": sizes.map { ["size": $0] }])
        }
        try fixture.file(".ollama/models/manifests/registry.ollama.ai/library/llama3/8b", contents: manifest([4_000_000, 500]))
        try fixture.file(".ollama/models/manifests/registry.ollama.ai/someone/coder/latest", contents: manifest([1_000]))
        try fixture.file(".ollama/models/blobs/sha256-aaa")

        let rule = RuleCatalog.ollamaModels
        #expect(rule.isManual)
        let result = try await scan(rule, fixture.environment())
        #expect(result.items.map(\.title) == ["llama3:8b", "someone/coder:latest"])
        #expect(result.items.first?.size == 4_000_600)
        #expect(!result.isCleanable)

        // 即使被选中，仅提示的规则也不会进删除入口
        let report = await CleanEngine.clean([result], selected: [rule.id], preferTrash: false, environment: fixture.environment(), log: nil)
        #expect(report.removedCount == 0)
        #expect(fixture.exists(".ollama/models/manifests/registry.ollama.ai/library/llama3/8b"))
    }

    // MARK: 邮件

    @Test func mailDownloadsNeedFullDiskAccessAndWaitForMailToQuit() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/1A2B/report.pdf")
        try fixture.file("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/3C4D/a.png")
        try fixture.file("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/3C4D/b.png")

        let withoutAccess = try await scan(RuleCatalog.mailDownloads, fixture.environment(fullDiskAccess: false))
        #expect(withoutAccess.blocked == .needsFullDiskAccess)
        let running = try await scan(RuleCatalog.mailDownloads, fixture.environment(running: ["com.apple.mail"]))
        #expect(running.blocked == .appRunning("邮件"))
        let idle = try await scan(RuleCatalog.mailDownloads, fixture.environment())
        #expect(Set(idle.items.map(\.title)) == ["report.pdf", "a.png 等 2 个文件"])
    }

    // MARK: 虚拟磁盘

    @Test func containerDisksAreReportOnlyAndGatedOnFullDiskAccess() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        try fixture.file(".colima/_lima/colima/diffdisk")

        let blocked = try await scan(RuleCatalog.containerDisks, fixture.environment(fullDiskAccess: false))
        #expect(blocked.blocked == .needsFullDiskAccess)
        let result = try await scan(RuleCatalog.containerDisks, fixture.environment())
        #expect(Set(result.items.map(\.title)) == ["Docker Desktop", "Colima"])
        #expect(!result.isCleanable)
    }

    @Test func virtualMachinesSkipProtectedPlacesWithoutFullDiskAccess() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("Parallels/Windows 11.pvm/harddisk.hdd")
        try fixture.file("Parallels/notes.txt")
        try fixture.file(".tart/vms/sonoma-base/disk.img")
        try fixture.file("Library/Containers/com.utmapp.UTM/Data/Documents/Ubuntu.utm/Data/disk.qcow2")

        let limited = try await scan(RuleCatalog.virtualMachines, fixture.environment(fullDiskAccess: false))
        #expect(Set(limited.items.map(\.title)) == ["Parallels › Windows 11", "Tart › sonoma-base"])
        let full = try await scan(RuleCatalog.virtualMachines, fixture.environment())
        #expect(Set(full.items.map(\.title)) == ["Parallels › Windows 11", "Tart › sonoma-base", "UTM › Ubuntu"])
    }

    // MARK: 模拟器

    @Test func parsesSimctlOutput() throws {
        let devices = Data(#"""
        {"devices": {
          "com.apple.CoreSimulator.SimRuntime.iOS-17-0": [
            {"name": "iPhone 15", "isAvailable": false, "dataPath": "/tmp/Devices/AAA/data", "udid": "AAA",
             "availabilityError": "runtime profile not found"}],
          "com.apple.CoreSimulator.SimRuntime.iOS-27-2": [
            {"name": "iPhone 18 Pro", "isAvailable": true, "dataPath": "/tmp/Devices/BBB/data", "udid": "BBB"}]
        }}
        """#.utf8)
        let runtimes = Data(#"""
        {"11098E26": {"runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-2", "version": "27.2", "build": "24B8117",
                      "sizeBytes": 8315434484, "deletable": true, "lastUsedAt": "2026-11-05T07:11:13Z", "path": "/System/x"},
         "22222222": {"runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.xrOS-2-0", "version": "2.0", "build": "22N",
                      "sizeBytes": 7000000000, "deletable": true, "path": "/System/y"},
         "33333333": {"runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-16-0", "version": "16.0", "build": "20A",
                      "sizeBytes": 6000000000, "deletable": false}}
        """#.utf8)

        let inventory = SimulatorInventory(devices: try #require(SimulatorInventory.parseDevices(devices)),
                                           runtimes: try #require(SimulatorInventory.parseRuntimes(runtimes)))
        let unavailable = inventory.unavailableDeviceEntries()
        #expect(unavailable.map(\.title) == ["iPhone 15 · iOS 17.0"])
        #expect(unavailable.first?.url.path == "/tmp/Devices/AAA")

        // 有设备在用的、系统不让删的都不算；visionOS 的旧名字要换过来
        let unused = inventory.unusedRuntimeEntries()
        #expect(unused.map(\.title) == ["visionOS 2.0 (22N) · 从未使用"])
        #expect(unused.first?.size == 7_000_000_000)
    }

    @Test func simulatorRulesReadTheInjectedInventoryAndAreReportOnly() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let device = try fixture.file("Library/Developer/CoreSimulator/Devices/AAA/data/Containers/x")
        let inventory = SimulatorInventory(
            devices: [.init(name: "iPhone 15", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-17-0", isAvailable: false,
                            dataPath: device.deletingLastPathComponent().deletingLastPathComponent().path)],
            runtimes: [])
        let result = try await scan(RuleCatalog.unavailableSimulators, fixture.environment(simulators: inventory))
        #expect(result.items.map(\.title) == ["iPhone 15 · iOS 17.0"])
        #expect(!result.isCleanable)

        let none = try await scan(RuleCatalog.unavailableSimulators, fixture.environment())
        #expect(none.items.isEmpty && none.blocked == nil)
    }

    // MARK: 开发工具

    @Test func newDeveloperCachesListOnlyTheirOwnFolders() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file(".gradle/caches/modules-2/files-2.1/a.jar")
        try fixture.file(".gradle/wrapper/dists/gradle-8.10-bin/abc/gradle.zip")
        try fixture.file(".gradle/gradle.properties")             // 用户配置：不碰
        try fixture.file("Library/pnpm/store/v10/files/00/abc")
        try fixture.file("Library/pnpm/pnpm")                     // pnpm 本身：不碰
        try fixture.file(".bun/install/cache/react@19/index.js")
        try fixture.file(".bun/bin/bun")
        try fixture.file(".yarn/berry/cache/react.zip")           // PnP 项目直接读这里：不碰
        try fixture.file(".cache/uv/wheels-v5/x.whl")
        let environment = fixture.environment()

        let gradle = try await scan(RuleCatalog.gradleCaches, environment)
        #expect(Set(gradle.items.map(\.url.lastPathComponent)) == ["caches", "gradle-8.10-bin"])
        let javascript = try await scan(RuleCatalog.javascriptPackageCaches, environment)
        #expect(Set(javascript.items.map(\.url.path)) == [fixture.root.path + "/Library/pnpm/store", fixture.root.path + "/.bun/install/cache"])
        let python = try await scan(RuleCatalog.pythonToolCaches, environment)
        #expect(python.items.map(\.url.lastPathComponent) == ["uv"])

        _ = await CleanEngine.clean([gradle, javascript], selected: [gradle.id, javascript.id], preferTrash: false,
                                    environment: environment, log: nil)
        #expect(!fixture.exists(".gradle/caches"))
        #expect(!fixture.exists("Library/pnpm/store"))
        #expect(fixture.exists(".gradle/gradle.properties"))
        #expect(fixture.exists("Library/pnpm/pnpm"))
        #expect(fixture.exists(".bun/bin/bun"))
        #expect(fixture.exists(".yarn/berry/cache/react.zip"))

        let blocked = try await scan(RuleCatalog.gradleCaches, fixture.environment(running: ["com.google.android.studio"]))
        #expect(blocked.blocked == .appRunning("Android Studio"))
    }

    @Test func newRulesAreAllOptIn() {
        for rule in RuleCatalog.rules() where rule.category == .large
            || ["developer.gradle", "developer.jsPackageCaches", "developer.unavailableSimulators",
                "developer.unusedSimulatorRuntimes"].contains(rule.id) {
            #expect(rule.selectedByDefault == false, "\(rule.id) 应当默认不勾选")
            if rule.category == .large && !rule.isManual { #expect(rule.policy == .trash, "\(rule.id) 应当移到废纸篓") }
        }
        #expect(Set(RuleCatalog.rules().map(\.id)).count == RuleCatalog.rules().count)
    }

    // MARK: 安全守卫

    @Test func safetyGuardAllowsTheNewLocationsButNotTheirParents() throws {
        let home = "/Users/tester"
        let guardian = SafetyGuard(home: home)
        func url(_ relative: String) -> URL { URL(fileURLWithPath: home + "/" + relative) }
        for allowed in ["Library/Application Support/MobileSync/Backup/00008110-AAAA",
                        "Library/iTunes/iPhone Software Updates/x.ipsw",
                        "Library/Containers/com.apple.mail/Data/Library/Mail Downloads/1A2B",
                        ".cache/huggingface/hub/models--a--b", ".lmstudio/models/pub/model",
                        ".gradle/caches", ".gradle/wrapper/dists/gradle-8-bin", "Library/pnpm/store", ".bun/install/cache", ".cache/uv"] {
            try guardian.validate(url(allowed))
        }
        for denied in ["Library/Application Support/MobileSync/Backup", "Library/Application Support/MobileSync",
                       "Library/Application Support/MobileSync/Other/x", "Library/iTunes/iTunes Library.itl",
                       "Library/Containers/com.apple.mail/Data/Library/Mail/V10", "Library/Containers/com.apple.mail",
                       ".cache/huggingface/hub", ".cache/huggingface/token", ".lmstudio/models", ".gradle",
                       ".gradle/gradle.properties", "Library/pnpm", "Library/pnpm/pnpm", ".bun/bin/bun", ".yarn/berry/cache",
                       // 更具体的那条放行规则不能让 Application Support 的其他内容跟着放行
                       "Library/Application Support/Slack/Local Storage"] {
            #expect(throws: SafetyError.self, "\(denied)") { try guardian.validate(url(denied)) }
        }
        #expect(throws: SafetyError.self) { try guardian.validate(URL(fileURLWithPath: "/Applications/Safari.app")) }
        #expect(throws: SafetyError.self) { try guardian.validate(URL(fileURLWithPath: "/Applications/Install macOS Sequoia.app/Contents")) }
    }
}
