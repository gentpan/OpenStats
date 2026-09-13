import AppKit
import Foundation
import HelperShared
import Metrics
import Observation
import os

/// 运行日志：写入系统统一日志（子系统 com.openstats.app），导出诊断信息时一并收集
enum Log {
    static let subsystem = "com.openstats.app"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let helper = Logger(subsystem: subsystem, category: "helper")
    static let fans = Logger(subsystem: subsystem, category: "fans")
    static let power = Logger(subsystem: subsystem, category: "power")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let update = Logger(subsystem: subsystem, category: "update")
}

/// 导出诊断信息：版本与系统、辅助工具状态、主要设置、最近 3 天的运行日志、清理记录与崩溃报告，打成一个 zip。
/// 不包含序列号、IP 地址与硬件地址。
@MainActor
@Observable
final class DiagnosticsExporter {
    enum Phase: Equatable {
        case idle
        case collecting
        case finished(URL)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    func export(model: AppModel) {
        guard phase != .collecting else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "OpenStats-诊断-\(Self.fileDate()).zip"
        panel.allowedContentTypes = [.zip]
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        NSApp.activate()
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        phase = .collecting
        Task {
            let summary = await Self.summary(model: model)
            do {
                try await Task.detached { try Self.writeArchive(summary: summary, to: destination) }.value
                Log.app.notice("已导出诊断信息")
                phase = .finished(destination)
            } catch {
                phase = .failed("导出失败：\(error.localizedDescription)")
            }
        }
    }

