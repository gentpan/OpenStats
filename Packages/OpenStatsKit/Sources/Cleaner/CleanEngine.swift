import Foundation
import Localization

public enum CleanEngine {
    // MARK: 扫描

    /// 并发扫描所有规则，只读，不修改任何文件
    public static func scan(_ rules: [CleanRule], environment: CleanEnvironment) async -> [RuleScan] {
        let safety = SafetyGuard(home: environment.home)
        return await withTaskGroup(of: (Int, RuleScan).self) { group in
            for (index, rule) in rules.enumerated() {
                group.addTask { (index, scanRule(rule, environment: environment, safety: safety)) }
            }
            var results = [(Int, RuleScan)]()
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    static func scanRule(_ rule: CleanRule, environment: CleanEnvironment, safety: SafetyGuard) -> RuleScan {
        let running = environment.runningBundleIdentifiers()
        if let app = rule.blockingApps.first(where: { running.contains($0.bundleID) }) {
            return RuleScan(rule: rule, items: [], skippedCount: 0, blocked: .appRunning(app.name))
        }

        let candidates: [URL]
        do {
            candidates = try rule.locate(environment)
        } catch {
            return RuleScan(rule: rule, items: [], skippedCount: 0, blocked: .needsFullDiskAccess)
        }

        // 预览与真正清理用同一个判断函数，预览不会承诺真实清理会拒绝的事
        let service = deletionService(environment: environment, safety: safety, log: nil)
        var items: [CleanItem] = []
        var skipped = 0
        for url in candidates {
            if Task.isCancelled { break }
            let identity = FileIdentity.capture(url)
            if service.evaluate(request(for: url, rule: rule, identity: identity, mode: .permanent, size: 0,
                                        environment: environment)) != nil {
                skipped += 1
                continue
            }
            let size = allocatedSize(of: url)
            if size > 0 { items.append(CleanItem(url: url, size: size, identity: identity)) }
        }
        items.sort { $0.size > $1.size }
        return RuleScan(rule: rule, items: items, skippedCount: skipped, blocked: nil)
    }

    static func deletionService(environment: CleanEnvironment, safety: SafetyGuard, log: CleanLog?) -> DeletionService {
        DeletionService(home: environment.home,
                        scope: { try safety.validate($0) },
                        running: { environment.runningAppsReadable ? .known(environment.runningBundleIdentifiers()) : .unknown },
                        now: environment.now,
                        standardTrasher: environment.trasher,
                        log: log)
    }

    static func request(for url: URL, rule: CleanRule, identity: FileIdentity?, mode: DeletionMode, size: UInt64,
                        environment: CleanEnvironment) -> DeletionRequest {
        DeletionRequest(url: url, mode: mode, base: URL(fileURLWithPath: environment.home), size: size, label: rule.id,
                        identity: identity,
                        guardApps: rule.blockingApps.map { GuardApp(bundleID: $0.bundleID, name: $0.name) },
                        checksOwnerApp: rule.checksOwnerApp, minimumAge: rule.minimumAge)
    }

    /// 实际占用的磁盘空间；不跟随符号链接
    public static func allocatedSize(of url: URL) -> UInt64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { return 0 }
        if values.isRegularFile == true {
            return UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [],
                                                              errorHandler: { _, _ in true }) else { return 0 }
        var total: UInt64 = 0
        while let file = enumerator.nextObject() as? URL {
            guard let fileValues = try? file.resourceValues(forKeys: Set(keys)),
                  fileValues.isRegularFile == true else { continue }
            total += UInt64(fileValues.totalFileAllocatedSize ?? fileValues.fileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: 清理

    /// 清理选中规则的扫描结果。每一项都经过删除入口，动手前重新判断：扫描到执行之间应用可能已经启动、路径可能已被替换
    public static func clean(_ scans: [RuleScan], selected: Set<String>, preferTrash: Bool,
                             environment: CleanEnvironment, log: CleanLog? = CleanLog()) async -> CleanReport {
        let safety = SafetyGuard(home: environment.home)
        let service = deletionService(environment: environment, safety: safety, log: log)
        var report = CleanReport()

        for scan in scans where selected.contains(scan.id) && scan.isCleanable {
            let running = environment.runningBundleIdentifiers()
            if scan.rule.blockingApps.contains(where: { running.contains($0.bundleID) }) {
                report.skippedCount += scan.items.count
                continue
            }
            // 废纸篓规则本身必须永久删除；其他可再生内容按用户偏好决定
            let useTrash = scan.rule.id != RuleCatalog.trash.id && (scan.rule.policy == .trash || preferTrash)
            let mode: DeletionMode = useTrash ? .trash : .permanent
            let requests = scan.items.map {
                request(for: $0.url, rule: scan.rule, identity: $0.identity, mode: mode, size: $0.size, environment: environment)
            }
            for result in await service.execute(requests) {
                switch result.outcome {
                case .removed:
                    report.removedCount += 1
                    if useTrash { report.trashedBytes += result.request.size } else { report.freedBytes += result.request.size }
                case .blocked, .wouldRemove:
                    report.skippedCount += 1
                case .failed(let message):
                    report.failures.append(tr("\(result.request.url.lastPathComponent)：\(message)"))
                }
            }
        }
        return report
    }
}

/// 清理操作日志：~/Library/Logs/OpenStats/cleanup.log，每行一条 JSON
public struct CleanLog: Sendable {
    public let url: URL

    public init(url: URL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/OpenStats/cleanup.log")) {
        self.url = url
    }

    func record(request: DeletionRequest, outcome: DeletionOutcome, run: String) {
        var entry: [String: Any] = [
            "time": ISO8601DateFormatter().string(from: Date()),
            "run": run,
            "rule": request.label,
            "path": request.url.path,
            "bytes": request.size,
            "mode": request.mode.rawValue,
        ]
        switch outcome {
        case .removed(let trashedTo):
            entry["action"] = request.mode == .trash ? "trash" : "delete"
            if let trashedTo { entry["trashedTo"] = trashedTo.path }
        case .wouldRemove:
            entry["action"] = "dry-run"
        case .blocked(let block):
            entry["action"] = "skip"
            entry["reason"] = block.code
            entry["detail"] = block.description
        case .failed(let message):
            entry["action"] = "fail"
            entry["detail"] = message
        }
        guard var data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        data.append(0x0A)

        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
