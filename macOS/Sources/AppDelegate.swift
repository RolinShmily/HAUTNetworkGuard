import Cocoa
import Darwin

/// 应用代理
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.log("\(AppConfig.appName) v\(AppConfig.version) 启动")
        Logger.debug("应用配置快照: hasConfigured=\(AppConfig.shared.hasConfigured), autoSave=\(AppConfig.shared.autoSave), autoLogin=\(AppConfig.shared.autoLogin), checkInterval=\(AppConfig.shared.checkInterval), autoLaunch=\(LaunchManager.shared.isEnabled)")

        if AppRuntime.isUISmokeTest {
            Logger.info("进入 macOS UI smoke test 启动路径")
            startApp()
            return
        }

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
        let changed = NSApp.setActivationPolicy(.regular)
        Logger.debug("首次配置窗口切换到 regular 激活策略 (changed=\(changed))")
        settingsWindow = SettingsWindowController(isInitialSetup: true)
        settingsWindow?.onSave = { [weak self] in
            self?.startApp()
        }
        settingsWindow?.onCloseWithoutSave = {
            Logger.warn("首次配置在保存前被关闭，应用将退出")
            NSApp.terminate(nil)
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.orderFrontRegardless()
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        _ = NSRunningApplication.current.activate(
            options: [.activateAllWindows, .activateIgnoringOtherApps]
        )
    }

    private func startApp() {
        Logger.debug("初始化菜单栏控制器")
        let changed = NSApp.setActivationPolicy(.accessory)
        Logger.debug("切回菜单栏应用激活策略 (changed=\(changed))")
        statusBarController = StatusBarController()

        if AppRuntime.isUISmokeTest, let controller = statusBarController {
            controller.runUISmokeTest { success, message in
                if success {
                    Logger.info(message)
                } else {
                    Logger.error(message)
                }
                fflush(stdout)
                fflush(stderr)
                Darwin.exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.log("\(AppConfig.appName) 退出")
    }
}
