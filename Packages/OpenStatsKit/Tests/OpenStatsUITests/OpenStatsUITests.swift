import Foundation
import Metrics
import Testing
@testable import OpenStatsUI

private func isolatedDefaults() -> UserDefaults {
    let name = "OpenStatsUITests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
@Suite struct SettingsTests {
    @Test func defaultsAndInvalidValues() {
        let defaults = isolatedDefaults()
        defaults.set(7, forKey: "refreshSeconds")
        defaults.set("bogus", forKey: "panelTab")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.refreshSeconds == 2)
        #expect(settings.panelTab == .overview)
        #expect(settings.menuBarItems == [.cpu, .memory, .network])
        #expect(settings.probeEnabled && settings.probeInBackground && settings.autoCheckUpdates)
    }

    @Test func persistsChanges() {
        let defaults = isolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.menuBarItems = [.gpu, .fan]
        settings.probeInBackground = false
        settings.hiddenPopoverSections = [.cpuHeatmap]
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.menuBarItems == [.gpu, .fan])
        #expect(!reloaded.probeInBackground)
        #expect(reloaded.hiddenPopoverSections == [.cpuHeatmap])
        #expect(reloaded.orderedMenuBarItems == [.gpu, .fan])
    }
}

@Suite struct PanelTabTests {
    @Test func sidebarGroupsCoverEveryTabOnce() {
        let grouped = PanelTab.monitors + PanelTab.tools + PanelTab.settings
        #expect(grouped.count == PanelTab.allCases.count)
        #expect(Set(grouped) == Set(PanelTab.allCases))
        #expect(PanelTab.settings.allSatisfy { $0.isSettings })
        #expect(PanelTab.settingsAbout.headerTitle == "设置 · 关于")
    }

    @Test func menuBarItemsMapToPages() {
        for item in MenuBarItem.allCases {
            let tab = PanelTab(item: item)
            #expect(tab.menuBarItem == item || (item == .fan && tab == .thermal))
        }
    }
}

@MainActor
@Suite struct DemandTests {
    private func model() -> AppModel {
        AppModel(settings: AppSettings(defaults: isolatedDefaults()), historyURL: nil)
    }

    @Test func menuBarOnlySamplesAtUserInterval() {
        let model = model()
        model.settings.refreshSeconds = 5
        #expect(model.demand.interval == .seconds(5))
        #expect(!model.demand.systemProcesses)
        #expect(!model.demand.disk)
    }

    @Test func processesPageRefreshesEveryTwoSeconds() {
        let model = model()
        model.isMainWindowVisible = true
        model.settings.panelTab = .processes
        #expect(model.demand.interval == .seconds(2))
        #expect(model.demand.processes && model.demand.systemProcesses)

        model.openPopover = .cpu
        #expect(model.demand.interval == .seconds(1))

        model.openPopover = nil
        model.settings.panelTab = .overview
        #expect(model.demand.interval == .seconds(1))
        #expect(!model.demand.systemProcesses)
    }

    @Test func networkDetailVisibility() {
        let model = model()
        #expect(!model.isNetworkDetailVisible)
        model.openPopover = .network
        #expect(model.isNetworkDetailVisible)
        model.openPopover = nil
        model.isMainWindowVisible = true
        model.settings.panelTab = .network
        #expect(model.isNetworkDetailVisible)
    }
}

@MainActor
@Suite struct UpdateControllerTests {
    @Test func automaticCheckRespectsSettingAndInterval() {
        let defaults = isolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.autoCheckUpdates = false
        let controller = UpdateController(settings: settings, defaults: defaults)
        controller.checkIfNeeded()
        #expect(controller.phase == .idle)

        settings.autoCheckUpdates = true
        defaults.set(Date(), forKey: "updateLastChecked")
        let recent = UpdateController(settings: settings, defaults: defaults)
        recent.checkIfNeeded()
        #expect(recent.phase == .idle)
    }

    @Test func developmentBuildCannotInstall() {
        // 测试进程不是签名的 OpenStats.app
        let controller = UpdateController(settings: AppSettings(defaults: isolatedDefaults()))
        #expect(controller.installBlockedReason != nil)
    }
}

@Suite struct DiagnosticsTests {
    @Test func redactsAddressesAndHome() {
        let text = "\(NSHomeDirectory())/Library/x 192.168.1.20 fe80::1c2b:3aff:fe4d:5e6f 2001:db8:0:0:1:2:3:4 ::1 a4:83:e7:12:34:56 12:30:45 版本 0.2.0"
        let redacted = DiagnosticsExporter.redact(text)
        #expect(redacted.hasPrefix("~/Library/x"))
        #expect(!redacted.contains("192.168.1.20"))
        #expect(!redacted.contains("a4:83:e7"))
        #expect(!redacted.contains("fe80::1c2b"))
        #expect(!redacted.contains("2001:db8"))
        #expect(!redacted.contains("::1"))
        #expect(redacted.contains("<MAC>"))
        #expect(redacted.contains("12:30:45"))
        #expect(redacted.contains("0.2.0"))
    }
}

