#include "api.h"
#include "encryption.h"
#include "logger.h"
#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QUrl>
#include <QUrlQuery>

const QString Api::STATUS_URL = "http://172.16.154.130/cgi-bin/rad_user_info";
const QString Api::LOGIN_URL = "http://172.16.154.130:69/cgi-bin/srun_portal";

Api::Api(QObject *parent)
    : QObject(parent), m_networkManager(new QNetworkAccessManager(this)) {}

Api::~Api() {}

QString Api::percentEncode(const QString &value) {
  QByteArray utf8 = value.toUtf8();
  QString result;
  for (int i = 0; i < utf8.size(); ++i) {
    unsigned char c = static_cast<unsigned char>(utf8[i]);
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') || c == '-' || c == '.' || c == '_' ||
        c == '~') {
      result.append(QChar(c));
    } else {
      result.append(QString("%%1").arg(c, 2, 16, QChar('0')).toUpper());
    }
  }
  return result;
}

quint64 Api::trackReply(QNetworkReply *reply, const QString &action) {
  if (!reply)
    return 0;
  const quint64 requestId = ++m_nextRequestId;
  m_requestIds.insert(reply, requestId);
  m_requestStartMs.insert(reply, QDateTime::currentMSecsSinceEpoch());
  m_requestActions.insert(reply, action);
  return requestId;
}

void Api::finishTrackedReply(QNetworkReply *reply, quint64 *requestId,
                             QString *action, qint64 *elapsedMs) {
  quint64 id = 0;
  QString act = "unknown";
  qint64 elapsed = -1;

  if (reply) {
    id = m_requestIds.take(reply);
    act = m_requestActions.take(reply);
    const qint64 startedAt = m_requestStartMs.take(reply);
    if (startedAt > 0) {
      elapsed = QDateTime::currentMSecsSinceEpoch() - startedAt;
    }
  }

  if (requestId)
    *requestId = id;
  if (action)
    *action = act;
  if (elapsedMs)
    *elapsedMs = elapsed;
}

QString Api::responsePreview(const QString &response, int maxLen) {
  QString normalized = response;
  normalized.replace('\r', ' ');
  normalized.replace('\n', ' ');
  normalized = normalized.simplified();
  if (normalized.length() > maxLen) {
    return normalized.left(maxLen) + "...";
  }
  return normalized;
}

QString Api::extractErrorCode(const QString &response) {
  QRegularExpression errRe("E(\\d+)");
  QRegularExpressionMatch match = errRe.match(response);
  if (match.hasMatch()) {
    return "E" + match.captured(1);
  }
  return "";
}

void Api::login(const QString &username, const QString &password) {
  QString encUsername = Encryption::encryptUsername(username);
  QString encPassword = Encryption::encryptPassword(password);

  // 手动拼接 POST body，使用自定义 percentEncode 确保特殊字符被正确编码
  QString body = "action=login"
                 "&username=" +
                 percentEncode(encUsername) + "&password=" +
                 percentEncode(encPassword) + "&ac_id=1"
                                              "&drop=0"
                                              "&pop=1"
                                              "&type=10"
                                              "&n=117"
                                              "&mbytes=0"
                                              "&minutes=0"
                                              "&mac=02%3A00%3A00%3A00%3A00%3A00";

  QUrl loginUrl(LOGIN_URL);
  QNetworkRequest request(loginUrl);
  request.setHeader(QNetworkRequest::ContentTypeHeader,
                    "application/x-www-form-urlencoded");
  request.setHeader(QNetworkRequest::UserAgentHeader,
                    "HAUTNetworkGuard/1.3.13 Qt");
  request.setTransferTimeout(10000);

  Logger::debug(QString("登录参数摘要: 用户=%1, 用户名长度=%2, 密码长度=%3, "
                        "encUserLen=%4, encPwdLen=%5")
                    .arg(Logger::maskUsername(username))
                    .arg(username.length())
                    .arg(password.length())
                    .arg(encUsername.length())
                    .arg(encPassword.length()));

  QNetworkReply *reply = m_networkManager->post(request, body.toUtf8());
  const quint64 requestId = trackReply(reply, "login");
  Logger::info(QString("[req:%1] 登录请求已发送").arg(requestId));
  connect(reply, &QNetworkReply::finished, this, &Api::onLoginReplyFinished);
}

