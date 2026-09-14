import Foundation

/// 在线归属地数据源。都由每台 Mac 直接查询自己的公网 IP，不经过我们的服务器
public enum GeoProvider: String, CaseIterable, Sendable, Codable {
    /// cleanip.io：归属地、ASN、网络类型、原生 / 广播、纯净度与风险评分，中文地名
    case cleanIP
    /// ipapi.is 匿名接口：归属地与 ASN，按客户端 IP 每天 30 次
    case ipapi
    /// DB-IP 免费接口：只有国家、省 / 州与城市
    case dbip
    /// ipinfo.io 匿名接口：归属地与 ASN，匿名额度很小
    case ipinfo

    public var displayName: String {
        switch self {
        case .cleanIP: "CleanIP.io"
        case .ipapi: "ipapi.is"
        case .dbip: "DB-IP"
        case .ipinfo: "ipinfo.io"
        }
    }

    /// 同一个 IP 的结果保留多久
    var cacheLifetime: TimeInterval {
        self == .cleanIP ? 60 * 60 : 24 * 60 * 60
    }

    func url(for ip: String) -> URL? {
        var components: URLComponents?
        switch self {
        case .cleanIP:
            components = URLComponents(string: "https://cleanip.io/cli")
            components?.queryItems = [URLQueryItem(name: "ip", value: ip), URLQueryItem(name: "json", value: "1")]
        case .ipapi:
            components = URLComponents(string: "https://api.ipapi.is/")
            components?.queryItems = [URLQueryItem(name: "q", value: ip)]
        case .dbip:
            components = URLComponents(string: "https://api.db-ip.com/v2/free/\(ip)")
        case .ipinfo:
            components = URLComponents(string: "https://ipinfo.io/\(ip)/json")
        }
        return components?.url
    }
}

public struct PublicAddresses: Sendable, Equatable, Codable {
    public var ipv4: String?
    public var ipv6: String?
    /// ISO 3166 两位国家 / 地区代码（大写），例如 “CN”
    public var countryCode: String?
    public var city: String?
    /// 省 / 州，例如 “New York”
    public var region: String?
    /// 数据源给的是中文地名时，这里是英文，供英文界面使用
    public var cityEnglish: String?
    public var regionEnglish: String?
    /// 自治系统号，例如 “AS4134”
    public var asn: String?
    /// 网络所属组织（英文），例如 “CHINANET-BACKBONE”
    public var organization: String?
    /// 以下只有 CleanIP.io 提供
    public var hostname: String?
    /// 网络类型：Residential / Business / Hosting / Mobile …
    public var networkType: String?
    /// 自治系统的类型：isp / hosting / business / education / government / mobile
    public var asnType: String?
    /// 接入方式：Cable/DSL / Cellular / Corporate …
    public var connectionType: String?
    /// IP 类型：Residential IP / Datacenter IP …
    public var ipType: String?
    /// 原生 IP（登记国、宣告 AS 注册国与定位国一致）还是广播 IP
    public var isNative: Bool?
    public var residentialProbability: Int?
    public var purity: Purity?
    public var risk: Risk?
    public var reportURL: URL?
    public var source: Source = .online(.cleanIP)

    public struct Purity: Sendable, Equatable, Codable {
        public var score: Int
        public var grade: String
        public var confidence: Int?
        public var recommendation: String?
        public init(score: Int, grade: String, confidence: Int? = nil, recommendation: String? = nil) {
            self.score = score
            self.grade = grade
            self.confidence = confidence
            self.recommendation = recommendation
        }
    }

    public struct Risk: Sendable, Equatable, Codable {
        public var score: Int
        public var label: String?
        /// 命中的标记：vpn、proxy、tor、datacenter、hosting、relay、abuser、residentialProxy
        public var flags: [String]
        public init(score: Int, label: String? = nil, flags: [String] = []) {
            self.score = score
            self.label = label
            self.flags = flags
        }
    }

    public enum Source: Sendable, Equatable, Codable {
        /// 本机的 MaxMind GeoLite2 数据库
        case localDatabase
        case online(GeoProvider)
    }

    public init(ipv4: String? = nil, ipv6: String? = nil, countryCode: String? = nil,
                city: String? = nil, region: String? = nil, asn: String? = nil, organization: String? = nil) {
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.countryCode = countryCode
        self.city = city
        self.region = region
        self.asn = asn
        self.organization = organization
    }

