import Foundation

/// 官网上的版本清单（https://getopenstats.com/download/appcast.json），由 Scripts/publish_release.sh 生成
public struct UpdateRelease: Codable, Sendable, Equatable {
    public let version: String
    public let build: String
    public let date: String
    public let minimumSystem: String
    /// 应用内升级下载的 zip（已公证、已装订的 OpenStats.app）
    public let url: URL
    public let sha256: String
    public let size: Int64
    /// 手动安装用的 DMG
    public let dmg: URL?
    /// 最近更新的摘要，每条一句
    public let notes: [String]
    public let changelog: URL?

    public init(version: String, build: String, date: String, minimumSystem: String, url: URL, sha256: String,
                size: Int64, dmg: URL?, notes: [String], changelog: URL?) {
        self.version = version
        self.build = build
        self.date = date
        self.minimumSystem = minimumSystem
        self.url = url
        self.sha256 = sha256
        self.size = size
        self.dmg = dmg
        self.notes = notes
        self.changelog = changelog
    }
}

public enum UpdateFeed {
    public static let url = URL(string: "https://getopenstats.com/download/appcast.json")!

    public static func parse(_ data: Data) -> UpdateRelease? {
        guard let release = try? JSONDecoder().decode(UpdateRelease.self, from: data),
              !release.version.isEmpty, release.sha256.count == 64,
              release.url.scheme == "https" else { return nil }
        return release
    }

    /// 按数字逐段比较版本号：“0.10.0” 比 “0.9.3” 新，“1.0” 与 “1.0.0” 相同
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = components(candidate), rhs = components(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// 当前系统是否满足清单要求的最低版本
    public static func systemSatisfies(_ minimum: String, current: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Bool {
        let running = "\(current.majorVersion).\(current.minorVersion).\(current.patchVersion)"
        return !isNewer(minimum, than: running)
    }

    private static func components(_ version: String) -> [Int] {
        version.split(whereSeparator: { !$0.isNumber }).map { Int($0) ?? 0 }
    }
}
