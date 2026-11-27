import Foundation
import Network
import Testing
@testable import Metrics
@testable import OpenStatsUI

@MainActor
@Suite struct DashboardTests {
    private func defaults() -> UserDefaults {
        let name = "OpenStatsUITests.Dashboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: 页面

    @Test func lightThemeOverridesEveryColorOfTheDarkOne() throws {
        let page = String(decoding: DashboardPage.html, as: UTF8.self)
        func variables(after marker: String) throws -> [String: String] {
            let start = try #require(page.range(of: marker))
            let block = page[start.upperBound...].prefix { $0 != "}" }
            var result: [String: String] = [:]
            for item in block.split(separator: ";") {
                let pair = item.split(separator: ":", maxSplits: 1)
                if pair.count == 2, pair[0].hasPrefix("--") { result[String(pair[0])] = String(pair[1]) }
            }
            return result
        }
        let dark = try variables(after: ":root{")
        let light = try variables(after: ":root[data-theme=light]{")
        #expect(dark.count > 10)
        #expect(Set(light.keys) == Set(dark.keys))
        // 两套配色取自应用的 DS.Palette：深色与浅色的数据色分别是品牌蓝的两档
        #expect(dark["--data"] == "#3b82f6")
        #expect(light["--data"] == "#2563eb")
        // 带主题参数的网址仍然是同一个页面
        let html = Data("<html/>".utf8)
        #expect(DashboardServer.makeResponse(path: "/?theme=light", html: html, metrics: Data()).body == html)
    }

    // MARK: 设置

    @Test func dashboardDefaultsAreOffOn8790() {
        let settings = AppSettings(defaults: defaults())
        #expect(settings.dashboardEnabled == false)
        #expect(settings.dashboardPort == 8790)
    }

    @Test func invalidPortFallsBackTo8790() {
        let stored = defaults()
        stored.set(22, forKey: "dashboardPort")
        let settings = AppSettings(defaults: stored)
        #expect(settings.dashboardPort == 8790)
    }

    @Test func dashboardSettingsStayOnThisMac() throws {
        let settings = AppSettings(defaults: defaults())
        settings.dashboardEnabled = true
        settings.dashboardPort = 8888
        let json = String(decoding: try JSONEncoder().encode(settings.exportDocument()), as: UTF8.self)
        #expect(!json.contains("dashboard"))

        // 云端文档（包括别的版本写的）带了开关和端口，也不能替这台 Mac 打开或改动对外服务
        let other = AppSettings(defaults: defaults())
        let foreign = try JSONDecoder().decode(SettingsDocument.self, from: Data(#"{"dashboardEnabled":true,"dashboardPort":8791}"#.utf8))
        other.apply(foreign)
        #expect(other.dashboardEnabled == false)
        #expect(other.dashboardPort == 8790)
    }

    // MARK: HTTP 响应路由

    @Test func serverRoutesByPath() {
        let html = Data("<html/>".utf8)
        let metrics = Data("{}".utf8)
        #expect(DashboardServer.makeResponse(path: "/", html: html, metrics: metrics).body == html)
        #expect(DashboardServer.makeResponse(path: "/index.html", html: html, metrics: metrics).body == html)
        #expect(DashboardServer.makeResponse(path: "/metrics?x=1", html: html, metrics: metrics).body == metrics)
        #expect(String(decoding: DashboardServer.makeResponse(path: "/healthz", html: html, metrics: metrics).body, as: UTF8.self) == "ok")
        #expect(DashboardServer.makeResponse(path: "/nope", html: html, metrics: metrics).status == 404)
        // 响应头里带关闭连接与禁用缓存
        let head = String(decoding: DashboardServer.makeResponse(path: "/metrics", html: html, metrics: metrics).data.prefix(250), as: UTF8.self)
        #expect(head.contains("Connection: close"))
        #expect(head.contains("no-store"))
    }

    @Test func requestParsingReadsMethodPathAndHost() {
        let head = Data("GET /metrics?x=1 HTTP/1.1\r\nAccept: */*\r\nhost: 192.168.1.5:8790\r\nUser-Agent: t".utf8)
        #expect(DashboardServer.parseRequest(head) == HTTPRequest(method: "GET", path: "/metrics?x=1", host: "192.168.1.5:8790"))
        #expect(DashboardServer.parseRequest(Data("GET / HTTP/1.0".utf8)) == HTTPRequest(method: "GET", path: "/", host: nil))
        #expect(DashboardServer.parseRequest(Data("hello".utf8)) == nil)
        #expect(DashboardServer.parseRequest(Data("GET /".utf8)) == nil)
        #expect(DashboardServer.parseRequest(Data()) == nil)
    }

    @Test func onlyGetAndHeadAreServed() {
        let html = Data("<html/>".utf8)
        let metrics = Data("{}".utf8)
        func respond(_ method: String, host: String? = "127.0.0.1") -> HTTPResponse {
            DashboardServer.makeResponse(for: HTTPRequest(method: method, path: "/", host: host), html: html, metrics: metrics)
        }
        #expect(respond("GET").status == 200)
        #expect(respond("POST").status == 405)
        #expect(respond("DELETE").status == 405)
        #expect(String(decoding: respond("POST").data, as: UTF8.self).contains("Allow: GET, HEAD"))
        #expect(DashboardServer.makeResponse(for: nil, html: html, metrics: metrics).status == 400)

        // HEAD 照常报告长度但不带正文
        let head = respond("HEAD")
        #expect(head.status == 200)
        let text = String(decoding: head.data, as: UTF8.self)
        #expect(text.contains("Content-Length: \(html.count)"))
        #expect(text.hasSuffix("\r\n\r\n"))
    }

    // MARK: 访问范围

    @Test func hostHeaderMustBeAnAddressOrLocalName() {
        for host in ["127.0.0.1:8790", "192.168.1.5", "localhost:8790", "mac-mini:8790", "peters-mac.local", "Peters-Mac.local:8790",
                     "nas.lan", "[fe80::1]:8790", "[::1]", "8.8.8.8:8790", nil] {
            #expect(DashboardServer.isAcceptableHost(host), "\(host ?? "nil")")
        }
        // 重绑定攻击里 Host 仍是攻击者自己的域名
        for host in ["evil.example.com", "evil.example.com:8790", "1.2.3.4.evil.com", "192.168.1.5.evil.com:8790", "[nothex]", "[::1"] {
            #expect(!DashboardServer.isAcceptableHost(host), "\(host)")
        }
    }

    @Test func onlyLocalNetworkPeersAreAccepted() {
        func v6(_ tail: [UInt8], head: [UInt8] = []) -> [UInt8] {
            head + [UInt8](repeating: 0, count: 16 - head.count - tail.count) + tail
        }
        let local: [[UInt8]] = [
            [10, 1, 2, 3], [127, 0, 0, 1], [192, 168, 1, 2], [172, 16, 0, 1], [172, 31, 255, 255], [169, 254, 1, 1],
            v6([1]),                                  // ::1
            v6([1], head: [0xfe, 0x80]),              // fe80::1
            v6([1], head: [0xfd, 0x00]),              // fd00::1，唯一本地地址
            v6([0xff, 0xff, 192, 168, 1, 2]),         // ::ffff:192.168.1.2
        ]
        for bytes in local { #expect(DashboardServer.isLocalAddress(bytes), "\(bytes)") }

        let remote: [[UInt8]] = [
            [8, 8, 8, 8], [11, 0, 0, 1], [172, 15, 0, 1], [172, 32, 0, 1], [192, 169, 0, 1], [100, 64, 0, 1], [169, 253, 0, 1],
            v6([1], head: [0x20, 0x01, 0x0d, 0xb8]),  // 2001:db8::1
            v6([0xff, 0xff, 8, 8, 8, 8]),             // ::ffff:8.8.8.8
            v6([2]),                                  // ::2
            [], [1, 2, 3],
        ]
        for bytes in remote { #expect(!DashboardServer.isLocalAddress(bytes), "\(bytes)") }
    }

    // MARK: 真实连接（本机回环）

    @Test func serverAnswersOverARealSocket() async throws {
        let (server, port) = try await startedServer()
        defer { server.stop() }

        let health = await RawClient.request(port: port, "GET /healthz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        #expect(health.hasPrefix("HTTP/1.1 200 OK"))
        #expect(health.hasSuffix("\r\n\r\nok"))

        let metrics = await RawClient.request(port: port, "GET /metrics HTTP/1.1\r\nHost: localhost:\(port)\r\n\r\n")
        #expect(metrics.hasSuffix(#"{"ok":true}"#))

        let page = await RawClient.request(port: port, "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        #expect(page.hasSuffix("<html/>"))

        let rebound = await RawClient.request(port: port, "GET /metrics HTTP/1.1\r\nHost: evil.example.com\r\n\r\n")
        #expect(rebound.hasPrefix("HTTP/1.1 403"))
        #expect(!rebound.contains(#"{"ok":true}"#))

        let post = await RawClient.request(port: port, "POST /metrics HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n")
        #expect(post.hasPrefix("HTTP/1.1 405"))

        let head = await RawClient.request(port: port, "HEAD /metrics HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        #expect(head.hasPrefix("HTTP/1.1 200 OK"))
        #expect(head.hasSuffix("\r\n\r\n"))

        let garbage = await RawClient.request(port: port, "hello\r\n\r\n")
        #expect(garbage.hasPrefix("HTTP/1.1 400"))
    }

    @Test func idleConnectionsAreClosedAfterTheTimeout() async throws {
        let (server, port) = try await startedServer(requestTimeout: 0.3)
        defer { server.stop() }

        let start = ContinuousClock.now
        let answer = await RawClient.request(port: port, nil, timeout: 5)
        #expect(answer == "")   // 服务器自己断开，而不是读超时
        #expect(ContinuousClock.now - start < .seconds(3))
    }

    @Test func connectionCapRejectsTheExcessAndFreesSlots() async throws {
        let (server, port) = try await startedServer(maxConnections: 2)
        defer { server.stop() }

        let idle = [RawClient(port: port), RawClient(port: port)]
        for client in idle { #expect(await client.connect()) }
        try await Task.sleep(for: .milliseconds(300))

        let refused = await RawClient.request(port: port, "GET /healthz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        #expect(refused == "")

        for client in idle { client.close() }
        try await Task.sleep(for: .milliseconds(300))
        let served = await RawClient.request(port: port, "GET /healthz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        #expect(served.hasPrefix("HTTP/1.1 200 OK"))
    }

    @Test func portInUseIsReportedAsFailed() async throws {
        let (first, port) = try await startedServer()
        defer { first.stop() }

        let second = DashboardServer(html: Data(), metricsProvider: { Data() })
        second.start(port: port)
        defer { second.stop() }
        var state = second.currentState()
        for _ in 0..<100 where state == .starting {
            try await Task.sleep(for: .milliseconds(20))
            state = second.currentState()
        }
        guard case .failed(let reason)? = state else {
            Issue.record("端口被占用时应报告失败，实际是 \(String(describing: state))")
            return
        }
        #expect(!reason.isEmpty)
        // 占着端口的那个服务不受影响
        let health = await RawClient.request(port: port, "GET /healthz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        #expect(health.hasPrefix("HTTP/1.1 200 OK"))
    }

    @Test func stoppedServerReportsNoState() async throws {
        let (server, _) = try await startedServer()
        #expect(server.currentState() == .ready)
        server.stop()
        #expect(server.currentState() == nil)
        #expect(server.boundPort == nil)
    }

    // MARK: /metrics 内容

    @Test func payloadCarriesTheSnapshot() throws {
        let store = MetricsStore()
        var snapshot = MetricsSnapshot()
        snapshot.cpu = CPULoad(total: 0.5, user: 0.3, system: 0.2, perCore: [0.25, 0.75], loadAverage: [1, 2, 3])
        snapshot.memory = MemoryUsage(total: 16 << 30, app: 6 << 30, wired: 2 << 30, compressed: 2 << 30,
                                      cached: 1 << 30, swapUsed: 1 << 20, swapTotal: 1 << 30, pressure: .normal,
                                      uncompressed: 4 << 30, swapInBytes: 0, swapOutBytes: 0)
        snapshot.network = NetworkRate(downloadBytesPerSecond: 100, uploadBytesPerSecond: 50, totalDownloaded: 0, totalUploaded: 0)
        snapshot.disk = DiskUsage(volumeName: "Macintosh HD", total: 500_000_000_000, available: 250_000_000_000)
        var systemProcess = ProcessUsage(pid: 1, name: "kernel_task", executablePath: nil, appBundlePath: nil, cpu: 99, memory: 1 << 30)
        systemProcess.isOwned = false
        snapshot.processes = [
            ProcessUsage(pid: 42, name: "demo", executablePath: nil, appBundlePath: nil, cpu: 1.5, memory: 1 << 30),
            systemProcess,
        ]
        snapshot.battery = BatteryStatus(level: 0.55, isCharging: false, isPluggedIn: true, isFullyCharged: false,
                                         minutesRemaining: nil, cycleCount: nil, systemHealth: nil, estimatedHealth: nil, adapterWatts: nil,
                                         designCapacity: nil, fullChargeCapacity: nil, voltage: nil, amperage: nil)
        store.apply(snapshot)

        let settings = AppSettings(defaults: defaults())
        let controller = DashboardController(settings: settings, store: store)
        // 走真实采样路径：两拍后历史里应有两条，累计下载每拍 +200B（100B/s × 2s）
        controller.sampleOnce()
        controller.sampleOnce()
        let data = controller.payloadBox.value
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let system = try #require(payload["system"] as? [String: Any])
        #expect(system["cpu"] as? Double == 50)
        #expect(system["cpuPercpu"] as? [Double] == [25, 75])
        #expect(system["load"] as? [Double] == [1, 2, 3])
        #expect((system["memUsedGB"] as? Double ?? 0) > 9.9 && (system["memUsedGB"] as? Double ?? 0) < 10.1)
        #expect(system["memTotalGB"] as? Double == 16)
        #expect((system["diskPercent"] as? Double ?? 0) > 49 && (system["diskPercent"] as? Double ?? 0) < 51)
        #expect(system["batteryPercent"] as? Double == 55)
        // 只列当前用户的进程：主窗口在进程页时采样会混进系统进程，榜单不能因此变
        let processes = try #require(system["processes"] as? [[String: Any]])
        #expect(processes.map { $0["name"] as? String } == ["demo"])
        #expect(processes.first?["cpu"] as? Double == 1.5)

        // 与主窗口仪表盘同样的内容：健康分、内存压力、磁盘余量、电池状态、各卡片的文字
        #expect((system["health"] as? [String: Any])?["score"] as? Int == 100)
        #expect((system["memPressure"] as? [String: Any])?["tone"] as? String == "success")
        #expect(system["memText"] as? String == "\(Format.bytes(UInt64(10 << 30))) / \(Format.bytes(UInt64(16 << 30)))")
        #expect(system["diskCapacity"] as? String == Format.capacity(500_000_000_000, base: .decimal))
        #expect((system["battery"] as? [String: Any])?["level"] as? Double == 0.55)
        #expect(system["cpuUser"] as? String == Format.percent(0.3))
        #expect(processes.first?["memText"] as? String == Format.bytes(UInt64(1 << 30)))
        #expect(processes.first?["tone"] as? String == "neutral")
        // 这次采样没有 GPU、温度和风扇读数：对应的键不出现，页面显示占位
        #expect(system["gpu"] == nil)
        #expect(system["cpuTemp"] == nil)
        #expect(system["fan"] == nil)

        let history = try #require(payload["history"] as? [String: Any])
        #expect(history["gpu"] as? [Double] == [0, 0])
        #expect(history["cpu"] as? [Double] == [50, 50])
        #expect(history["netDown"] as? [Double] == [200, 400])
        #expect((history["time"] as? [Double])?.count == 2)
        #expect(payload["sampleInterval"] as? Double == 2)
        // 页面不再有第二个数据源
        #expect(payload["gost"] == nil)
    }

    @Test func payloadSurvivesAnEmptyStore() throws {
        let controller = DashboardController(settings: AppSettings(defaults: defaults()), store: MetricsStore())
        let data = controller.buildPayload(sample: .init(time: 1, cpu: 0, memory: 0, totalDown: 0, totalUp: 0))
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((payload["system"] as? [String: Any])?["cpu"] as? Double == 0)
    }

    @Test func controllerIsIdleUntilEnabled() {
        let controller = DashboardController(settings: AppSettings(defaults: defaults()), store: MetricsStore())
        #expect(controller.availability == .off)
        #expect(!controller.isServing)
        #expect(controller.address == nil)
        controller.applySettings()   // 开关是关的，什么都不该启动
        controller.stop()
        #expect(controller.availability == .off)
    }
}

// MARK: 测试辅助

private struct ServerNotReady: Error {}

/// 在系统挑的空闲端口上起一个服务并等它就绪
@MainActor
private func startedServer(maxConnections: Int = 32, requestTimeout: TimeInterval = 5) async throws -> (DashboardServer, UInt16) {
    let server = DashboardServer(html: Data("<html/>".utf8), maxConnections: maxConnections, requestTimeout: requestTimeout) {
        Data(#"{"ok":true}"#.utf8)
    }
    server.start(port: 0)
    for _ in 0..<150 {
        if server.currentState() == .ready, let port = server.boundPort { return (server, port) }
        try await Task.sleep(for: .milliseconds(20))
    }
    server.stop()
    throw ServerNotReady()
}

private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Value) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

/// 最小的 TCP 客户端：连本机端口，发原始文本，读到对端关闭为止
private final class RawClient: @unchecked Sendable {
    private let connection: NWConnection
    private let lock = NSLock()
    private var received = Data()

    init(port: UInt16) {
        connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    }

    func connect() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = ResumeOnce(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(true)
                case .failed, .cancelled: once.resume(false)
                default: break
                }
            }
            connection.start(queue: .global())
        }
    }

    func send(_ text: String) {
        connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in })
    }

    /// 读到对端关闭或出错；timeout 内没等到就返回 "<<timeout>>"，免得服务器没断开时测试一直挂着
    func readAll(timeout: TimeInterval) async -> String {
        await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            let once = ResumeOnce(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { once.resume("<<timeout>>") }
            readMore(once)
        }
    }

    private func readMore(_ once: ResumeOnce<String>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, isComplete, error in
            lock.lock()
            if let data { received.append(data) }
            let text = String(decoding: received, as: UTF8.self)
            lock.unlock()
            if isComplete || error != nil {
                once.resume(text)
            } else {
                readMore(once)
            }
        }
    }

    func close() {
        connection.cancel()
    }

    /// 连上、发一次请求（nil 表示只连不发）、读完整个响应
    static func request(port: UInt16, _ text: String?, timeout: TimeInterval = 5) async -> String {
        let client = RawClient(port: port)
        defer { client.close() }
        guard await client.connect() else { return "" }
        if let text { client.send(text) }
        return await client.readAll(timeout: timeout)
    }
}
