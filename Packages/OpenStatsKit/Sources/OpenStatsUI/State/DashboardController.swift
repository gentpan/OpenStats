import AppKit
import Foundation
import Localization
import Metrics
import Observation

/// 线程间传递最新 /metrics 内容的小盒子
final class DashboardPayloadBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = Data("{}".utf8)

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func update(_ data: Data) {
        lock.lock()
        stored = data
        lock.unlock()
    }
}

/// 监控大屏：把 MetricsStore 里的读数每 2 秒整理成一份 JSON，经 DashboardServer 发给局域网里的
/// 任意设备（平板、旧电脑、电视浏览器），配合全屏模式当监控墙用。数据不出局域网
@MainActor
@Observable
public final class DashboardController {
    /// 服务可用性；running 时附带端口
    public enum Availability: Equatable {
        case off
        case starting(port: Int)
        case running(port: Int)
        case failed(port: Int, reason: String)
    }

    public private(set) var availability: Availability = .off
    public static let sampleInterval: TimeInterval = 2
    static let historyPoints = 150   // 150 × 2s = 5 分钟走势

    private let settings: AppSettings
    private let store: MetricsStore
    @ObservationIgnored let payloadBox = DashboardPayloadBox()
    @ObservationIgnored private let server: DashboardServer
    @ObservationIgnored private var sampler: Task<Void, Never>?
    /// 走势样本：时间、CPU%、内存%、累计下载 / 上传字节（网页端按差值算速率）
    struct Sample {
        let time: TimeInterval
        let cpu: Double
        let memory: Double
        let totalDown: Double
        let totalUp: Double
    }
    private var samples: [Sample] = []
    private var totalDown: Double = 0
    private var totalUp: Double = 0

    init(settings: AppSettings, store: MetricsStore) {
        self.settings = settings
        self.store = store
        server = DashboardServer(html: DashboardPage.html) { [payloadBox] in payloadBox.value }
        if settings.dashboardEnabled {
            applySettings()
        }
    }

    // MARK: 生命周期

    /// 开关或端口变化后调用；幂等，当前配置已在跑则不动
    public func applySettings() {
        guard settings.dashboardEnabled else {
            stop()
            return
        }
        let port = settings.dashboardPort
        if case .running(let running) = availability, running == port { return }
        availability = .starting(port: port)
        server.start(port: UInt16(clamping: port))
        if sampler == nil {
            sampler = Task { [weak self] in
                while !Task.isCancelled {
                    let start = Date()
                    await self?.sampleOnce()
                    let elapsed = Date().timeIntervalSince(start)
                    if elapsed < Self.sampleInterval {
                        try? await Task.sleep(for: .seconds(Self.sampleInterval - elapsed))
                    }
                }
            }
        }
    }

    public func stop() {
        sampler?.cancel()
        sampler = nil
        server.stop()
        availability = .off
    }

    /// 展示用地址：优先主网络接口的 IPv4
    public var address: String? {
        guard case .running = availability else { return nil }
        let host = store.networkInterface?.ipv4 ?? "127.0.0.1"
        return "http://\(host):\(settings.dashboardPort)/"
    }

    // MARK: 采样

    func sampleOnce() {
        // 监听状态（端口被占用等）在采样循环里轮询，最多晚 2 秒反映到设置页
        if case .starting(let port) = availability, let state = server.currentState() {
            availability = state.ready
                ? .running(port: port)
                : .failed(port: port, reason: state.reason ?? tr("未知错误"))
        }

        let now = Date()
        let network = store.network
        // 网页端的走势按累计字节的差值算速率，这里把瞬时速率积分成累计值
        totalDown += (network?.downloadBytesPerSecond ?? 0) * Self.sampleInterval
        totalUp += (network?.uploadBytesPerSecond ?? 0) * Self.sampleInterval
        let sample = Sample(time: now.timeIntervalSince1970,
                            cpu: (store.cpu?.total ?? 0) * 100,
                            memory: (store.memory?.usedFraction ?? 0) * 100,
                            totalDown: totalDown,
                            totalUp: totalUp)
        samples.append(sample)
        if samples.count > Self.historyPoints { samples.removeFirst(samples.count - Self.historyPoints) }
        payloadBox.update(buildPayload(sample: sample))
    }

    /// 组装 /metrics；抽成可单测的纯读取
    func buildPayload(sample: Sample) -> Data {
        let cpu = store.cpu
        let memory = store.memory
        let disk = store.disk
        let gigabyte = 1_000_000_000.0
        let gibibyte = 1_073_741_824.0

        var system: [String: Any] = [
            "time": sample.time,
            "hostname": Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            "cpu": sample.cpu,
            "cpuPercpu": (cpu?.perCore ?? []).map { ($0 * 100).rounded(.toNearestOrAwayFromZero) },
            "load": (cpu?.loadAverage ?? [0, 0, 0]).map { ($0 * 100).rounded() / 100 },
            "memUsedGB": memory.map { Double($0.used) / gibibyte } ?? 0,
            "memTotalGB": memory.map { Double($0.total) / gibibyte } ?? 0,
            "memPercent": sample.memory,
            "swapPercent": ((memory.flatMap { $0.swapTotal > 0 ? Double($0.swapUsed) / Double($0.swapTotal) * 100 : 0 } ?? 0) * 10).rounded() / 10,
            "netDownBps": (store.network?.downloadBytesPerSecond ?? 0).rounded(),
            "netUpBps": (store.network?.uploadBytesPerSecond ?? 0).rounded(),
            "diskUsedGB": disk.map { (Double($0.used) / gigabyte * 10).rounded() / 10 } ?? 0,
            "diskTotalGB": disk.map { (Double($0.total) / gigabyte * 10).rounded() / 10 } ?? 0,
            "diskPercent": disk.map { ($0.usedFraction * 1000).rounded() / 10 } ?? 0,
            "uptimeSec": store.system.bootDate.map { Date().timeIntervalSince($0).rounded() } ?? 0,
        ]
        if let battery = store.battery {
            system["batteryPercent"] = (battery.level * 100).rounded()
        } else {
            system["batteryPercent"] = NSNull()
        }
        system["processes"] = topProcesses()

        let history: [String: Any] = [
            "cpu": samples.map(\.cpu),
            "mem": samples.map(\.memory),
            "netDown": samples.map(\.totalDown),
            "netUp": samples.map(\.totalUp),
            "time": samples.map(\.time),
        ]

        let payload: [String: Any] = [
            "system": system,
            "history": history,
            "sampleInterval": Self.sampleInterval,
            "serverTime": Date().timeIntervalSince1970,
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
    }

    /// CPU 前六名；CPU 口径与活动监视器一致（单核满载为 100%）
    private func topProcesses() -> [[String: Any]] {
        let total = Double(store.memory?.total ?? 0)
        return store.processes
            .sorted { $0.cpu > $1.cpu }
            .prefix(6)
            .map { process in
                [
                    "pid": process.pid,
                    "name": process.name,
                    "cpu": (process.cpu * 100).rounded() / 100,
                    "mem": total > 0 ? (Double(process.memory) / total * 100 * 10).rounded() / 10 : 0,
                ] as [String: Any]
            }
    }

}
