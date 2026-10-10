import Dispatch
import Foundation
import Testing
@testable import Cleaner
@testable import OpenStatsUI

/// 控制旧扫描何时返回，验证同一应用重新选择或取消后不会恢复旧详情。
private final class ControlledUninstallScan: @unchecked Sendable {
    let firstStarted = DispatchSemaphore(value: 0)
    let releaseFirst = DispatchSemaphore(value: 0)
    let firstReturned = DispatchSemaphore(value: 0)
    private let first: AppUninstallScan
    private let next: AppUninstallScan
    private let lock = NSLock()
    private var calls = 0

    init(first: AppUninstallScan, next: AppUninstallScan) {
        self.first = first
        self.next = next
    }

    func scan(_ app: InstalledApp) -> AppUninstallScan {
        lock.lock()
        calls += 1
        let current = calls
        lock.unlock()
        if current == 1 {
            firstStarted.signal()
            _ = releaseFirst.wait(timeout: .now() + 3)
            firstReturned.signal()
            return first
        }
        return next
    }
}

@MainActor
@Suite struct UninstallerScanTests {
    private func app(at root: URL) -> InstalledApp {
        InstalledApp(url: root.appendingPathComponent("Applications/Probe Editor.app"), name: "Probe Editor",
                     bundleIdentifier: "com.example.scan-probe", version: nil, teamIdentifier: nil)
    }

    private func wait(_ semaphore: DispatchSemaphore) async -> Bool {
        await Task.detached { Self.waitSynchronously(semaphore) }.value
    }

    private nonisolated static func waitSynchronously(_ semaphore: DispatchSemaphore) -> Bool {
        semaphore.wait(timeout: .now() + 3) == .success
    }

    private func waitForScan(_ controller: UninstallerController) async -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while controller.isScanning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return !controller.isScanning
    }

    @Test func realScanPropagatesWarningsAndLeavesReviewCandidatesUnchecked() async throws {
        let root = URL(fileURLWithPath: "/tmp").appendingPathComponent("openstats-scan-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("Home")
        let selected = app(at: home)
        let contents = selected.url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let metadata = ["CFBundleIdentifier": selected.bundleIdentifier, "CFBundleDisplayName": selected.name]
        let info = try PropertyListSerialization.data(fromPropertyList: metadata, format: .binary, options: 0)
        try info.write(to: contents.appendingPathComponent("Info.plist"))
        let cache = home.appendingPathComponent("Library/Caches/\(selected.bundleIdentifier)")
        let namedData = home.appendingPathComponent("Library/Application Support/\(selected.name)")
        let outside = root.appendingPathComponent("Outside")
        for directory in [cache, namedData, outside] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let redirected = home.appendingPathComponent("Library/WebKit")
        try FileManager.default.createSymbolicLink(at: redirected, withDestinationURL: outside)

        let controller = UninstallerController(scanner: { AppUninstaller.scan(for: $0, home: home.path) })
        controller.select(selected)
        #expect(await waitForScan(controller))
        #expect(controller.selected == selected)
        #expect(controller.unreadableDirectories.contains(redirected))
        #expect(controller.otherInstalledCopies.isEmpty)
        let reviewItems = controller.leftovers.filter(\.requiresReview)
        #expect(!reviewItems.isEmpty)
        #expect(reviewItems.allSatisfy { !controller.chosen.contains($0.id) })
        #expect(controller.chosen.contains(cache.path))
    }

    @Test func reselectingTheSameAppDiscardsItsOlderScan() async {
        let root = URL(fileURLWithPath: "/tmp/openstats-old-scan-fixture")
        let selected = app(at: root)
        let body = AppLeftover(url: selected.url, kind: .application, size: 100)
        let stale = AppLeftover(url: root.appendingPathComponent("Library/Caches/old"), kind: .caches, size: 200)
        let fresh = AppLeftover(url: root.appendingPathComponent("Library/Group Containers/fresh"), kind: .containers, size: 300, requiresReview: true)
        let oldWarning = root.appendingPathComponent("Library/OldWarning")
        let newWarning = root.appendingPathComponent("Library/NewWarning")
        let copy = root.appendingPathComponent("Applications/Probe Copy.app")
        let identity = AppUninstallIdentity(app: selected)
        let scanner = ControlledUninstallScan(
            first: AppUninstallScan(items: [body, stale], unreadableDirectories: [oldWarning], otherInstalledCopies: [copy],
                                    identity: identity, applicationURL: selected.url),
            next: AppUninstallScan(items: [body, fresh], unreadableDirectories: [newWarning], otherInstalledCopies: [],
                                   identity: identity, applicationURL: selected.url))
        defer { scanner.releaseFirst.signal() }
        let controller = UninstallerController(scanner: { scanner.scan($0) })
        controller.select(selected)
        #expect(await wait(scanner.firstStarted))
        controller.select(selected)
        #expect(await waitForScan(controller))
        scanner.releaseFirst.signal()
        #expect(await wait(scanner.firstReturned))
        try? await Task.sleep(for: .milliseconds(30))

        #expect(controller.leftovers == [body, fresh])
        #expect(controller.chosen == [body.id])
        #expect(controller.unreadableDirectories == [newWarning])
        #expect(controller.otherInstalledCopies.isEmpty)
    }

    @Test func cancellingSelectionDiscardsThePendingScanAndWarnings() async {
        let root = URL(fileURLWithPath: "/tmp/openstats-cancelled-scan-fixture")
        let selected = app(at: root)
        let body = AppLeftover(url: selected.url, kind: .application, size: 100)
        let result = AppUninstallScan(items: [body], unreadableDirectories: [root.appendingPathComponent("Library/Warning")],
                                      otherInstalledCopies: [root.appendingPathComponent("Applications/Copy.app")],
                                      identity: AppUninstallIdentity(app: selected), applicationURL: selected.url)
        let scanner = ControlledUninstallScan(first: result, next: result)
        defer { scanner.releaseFirst.signal() }
        let controller = UninstallerController(scanner: { scanner.scan($0) })
        controller.select(selected)
        #expect(await wait(scanner.firstStarted))
        controller.select(nil)
        #expect(!controller.isScanning)
        scanner.releaseFirst.signal()
        #expect(await wait(scanner.firstReturned))
        try? await Task.sleep(for: .milliseconds(30))

        #expect(controller.selected == nil)
        #expect(controller.leftovers.isEmpty && controller.chosen.isEmpty)
        #expect(controller.unreadableDirectories.isEmpty && controller.otherInstalledCopies.isEmpty)
        #expect(!controller.isScanning)
    }
}
