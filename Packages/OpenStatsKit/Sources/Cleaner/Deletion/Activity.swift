import Foundation

/// 当前在运行的应用。“读不到”和“没有在运行”是两回事：读不到时一律按“可能在运行”处理，不删。
public enum RunningApps: Sendable {
    case known(Set<String>)
    case unknown
}

/// 这个应用在运行时，相关条目不能动
public struct GuardApp: Sendable, Hashable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// 条目名是反向域名（如 com.foo.bar）时，找出正在运行的、名字与之相同或是其子标识的应用。
/// 容器目录常带前缀：团队号（5A4RE8SF68.com.foo.bar）或 group.（group.com.foo.bar），先去掉；比较不区分大小写
func owningRunningApp(ofEntryNamed name: String, running: Set<String>) -> String? {
    var candidate = name
    if candidate.lowercased().hasPrefix("group.") {
        candidate = String(candidate.dropFirst("group.".count))
    } else if let dot = candidate.firstIndex(of: "."), candidate[..<dot].count == 10,
              candidate[..<dot].allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) {
        candidate = String(candidate[candidate.index(after: dot)...])
    }
    guard candidate.split(separator: ".").count >= 3 else { return nil }
    let lowered = candidate.lowercased()
    return running.first { lowered == $0.lowercased() || lowered.hasPrefix($0.lowercased() + ".") }
}
