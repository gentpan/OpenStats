import Foundation
import HelperShared
import Metrics
import Observation

/// 刷新 DNS、释放内存：已安装辅助工具时直接执行，否则弹出系统管理员授权
@MainActor
@Observable
public final class MaintenanceController {
    public struct Outcome: Equatable {
        let text: String
        let isError: Bool
    }

    public private(set) var running: MaintenanceCommand?
    public private(set) var outcomes: [MaintenanceCommand: Outcome] = [:]

    @ObservationIgnored private let helper: HelperClient

    init(helper: HelperClient) {
        self.helper = helper
    }

    func run(_ command: MaintenanceCommand) async {
        guard running == nil else { return }
        running = command
        defer { running = nil }

        let before = MemorySampler().sample()
        helper.refreshStatus()
        let error = helper.isReady ? await helper.run(command) : await Self.runWithAdministratorPrompt(command)

        if let error {
            outcomes[command] = Outcome(text: error, isError: error != Self.cancelled)
            return
        }
        switch command {
        case .flushDNS:
            outcomes[command] = Outcome(text: "DNS 缓存已刷新", isError: false)
        case .purgeMemory:
            let after = MemorySampler().sample()
            let freed = (before?.cached ?? 0) > (after?.cached ?? 0) ? before!.cached - after!.cached : 0
            outcomes[command] = Outcome(text: freed > 0 ? "已释放 \(Format.bytes(freed)) 缓存内存" : "内存已整理", isError: false)
        }
    }

    nonisolated private static let cancelled = "已取消"

    /// 未安装辅助工具时的回退：通过 AppleScript 请求一次性管理员授权，执行固定命令
    private static func runWithAdministratorPrompt(_ command: MaintenanceCommand) async -> String? {
        let prompt = command == .flushDNS ? "OpenStats 需要管理员权限来刷新 DNS 缓存。" : "OpenStats 需要管理员权限来释放内存。"
        let script = "do shell script \"\(command.shellCommand)\" with administrator privileges with prompt \"\(prompt)\""
        return await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = Pipe()
            do {
                try process.run()
            } catch {
                return error.localizedDescription
            }
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus != 0 else { return nil }
            let message = String(decoding: data, as: UTF8.self)
            // -128：用户在授权对话框中点了取消
            return message.contains("-128") ? cancelled : message.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}
