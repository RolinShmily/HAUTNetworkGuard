import Foundation

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
    static var minLevel: Level = {
        let raw = ProcessInfo.processInfo.environment["HAUT_LOG_LEVEL"]?.uppercased() ?? "DEBUG"
        switch raw {
        case "ERROR":
            return .error
        case "WARN", "WARNING":
            return .warn
        case "INFO":
            return .info
        default:
            return .debug
        }
    }()

    private static let requestQueue = DispatchQueue(label: "cn.ehaut.networkguard.logger.request")
    private static var requestCounter: UInt64 = 0
    private static let maxFileSize: UInt64 = 1_048_576

    private static var logDirectory: String {
        "\(NSHomeDirectory())/Library/Logs/HAUTNetworkGuard"
    }

    private static var logFilePath: String {
        "\(logDirectory)/app.log"
    }

    private static func writeToFile(_ line: String) {
        let fm = FileManager.default

        if !fm.fileExists(atPath: logDirectory) {
            try? fm.createDirectory(
                atPath: logDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        if let attrs = try? fm.attributesOfItem(atPath: logFilePath),
           let size = attrs[.size] as? UInt64,
           size > maxFileSize {
            let oldPath = logFilePath + ".old"
            try? fm.removeItem(atPath: oldPath)
            try? fm.moveItem(atPath: logFilePath, toPath: oldPath)
        }

        if !fm.fileExists(atPath: logFilePath) {
            fm.createFile(atPath: logFilePath, contents: nil)
        }

        guard let handle = FileHandle(forWritingAtPath: logFilePath),
              let data = (line + "\n").data(using: .utf8) else {
            return
        }

        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
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
        requestQueue.sync {
            requestCounter += 1
            return "\(prefix)-\(requestCounter)"
        }
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

    static func log(_ message: String) { info(message) }
}