void Api::logout() {
  QString body = "action=logout";

  QUrl logoutUrl(LOGIN_URL);
  QNetworkRequest request(logoutUrl);
  request.setHeader(QNetworkRequest::ContentTypeHeader,
                    "application/x-www-form-urlencoded");
  request.setHeader(QNetworkRequest::UserAgentHeader,
                    "HAUTNetworkGuard/1.3.13 Qt");
  request.setTransferTimeout(10000);

  QNetworkReply *reply = m_networkManager->post(request, body.toUtf8());
  const quint64 requestId = trackReply(reply, "logout");
  Logger::info(QString("[req:%1] 注销请求已发送").arg(requestId));
  connect(reply, &QNetworkReply::finished, this, &Api::onLogoutReplyFinished);
}

void Api::checkStatus() {
  if (m_statusCheckInFlight) {
    Logger::debug("跳过状态检测：上一个状态请求尚未完成");
    return;
  }

  // 使用 JSONP callback 格式获取 JSON 响应 (与 OpenWrt 一致)
  qint64 timestamp = QDateTime::currentMSecsSinceEpoch();
  QString callback = QString("jQuery_%1").arg(timestamp);

  QUrl url(STATUS_URL);
  QUrlQuery query;
  query.addQueryItem("callback", callback);
  query.addQueryItem("_", QString::number(timestamp));
  url.setQuery(query);

  QNetworkRequest request(url);
  request.setHeader(QNetworkRequest::UserAgentHeader,
                    "HAUTNetworkGuard/1.3.13 Qt");
  request.setTransferTimeout(5000);

  QNetworkReply *reply = m_networkManager->get(request);
  m_statusCheckInFlight = true;
  const quint64 requestId = trackReply(reply, "status");
  Logger::debug(QString("[req:%1] 状态请求已发送: %2")
                    .arg(requestId)
                    .arg(url.toString()));
  connect(reply, &QNetworkReply::finished, this, &Api::onStatusReplyFinished);
}

void Api::onLoginReplyFinished() {
  QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
  if (!reply)
    return;

  quint64 requestId = 0;
  QString action;
  qint64 elapsedMs = -1;
  finishTrackedReply(reply, &requestId, &action, &elapsedMs);
  reply->deleteLater();

  if (reply->error() != QNetworkReply::NoError) {
    Logger::error(QString("[req:%1][%2] 网络错误: %3 (耗时: %4 ms)")
                      .arg(requestId)
                      .arg(action)
                      .arg(reply->errorString())
                      .arg(elapsedMs));
    emit loginFailed(QString("网络错误: %1").arg(reply->errorString()));
    return;
  }

  QString response = QString::fromUtf8(reply->readAll());
  const QString errCode = extractErrorCode(response);
  Logger::info(QString("[req:%1][%2] 响应成功 (耗时: %3 ms, 错误码: %4)")
                   .arg(requestId)
                   .arg(action)
                   .arg(elapsedMs)
                   .arg(errCode.isEmpty() ? "none" : errCode));
  Logger::debug(QString("[req:%1] 登录响应预览: %2")
                    .arg(requestId)
                    .arg(responsePreview(response)));

  // 检查登录结果 (与 Rust 版本一致)
  if (response.contains("login_ok") || response.contains("already_online")) {
    emit loginSuccess("登录成功");
  } else {
    QString error = "登录失败";
    if (!errCode.isEmpty()) {
      error = QString("登录失败 (错误码: %1)").arg(errCode);
    }
    if (!response.isEmpty() && response.length() < 200) {
      error = response;
    }
    emit loginFailed(error);
  }
}

