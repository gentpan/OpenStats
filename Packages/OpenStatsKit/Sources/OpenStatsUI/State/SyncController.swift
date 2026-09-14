import AccountSync
import AppKit
import AuthenticationServices
import Foundation
import Localization
import Observation

/// 账号与设置同步：用系统的登录窗口走 GitHub / Google / Apple 授权，令牌存钥匙串；
/// 设置一变就在 2 秒后整份推送，启动、唤醒与每 15 分钟拉一次。云端以最后写入为准，
/// 只有第一次登录且两边都有内容时让用户选一次
@MainActor
@Observable
public final class SyncController {
    public enum Phase: Equatable {
        case idle
        case signingIn
        case syncing
        case failed(String)
    }

    /// 首次登录时本机与云端设置不同，等用户选择
    public struct Conflict: Equatable {
        public let remoteUpdatedAt: Date
        public let remoteDevice: String?
    }

    public private(set) var phase: Phase = .idle
    public private(set) var user: SyncUser? {
        didSet { defaults.set(user.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.user) }
    }
    public private(set) var lastSyncedAt: Date? {
        didSet { defaults.set(lastSyncedAt, forKey: Keys.lastSyncedAt) }
    }
    public private(set) var conflict: Conflict?
    /// 服务器上配置好的登录方式；取不到时全部显示
    public private(set) var providers: [SyncProvider] = SyncProvider.allCases

    public var isSignedIn: Bool { token != nil && user != nil }

    /// 登录窗口挂在哪个窗口上，由 AppController 提供主窗口
    @ObservationIgnored var presentationAnchor: @MainActor () -> NSWindow? = { nil }

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let client: SyncClient
    @ObservationIgnored private let tokens: TokenStore
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var lastSyncedVersion: Int {
        didSet { defaults.set(lastSyncedVersion, forKey: Keys.lastSyncedVersion) }
    }
    /// 上次推送或套用过的文档：本机再次读到同样的内容就不用推，也用来识别套用云端设置引起的回声
    @ObservationIgnored private var lastKnownDocument: SettingsDocument? {
        didSet { defaults.set(lastKnownDocument.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.lastKnownDocument) }
    }
    @ObservationIgnored private var pendingRemote: RemoteSettings<SettingsDocument>?
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var pullTask: Task<Void, Never>?
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private var anchorProvider: AnchorProvider?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observing = false

    static let pushDelay: Duration = .seconds(2)
    static let pullInterval: TimeInterval = 15 * 60

    init(settings: AppSettings, defaults: UserDefaults = .standard, client: SyncClient = SyncClient(), tokens: TokenStore = KeychainTokenStore()) {
        self.settings = settings
        self.defaults = defaults
        self.client = client
        self.tokens = tokens
        user = defaults.data(forKey: Keys.user).flatMap { try? JSONDecoder().decode(SyncUser.self, from: $0) }
        lastSyncedAt = defaults.object(forKey: Keys.lastSyncedAt) as? Date
        lastSyncedVersion = defaults.integer(forKey: Keys.lastSyncedVersion)
        lastKnownDocument = defaults.data(forKey: Keys.lastKnownDocument).flatMap { try? JSONDecoder().decode(SettingsDocument.self, from: $0) }
    }

    /// 启动时调用：已登录就开始观察设置并补一次同步
    public func start() {
        token = tokens.read()
        guard let token else {
            if user != nil { clearLocalSession() }
            return
        }
        if user == nil {
            Task { [weak self] in
                guard let self, let fetched = try? await self.client.me(token: token) else { return }
                self.user = fetched
                self.start()
            }
            return
        }
        beginObserving()
        if lastKnownDocument != settings.exportDocument() {
            schedulePush()
        } else {
            pullSoon()
        }
    }

    /// 账号页打开时：未登录就刷新可用的登录方式，已登录就拉一次
    func pageOpened() {
        if isSignedIn {
            pullSoon()
        } else {
            Task { [weak self] in
                guard let self, let fetched = try? await self.client.providers(), !fetched.isEmpty else { return }
                self.providers = fetched
            }
        }
    }

