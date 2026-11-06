import Darwin
import Foundation
import Localization

// “系统数据”里常见的大件：读它们需要的几样外部信息。都只读，不改任何东西。

// MARK: - 完全磁盘访问权限

public enum FullDiskAccess {
    /// 系统的隐私授权数据库只有拿到“完全磁盘访问权限”的进程才能打开；没有权限时直接失败，不会弹授权框
    public static func isGranted(home: String = NSHomeDirectory()) -> Bool {
        for path in ["/Library/Application Support/com.apple.TCC/TCC.db", home + "/Library/Application Support/com.apple.TCC/TCC.db"] {
            let descriptor = open(path, O_RDONLY)
            if descriptor >= 0 {
                close(descriptor)
                return true
            }
        }
        return false
    }
}

// MARK: - 模拟器

/// simctl 报告的模拟器设备与运行时
public struct SimulatorInventory: Sendable, Equatable {
    public struct Device: Sendable, Equatable {
        public let name: String
        /// 形如 com.apple.CoreSimulator.SimRuntime.iOS-17-0
        public let runtime: String
        public let isAvailable: Bool
        public let dataPath: String?
    }

    public struct Runtime: Sendable, Equatable {
        /// 形如 com.apple.CoreSimulator.SimRuntime.iOS-17-0，和设备里的 runtime 对得上
        public let runtimeIdentifier: String
        public let version: String
        public let build: String
        public let sizeBytes: UInt64
        public let lastUsed: Date?
        public let deletable: Bool
        public let path: String?
    }

    public var devices: [Device]
    public var runtimes: [Runtime]

    public init(devices: [Device], runtimes: [Runtime]) {
        self.devices = devices
        self.runtimes = runtimes
    }

    /// `simctl list devices -j`
    static func parseDevices(_ data: Data) -> [Device]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let byRuntime = root["devices"] as? [String: [[String: Any]]] else { return nil }
        return byRuntime.flatMap { runtime, devices in
            devices.compactMap { device in
                guard let name = device["name"] as? String else { return nil }
                return Device(name: name, runtime: runtime, isAvailable: device["isAvailable"] as? Bool ?? true,
                              dataPath: device["dataPath"] as? String)
            }
        }
    }

    /// `simctl runtime list -j`：以运行时编号为键的字典
    static func parseRuntimes(_ data: Data) -> [Runtime]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return nil }
        let dates = ISO8601DateFormatter()
        return root.values.compactMap { runtime in
            guard let identifier = runtime["runtimeIdentifier"] as? String else { return nil }
            return Runtime(runtimeIdentifier: identifier,
                           version: runtime["version"] as? String ?? "",
                           build: runtime["build"] as? String ?? "",
                           sizeBytes: (runtime["sizeBytes"] as? NSNumber)?.uint64Value ?? 0,
                           lastUsed: (runtime["lastUsedAt"] as? String).flatMap { dates.date(from: $0) },
                           deletable: runtime["deletable"] as? Bool ?? false,
                           path: runtime["path"] as? String)
        }
    }

    /// 用过模拟器、装了 Xcode 才去问 simctl。直接运行 Xcode 里的 simctl，不经过 xcrun：
    /// 没装开发工具时 xcrun 会弹出“安装命令行工具”的对话框
    public static func load(home: String = NSHomeDirectory()) -> SimulatorInventory? {
        guard FileManager.default.fileExists(atPath: home + "/Library/Developer/CoreSimulator/Devices"),
              let select = ShellTool.run("/usr/bin/xcode-select", ["-p"], timeout: 5), select.status == 0 else { return nil }
        let developer = String(decoding: select.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let simctl = developer + "/usr/bin/simctl"
        guard FileManager.default.isExecutableFile(atPath: simctl),
              let list = ShellTool.run(simctl, ["list", "devices", "-j"], timeout: 30), list.status == 0,
              let devices = parseDevices(list.output) else { return nil }
        // 旧版 Xcode 没有 runtime 子命令：只是没有运行时清单
        var runtimes: [Runtime] = []
        if let result = ShellTool.run(simctl, ["runtime", "list", "-j"], timeout: 30), result.status == 0 {
            runtimes = parseRuntimes(result.output) ?? []
        }
        return SimulatorInventory(devices: devices, runtimes: runtimes)
    }

    /// 一次扫描里有两条规则要用：给出一个只问一次 simctl 的读取函数（规则是并发扫描的，后到的等先到的读完）
    public static func loader(home: String = NSHomeDirectory()) -> @Sendable () -> SimulatorInventory? {
        let cache = LoadOnce<SimulatorInventory?>()
        return { cache.value { load(home: home) } }
    }

    /// com.apple.CoreSimulator.SimRuntime.iOS-17-0 → iOS 17.0
    static func runtimeName(_ identifier: String) -> String {
        let short = identifier.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
        var parts = short.split(separator: "-").map(String.init)
        guard parts.count >= 2 else { return short }
        let platform = parts.removeFirst()
        return (platform == "xrOS" ? "visionOS" : platform) + " " + parts.joined(separator: ".")
    }

    /// 运行时已经不在的设备：打不开，数据还占着空间
    func unavailableDeviceEntries() -> [ManualEntry] {
        devices.filter { !$0.isAvailable }.compactMap { device in
            guard let dataPath = device.dataPath else { return nil }
            return ManualEntry(url: URL(fileURLWithPath: dataPath).deletingLastPathComponent(),
                               title: device.name + " · " + Self.runtimeName(device.runtime))
        }
    }

    /// 可以删、而且没有任何模拟器设备在用的运行时
    func unusedRuntimeEntries() -> [ManualEntry] {
        let used = Set(devices.map(\.runtime))
        return runtimes.filter { $0.deletable && !used.contains($0.runtimeIdentifier) }.map { runtime in
            var title = Self.runtimeName(runtime.runtimeIdentifier)
            if !runtime.build.isEmpty { title += " (\(runtime.build))" }
            if let lastUsed = runtime.lastUsed {
                title += " · " + tr("上次使用 \(lastUsed.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()))")
            } else {
                title += " · " + tr("从未使用")
            }
            return ManualEntry(url: URL(fileURLWithPath: runtime.path ?? "/Library/Developer/CoreSimulator"), title: title,
                               size: runtime.sizeBytes)
        }
    }
}

