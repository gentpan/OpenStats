import AppKit
import Foundation
import Localization
import Metrics
import Observation
import SMC

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
/// 任意设备（平板、旧电脑、电视浏览器），配合全屏模式当监控墙用。只接受本机和局域网的访问
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
        /// GPU 占用（%）与最快那台风扇的转速占比（%）；没有读数时为 0
        var gpu: Double = 0
        var fan: Double = 0
        let totalDown: Double
        let totalUp: Double
    }
    private var samples: [Sample] = []
    private var totalDown: Double = 0
    private var totalUp: Double = 0
    /// 主机名要查系统，可能卡在域名解析上，所以只在后台查一次，查到之前先用占位
    @ObservationIgnored private var hostname = "Mac"
    @ObservationIgnored private var isResolvingHostname = false

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
        switch availability {
        case .starting(let current), .running(let current):
            if current == port { return }
        case .off, .failed:
            break
        }
        availability = .starting(port: port)
        server.start(port: UInt16(clamping: port))
        resolveHostname()
        if sampler == nil {
            sampler = Task { [weak self] in
                while !Task.isCancelled {
                    let start = Date()
                    self?.sampleOnce()
                    let elapsed = Date().timeIntervalSince(start)
                    if elapsed < Self.sampleInterval {
                        try? await Task.sleep(for: .seconds(Self.sampleInterval - elapsed))
                    }
                }
            }
        }
        // 监听通常几十毫秒内就绪，不必等下一拍采样才在设置页反映出来
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.refreshAvailability()
        }
    }

    public func stop() {
        guard availability != .off || sampler != nil else { return }
        sampler?.cancel()
        sampler = nil
        server.stop()
        availability = .off
        samples.removeAll()
        totalDown = 0
        totalUp = 0
        payloadBox.update(Data("{}".utf8))
    }

    /// 服务在跑或正在启动；监听失败后大屏不再让磁盘、电量和进程一直采集
    public var isServing: Bool {
        switch availability {
        case .starting, .running: true
        case .off, .failed: false
        }
    }

    /// 展示用地址：主网络接口的 IPv4；没有网络时不给地址
    public var address: String? {
        guard case .running = availability, let host = store.networkInterface?.ipv4 else { return nil }
        return "http://\(host):\(settings.dashboardPort)/"
    }

    /// 设置被设置页以外的途径改了而没人通知控制器时，在采样循环里补上
    private func reconcile() {
        guard settings.dashboardEnabled else {
            stop()
            return
        }
        switch availability {
        case .off:
            applySettings()
        case .starting(let port), .running(let port), .failed(let port, _):
            if port != settings.dashboardPort {
                applySettings()
            } else {
                refreshAvailability()
            }
        }
    }

    /// 监听状态（端口被占用、运行中掉线等）从服务器读回来，最多晚一拍反映到设置页
    private func refreshAvailability() {
        let port: Int
        switch availability {
        case .off: return
        case .starting(let current), .running(let current), .failed(let current, _): port = current
        }
        let updated: Availability
        switch server.currentState() {
        case .ready?: updated = .running(port: port)
        case .failed(let reason)?: updated = .failed(port: port, reason: reason)
        case .starting?, nil: return
        }
        if updated != availability { availability = updated }
    }

    private func resolveHostname() {
        guard !isResolvingHostname else { return }
        isResolvingHostname = true
        Task.detached(priority: .utility) { [weak self] in
            let name = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
            await self?.setHostname(name)
        }
    }

    private func setHostname(_ name: String) {
        hostname = name
    }

    // MARK: 采样

    func sampleOnce() {
        reconcile()

        let now = Date()
        let network = store.network
        // 网页端的走势按累计字节的差值算速率，这里把瞬时速率积分成累计值
        totalDown += (network?.downloadBytesPerSecond ?? 0) * Self.sampleInterval
        totalUp += (network?.uploadBytesPerSecond ?? 0) * Self.sampleInterval
        let sample = Sample(time: now.timeIntervalSince1970,
                            cpu: (store.cpu?.total ?? 0) * 100,
                            memory: (store.memory?.usedFraction ?? 0) * 100,
                            gpu: (store.gpu?.utilization ?? 0) * 100,
                            fan: (store.fastestFan?.fraction ?? 0) * 100,
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
        let fahrenheit = settings.useFahrenheit

        var system: [String: Any] = [
            "time": sample.time,
            "hostname": hostname,
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

        // 以下与主窗口的仪表盘是同一套内容和措辞：文字在这边按应用的语言与单位设置排好，网页只管摆放
        let health = HealthReport(store: store)
        system["health"] = ["score": health.score, "summary": health.summary, "tone": Self.name(health.tone)]
        let brand = store.topology.brand
        var chips = [brand.hasPrefix("Apple ") ? String(brand.dropFirst("Apple ".count)) : brand,
                     Format.capacity(ProcessInfo.processInfo.physicalMemory), store.system.osVersion]
        if let boot = store.system.bootDate { chips.append(tr("已运行 ") + Format.uptime(since: boot)) }
        chips.append(store.system.modelName)
        system["chips"] = chips.filter { !$0.isEmpty }

        let load = cpu?.loadAverage.first.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—"
        system["cpuFooter"] = tr("\(loadLevel(cpu?.total ?? 0)) · 负载 \(load)/\(store.topology.logicalCores)")
        system["cpuUser"] = cpu.map { Format.percent($0.user) } ?? "—"
        system["cpuSystem"] = cpu.map { Format.percent($0.system) } ?? "—"
        // 与应用里的各核心占用一致：按性能档分组，高性能档在前
        system["clusters"] = store.topology.clusters
            .sorted { ($0.coreIndices.first ?? 0) > ($1.coreIndices.first ?? 0) }
            .map { ["name": "\($0.name) · \($0.coreIndices.count)", "cores": $0.coreIndices] as [String: Any] }
        for (key, group) in [("cpuTemp", TemperatureGroup.cpu), ("gpuTemp", .gpu)] {
            if let summary = store.sensors?.temperature(group) {
                system[key] = ["text": Format.temperature(summary.maximum, fahrenheit: fahrenheit),
                               "tone": Self.name(.forTemperatureText(summary.maximum))]
            }
        }
        if let gpu = store.gpu {
            system["gpu"] = ["percent": (gpu.utilization * 100).rounded(),
                             "footer": [loadLevel(gpu.utilization), gpu.coreCount.map { tr("\($0) 核") }]
                                .compactMap { $0 }.joined(separator: " · ")] as [String: Any]
        }
        if let memory {
            system["memText"] = "\(Format.bytes(memory.used)) / \(Format.bytes(memory.total))"
            system["memPressure"] = ["text": tr("压力 \(memory.pressure.title)"), "tone": Self.name(memory.pressure.tone)]
        }
        if let disk {
            system["diskCapacity"] = Format.capacity(disk.total, base: .decimal)
            system["diskFooter"] = tr("可用 \(Format.bytes(disk.available, base: .decimal))")
        }
        if let interface = store.networkInterface {
            system["interface"] = interface.displayName == tr("VPN 隧道") ? "VPN" : interface.displayName
        }
        if let network = store.network {
            system["netTotalText"] = Format.menuBarRate(network.downloadBytesPerSecond + network.uploadBytesPerSecond)
            system["netDownText"] = Format.menuBarRate(network.downloadBytesPerSecond)
            system["netUpText"] = Format.menuBarRate(network.uploadBytesPerSecond)
        }
        let fans = store.sensors?.fans ?? []
        if let fastest = store.fastestFan {
            let average = fans.map(\.fraction).reduce(0, +) / Double(fans.count)
            system["fan"] = ["rpm": Int(fastest.current).formatted(),
                             "rpmValue": fastest.current.rounded(),
                             "chip": tr("转速 \(Format.percent(average))"),
                             "footer": fans.map { Format.rpm($0.current) }.joined(separator: " · "),
                             // 每台风扇的真实转速与占最高转速的比例：网页上的扇叶按它转
                             "fans": fans.map { ["rpm": $0.current.rounded(), "fraction": ($0.fraction * 1000).rounded() / 1000] }] as [String: Any]
        }
        if let battery = store.battery {
            var detail: [String] = []
            if let minutes = battery.minutesRemaining {
                detail.append(battery.isCharging ? tr("\(Format.duration(minutes: minutes))后充满") : tr("剩余 \(Format.duration(minutes: minutes))"))
            }
            if let cycles = battery.cycleCount { detail.append(tr("循环 \(cycles) 次")) }
            var info: [String: Any] = ["percent": Format.percent(battery.level), "level": battery.level,
                                       "state": battery.stateText, "tone": Self.name(battery.tone),
                                       "detail": detail.joined(separator: " · ")]
            if let health = battery.health {
                info["health"] = ["text": tr("健康度 \(Format.percent(health))"), "tone": health < 0.8 ? "warning" : "neutral"]
            }
            if let watts = battery.adapterWatts, battery.isPluggedIn { info["watts"] = "\(watts)W" }
            system["battery"] = info
        }
        system["labels"] = [
            "memory": tr("内存"), "disk": tr("磁盘"), "network": tr("网络"), "fan": tr("风扇"), "battery": tr("电池"),
            "cores": tr("各核心占用"), "user": tr("用户"), "system": tr("系统"), "processes": tr("高占用进程"),
        ]

        let history: [String: Any] = [
            "cpu": samples.map(\.cpu),
            "mem": samples.map(\.memory),
            "gpu": samples.map(\.gpu),
            "fan": samples.map(\.fan),
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

    private static func name(_ tone: Tone) -> String {
        switch tone {
        case .neutral: "neutral"
        case .primary: "primary"
        case .success: "success"
        case .warning: "warning"
        case .error: "error"
        }
    }

    /// 当前用户的进程里 CPU 最高的几个，条数跟「设置 · 通用」的排行显示数量（默认 6）；
    /// CPU 的口径（单核 / 整机）与着色都和应用里的“高占用进程”一致。
    /// 主窗口停在进程页时采样会带上系统进程，这里按 isOwned 筛掉，榜单不随本机在看什么而变
    private func topProcesses() -> [[String: Any]] {
        let total = Double(store.memory?.total ?? 0)
        let cores = Double(max(1, store.topology.logicalCores))
        return store.processes
            .filter(\.isOwned)
            .sorted { $0.cpu > $1.cpu }
            .prefix(settings.rankingRows(default: 6))
            .map { process in
                let share = process.cpu / cores
                return [
                    "pid": process.pid,
                    "name": process.displayName,
                    "cpu": (process.cpu * 100).rounded() / 100,
                    "mem": total > 0 ? (Double(process.memory) / total * 100 * 10).rounded() / 10 : 0,
                    "cpuText": settings.cpuSharePerCore ? Format.coreShare(process.cpu) : Format.machineShare(process.cpu),
                    "memText": Format.bytes(process.memory),
                    "tone": share >= 0.5 ? "error" : share >= 0.25 ? "warning" : "neutral",
                ] as [String: Any]
            }
    }
}
