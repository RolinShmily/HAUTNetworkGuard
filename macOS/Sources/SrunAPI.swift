import Foundation

/// 网络状态枚举
enum NetworkStatus {
    case online(username: String, ip: String, usedBytes: Int64, usedSeconds: Int64)
    case offline
    case checking
    case error(String)

    var isOnline: Bool {
        if case .online = self { return true }
        return false
    }

    var kindLabel: String {
        switch self {
        case .online:
            return "online"
        case .offline:
            return "offline"
        case .checking:
            return "checking"
        case .error:
            return "error"
        }
    }

    var description: String {
        switch self {
        case .online(let username, let ip, let usedBytes, let usedSeconds):
            let dataStr = formatBytes(usedBytes)
            let timeStr = formatDuration(usedSeconds)
            return "在线: \(username)\nIP: \(ip)\n已用流量: \(dataStr)\n在线时长: \(timeStr)"
        case .offline:
            return "未连接"
        case .checking:
            return "检测中..."
        case .error(let msg):
            return "错误: \(msg)"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1073741824.0
        let mb = Double(bytes) / 1048576.0
        if gb >= 1 {
            return String(format: "%.2f GB", gb)
        } else {
            return String(format: "%.2f MB", mb)
        }
    }

    private func formatDuration(_ seconds: Int64) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d小时%d分%d秒", hours, minutes, secs)
        } else if minutes > 0 {
            return String(format: "%d分%d秒", minutes, secs)
        } else {
            return String(format: "%d秒", secs)
        }
    }
}

/// 登录结果枚举
enum LoginResult {
    case success
    case alreadyOnline
    case failed(String)
}

/// SRUN3K API 封装
class SrunAPI {
    // 服务器配置
    static let serverIP = "172.16.154.130"
    static let loginPort = 69
    static let statusURL = "http://\(serverIP)/cgi-bin/rad_user_info"
    static let loginURL = "http://\(serverIP):\(loginPort)/cgi-bin/srun_portal"
    static let acId = "1"

    // 从配置读取凭据
    private var username: String { AppConfig.shared.username }
    private var password: String { AppConfig.shared.password }

    private let httpClient = DirectHTTPClient(timeout: 10)

    private func mask(_ value: String) -> String {
        guard value.count > 4 else { return String(repeating: "*", count: value.count) }
        return String(value.prefix(2)) + String(repeating: "*", count: max(0, value.count - 4)) + String(value.suffix(2))
    }

    private func preview(_ value: String, limit: Int = 160) -> String {
        let normalized = value.replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        if normalized.count > limit {
            return String(normalized.prefix(limit)) + "...(\(normalized.count) chars)"
        }
        return normalized
    }

    /// 检查网络状态 (使用 JSONP 格式，与 OpenWrt 一致)
    func checkStatus(completion: @escaping (NetworkStatus) -> Void) {
        let requestID = Logger.makeRequestID(prefix: "status")
        let startedAt = CFAbsoluteTimeGetCurrent()

        // 生成 JSONP callback 参数
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let callback = "jQuery_\(timestamp)"

        var urlComponents = URLComponents(string: SrunAPI.statusURL)
        urlComponents?.queryItems = [
            URLQueryItem(name: "callback", value: callback),
            URLQueryItem(name: "_", value: String(timestamp))
        ]

        guard let url = urlComponents?.url?.absoluteString else {
            completion(.error("无效的URL"))
            return
        }

        Logger.debug("[\(requestID)] 开始检查网络状态: \(url)")
        httpClient.get(url: url) { result in
            switch result {
            case .success(let responseStr):
                let status = self.parseStatusResponse(responseStr, callback: callback)
                let durationMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                Logger.info("[\(requestID)] 状态检测完成: \(status.kindLabel) (\(durationMs)ms)")
                Logger.debug("[\(requestID)] 状态响应(\(responseStr.utf8.count) bytes): \(self.preview(responseStr))")
                completion(status)
            case .failure(let error):
                let durationMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                Logger.warn("[\(requestID)] 状态检查失败 (\(durationMs)ms): \(error.localizedDescription)")
                completion(.error(error.localizedDescription))
            }
        }
    }

