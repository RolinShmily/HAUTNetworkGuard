import Foundation

enum AppRuntime {
    private static let args = Set(ProcessInfo.processInfo.arguments)

    static var isUISmokeTest: Bool {
        args.contains("--ui-smoke-test")
    }
}
