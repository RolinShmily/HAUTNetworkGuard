#include "../src/config.h"
#include "../src/encryption.h"
#include "../src/logger.h"
#include "../src/protocol_utils.h"
#include <QCoreApplication>
#include <QDebug>
#include <QSettings>
#include <cstdlib>

namespace {

[[noreturn]] void fail(const QString &message) {
  qCritical().noquote() << message;
  std::exit(1);
}

void expect(bool condition, const QString &message) {
  if (!condition) {
    fail(message);
  }
}

} // namespace

int main(int argc, char *argv[]) {
  QCoreApplication app(argc, argv);
  app.setOrganizationName("YellowPeach");
  app.setApplicationName("HAUTNetworkGuard-SmokeTests");

  expect(Encryption::encryptUsername("231040600203") ==
             "{SRUN3}\r\n675484:44647",
         "用户名加密向量不匹配");
  expect(Encryption::encryptPassword("password123") == "6gh>Agg:7gh@<gh=9cc99c",
         "密码加密向量不匹配");
  expect(Logger::maskUsername("231040600203") != "231040600203",
         "用户名脱敏失败");
  expect(ProtocolUtils::classifyLoginResponse(
             "login_error#E2531:User not found") == "error_E2531",
         "登录响应分类不匹配");

  const StatusParseResult jsonResult = ProtocolUtils::parseStatusResponse(
      "jQuery_1712630100000({\"error\":\"ok\",\"user_name\":\"231040600203\","
      "\"online_ip\":\"10.10.0.8\",\"sum_bytes\":12345678,"
      "\"sum_seconds\":321})");
  expect(jsonResult.online, "JSONP 状态解析应判定为在线");
  expect(jsonResult.format == "jsonp", "JSONP 状态解析格式不匹配");
  expect(jsonResult.ip == "10.10.0.8", "JSONP 状态解析 IP 不匹配");
  expect(jsonResult.bytes == 12345678, "JSONP 状态解析流量不匹配");
  expect(jsonResult.seconds == 321, "JSONP 状态解析时长不匹配");

  const StatusParseResult csvResult = ProtocolUtils::parseStatusResponse(
      "231040600203,321,10.10.0.8,12345678,0,0");
  expect(csvResult.online, "CSV 状态解析应判定为在线");
  expect(csvResult.format == "csv", "CSV 状态解析格式不匹配");

  const StatusParseResult invalidCsvResult =
      ProtocolUtils::parseStatusResponse("oops,NaN,not-an-ip,garbage");
  expect(!invalidCsvResult.online, "异常 CSV 响应不应判定为在线");
  expect(invalidCsvResult.format == "unparsed",
         "异常 CSV 响应应标记为 unparsed");

  QSettings settings("HAUTNetworkGuard", "HAUTNetworkGuard");
  settings.clear();
  settings.sync();

  Config &config = Config::instance();
  config.setUsername("231040600203");
  config.setPassword("password123");
  config.setAutoSave(false);
  config.setAutoLaunch(false);
  config.setAutoLogin(true);
  config.setHasConfigured(true);
  config.setCheckInterval(45);
  config.save();

  settings.sync();
  expect(settings.value("password").toString().isEmpty(),
         "未勾选记住密码时不应持久化密码");

  config.setAutoSave(true);
  config.save();
  settings.sync();
  expect(!settings.value("password").toString().isEmpty(),
         "勾选记住密码后应持久化密码");

  settings.clear();
  settings.sync();
  qInfo().noquote() << "windows smoke tests passed";
  return 0;
}
