import Foundation
import Testing
@testable import Cleaner

/// 删除入口的路径策略。这里只调用 validate，从不真的删任何东西
@Suite("路径策略")
struct PathPolicyTests {
    private let home = NSHomeDirectory()
    private var policy: PathPolicy { PathPolicy(home: home) }
    private let anywhere = URL(fileURLWithPath: "/")

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    /// 对抗语料：每一条都必须被拒绝，且理由是“受保护的位置”
    @Test func rejectsCriticalPaths() {
        let critical = [
            "/", "/System", "/System/Library/Caches/x", "/bin/ls", "/sbin/launchd", "/usr/bin/swift", "/usr/local",
            "/etc/hosts", "/private/etc/hosts", "/var/db/dslocal", "/private/var/db/receipts/x.bom", "/dev/null",
            "/Library", "/Library/Extensions/x.kext", "/Library/Keychains/System.keychain", "/Applications",
            "/Users", "/Users/Shared", "/Volumes", "/opt/homebrew", "/private/var/folders", "/tmp", "/private/tmp",
            // 大小写别名：APFS 默认不区分大小写
            "/SYSTEM/Library", "/system/library/CoreServices", "/users/shared", "/APPLICATIONS",
            // firmlink：数据卷下的同一个位置
            "/System/Volumes/Data/Users", "/System/Volumes/Data/Library",
            // 路径写法
            "/System//Library", "/System/./Library", "/Users/Shared/",
            // 家目录本身与顶层目录
            home, home + "/", home + "/Library", home + "/Documents", home + "/Desktop", home + "/Downloads",
            home + "/Library/Caches", home + "/Library/Application Support", home + "/Library/Containers",
            home + "/Library/Group Containers", home + "/.Trash", home + "/.config",
            // 凭据与同步数据
            home + "/.ssh", home + "/.ssh/id_ed25519", home + "/.gnupg/pubring.kbx",
            home + "/Library/Keychains/login.keychain-db", home + "/Library/Mobile Documents/com~apple~CloudDocs/a",
        ]
        for path in critical { expectCritical(path) }
    }

    /// 旧版只断言“抛了某个 PathPolicyError”，保护逻辑漏了也会被 outsideBase 之类顶替而测试照样绿；这里必须是受保护的位置
    private func expectCritical(_ path: String, sourceLocation: SourceLocation = #_sourceLocation) {
        do {
            try policy.validate(url(path), base: anywhere)
            Issue.record("应当拒绝 \(path)", sourceLocation: sourceLocation)
        } catch let error as PathPolicyError {
            guard case .critical = error else {
                Issue.record("\(path) 的拒绝原因应是受保护的位置，实际是 \(error)", sourceLocation: sourceLocation)
                return
            }
        } catch {
            Issue.record("意外的错误 \(error)", sourceLocation: sourceLocation)
        }
    }

    /// 标准化会把 /private/var 写成 /var：这些目录必须按标准化后的写法也被识别，不能只靠“初始化时它们恰好存在”的同一性兜底
    @Test func normalisedSystemFoldersAreProtectedByName() {
        for path in ["/var/folders", "/var/tmp", "/var/root", "/private/var/folders", "/private/var/tmp", "/private/var/root",
                     "/var/db/x", "/private/var/db/receipts", "/private/etc/hosts", "/private/tmp"] {
            expectCritical(path)
        }
        // 这几个目录自己受保护，里面的子项由调用方的范围决定
        #expect(policy.criticalName(for: "/var/folders") != nil)
        #expect(policy.criticalName(for: "/var/folders/ab/cd/C/com.example.app") == nil)
    }

    @Test func aBaseOfRootNoLongerHidesTheRealReason() throws {
        // base 为 "/" 时旧版恒返回 outsideBase；现在普通路径在区域内才放行，受保护路径仍然报受保护
        expectCritical("/private/var/folders")
        #expect(throws: PathPolicyError.outsideZones) { try policy.validate(url("/opt/example/file"), base: anywhere) }
    }

