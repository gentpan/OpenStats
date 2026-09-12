import Foundation
import HelperShared
import Observation
import ServiceManagement

/// 与 root 辅助工具的连接。安装通过 SMAppService.daemon，用户需在“登录项”中批准一次。
@MainActor
@Observable
public final class HelperClient {
    public enum Status: Equatable {
        case notInstalled
        case requiresApproval
        case enabled
        case unavailable(String)

        var title: String {
            switch self {
            case .notInstalled: "未安装"
            case .requiresApproval: "等待批准"
            case .enabled: "已启用"
            case .unavailable: "不可用"
            }
        }
    }

    public private(set) var status: Status = .notInstalled
    public private(set) var isWorking = false
    public private(set) var lastError: String?

    /// 连接中断后重新连上时回调，用于重新下发风扇 / 防休眠状态
    @ObservationIgnored var onReconnect: (() -> Void)?

    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private let service = SMAppService.daemon(plistName: HelperConstants.launchdPlistName)

    public init() {}

    public var isReady: Bool { status == .enabled }

    public func refreshStatus() {
        switch service.status {
        case .enabled: status = .enabled
        case .requiresApproval: status = .requiresApproval
        case .notRegistered: status = .notInstalled
        case .notFound:
            // 首次注册前系统同样返回 notFound，需结合包内文件判断
            let plist = Bundle.main.bundleURL
                .appendingPathComponent("Contents/Library/LaunchDaemons/\(HelperConstants.launchdPlistName)")
            status = FileManager.default.fileExists(atPath: plist.path)
                ? .notInstalled
                : .unavailable("应用包内未找到辅助工具，请使用完整构建的 OpenStats.app")
        @unknown default: status = .unavailable("未知状态")
        }
    }

    public func install() {
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        do {
            try service.register()
        } catch {
            lastError = "安装失败：\(error.localizedDescription)"
        }
        refreshStatus()
        if status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    public func uninstall() async {
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        connection?.invalidate()
        connection = nil
        do {
            // 使用回调版本：不把非 Sendable 的 SMAppService 跨隔离域传递
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                service.unregister { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        } catch {
            lastError = "卸载失败：\(error.localizedDescription)"
        }
        refreshStatus()
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: 远程调用

    func setFanTarget(fan: Int, rpm: Double) async -> String? {
        await call { proxy, reply in proxy.setFanTarget(fan: fan, rpm: rpm, reply: reply) }
    }

    func setFanAutomatic(fan: Int) async -> String? {
        await call { proxy, reply in proxy.setFanAutomatic(fan: fan, reply: reply) }
    }

    func resetAllFans() async -> String? {
        await call { proxy, reply in proxy.resetAllFans(reply: reply) }
    }

    func setSleepDisabled(_ disabled: Bool) async -> String? {
        await call { proxy, reply in proxy.setSleepDisabled(disabled, reply: reply) }
    }

    func run(_ command: MaintenanceCommand) async -> String? {
        switch command {
        case .flushDNS: await call { proxy, reply in proxy.flushDNSCache(reply: reply) }
        case .purgeMemory: await call { proxy, reply in proxy.purgeMemory(reply: reply) }
        }
    }

    /// 退出应用时使用：同步恢复风扇与睡眠设置，每步最多等待 1 秒
    func restoreDefaultsSynchronously() {
        guard isReady else { return }
        let connection = ensureConnection()
        let steps: [(OpenStatsHelperProtocol, @escaping @Sendable (String?) -> Void) -> Void] = [
            { proxy, reply in proxy.resetAllFans(reply: reply) },
            { proxy, reply in proxy.setSleepDisabled(false, reply: reply) },
        ]
        for step in steps {
            let semaphore = DispatchSemaphore(value: 0)
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in semaphore.signal() })
                    as? OpenStatsHelperProtocol else { return }
            step(proxy) { _ in semaphore.signal() }
            _ = semaphore.wait(timeout: .now() + 1)
        }
    }

    private func call(_ body: (OpenStatsHelperProtocol, @escaping @Sendable (String?) -> Void) -> Void) async -> String? {
        refreshStatus()
        guard isReady else { return "辅助工具未启用" }
        let connection = ensureConnection()
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let once = ResumeOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                once.resume("无法连接辅助工具：\(error.localizedDescription)")
            } as? OpenStatsHelperProtocol
            guard let proxy else {
                once.resume("无法连接辅助工具")
                return
            }
            body(proxy) { once.resume($0) }
        }
    }

    private func ensureConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: OpenStatsHelperProtocol.self)
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.onReconnect?() }
        }
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        connection.resume()
        self.connection = connection
        return connection
    }
}

/// XPC 的错误回调和正常回调可能都会触发，保证 continuation 只恢复一次
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: String?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
