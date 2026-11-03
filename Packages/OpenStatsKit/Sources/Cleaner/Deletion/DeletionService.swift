import Foundation
import Localization

public enum DeletionMode: String, Sendable {
    /// 移到废纸篓，可以放回原处
    case trash
    /// 直接删除，只用于可以重新生成的缓存与日志
    case permanent
}

/// 移到废纸篓走哪条路：`interactive` 可能弹出管理员授权（例如 root 拥有的应用），由界面层提供
public enum TrashRoute: Sendable {
    case standard
    case interactive
}

public struct DeletionRequest: Sendable, Identifiable {
    public var id: String { url.path }
    public let url: URL
    public let mode: DeletionMode
    /// 这次删除信任的根：从它往下的每一层都必须是真实目录项
    public let base: URL
    public let size: UInt64
    /// 写进日志的来源，例如规则编号或“uninstall:<bundle id>:<类别>”
    public let label: String
    /// 扫描时记下的身份；删除前对不上就放弃
    public var identity: FileIdentity?
    public var guardApps: [GuardApp] = []
    /// 条目名是反向域名时，对应应用在运行就跳过
    public var checksOwnerApp = false
    /// 最近修改过的视为正在使用
    public var minimumAge: TimeInterval = 0
    public var route: TrashRoute = .standard

    public init(url: URL, mode: DeletionMode, base: URL, size: UInt64 = 0, label: String,
                identity: FileIdentity? = nil, guardApps: [GuardApp] = [], checksOwnerApp: Bool = false,
                minimumAge: TimeInterval = 0, route: TrashRoute = .standard) {
        self.url = url
        self.mode = mode
        self.base = base
        self.size = size
        self.label = label
        self.identity = identity
        self.guardApps = guardApps
        self.checksOwnerApp = checksOwnerApp
        self.minimumAge = minimumAge
        self.route = route
    }
}

public enum DeletionBlock: Sendable, Equatable, CustomStringConvertible {
    case policy(PathPolicyError)
    /// 调用方自己的范围校验没通过（清理规则的允许目录、卸载计划里的候选）
    case scope(String)
    case missing
    case identityChanged
    case appRunning(String)
    case activityUnknown
    case recentlyModified

    /// 写进日志的固定原因码
    public var code: String {
        switch self {
        case .policy(let error): error.code
        case .scope: "out-of-scope"
        case .missing: "missing"
        case .identityChanged: "identity-changed"
        case .appRunning: "app-running"
        case .activityUnknown: "activity-unknown"
        case .recentlyModified: "recently-modified"
        }
    }

    public var description: String {
        switch self {
        case .policy(let error): error.description
        case .scope(let message): message
        case .missing: tr("已经不存在")
        case .identityChanged: tr("路径在扫描之后被替换，请重新扫描")
        case .appRunning(let name): tr("\(name) 正在运行")
        case .activityUnknown: tr("无法确认相关应用是否在运行")
        case .recentlyModified: tr("刚刚被使用")
        }
    }
}

public enum DeletionOutcome: Sendable, Equatable {
    case removed(trashedTo: URL?)
    /// 预览：判断都通过了，真正执行时会处理它
    case wouldRemove
    case blocked(DeletionBlock)
    case failed(String)

    public var isRemoved: Bool {
        if case .removed = self { return true }
        return false
    }
}

/// 给只要一个“成功或抛错”结果的调用方（单个文件的操作）
public enum DeletionError: Error, LocalizedError, Sendable {
    case blocked(DeletionBlock)
    case failed(String)
    /// 列表是扫描时的结果，文件之后又变了
    case staleScan

    public var errorDescription: String? {
        switch self {
        case .blocked(let block): block.description
        case .failed(let message): message
        case .staleScan: tr("文件在扫描之后被改过，请重新扫描")
        }
    }
}

public struct DeletionResult: Sendable {
    public let request: DeletionRequest
    public let outcome: DeletionOutcome
}

/// 所有用户数据的删除只能经过这里。判断顺序固定：通用路径策略 → 调用方的范围 → 是否还在 → 身份是否一致
/// → 相关应用是否在运行 → 是否刚被改过 → 才动手。预览（`plan`）与执行（`execute`）调用的是同一个 `evaluate`，
/// 所以预览不会承诺真实执行会拒绝的事。
public struct DeletionService: Sendable {
    public typealias Scope = @Sendable (URL) throws -> Void

