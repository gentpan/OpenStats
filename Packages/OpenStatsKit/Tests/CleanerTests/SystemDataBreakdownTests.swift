import Foundation
import Testing
@testable import Cleaner

/// 一个临时目录当家目录（或临时目录、共享文件夹），测完删掉
private struct Folder {
    let root: URL

    init(_ name: String = "home") throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openstats-breakdown-\(name)-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var path: String { root.path }

    @discardableResult
    func file(_ relative: String, age: TimeInterval = 7200) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 8192).write(to: url)
        try backdate(url, by: age)
        return url
    }

    func plist(_ relative: String, _ values: [String: Any]) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0).write(to: url)
    }

    /// 条目和沿途新建的目录一起调老
    func backdate(_ url: URL, by age: TimeInterval) throws {
        let date = Date().addingTimeInterval(-age)
        var current = url
        while current.path.count > root.path.count {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: current.path)
            current = current.deletingLastPathComponent()
        }
    }

    func exists(_ relative: String) -> Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(relative).path) }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private func environment(home: Folder, temporary: Folder? = nil, running: Set<String> = [], fullDiskAccess: Bool = true,
                         apps: [InstalledApp]? = nil) -> CleanEnvironment {
    CleanEnvironment(home: home.path, runningBundleIdentifiers: { running }, hasFullDiskAccess: fullDiskAccess,
                     applications: home.path + "/Applications", temporaryDirectory: temporary?.path, installedApps: { apps })
}

private func scan(_ rule: CleanRule, _ environment: CleanEnvironment) async throws -> RuleScan {
    try #require(await CleanEngine.scan([rule], environment: environment).first)
}

private func app(_ name: String, _ identifier: String) -> InstalledApp {
    InstalledApp(url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, bundleIdentifier: identifier,
                 version: nil, teamIdentifier: nil)
}

@Suite("系统数据分析与补充规则", .serialized)
struct SystemDataBreakdownTests {
    // MARK: 临时文件

    @Test func onlyTemporaryItemsUntouchedForThreeDaysAreListedAndCleaned() async throws {
        let home = try Folder()
        let temporary = try Folder("tmp")
        defer { home.remove(); temporary.remove() }
        let old: TimeInterval = 4 * 86_400
        try temporary.file("stale.zip", age: old)
        try temporary.file("stale-folder/a/b.bin", age: old)
        try temporary.file("fresh.txt", age: 3600)
        try temporary.file("mixed/old.bin", age: old)
        try temporary.file("mixed/new.bin", age: 60)                  // 目录里还有新文件：可能在用
        try temporary.backdate(temporary.root.appendingPathComponent("mixed"), by: old)
        try temporary.file("com.apple.Safari/x.bin", age: old)       // 系统进程的：不碰
        try temporary.file("com.vendor.Running/x.bin", age: old)     // 所属应用在运行：不碰
        let env = environment(home: home, temporary: temporary, running: ["com.vendor.Running"])

        let result = try await scan(RuleCatalog.temporaryFiles, env)
        #expect(Set(result.items.map(\.url.lastPathComponent)) == ["stale.zip", "stale-folder"])
        #expect(result.skippedCount == 1)
        #expect(result.items.allSatisfy { $0.title.hasSuffix($0.url.lastPathComponent) })
        #expect(RuleCatalog.temporaryFiles.selectedByDefault == false)

        let report = await CleanEngine.clean([result], selected: [result.id], preferTrash: false, environment: env, log: nil)
        #expect(report.removedCount == 2)
        #expect(!temporary.exists("stale.zip") && !temporary.exists("stale-folder"))
        #expect(temporary.exists("fresh.txt") && temporary.exists("mixed/new.bin") && temporary.exists("com.apple.Safari/x.bin"))
        #expect(temporary.exists("com.vendor.Running/x.bin"))
    }

    @Test func withoutATemporaryDirectoryNothingIsScanned() async throws {
        let home = try Folder()
        defer { home.remove() }
        let result = try await scan(RuleCatalog.temporaryFiles, environment(home: home))
        #expect(result.items.isEmpty && result.blocked == nil)
    }