    @Test func refusesLocationsOutsideTheAllowedZones() {
        // 系统级残留只预览，策略本身就不允许这些位置，哪怕调用方放行
        for (path, base) in [("/Library/Application Support/Foo", "/Library/Application Support"),
                             ("/Library/LaunchDaemons/com.example.plist", "/Library/LaunchDaemons"),
                             ("/Users/Shared/Foo", "/Users/Shared"), ("/Volumes/Disk/Foo", "/Volumes/Disk")] {
            #expect(throws: PathPolicyError.outsideZones, "\(path)") {
                try policy.validate(url(path), base: URL(fileURLWithPath: base))
            }
        }
        // 应用程序文件夹里的应用、家目录里的东西、用户缓存区放行
        #expect(throws: Never.self) { try policy.validate(url("/Applications/Example.app"), base: URL(fileURLWithPath: "/Applications")) }
        #expect(throws: Never.self) { try policy.validate(url("/var/folders/ab/cd/C/com.example"), base: URL(fileURLWithPath: "/var/folders/ab/cd/C")) }
    }

    @Test func aBaseThatIsItselfASymlinkIsNotAValidTarget() throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let real = scratch.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = scratch.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        // 目标就是 base 本身时，旧版不检查叶子是不是链接
        #expect(throws: PathPolicyError.symlinkLeaf) { try PathPolicy(home: scratch.path).validate(link, base: link) }
    }

    @Test func rejectsMalformedPaths() {
        #expect(throws: PathPolicyError.notAbsolute) { try policy.validate(URL(string: "relative/x")!, base: anywhere) }
        #expect(throws: PathPolicyError.traversal) {
            try policy.validate(url(home + "/Library/Caches/../../Documents"), base: anywhere)
        }
        #expect(throws: PathPolicyError.controlCharacter) {
            try policy.validate(url(home + "/Library/Caches/a\u{0007}b"), base: anywhere)
        }
        #expect(throws: PathPolicyError.controlCharacter) {
            try policy.validate(url(home + "/Library/Caches/a\nb"), base: anywhere)
        }
    }

    @Test func allowsOrdinaryItemsBelowTheBase() throws {
        let base = URL(fileURLWithPath: home)
        try policy.validate(url(home + "/Library/Caches/com.example.app"), base: base)
        try policy.validate(url(home + "/Library/Application Support/Example"), base: base)
        // 名字里带两个点不算穿越
        try policy.validate(url(home + "/Library/Caches/Firefox..files"), base: base)
    }

    @Test func rejectsPathsOutsideTheBase() {
        #expect(throws: PathPolicyError.outsideBase) {
            try policy.validate(url("/Users/someone-else/Library/Caches/x"), base: URL(fileURLWithPath: home))
        }
    }

    // MARK: 符号链接

    private func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("openstats-policy-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func rejectsSymlinkLeavesAndSymlinkedAncestors() throws {
        let base = try scratch()
        defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: real.appendingPathComponent("file"))
        let link = base.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let policy = PathPolicy(home: base.path)

        try policy.validate(real.appendingPathComponent("file"), base: base)
        #expect(throws: PathPolicyError.symlinkLeaf) { try policy.validate(link, base: base) }
        #expect(throws: PathPolicyError.self) { try policy.validate(link.appendingPathComponent("file"), base: base) }
    }

    /// 属性：每个关键根，只要有一条符号链接指向它，经由这条链接的任何路径都被拒绝
    @Test func rejectsSymlinksPointingAtEveryCriticalRoot() throws {
        let base = try scratch()
        defer { try? FileManager.default.removeItem(at: base) }
        let policy = PathPolicy(home: base.path)
        for (index, target) in ["/System", "/usr", "/bin", "/etc", "/Library", "/Applications", "/Users", "/var/db"].enumerated() {
            let link = base.appendingPathComponent("alias\(index)")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: target))
            #expect(throws: PathPolicyError.redirected("alias\(index)"), "经链接指向 \(target)") {
                try policy.validate(link.appendingPathComponent("child"), base: base)
            }
            #expect(throws: PathPolicyError.symlinkLeaf, "链接本身 → \(target)") { try policy.validate(link, base: base) }
        }
    }

    /// 同一性匹配：路径写法上看不出来，但实际就是受保护目录（这里让 base 自己是指向受保护目录的链接）
    @Test func rejectsPathsThatAreTheSameObjectAsAProtectedTree() throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let protected = scratch.appendingPathComponent("protected")
        try FileManager.default.createDirectory(at: protected.appendingPathComponent("inside"), withIntermediateDirectories: true)
        let alias = scratch.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: protected)

        let policy = PathPolicy(home: scratch.path, additionalTrees: [protected.path])
        // alias 这个 base 解析后就是受保护目录；alias/inside 没有经过任何下级链接，字面上也不在保护列表里
        #expect(throws: PathPolicyError.self) { try policy.validate(alias.appendingPathComponent("inside"), base: alias) }
        // 对照：没把它列为受保护时同样的路径是放行的，说明上面确实是同一性匹配在起作用
        try PathPolicy(home: scratch.path).validate(alias.appendingPathComponent("inside"), base: alias)
    }
}
