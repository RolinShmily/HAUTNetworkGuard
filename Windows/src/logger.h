#ifndef LOGGER_H
#define LOGGER_H

#include <QMutex>
#include <QString>

class Logger {
public:
  enum Level { DEBUG, INFO, WARN, ERROR };

  static Logger &instance();

  static void debug(const QString &msg);
  static void info(const QString &msg);
  static void warn(const QString &msg);
  static void error(const QString &msg);

private:
  Logger();
  void write(Level level, const QString &msg);
  void rotate();
  QString logFilePath() const;

  QMutex m_mutex;
  static const qint64 MAX_LOG_SIZE = 1024 * 1024; // 1MB
};

#endif // LOGGER_H
