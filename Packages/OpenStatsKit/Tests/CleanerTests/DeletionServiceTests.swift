import Foundation
import os
import Testing
@testable import Cleaner

/// 记录被要求移到废纸篓的路径；失败时抛出
private final class StubTrasher: Trasher, @unchecked Sendable {
    private let trashed = OSAllocatedUnfairLock(initialState: [URL]())
    var failure: Error?
    let destination: URL?

    init(destination: URL? = nil) { self.destination = destination }

    var trashedURLs: [URL] { trashed.withLock { $0 } }

    func trash(_ url: URL) async throws -> URL? {
        if let failure { throw failure }
        trashed.withLock { $0.append(url) }
        return destination?.appendingPathComponent(url.lastPathComponent)
    }
}

private struct Sandbox {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openstats-deletion-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @discardableResult
    func file(_ relative: String, age: TimeInterval = 3600) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("data".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
        return url
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

private func service(_ sandbox: Sandbox, running: RunningApps = .known([]), trasher: StubTrasher = StubTrasher(),
                     scope: @escaping DeletionService.Scope = { _ in }, log: CleanLog? = nil) -> DeletionService {
    DeletionService(home: sandbox.root.path, scope: scope, running: { running }, standardTrasher: trasher, log: log)
}

/// 与真实流程一致：身份在“扫描”（构造请求）这一刻采集
private func request(_ url: URL, in sandbox: Sandbox, mode: DeletionMode = .permanent, label: String = "test") -> DeletionRequest {
    DeletionRequest(url: url, mode: mode, base: sandbox.root, size: 4, label: label, identity: FileIdentity.capture(url))
}

@Suite("删除入口", .serialized)
struct DeletionServiceTests {
    @Test func previewNeverTouchesFilesAndMatchesExecution() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let removable = try sandbox.file("Library/Caches/a")
        let outOfScope = try sandbox.file("Library/Caches/keep")
        let busy = try sandbox.file("Library/Caches/com.example.busy")

        let service = service(sandbox, running: .known(["com.example.busy"]), scope: { url in
            if url.lastPathComponent == "keep" { throw SafetyError.protectedName("keep") }
        })
        var busyRequest = request(busy, in: sandbox)
        busyRequest.checksOwnerApp = true
        let requests = [request(removable, in: sandbox), request(outOfScope, in: sandbox), busyRequest]

        let preview = service.plan(requests)
        #expect(sandbox.exists(removable) && sandbox.exists(outOfScope) && sandbox.exists(busy))  // 预览不动文件

        let executed = await service.execute(requests)
        // 预览与执行对同一批请求给出同样的结论
        #expect(preview.map { $0.outcome == .wouldRemove } == executed.map(\.outcome.isRemoved))
        #expect(executed.map(\.request.url) == preview.map(\.request.url))
        #expect(!sandbox.exists(removable))
        #expect(sandbox.exists(outOfScope) && sandbox.exists(busy))
        #expect(executed[1].outcome == .blocked(.scope(String(describing: SafetyError.protectedName("keep")))))
        #expect(executed[2].outcome == .blocked(.appRunning("com.example.busy")))
    }

    @Test func refusesWhenTheRunningStateIsUnknown() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let file = try sandbox.file("Library/Caches/a")
        var item = request(file, in: sandbox)
        item.guardApps = [GuardApp(bundleID: "com.example.app", name: "Example")]

        let unknown = await service(sandbox, running: .unknown).execute([item])
        #expect(unknown.first?.outcome == .blocked(.activityUnknown))
        #expect(sandbox.exists(file))

        let running = await service(sandbox, running: .known(["com.example.app"])).execute([item])
        #expect(running.first?.outcome == .blocked(.appRunning("Example")))
        #expect(sandbox.exists(file))

        let idle = await service(sandbox, running: .known([])).execute([item])
        #expect(idle.first?.outcome.isRemoved == true)
        #expect(!sandbox.exists(file))
    }

    @Test func refusesWhenThePathWasReplacedAfterScanning() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let url = try sandbox.file("Library/Caches/a")
        var item = request(url, in: sandbox)
        item.identity = FileIdentity.capture(url)

        // 预览之后，原文件被删掉，同一路径换成了一个目录
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("precious".utf8).write(to: url.appendingPathComponent("important"))

