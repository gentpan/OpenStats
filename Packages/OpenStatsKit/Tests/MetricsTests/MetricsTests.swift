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

@Suite struct NetworkParsingTests {
    @Test func parsesNettopOutput() {
        let output = """
        ,bytes_in,bytes_out,
        launchd.1,0,0,
        Google Chrome H.4521,120127,95191,
        broken line
        """
        let parsed = NetworkProcessSampler.parse(output)
        #expect(parsed.count == 2)
        #expect(parsed[4521]?.name == "Google Chrome H")
        #expect(parsed[4521]?.download == 120_127)
        #expect(parsed[4521]?.upload == 95_191)
    }

    @Test func parsesCloudflareTrace() {
        let fields = PublicAddressLookup.parseTrace("fl=123\nip=203.0.113.24\nloc=CN\n")
        #expect(fields["ip"] == "203.0.113.24")
        #expect(fields["loc"] == "CN")
        #expect(PublicAddressLookup.parseTrace("ip=<html>")["ip"] == nil)
    }

    @Test func matchesEchoReplyBySequenceAndToken() {
        // 20 字节 IPv4 头 + ICMP 回显应答（标识符被内核改写为 0x8e84）
        var reply = [UInt8](repeating: 0, count: 20)
        reply[0] = 0x45
        reply += [0, 0, 0, 0, 0x8E, 0x84, 0x00, 0x07, 0xDE, 0xAD, 0xBE, 0xEF]
        #expect(ConnectivityProbe.matches(reply, count: reply.count, family: AF_INET, sequence: 7, token: 0xDEADBEEF))
        #expect(!ConnectivityProbe.matches(reply, count: reply.count, family: AF_INET, sequence: 8, token: 0xDEADBEEF))
        #expect(!ConnectivityProbe.matches(reply, count: reply.count, family: AF_INET, sequence: 7, token: 1))
    }

    @Test func computesInternetChecksum() {
        let packet: [UInt8] = [8, 0, 0, 0, 0x12, 0x34, 0, 1]
        let sum = ConnectivityProbe.checksum(packet)
        var filled = packet
        filled[2] = UInt8(sum >> 8)
        filled[3] = UInt8(sum & 0xFF)
        #expect(ConnectivityProbe.checksum(filled) == 0)
    }
}

@Suite struct GeoParsingTests {
    @Test func parsesIpinfoResponse() throws {
        let json = #"{"ip":"82.139.234.155","city":"Frankfurt am Main","country":"DE","org":"AS151338 POLONETWORK LIMITED"}"#
        let result = try #require(PublicAddressLookup.parseGeo(Data(json.utf8)))
        #expect(result.ipv4 == "82.139.234.155")
        #expect(result.ipv6 == nil)
        #expect(result.countryCode == "DE")
        #expect(result.city == "Frankfurt am Main")
        #expect(result.asn == "AS151338")
        #expect(result.organization == "POLONETWORK LIMITED")
    }

    @Test func rejectsUnsafeCountryCode() {
        #expect(PublicAddressLookup.validCountryCode("cn") == "CN")
        #expect(PublicAddressLookup.validCountryCode("../x") == nil)
        #expect(PublicAddressLookup.validCountryCode("USA") == nil)
        let json = #"{"ip":"2606:4700:4700::1111","country":"../../etc","org":"Cloudflare"}"#
        let result = PublicAddressLookup.parseGeo(Data(json.utf8))
        #expect(result?.ipv6 == "2606:4700:4700::1111")
        #expect(result?.countryCode == nil)
        #expect(result?.asn == nil)
        #expect(result?.organization == "Cloudflare")
    }
}
