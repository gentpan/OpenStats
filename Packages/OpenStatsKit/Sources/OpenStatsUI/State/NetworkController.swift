import Foundation
import HelperShared
import Metrics
import Observation

/// 一次连接探测：latency 为往返毫秒数，nil 表示超时或不可达
public struct ProbeSample: Sendable, Equatable {
    public let latency: Double?
}

/// 网络详情：接口与地址、公网 IP、连接探测、各进程流量与 DNS 配置
@MainActor
@Observable
public final class NetworkController {
    /// 主窗口显示 120 次，弹窗显示最近 60 次
    public static let probeCapacity = 120

    public private(set) var details: NetworkDetails?
    public private(set) var publicAddresses: PublicAddresses?
    public private(set) var isLookingUpPublic = false
    public private(set) var probes = History<ProbeSample>(capacity: probeCapacity)
    public private(set) var processes: [NetworkProcessUsage] = []

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    @ObservationIgnored private var probedAddress: String?
    @ObservationIgnored private var lastPublicLookup: (date: Date, localIPv4: [String])?
    @ObservationIgnored private var isPaused = false
    @ObservationIgnored private var wantsDetail = false
    @ObservationIgnored private var inMenuBar = false
    /// 正在运行的探测是否为前台频率；前后台切换时重启循环，不必等完后台的长间隔
    @ObservationIgnored private var probingForeground: Bool?

    /// 详情关闭、只在菜单栏显示网速时的低频探测间隔
    static let backgroundProbeSeconds = 10

    @ObservationIgnored private let geo: GeoDatabaseController

    init(settings: AppSettings, geo: GeoDatabaseController) {
        self.settings = settings
        self.geo = geo
    }

    // MARK: 统计

    /// 最近一次成功探测的延迟
    var latency: Double? { probes.elements.last?.latency }

    /// 抖动：相邻两次成功探测的延迟差的平均值
    var jitter: Double? {
        let values = probes.elements.suffix(20).compactMap(\.latency)
        guard values.count > 2 else { return nil }
        let differences = zip(values.dropFirst(), values).map { abs($0 - $1) }
        return differences.reduce(0, +) / Double(differences.count)
    }

    var lossRate: Double? {
        let recent = probes.elements
        guard !recent.isEmpty else { return nil }
        return Double(recent.filter { $0.latency == nil }.count) / Double(recent.count)
    }

    var probeAddress: String? {
        settings.probeTarget.address(router: details?.physical?.router)
    }

    // MARK: 生命周期

    /// 网络详情打开时按设置的间隔探测；只在菜单栏显示网络项时按 10 秒低频探测（可在设置里关闭），其余时间停止
    func setVisibility(inMenuBar: Bool, detailVisible: Bool) {
        self.inMenuBar = inMenuBar
        wantsDetail = detailVisible
        applyDetailState()
        applyProbeState()
    }

    private func applyProbeState() {
        let foreground = wantsDetail
        let shouldRun = settings.probeEnabled && !isPaused
            && (foreground || (inMenuBar && settings.probeInBackground))
        guard shouldRun else {
            probeTask?.cancel()
            probeTask = nil
            probingForeground = nil
            return
        }
        guard probeTask == nil || probingForeground != foreground else { return }
        probeTask?.cancel()
        probingForeground = foreground
        startProbing()
    }

    /// 探测目标或间隔变化时重新开始，历史清空避免混入不同目标的数据
    func restartProbing() {
        guard probeTask != nil else { return }
        probeTask?.cancel()
        probes = History(capacity: Self.probeCapacity)
        startProbing()
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        applyProbeState()
        applyDetailState()
    }