    public let policy: PathPolicy
    private let scope: Scope
    private let running: @Sendable () -> RunningApps
    private let now: @Sendable () -> Date
    private let standardTrasher: any Trasher
    private let interactiveTrasher: any Trasher
    private let log: CleanLog?

    public init(home: String = NSHomeDirectory(),
                scope: @escaping Scope,
                running: @escaping @Sendable () -> RunningApps,
                now: @escaping @Sendable () -> Date = Date.init,
                standardTrasher: any Trasher = FileManagerTrasher(),
                interactiveTrasher: (any Trasher)? = nil,
                log: CleanLog? = CleanLog()) {
        policy = PathPolicy(home: home)
        self.scope = scope
        self.running = running
        self.now = now
        self.standardTrasher = standardTrasher
        self.interactiveTrasher = interactiveTrasher ?? standardTrasher
        self.log = log
    }

    // MARK: 判断

    /// 只判断，不动文件。nil 表示可以处理
    public func evaluate(_ request: DeletionRequest) -> DeletionBlock? {
        do {
            try policy.validate(request.url, base: request.base)
        } catch let error as PathPolicyError {
            return .policy(error)
        } catch {
            return .scope(Self.message(for: error))
        }
        // 不存在要先于范围校验：范围校验对不存在的路径会说“不在可卸载的位置”，那会误导
        guard let current = FileIdentity.capture(request.url) else { return .missing }
        do {
            try scope(request.url)
        } catch {
            return .scope(Self.message(for: error))
        }
        // 没有扫描时的身份就无从判断是不是同一个东西：不放行
        guard let expected = request.identity, expected.isStillTheSame(as: current) else { return .identityChanged }

        if !request.guardApps.isEmpty || request.checksOwnerApp {
            switch running() {
            case .unknown:
                return .activityUnknown
            case .known(let apps):
                if let app = request.guardApps.first(where: { apps.contains($0.bundleID) }) { return .appRunning(app.name) }
                if request.checksOwnerApp,
                   let owner = owningRunningApp(ofEntryNamed: request.url.lastPathComponent, running: apps) {
                    return .appRunning(owner)
                }
            }
        }

        if request.minimumAge > 0,
           let modified = FileIdentity.modificationDate(of: request.url.path),
           now().timeIntervalSince(modified) < request.minimumAge {
            return .recentlyModified
        }
        return nil
    }

    /// 调用方范围校验抛出的错误的可读说明：优先用本地化描述（枚举的 String(describing:) 只会给出 case 名）
    static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    /// 预览：每一项要么“会处理”，要么说明为什么不会
    public func plan(_ requests: [DeletionRequest]) -> [DeletionResult] {
        requests.map { request in
            DeletionResult(request: request, outcome: evaluate(request).map { .blocked($0) } ?? .wouldRemove)
        }
    }

    // MARK: 执行

    /// 逐项执行，每一项动手前都重新判断一次（扫描到执行之间状态可能变了）。被取消就停在当前位置，返回已处理的部分
    public func execute(_ requests: [DeletionRequest]) async -> [DeletionResult] {
        let run = String(UUID().uuidString.prefix(8))
        var results: [DeletionResult] = []
        for request in requests {
            if Task.isCancelled { break }
            let outcome: DeletionOutcome
            if let block = evaluate(request) {
                outcome = .blocked(block)
            } else {
                outcome = await remove(request)
            }
            log?.record(request: request, outcome: outcome, run: run)
            results.append(DeletionResult(request: request, outcome: outcome))
        }
        return results
    }

    private func remove(_ request: DeletionRequest) async -> DeletionOutcome {
        do {
            switch request.mode {
            case .trash:
                let trasher = request.route == .interactive ? interactiveTrasher : standardTrasher
                return .removed(trashedTo: try await trasher.trash(request.url))
            case .permanent:
                try FileManager.default.removeItem(at: request.url) // SAFE: 这是删除入口里唯一的永久删除调用点，之前已通过全部判断
                return .removed(trashedTo: nil)
            }
        } catch {
            // 移到废纸篓失败就是失败，不会改成永久删除
            return .failed(error.localizedDescription)
        }
    }
}
