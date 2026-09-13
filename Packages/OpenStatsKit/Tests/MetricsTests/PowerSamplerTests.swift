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
