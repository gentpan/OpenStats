import Darwin
import Foundation
import Localization

public struct CPUSampler {
    private var previousTicks: [[UInt32]] = []

    public init() {}

    public static func topology() -> CPUTopology {
        let brand = Sysctl.string("machdep.cpu.brand_string") ?? "CPU"
        let logical = Sysctl.int("hw.logicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount
        let levels = Sysctl.int("hw.nperflevels") ?? 1

        guard levels > 1 else {
            return CPUTopology(brand: brand, logicalCores: logical,
                               clusters: [CPUCluster(id: 0, name: tr("核心"), coreIndices: Array(0..<logical))])
        }

        // 核心序号从最低性能档开始排列：perflevel(n-1) 在前，perflevel0 在后
        var clusters: [CPUCluster] = []
        var offset = 0
        for level in stride(from: levels - 1, through: 0, by: -1) {
            let count = Sysctl.int("hw.perflevel\(level).logicalcpu") ?? 0
            guard count > 0 else { continue }
            let raw = Sysctl.string("hw.perflevel\(level).name") ?? ""
            clusters.append(CPUCluster(id: level, name: localizedClusterName(raw), coreIndices: Array(offset..<offset + count)))
            offset += count
        }
        return CPUTopology(brand: brand, logicalCores: logical, clusters: clusters.sorted { $0.id < $1.id })
    }

    private static func localizedClusterName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "super": tr("超级核")
        case "performance": tr("性能核")
        case "efficiency": tr("能效核")
        default: raw.isEmpty ? tr("核心") : raw
        }
    }

    public mutating func sample() -> CPULoad? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard kr == KERN_SUCCESS, let info else { return nil }
        // 内核分配的数组必须归还，否则每次采样都会泄漏
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        var ticks: [[UInt32]] = []
        ticks.reserveCapacity(Int(cpuCount))
        for core in 0..<Int(cpuCount) {
            ticks.append((0..<states).map { UInt32(bitPattern: info[core * states + $0]) })
        }
        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count else { return nil }

        var perCore: [Double] = []
        perCore.reserveCapacity(ticks.count)
        var sumUser: UInt64 = 0, sumSystem: UInt64 = 0, sumAll: UInt64 = 0
        for (now, before) in zip(ticks, previousTicks) {
            let delta = zip(now, before).map { UInt64($0 &- $1) }
            let user = delta[Int(CPU_STATE_USER)] + delta[Int(CPU_STATE_NICE)]
            let system = delta[Int(CPU_STATE_SYSTEM)]
            let all = user + system + delta[Int(CPU_STATE_IDLE)]
            perCore.append(all == 0 ? 0 : Double(user + system) / Double(all))
            sumUser += user
            sumSystem += system
            sumAll += all
        }
        guard sumAll > 0 else { return nil }

        var averages = [Double](repeating: 0, count: 3)
        let loadCount = getloadavg(&averages, 3)
        let user = Double(sumUser) / Double(sumAll)
        let system = Double(sumSystem) / Double(sumAll)
        return CPULoad(total: min(1, user + system), user: user, system: system, perCore: perCore,
                       loadAverage: loadCount > 0 ? Array(averages.prefix(Int(loadCount))) : [])
    }
}

/// 整机累计的 CPU 时钟滴答（各核相加），两次读数相减就是这段时间的平均占用。
/// 小组件每次刷新记下一份，下次刷新时直接相减，不必为了两次采样停半秒
public struct CPUTicks: Sendable, Codable, Equatable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32
    /// 开机时间：重启后计数从零开始，与重启前的读数不能相减
    public var bootTime: Int

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32, bootTime: Int) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
        self.bootTime = bootTime
    }

    public static func read() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        let bootTime = sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 ? Int(boot.tv_sec) : 0
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3,
                        bootTime: bootTime)
    }

    /// 从 `previous` 到这次的平均占用（0…1）。计数是 32 位的，按回绕一次计算；
    /// 重启过、或间隔太短（不足一个核一秒的滴答，读数噪声大）时返回 nil
    public func usage(since previous: CPUTicks) -> Double? {
        guard bootTime == previous.bootTime else { return nil }
        let busy = Double(user &- previous.user) + Double(system &- previous.system) + Double(nice &- previous.nice)
        let total = busy + Double(idle &- previous.idle)
        guard total >= 100 else { return nil }
        return min(1, max(0, busy / total))
    }
}
