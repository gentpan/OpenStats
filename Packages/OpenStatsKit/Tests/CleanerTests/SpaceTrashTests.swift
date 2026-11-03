import Foundation
import os
import Testing
@testable import Cleaner

/// 大文件“移到废纸篓”：身份在扫描时采集，移动前对不上就拒绝
@Suite("大文件移到废纸篓", .serialized)
struct SpaceTrashTests {
    private final class StubTrasher: Trasher, @unchecked Sendable {
        let trashed = OSAllocatedUnfairLock(initialState: [URL]())
        func trash(_ url: URL) async throws -> URL? {
            trashed.withLock { $0.append(url) }
            return URL(fileURLWithPath: "/tmp/stub-trash").appendingPathComponent(url.lastPathComponent)
        }
    }

    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("openstats-space-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    /// 与扫描结果一致：记下修改时间，并在“扫描结束”时采集身份
    private func scanned(_ relative: String, in home: URL, withIdentity: Bool = true) throws -> SpaceScanResult.File {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("big".utf8).write(to: url)
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return SpaceScanResult.File(url: url, bytes: 3, modified: modified, isPackage: false,
                                    identity: withIdentity ? FileIdentity.capture(url) : nil)
    }

    @Test func movesAFileThatIsUnchangedSinceScanning() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = try scanned("Downloads/big.bin", in: home)
        let trasher = StubTrasher()

        let destination = try await SpaceScanner.trash(file, home: home, trasher: trasher, log: nil)
        #expect(destination?.lastPathComponent == "big.bin")
        #expect(trasher.trashed.withLock { $0 } == [file.url])
    }

    @Test func refusesAFileWithoutAScanTimeIdentity() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        // 旧版在点击那一刻才采集身份，等于拿自己和自己比；没有扫描时的身份就不放行
        let file = try scanned("Downloads/big.bin", in: home, withIdentity: false)
        let trasher = StubTrasher()

        await #expect(throws: DeletionError.self) { try await SpaceScanner.trash(file, home: home, trasher: trasher, log: nil) }
        #expect(trasher.trashed.withLock { $0 }.isEmpty)
    }

    @Test func refusesAFileReplacedAfterScanning() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let package = home.appendingPathComponent("Movies/Project.fcpbundle")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let modified = try package.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let file = SpaceScanResult.File(url: package, bytes: 3, modified: modified, isPackage: true, identity: FileIdentity.capture(package))

        // 扫描之后，整个包被换成了另一个同名目录（mtime 也设成一样，只有身份能发现）
        try FileManager.default.removeItem(at: package)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: package.path) }
        let trasher = StubTrasher()

        await #expect(throws: DeletionError.self) { try await SpaceScanner.trash(file, home: home, trasher: trasher, log: nil) }
        #expect(trasher.trashed.withLock { $0 }.isEmpty)
    }

    @Test func refusesAFileModifiedAfterScanning() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = try scanned("Downloads/big.bin", in: home)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(3600)], ofItemAtPath: file.url.path)
        let trasher = StubTrasher()

        do {
            _ = try await SpaceScanner.trash(file, home: home, trasher: trasher, log: nil)
            Issue.record("文件在扫描之后被改过，应当拒绝")
        } catch let DeletionError.blocked(block) {
            #expect(block.description.contains("重新扫描"))  // 不是枚举的 case 名
        }
        #expect(trasher.trashed.withLock { $0 }.isEmpty)
    }

    @Test func refusesLocationsOutsideTheUsersFiles() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = try scanned("Library/Application Support/x/data.bin", in: home)
        let trasher = StubTrasher()

        await #expect(throws: DeletionError.self) { try await SpaceScanner.trash(file, home: home, trasher: trasher, log: nil) }
        #expect(trasher.trashed.withLock { $0 }.isEmpty)
    }
}
