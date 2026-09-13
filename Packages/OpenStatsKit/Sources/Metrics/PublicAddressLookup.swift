import Foundation

public struct PublicAddresses: Sendable, Equatable {
    public var ipv4: String?
    public var ipv6: String?
    /// ISO 3166 两位国家 / 地区代码（大写），例如 “CN”
    public var countryCode: String?
    public var city: String?
    /// 自治系统号，例如 “AS4134”
    public var asn: String?
    /// 网络所属组织（英文），例如 “CHINANET-BACKBONE”
    public var organization: String?

    public init(ipv4: String? = nil, ipv6: String? = nil, countryCode: String? = nil,
                city: String? = nil, asn: String? = nil, organization: String? = nil) {
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.countryCode = countryCode
        self.city = city
        self.asn = asn
        self.organization = organization
    }
}

/// 查询公网 IP 与归属地。只在用户打开网络详情时请求，不携带任何本机信息。
/// 归属地与 ASN 来自 ipinfo.io；IPv6 地址与失败时的回退使用 Cloudflare trace（直连 IP，不依赖 DNS）与 ipify。
public enum PublicAddressLookup {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    public static func fetch() async -> PublicAddresses {
        async let geoResult = geo()
        async let v6Result = lookup(trace: "https://[2606:4700:4700::1111]/cdn-cgi/trace", fallback: "https://api6.ipify.org")
        var result = await geoResult ?? PublicAddresses()
        let v6 = await v6Result

        if let ip = result.ipv6, result.ipv4 == nil {
            // 本机优先走 IPv6 时，归属地接口返回的是 IPv6 地址，IPv4 另外查询
            result.ipv6 = ip
            let v4 = await lookup(trace: "https://1.1.1.1/cdn-cgi/trace", fallback: "https://api.ipify.org")
            result.ipv4 = v4.ip
        } else if result.ipv4 == nil {
            let v4 = await lookup(trace: "https://1.1.1.1/cdn-cgi/trace", fallback: "https://api.ipify.org")
            result.ipv4 = v4.ip
            result.countryCode = result.countryCode ?? v4.country
        }
        if result.ipv6 == nil { result.ipv6 = v6.ip }
        if result.countryCode == nil { result.countryCode = v6.country }
        return result
    }

    // MARK: 归属地

    /// ipinfo.io 的响应：`country` 是两位代码，`org` 形如 “AS151338 POLONETWORK LIMITED”
    struct GeoResponse: Decodable {
        let ip: String?
        let city: String?
        let country: String?
        let org: String?
    }

    private static func geo() async -> PublicAddresses? {
        guard let data = await get("https://ipinfo.io/json") else { return nil }
        return parseGeo(data)
    }

    static func parseGeo(_ data: Data) -> PublicAddresses? {
        guard let response = try? JSONDecoder().decode(GeoResponse.self, from: data),
              let ip = response.ip, isAddress(ip) else { return nil }
        var result = PublicAddresses()
        if ip.contains(":") { result.ipv6 = ip } else { result.ipv4 = ip }
        result.countryCode = response.country.flatMap(validCountryCode)
        result.city = response.city.flatMap(nonEmpty)
        if let org = response.org.flatMap(nonEmpty) {
            let parts = org.split(separator: " ", maxSplits: 1).map(String.init)
            if let first = parts.first, first.hasPrefix("AS"), Int(first.dropFirst(2)) != nil {
                result.asn = first
                result.organization = parts.count > 1 ? parts[1] : nil
            } else {
                result.organization = org
            }
        }
        return result
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
        guard let url = URL(string: string),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
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
