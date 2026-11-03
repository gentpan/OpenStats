import Foundation
import Localization
import Network

/// 监控大屏的 HTTP 服务：NWListener 上跑一个极简 HTTP/1.1，一连接一个请求（Connection: close）。
/// 只服务三个只读端点（页面 / 指标 / 存活），只认 GET 和 HEAD，不解析请求体。
/// 监听的是所有网卡，所以在这里挡：只接受来自本机、局域网和链路本地地址的连接；
/// Host 头必须是 IP 或本机 / 局域网主机名，别人的域名经 DNS 重绑定指到本机也读不到；
/// 每个连接限时、总数封顶，空连接占不满文件描述符。
/// 页面与指标快照由 DashboardController 提前备好，这里只负责收发。
/// 监听是否成功不通过回调通知（避免跨线程闭包），控制器在采样循环里读 currentState 轮询
final class DashboardServer: @unchecked Sendable {
    enum ListenerState: Equatable, Sendable {
        case starting
        case ready
        case failed(String)
    }

    static let maxRequestBytes = 16_384

    private let lock = NSLock()
    private var listener: NWListener?
    private var state: ListenerState?
    private var openConnections = 0
    private let html: Data
    private let maxConnections: Int
    private let requestTimeout: TimeInterval
    /// 最新的 /metrics 内容，由控制器的采样循环更新
    private let metricsProvider: @Sendable () -> Data

    init(html: Data, maxConnections: Int = 32, requestTimeout: TimeInterval = 5,
         metricsProvider: @escaping @Sendable () -> Data) {
        self.html = html
        self.maxConnections = maxConnections
        self.requestTimeout = requestTimeout
        self.metricsProvider = metricsProvider
    }

    // MARK: 生命周期

    /// 开始监听指定端口；端口冲突等异步失败写进 currentState
    func start(port: UInt16) {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let created: NWListener
        do {
            created = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port) ?? .any)
        } catch {
            lock.lock()
            discardListenerLocked()
            state = .failed(tr("无法在端口 \(port) 上监听"))
            lock.unlock()
            return
        }
        lock.lock()
        discardListenerLocked()
        listener = created
        state = .starting
        lock.unlock()

        created.stateUpdateHandler = { [weak self, weak created] newState in
            guard let self, let created else { return }
            self.note(newState, from: created)
        }
        created.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        created.start(queue: .global())
    }

    func stop() {
        lock.lock()
        discardListenerLocked()
        state = nil
        lock.unlock()
    }

    /// 最近一次监听状态；未调用过 start 或已停止时为 nil
    func currentState() -> ListenerState? {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    /// 实际监听的端口，ready 之后才有值（传 0 让系统挑端口时用来取回）
    var boundPort: UInt16? {
        lock.lock()
        defer { lock.unlock() }
        return listener?.port?.rawValue
    }

    private func discardListenerLocked() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
    }

    /// 只认当前这一个监听器的事件：换端口后旧监听器迟到的 ready / failed 不能覆盖新状态
    private func note(_ newState: NWListener.State, from source: NWListener) {
        lock.lock()
        defer { lock.unlock() }
        guard listener === source else { return }
        switch newState {
        case .ready:
            state = .ready
        case .failed(let error), .waiting(let error):
            // waiting 是系统暂时绑不上（端口被占、网络没起来），对用户来说同样是没在服务
            state = .failed(error.localizedDescription)
        default:
            break
        }
    }

    // MARK: 连接处理

    private func accept(_ connection: NWConnection) {
        guard Self.isLocalPeer(connection.endpoint), reserveSlot() else {
            connection.cancel()
            return
        }
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .failed: connection?.cancel()
            case .cancelled: self?.releaseSlot()
            default: break
            }
        }
        connection.start(queue: .global())
        // 到点还没收发完就断开；正常结束的连接早已释放，这里的弱引用取不到，什么也不做
        DispatchQueue.global().asyncAfter(deadline: .now() + requestTimeout) { [weak connection] in
            connection?.cancel()
        }
        receiveRequest(connection, buffered: Data())
    }

    private func reserveSlot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard openConnections < maxConnections else { return false }
        openConnections += 1
        return true
    }

    private func releaseSlot() {
        lock.lock()
        openConnections -= 1
        lock.unlock()
    }

    private func receiveRequest(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            var buffer = buffered
            if let data { buffer.append(data) }
            // 头没收全就继续收；超过 16KB 或对端写完还没出现头也不再等
            let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8))
            if headerEnd == nil, !isComplete, buffer.count < Self.maxRequestBytes {
                self.receiveRequest(connection, buffered: buffer)
                return
            }
            let head = headerEnd.map { buffer.prefix(upTo: $0.lowerBound) } ?? buffer
            let request = Self.parseRequest(Data(head))
            let response = Self.makeResponse(for: request, html: self.html, metrics: self.metricsProvider())
            connection.send(content: response.data, contentContext: .defaultMessage, isComplete: true,
                            completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}

