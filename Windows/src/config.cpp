#include "config.h"
#include "logger.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTextStream>
#include <cstring>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

Config &Config::instance() {
  static Config instance;
  return instance;
}

Config::Config() { load(); }

void Config::load() {
  QSettings settings("HAUTNetworkGuard", "HAUTNetworkGuard");

  m_username = settings.value("username", "").toString();
  m_password = decodePassword(settings.value("password", "").toString());
  m_autoSave = settings.value("auto_save", false).toBool();
  m_autoLaunch = settings.value("auto_launch", false).toBool();
  m_hasConfigured = settings.value("has_configured", false).toBool();
  m_checkInterval = settings.value("check_interval", 30).toInt();
  m_autoLogin = settings.value("auto_login", true).toBool();

  m_checkInterval = qBound(30, m_checkInterval, 300);

  Logger::info(QString("配置已加载 (用户: %1, 间隔: %2s, 自动保存: %3, 自动登录: %4, "
                       "开机自启: %5)")
                   .arg(Logger::maskUsername(m_username))
                   .arg(m_checkInterval)
                   .arg(Logger::boolText(m_autoSave))
                   .arg(Logger::boolText(m_autoLogin))
                   .arg(Logger::boolText(m_autoLaunch)));

  // 兼容旧版本：自动修正开机自启命令，并补充 Startup 目录兜底脚本
  if (m_autoLaunch) {
    verifyAndRepairAutoLaunch();
  }
}

void Config::save() {
  QSettings settings("HAUTNetworkGuard", "HAUTNetworkGuard");

  settings.setValue("username", m_username);
  settings.setValue("password", encodePassword(m_password));
  settings.setValue("auto_save", m_autoSave);
  settings.setValue("auto_launch", m_autoLaunch);
  settings.setValue("has_configured", m_hasConfigured);
  settings.setValue("check_interval", m_checkInterval);
  settings.setValue("auto_login", m_autoLogin);

  settings.sync();

  Logger::info(QString("配置已保存 (用户: %1, 自动保存: %2, 自动登录: %3, "
                       "开机自启: %4, 间隔: %5s)")
                   .arg(Logger::maskUsername(m_username))
                   .arg(Logger::boolText(m_autoSave))
                   .arg(Logger::boolText(m_autoLogin))
                   .arg(Logger::boolText(m_autoLaunch))
                   .arg(m_checkInterval));
}

QString Config::encodePassword(const QString &password) {
  // 简单的 XOR 混淆
  QByteArray data = password.toUtf8();
  const char key[] = "HAUTGuard2024";
  int keyLen = strlen(key);

  for (int i = 0; i < data.size(); ++i) {
    data[i] = data[i] ^ key[i % keyLen];
  }

  return QString::fromLatin1(data.toBase64());
}

QString Config::decodePassword(const QString &encoded) {
  if (encoded.isEmpty())
    return "";

  QByteArray data = QByteArray::fromBase64(encoded.toLatin1());
  const char key[] = "HAUTGuard2024";
  int keyLen = strlen(key);

  for (int i = 0; i < data.size(); ++i) {
    data[i] = data[i] ^ key[i % keyLen];
  }

  return QString::fromUtf8(data);
}

void Config::setAutoLaunch(bool autoLaunch) {
  m_autoLaunch = autoLaunch;
  Logger::info(QString("开机自启动设置变更: %1")
                   .arg(Logger::boolText(m_autoLaunch)));
  updateAutoLaunch(autoLaunch);
}

QString Config::autoLaunchCommand() const {
  const QString appPath =
      QDir::toNativeSeparators(QCoreApplication::applicationFilePath());
  return QString("\"%1\" --startup").arg(appPath);
}

QString Config::startupScriptPath() const {
  const QString appData = qEnvironmentVariable("APPDATA");
  if (appData.isEmpty()) {
    return QString();
  }
  return QDir::toNativeSeparators(
      appData + "\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\"
                 "HAUTNetworkGuard-Startup.vbs");
}

void Config::updateAutoLaunch(bool enable) {
  const QString command = autoLaunchCommand();
  Logger::debug(QString("更新开机自启配置: enable=%1, command=%2")
                    .arg(Logger::boolText(enable))
                    .arg(command));
  updateAutoLaunchRegistry(enable, command);
  updateAutoLaunchStartupScript(enable, command);
}

