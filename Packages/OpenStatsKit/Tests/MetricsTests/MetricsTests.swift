import Foundation
import Testing
@testable import Metrics
@testable import SMC

@Suite("SMC 编解码")
struct SMCDecoderTests {
    @Test func keyRoundTrip() {
        #expect(SMCKey("F0Ac").description == "F0Ac")
        #expect(SMCKey("#KEY").code == 0x234B_4559)
    }

    @Test func decodesCommonTypes() {
        let float = withUnsafeBytes(of: Float32(1464.5)) { Array($0) }
        #expect(SMCDecoder.decode(type: "flt ", bytes: float) == 1464.5)
        #expect(SMCDecoder.decode(type: "ui8 ", bytes: [2]) == 2)
        #expect(SMCDecoder.decode(type: "ui16", bytes: [0x01, 0x02]) == 258)
        #expect(SMCDecoder.decode(type: "sp78", bytes: [0x2A, 0x80]) == 42.5)
        #expect(SMCDecoder.decode(type: "fpe2", bytes: [0x16, 0xE0]) == 1464)
        #expect(SMCDecoder.decode(type: "????", bytes: [1, 2]) == nil)
    }

    @Test func encodeMatchesDecode() throws {
        for type in ["flt ", "fpe2"] {
            let bytes = try #require(SMCDecoder.encode(type: type, value: 2400))
            #expect(SMCDecoder.decode(type: type, bytes: bytes) == 2400)
        }
    }

    @Test func SMCStructMatchesKernelLayout() {
        #expect(MemoryLayout<SMCParam>.stride == 80)
    }

    @Test func temperatureGrouping() {
        #expect(TemperatureCatalog.group(for: "Tp0C") == .cpu)
        #expect(TemperatureCatalog.group(for: "Te05") == .cpu)
        #expect(TemperatureCatalog.group(for: "Tg1U") == .gpu)
        #expect(TemperatureCatalog.group(for: "TB0T") == .battery)
        #expect(TemperatureCatalog.group(for: "Ts0P") == .palmRest)
        #expect(TemperatureCatalog.group(for: "TC0P") == .cpu)
        #expect(TemperatureCatalog.group(for: "F0Ac") == nil)
        #expect(TemperatureCatalog.group(for: "TaLP") == nil)
    }
}

@Suite("格式化")
struct FormatTests {
    @Test func bytes() {
        #expect(Format.bytes(UInt64(512)) == "512 B")
        #expect(Format.bytes(UInt64(68_719_476_736)) == "64.0 GB")
        #expect(Format.bytes(UInt64(1_000_000_000_000), base: .decimal) == "1.0 TB")
        #expect(Format.bytes(UInt64(412_000_000_000), base: .decimal) == "412 GB")
    }

    @Test func compactRate() {
        #expect(Format.compactRate(0) == "0B")
        #expect(Format.compactRate(692_486) == "676K")
        #expect(Format.compactRate(3.5 * 1024 * 1024) == "3.5M")
        #expect(Format.compactRate(42 * 1024 * 1024) == "42M")
    }

    @Test func menuBarRate() {
        #expect(Format.menuBarRate(0) == "0 B/s")
        #expect(Format.menuBarRate(512) == "512 B/s")
        #expect(Format.menuBarRate(12 * 1024) == "12 KB/s")
        #expect(Format.menuBarRate(154 * 1024) == "154 KB/s")
        #expect(Format.menuBarRate(1000 * 1024) == "1.0 MB/s")
        #expect(Format.menuBarRate(1.2 * 1024 * 1024) == "1.2 MB/s")
        #expect(Format.menuBarRate(12 * 1024 * 1024) == "12 MB/s")
        #expect(Format.menuBarRate(1.1 * 1024 * 1024 * 1024) == "1.1 GB/s")
    }

    @Test func percentAndDuration() {
        #expect(Format.percent(0.257) == "26%")
        #expect(Format.percent(1.4) == "100%")
        #expect(Format.duration(minutes: 45) == "45 分钟")
        #expect(Format.duration(minutes: 120) == "2 小时")
        #expect(Format.duration(minutes: 90) == "1 小时 30 分钟")
        #expect(Format.temperature(68.4) == "68°C")
        #expect(Format.temperature(100, fahrenheit: true) == "212°F")
    }

    @Test func historyDropsOldest() {
        var history = History<Int>(capacity: 3)
        (1...5).forEach { history.append($0) }
        #expect(history.elements == [3, 4, 5])
    }
}

@Suite("本机采样", .serialized)
struct LiveSamplerTests {
    @Test func cpuNeedsTwoSamples() async throws {
        var sampler = CPUSampler()
        #expect(sampler.sample() == nil)
        try await Task.sleep(for: .milliseconds(200))
        let sample = sampler.sample()
        let load = try #require(sample)
        #expect((0...1).contains(load.total))
        #expect(load.perCore.count == CPUSampler.topology().logicalCores)
    }

    @Test func topologyCoversAllCores() {
        let topology = CPUSampler.topology()
        let indices = topology.clusters.flatMap(\.coreIndices).sorted()
        #expect(indices == Array(0..<topology.logicalCores))
    }

    @Test func memoryIsWithinPhysicalLimits() throws {
        let memory = try #require(MemorySampler().sample())
        #expect(memory.total == ProcessInfo.processInfo.physicalMemory)
        #expect(memory.used <= memory.total)
    }

    @Test func networkRateIsNonNegative() async throws {
        var sampler = NetworkSampler()
        _ = sampler.sample()
        try await Task.sleep(for: .milliseconds(200))
        let sample = sampler.sample()
        let rate = try #require(sample)
        #expect(rate.downloadBytesPerSecond >= 0)
        #expect(rate.uploadBytesPerSecond >= 0)
    }

    @Test func processesIncludeCurrentProcess() {
        var sampler = ProcessSampler()
        let processes = sampler.sample(limit: .max)
        #expect(processes.contains { $0.pid == getpid() })
    }

    @Test func diskHasCapacity() throws {
        let disk = try #require(DiskSampler.sample())
        #expect(disk.total > 0)
        #expect(disk.available <= disk.total)
    }
}