    func reveal() {
        if case .finished(let url) = phase { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    // MARK: 内容

    private static func summary(model: AppModel) async -> String {
        let bundle = Bundle.main
        let settings = model.settings
        let store = model.store
        let process = ProcessInfo.processInfo
        let remoteVersion = await model.helper.remoteProtocolVersion()
        var lines: [String] = []
        func section(_ title: String) { lines.append(""); lines.append("## \(title)") }
        func row(_ key: String, _ value: Any?) { lines.append("\(key): \(value.map { "\($0)" } ?? "—")") }

        lines.append("# OpenStats 诊断信息")
        row("导出时间", ISO8601DateFormatter().string(from: Date()))

        section("应用")
        row("版本", bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString"))
        row("构建", bundle.object(forInfoDictionaryKey: "CFBundleVersion"))
        row("位置", bundle.bundleURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        row("签名团队", CodeSigningInfo.currentTeamIdentifier() ?? "未签名（开发构建）")
        row("已运行", Format.uptime(since: launchDate))

        section("系统")
        row("机型", "\(store.system.modelName)（\(store.system.modelIdentifier)）")
        row("macOS", "\(store.system.osVersion)（\(store.system.osBuild)）")
        row("处理器核心", process.activeProcessorCount)
        row("内存", Format.bytes(process.physicalMemory))
        row("开机以来", Format.uptime(since: Date().addingTimeInterval(-process.systemUptime)))
        row("语言", Locale.preferredLanguages.prefix(3).joined(separator: ", "))
        row("温度传感器", store.sensors.map { "\($0.temperatures.count) 组" })
        row("风扇", store.sensors.map { "\($0.fans.count) 个" })
        row("电池", store.battery.map { "\(Format.percent($0.level))，\($0.isPluggedIn ? "接通电源" : "使用电池")，健康 \($0.health.map(Format.percent) ?? "—")" } ?? "无")

        section("辅助工具")
        row("状态", model.helper.status.title)
        if case .unavailable(let reason) = model.helper.status { row("原因", reason) }
        row("协议版本", "应用 \(HelperConstants.protocolVersion) / 辅助工具 \(remoteVersion.map(String.init) ?? "未连接")")
        row("最近错误", model.helper.lastError)

        section("状态")
        row("风扇模式", model.fans.mode.title)
        row("防休眠", model.keepAwake.isActive ? model.keepAwake.mode.title : "关闭")
        row("合盖运行", model.keepAwake.lidClosedActive ? "开启" : "关闭")
        row("登录时启动", model.launchAtLoginEnabled ? "开启" : "关闭")
        row("在线升级", "上次检查 \(model.updates.lastChecked.map { ISO8601DateFormatter().string(from: $0) } ?? "从未")，最新 \(model.updates.release?.version ?? "当前版本")")
        let geo = model.geo.installed.values.sorted { $0.edition < $1.edition }.map { "\($0.edition) \($0.build)" }
        row("归属地数据库", geo.isEmpty ? "未安装" : geo.joined(separator: "，"))

        section("设置")
        row("菜单栏项目", settings.orderedMenuBarItems.map(\.rawValue).joined(separator: ", "))
        row("菜单栏布局", settings.menuBarLayout.rawValue)
        row("菜单栏风格", settings.menuBarStyle.rawValue)
        row("刷新间隔", "\(settings.refreshSeconds) 秒")
        row("外观", settings.appearance.rawValue)
        row("连接探测", settings.probeEnabled ? "\(settings.probeTarget.rawValue)，\(settings.probeSeconds) 秒，后台\(settings.probeInBackground ? "开启" : "关闭")" : "关闭")
        row("公网 IP 查询", settings.publicIPLookup ? "开启" : "关闭")
        row("风扇安全温度", "\(settings.fanSafetyTemperature)°C")
        row("合盖电量下限", "\(settings.lidModeBatteryFloor)%")
        return lines.joined(separator: "\n") + "\n"
    }

    nonisolated static func writeArchive(summary: String, to destination: URL) throws {
        let manager = FileManager.default
        let work = manager.temporaryDirectory.appendingPathComponent("OpenStats-diagnostics-\(UUID().uuidString)")
        let folder = work.appendingPathComponent("OpenStats-诊断-\(fileDate())")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: work) }

        try summary.write(to: folder.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)

        // 统一日志：应用与辅助工具最近 3 天的记录
        let log = run("/usr/bin/log", ["show", "--style", "compact", "--last", "3d", "--info",
                                       "--predicate", "subsystem == \"\(Log.subsystem)\" OR subsystem == \"com.openstats.helper\""])
        try redact(log).write(to: folder.appendingPathComponent("openstats.log"), atomically: true, encoding: .utf8)

        let home = URL(fileURLWithPath: NSHomeDirectory())
        let cleanup = home.appendingPathComponent("Library/Logs/OpenStats/cleanup.log")
        if let text = try? String(contentsOf: cleanup, encoding: .utf8) {
            let recent = text.split(separator: "\n").suffix(500).joined(separator: "\n")
            try redact(recent).write(to: folder.appendingPathComponent("cleanup.log"), atomically: true, encoding: .utf8)
        }

        // 最近 5 份崩溃 / 卡死报告
        let reports = home.appendingPathComponent("Library/Logs/DiagnosticReports")
        let crashes = ((try? manager.contentsOfDirectory(at: reports, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("OpenStats") }
            .sorted { modified($0) > modified($1) }
            .prefix(5)
        if !crashes.isEmpty {
            let crashFolder = folder.appendingPathComponent("crashes")
            try manager.createDirectory(at: crashFolder, withIntermediateDirectories: true)
            for crash in crashes {
                try? manager.copyItem(at: crash, to: crashFolder.appendingPathComponent(crash.lastPathComponent))
            }
        }

        try? manager.removeItem(at: destination)
        let zip = run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, destination.path])
        guard manager.fileExists(atPath: destination.path) else {
            throw NSError(domain: "OpenStats", code: 1, userInfo: [NSLocalizedDescriptionKey: zip])
        }
    }

    /// 去掉用户目录名、IPv4 / IPv6 地址与硬件地址
    nonisolated static func redact(_ text: String) -> String {
        var result = text.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        // 顺序有关：硬件地址先于 IPv6；IPv6 至少 4 段或含 “::”，避免把 12:30:45 这样的时间当成地址
        let patterns: [(String, String)] = [
            (#"\b(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b"#, "<MAC>"),
            (#"\b(?:[0-9a-fA-F]{1,4}:){3,7}[0-9a-fA-F]{1,4}\b"#, "<IPv6>"),
            (#"(?:\b[0-9a-fA-F]{1,4})?(?::[0-9a-fA-F]{1,4})*::(?:[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{1,4})*\b)?"#, "<IPv6>"),
            (#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, "<IPv4>"),
        ]
        for (pattern, replacement) in patterns {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return result
    }

    nonisolated private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    nonisolated private static func fileDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    nonisolated private static func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return error.localizedDescription }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// AppController 启动时读取一次，记下应用启动时间
    static let launchDate = Date()
}