void Api::onLogoutReplyFinished() {
  QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
  if (!reply)
    return;

  quint64 requestId = 0;
  QString action;
  qint64 elapsedMs = -1;
  finishTrackedReply(reply, &requestId, &action, &elapsedMs);
  reply->deleteLater();

  if (reply->error() != QNetworkReply::NoError) {
    Logger::error(QString("[req:%1][%2] 网络错误: %3 (耗时: %4 ms)")
                      .arg(requestId)
                      .arg(action)
                      .arg(reply->errorString())
                      .arg(elapsedMs));
    emit logoutFailed(QString("网络错误: %1").arg(reply->errorString()));
    return;
  }

  QString response = QString::fromUtf8(reply->readAll());
  Logger::info(QString("[req:%1][%2] 响应成功 (耗时: %3 ms)")
                   .arg(requestId)
                   .arg(action)
                   .arg(elapsedMs));
  Logger::debug(QString("[req:%1] 注销响应预览: %2")
                    .arg(requestId)
                    .arg(responsePreview(response)));

  if (response.contains("logout_ok") || response.contains("not_online")) {
    emit logoutSuccess();
  } else {
    emit logoutFailed("注销失败");
  }
}

void Api::onStatusReplyFinished() {
  QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
  if (!reply)
    return;

  quint64 requestId = 0;
  QString action;
  qint64 elapsedMs = -1;
  finishTrackedReply(reply, &requestId, &action, &elapsedMs);
  m_statusCheckInFlight = false;
  reply->deleteLater();

  if (reply->error() != QNetworkReply::NoError) {
    Logger::warn(QString("[req:%1][%2] 状态请求失败: %3 (耗时: %4 ms)")
                     .arg(requestId)
                     .arg(action)
                     .arg(reply->errorString())
                     .arg(elapsedMs));
    emit statusChecked(false, "", 0, 0);
    return;
  }

  QString response = QString::fromUtf8(reply->readAll());
  Logger::debug(QString("[req:%1] 状态响应长度: %2 bytes, 耗时: %3 ms, 预览: %4")
                    .arg(requestId)
                    .arg(response.toUtf8().size())
                    .arg(elapsedMs)
                    .arg(responsePreview(response)));

  if (response.isEmpty() || response.contains("not_online")) {
    emit statusChecked(false, "", 0, 0);
    return;
  }

  QString jsonStr;
  QRegularExpression jsonpRe("jQuery_\\d+\\((.+)\\)$");
  QRegularExpressionMatch match = jsonpRe.match(response.trimmed());
  if (match.hasMatch()) {
    jsonStr = match.captured(1);
  } else {
    jsonStr = response;
  }

  QJsonParseError parseError;
  QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8(), &parseError);
  if (doc.isObject()) {
    QJsonObject obj = doc.object();
    QString error = obj.value("error").toString();
    if (error == "not_online_error" || error.contains("not_online")) {
      emit statusChecked(false, "", 0, 0);
      return;
    }

    QString ip = obj.value("online_ip").toString();
    qint64 bytes = obj.value("sum_bytes").toVariant().toLongLong();
    qint64 seconds = obj.value("sum_seconds").toVariant().toLongLong();
    QString username = obj.value("user_name").toString();

    if (!username.isEmpty() || !ip.isEmpty()) {
      Logger::debug(QString("[req:%1] JSON 状态解析成功: user=%2 ip=%3 "
                            "bytes=%4 seconds=%5")
                        .arg(requestId)
                        .arg(Logger::maskUsername(username))
                        .arg(ip)
                        .arg(bytes)
                        .arg(seconds));
      emit statusChecked(true, ip, bytes, seconds);
      return;
    }
  }

  QStringList parts = response.split(',');
  if (parts.size() >= 4) {
    QString username = parts[0];
    qint64 seconds = parts[1].toLongLong();
    QString ip = parts[2];
    qint64 bytes = parts[3].toLongLong();

    Logger::debug(QString("[req:%1] CSV 状态解析成功: user=%2 ip=%3 bytes=%4 "
                          "seconds=%5")
                      .arg(requestId)
                      .arg(Logger::maskUsername(username))
                      .arg(ip)
                      .arg(bytes)
                      .arg(seconds));
    emit statusChecked(true, ip, bytes, seconds);
  } else {
    Logger::warn(
        QString("[req:%1] 状态响应无法解析，回退为离线").arg(requestId));
    emit statusChecked(false, "", 0, 0);
  }
}