    /// 网络详情打开时每 2 秒刷新接口信息与进程流量，关闭后停止
    private func applyDetailState() {
        let shouldRun = wantsDetail && !isPaused
        guard shouldRun != (detailTask != nil) else { return }
        detailTask?.cancel()
        detailTask = nil
        // 关闭时保留上次的进程列表，再次打开时不会先闪一下空白
        guard shouldRun else { return }
        detailTask = Task { [weak self] in
            var sampler = NetworkProcessSampler()
            var tick = 0
            while !Task.isCancelled {
                // 接口信息每 4 秒读一次，进程流量每 2 秒
                if tick % 2 == 0 {
                    let details = await Task.detached { NetworkDetailsReader.read() }.value
                    guard !Task.isCancelled, let self else { return }
                    if details != self.details { self.details = details }
                    if tick == 0 { self.lookUpPublicAddressesIfStale() }
                }
                let (usage, next) = await Task.detached { [sampler] in
                    var copy = sampler
                    let usage = copy.sample()
                    return (usage, copy)
                }.value
                sampler = next
                guard !Task.isCancelled, let self else { return }
                self.processes = usage
                tick += 1
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func refreshDetails() async {
        details = await Task.detached { NetworkDetailsReader.read() }.value
    }

    // MARK: 公网 IP

    func lookUpPublicAddresses() {
        guard settings.publicIPLookup, !isLookingUpPublic else { return }
        isLookingUpPublic = true
        let localIPv4 = details?.physical?.ipv4 ?? []
        Task {
            // 有本地 GeoLite2 时只向外查询公网 IP，归属地与 ASN 在本机查
            let local = geo.isAvailable
            var result = await PublicAddressLookup.fetch(includeGeo: !local)
            if local, let address = result.ipv4 ?? result.ipv6, let location = geo.locate(address) {
                result.countryCode = location.countryCode ?? result.countryCode
                result.city = location.city
                result.asn = location.asn
                result.organization = location.organization
                result.source = .localDatabase
            }
            publicAddresses = result
            lastPublicLookup = (Date(), localIPv4)
            isLookingUpPublic = false
        }
    }

    /// 10 分钟内且本地地址未变化时沿用上次结果
    private func lookUpPublicAddressesIfStale() {
        guard settings.publicIPLookup else { return }
        let localIPv4 = details?.physical?.ipv4 ?? []
        if let last = lastPublicLookup, Date().timeIntervalSince(last.date) < 600, last.localIPv4 == localIPv4 { return }
        lookUpPublicAddresses()
    }

    func clearPublicAddresses() {
        publicAddresses = nil
        lastPublicLookup = nil
    }

    // MARK: 探测

    private func startProbing() {
        let foreground = probingForeground ?? true
        probeTask = Task { [weak self] in
            var sequence: UInt16 = 0
            let clock = ContinuousClock()
            while !Task.isCancelled {
                guard let self else { return }
                let interval = Double(foreground ? self.settings.probeSeconds : Self.backgroundProbeSeconds)
                if self.details == nil { await self.refreshDetails() }
                let started = clock.now
                guard let address = self.probeAddress else {
                    try? await Task.sleep(for: .seconds(interval))
                    continue
                }
                sequence &+= 1
                let current = sequence
                let latency = await Task.detached {
                    ConnectivityProbe.ping(address, sequence: current, timeout: min(interval, 1.5))
                }.value
                guard !Task.isCancelled else { return }
                self.probes.append(ProbeSample(latency: latency))
                // 后台探测允许系统合并唤醒，更省电
                try? await Task.sleep(until: started + .seconds(interval),
                                      tolerance: foreground ? .milliseconds(100) : .seconds(2), clock: clock)
            }
        }
    }

    // MARK: 截图

    /// 截图时换成文档示例地址，不暴露本机的 IP 与硬件地址
    func maskForSnapshot() {
        guard var details else { return }
        details.physical?.ipv4 = ["192.168.1.20"]
        details.physical?.ipv6 = ["2001:db8::20"]
        details.physical?.router = "192.168.1.1"
        details.physical?.hardwareAddress = "a4:83:e7:12:34:56"
        details.dnsServers = details.physical?.manualDNS.isEmpty == false ? details.physical!.manualDNS : ["192.168.1.1"]
        self.details = details
        publicAddresses = PublicAddresses(ipv4: "203.0.113.24", ipv6: nil, countryCode: "CN",
                                          city: "Shanghai", asn: "AS64500", organization: "EXAMPLE NETWORK")
    }
}
