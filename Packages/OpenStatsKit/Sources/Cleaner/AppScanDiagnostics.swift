import Darwin
import Foundation

/// 一次残留扫描的过程记录：每个目录读到了什么、哪些匹配项被丢弃以及原因。
/// 扫描结果为空或比预期少时，用它定位原因（权限、符号链接、路径检查），不影响扫描本身
public struct AppScanDiagnostics: Sendable {
    public enum State: Sendable, Equatable {
        /// 读到了，附条目数
        case listed(Int)
        case missing
        /// 系统不让读（权限、完全磁盘访问等），附错误说明
        case denied(String)
        /// 路径里有符号链接
        case redirected(String)
        case failed(String)
    }

    public struct Directory: Sendable, Equatable {
        public let path: String
        public let state: State
    }

    /// 名字匹配上了，但没通过路径检查或读不了，因此没有列入结果
    public struct Rejection: Sendable, Equatable {
        public let path: String
        public let reason: String
    }

    public internal(set) var directories: [Directory] = []
    public internal(set) var rejections: [Rejection] = []
    /// 没有进行残留扫描的原因（例如存在其他安装副本）
    public internal(set) var skippedReason: String?

    public init() {}

    func record(_ path: String, _ state: State) -> Directory { Directory(path: path, state: state) }

    /// errno 的可读说明
    static func message(for code: Int32) -> String { String(cString: strerror(code)) }
}

extension AppUninstallScan {
    /// 可复制的诊断报告：给开发者看。家目录统一写成 ~；文件名里的控制字符转义，免得一个怪文件名伪造出报告里的行
    public func diagnosticReport(app: InstalledApp, home: String = NSHomeDirectory(),
                                 header: [String] = []) -> String {
        /// 家目录写成 ~（按目录边界判断，/Users/ab 不算 /Users/a 的子路径），并转义控制字符
        func tidy(_ text: String) -> String {
            var result = text
            if !home.isEmpty, home != "/" {
                result = result.replacingOccurrences(of: home + "/", with: "~/")
                if result == home { result = "~" }
            }
            var escaped = ""
            for scalar in result.unicodeScalars {
                if scalar.properties.generalCategory == .control {
                    escaped += scalar.value < 0x100 ? String(format: "\\x%02X", scalar.value) : "\\u{\(String(scalar.value, radix: 16))}"
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
            return escaped
        }
        var lines = header.map(tidy)
        lines.append(tidy("应用：\(app.name)（\(app.bundleIdentifier)）\(app.version.map { " 版本 \($0)" } ?? "")"))
        lines.append(tidy("位置：\(app.url.path)"))
        lines.append(tidy("用于匹配的标识：" + identity.identifiers.sorted().joined(separator: "、")))
        if !identity.applicationGroups.isEmpty {
            lines.append(tidy("签名里的应用组：" + identity.applicationGroups.sorted().joined(separator: "、")))
        }
        lines.append(tidy("用于匹配的名称：" + identity.names.sorted().joined(separator: "、")))

        if let reason = diagnostics.skippedReason { lines.append("没有扫描残留：\(reason)") }
        if !otherInstalledCopies.isEmpty {
            lines.append(tidy("其他安装副本：" + otherInstalledCopies.map(\.path).joined(separator: "、")))
        }

        lines.append("")
        lines.append("找到 \(items.count) 项：")
        for item in items {
            let evidence = item.evidence.map { "  ← \(tidy($0.summary))" } ?? ""
            let flags = [item.location == .system ? "系统级，仅提示" : nil, item.requiresReview ? "默认保留" : nil]
                .compactMap { $0 }.joined(separator: "，")
            lines.append("  [\(item.kind.rawValue)] \(tidy(item.url.path))\(flags.isEmpty ? "" : "（\(flags)）")\(evidence)")
        }

        lines.append("")
        lines.append("读取过的目录：")
        for directory in diagnostics.directories {
            let state: String
            switch directory.state {
            case .listed(let count): state = "✓ 列出 \(count) 项"
            case .missing: state = "– 不存在"
            case .denied(let message): state = "✗ 系统拒绝访问（\(tidy(message))）"
            case .redirected(let detail): state = "✗ 路径里有符号链接（\(tidy(detail))）"
            case .failed(let message): state = "✗ 读取失败（\(tidy(message))）"
            }
            lines.append("  \(tidy(directory.path))：\(state)")
        }

        if !diagnostics.rejections.isEmpty {
            lines.append("")
            lines.append("名字匹配上、但没有列入结果的项目：")
            for rejection in diagnostics.rejections {
                lines.append("  \(tidy(rejection.path))：\(tidy(rejection.reason))")
            }
        }
        return lines.joined(separator: "\n")
    }
}
