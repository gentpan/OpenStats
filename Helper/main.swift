//
//  OpenStatsHelper
//
//  以 root 运行的辅助工具，由 SMAppService.daemon 注册。
//  只做三件事：设置风扇转速、切换“合盖不睡眠”、在客户端断开时恢复默认。
//

import Foundation
import HelperShared
import SMC

final class HelperService: NSObject, NSXPCListenerDelegate, OpenStatsHelperProtocol, @unchecked Sendable {
    /// 所有可变状态只在该队列上访问
    private let queue = DispatchQueue(label: "com.openstats.helper.state")
    private let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
    private let stateURL = URL(fileURLWithPath: "/Library/Application Support/OpenStats/helper-state.plist")
    private let idleTimeout: TimeInterval = 30

    private var connections: Set<ObjectIdentifier> = []
    private var fans: FanControl?
    private var manualFans: Set<Int> = []
    private var sleepDisabledByHelper = false
    private var idleExit: DispatchWorkItem?

    func run() {
        queue.sync {
            fans = (try? SMCConnection()).map(FanControl.init)
            recoverFromPreviousRun()
            scheduleIdleExit()
        }
        listener.delegate = self
        listener.resume()
        dispatchMain()
    }

    // MARK: NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // 系统在收到消息前校验调用方签名，不符合要求的连接会被直接失效
        connection.setCodeSigningRequirement(HelperConstants.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: OpenStatsHelperProtocol.self)
        connection.exportedObject = self

        let id = ObjectIdentifier(connection)
        connection.invalidationHandler = { [weak self] in
            guard let self else { return }
            self.queue.async { self.connectionClosed(id) }
        }
        queue.sync {
            connections.insert(id)
            idleExit?.cancel()
        }
        connection.resume()
        return true
    }

    // MARK: OpenStatsHelperProtocol

    func protocolVersion(reply: @escaping @Sendable (Int) -> Void) {
        reply(HelperConstants.protocolVersion)
    }

    func setFanTarget(fan: Int, rpm: Double, reply: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            guard let fans else { return reply("无法访问 SMC") }
            guard (0..<fans.fanCount).contains(fan), rpm.isFinite, rpm > 0 else { return reply("无效的风扇参数") }
            do {
                try fans.setManual(fan: fan, rpm: rpm)
                manualFans.insert(fan)
                reply(nil)
            } catch {
                reply("设置风扇失败：\(error)")
            }
        }
    }

    func setFanAutomatic(fan: Int, reply: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            guard let fans else { return reply("无法访问 SMC") }
            guard (0..<fans.fanCount).contains(fan) else { return reply("无效的风扇编号") }
            do {
                try fans.setAutomatic(fan: fan)
                manualFans.remove(fan)
                reply(nil)
            } catch {
                reply("恢复风扇失败：\(error)")
            }
        }
    }

    func resetAllFans(reply: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            reply(resetFans())
        }
    }

    func setSleepDisabled(_ disabled: Bool, reply: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            reply(applySleepDisabled(disabled))
        }
    }

    func sleepDisabled(reply: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            reply(currentSleepDisabled())
        }
    }

    // MARK: 状态恢复

    private func connectionClosed(_ id: ObjectIdentifier) {
        connections.remove(id)
        guard connections.isEmpty else { return }
        // 应用已退出或崩溃：把系统恢复到默认状态
        _ = resetFans()
        if sleepDisabledByHelper { _ = applySleepDisabled(false) }
        scheduleIdleExit()
    }

    private func recoverFromPreviousRun() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? PropertyListDecoder().decode(PersistedState.self, from: data) else { return }
        if state.sleepDisabled {
            sleepDisabledByHelper = true
            _ = applySleepDisabled(false)
        }
        if state.fansOverridden { _ = resetFans() }
    }

    private func scheduleIdleExit() {
        idleExit?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.connections.isEmpty else { return }
            exit(0)
        }
        idleExit = work
        queue.asyncAfter(deadline: .now() + idleTimeout, execute: work)
    }

    // MARK: 风扇

    private func resetFans() -> String? {
        guard let fans else { return manualFans.isEmpty ? nil : "无法访问 SMC" }
        do {
            try fans.resetAll()
            manualFans.removeAll()
            persist()
            return nil
        } catch {
            return "恢复风扇失败：\(error)"
        }
    }

    // MARK: 睡眠

    private func applySleepDisabled(_ disabled: Bool) -> String? {
        let result = runPmset(["-a", "disablesleep", disabled ? "1" : "0"])
        guard result.status == 0 else {
            return "pmset 执行失败：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        sleepDisabledByHelper = disabled
        persist()
        return nil
    }

    private func currentSleepDisabled() -> Bool {
        let output = runPmset(["-g"]).output
        return output.split(separator: "\n").contains { line in
            let parts = line.split(whereSeparator: \.isWhitespace)
            return parts.first == "SleepDisabled" && parts.last == "1"
        }
    }

    private func runPmset(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // MARK: 持久化

    private struct PersistedState: Codable {
        var sleepDisabled: Bool
        var fansOverridden: Bool
    }

    private func persist() {
        let state = PersistedState(sleepDisabled: sleepDisabledByHelper, fansOverridden: !manualFans.isEmpty)
        guard state.sleepDisabled || state.fansOverridden else {
            try? FileManager.default.removeItem(at: stateURL)
            return
        }
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? PropertyListEncoder().encode(state).write(to: stateURL, options: .atomic)
    }
}

HelperService().run()
