import Foundation
@testable import Metrics
import Testing
@testable import OpenStatsUI

/// 各页面之间同一件事的口径、跳转与说明要一致
@Suite struct PageConsistencyTests {
    @Test func processCPUFollowsTheSharedBasis() {
        // 单核口径：单核满载就是 100%，多线程可以超过 100%
        #expect(ProcessColumn.cpuText(1, perCore: true) == "100.0%")
        #expect(ProcessColumn.cpuText(2.5, perCore: true) == "250.0%")
        // 整机口径：全部核心跑满才是 100%，与仪表盘、CPU 页同一把尺子
        #expect(ProcessColumn.cpuText(Double(Format.logicalCores), perCore: false) == "100.0%")
        #expect(ProcessColumn.cpuText(1, perCore: false) == Format.machineShare(1))
        // 几乎空闲时两种口径都写 0%
        #expect(ProcessColumn.cpuText(0, perCore: true) == "0%")
        #expect(ProcessColumn.cpuText(0.0001, perCore: false) == "0%")
        // 同一个进程，两种口径相差核数倍
        #expect(ProcessColumn.cpu.help(cpuPerCore: true) != ProcessColumn.cpu.help(cpuPerCore: false))
    }

    @Test func batteryNotificationsOpenTheBatteryPage() {
        // 本机信息页不含电池与蓝牙设备，点通知应该落在电池页
        #expect(AlertKind.batteryHealth.tab == .battery)
        #expect(AlertKind.bluetoothBattery.tab == .battery)
        #expect(Set(AlertKind.allCases.map(\.tab)).isSubset(of: Set(PanelTab.allCases)))
    }

    @Test func syncedFieldsAreAllDescribed() {
        // 账号页“同步的内容”的说明由 describedFields 对应；文档里新增字段却没登记，说明文案就会漂移
        let fields = Set(Mirror(reflecting: SettingsDocument()).children.compactMap(\.label))
        #expect(fields.subtracting(["schema"]) == SettingsDocument.describedFields)
    }
}
