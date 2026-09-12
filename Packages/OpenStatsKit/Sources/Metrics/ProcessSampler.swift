import Darwin
import Foundation

public struct ProcessSampler {
    private struct Identity: Hashable {
        let pid: Int32
        let startTime: UInt64
    }

    private struct Meta {
        let name: String
        let path: String?
        let bundle: String?
    }

    private var previousCPU: [Identity: UInt64] = [:]
    private var previousTime: UInt64 = 0
    private var metaCache: [Identity: Meta] = [:]

    public init() {}

    /// 返回按 CPU 排序的进程；无权限读取的进程（通常属于 root）会被跳过。
    public mutating func sample(limit: Int = 50) -> [ProcessUsage] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.stride)))
        guard count > 0 else { return [] }

        // CPU 时间与墙钟时间都用 mach 绝对时间单位，比值无需换算时基
        let now = mach_absolute_time()
        let elapsed = previousTime > 0 ? now - previousTime : 0

        var cpuTimes: [Identity: UInt64] = [:]
        var liveMeta: [Identity: Meta] = [:]
        var results: [ProcessUsage] = []
        results.reserveCapacity(count)

        for pid in pids.prefix(count) where pid > 0 {
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard status == 0 else { continue }

            let identity = Identity(pid: pid, startTime: info.ri_proc_start_abstime)
            let cpuTime = info.ri_user_time + info.ri_system_time
            cpuTimes[identity] = cpuTime

            let meta = metaCache[identity] ?? Self.meta(for: pid)
            liveMeta[identity] = meta

            var cpu = 0.0
            if elapsed > 0, let before = previousCPU[identity], cpuTime >= before {
                cpu = Double(cpuTime - before) / Double(elapsed)
            }
            results.append(ProcessUsage(pid: pid, name: meta.name, executablePath: meta.path,
                                        appBundlePath: meta.bundle, cpu: cpu, memory: info.ri_phys_footprint))
        }

        previousCPU = cpuTimes
        previousTime = now
        metaCache = liveMeta

        results.sort { $0.cpu == $1.cpu ? $0.memory > $1.memory : $0.cpu > $1.cpu }
        return Array(results.prefix(limit))
    }

    private static func meta(for pid: pid_t) -> Meta {
        var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        let path = pathLength > 0 ? String(nullTerminated: pathBuffer) : nil

        var name = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        if name.isEmpty {
            var nameBuffer = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            name = String(nullTerminated: nameBuffer)
        }

        // 取最外层 .app，辅助进程也能显示主应用图标
        let bundle = path.flatMap { path -> String? in
            guard let range = path.range(of: ".app/") else { return nil }
            return String(path[..<range.lowerBound]) + ".app"
        }
        return Meta(name: name.isEmpty ? "PID \(pid)" : name, path: path, bundle: bundle)
    }
}
