import Foundation
import HelperShared
import Localization
import Observation
import ServiceManagement

/// 与 root 辅助工具的连接。辅助工具随应用一起提供：启动时自动通过 SMAppService.daemon 登记，
/// 用户只需在“登录项”中批准一次，界面里没有单独的安装 / 卸载入口。
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
            case .notInstalled: tr("未安装")
            case .requiresApproval: tr("等待批准")
            case .enabled: tr("已启用")
            case .unavailable: tr("不可用")
            }
        }
    }

    public private(set) var status: Status = .notInstalled
    public private(set) var isWorking = false
    public private(set) var lastError: String?
    /// 正在运行的辅助工具比应用旧：登记的是另一份应用包里的辅助工具，或替换应用后旧进程还没退出
    public private(set) var isOutdated = false

    /// 连接中断后重新连上时回调，用于重新下发风扇 / 防休眠状态
    @ObservationIgnored var onReconnect: (() -> Void)?

    /// 辅助工具正替应用保持着系统状态（风扇手动、合盖运行）。这期间连接必须一直开着：
    /// 辅助工具靠连接断开发现应用崩溃，替用户把风扇与睡眠恢复原样。默认按“保持着”处理，不会断开
    @ObservationIgnored var holdsSystemState: () -> Bool = { true }

    @ObservationIgnored private var connection: NSXPCConnection?
    /// 辅助工具报告的协议版本；够新才会在空闲时断开
    @ObservationIgnored private var remoteVersion: Int?
    @ObservationIgnored private var pendingCalls = 0
    @ObservationIgnored private var idleDisconnect: Task<Void, Never>?
    /// 最后一次调用结束后多久断开；辅助工具再空闲 30 秒自己退出，省下常驻的进程
    static let idleDisconnectDelay: Duration = .seconds(10)
    @ObservationIgnored private let service = SMAppService.daemon(plistName: HelperConstants.launchdPlistName)

    public init() {}

    public var isReady: Bool { status == .enabled }

    static var outdatedMessage: String { tr("辅助工具版本比应用旧，部分功能可能无法使用，请重新安装一次（需要管理员授权）。") }

    /// 未安装、待批准或版本过旧，需要用户处理
    var needsAttention: Bool { !isReady || isOutdated }

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
                : .unavailable(tr("应用包内未找到辅助工具，请使用完整构建的 OpenStats.app"))
        @unknown default: status = .unavailable(tr("未知状态"))
        }
    }

    /// 启动时调用：还没登记就自动登记。系统会自己发一条“已添加后台项目”的通知，这里不再主动打开系统设置
    public func installIfNeeded() {
        refreshStatus()
        guard status == .notInstalled else { return }
        install(opensSettings: false)
    }

    /// `opensSettings`：登记后需要用户批准时，顺手打开“登录项”设置（用户点按钮时为真）
    public func install(opensSettings: Bool = true) {
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        do {
            try service.register()
        } catch {
            lastError = tr("安装失败：\(error.localizedDescription)")
            Log.helper.error("安装失败：\(error.localizedDescription, privacy: .public)")
        }
        refreshStatus()
        if opensSettings, status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    /// 只在重新安装时用：先注销旧的登记
    private func uninstall() async {
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
            lastError = tr("卸载失败：\(error.localizedDescription)")
            Log.helper.error("卸载失败：\(error.localizedDescription, privacy: .public)")
        }
        refreshStatus()
    }

    /// 卸载后重新登记，让 launchd 运行当前应用包里的辅助工具
    public func reinstall() async {
        await uninstall()
        install()
        await verifyVersion(allowRestart: false)
    }

    /// 核对辅助工具的协议版本。版本旧通常是替换应用后旧的辅助工具进程还在运行（新应用一连上它就不会空闲退出）：
    /// 先断开连接让它空闲 30 秒后退出，再连接时 launchd 会启动应用包里的新版本；仍然旧才提示重新安装
    func verifyVersion(allowRestart: Bool = true) async {
        let remote = await remoteProtocolVersion()
        Log.helper.info("辅助工具状态 \(self.status.title, privacy: .public)，协议版本 \(remote.map(String.init) ?? "未连接", privacy: .public)")
        guard let version = remote, version < HelperConstants.protocolVersion else {
            isOutdated = false
            return
        }
        guard allowRestart else {
            isOutdated = true
            return
        }
        connection?.invalidate()
        connection = nil
        try? await Task.sleep(for: .seconds(40))
        guard let again = await remoteProtocolVersion() else { return }
        isOutdated = again < HelperConstants.protocolVersion
        if isOutdated {
            Log.helper.error("辅助工具协议版本 \(again) 低于应用的 \(HelperConstants.protocolVersion)")
        } else {
            // 新的辅助工具进程没有之前的风扇与睡眠设置，重新下发
            onReconnect?()
        }
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: 远程调用

    func setFanTarget(fan: Int, rpm: Double) async -> String? {
        await call { proxy, reply in proxy.setFanTarget(fan: fan, rpm: rpm, reply: reply) }
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

    func setDNSServers(service: String, servers: [String]) async -> String? {
        await call { proxy, reply in proxy.setDNSServers(service: service, servers: servers, reply: reply) }
    }

    func deleteLocalSnapshots(identifiers: [String]) async -> String? {
        await call { proxy, reply in proxy.deleteLocalSnapshots(identifiers: identifiers, reply: reply) }
    }

    /// 已安装的辅助工具的协议版本；旧版本不认识新增的方法，调用前先确认
    func remoteProtocolVersion() async -> Int? {
        refreshStatus()
        guard isReady else { return nil }
        let connection = ensureConnection()
        pendingCalls += 1
        defer {
            pendingCalls -= 1
            scheduleIdleDisconnect()
        }
        let version = await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            let once = ResumeOnceValue<Int?>(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in once.resume(nil) } as? OpenStatsHelperProtocol
            guard let proxy else { return once.resume(nil) }
            proxy.protocolVersion { once.resume($0) }
        }
        if let version { remoteVersion = version }
        return version
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
        guard isReady else { return tr("辅助工具未启用") }
        let connection = ensureConnection()
        pendingCalls += 1
        defer {
            pendingCalls -= 1
            scheduleIdleDisconnect()
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let once = ResumeOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                Log.helper.error("XPC 调用失败：\(error.localizedDescription, privacy: .public)")
                once.resume(tr("无法连接辅助工具：\(error.localizedDescription)"))
            } as? OpenStatsHelperProtocol
            guard let proxy else {
                once.resume(tr("无法连接辅助工具"))
                return
            }
            body(proxy) { once.resume($0) }
        }
    }

    private func ensureConnection() -> NSXPCConnection {
        idleDisconnect?.cancel()
        idleDisconnect = nil
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        let id = ObjectIdentifier(connection)
        connection.remoteObjectInterface = NSXPCInterface(with: OpenStatsHelperProtocol.self)
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.onReconnect?() }
        }
        // 只清掉自己：主动断开后可能已经又建了新连接，旧连接的回调不能把新的也丢掉
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                guard let self, let current = self.connection, ObjectIdentifier(current) == id else { return }
                self.connection = nil
            }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    /// 调用都结束、辅助工具没替应用保持任何系统状态时，过一会儿断开连接，让它空闲退出。
    /// 下次调用会重新连上，launchd 按需启动它
    private func scheduleIdleDisconnect() {
        idleDisconnect?.cancel()
        idleDisconnect = nil
        guard pendingCalls == 0, connection != nil,
              let remoteVersion, remoteVersion >= HelperConstants.idleDisconnectVersion else { return }
        idleDisconnect = Task { [weak self] in
            try? await Task.sleep(for: Self.idleDisconnectDelay)
            guard !Task.isCancelled, let self, self.pendingCalls == 0, !self.holdsSystemState(),
                  let connection = self.connection else { return }
            Log.helper.info("用不着辅助工具，断开连接")
            self.connection = nil
            connection.invalidate()
        }
    }
}

private typealias ResumeOnce = ResumeOnceValue<String?>

/// XPC 的错误回调和正常回调可能都会触发，保证 continuation 只恢复一次
private final class ResumeOnceValue<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Value) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