/// 一次 HTTP 响应：状态行 + 头 + 正文，已拼好待发送
struct HTTPResponse {
    let status: Int
    let contentType: String
    let body: Data
    /// 405 时告诉对方允许哪些方法
    var allow: String?
    /// HEAD：头里照常带 Content-Length，但不发正文
    var headOnly = false

    var data: Data {
        let reason = Self.reasons[status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(body.count)\r\n"
        if let allow { head += "Allow: \(allow)\r\n" }
        head += "Cache-Control: no-store\r\n"
            + "Connection: close\r\n"
            + "X-Content-Type-Options: nosniff\r\n\r\n"
        return Data(head.utf8) + (headOnly ? Data() : body)
    }

    private static let reasons: [Int: String] = [
        200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed",
    ]
}

/// 请求行与 Host 头；其余请求头一概不看
struct HTTPRequest: Equatable {
    let method: String
    let path: String
    let host: String?
}

extension DashboardServer {
    /// 纯函数：解析请求头，请求行不合规返回 nil
    static func parseRequest(_ head: Data) -> HTTPRequest? {
        let text = String(decoding: head.prefix(maxRequestBytes), as: UTF8.self)
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/") else { return nil }
        var host: String?
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), line[..<colon].lowercased() == "host" else { continue }
            host = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            break
        }
        return HTTPRequest(method: String(parts[0]), path: String(parts[1]), host: host)
    }

    /// 纯函数：按请求生成响应，便于单测
    static func makeResponse(for request: HTTPRequest?, html: Data, metrics: Data) -> HTTPResponse {
        guard let request else { return text(400, "bad request") }
        guard isAcceptableHost(request.host) else { return text(403, "forbidden") }
        guard request.method == "GET" || request.method == "HEAD" else {
            var response = text(405, "method not allowed")
            response.allow = "GET, HEAD"
            return response
        }
        var response = makeResponse(path: request.path, html: html, metrics: metrics)
        response.headOnly = request.method == "HEAD"
        return response
    }

    /// 纯函数：按路径生成响应
    static func makeResponse(path: String?, html: Data, metrics: Data) -> HTTPResponse {
        let path = path?.split(separator: "?").first.map(String.init) ?? "/"
        switch path {
        case "/", "/index.html":
            return HTTPResponse(status: 200, contentType: "text/html; charset=utf-8", body: html)
        case "/metrics":
            return HTTPResponse(status: 200, contentType: "application/json; charset=utf-8", body: metrics)
        case "/healthz":
            return text(200, "ok")
        default:
            return text(404, "not found")
        }
    }

    private static func text(_ status: Int, _ body: String) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "text/plain; charset=utf-8", body: Data(body.utf8))
    }

    // MARK: 访问范围

    /// 浏览器访问大屏时 Host 头只会是 IP、localhost 或局域网主机名；
    /// 别人的域名经 DNS 重绑定指到本机时 Host 仍是他的域名，据此拒绝。
    /// 没带 Host 的只可能是 HTTP/1.0 的命令行客户端，放行
    static func isAcceptableHost(_ header: String?) -> Bool {
        guard let header = header?.lowercased(), !header.isEmpty else { return true }
        if header.hasPrefix("[") {   // [fe80::1]:8790
            guard let close = header.firstIndex(of: "]") else { return false }
            return IPv6Address(String(header[header.index(after: header.startIndex)..<close])) != nil
        }
        var host = header
        if let colon = host.lastIndex(of: ":") { host = String(host[..<colon]) }
        if host.hasSuffix(".") { host.removeLast() }
        if host.isEmpty { return false }
        if IPv4Address(host) != nil { return true }
        if !host.contains(".") { return true }   // localhost 与单段主机名
        return [".local", ".lan", ".home.arpa", ".localdomain"].contains { host.hasSuffix($0) }
    }

    /// 来源是不是本机、局域网或链路本地地址：10/8、172.16/12、192.168/16、169.254/16、127/8，
    /// IPv6 的 ::1、fe80::/10、fc00::/7，以及映射成 IPv6 的这些 IPv4 地址
    static func isLocalAddress(_ bytes: [UInt8]) -> Bool {
        switch bytes.count {
        case 4:
            let (first, second) = (bytes[0], bytes[1])
            return first == 10 || first == 127
                || (first == 192 && second == 168)
                || (first == 172 && (16...31).contains(second))
                || (first == 169 && second == 254)
        case 16:
            if bytes[..<15].allSatisfy({ $0 == 0 }), bytes[15] == 1 { return true }
            if bytes[0] == 0xfe, bytes[1] & 0xc0 == 0x80 { return true }
            if bytes[0] & 0xfe == 0xfc { return true }
            if bytes[..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
                return isLocalAddress(Array(bytes[12...]))
            }
            return false
        default:
            return false
        }
    }

    static func isLocalPeer(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return isLocalAddress(Array(address.rawValue))
        case .ipv6(let address): return isLocalAddress(Array(address.rawValue))
        default: return false
        }
    }
}
