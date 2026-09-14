import CryptoKit
import Foundation
import Localization

/// 支持的登录方式；服务器 /auth/providers 告诉应用哪些已经配置好
public enum SyncProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case github, google, apple

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .github: "GitHub"
        case .google: "Google"
        case .apple: "Apple"
        }
    }
}

public struct SyncUser: Codable, Equatable, Sendable {
    public var id: String
    public var email: String?
    public var name: String?
    public var avatar: URL?
    public var providers: [String]

    public init(id: String, email: String? = nil, name: String? = nil, avatar: URL? = nil, providers: [String] = []) {
        self.id = id
        self.email = email
        self.name = name
        self.avatar = avatar
        self.providers = providers
    }

    /// 界面上显示的名字：姓名，其次邮箱
    public var displayName: String { name?.isEmpty == false ? name! : (email ?? id) }
}

/// 云端保存的一份设置：整份覆盖，版本号递增
public struct RemoteSettings<Document: Codable & Sendable>: Codable, Sendable {
    public var version: Int
    public var updatedAt: Date
    public var device: String?
    public var document: Document
}

public struct SettingsReceipt: Codable, Equatable, Sendable {
    public var version: Int
    public var updatedAt: Date
}

public struct SyncSession: Codable, Equatable, Sendable {
    public var token: String
    public var user: SyncUser
}

public enum SyncError: Error, Equatable, LocalizedError {
    /// 令牌已作废（退出登录、删除账号或服务器清理）
    case unauthorized
    case server(Int, String)
    case transport(String)
    case invalidCallback
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unauthorized: tr("登录已失效，请重新登录")
        case .server(let status, let message): message.isEmpty ? tr("服务器返回 \(status)") : message
        case .transport(let message): message
        case .invalidCallback: tr("登录回调不正确")
        case .cancelled: tr("已取消登录")
        }
    }
}

/// 同步服务的 HTTP 客户端：只做请求与解码，不保存状态
public struct SyncClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://getopenstats.com/api/v1")!
    /// 应用在 Info.plist 里注册的 URL scheme，登录完成后浏览器跳回这里
    public static let callbackScheme = "openstats"

    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = SyncClient.defaultBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: 登录

    /// 浏览器打开的登录入口；challenge 是 PKCE verifier 的 S256 摘要
    public func loginURL(provider: SyncProvider, challenge: String) -> URL {
        var components = URLComponents(url: baseURL.appending(path: "auth/\(provider.rawValue)/start"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "challenge", value: challenge)]
        return components.url!
    }

    /// 解析 openstats://auth/callback?code=… 或 ?error=…
    public static func parseCallback(_ url: URL) -> Result<String, SyncError> {
        guard url.scheme == callbackScheme,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return .failure(.invalidCallback)
        }
        if let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            return .success(code)
        }
        let error = items.first(where: { $0.name == "error" })?.value ?? ""
        return .failure(error == "cancelled" ? .cancelled : .server(0, error))
    }

    public func providers() async throws -> [SyncProvider] {
        struct Response: Decodable { var providers: [String] }
        let response: Response = try await send(request("GET", "auth/providers"))
        return response.providers.compactMap(SyncProvider.init(rawValue:))
    }

    public func exchange(code: String, verifier: String, device: String) async throws -> SyncSession {
        struct Body: Encodable { var code: String; var verifier: String; var device: String }
        return try await send(request("POST", "auth/exchange", body: Body(code: code, verifier: verifier, device: device)))
    }

    public func me(token: String) async throws -> SyncUser {
        try await send(request("GET", "me", token: token))
    }

    public func logout(token: String) async throws {
        _ = try await sendRaw(request("POST", "auth/logout", token: token))
    }

    public func deleteAccount(token: String) async throws {
        _ = try await sendRaw(request("DELETE", "account", token: token))
    }

    // MARK: 设置

    /// 没有保存过时返回 nil
    public func fetchSettings<Document: Codable & Sendable>(token: String, as type: Document.Type) async throws -> RemoteSettings<Document>? {
        let (data, status) = try await sendRaw(request("GET", "settings", token: token), allowing: [404])
        guard status != 404 else { return nil }
        return try Self.decoder.decode(RemoteSettings<Document>.self, from: data)
    }

    public func putSettings<Document: Codable & Sendable>(token: String, document: Document, device: String) async throws -> SettingsReceipt {
        try await send(request("PUT", "settings", token: token, body: PutSettingsBody(document: document, device: device)))
    }

    private struct PutSettingsBody<Document: Encodable>: Encodable {
        var document: Document
        var device: String
    }

    // MARK: 请求

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func request(_ method: String, _ path: String, token: String? = nil, body: (some Encodable)? = nil as Data?) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("OpenStats", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)
        }
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, _) = try await sendRaw(request)
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw SyncError.server(200, tr("服务器返回的数据格式不正确"))
        }
    }

    /// 返回响应体与状态码；2xx 与 allowing 之外的状态码转成 SyncError
    private func sendRaw(_ request: URLRequest, allowing: Set<Int> = []) async throws -> (Data, Int) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SyncError.transport(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) || allowing.contains(status) { return (data, status) }
        if status == 401 { throw SyncError.unauthorized }
        struct Failure: Decodable { var error: String }
        let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error ?? ""
        throw SyncError.server(status, message)
    }
}

/// PKCE（RFC 7636）：verifier 留在应用里，只把 S256 摘要交给服务器
public enum PKCE {
    public static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    public static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
