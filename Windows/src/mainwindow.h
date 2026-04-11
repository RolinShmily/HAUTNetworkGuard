#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QCheckBox>
#include <QCloseEvent>
#include <QLabel>
#include <QLineEdit>
#include <QMainWindow>
#include <QPushButton>
#include <QSpinBox>
#include <QTimer>

#include "api.h"
#include "trayicon.h"

class MainWindow : public QMainWindow {
  Q_OBJECT

public:
  explicit MainWindow(QWidget *parent = nullptr);
  ~MainWindow();

protected:
  void closeEvent(QCloseEvent *event) override;

private slots:
  void onLoginClicked();
  void onLogoutClicked();
  void onSaveClicked();

  void onLoginSuccess(const QString &message);
  void onLoginFailed(const QString &error);
  void onLogoutSuccess(const QString &resultClass);
  void onLogoutFailed(const QString &error);
  void onStatusChecked(bool online, const QString &resultClass,
                       const QString &ip, qint64 bytesUsed,
                       qint64 secondsOnline);

  void checkNetworkStatus();
  void showWindow();
  void exitApplication();
  void tryAutoLogin();

private:
  void setupUi();
  void loadSettings();
  void saveSettings();
  void syncCredentialsToConfig();
  void triggerAutoLoginIfPossible(const QString &reason);
  void refreshActionState();
  void updateStatusDisplay(bool online, const QString &ip = "",
                           qint64 bytes = 0, qint64 seconds = 0);
  QString formatBytes(qint64 bytes);
  QString formatTime(qint64 seconds);

  // UI 组件
  QWidget *m_centralWidget;
  QLabel *m_statusLabel;
  QLabel *m_ipLabel;
  QLabel *m_usageLabel;
  QLabel *m_timeLabel;
  QLineEdit *m_usernameEdit;
  QLineEdit *m_passwordEdit;
  QCheckBox *m_autoSaveCheck;
  QCheckBox *m_autoLaunchCheck;
  QCheckBox *m_autoLoginCheck;
  QSpinBox *m_intervalSpinBox;
  QPushButton *m_loginBtn;
  QPushButton *m_logoutBtn;
  QPushButton *m_saveBtn;

  // 功能组件
  Api *m_api;
  TrayIcon *m_trayIcon;
  QTimer *m_statusTimer;

  bool m_isOnline = false;
  bool m_startupLoginAttempted = false;
  bool m_isLoggingIn = false;
  bool m_isLoggingOut = false;
  bool m_isManualLogin = false;
  bool m_manualOfflineHold = false;
  qint64 m_lastAutoLoginAttemptMs = 0;
  int m_autoLoginRetryIntervalMs = 60000; // 最短 60 秒重试一次
};

#endif // MAINWINDOW_H