// MARK: - Ollama

enum OllamaModels {
    /// ~/.ollama/models/manifests/<仓库>/<命名空间>/<模型>/<标签>：每个清单列出这个模型用到的文件和大小。
    /// 文件可能被几个模型共用，所以按模型加起来会比实际占用多一点
    static func entries(home: String) -> [ManualEntry] {
        let root = URL(fileURLWithPath: home + "/.ollama/models/manifests")
        var entries: [ManualEntry] = []
        for registry in directories(in: root) {
            for namespace in directories(in: registry) {
                for model in directories(in: namespace) {
                    for tag in files(in: model) {
                        guard let size = manifestSize(tag) else { continue }
                        var name = model.lastPathComponent + ":" + tag.lastPathComponent
                        if namespace.lastPathComponent != "library" { name = namespace.lastPathComponent + "/" + name }
                        if registry.lastPathComponent != "registry.ollama.ai" { name = registry.lastPathComponent + "/" + name }
                        entries.append(ManualEntry(url: tag, title: name, size: size))
                    }
                }
            }
        }
        return entries
    }

    static func manifestSize(_ url: URL) -> UInt64? {
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var parts = (manifest["layers"] as? [[String: Any]]) ?? []
        if let config = manifest["config"] as? [String: Any] { parts.append(config) }
        let total = parts.reduce(UInt64(0)) { $0 + ((($1["size"] as? NSNumber)?.uint64Value) ?? 0) }
        return total > 0 ? total : nil
    }

    private static func contents(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    }

    private static func directories(in url: URL) -> [URL] {
        contents(of: url).filter { FileIdentity.status(of: $0.path)?.isDirectory == true }
    }

    private static func files(in url: URL) -> [URL] {
        contents(of: url).filter { FileIdentity.status(of: $0.path)?.isRegularFile == true }
    }
}

/// 第一次取值时计算，之后都返回同一个结果
private final class LoadOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?
    private var loaded = false

    func value(_ compute: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        if !loaded {
            stored = compute()
            loaded = true
        }
        return stored!
    }
}

// MARK: - 带超时运行命令

/// 读子进程输出的缓冲：读的线程写一次，等待的线程读一次，中间用信号量隔开
private final class OutputBox: @unchecked Sendable {
    var data = Data()
}

extension ShellTool {
    /// 带超时：工具卡住（例如 CoreSimulator 服务没响应）就结束它，返回 nil。只取标准输出
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) -> (status: Int32, output: Data)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // 边跑边读：输出超过管道缓冲时不读，子进程会卡在写上
        let box = OutputBox()
        let finished = DispatchSemaphore(value: 0)
        let handle = pipe.fileHandleForReading
        DispatchQueue.global().async {
            box.data = handle.readDataToEndOfFile()
            finished.signal()
        }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            _ = finished.wait(timeout: .now() + 2)
            return nil
        }
        process.waitUntilExit()
        return (process.terminationStatus, box.data)
    }
}
