import Foundation
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

    @Test func settingsDocumentCarriesDashboardFields() {
        let settings = AppSettings(defaults: defaults())
        settings.dashboardEnabled = true
        settings.dashboardPort = 8888
        let doc = settings.exportDocument()
        #expect(doc.dashboardEnabled == true)
        #expect(doc.dashboardPort == 8888)

        let other = AppSettings(defaults: defaults())
        other.apply(doc)
        #expect(other.dashboardEnabled == true && other.dashboardPort == 8888)
        // 越界端口在套用时被忽略
        var invalid = SettingsDocument()
        invalid.dashboardPort = 22
        other.apply(invalid)
        #expect(other.dashboardPort == 8888)
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
        let head = String(decoding: DashboardServer.makeResponse(path: "/metrics", html: html, metrics: metrics).data.prefix(200), as: UTF8.self)
        #expect(head.contains("Connection: close"))
        #expect(head.contains("no-store"))
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
        snapshot.processes = [ProcessUsage(pid: 42, name: "demo", executablePath: nil, appBundlePath: nil, cpu: 1.5, memory: 1 << 30)]
        snapshot.battery = BatteryStatus(level: 0.55, isCharging: false, isPluggedIn: true, isFullyCharged: false,
                                         minutesRemaining: nil, cycleCount: nil, health: nil, adapterWatts: nil,
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
        let processes = try #require(system["processes"] as? [[String: Any]])
        #expect(processes.first?["name"] as? String == "demo")
        #expect(processes.first?["cpu"] as? Double == 1.5)

        let history = try #require(payload["history"] as? [String: Any])
        #expect(history["cpu"] as? [Double] == [50, 50])
        #expect(history["netDown"] as? [Double] == [200, 400])
        #expect((history["time"] as? [Double])?.count == 2)
        #expect(payload["sampleInterval"] as? Double == 2)
    }

    @Test func payloadSurvivesAnEmptyStore() throws {
        let controller = DashboardController(settings: AppSettings(defaults: defaults()), store: MetricsStore())
        let data = controller.buildPayload(sample: .init(time: 1, cpu: 0, memory: 0, totalDown: 0, totalUp: 0))
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((payload["system"] as? [String: Any])?["cpu"] as? Double == 0)
    }
}
