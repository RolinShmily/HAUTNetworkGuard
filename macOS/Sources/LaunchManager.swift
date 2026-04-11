import Foundation
import Darwin

/// 开机自启动管理器
class LaunchManager {
    static let shared = LaunchManager()

    private let launchAgentLabel = "cn.ehaut.networkguard"
    private let launchAgentsPath: String
    private let logDirectory: String

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        launchAgentsPath = "\(home)/Library/LaunchAgents"
        logDirectory = "\(home)/Library/Logs/HAUTNetworkGuard"
    }

    private var plistPath: String {
        return "\(launchAgentsPath)/\(launchAgentLabel).plist"
    }

    private var executablePath: String {
        Bundle.main.executablePath ?? "/Applications/HAUTNetworkGuard.app/Contents/MacOS/HAUTNetworkGuard"
    }

    private var launchctlDomain: String {
        "gui/\(getuid())"
    }

    private var stdoutPath: String {
        "\(logDirectory)/launchd.stdout.log"
    }

    private var stderrPath: String {
        "\(logDirectory)/launchd.stderr.log"
    }

    /// 是否已启用开机自启动
    var isEnabled: Bool {
        guard let plist = loadPlist() else {
            Logger.debug("检查开机自启动状态: plist 不存在 path=\(plistPath)")
            return false
        }
        let matches = plistMatchesExpected(plist)
        Logger.debug("检查开机自启动状态: matches=\(matches), path=\(plistPath)")
        return matches
    }

    /// 启用开机自启动
    func enable() -> Bool {
        // 确保 LaunchAgents 目录存在
        if !FileManager.default.fileExists(atPath: launchAgentsPath) {
            do {
                try FileManager.default.createDirectory(
                    atPath: launchAgentsPath,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                Logger.log("创建 LaunchAgents 目录失败: \(error)")
                return false
            }
        }

        if !FileManager.default.fileExists(atPath: executablePath) {
            Logger.warn("启用开机自启动时未找到应用可执行文件: \(executablePath)")
        }

        if !FileManager.default.fileExists(atPath: logDirectory) {
            do {
                try FileManager.default.createDirectory(
                    atPath: logDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                Logger.warn("创建 LaunchAgent 日志目录失败: \(error)")
            }
        }

        // 创建 plist 内容
        let plistContent: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": stdoutPath,
            "StandardErrorPath": stderrPath
        ]

        // 序列化 plist
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plistContent,
            format: .xml,
            options: 0
        ) else {
            Logger.log("生成 plist 数据失败")
            return false
        }

        // 写入文件
        do {
            try data.write(to: URL(fileURLWithPath: plistPath), options: .atomic)
            Logger.log("开机自启动 plist 已写入: \(plistPath)")
            _ = runLaunchctl(arguments: ["bootout", launchctlDomain, plistPath], tolerateFailure: true)
            _ = runLaunchctl(arguments: ["unload", plistPath], tolerateFailure: true)
            if runLaunchctl(arguments: ["bootstrap", launchctlDomain, plistPath], tolerateFailure: true)
                || runLaunchctl(arguments: ["load", plistPath], tolerateFailure: false) {
                Logger.log("开机自启动已启用并加载")
                return true
            }
            Logger.warn("plist 已写入，但 launchctl 加载失败")
            return false
        } catch {
            Logger.log("写入 plist 文件失败: \(error)")
            return false
        }
    }

    /// 禁用开机自启动
    func disable() -> Bool {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            Logger.debug("开机自启动 plist 不存在，视为已禁用")
            return true
        }

        do {
            _ = runLaunchctl(arguments: ["bootout", launchctlDomain, plistPath], tolerateFailure: true)
            _ = runLaunchctl(arguments: ["unload", plistPath], tolerateFailure: true)
            try FileManager.default.removeItem(atPath: plistPath)
            Logger.log("开机自启动已禁用")
            return true
        } catch {
            Logger.log("删除 plist 文件失败: \(error)")
            return false
        }
    }

    /// 设置开机自启动状态
    func setEnabled(_ enabled: Bool) -> Bool {
        return enabled ? enable() : disable()
    }

    @discardableResult
    private func runLaunchctl(arguments: [String], tolerateFailure: Bool) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if process.terminationStatus == 0 {
                Logger.debug("launchctl \(arguments.joined(separator: " ")) 成功 \(output)")
                return true
            }
            if !tolerateFailure {
                Logger.warn("launchctl \(arguments.joined(separator: " ")) 失败: \(output)")
            }
            return false
        } catch {
            if !tolerateFailure {
                Logger.warn("执行 launchctl 失败: \(error)")
            }
            return false
        }
    }

    private func loadPlist() -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return plist
    }

    private func plistMatchesExpected(_ plist: [String: Any]) -> Bool {
        let args = plist["ProgramArguments"] as? [String] ?? []
        let keepAlive = plist["KeepAlive"] as? Bool ?? false
        let out = plist["StandardOutPath"] as? String ?? ""
        let err = plist["StandardErrorPath"] as? String ?? ""
        return args == [executablePath] && keepAlive && out == stdoutPath && err == stderrPath
    }
}