@MainActor
@Suite struct ProcessRowTests {
    private func process(_ pid: Int32, _ name: String, bundle: String?, cpu: Double, memory: UInt64, owned: Bool = true) -> ProcessUsage {
        var usage = ProcessUsage(pid: pid, name: name, executablePath: nil, appBundlePath: bundle, cpu: cpu, memory: memory)
        usage.isOwned = owned
        usage.threads = 4
        return usage
    }

    @Test func groupsHelpersIntoTheirApp() {
        let rows = ProcessRowModel.grouped([
            process(10, "Safari", bundle: "/Applications/Safari.app", cpu: 10, memory: 100),
            process(11, "Safari Web Content", bundle: "/Applications/Safari.app", cpu: 5, memory: 300),
            process(12, "cloudd", bundle: nil, cpu: 1, memory: 50),
        ])
        #expect(rows.count == 2)
        let safari = rows.first { $0.count == 2 }
        #expect(safari?.cpu == 15)
        #expect(safari?.memory == 400)
        #expect(safari?.threads == 8)
        #expect(safari?.pid == nil)
    }

    @Test func blocksQuittingProtectedProcesses() {
        #expect(ProcessRowModel(process: process(1, "launchd", bundle: nil, cpu: 0, memory: 1, owned: false)).quitBlockedReason != nil)
        #expect(ProcessRowModel(process: process(getpid(), "OpenStats", bundle: nil, cpu: 0, memory: 1)).quitBlockedReason != nil)
        #expect(ProcessRowModel(process: process(99, "loginwindow", bundle: nil, cpu: 0, memory: 1)).quitBlockedReason != nil)
        #expect(ProcessRowModel(process: process(98, "Notes", bundle: nil, cpu: 0, memory: 1)).quitBlockedReason == nil)
    }

    @Test func narrowTablesDropColumns() {
        #expect(ProcessColumn.visible(forWidth: 2000) == ProcessColumn.allCases)
        #expect(ProcessColumn.visible(forWidth: 300) == [.name, .cpu, .memory, .user])
    }
}

@Suite struct DiagnosticsArchiveTests {
    @Test func writesZipWithSummaryAndLog() throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: destination) }
        try DiagnosticsExporter.writeArchive(summary: "# 测试\n", to: destination)
        let listing = Process()
        listing.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        listing.arguments = ["-1", destination.path]
        let pipe = Pipe()
        listing.standardOutput = pipe
        try listing.run()
        let names = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        listing.waitUntilExit()
        #expect(names.contains("summary.txt"))
        #expect(names.contains("openstats.log"))
    }
}

@Suite struct AlertTrackerTests {
    @Test func firesOnceAfterSustainAndRespectsCooldown() {
        var tracker = AlertTracker()
        func step(_ active: Bool, _ seconds: TimeInterval) -> Bool {
            tracker.update(isActive: active, now: Date(timeIntervalSince1970: seconds), sustain: 60, cooldown: 1800)
        }
        #expect(!step(true, 0))
        #expect(!step(true, 59))
        #expect(step(true, 60))
        // 同一段持续期内不重复
        #expect(!step(true, 600))
        // 恢复后再次出现，但还在冷却期
        #expect(!step(false, 700))
        #expect(!step(true, 800))
        #expect(!step(true, 900))
        // 冷却结束后同一段持续期仍可触发
        #expect(step(true, 1900))
    }

    @Test func briefSpikesDoNotFire() {
        var tracker = AlertTracker()
        var fired = false
        for second in stride(from: 0.0, to: 600, by: 30) {
            // 每 30 秒一升一降，从未持续满 60 秒
            fired = fired || tracker.update(isActive: Int(second) % 60 == 0, now: Date(timeIntervalSince1970: second),
                                            sustain: 60, cooldown: 1800)
        }
        #expect(!fired)
    }

    @Test func notificationTabsExist() {
        #expect(PanelTab.settings.contains(.settingsNotifications))
        #expect(Set(AlertKind.allCases.map(\.tab)).isSubset(of: Set(PanelTab.allCases)))
    }
}

@Suite struct HotKeyTests {
    @Test func displaysAndValidates() {
        let hotKey = HotKey(keyCode: 1, modifiers: [.command, .option, .capsLock], key: "s")
        #expect(hotKey.display == "⌥⌘S")
        #expect(hotKey.isValid)
        #expect(!HotKey(keyCode: 1, modifiers: [.shift], key: "s").isValid)
        #expect(HotKey(keyCode: 49, modifiers: [.control], key: " ").display == "⌃空格")
    }

    @MainActor
    @Test func persistsBindings() {
        let defaults = isolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.hotKeys[.toggleKeepAwake] = HotKey(keyCode: 40, modifiers: [.command, .shift], key: "k")
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.hotKeys[.toggleKeepAwake]?.display == "⇧⌘K")
    }
}

@Suite struct FunctionKeyTests {
    @Test func namesFunctionKeys() {
        #expect(HotKey(keyCode: 0x7A, modifiers: [.command], key: "\u{F704}").display == "⌘F1")
    }
}
