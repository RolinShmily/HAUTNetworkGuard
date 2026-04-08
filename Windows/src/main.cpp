#include "config.h"
#include "logger.h"
#include "mainwindow.h"
#include <QApplication>
#include <QCoreApplication>
#include <QDir>
#include <QStringList>
#include <QStyle>

int main(int argc, char *argv[]) {
  QApplication app(argc, argv);

  // 设置应用程序信息
  app.setApplicationName("HAUTNetworkGuard");
  app.setApplicationVersion("1.3.12");
  app.setOrganizationName("YellowPeach");
  // 使用系统默认图标
  app.setWindowIcon(app.style()->standardIcon(QStyle::SP_ComputerIcon));

  // 设置关闭最后窗口时不退出应用（托盘常驻）
  app.setQuitOnLastWindowClosed(false);

  // 加载配置
  Config::instance();

  // 带 --startup 参数时静默启动到托盘（开机自启场景）
  const QStringList args = app.arguments();
  const bool startInBackground =
      args.contains("--startup", Qt::CaseInsensitive);
  Logger::info(QString("应用启动 (版本: %1, 路径: %2, 参数: %3, 启动模式: %4)")
                   .arg(QCoreApplication::applicationVersion(),
                        QDir::toNativeSeparators(
                            QCoreApplication::applicationFilePath()),
                        args.join(" "),
                        startInBackground ? "background" : "normal"));

  // 创建主窗口
  MainWindow mainWindow;
  if (!startInBackground) {
    Logger::debug("主窗口前台显示");
    mainWindow.show();
  } else {
    Logger::info("检测到 --startup，主窗口保持隐藏，仅托盘常驻");
  }

  return app.exec();
}