        let result = await service(sandbox).execute([item])
        #expect(result.first?.outcome == .blocked(.identityChanged))
        #expect(sandbox.exists(url.appendingPathComponent("important")))
    }

    // MARK: 身份比对的细节

    @Test func aRegularFileRewrittenAtomicallyIsStillTheSameFile() async throws {
        // 偏好设置、defaults write、先写临时文件再改名：保存一次 inode 就换一次，不能因此拒绝
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let file = try sandbox.file("Library/Preferences/com.example.app.plist")
        let item = request(file, in: sandbox)
        let before = file.path.withCString { path -> UInt64 in var info = stat(); lstat(path, &info); return UInt64(info.st_ino) }

        let temporary = file.appendingPathExtension("tmp")
        try Data("rewritten".utf8).write(to: temporary)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: temporary, to: file)
        let after = file.path.withCString { path -> UInt64 in var info = stat(); lstat(path, &info); return UInt64(info.st_ino) }
        #expect(before != after)  // 前提：inode 确实变了

        let results = await service(sandbox).execute([item])
        #expect(results.first?.outcome.isRemoved == true)
    }

    @Test func aDirectoryReplacedByAnotherDirectoryIsRefused() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let directory = sandbox.root.appendingPathComponent("Library/Caches/com.example.app")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let item = request(directory, in: sandbox)

        // 目录被换成另一个目录：inode 不同
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("precious".utf8).write(to: directory.appendingPathComponent("important"))

        let results = await service(sandbox).execute([item])
        #expect(results.first?.outcome == .blocked(.identityChanged))
        #expect(sandbox.exists(directory.appendingPathComponent("important")))
    }

    @Test func aRequestWithoutAScanTimeIdentityIsNeverExecuted() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let file = try sandbox.file("Library/Caches/a")
        let noIdentity = DeletionRequest(url: file, mode: .permanent, base: sandbox.root, label: "test")

        let results = await service(sandbox).execute([noIdentity])
        #expect(results.first?.outcome == .blocked(.identityChanged))
        #expect(sandbox.exists(file))
    }

    // MARK: 判断顺序与文案

    @Test func aMissingItemIsReportedAsMissingNotAsOutOfScope() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let gone = sandbox.root.appendingPathComponent("Library/Caches/gone")
        let strict = service(sandbox, scope: { _ in throw SafetyError.outsideAllowedRoots })

        let results = await strict.execute([DeletionRequest(url: gone, mode: .permanent, base: sandbox.root, label: "test")])
        #expect(results.first?.outcome == .blocked(.missing))
    }

    @Test func scopeErrorsAreShownWithTheirLocalizedText() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let file = try sandbox.file("Library/Caches/a")
        let strict = service(sandbox, scope: { _ in throw DeletionError.staleScan })

        let results = await strict.execute([request(file, in: sandbox)])
        guard case .blocked(.scope(let message)) = results.first?.outcome else {
            Issue.record("应当被范围校验拦下")
            return
        }
        #expect(message != "staleScan")  // 以前会原样显示枚举的 case 名
        #expect(message.contains("重新扫描"))
    }

    @Test func systemLocationsAreRefusedByThePolicyItself() throws {
        // 系统级残留只预览：即使调用方的范围校验放行，策略本身也不允许 /Library、/Users/Shared 等位置
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let service = service(sandbox)
        for (path, base) in [("/Library/Application Support/Foo", "/Library/Application Support"),
                             ("/Library/LaunchDaemons/com.example.plist", "/Library/LaunchDaemons"),
                             ("/Users/Shared/Foo", "/Users/Shared"),
                             ("/Library/PrivilegedHelperTools/com.example.helper", "/Library/PrivilegedHelperTools")] {
            let block = service.evaluate(DeletionRequest(url: URL(fileURLWithPath: path), mode: .permanent,
                                                          base: URL(fileURLWithPath: base), label: "test"))
            #expect(block == .policy(.outsideZones), "\(path)")
        }
    }

    @Test func entriesNamedAfterARunningAppAreRecognisedWithTeamAndGroupPrefixes() {
        let running: Set<String> = ["com.tencent.xinWeChat"]
        #expect(owningRunningApp(ofEntryNamed: "com.tencent.xinWeChat", running: running) == "com.tencent.xinWeChat")
        #expect(owningRunningApp(ofEntryNamed: "com.tencent.xinWeChat.helper", running: running) != nil)
        #expect(owningRunningApp(ofEntryNamed: "5A4RE8SF68.com.tencent.xinWeChat", running: running) != nil)  // 团队前缀
        #expect(owningRunningApp(ofEntryNamed: "group.com.tencent.xinWeChat", running: running) != nil)      // group. 前缀
        #expect(owningRunningApp(ofEntryNamed: "COM.TENCENT.XINWECHAT.cache", running: running) != nil)      // 大小写
        #expect(owningRunningApp(ofEntryNamed: "com.tencent.xinWeChatExtra", running: running) == nil)        // 不是点号边界
        #expect(owningRunningApp(ofEntryNamed: "Library", running: running) == nil)
    }

    @Test func skipsRecentlyModifiedAndMissingItems() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let fresh = try sandbox.file("Library/Caches/fresh", age: 5)
        let missing = sandbox.root.appendingPathComponent("Library/Caches/none")
        var freshRequest = request(fresh, in: sandbox)
        freshRequest.minimumAge = 120

        let results = await service(sandbox).execute([freshRequest, request(missing, in: sandbox)])
        #expect(results[0].outcome == .blocked(.recentlyModified))
        #expect(results[1].outcome == .blocked(.missing))
        #expect(sandbox.exists(fresh))
    }

    @Test func criticalPathsAreRefusedWhateverTheCallerScopeAllows() async throws {
        // 只判断，从不执行：调用方的范围故意放行一切
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let service = DeletionService(home: NSHomeDirectory(), scope: { _ in }, running: { .known([]) }, log: nil)
        let root = URL(fileURLWithPath: "/")
        for path in ["/", "/System/Library", "/Applications", NSHomeDirectory(), NSHomeDirectory() + "/Documents", "/usr/bin"] {
            let block = service.evaluate(DeletionRequest(url: URL(fileURLWithPath: path), mode: .permanent, base: root, label: "test"))
            guard case .policy(.critical) = block else {
                Issue.record("\(path) 应当被通用路径策略拒绝，实际是 \(String(describing: block))")
                continue
            }
        }
    }

    @Test func aFailedTrashIsNeverTurnedIntoAPermanentDelete() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let file = try sandbox.file("Library/Caches/a")
        let trasher = StubTrasher()
        trasher.failure = CocoaError(.fileWriteNoPermission)

        let results = await service(sandbox, trasher: trasher).execute([request(file, in: sandbox, mode: .trash)])
        guard case .failed = results.first?.outcome else {
            Issue.record("移到废纸篓失败应当报告失败，实际是 \(String(describing: results.first?.outcome))")
            return
        }
        #expect(sandbox.exists(file))  // 文件还在，没有被悄悄永久删除
    }

    @Test func trashedItemsAreRecordedWithTheirTrashLocation() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let file = try sandbox.file("Library/Caches/a")
        let trashDestination = sandbox.root.appendingPathComponent(".Trash")
        let trasher = StubTrasher(destination: trashDestination)
        let logURL = sandbox.root.appendingPathComponent("log/cleanup.log")

        let results = await service(sandbox, trasher: trasher, log: CleanLog(url: logURL))
            .execute([request(file, in: sandbox, mode: .trash, label: "uninstall:com.example:caches")])
        #expect(results.first?.outcome == .removed(trashedTo: trashDestination.appendingPathComponent("a")))
        #expect(trasher.trashedURLs == [file])

        let lines = try String(contentsOf: logURL, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 1)
        let entry = try #require(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        #expect(entry["action"] as? String == "trash")
        #expect(entry["rule"] as? String == "uninstall:com.example:caches")
        #expect(entry["trashedTo"] as? String == trashDestination.appendingPathComponent("a").path)
        #expect(entry["mode"] as? String == "trash")
    }

    @Test func fileNamesCannotForgeLogRecords() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let logURL = sandbox.root.appendingPathComponent("log/cleanup.log")
        // 文件名里带换行和一段看起来像日志记录的内容
        let nasty = try sandbox.file("Library/Caches/a\n{\"action\":\"delete\",\"path\":\"/etc/passwd\"}")

        _ = await service(sandbox, log: CleanLog(url: logURL)).execute([request(nasty, in: sandbox)])
        let lines = try String(contentsOf: logURL, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 1)  // 仍然只有一行，换行被转义
        let entry = try #require(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        #expect((entry["path"] as? String)?.hasSuffix("/etc/passwd\"}") == true)
    }

    @Test func cancellationStopsBeforeTouchingAnything() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let files = try (0..<3).map { try sandbox.file("Library/Caches/f\($0)") }
        let service = service(sandbox)
        let requests = files.map { request($0, in: sandbox) }

        // 先等到取消生效再开始执行，避免“任务已经跑了一项才被取消”的竞态
        let task = Task { () -> [DeletionResult] in
            while !Task.isCancelled { await Task.yield() }
            return await service.execute(requests)
        }
        task.cancel()
        let results = await task.value
        #expect(results.isEmpty)
        #expect(files.allSatisfy(sandbox.exists))
    }
}
