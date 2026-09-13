import Foundation

public struct History<Element: Sendable>: Sendable {
    public let capacity: Int
    public private(set) var elements: [Element] = []

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        elements.reserveCapacity(self.capacity)
    }

    public mutating func append(_ element: Element) {
        if elements.count == capacity { elements.removeFirst() }
        elements.append(element)
    }
}

public enum Format {
    public enum ByteBase: Sendable {
        case binary   // 内存：1 GB = 1024³，与活动监视器一致
        case decimal  // 磁盘：1 GB = 1000³，与访达一致
    }

    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    public static func bytes(_ value: UInt64, base: ByteBase = .binary) -> String {
        bytes(Double(value), base: base)
    }

    public static func bytes(_ value: Double, base: ByteBase = .binary) -> String {
        let step: Double = base == .binary ? 1024 : 1000
        var amount = max(0, value)
        var index = 0
        while amount >= step, index < units.count - 1 {
            amount /= step
            index += 1
        }
        if index == 0 { return "\(Int(amount)) B" }
        let digits = amount >= 100 ? 0 : 1
        return "\(amount.formatted(.number.precision(.fractionLength(digits)))) \(units[index])"
    }

    /// 菜单栏网速：保留完整单位，数字最多 3 位，宽度稳定
    /// 例：512 B/s、12 KB/s、154 KB/s、1.2 MB/s、12 MB/s、1.1 GB/s
    public static func menuBarRate(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = max(0, bytesPerSecond)
        var index = 0
        // 超过 999 就进位，避免出现 1023 KB/s 这种 4 位数
        while value >= 999.5, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        let text = index >= 2 && value < 9.95
            ? value.formatted(.number.precision(.fractionLength(1)))
            : String(Int(value.rounded()))
        return "\(text) \(units[index])"
    }

    public static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    public static func temperature(_ celsius: Double, fahrenheit: Bool = false) -> String {
        fahrenheit ? "\(Int((celsius * 9 / 5 + 32).rounded()))°F" : "\(Int(celsius.rounded()))°C"
    }

    public static func rpm(_ value: Double) -> String {
        "\(Int(value.rounded())) RPM"
    }

    public static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) 分钟"
        case (_, 0): return "\(hours) 小时"
        default: return "\(hours) 小时 \(rest) 分钟"
        }
    }

    /// CPU 时间：不到 1 分钟显示“12.34 秒”，不到 1 小时“12:34”，更长“1:02:03”
    public static func cpuTime(_ seconds: Double) -> String {
        let total = max(0, seconds)
        if total < 60 { return "\(total.formatted(.number.precision(.fractionLength(2)))) 秒" }
        let whole = Int(total)
        let hours = whole / 3600, minutes = whole % 3600 / 60, secs = whole % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    public static func uptime(since date: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        let days = minutes / (60 * 24)
        let hours = (minutes / 60) % 24
        if days > 0 { return hours > 0 ? "\(days) 天 \(hours) 小时" : "\(days) 天" }
        if hours > 0 { return "\(hours) 小时" }
        return "\(minutes) 分钟"
    }
}