    @Test func safetyGuardAllowsOnlyDirectChildrenOfTheTemporaryDirectory() throws {
        let guardian = SafetyGuard(home: "/Users/tester", temporary: "/private/var/folders/ab/xyz/T/")
        try guardian.validate(URL(fileURLWithPath: "/var/folders/ab/xyz/T/stale.zip"))
        try guardian.validate(URL(fileURLWithPath: "/private/var/folders/ab/xyz/T/stale-folder"))
        for denied in ["/var/folders/ab/xyz/T", "/var/folders/ab/xyz/T/a/b", "/var/folders/ab/xyz/C/x",
                       "/var/folders/ab/xyz/T/OpenStats-update", "/tmp/x"] {
            #expect(throws: SafetyError.self, "\(denied)") { try guardian.validate(URL(fileURLWithPath: denied)) }
        }
        #expect(throws: SafetyError.self) {
            try SafetyGuard(home: "/Users/tester").validate(URL(fileURLWithPath: "/var/folders/ab/xyz/T/stale.zip"))
        }
    }

    // MARK: Maven、Go、PyTorch、Android

    @Test func mavenGoPyTorchAndAndroidListTheirOwnPlaces() async throws {
        let home = try Folder()
        defer { home.remove() }
        try home.file(".m2/repository/org/junit/junit.jar")
        try home.file(".m2/settings.xml")
        try home.file("go/pkg/mod/github.com/x/y/z.go")
        try home.file(".cache/torch/hub/checkpoints/resnet50.pth")
        try home.file(".android/avd/Pixel_8.avd/userdata.img")
        try home.file(".android/avd/Pixel_8.ini")
        try home.file("Library/Android/sdk/system-images/android-35/google_apis/arm64-v8a/system.img")
        let env = environment(home: home)

        let maven = try await scan(RuleCatalog.mavenRepository, env)
        #expect(maven.items.map(\.url.path) == [home.path + "/.m2/repository"])
        #expect(RuleCatalog.mavenRepository.selectedByDefault == false)
        _ = await CleanEngine.clean([maven], selected: [maven.id], preferTrash: false, environment: env, log: nil)
        #expect(!home.exists(".m2/repository") && home.exists(".m2/settings.xml"))

        let go = try await scan(RuleCatalog.goModules, env)
        #expect(go.items.count == 1 && !go.isCleanable)

        let models = try await scan(RuleCatalog.aiModels, env)
        #expect(models.items.map(\.title) == ["PyTorch › resnet50.pth"])

        let android = try await scan(RuleCatalog.androidEmulators, env)
        #expect(Set(android.items.map(\.title)) == ["模拟器 › Pixel_8", "系统镜像 › android-35/google_apis/arm64-v8a"])
        #expect(!android.isCleanable)
    }

    // MARK: 归属

    @Test func ownersAreRecognisedByIdentifierNameAndGroup() {
        let index = AppOwnerIndex(apps: [app("Slack", "com.tinyspeck.slackmacgap"), app("微信", "com.tencent.xinWeChat")])
        #expect(index.owner(of: "com.tinyspeck.slackmacgap", location: .container) == .app("Slack"))
        #expect(index.owner(of: "com.tencent.xinWeChat.WeChatFinderExtension", location: .container) == .app("微信"))
        #expect(index.owner(of: "Slack", location: .applicationSupport) == .app("Slack"))
        #expect(index.owner(of: "5A4RE8SF68.com.tencent.xinWeChat", location: .groupContainer) == .app("微信"))
        #expect(index.owner(of: "group.com.tinyspeck.slackmacgap", location: .groupContainer) == .app("Slack"))
        #expect(index.owner(of: "com.apple.Notes", location: .container) == .system)
        #expect(index.owner(of: "group.com.apple.notes", location: .groupContainer) == .system)
        #expect(index.owner(of: "com.gone.oldapp", location: .container) == .missing)
        #expect(index.owner(of: "com.gone.oldapp", location: .applicationSupport) == .missing)
        // 共享容器的组名可以随意起，认不出不等于应用不在
        #expect(index.owner(of: "group.net.whatever.shared", location: .groupContainer) == .unknown)
        #expect(index.owner(of: "Google", location: .applicationSupport) == .unknown)
        // 没读到应用清单：不说“没找到”
        #expect(AppOwnerIndex(apps: nil).owner(of: "com.gone.oldapp", location: .container) == .unknown)
    }

    @Test func appDataListsBigFoldersByOwnerAndSkipsContainersWithoutFullDiskAccess() async throws {
        let home = try Folder()
        defer { home.remove() }
        try home.file("Library/Application Support/Slack/IndexedDB/a.db")
        try home.file("Library/Application Support/com.gone.oldapp/data.bin")
        try home.file("Library/Application Support/MobileSync/Backup/x/Manifest.db")    // 设备备份单独列
        try home.file("Library/Containers/6F1B2C3D-UUID/Data/Library/a.bin")
        try home.plist("Library/Containers/6F1B2C3D-UUID/.com.apple.containermanagerd.metadata.plist",
                       ["MCMMetadataIdentifier": "com.tinyspeck.slackmacgap"])
        try home.file("Library/Containers/com.apple.mail/Data/big.mbox")              // 邮件不算系统数据
        try home.file("Library/Group Containers/group.com.tinyspeck.slackmacgap/a.bin")
        let apps = [app("Slack", "com.tinyspeck.slackmacgap")]
        let rule = RuleCatalog.appDataRule(threshold: 1)

        let full = try await scan(rule, environment(home: home, apps: apps))
        #expect(Set(full.items.map(\.title)) == ["Slack › Application Support", "com.gone.oldapp · 没找到对应的应用",
                                                 "Slack › 沙盒容器", "Slack › 共享容器"])
        #expect(!full.isCleanable)

        let limited = try await scan(rule, environment(home: home, fullDiskAccess: false, apps: apps))
        #expect(Set(limited.items.map(\.title)) == ["Slack › Application Support", "com.gone.oldapp · 没找到对应的应用"])

        let small = try await scan(RuleCatalog.appDataRule(threshold: 1_000_000), environment(home: home, apps: apps))
        #expect(small.items.isEmpty)
    }

    // MARK: 其余大目录

    @Test func largeFoldersSkipWhatOtherRulesExplainAndNameKnownOnes() async throws {
        let home = try Folder()
        let shared = try Folder("shared")
        defer { home.remove(); shared.remove() }
        for relative in ["Library/Caches/x/a", "Library/Application Support/x/a", "Library/Mail/V10/a",
                         "Library/Developer/Xcode/DerivedData/x/a", ".npm/_cacache/a", ".cache/huggingface/hub/a",
                         "Documents/big.mov", ".Trash/a"] {
            try home.file(relative)
        }
        for relative in ["Library/Metadata/a", "Library/Developer/CoreSimulator/Devices/x/a", ".rustup/toolchains/a",
                         ".cache/some-tool/a", "go/pkg/mod/a", "Library/Weird Vendor/a"] {
            try home.file(relative)
        }
        try shared.file("BlueStacks/disk.img")
        try FileManager.default.createSymbolicLink(atPath: home.path + "/.linked", withDestinationPath: shared.path)

        let result = try await scan(RuleCatalog.largeFoldersRule(threshold: 1, shared: shared.path), environment(home: home))
        #expect(Set(result.items.map(\.title)) == [
            "Spotlight 等系统索引 · ~/Library/Metadata",
            "模拟器设备的数据 · ~/Library/Developer/CoreSimulator/Devices",
            "Rust 工具链（rustup） · ~/.rustup",
            "~/.cache/some-tool",
            "Go 模块与工具（~/go） · ~/go",
            "~/Library/Weird Vendor",
            "共享 › BlueStacks",
        ])
        #expect(!result.isCleanable)
    }

    @Test func analysisRulesAreNeverCleanedEvenIfSelected() async throws {
        let home = try Folder()
        defer { home.remove() }
        try home.file("Library/Application Support/com.gone.oldapp/data.bin")
        let env = environment(home: home, apps: [])
        let result = try await scan(RuleCatalog.appDataRule(threshold: 1), env)
        #expect(result.items.count == 1)
        let report = await CleanEngine.clean([result], selected: [result.id], preferTrash: false, environment: env, log: nil)
        #expect(report.removedCount == 0)
        #expect(home.exists("Library/Application Support/com.gone.oldapp/data.bin"))
        let analysisRules = RuleCatalog.rules().filter { $0.category == .systemData }
        #expect(analysisRules.count == 2 && analysisRules.allSatisfy { $0.isManual })
    }
}
