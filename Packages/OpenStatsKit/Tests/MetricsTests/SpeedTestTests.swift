import Foundation
import Testing
@testable import Metrics

@Suite("网络测速")
struct SpeedTestTests {
    @Test func 国内节点覆盖三十一个省的三网() {
        #expect(ChinaNode.provinces.count == 31)
        #expect(ChinaNode.all.count == 93)
        let bjTelecom = ChinaNode.all.first { $0.code == "bj" && $0.carrier == .telecom }
        #expect(bjTelecom?.host == "bj-ct-v4.ip.zstaticcdn.com")
        #expect(bjTelecom?.port == 80)
        // 每个省三家运营商各一个，编号不重复
        #expect(Set(ChinaNode.all.map(\.id)).count == ChinaNode.all.count)
    }

    @Test func 全球节点各大区都有且地址唯一() {
        #expect(GlobalNode.all.count == 24)
        #expect(Set(GlobalNode.all.map(\.id)).count == GlobalNode.all.count)
        #expect(Set(GlobalNode.all.map(\.downloadURL)).count == GlobalNode.all.count)
        for region in GlobalRegion.allCases {
            #expect(GlobalNode.all.contains { $0.region == region })
        }
        // 测速文件都走 HTTPS，主机名与端口取自地址
        #expect(GlobalNode.all.allSatisfy { $0.downloadURL.scheme == "https" && !$0.host.isEmpty && $0.port == 443 })
    }

    @Test func 探针按大洲分配且总数正好() {
        for probes in [10, 20, 30] {
            let locations = GlobalpingClient.distribution(probes)
            #expect(locations.reduce(0) { $0 + $1.limit } == probes)
            #expect(locations.allSatisfy { $0.limit > 0 })
            // 亚洲、欧洲、北美一定有份
            #expect(Set(locations.map(\.continent)).isSuperset(of: ["AS", "EU", "NA"]))
        }
    }

    @Test func 用量上限按档位换算() {
        #expect(SpeedTestBudget.full.limit.seconds == 10)
        #expect(SpeedTestBudget.full.limit.bytes == 200 * 1024 * 1024)
        #expect(SpeedTestBudget.light.limit.bytes < SpeedTestBudget.medium.limit.bytes)
    }

    @Test func 带宽按一千进位() {
        #expect(Format.bandwidth(820_000) == "820 kbps")
        #expect(Format.bandwidth(95_300_000) == "95.3 Mbps")
        #expect(Format.bandwidth(1_210_000_000) == "1.21 Gbps")
        #expect(Format.bandwidth(0) == "0 bps")
    }

    @Test func 扣掉Cloudflare报的服务器处理时间() {
        let headers = ["server-timing": "cfSpeedEdge;dur=3, cfSpeedWorker;dur=21, cfL4;desc=\"?proto=TCP&rtt=65767\""]
        #expect(BroadbandTest.serverMilliseconds(headers) == 24)
        #expect(BroadbandTest.serverMilliseconds([:]) == 0)
    }

    @Test func 物理网卡的DNS被代理接管时要自己解析() {
        #expect(SpeedPath.isHijackedDNS("198.18.0.2"))
        #expect(SpeedPath.isHijackedDNS("127.0.0.1"))
        #expect(SpeedPath.isHijackedDNS("::1"))
        #expect(!SpeedPath.isHijackedDNS("192.168.0.1"))
        #expect(!SpeedPath.isHijackedDNS("223.5.5.5"))
    }

    @Test func 没有代理时两条线路一样() async {
        let details = NetworkDetails(physical: nil, tunnel: nil, dnsServers: [])
        for route in SpeedRoute.allCases {
            let path = await SpeedPath.make(route: route, details: details, environment: ProxyEnvironment())
            #expect(path.route == nil)
            #expect(!path.isProxied)
        }
        // 经代理：延迟改用 HTTP 往返计时
        let proxied = await SpeedPath.make(route: .proxy, details: details,
                                           environment: ProxyEnvironment(proxies: [.init(kind: .http, host: "127.0.0.1", port: 6152)]))
        #expect(proxied.isProxied)
        #expect(proxied.route == .proxy)
    }
}

