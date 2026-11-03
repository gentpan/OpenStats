import Foundation
import Testing
@testable import Cleaner
@testable import OpenStatsUI

@MainActor
@Suite("卸载页的诊断与系统级残留")
struct UninstallerDiagnosticsTests {
    private let app = InstalledApp(url: URL(fileURLWithPath: "/tmp/openstats-diag-fixture/Applications/Probe.app"), name: "Probe",
                                   bundleIdentifier: "com.example.probe", version: "1.0", teamIdentifier: nil)

    private func scan(_ items: [AppLeftover], copies: [URL] = [], rejections: [AppScanDiagnostics.Rejection] = []) -> AppUninstallScan {
        var result = AppUninstallScan(items: items, unreadableDirectories: [], otherInstalledCopies: copies,
                                      identity: AppUninstallIdentity(app: app), applicationURL: app.url)
        result.diagnostics.rejections = rejections
        return result
    }

    private func controller(showing scan: AppUninstallScan) async -> UninstallerController {
        let controller = UninstallerController(scanner: { _ in scan })
        controller.select(app)
        for _ in 0..<200 where controller.isScanning { try? await Task.sleep(for: .milliseconds(10)) }
        return controller
    }

    private var body: AppLeftover { AppLeftover(url: app.url, kind: .application, size: 100) }
    private var cache: AppLeftover {
        AppLeftover(url: URL(fileURLWithPath: "/tmp/openstats-diag-fixture/Library/Caches/com.example.probe"), kind: .caches, size: 10)
    }
    private var helper: AppLeftover {
        AppLeftover(url: URL(fileURLWithPath: "/Library/PrivilegedHelperTools/com.example.probe.helper"), kind: .helpers, size: 5,
                    requiresReview: true, location: .system)
    }

    @Test func systemLevelLeftoversAreNeverPreselectedOrSelectable() async {
        let controller = await controller(showing: scan([body, cache, helper]))
        #expect(controller.chosen == [body.id, cache.id])

        controller.toggle(helper)
        #expect(!controller.chosen.contains(helper.id))
        controller.toggle(cache)
        #expect(controller.chosen == [body.id])
    }

    @Test func uninstallNeverActsOnSystemLevelItemsEvenIfTheyAreForcedIntoTheSelection() async {
        let controller = await controller(showing: scan([body, cache, helper]))
        controller.chosen = [helper.id]  // 绕过界面，硬塞进选择

        controller.uninstall()
        // 系统级条目被过滤掉，没有可处理的项目；不会开始任何删除
        #expect(!controller.isRemoving)
        #expect(controller.outcome?.isError == true)
        #expect(controller.leftovers.contains { $0.id == helper.id })
    }

    @Test func offersDiagnosticsWhenOnlyTheApplicationWasFound() async {
        let controller = await controller(showing: scan([body]))
        #expect(controller.showsDiagnostics)
        let report = controller.diagnosticReport()
        #expect(report?.contains("com.example.probe") == true)
        #expect(report?.hasPrefix("OpenStats") == true)
    }

    @Test func offersDiagnosticsWhenCandidatesWereRejected() async {
        let rejected = AppScanDiagnostics.Rejection(path: "/tmp/openstats-diag-fixture/Library/Caches/com.example.probe", reason: "x 是符号链接")
        let controller = await controller(showing: scan([body, cache], rejections: [rejected]))
        #expect(controller.showsDiagnostics)
        #expect(controller.skippedCandidateCount == 1)
    }

    @Test func staysQuietWhenLeftoversWereFoundAndNothingWasSkipped() async {
        let controller = await controller(showing: scan([body, cache, helper]))
        #expect(!controller.showsDiagnostics)
    }

    @Test func doesNotNagWhenAnotherCopyExplainsTheMissingLeftovers() async {
        let copy = URL(fileURLWithPath: "/tmp/openstats-diag-fixture/Applications/Other/Probe.app")
        let controller = await controller(showing: scan([body], copies: [copy]))
        #expect(!controller.showsDiagnostics)  // 页面上已经有“检测到其他安装副本”的提示
    }
}
