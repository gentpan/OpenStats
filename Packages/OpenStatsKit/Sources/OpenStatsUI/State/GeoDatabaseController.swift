import CryptoKit
import Foundation
import Metrics
import Observation

/// 本地 IP 归属地数据库（MaxMind GeoLite2）：从官网下载或手动导入，校验后放在应用支持目录，查询完全离线。
@MainActor
@Observable
public final class GeoDatabaseController {
    public struct Installed: Codable, Equatable {
        let edition: String
        let build: String
        let sha256: String
        let size: Int64
    }

    public private(set) var installed: [String: Installed] = [:]
    public private(set) var isUpdating = false
    public private(set) var message: (text: String, isError: Bool)?
    public private(set) var lastChecked: Date?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var locationDatabase: MaxMindDatabase?
    @ObservationIgnored private var asnDatabase: MaxMindDatabase?

    static let manifestURL = URL(string: "https://getopenstats.com/geoip/manifest.json")!
    static let attribution = "本产品包含 MaxMind 创建的 GeoLite2 数据，可从 https://www.maxmind.com 获取。"
    private static let checkInterval: TimeInterval = 3 * 24 * 3600
    private static let lastCheckedKey = "geoDatabaseLastChecked"

    let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("OpenStats/GeoIP", isDirectory: true)
    }()
    private var indexURL: URL { directory.appendingPathComponent("installed.json") }

    init(settings: AppSettings) {
        self.settings = settings
        lastChecked = UserDefaults.standard.object(forKey: Self.lastCheckedKey) as? Date
        reload()
    }

    /// 至少有国家 / 城市库或 ASN 库之一
    var isAvailable: Bool { locationDatabase != nil || asnDatabase != nil }

    func locate(_ address: String) -> GeoLocation? {
        GeoLookup.locate(address, location: locationDatabase, asn: asnDatabase)
    }

    // MARK: 更新

    func updateIfNeeded() async {
        guard settings.geoAutoUpdate else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.checkInterval, isAvailable { return }
        await update()
    }

    func update() async {
        guard !isUpdating else { return }
        isUpdating = true
        message = nil
        defer { isUpdating = false }

        let wanted = ["GeoLite2-ASN", settings.geoIncludeCity ? "GeoLite2-City" : "GeoLite2-Country"]
        do {
            let (data, response) = try await URLSession.shared.data(from: Self.manifestURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw Failure("服务器上还没有数据库，稍后再试")
            }
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            var changed = 0
            for edition in wanted {
                guard let entry = manifest.databases.first(where: { $0.edition == edition }) else {
                    throw Failure("服务器清单里没有 \(edition)")
                }
                if installed[edition]?.sha256 == entry.sha256 { continue }
                try await download(entry)
                changed += 1
            }
            // 切换城市 / 国家库后删掉不再需要的那个
            for edition in installed.keys where !wanted.contains(edition) && edition.hasPrefix("GeoLite2-") {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(edition).mmdb"))
                installed[edition] = nil
            }
            try saveIndex()
            reload()
            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: Self.lastCheckedKey)
            message = (changed > 0 ? "已更新 \(changed) 个数据库" : "已经是最新", false)
        } catch let failure as Failure {
            message = (failure.text, true)
        } catch {
            message = ("更新失败：\(error.localizedDescription)", true)
            Log.network.error("归属地数据库更新失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 下载到临时文件，sha256 与清单一致、且能按库类型打开后才替换
    private func download(_ entry: Manifest.Entry) async throws {
        guard let url = URL(string: entry.file, relativeTo: Self.manifestURL) else { throw Failure("清单里的文件地址无效") }
        let (temporary, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure("下载 \(entry.edition) 失败") }
        let digest = try await Task.detached { try Self.sha256(of: temporary) }.value
        guard digest == entry.sha256 else { throw Failure("\(entry.edition) 校验不一致，已丢弃") }
        let database = try MaxMindDatabase(url: temporary)
        guard database.databaseType == entry.edition else { throw Failure("\(entry.edition) 文件类型不对") }
        try install(temporary, edition: entry.edition, build: entry.build, sha256: digest, size: entry.size)
    }

    /// 手动导入 .mmdb：按文件里记录的库类型识别是城市、国家还是 ASN 库
    func importDatabase(from url: URL) {
        do {
            let database = try MaxMindDatabase(url: url)
            let type = database.databaseType
            guard type.hasSuffix("-City") || type.hasSuffix("-Country") || type.hasSuffix("-ASN") else {
                throw Failure("不是城市、国家或 ASN 数据库（\(type)）")
            }
            let digest = try Self.sha256(of: url)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            let build = database.buildDate.formatted(.iso8601.year().month().day().dateSeparator(.omitted))
            try install(url, edition: type, build: build, sha256: digest, size: size, copy: true)
            try saveIndex()
            reload()
            message = ("已导入 \(type)", false)
        } catch let failure as Failure {
            message = (failure.text, true)
        } catch {
            message = ("导入失败：\(error.localizedDescription)", true)
        }
    }

    private func install(_ source: URL, edition: String, build: String, sha256: String, size: Int64, copy: Bool = false) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(edition).mmdb")
        let staging = directory.appendingPathComponent(".\(edition).mmdb.new")
        try? FileManager.default.removeItem(at: staging)
        if copy {
            try FileManager.default.copyItem(at: source, to: staging)
        } else {
            try FileManager.default.moveItem(at: source, to: staging)
        }
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        installed[edition] = Installed(edition: edition, build: build, sha256: sha256, size: size)
    }

    // MARK: 加载

    private func reload() {
        if let data = try? Data(contentsOf: indexURL),
           let index = try? JSONDecoder().decode([String: Installed].self, from: data) {
            installed = index.filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent("\($0.key).mmdb").path) }
        }
        func open(_ suffix: String) -> MaxMindDatabase? {
            installed.keys.sorted().filter { $0.hasSuffix(suffix) }
                .lazy.compactMap { try? MaxMindDatabase(url: self.directory.appendingPathComponent("\($0).mmdb")) }.first
        }
        locationDatabase = open("-City") ?? open("-Country")
        asnDatabase = open("-ASN")
    }

    private func saveIndex() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(installed).write(to: indexURL, options: .atomic)
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private struct Manifest: Decodable {
        struct Entry: Decodable {
            let edition: String
            let file: String
            let build: String
            let sha256: String
            let size: Int64
        }
        let databases: [Entry]
    }

    private struct Failure: Error {
        let text: String
        init(_ text: String) { self.text = text }
    }
}
