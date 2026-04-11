import Foundation
import Network

/// 绕过系统代理/VPN，通过物理网络接口直连内网网关的 HTTP 客户端
/// 使用 POSIX socket + IP_BOUND_IF 在内核层面绑定物理接口，
/// 彻底绕过 TUN 路由和系统代理设置
class DirectHTTPClient {
    private let queue = DispatchQueue(label: "DirectHTTPClient")
    private let stateQueue = DispatchQueue(label: "DirectHTTPClient.state")
    private let monitorQueue = DispatchQueue(label: "DirectHTTPClient.monitor")
    private var interfaceName: String?
    private let monitor: NWPathMonitor
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 10) {
        self.timeout = timeout
        self.monitor = NWPathMonitor()
        self.monitor.pathUpdateHandler = { [weak self] path in
            self?.updateInterface(from: path)
        }
        self.monitor.start(queue: monitorQueue)
        updateInterface(from: monitor.currentPath)
    }

    deinit {
        monitor.cancel()
    }

    /// 从网络路径中选取物理接口（优先有线，其次 WiFi）
    private func updateInterface(from path: NWPath) {
        let interfaces = path.availableInterfaces
        let resolvedName: String?
        if let wired = interfaces.first(where: { $0.type == .wiredEthernet }) {
            resolvedName = wired.name
            Logger.info("[DirectHTTP] 使用有线接口: \(wired.name)")
        } else if let wifi = interfaces.first(where: { $0.type == .wifi }) {
            resolvedName = wifi.name
            Logger.info("[DirectHTTP] 使用 WiFi 接口: \(wifi.name)")
        } else {
            resolvedName = interfaces.first?.name
            if let name = resolvedName {
                Logger.info("[DirectHTTP] 使用接口: \(name)")
            } else {
                Logger.warn("[DirectHTTP] 未找到可用物理接口")
            }
        }

        stateQueue.sync {
            interfaceName = resolvedName
        }
    }

    // MARK: - Public API

    /// 发送 GET 请求
    func get(url: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let parsed = parseURL(url) else {
            completion(.failure(HTTPError.invalidURL))
            return
        }
        let request = "GET \(parsed.path) HTTP/1.1\r\n" +
                      hostHeader(parsed.host, port: parsed.port) +
                      "Connection: close\r\n\r\n"
        performRequest(host: parsed.host, port: parsed.port, request: request, completion: completion)
    }

    /// 发送 POST 请求（application/x-www-form-urlencoded）
    func post(url: String, body: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let parsed = parseURL(url) else {
            completion(.failure(HTTPError.invalidURL))
            return
        }
        let bodyBytes = body.data(using: .utf8) ?? Data()
        let request = "POST \(parsed.path) HTTP/1.1\r\n" +
                      hostHeader(parsed.host, port: parsed.port) +
                      "Content-Type: application/x-www-form-urlencoded\r\n" +
                      "Content-Length: \(bodyBytes.count)\r\n" +
                      "Connection: close\r\n\r\n" +
                      body
        performRequest(host: parsed.host, port: parsed.port, request: request, completion: completion)
    }

    // MARK: - Private

    private func hostHeader(_ host: String, port: UInt16) -> String {
        return port == 80 ? "Host: \(host)\r\n" : "Host: \(host):\(port)\r\n"
    }

    /// 使用 POSIX socket 发送 HTTP 请求，通过 IP_BOUND_IF 绑定物理接口
    private func performRequest(host: String, port: UInt16, request: String,
                                completion: @escaping (Result<String, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // 解析目标地址
            guard var addr = self.resolveHost(host, port: port) else {
                completion(.failure(HTTPError.invalidURL))
                return
            }

            // 创建 TCP socket
            let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
            guard fd >= 0 else {
                completion(.failure(HTTPError.socketError("socket() 失败, errno=\(errno)")))
                return
            }

            // 绑定到物理接口（绕过 TUN 路由和代理）
            if let ifName = self.waitForInterfaceName(timeout: 1.0) {
                let ifIndex = if_nametoindex(ifName)
                if ifIndex > 0 {
                    var idx = ifIndex
                    let ret = setsockopt(fd, IPPROTO_IP, IP_BOUND_IF,
                                         &idx, socklen_t(MemoryLayout<UInt32>.size))
                    if ret == 0 {
                        Logger.debug("[DirectHTTP] 绑定接口: \(ifName) (index=\(ifIndex))")
                    } else {
                        Logger.warn("[DirectHTTP] 绑定接口失败: \(ifName), errno=\(errno)")
                    }
                }
            } else {
                Logger.warn("[DirectHTTP] 请求开始时仍未解析到物理接口，将使用系统默认路由")
            }

            // 设置超时
            var tv = timeval(tv_sec: Int(self.timeout), tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            // 连接
            let connectResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if connectResult < 0 {
                let err = errno
                Darwin.close(fd)
                if err == ETIMEDOUT {
                    completion(.failure(HTTPError.timeout))
                } else {
                    completion(.failure(HTTPError.socketError("connect() 失败, errno=\(err)")))
                }
                return
            }

            // 发送请求
            guard let requestData = request.data(using: .utf8) else {
                Darwin.close(fd)
                completion(.failure(HTTPError.invalidURL))
                return
            }
            let sent = self.sendAll(fd: fd, data: requestData)
            if let sentError = sent {
                Darwin.close(fd)
                completion(.failure(sentError))
                return
            }

            // 接收响应（Connection: close，读到 EOF）
            var responseData = Data()
            var buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = recv(fd, &buffer, buffer.count, 0)
                if n == 0 { break }
                if n < 0 {
                    let err = errno
                    Darwin.close(fd)
                    if err == ETIMEDOUT {
                        completion(.failure(HTTPError.timeout))
                    } else {
                        completion(.failure(HTTPError.socketError("recv() 失败, errno=\(err)")))
                    }
                    return
                }
                responseData.append(buffer, count: n)
            }
            Darwin.close(fd)

            // 解析 HTTP body
            if let body = self.extractHTTPBody(from: responseData) {
                completion(.success(body))
            } else if let str = String(data: responseData, encoding: .utf8) {
                completion(.success(str))
            } else {
                completion(.failure(HTTPError.invalidResponse))
            }
        }
    }

    /// 解析主机名为 IPv4 地址
    private func resolveHost(_ host: String, port: UInt16) -> sockaddr_in? {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

        // 先尝试直接解析 IP
        if inet_pton(AF_INET, host, &addr.sin_addr) == 1 {
            return addr
        }

        // DNS 解析
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let ai = result else {
            return nil
        }
        defer { freeaddrinfo(result) }

        if ai.pointee.ai_family == AF_INET {
            let sin = ai.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            addr.sin_addr = sin.sin_addr
            return addr
        }
        return nil
    }

    /// 从原始 HTTP 响应中提取 body
    private func extractHTTPBody(from data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        if let range = raw.range(of: "\r\n\r\n") {
            return String(raw[range.upperBound...])
        }
        return raw
    }

    // MARK: - URL 解析

    private struct ParsedURL {
        let host: String
        let port: UInt16
        let path: String
    }

    private func parseURL(_ url: String) -> ParsedURL? {
        guard let comps = URLComponents(string: url),
              let host = comps.host else {
            return nil
        }
        let port = UInt16(comps.port ?? 80)
        var path = comps.path.isEmpty ? "/" : comps.path
        if let query = comps.query {
            path += "?\(query)"
        }
        return ParsedURL(host: host, port: port, path: path)
    }

    private func currentInterfaceName() -> String? {
        stateQueue.sync { interfaceName }
    }

    private func waitForInterfaceName(timeout: TimeInterval) -> String? {
        if let name = currentInterfaceName() {
            return name
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            if let name = currentInterfaceName() {
                return name
            }
        }
        return currentInterfaceName()
    }

    private func sendAll(fd: Int32, data: Data) -> HTTPError? {
        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return HTTPError.invalidURL
            }

            let basePointer = baseAddress.assumingMemoryBound(to: UInt8.self)
            var offset = 0
            while offset < data.count {
                let sent = Darwin.send(fd, basePointer.advanced(by: offset), data.count - offset, 0)
                if sent <= 0 {
                    let err = errno
                    if err == ETIMEDOUT {
                        return HTTPError.timeout
                    }
                    return HTTPError.socketError("send() 失败, errno=\(err)")
                }
                offset += sent
            }

            return nil
        }
    }

    enum HTTPError: Error, CustomStringConvertible {
        case invalidURL
        case timeout
        case invalidResponse
        case socketError(String)

        var description: String {
            switch self {
            case .invalidURL: return "无效的 URL"
            case .timeout: return "请求超时"
            case .invalidResponse: return "无效的响应"
            case .socketError(let msg): return "Socket 错误: \(msg)"
            }
        }

        var localizedDescription: String { description }
    }
}
