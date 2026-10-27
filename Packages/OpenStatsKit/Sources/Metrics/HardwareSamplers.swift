import Foundation
import IOKit
import IOKit.ps
import Localization

// MARK: - 磁盘

public enum DiskSampler {
    /// 可清除空间要系统去统计（一次约 7 毫秒 CPU），普通可用空间几乎不花时间。
    /// 可清除的部分记住 5 分钟，期间可用空间 = 普通可用空间 + 记住的可清除空间，写入文件后仍能马上反映
    static let purgeableLifetime: TimeInterval = 5 * 60
    private static let purgeableCache = PurgeableCache()

    /// `fresh` 为真时重新统计可清除空间（磁盘页打开时）
    public static func sample(volume: URL = URL(fileURLWithPath: "/"), fresh: Bool = false, now: Date = Date()) -> DiskUsage? {
        let cached = fresh ? nil : purgeableCache.value(for: volume.path, now: now)
        var keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        if cached == nil { keys.insert(.volumeAvailableCapacityForImportantUsageKey) }
        guard let values = try? volume.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }
        let strict = max(0, Int64(values.volumeAvailableCapacity ?? 0))
        let purgeable: Int64
        if let cached {
            purgeable = cached
        } else {
            // “重要用途可用空间”包含可清除空间，与访达显示一致；减去普通可用空间就是可清除的部分
            let important = max(0, values.volumeAvailableCapacityForImportantUsage ?? 0)
            purgeable = max(0, important - strict)
            purgeableCache.store(purgeable, for: volume.path, now: now)
        }
        var usage = DiskUsage(volumeName: values.volumeLocalizedName ?? tr("磁盘"),
                              total: UInt64(total), available: UInt64(strict + purgeable),
                              purgeable: UInt64(purgeable))
        if volume.path == "/" { usage.breakdown = breakdown(usage) }
        return usage
    }

    /// 各卷最近一次统计出的可清除空间；应用与小组件里都可能从不同线程读写
    private final class PurgeableCache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: (bytes: Int64, date: Date)] = [:]

        func value(for path: String, now: Date) -> Int64? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = entries[path], now.timeIntervalSince(entry.date) < DiskSampler.purgeableLifetime,
                  now >= entry.date else { return nil }
            return entry.bytes
        }

        func store(_ bytes: Int64, for path: String, now: Date) {
            lock.lock()
            entries[path] = (bytes, now)
            lock.unlock()
        }
    }

    /// APFS 下系统卷、数据卷与虚拟内存卷共用一个容器：statfs 对每个卷都只给出整个容器的用量，
    /// 每个卷自己占了多少要用 getattrlist 的 ATTR_VOL_SPACEUSED（df 也是这样读的）
    private static func breakdown(_ usage: DiskUsage) -> DiskBreakdown? {
        func used(_ path: String) -> UInt64? {
            var attributes = attrlist(bitmapcount: u_short(ATTR_BIT_MAP_COUNT), reserved: 0, commonattr: 0,
                                      volattr: attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_SPACEUSED),
                                      dirattr: 0, fileattr: 0, forkattr: 0)
            // 返回的缓冲区：4 字节总长度，后面紧跟 8 字节的已用量
            var buffer = [UInt8](repeating: 0, count: 32)
            guard getattrlist(path, &attributes, &buffer, buffer.count, 0) == 0 else { return nil }
            let value = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
            return value > 0 ? UInt64(value) : nil
        }
        guard let system = used("/"), let data = used("/System/Volumes/Data") else { return nil }
        return DiskBreakdown.compose(total: usage.total, free: usage.free, purgeable: usage.purgeable,
                                     systemUsed: system, dataUsed: data, vmUsed: used("/System/Volumes/VM") ?? 0)
    }
}

// MARK: - 电池

public enum BatterySampler {
    /// `waitForSystemHealth` 为真时，系统的最大容量没读过或已过期就当场读（几十毫秒，一小时最多一次），只在后台线程这样调用；
    /// 为假时只用记下的读数，过期了在后台重读，这次先用上次的值
    public static func sample(waitForSystemHealth: Bool = false) -> BatteryStatus? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let pluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charged = description[kIOPSIsChargedKey] as? Bool ?? false
            let minutesKey = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutes = (description[minutesKey] as? Int).flatMap { $0 > 0 ? $0 : nil }

            var status = BatteryStatus(level: maximum > 0 ? Double(current) / Double(maximum) : 0,
                                       isCharging: isCharging, isPluggedIn: pluggedIn, isFullyCharged: charged,
                                       minutesRemaining: pluggedIn && !isCharging ? nil : minutes)
            fillRegistryDetails(&status)
            status.systemHealth = SystemBatteryHealth.maximumCapacity(wait: waitForSystemHealth)
            return status
        }
        return nil
    }

    private static func fillRegistryDetails(_ status: inout BatteryStatus) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        status.cycleCount = IORegistry.property(service, "CycleCount") as? Int
        if let data = IORegistry.property(service, "BatteryData") as? [String: Any],
           let design = data["DesignCapacity"] as? Int, design > 0,
           let capacity = (data["NominalChargeCapacity"] as? Int) ?? (data["FullChargeCapacity"] as? Int) {
            // 标称满充容量是电量计平滑过的值，比原始满充容量（随温度和使用起伏）稳定。
            // 系统设置里的“最大容量”不是它除以设计容量：界面上的健康度优先用 SystemBatteryHealth 读到的系统值，这个推算值单独显示
            status.estimatedHealth = min(1, Double(capacity) / Double(design))
            status.designCapacity = design
            status.fullChargeCapacity = capacity
        }
        // 电压单位 mV，电流单位 mA（有符号，放电为负）
        if let millivolts = IORegistry.property(service, "Voltage") as? Int, millivolts > 0 {
            status.voltage = Double(millivolts) / 1000
        }
        // 负值有时以无符号数存放，按有符号 64 位读出
        if let milliamps = (IORegistry.property(service, "InstantAmperage") ?? IORegistry.property(service, "Amperage")) as? NSNumber {
            status.amperage = Double(milliamps.int64Value) / 1000
        }
        if let adapter = IORegistry.property(service, "AdapterDetails") as? [String: Any] {
            status.adapterWatts = adapter["Watts"] as? Int
        }
    }
}