    /// 把在线查到的归属地信息并进来；国家代码以 Cloudflare 给的为准，没有时才用数据源的
    public mutating func apply(_ geo: PublicAddressLookup.GeoInfo) {
        city = geo.city
        region = geo.region
        cityEnglish = geo.cityEnglish
        regionEnglish = geo.regionEnglish
        asn = geo.asn
        organization = geo.organization
        hostname = geo.hostname
        networkType = geo.networkType
        asnType = geo.asnType
        connectionType = geo.connectionType
        ipType = geo.ipType
        isNative = geo.isNative
        residentialProbability = geo.residentialProbability
        purity = geo.purity
        risk = geo.risk
        reportURL = geo.reportURL
        if countryCode == nil { countryCode = geo.countryCode }
    }
}

/// 查询公网 IP 与归属地。只在用户打开网络详情时请求，不携带任何本机信息。
/// 公网地址来自 Cloudflare trace（直连 IP，不依赖 DNS，同时给出国家代码），回退 ipify；
/// 归属地等信息按用户选择的数据源在线查询，由每台 Mac 自己直接查。这些接口按客户端 IP 限额，
/// 所以同一个公网 IP 的结果会记住一段时间，收到 429 后到当天（UTC）结束都不再请求
public enum PublicAddressLookup {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["User-Agent": "OpenStats"]
        return URLSession(configuration: configuration)
    }()

    private static let geoCache = GeoCache()

    /// `includeGeo` 为假时只查询公网 IP，不请求任何归属地服务
    public static func fetch(includeGeo: Bool = true, provider: GeoProvider = .cleanIP) async -> PublicAddresses {
        async let v4 = lookup(trace: "https://1.1.1.1/cdn-cgi/trace", fallback: "https://api.ipify.org")
        async let v6 = lookup(trace: "https://[2606:4700:4700::1111]/cdn-cgi/trace", fallback: "https://api6.ipify.org")
        let (ipv4, ipv6) = await (v4, v6)
        var result = PublicAddresses(ipv4: ipv4.ip, ipv6: ipv6.ip, countryCode: ipv4.country ?? ipv6.country)
        result.source = .online(provider)
        guard includeGeo, let ip = result.ipv4 ?? result.ipv6, let geo = await geoCache.lookup(ip, provider: provider) else { return result }
        result.apply(geo)
        return result
    }

    /// 只查一个已知地址的归属地，公网 IP 没变时用它补全，不必重新取地址
    public static func geo(for ip: String, provider: GeoProvider) async -> GeoInfo? {
        await geoCache.lookup(ip, provider: provider)
    }

    // MARK: 归属地

    public struct GeoInfo: Sendable, Equatable {
        public var countryCode: String?
        public var city: String?
        public var region: String?
        public var cityEnglish: String?
        public var regionEnglish: String?
        public var asn: String?
        public var organization: String?
        public var hostname: String?
        public var networkType: String?
        public var asnType: String?
        public var connectionType: String?
        public var ipType: String?
        public var isNative: Bool?
        public var residentialProbability: Int?
        public var purity: PublicAddresses.Purity?
        public var risk: PublicAddresses.Risk?
        public var reportURL: URL?
    }

    static func parse(_ data: Data, provider: GeoProvider) -> GeoInfo? {
        switch provider {
        case .cleanIP: parseCleanIP(data)
        case .ipapi: parseGeo(data)
        case .dbip: parseDBIP(data)
        case .ipinfo: parseIpinfo(data)
        }
    }

    // MARK: CleanIP.io

    struct CleanIPResponse: Decodable {
        struct Geo: Decodable {
            let countryCode: String?
            let country: String?
            let countryEn: String?
            let region: String?
            let city: String?
        }
        struct GeoSource: Decodable {
            let source: String?
            let region: String?
            let city: String?
        }
        struct Network: Decodable {
            let asn: Int?
            let asnName: String?
            let asnType: String?
            let isp: String?
            let networkType: String?
            let connectionType: String?
            let nativeOrBroadcast: String?
        }
        struct Purity: Decodable {
            let score: Int?
            let grade: String?
            let confidence: Int?
            let ipType: String?
            let isNative: Bool?
            let residentialProbability: Int?
            let recommendation: String?
        }
        struct Risk: Decodable {
            let riskScore: Int?
            let riskLabel: String?
            let isVpn: Bool?
            let isProxy: Bool?
            let isTor: Bool?
            let isDatacenter: Bool?
            let isHosting: Bool?
            let isRelay: Bool?
            let isAbuser: Bool?
            let isResidentialProxy: Bool?
        }
        let ok: Bool?
        let ip: String?
        let hostname: String?
        let geo: Geo?
        let geoSources: [GeoSource]?
        let network: Network?
        let purity: Purity?
        let risk: Risk?
    }

    static func parseCleanIP(_ data: Data) -> GeoInfo? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(CleanIPResponse.self, from: data), response.ok != false else { return nil }
        var info = GeoInfo()
        info.countryCode = response.geo?.countryCode.flatMap(validCountryCode)
        info.city = response.geo?.city.flatMap(nonEmpty)
        info.region = response.geo?.region.flatMap(nonEmpty)
        // 英文地名取 ipinfo 那一路的
        if let english = response.geoSources?.first(where: { $0.source == "ipinfo" }) {
            info.cityEnglish = english.city.flatMap(nonEmpty)
            info.regionEnglish = english.region.flatMap(nonEmpty)
        }
        if let asn = response.network?.asn, asn > 0 { info.asn = "AS\(asn)" }
        info.organization = response.network?.isp.flatMap(nonEmpty) ?? response.network?.asnName.flatMap(nonEmpty)
        if let hostname = response.hostname.flatMap(nonEmpty), hostname != response.ip { info.hostname = hostname }
        info.networkType = response.network?.networkType.flatMap(nonEmpty)
        info.asnType = response.network?.asnType.flatMap(nonEmpty)?.lowercased()
        info.connectionType = response.network?.connectionType.flatMap(nonEmpty)
        info.ipType = response.purity?.ipType.flatMap(nonEmpty)
        info.isNative = response.purity?.isNative ?? response.network?.nativeOrBroadcast.map { $0.uppercased() == "NATIVE" }
        info.residentialProbability = response.purity?.residentialProbability
        if let score = response.purity?.score, let grade = response.purity?.grade.flatMap(nonEmpty) {
            info.purity = PublicAddresses.Purity(score: min(100, max(0, score)), grade: grade,
                                                 confidence: response.purity?.confidence,
                                                 recommendation: response.purity?.recommendation.flatMap(nonEmpty))
        }
        if let risk = response.risk, let score = risk.riskScore {
            var flags: [String] = []
            if risk.isVpn == true { flags.append("vpn") }
            if risk.isProxy == true { flags.append("proxy") }
            if risk.isResidentialProxy == true { flags.append("residentialProxy") }
            if risk.isTor == true { flags.append("tor") }
            if risk.isRelay == true { flags.append("relay") }
            if risk.isDatacenter == true { flags.append("datacenter") }
            if risk.isHosting == true { flags.append("hosting") }
            if risk.isAbuser == true { flags.append("abuser") }
            info.risk = PublicAddresses.Risk(score: min(100, max(0, score)), label: risk.riskLabel.flatMap(nonEmpty), flags: flags)
        }
        if let ip = response.ip, isAddress(ip) { info.reportURL = URL(string: "https://cleanip.io/\(ip)") }
        return info
    }

    // MARK: ipapi.is

    /// ipapi.is 匿名接口的响应：`asn` 形如 “AS7018 AT&T Enterprises, LLC”，`country` 是英文全名，`company` 是地址持有方
    struct GeoResponse: Decodable {
        let ip: String?
        let company: String?
        let asn: String?
        let city: String?
        let region: String?
        let country: String?
    }

    static func parseGeo(_ data: Data) -> GeoInfo? {
        guard let response = try? JSONDecoder().decode(GeoResponse.self, from: data) else { return nil }
        var info = GeoInfo()
        info.countryCode = response.country.flatMap(nonEmpty).flatMap(countryCode(fromName:))
        info.city = response.city.flatMap(nonEmpty)
        info.region = response.region.flatMap(nonEmpty)
        let (asn, asnOrganization) = splitASN(response.asn)
        info.asn = asn
        // 地址持有方通常比自治系统的注册名更能说明“是谁的网络”
        info.organization = response.company.flatMap(nonEmpty) ?? asnOrganization
        return info
    }

    // MARK: DB-IP

    struct DBIPResponse: Decodable {
        let countryCode: String?
        let stateProv: String?
        let city: String?
    }

    static func parseDBIP(_ data: Data) -> GeoInfo? {
        guard let response = try? JSONDecoder().decode(DBIPResponse.self, from: data) else { return nil }
        var info = GeoInfo()
        info.countryCode = response.countryCode.flatMap(validCountryCode)
        info.region = response.stateProv.flatMap(nonEmpty)
        info.city = response.city.flatMap(nonEmpty)
        return info
    }

    // MARK: ipinfo.io

    struct IpinfoResponse: Decodable {
        let country: String?
        let region: String?
        let city: String?
        let org: String?
    }

    static func parseIpinfo(_ data: Data) -> GeoInfo? {
        guard let response = try? JSONDecoder().decode(IpinfoResponse.self, from: data) else { return nil }
        var info = GeoInfo()
        info.countryCode = response.country.flatMap(validCountryCode)
        info.region = response.region.flatMap(nonEmpty)
        info.city = response.city.flatMap(nonEmpty)
        let (asn, organization) = splitASN(response.org)
        info.asn = asn
        info.organization = organization
        return info
    }

    /// “AS7018 AT&T Enterprises, LLC” → (“AS7018”, “AT&T Enterprises, LLC”)；没有 AS 前缀时整段当组织名
    static func splitASN(_ text: String?) -> (String?, String?) {
        guard let text = text.flatMap(nonEmpty) else { return (nil, nil) }
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        if let first = parts.first, first.hasPrefix("AS"), Int(first.dropFirst(2)) != nil {
            return (first, parts.count > 1 ? parts[1] : nil)
        }
        return (nil, text)
    }

    /// 英文国家名转两位代码：先查几个系统名称对不上的别名，再按系统的英文区域名反查
    static func countryCode(fromName name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let alias = countryAliases[trimmed.lowercased()] { return alias }
        let english = Locale(identifier: "en_US")
        for region in Locale.Region.isoRegions where region.identifier.count == 2 {
            if english.localizedString(forRegionCode: region.identifier)?.caseInsensitiveCompare(trimmed) == .orderedSame {
                return validCountryCode(region.identifier)
            }
        }
        return nil
    }

    private static let countryAliases: [String: String] = [
        "china": "CN", "china mainland": "CN", "united states": "US", "usa": "US", "united kingdom": "GB", "uk": "GB",
        "russia": "RU", "south korea": "KR", "north korea": "KP", "hong kong": "HK", "macau": "MO", "macao": "MO",
        "taiwan": "TW", "vietnam": "VN", "viet nam": "VN", "turkey": "TR", "türkiye": "TR", "czech republic": "CZ",
        "czechia": "CZ", "iran": "IR", "syria": "SY", "laos": "LA", "brunei": "BN", "bolivia": "BO", "venezuela": "VE",
        "tanzania": "TZ", "moldova": "MD", "palestine": "PS", "the netherlands": "NL", "netherlands": "NL",
        "ivory coast": "CI", "cape verde": "CV", "swaziland": "SZ", "myanmar": "MM", "burma": "MM", "congo": "CG",
        "dr congo": "CD", "democratic republic of the congo": "CD", "micronesia": "FM", "vatican": "VA", "reunion": "RE",
        "curacao": "CW", "saint martin": "MF", "sint maarten": "SX",
    ]

    /// 按数据源与 IP 缓存；收到 429 后该数据源到当天（UTC）结束都不再请求
    actor GeoCache {
        private var entries: [String: (info: GeoInfo?, date: Date)] = [:]
        private var blockedUntil: [GeoProvider: Date] = [:]

        func lookup(_ ip: String, provider: GeoProvider) async -> GeoInfo? {
            let key = "\(provider.rawValue)|\(ip)"
            if let entry = entries[key], Date().timeIntervalSince(entry.date) < provider.cacheLifetime { return entry.info }
            if let until = blockedUntil[provider], Date() < until { return nil }
            guard let url = provider.url(for: ip) else { return nil }
            let (data, status) = await PublicAddressLookup.getWithStatus(url)
            if status == 429 {
                blockedUntil[provider] = Self.nextUTCMidnight()
                return nil
            }
            guard status == 200, let data else { return nil }
            let info = PublicAddressLookup.parse(data, provider: provider)
            entries[key] = (info, Date())
            return info
        }

        private static func nextUTCMidnight() -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let start = calendar.startOfDay(for: Date())
            return calendar.date(byAdding: .day, value: 1, to: start) ?? Date().addingTimeInterval(12 * 3600)
        }
    }

    /// 只接受两位字母，之后会用作国旗文件名
    static func validCountryCode(_ code: String) -> String? {
        let upper = code.uppercased()
        guard upper.count == 2, upper.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }) else { return nil }
        return upper
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: 回退

    private static func lookup(trace: String, fallback: String) async -> (ip: String?, country: String?) {
        if let data = await get(trace), let body = String(data: data, encoding: .utf8) {
            let fields = parseTrace(body)
            if let ip = fields["ip"] { return (ip, fields["loc"].flatMap(validCountryCode)) }
        }
        if let data = await get(fallback), let body = String(data: data, encoding: .utf8) {
            let ip = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if isAddress(ip) { return (ip, nil) }
        }
        return (nil, nil)
    }

    private static func get(_ string: String) async -> Data? {
        guard let url = URL(string: string) else { return nil }
        let (data, status) = await getWithStatus(url)
        return status == 200 ? data : nil
    }

    static func getWithStatus(_ url: URL) async -> (Data?, Int) {
        guard let (data, response) = try? await session.data(from: url) else { return (nil, 0) }
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func parseTrace(_ body: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in body.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            fields[String(parts[0])] = String(parts[1])
        }
        if let ip = fields["ip"], !isAddress(ip) { fields["ip"] = nil }
        return fields
    }

    static func isAddress(_ text: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return inet_pton(AF_INET, text, &v4) == 1 || inet_pton(AF_INET6, text, &v6) == 1
    }
}
