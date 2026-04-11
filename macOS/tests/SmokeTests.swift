import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct SmokeTests {
    static func main() {
        expect(SrunEncryption.encryptUsername("231040600203") == "{SRUN3}\r\n675484:44647", "用户名加密向量不匹配")
        expect(SrunEncryption.encryptPassword("password123") == "6gh>Agg:7gh@<gh=9cc99c", "密码加密向量不匹配")

        let login = SrunProtocol.classifyLoginResponse("login_error#E2531:User not found")
        expect(login.category == "error_E2531", "登录响应分类不匹配")

        let parsed = SrunProtocol.parseStatusResponse(
            "jQuery_1712630100000({\"error\":\"ok\",\"user_name\":\"231040600203\",\"online_ip\":\"10.10.0.8\",\"sum_bytes\":12345678,\"sum_seconds\":321})",
            callback: "jQuery_1712630100000"
        )
        expect(parsed.online, "JSONP 状态解析应判定为在线")
        expect(parsed.format == "jsonp", "JSONP 状态解析格式不匹配")
        expect(parsed.ip == "10.10.0.8", "JSONP 状态解析 IP 不匹配")
        expect(parsed.usedBytes == 12345678, "JSONP 状态解析流量不匹配")
        expect(parsed.usedSeconds == 321, "JSONP 状态解析时长不匹配")

        AppConfig.shared.clear()
        AppConfig.shared.save(
            username: "231040600203",
            password: "password123",
            autoSave: false,
            checkInterval: 45,
            autoLogin: true
        )
        expect(UserDefaults.standard.string(forKey: "haut_password") == nil, "未勾选记住密码时不应持久化密码")

        AppConfig.shared.password = "session-only"
        expect(AppConfig.shared.password == "session-only", "会话密码应可读回")
        expect(UserDefaults.standard.string(forKey: "haut_password") == nil, "会话密码不应落盘")

        AppConfig.shared.clear()
        print("macOS smoke tests passed")
    }
}