    /// 解析状态响应 (支持 JSONP 和 CSV 格式)
    private func parseStatusResponse(_ response: String, callback: String) -> NetworkStatus {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // 如果响应为空或包含 "not_online"，则表示离线
        if trimmed.isEmpty || trimmed.contains("not_online") {
            return .offline
        }

        // 尝试解析 JSONP 响应: callback({...})
        if let jsonStr = extractJSONFromJSONP(trimmed, callback: callback) {
            if let jsonData = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                
                // 检查 error 字段
                if let error = json["error"] as? String,
                   error.contains("not_online") {
                    return .offline
                }
                
                // 解析用户信息 (与 OpenWrt 一致的字段名)
                let ip = json["online_ip"] as? String ?? ""
                let bytes = parseNumber(json["sum_bytes"])
                let seconds = parseNumber(json["sum_seconds"])
                let username = json["user_name"] as? String ?? ""
                
                if !username.isEmpty || !ip.isEmpty {
                    return .online(username: username, ip: ip,
                                  usedBytes: bytes, usedSeconds: seconds)
                }
            }
        }

        // 回退到 CSV 格式: username,time,ip,bytes,...
        let parts = trimmed.components(separatedBy: ",")
        if parts.count >= 4 {
            let username = parts[0]
            let ip = parts[2]
            let usedBytes = Int64(parts[3]) ?? 0
            let usedSeconds = Int64(parts[1]) ?? 0
            return .online(username: username, ip: ip,
                          usedBytes: usedBytes, usedSeconds: usedSeconds)
        }

        return .offline
    }
    
    /// 从 JSONP 响应中提取 JSON 字符串
    private func extractJSONFromJSONP(_ response: String, callback: String) -> String? {
        // 格式: callback({...}) 或 jQuery_xxx({...})
        let pattern = "jQuery_\\d+\\((.+)\\)$"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)),
           let range = Range(match.range(at: 1), in: response) {
            return String(response[range])
        }
        
        // 尝试精确匹配 callback
        let prefix = "\(callback)("
        let suffix = ")"
        if response.hasPrefix(prefix) && response.hasSuffix(suffix) {
            let start = response.index(response.startIndex, offsetBy: prefix.count)
            let end = response.index(response.endIndex, offsetBy: -suffix.count)
            return String(response[start..<end])
        }
        
        return nil
    }
    
    /// 解析数字 (支持 Int 和 String)
    private func parseNumber(_ value: Any?) -> Int64 {
        if let intValue = value as? Int64 {
            return intValue
        } else if let intValue = value as? Int {
            return Int64(intValue)
        } else if let doubleValue = value as? Double {
            return Int64(doubleValue)
        } else if let strValue = value as? String {
            return Int64(strValue) ?? 0
        }
        return 0
    }

    /// 执行登录
    func login(completion: @escaping (LoginResult) -> Void) {
        guard !username.isEmpty, !password.isEmpty else {
            Logger.warn("登录已取消：凭据为空")
            completion(.failed("未配置学号或密码"))
            return
        }

        let requestID = Logger.makeRequestID(prefix: "login")
        let encryptedUsername = SrunEncryption.encryptUsername(username)
        let encryptedPassword = SrunEncryption.encryptPassword(password)

        Logger.info(
            "[\(requestID)] 准备登录: account=\(Logger.maskUsername(username)), user_len=\(username.count), pass_len=\(password.count), remember_password=\(AppConfig.shared.autoSave)"
        )
        Logger.debug("[\(requestID)] 编码长度: enc_user_len=\(encryptedUsername.count), enc_pass_len=\(encryptedPassword.count)")

        let params: [String: String] = [
            "action": "login",
            "username": encryptedUsername,
            "password": encryptedPassword,
            "ac_id": SrunAPI.acId,
            "drop": "0",
            "pop": "1",
            "type": "10",
            "n": "117",
            "mbytes": "0",
            "minutes": "0",
            "mac": "02:00:00:00:00:00"
        ]

        sendRequest(params: params, requestID: requestID) { result in
            completion(result)
        }
    }

    /// 执行注销
    func logout(completion: @escaping (LoginResult) -> Void) {
        let requestID = Logger.makeRequestID(prefix: "logout")
        let params: [String: String] = [
            "action": "logout"
        ]

        sendRequest(params: params, requestID: requestID) { result in
            completion(result)
        }
    }

    /// 发送 POST 请求
    private func sendRequest(params: [String: String],
                            requestID: String,
                            completion: @escaping (LoginResult) -> Void) {
        let action = params["action"] ?? "unknown"
        let startedAt = CFAbsoluteTimeGetCurrent()
        let bodyString = params.map { "\($0.key)=\($0.value.urlEncoded)" }
                               .joined(separator: "&")

        Logger.info("[\(requestID)] 发送请求: \(SrunAPI.loginURL) action=\(action)")
        Logger.debug("[\(requestID)] 请求摘要: field_count=\(params.count), body_len=\(bodyString.utf8.count)")

        httpClient.post(url: SrunAPI.loginURL, body: bodyString) { result in
            switch result {
            case .success(let responseStr):
                let durationMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                Logger.info("[\(requestID)] 响应分类: \(self.classifyResponse(responseStr)) (\(durationMs)ms)")
                Logger.debug("[\(requestID)] 响应预览: \(self.preview(responseStr))")
                let loginResult = self.parseLoginResponse(responseStr)
                completion(loginResult)
            case .failure(let error):
                let durationMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                Logger.error("[\(requestID)] 请求失败 (\(durationMs)ms): \(error.localizedDescription)")
                completion(.failed(error.localizedDescription))
            }
        }
    }

    private func classifyResponse(_ response: String) -> String {
        if response.contains("login_ok") {
            return "login_ok"
        } else if response.contains("already_online") {
            return "already_online"
        } else if response.contains("logout_ok") {
            return "logout_ok"
        } else if let range = response.range(of: "E\\d+", options: .regularExpression) {
            return "error_\(response[range])"
        }
        return "unknown"
    }

    /// 解析登录响应
    private func parseLoginResponse(_ response: String) -> LoginResult {
        if response.contains("login_ok") {
            return .success
        } else if response.contains("already_online") {
            return .alreadyOnline
        } else if response.contains("logout_ok") {
            return .success
        } else {
            return .failed(response)
        }
    }
}

