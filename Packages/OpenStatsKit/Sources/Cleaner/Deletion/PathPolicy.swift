import Darwin
import Foundation
import Localization

public enum PathPolicyError: Error, Sendable, Equatable, CustomStringConvertible {
    case empty
    case notAbsolute
    case traversal
    case controlCharacter
    /// 系统目录、顶层目录本身，或用户凭据与同步数据所在的目录
    case critical(String)
    /// 目标本身是符号链接：删除只会处理真实的文件与目录，不处理链接
    case symlinkLeaf
    /// 从可信根往下，某一层是符号链接，或读不了
    case redirected(String)
    case outsideBase
    /// 不在允许删除的区域里（家目录、/Applications、用户缓存区）；/Library 等系统位置在这里就被拒绝
    case outsideZones

    public var code: String {
        switch self {
        case .empty: "empty"
        case .notAbsolute: "not-absolute"
        case .traversal: "traversal"
        case .controlCharacter: "control-character"
        case .critical: "critical-path"
        case .symlinkLeaf: "symlink"
        case .redirected: "redirected"
        case .outsideBase: "outside-base"
        case .outsideZones: "outside-zones"
        }
    }

    public var description: String {
        switch self {
        case .empty: tr("路径为空")
        case .notAbsolute: tr("不是绝对路径")
        case .traversal: tr("路径包含 ..")
        case .controlCharacter: tr("路径包含控制字符")
        case .critical(let name): tr("受保护的位置：\(name)")
        case .symlinkLeaf: tr("目标是符号链接")
        case .redirected(let detail): tr("路径经过符号链接或无法读取：\(detail)")
        case .outsideBase: tr("不在允许的范围内")
        case .outsideZones: tr("不在允许删除的区域内（家目录、应用程序文件夹之外）")
        }
    }
}

/// 所有删除共用的、与具体功能无关的路径策略。比各功能自己的范围校验更宽，只拦“无论如何都不能删”的东西：
/// 系统目录、顶层目录本身、用户的凭据与同步数据，以及任何借符号链接或大小写别名指向它们的路径。
/// 只会更严，不会因为解析了链接而放行原本不允许的路径。
public struct PathPolicy: Sendable {
    public let home: String

    /// 整棵子树都不能碰（目录本身及其中所有内容）
    private let trees: [String]
    /// 只有目录本身不能删，里面的子项由各功能自己的范围决定
    private let exacts: [String]
    /// 上面两组的小写形式，初始化时算好，免得每个候选都重复转换
    private let lowercasedTrees: [String]
    private let lowercasedExacts: [String]
    private let zones: [String]
    /// 上面两组里实际存在的目录的身份，用来抵御大小写别名（APFS 默认不区分大小写）与 firmlink
    private let treeIdentities: [Identity]
    private let exactIdentities: [Identity]

    private struct Identity: Sendable, Hashable {
        let device: Int64
        let inode: UInt64
    }

    static let systemTrees = [
        "/System", "/bin", "/sbin", "/usr", "/etc", "/private/etc", "/var/db", "/private/var/db", "/var/audit",
        "/private/var/audit", "/dev", "/cores", "/Library/Apple", "/Library/Extensions", "/Library/Keychains",
    ]

    /// 标准化会把 /private/var、/private/tmp、/private/etc 前缀去掉，所以两种写法都列
    static let systemExacts = [
        "/", "/Applications", "/Library", "/Library/Application Support", "/Library/Preferences", "/Library/Caches",
        "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools", "/Library/Logs",
        "/Users", "/Users/Shared", "/Volumes", "/opt", "/opt/homebrew", "/private", "/private/tmp", "/private/var",
        "/private/var/tmp", "/private/var/folders", "/private/var/root", "/var", "/var/tmp", "/var/folders", "/var/root",
        "/tmp", "/home", "/net", "/Network",
    ]

    /// 允许删除的区域：家目录、应用程序文件夹、用户缓存区（/var/folders）。其余位置（/Library、/Users/Shared 等）
    /// 一律拒绝：系统级残留只预览，这里不会让它们进到删除里
    private static let systemZones = ["/Applications", "/var/folders", "/private/var/folders"]

    /// 相对家目录
    static let homeTrees = [
        ".ssh", ".gnupg", "Library/Keychains", "Library/Mobile Documents", "Library/Accounts", "Library/Mail",
        "Library/Calendars", "Library/Messages",
    ]

    static let homeExacts = [
        "", ".Trash", ".config", ".cache", ".local", ".local/share", ".local/state", ".local/bin",
        "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Applications",
        "Library", "Library/Application Support", "Library/Caches", "Library/Containers", "Library/Group Containers",
        "Library/Preferences", "Library/Preferences/ByHost", "Library/Logs", "Library/Saved Application State",
        "Library/LaunchAgents", "Library/Application Scripts", "Library/WebKit", "Library/HTTPStorages",
        "Library/Cookies", "Library/Developer", "Library/Fonts", "Library/Frameworks", "Library/Internet Plug-Ins",
        "Library/Audio", "Library/Input Methods", "Library/Services", "Library/Screen Savers",
        "Library/PreferencePanes", "Library/QuickLook", "Library/Spotlight", "Library/ColorPickers",
    ]

    public init(home: String = NSHomeDirectory()) {
        self.init(home: home, additionalTrees: [])
    }

