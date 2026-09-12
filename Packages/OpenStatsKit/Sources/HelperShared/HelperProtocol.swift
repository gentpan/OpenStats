import Foundation

public enum HelperConstants {
    public static let machServiceName = "com.openstats.helper"
    public static let launchdPlistName = "com.openstats.helper.plist"
    public static let appBundleIdentifier = "com.openstats.app"
    /// 与 App 版本同步；App 发现辅助工具版本不一致时提示重新安装
    public static let protocolVersion = 2

    /// 用 Developer ID 签名后填入 Team ID，辅助工具会据此严格校验调用方。
    /// 为空时只校验 bundle identifier，仅适用于本地开发。
    public static let teamIdentifier = ""

    public static var clientRequirement: String {
        let identifier = "identifier \"\(appBundleIdentifier)\""
        guard !teamIdentifier.isEmpty else { return identifier }
        return identifier + " and anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }
}

/// 辅助工具以 root 运行，只暴露固定的少量操作，不提供任意命令执行能力。
/// 所有回调中的 `String?` 为错误描述，nil 表示成功。
@objc public protocol OpenStatsHelperProtocol {
    func protocolVersion(reply: @escaping @Sendable (Int) -> Void)
    func setFanTarget(fan: Int, rpm: Double, reply: @escaping @Sendable (String?) -> Void)
    func setFanAutomatic(fan: Int, reply: @escaping @Sendable (String?) -> Void)
    func resetAllFans(reply: @escaping @Sendable (String?) -> Void)
    func setSleepDisabled(_ disabled: Bool, reply: @escaping @Sendable (String?) -> Void)
    func flushDNSCache(reply: @escaping @Sendable (String?) -> Void)
    func purgeMemory(reply: @escaping @Sendable (String?) -> Void)
}

/// 需要管理员权限的系统维护命令。辅助工具与未安装辅助工具时的授权回退共用同一份固定命令
public enum MaintenanceCommand: String, Sendable, CaseIterable {
    case flushDNS, purgeMemory

    public var steps: [(path: String, arguments: [String])] {
        switch self {
        case .flushDNS: [("/usr/bin/dscacheutil", ["-flushcache"]), ("/usr/bin/killall", ["-HUP", "mDNSResponder"])]
        case .purgeMemory: [("/usr/sbin/purge", [])]
        }
    }

    public var shellCommand: String {
        steps.map { ([$0.path] + $0.arguments).joined(separator: " ") }.joined(separator: "; ")
    }
}
