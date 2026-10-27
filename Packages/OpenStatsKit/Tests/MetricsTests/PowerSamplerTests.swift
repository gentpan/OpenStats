import Foundation
import Testing
@testable import Metrics

@Suite struct PowerSamplerTests {
    private func table(_ values: [UInt32]) -> Data {
        var data = Data()
        for value in values {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt32(800).littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    @Test func parsesTablesInHertzAndMegahertz() {
        #expect(PowerSampler.parseFrequencyTable(table([600_000_000, 1_200_000_000, 3_200_000_000])) == [600, 1200, 3200])
        #expect(PowerSampler.parseFrequencyTable(table([1308, 2292, 4608])) == [1308, 2292, 4608])
        // 第一项为 0 的是 GPU 等模块的表
        #expect(PowerSampler.parseFrequencyTable(table([0, 338_000, 1_620_000])) == nil)
        #expect(PowerSampler.parseFrequencyTable(Data([1, 2, 3])) == nil)
    }

    @Test func parsesGPUTableAndAveragesActiveStates() {
        let gpu = PowerSampler.parseGPUFrequencyTable(table([0, 338_000_000, 1_620_000_000]))
        #expect(gpu == [0, 338, 1620])
        // CPU 的表（第一项不为 0）不是 GPU 表
        #expect(PowerSampler.parseGPUFrequencyTable(table([600_000_000, 3_200_000_000])) == nil)
        // OFF 不计入；P1、P2 各占一半时间，平均频率为两者之间
        let states: [(name: String, residency: Int64)] = [("OFF", 900), ("P1", 50), ("P2", 50)]
        #expect(PowerSampler.gpuFrequency(states, table: [0, 338, 1620]) == 979)
        #expect(PowerSampler.gpuFrequency([("OFF", 100)], table: [0, 338, 1620]) == 0)
    }

    @Test func recognizesComplexChannels() {
        #expect(PowerSampler.complexLetter("ECPU") == "E")
        #expect(PowerSampler.complexLetter("PCPU") == "P")
        #expect(PowerSampler.complexLetter("MCPU1") == "M")
        #expect(PowerSampler.complexLetter("PCPM") == nil)
        #expect(PowerSampler.complexLetter("MCPM0_IDLE") == nil)
    }

    @Test func weightsFrequencyByResidencyAndOrdersClusters() {
        let tables: [[Double]] = [[600, 1000, 2000], [1000, 2000, 3000, 4000]]
        let efficiency = PowerSampler.ComplexResidency(letter: "E", states: [("IDLE", 900), ("V0P2", 50), ("V1P1", 0), ("V2P0", 50)])
        let performance = PowerSampler.ComplexResidency(letter: "P", states: [("DOWN", 10), ("IDLE", 10), ("V0P3", 0), ("V1P2", 0), ("V2P1", 0), ("V3P0", 100)])
        let result = PowerSampler.clusterFrequencies([efficiency, performance], tables: tables, perfLevels: 2)
        #expect(result[0] == 4000)
        #expect(result[1] == 1300)
        // 核心组数与 perflevel 数对不上时不猜
        #expect(PowerSampler.clusterFrequencies([efficiency], tables: tables, perfLevels: 2).isEmpty)
    }

    @Test func convertsEnergyUnits() {
        #expect(PowerSampler.joulesPerUnit("nJ") == 1e-9)
        #expect(PowerSampler.joulesPerUnit("mJ") == 1e-3)
    }
}

@Suite struct DiskSamplerTests {
    @Test func parsesNVMeHealthLog() throws {
        var log = [UInt8](repeating: 0, count: 512)
        log[0] = 0
        log[1] = 0x3B; log[2] = 0x01          // 315 K ≈ 41.85 °C
        log[3] = 100; log[4] = 10; log[5] = 3
        log[48] = 0x10; log[49] = 0x27        // 写入 10000 个数据单位
        log[128] = 0xE8; log[129] = 0x03      // 通电 1000 小时
        log[144] = 5
        let health = try #require(DiskHealthReader.parse(log, model: "SSD"))
        #expect(health.percentageUsed == 3)
        #expect(health.remainingLife == 97)
        #expect(health.bytesWritten == 10_000 * 512 * 1000)
        #expect(health.powerOnHours == 1000)
        #expect(health.unsafeShutdowns == 5)
        #expect(abs((health.temperature ?? 0) - 41.85) < 0.01)
        #expect(DiskHealthReader.parse([1, 2, 3], model: "SSD") == nil)
    }

    @Test func activityNeedsTwoSamples() {
        var sampler = DiskActivitySampler()
        #expect(sampler.sample(now: Date()) == nil)
        let second = sampler.sample(now: Date().addingTimeInterval(1))
        #expect(second.map { $0.readRate >= 0 && $0.writeRate >= 0 } ?? true)
    }
}

@Suite struct SystemBatteryHealthTests {
    @Test func parsesMaximumCapacity() {
        let json = """
        {"SPPowerDataType":[
          {"_name":"spbattery_information",
           "sppower_battery_health_info":{"sppower_battery_cycle_count":38,"sppower_battery_health":"Good",
                                          "sppower_battery_health_maximum_capacity":"100%"}},
          {"_name":"sppower_information"}]}
        """
        #expect(SystemBatteryHealth.parse(Data(json.utf8)) == 1)
        #expect(SystemBatteryHealth.parse(Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"87 %"}}]}"#.utf8)) == 0.87)
    }

    @Test func missingReadingFallsBack() {
        // 没有最大容量这一项（如部分 Intel Mac）、读数无效或输出为空时交给估算值
        #expect(SystemBatteryHealth.parse(Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health":"Good"}}]}"#.utf8)) == nil)
        #expect(SystemBatteryHealth.parse(Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"0%"}}]}"#.utf8)) == nil)
        #expect(SystemBatteryHealth.parse(Data()) == nil)
    }
}

@Suite struct BatteryHealthPreferenceTests {
    @Test func healthPrefersSystemReading() {
        var status = BatteryStatus(level: 1, isCharging: false, isPluggedIn: true, isFullyCharged: true, minutesRemaining: nil)
        #expect(status.health == nil)
        status.estimatedHealth = 0.977
        #expect(status.health == 0.977)
        status.systemHealth = 1
        #expect(status.health == 1)
        #expect(status.estimatedHealth == 0.977)
    }
}
