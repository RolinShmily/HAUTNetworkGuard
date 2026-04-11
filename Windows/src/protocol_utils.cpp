#include "protocol_utils.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStringList>

namespace {

bool isValidIpv4(const QString &value) {
  const QStringList octets = value.split('.');
  if (octets.size() != 4) {
    return false;
  }

  for (const QString &octet : octets) {
    bool ok = false;
    const int part = octet.toInt(&ok);
    if (!ok || part < 0 || part > 255) {
      return false;
    }
  }
  return true;
}

} // namespace

QString ProtocolUtils::responsePreview(const QString &response, int maxLen) {
  QString normalized = response;
  normalized.replace('\r', ' ');
  normalized.replace('\n', ' ');
  normalized = normalized.simplified();
  if (normalized.length() > maxLen) {
    return normalized.left(maxLen) + "...";
  }
  return normalized;
}

QString ProtocolUtils::extractErrorCode(const QString &response) {
  QRegularExpression errRe("E(\\d+)");
  QRegularExpressionMatch match = errRe.match(response);
  if (match.hasMatch()) {
    return "E" + match.captured(1);
  }
  return "";
}

QString ProtocolUtils::classifyLoginResponse(const QString &response) {
  const QString body = response.trimmed();
  if (body.contains("login_ok")) {
    return "success";
  }
  if (body.contains("already_online")) {
    return "already_online";
  }
  if (body.contains("logout_ok")) {
    return "logout_ok";
  }
  if (body.contains("not_online")) {
    return "not_online";
  }
  const QString errorCode = extractErrorCode(body);
  if (!errorCode.isEmpty()) {
    return "error_" + errorCode;
  }
  if (body.isEmpty()) {
    return "empty";
  }
  return "unknown";
}

StatusParseResult ProtocolUtils::parseStatusResponse(const QString &response) {
  StatusParseResult result;
  const QString trimmed = response.trimmed();

  if (trimmed.isEmpty() || trimmed.contains("not_online")) {
    result.format = "offline";
    return result;
  }

  QString jsonStr;
  QRegularExpression jsonpRe("jQuery_\\d+\\((.+)\\)$");
  QRegularExpressionMatch match = jsonpRe.match(trimmed);
  if (match.hasMatch()) {
    jsonStr = match.captured(1);
    result.format = "jsonp";
  } else {
    jsonStr = trimmed;
    result.format = "json";
  }

  QJsonParseError parseError;
  QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8(), &parseError);
  if (doc.isObject()) {
    QJsonObject obj = doc.object();
    const QString error = obj.value("error").toString();
    if (error == "not_online_error" || error.contains("not_online")) {
      result.format = "offline";
      return result;
    }

    result.ip = obj.value("online_ip").toString();
    result.bytes = obj.value("sum_bytes").toVariant().toLongLong();
    result.seconds = obj.value("sum_seconds").toVariant().toLongLong();
    result.username = obj.value("user_name").toString();
    if (!result.username.isEmpty() || !result.ip.isEmpty()) {
      result.online = true;
      return result;
    }
  }

  QStringList parts = trimmed.split(',');
  bool secondsOk = false;
  bool bytesOk = false;
  const qint64 seconds = parts.size() >= 2 ? parts[1].toLongLong(&secondsOk)
                                           : 0;
  const qint64 bytes =
      parts.size() >= 4 ? parts[3].toLongLong(&bytesOk) : 0;
  if (parts.size() >= 4 && !parts[0].isEmpty() && secondsOk &&
      bytesOk && isValidIpv4(parts[2])) {
    result.format = "csv";
    result.username = parts[0];
    result.seconds = seconds;
    result.ip = parts[2];
    result.bytes = bytes;
    result.online = true;
    return result;
  }

  result.format = "unparsed";
  return result;
}