/// 系统设置“电池 › 电池健康”里的最大容量。它由系统电源服务按苹果自己的算法得出，
/// 和“标称满充容量 ÷ 设计容量”常差一两个百分点（例如系统显示 100%，相除只有 97.7%）。
/// 系统信息读它用的接口要苹果的私有权限，第三方应用只能从 system_profiler 拿；值变化很慢，读一次记一小时
enum SystemBatteryHealth {
    static let lifetime: TimeInterval = 60 * 60
    /// 沙盒里（桌面小组件）的 system_profiler 读不到电源服务，不启动它
    private static let isAvailable = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil
    /// 重读排在这条串行队列上，同时来的几次请求只启动一次进程
    private static let queue = DispatchQueue(label: "OpenStats.SystemBatteryHealth", qos: .utility)
    private static let cache = Cache()

    /// 最大容量（0...1）；读不到（如没有这项读数的机型）时为空
    static func maximumCapacity(wait: Bool, now: Date = Date()) -> Double? {
        guard isAvailable else { return nil }
        if let entry = cache.fresh(now: now) { return entry.value }
        if wait { return queue.sync { refreshIfStale() } }
        queue.async { _ = refreshIfStale() }
        return cache.latest
    }

    private static func refreshIfStale() -> Double? {
        if let entry = cache.fresh(now: Date()) { return entry.value }
        let value = parse(SystemProfiler.run("SPPowerDataType", detailLevel: "mini", timeout: 10))
        return cache.store(value, date: Date())
    }

    /// `system_profiler SPPowerDataType -json` 里 sppower_battery_health_info 的 "100%"
    static func parse(_ data: Data) -> Double? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPPowerDataType"] as? [[String: Any]] else { return nil }
        for section in sections {
            if let info = section["sppower_battery_health_info"] as? [String: Any],
               let percent = SystemProfiler.percent(info["sppower_battery_health_maximum_capacity"]), percent > 0 {
                return Double(percent) / 100
            }
        }
        return nil
    }

    private final class Cache: @unchecked Sendable {
        struct Entry { var value: Double?; var date: Date }
        private let lock = NSLock()
        private var entry: Entry?

        func fresh(now: Date) -> Entry? {
            lock.withLock {
                guard let entry, now >= entry.date, now.timeIntervalSince(entry.date) < SystemBatteryHealth.lifetime else { return nil }
                return entry
            }
        }

        var latest: Double? { lock.withLock { entry?.value } }

        /// 这次没读到（超时等）就沿用上次读到的值，一小时后再试
        func store(_ value: Double?, date: Date) -> Double? {
            lock.withLock {
                let kept = value ?? entry?.value
                entry = Entry(value: kept, date: date)
                return kept
            }
        }
    }
}

// MARK: - GPU

public enum GPUSampler {
    public static func sample() -> GPUUsage? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var best: GPUUsage?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            // 只读取需要的属性，避免复制整张属性表
            guard let stats = IORegistry.property(service, "PerformanceStatistics") as? [String: Any],
                  let utilization = stats["Device Utilization %"] as? Int else { continue }
            let percent = { (key: String) in (stats[key] as? Int).map { Double(min(100, max(0, $0))) / 100 } }
            var usage = GPUUsage(name: IORegistry.property(service, "model") as? String ?? "GPU",
                                 utilization: Double(min(100, max(0, utilization))) / 100,
                                 coreCount: IORegistry.property(service, "gpu-core-count") as? Int)
            usage.rendererUtilization = percent("Renderer Utilization %")
            usage.tilerUtilization = percent("Tiler Utilization %")
            usage.memoryInUse = (stats["In use system memory"] as? Int).map { UInt64(max(0, $0)) }
            if best == nil || usage.utilization > best!.utilization { best = usage }
        }
        return best
    }
}

// MARK: - 系统信息

public enum SystemInfoReader {
    public static func read() -> SystemInfo {
        let product = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        var modelName = Sysctl.string("hw.model") ?? "Mac"
        if product != 0 {
            if let name = IORegistry.string(fromData: IORegistry.property(product, "product-name")), !name.isEmpty {
                modelName = name
            }
            IOObjectRelease(product)
        }

        let version = ProcessInfo.processInfo.operatingSystemVersion
        let patch = version.patchVersion > 0 ? ".\(version.patchVersion)" : ""
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        let boot = sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0
            ? Date(timeIntervalSince1970: TimeInterval(bootTime.tv_sec)) : nil

        var info = SystemInfo(modelName: modelName,
                              osVersion: "macOS \(version.majorVersion).\(version.minorVersion)\(patch)",
                              bootDate: boot)
        info.modelIdentifier = Sysctl.string("hw.model") ?? ""
        info.osBuild = Sysctl.string("kern.osversion") ?? ""
        let platform = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if platform != 0 {
            info.serialNumber = IORegistryEntryCreateCFProperty(platform, kIOPlatformSerialNumberKey as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            IOObjectRelease(platform)
        }
        return info
    }
}