    /// 测试用：额外加入受保护的子树
    init(home: String, additionalTrees: [String]) {
        let standardized = URL(fileURLWithPath: home).standardizedFileURL.path
        self.home = standardized
        let homeTrees = Self.homeTrees.map { standardized + "/" + $0 }
        let homeExacts = Self.homeExacts.map { $0.isEmpty ? standardized : standardized + "/" + $0 }
        trees = Self.systemTrees + homeTrees + additionalTrees
        exacts = Self.systemExacts + homeExacts
        lowercasedTrees = trees.map { $0.lowercased() }
        lowercasedExacts = exacts.map { $0.lowercased() }
        zones = ([standardized] + Self.systemZones).map { $0.lowercased() }
        treeIdentities = Self.identities(of: trees)
        exactIdentities = Self.identities(of: exacts)
    }

    private static func identities(of paths: [String]) -> [Identity] {
        paths.compactMap { path in
            FileIdentity.resolvedStatus(of: path).map { Identity(device: $0.device, inode: $0.inode) }
        }
    }

    /// 通过时什么都不返回；不通过时抛出具体原因。`base` 是这次删除信任的根（例如家目录）：
    /// 从它往下的每一层都必须是真实目录项，不能经过符号链接。
    public func validate(_ url: URL, base: URL) throws {
        let raw = url.path
        guard !raw.isEmpty else { throw PathPolicyError.empty }
        guard raw.hasPrefix("/") else { throw PathPolicyError.notAbsolute }
        guard !url.pathComponents.contains("..") else { throw PathPolicyError.traversal }
        guard !raw.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw PathPolicyError.controlCharacter
        }

        let path = url.standardizedFileURL.path
        if let name = criticalName(for: path) { throw PathPolicyError.critical(name) }
        try checkChain(path: path, base: base)
        if let name = criticalNameByIdentity(for: path) { throw PathPolicyError.critical(name) }
        guard isInsideAllowedZone(path) else { throw PathPolicyError.outsideZones }

        // 解析链接后再查一次（含 base 以上的系统别名）：只会更严
        let physical = url.resolvingSymlinksInPath().standardizedFileURL.path
        if physical != path, let name = criticalName(for: physical) { throw PathPolicyError.critical(name) }
    }

    // MARK: 字面匹配

    private static let dataVolumePrefix = "/System/Volumes/Data"

    /// 命中的受保护位置名；大小写不敏感（APFS 默认如此，宁可多拦）
    func criticalName(for path: String) -> String? {
        var candidates = [path]
        // /System/Volumes/Data/Users/x 与 /Users/x 是同一个地方
        if path.hasPrefix(Self.dataVolumePrefix + "/") {
            candidates.append(String(path.dropFirst(Self.dataVolumePrefix.count)))
        }
        for candidate in candidates {
            let lowered = candidate.lowercased()
            if let index = lowercasedTrees.firstIndex(where: { lowered == $0 || lowered.hasPrefix($0 + "/") }) {
                return trees[index]
            }
            if let index = lowercasedExacts.firstIndex(where: { lowered == $0 }) { return exacts[index] }
        }
        return nil
    }

    private func isInsideAllowedZone(_ path: String) -> Bool {
        let lowered = path.lowercased()
        return zones.contains { lowered == $0 || lowered.hasPrefix($0 + "/") }
    }

    // MARK: 同一性匹配

    /// 路径本身或它的任一层父目录，与某个受保护目录是同一个文件系统对象
    private func criticalNameByIdentity(for path: String) -> String? {
        var current = path
        var isLeaf = true
        while true {
            if let status = FileIdentity.resolvedStatus(of: current) {
                let identity = Identity(device: status.device, inode: status.inode)
                if treeIdentities.contains(identity) { return current }
                if isLeaf, exactIdentities.contains(identity) { return current }
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent.isEmpty { return nil }
            current = parent
            isLeaf = false
        }
    }

    // MARK: 链接检查

    private func checkChain(path: String, base: URL) throws {
        let supplied = base.standardizedFileURL.path
        let resolved = base.resolvingSymlinksInPath().standardizedFileURL.path
        func contains(_ root: String) -> Bool {
            root == "/" ? true : path == root || path.hasPrefix(root + "/")
        }
        guard let root = [supplied, resolved].first(where: contains) else { throw PathPolicyError.outsideBase }
        let remainder = path == root ? "" : String(path.dropFirst(root == "/" ? 1 : root.count))
        let components = remainder.split(separator: "/")

        // 目标就是 base 本身：base 是被信任的根，但目标不能是个符号链接
        if components.isEmpty {
            if let status = FileIdentity.status(of: path), status.isSymbolicLink { throw PathPolicyError.symlinkLeaf }
            return
        }
        var current = root == "/" ? "" : root
        for (index, component) in components.enumerated() {
            current += "/" + component
            guard let status = FileIdentity.status(of: current) else {
                // 不存在由调用方另行处理；其他读取失败视为不可信
                if errno == ENOENT || errno == ENOTDIR { return }
                throw PathPolicyError.redirected(String(component))
            }
            if status.isSymbolicLink {
                throw index == components.count - 1 ? PathPolicyError.symlinkLeaf : PathPolicyError.redirected(String(component))
            }
        }
    }
}