// MARK: - String 扩展
extension String {
    var urlEncoded: String {
        // 使用更严格的字符集，确保特殊字符被正确编码
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return self.addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

// MARK: - 日志工具
struct Logger {
    enum Level: Int, Comparable {
        case debug = 0, info, warn, error

        var label: String {
            switch self {
            case .debug: return "DEBUG"
            case .info:  return "INFO"
            case .warn:  return "WARN"
            case .error: return "ERROR"
            }
        }

        static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    static var isEnabled = true
    static var minLevel: Level = .debug
    private static var requestCounter: UInt64 = 0

    private static let maxFileSize: UInt64 = 1_048_576 // 1MB

    private static var logDirectory: String {
        let home = NSHomeDirectory()
        return "\(home)/Library/Logs/HAUTNetworkGuard"
    }

    private static var logFilePath: String {
        return "\(logDirectory)/app.log"
    }

    private static func writeToFile(_ line: String) {
        let dir = logDirectory
        let path = logFilePath
        let fm = FileManager.default

        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        // 轮转
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64,
           size > maxFileSize {
            let oldPath = path + ".old"
            try? fm.removeItem(atPath: oldPath)
            try? fm.moveItem(atPath: path, toPath: oldPath)
        }

        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }

        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            if let data = (line + "\n").data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        }
    }

    private static func log(_ level: Level, _ message: String) {
        guard isEnabled, level >= minLevel else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] [\(level.label)] \(message)"
        print(line)
        writeToFile(line)
    }

    static func debug(_ message: String) { log(.debug, message) }
    static func info(_ message: String)  { log(.info, message) }
    static func warn(_ message: String)  { log(.warn, message) }
    static func error(_ message: String) { log(.error, message) }

    static func makeRequestID(prefix: String) -> String {
        requestCounter += 1
        return "\(prefix)-\(requestCounter)"
    }

    static func maskUsername(_ username: String) -> String {
        guard !username.isEmpty else { return "<empty>" }
        if username.count <= 4 {
            return String(repeating: "*", count: username.count)
        }
        let prefix = username.prefix(2)
        let suffix = username.suffix(2)
        return "\(prefix)\(String(repeating: "*", count: max(0, username.count - 4)))\(suffix)"
    }

    /// 兼容旧调用
    static func log(_ message: String) { info(message) }
}
