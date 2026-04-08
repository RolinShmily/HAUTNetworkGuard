import Cocoa

/// 应用代理
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.log("\(AppConfig.appName) v\(AppConfig.version) 启动")
        Logger.debug("应用配置快照: hasConfigured=\(AppConfig.shared.hasConfigured), autoSave=\(AppConfig.shared.autoSave), autoLogin=\(AppConfig.shared.autoLogin), checkInterval=\(AppConfig.shared.checkInterval), autoLaunch=\(LaunchManager.shared.isEnabled)")

        // 检查是否首次运行或未配置
        if !AppConfig.shared.hasConfigured {
            Logger.info("检测到首次运行或未配置，打开设置窗口")
            showFirstRunSettings()
        } else {
            Logger.info("配置已存在，直接启动菜单栏控制器")
            startApp()
        }
    }

    private func showFirstRunSettings() {
        settingsWindow = SettingsWindowController()
        settingsWindow?.onSave = { [weak self] in
            self?.startApp()
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startApp() {
        Logger.debug("初始化菜单栏控制器")
        statusBarController = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.log("\(AppConfig.appName) 退出")
    }
}