    // MARK: 登录

    public func signIn(with provider: SyncProvider) {
        guard phase != .signingIn else { return }
        let verifier = PKCE.verifier()
        let url = client.loginURL(provider: provider, challenge: PKCE.challenge(for: verifier))
        let anchor = AnchorProvider(anchor: presentationAnchor)
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: SyncClient.callbackScheme) { [weak self] callback, error in
            Task { @MainActor in self?.finishSignIn(callback: callback, error: error, verifier: verifier) }
        }
        session.presentationContextProvider = anchor
        // 保留浏览器里已登录的第三方账号，用户不必再输一次密码
        session.prefersEphemeralWebBrowserSession = false
        anchorProvider = anchor
        authSession = session
        phase = .signingIn
        Log.sync.notice("开始登录：\(provider.rawValue, privacy: .public)")
        if !session.start() {
            phase = .failed(tr("无法打开登录窗口"))
            authSession = nil
        }
    }

    public func cancelSignIn() {
        authSession?.cancel()
        authSession = nil
        if phase == .signingIn { phase = .idle }
    }

    private func finishSignIn(callback: URL?, error: Error?, verifier: String) {
        authSession = nil
        anchorProvider = nil
        if let error {
            let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
            phase = cancelled ? .idle : .failed(error.localizedDescription)
            return
        }
        guard let callback else {
            phase = .failed(SyncError.invalidCallback.localizedDescription)
            return
        }
        switch SyncClient.parseCallback(callback) {
        case .failure(.cancelled):
            phase = .idle
        case .failure(let error):
            phase = .failed(error.localizedDescription)
        case .success(let code):
            Task { await exchange(code: code, verifier: verifier) }
        }
    }

    private func exchange(code: String, verifier: String) async {
        do {
            let session = try await client.exchange(code: code, verifier: verifier, device: Self.deviceName)
            try tokens.write(session.token)
            token = session.token
            user = session.user
            lastSyncedVersion = 0
            lastKnownDocument = nil
            conflict = nil
            phase = .idle
            Log.sync.notice("登录成功：\(session.user.providers.joined(separator: ","), privacy: .public)")
            beginObserving()
            await reconcileAfterSignIn()
        } catch {
            Log.sync.error("登录失败：\(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// 第一次登录：云端没有就上传；本机还是出厂设置就直接用云端；两边都有且不同就问用户
    private func reconcileAfterSignIn() async {
        guard let token else { return }
        phase = .syncing
        do {
            let local = settings.exportDocument()
            guard let remote = try await client.fetchSettings(token: token, as: SettingsDocument.self) else {
                phase = .idle
                await push()
                return
            }
            if remote.document == local || local == AppSettings.defaultDocument() {
                applyRemote(remote)
            } else {
                pendingRemote = remote
                conflict = Conflict(remoteUpdatedAt: remote.updatedAt, remoteDevice: remote.device)
            }
            phase = .idle
        } catch {
            handle(error)
        }
    }

    public func resolveConflict(useRemote: Bool) {
        guard conflict != nil else { return }
        conflict = nil
        if useRemote, let remote = pendingRemote {
            applyRemote(remote)
        } else {
            Task { await push() }
        }
        pendingRemote = nil
    }

    // MARK: 退出

    public func signOut() {
        if let token {
            Task { [client] in try? await client.logout(token: token) }
        }
        clearLocalSession()
        Log.sync.notice("已退出登录")
    }

    public func deleteAccount() {
        guard let token else { return }
        phase = .syncing
        Task {
            do {
                try await client.deleteAccount(token: token)
                clearLocalSession()
                Log.sync.notice("已删除云端账号")
            } catch {
                handle(error)
            }
        }
    }

    private func clearLocalSession() {
        pushTask?.cancel()
        pullTask?.cancel()
        pushTask = nil
        pullTask = nil
        timer?.invalidate()
        timer = nil
        tokens.delete()
        token = nil
        user = nil
        conflict = nil
        pendingRemote = nil
        lastSyncedAt = nil
        lastSyncedVersion = 0
        lastKnownDocument = nil
        observing = false
        phase = .idle
    }

    // MARK: 同步

    /// 用户点“立即同步”：有本机改动就推，否则拉
    public func syncNow() {
        guard isSignedIn, conflict == nil else { return }
        if lastKnownDocument != settings.exportDocument() {
            pushTask?.cancel()
            pushTask = nil
            Task { await push() }
        } else {
            pullTask?.cancel()
            pullTask = nil
            Task { await pull() }
        }
    }

    /// 唤醒或打开账号页时稍后拉一次，合并短时间内的多次触发
    func pullSoon() {
        guard isSignedIn, pullTask == nil else { return }
        pullTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            self.pullTask = nil
            await self.pull()
        }
    }

    private func beginObserving() {
        guard !observing else { return }
        observing = true
        observeSettings()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pullInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pullSoon() }
        }
        timer?.tolerance = 60
    }

    private func observeSettings() {
        guard observing else { return }
        withObservationTracking {
            _ = settings.exportDocument()
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.observing else { return }
                self.schedulePush()
                self.observeSettings()
            }
        }
    }

    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.pushDelay)
            guard let self, !Task.isCancelled else { return }
            self.pushTask = nil
            await self.push()
        }
    }

    private func push() async {
        guard let token, conflict == nil else { return }
        let document = settings.exportDocument()
        guard document != lastKnownDocument else { return }
        phase = .syncing
        do {
            let receipt = try await client.putSettings(token: token, document: document, device: Self.deviceName)
            lastKnownDocument = document
            lastSyncedVersion = receipt.version
            lastSyncedAt = receipt.updatedAt
            phase = .idle
            Log.sync.info("已上传设置，版本 \(receipt.version)")
        } catch {
            handle(error)
        }
    }

    private func pull() async {
        guard let token, conflict == nil, pushTask == nil else { return }
        do {
            guard let remote = try await client.fetchSettings(token: token, as: SettingsDocument.self) else { return }
            if remote.version != lastSyncedVersion {
                applyRemote(remote)
                Log.sync.info("已套用云端设置，版本 \(remote.version)")
            }
            if case .failed = phase { phase = .idle }
        } catch {
            handle(error)
        }
    }

    private func applyRemote(_ remote: RemoteSettings<SettingsDocument>) {
        // 先记下再套用：套用触发的观察回调会发现内容一致，不会再推回去
        lastKnownDocument = remote.document
        lastSyncedVersion = remote.version
        lastSyncedAt = remote.updatedAt
        settings.apply(remote.document)
        // 文档里不认识的值被跳过后本机内容可能与云端不完全一致，以本机实际内容为准避免反复推送
        lastKnownDocument = settings.exportDocument()
    }

    private func handle(_ error: Error) {
        if let syncError = error as? SyncError, syncError == .unauthorized {
            Log.sync.error("令牌已失效")
            clearLocalSession()
            phase = .failed(syncError.localizedDescription)
            return
        }
        Log.sync.error("同步失败：\(error.localizedDescription, privacy: .public)")
        phase = .failed(error.localizedDescription)
    }

    static var deviceName: String {
        Host.current().localizedName ?? "Mac"
    }

    private enum Keys {
        static let user = "syncUser"
        static let lastSyncedAt = "syncLastSyncedAt"
        static let lastSyncedVersion = "syncLastSyncedVersion"
        static let lastKnownDocument = "syncLastKnownDocument"
    }
}

/// 登录窗口需要一个挂靠的窗口：优先主窗口，其次当前主窗口
private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: @MainActor () -> NSWindow?

    init(anchor: @escaping @MainActor () -> NSWindow?) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            anchor() ?? NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) ?? NSWindow()
        }
    }
}
