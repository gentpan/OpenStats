import Foundation
import SMC

public struct CPUCluster: Sendable, Equatable, Identifiable {
    public let id: Int              // perflevel 序号，0 为最高性能档
    public let name: String         // 超级核 / 性能核 / 能效核
    public let coreIndices: [Int]   // 对应 host_processor_info 的核心序号
}

public struct CPUTopology: Sendable, Equatable {
    public let brand: String
    public let logicalCores: Int
    public let clusters: [CPUCluster]
}

public struct CPULoad: Sendable, Equatable {
    public var total: Double
    public var user: Double
    public var system: Double
    public var perCore: [Double]
    public var loadAverage: [Double]
}

public enum MemoryPressure: Int, Sendable {
    case normal = 1, warning = 2, critical = 4

    public var title: String {
        switch self {
        case .normal: "正常"
        case .warning: "偏高"
        case .critical: "严重"
        }
    }
}

public struct MemoryUsage: Sendable, Equatable {
    public var total: UInt64
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var cached: UInt64
    public var swapUsed: UInt64
    public var swapTotal: UInt64
    public var pressure: MemoryPressure
    /// 被压缩的内容原本的大小；与 compressed 之差就是压缩省下的内存
    public var uncompressed: UInt64
    /// 开机以来从交换区换入 / 换出的累计字节数，用相邻两次采样算速率
    public var swapInBytes: UInt64
    public var swapOutBytes: UInt64

    public var used: UInt64 { app + wired + compressed }
    public var usedFraction: Double { total == 0 ? 0 : min(1, Double(used) / Double(total)) }
    public var available: UInt64 { total > used ? total - used : 0 }
    /// 空闲 = 总量 - 已用 - 缓存文件
    public var free: UInt64 { total > used + cached ? total - used - cached : 0 }
    public var compressionSavings: UInt64 { uncompressed > compressed ? uncompressed - compressed : 0 }
    public var compressionRatio: Double? { compressed > 0 && uncompressed > 0 ? Double(uncompressed) / Double(compressed) : nil }
}

public struct NetworkInterfaceInfo: Sendable, Equatable {
    public var bsdName: String
    public var displayName: String
    public var ipv4: String?
}

public struct NetworkRate: Sendable, Equatable {
    public var downloadBytesPerSecond: Double
    public var uploadBytesPerSecond: Double
    public var totalDownloaded: UInt64
    public var totalUploaded: UInt64
}

public struct DiskUsage: Sendable, Equatable {
    public var volumeName: String
    public var total: UInt64
    public var available: UInt64

    public var used: UInt64 { total > available ? total - available : 0 }
    public var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

public struct BatteryStatus: Sendable, Equatable {
    public var level: Double            // 0...1
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var isFullyCharged: Bool
    public var minutesRemaining: Int?   // 放电剩余或充满所需时间
    public var cycleCount: Int?
    public var health: Double?          // 0...1
    public var adapterWatts: Int?
}

public struct GPUUsage: Sendable, Equatable {
    public var name: String
    public var utilization: Double      // 0...1
    public var coreCount: Int?
}

public struct ProcessUsage: Sendable, Equatable, Identifiable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let executablePath: String?
    public let appBundlePath: String?
    public var cpu: Double              // 以单核为 100%，与活动监视器一致
    public var memory: UInt64           // phys_footprint
}

public struct TemperatureSummary: Sendable, Equatable, Identifiable {
    public var id: TemperatureGroup { group }
    public let group: TemperatureGroup
    public var average: Double
    public var maximum: Double
    public var sensorCount: Int
}

public struct SensorReadings: Sendable, Equatable {
    public var temperatures: [TemperatureSummary]
    public var fans: [FanState]

    public init(temperatures: [TemperatureSummary], fans: [FanState]) {
        self.temperatures = temperatures
        self.fans = fans
    }

    public func temperature(_ group: TemperatureGroup) -> TemperatureSummary? {
        temperatures.first { $0.group == group }
    }
}

public struct SystemInfo: Sendable, Equatable {
    public var modelName: String
    public var osVersion: String
    public var bootDate: Date?
}

public struct MetricsSnapshot: Sendable {
    public var date = Date()
    public var cpu: CPULoad?
    public var memory: MemoryUsage?
    public var network: NetworkRate?
    public var networkInterface: NetworkInterfaceInfo?
    public var disk: DiskUsage?
    public var battery: BatteryStatus?
    public var gpu: GPUUsage?
    public var processes: [ProcessUsage]?
    public var sensors: SensorReadings?

    public init() {}
}
