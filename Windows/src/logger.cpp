#include "logger.h"
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QTextStream>

Logger &Logger::instance() {
  static Logger inst;
  return inst;
}

Logger::Logger() {}

QString Logger::logFilePath() const {
  QString dir =
      QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
  QDir().mkpath(dir);
  return dir + "/app.log";
}

void Logger::rotate() {
  QString path = logFilePath();
  QFileInfo fi(path);
  if (fi.exists() && fi.size() > MAX_LOG_SIZE) {
    QString oldPath = path + ".old";
    QFile::remove(oldPath);
    QFile::rename(path, oldPath);
  }
}

void Logger::write(Level level, const QString &msg) {
  QMutexLocker locker(&m_mutex);

  static const char *labels[] = {"DEBUG", "INFO", "WARN", "ERROR"};

  rotate();

  QFile file(logFilePath());
  if (!file.open(QIODevice::Append | QIODevice::Text))
    return;

  QTextStream out(&file);
  QString timestamp =
      QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss");
  out << "[" << timestamp << "] [" << labels[level] << "] " << msg << "\n";
}

void Logger::debug(const QString &msg) { instance().write(DEBUG, msg); }
void Logger::info(const QString &msg) { instance().write(INFO, msg); }
void Logger::warn(const QString &msg) { instance().write(WARN, msg); }
void Logger::error(const QString &msg) { instance().write(ERROR, msg); }