void Config::updateAutoLaunchRegistry(bool enable, const QString &command) {
#ifdef Q_OS_WIN
  QSettings bootSettings(
      "HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
      QSettings::NativeFormat);

  if (enable) {
    bootSettings.setValue("HAUTNetworkGuard", command);
    bootSettings.sync();
    QString stored;
    const bool ok = isRegistryCommandExpected(command, &stored);
    Logger::info(QString("开机自启注册表已写入 (回读: %1)")
                     .arg(ok ? "ok" : "mismatch"));
    if (!ok) {
      Logger::warn(
          QString("开机自启注册表回读不一致: expected=%1, actual=%2")
              .arg(command, stored));
    }
  } else {
    bootSettings.remove("HAUTNetworkGuard");
    bootSettings.sync();
    Logger::info("开机自启注册表项已删除");
  }
#endif
}

void Config::updateAutoLaunchStartupScript(bool enable, const QString &command) {
#ifdef Q_OS_WIN
  const QString scriptPath = startupScriptPath();
  if (scriptPath.isEmpty()) {
    Logger::warn("无法定位 Startup 目录，跳过启动脚本兜底");
    return;
  }

  QFileInfo scriptInfo(scriptPath);
  QDir dir = scriptInfo.dir();
  if (!dir.exists() && !dir.mkpath(".")) {
    Logger::warn(QString("创建 Startup 目录失败: %1").arg(dir.absolutePath()));
    return;
  }

  if (enable) {
    QFile scriptFile(scriptPath);
    if (!scriptFile.open(QIODevice::WriteOnly | QIODevice::Text |
                         QIODevice::Truncate)) {
      Logger::warn(QString("写入 Startup 脚本失败: %1")
                       .arg(scriptFile.errorString()));
      return;
    }

    QString escaped = command;
    escaped.replace("\"", "\"\"");

    QTextStream out(&scriptFile);
    out << "Set WshShell = CreateObject(\"WScript.Shell\")\r\n";
    out << "WshShell.Run \"" << escaped << "\", 0, False\r\n";
    scriptFile.close();
    Logger::info(QString("Startup 目录兜底脚本已写入: %1")
                     .arg(scriptPath));
    if (!isStartupScriptExpected(command)) {
      Logger::warn("Startup 兜底脚本写入后校验失败");
    }
  } else if (QFile::exists(scriptPath)) {
    if (QFile::remove(scriptPath)) {
      Logger::info(QString("Startup 目录兜底脚本已删除: %1").arg(scriptPath));
    } else {
      Logger::warn(QString("删除 Startup 脚本失败: %1").arg(scriptPath));
    }
  }
#endif
}

bool Config::isRegistryCommandExpected(const QString &command,
                                       QString *storedValue) const {
#ifdef Q_OS_WIN
  QSettings bootSettings(
      "HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
      QSettings::NativeFormat);
  const QString stored = bootSettings.value("HAUTNetworkGuard").toString();
  if (storedValue) {
    *storedValue = stored;
  }
  return stored.trimmed() == command.trimmed();
#else
  Q_UNUSED(command);
  Q_UNUSED(storedValue);
  return false;
#endif
}

bool Config::isStartupScriptExpected(const QString &command,
                                     QString *scriptPathOut) const {
  const QString path = startupScriptPath();
  if (scriptPathOut) {
    *scriptPathOut = path;
  }
  if (path.isEmpty() || !QFile::exists(path)) {
    return false;
  }

  QFile file(path);
  if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
    return false;
  }
  const QString content = QString::fromUtf8(file.readAll());
  QString escaped = command;
  escaped.replace("\"", "\"\"");
  return content.contains(escaped, Qt::CaseInsensitive);
}

void Config::verifyAndRepairAutoLaunch() {
  const QString command = autoLaunchCommand();
  QString storedRegistryValue;
  QString scriptPath;

  const bool registryOk =
      isRegistryCommandExpected(command, &storedRegistryValue);
  const bool startupOk = isStartupScriptExpected(command, &scriptPath);

  Logger::debug(
      QString("开机自启一致性检查: registry=%1, startup=%2, script=%3")
          .arg(Logger::boolText(registryOk))
          .arg(Logger::boolText(startupOk))
          .arg(scriptPath.isEmpty() ? "<unknown>" : scriptPath));

  if (registryOk && startupOk) {
    return;
  }

  Logger::warn(QString("检测到开机自启配置缺失或不一致，执行修复 "
                       "(registry=%1, startup=%2)")
                   .arg(Logger::boolText(registryOk))
                   .arg(Logger::boolText(startupOk)));
  updateAutoLaunch(true);
}
