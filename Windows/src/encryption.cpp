#include "encryption.h"
#include "logger.h"
#include <QCryptographicHash>

const QString Encryption::PASSWORD_KEY = "1234567890";

QString Encryption::encryptUsername(const QString &username) {
  QString encrypted;
  for (const QChar &c : username) {
    encrypted.append(QChar(c.unicode() + 4));
  }
  QString result = "{SRUN3}\r\n" + encrypted;
  Logger::debug(QString("加密用户名: user=%1 result_len=%2")
                    .arg(Logger::maskUsername(username))
                    .arg(result.length()));
  return result;
}

QString Encryption::encryptPassword(const QString &password) {
  Logger::debug(QString("加密密码: secret_len=%1").arg(password.length()));
  // SRUN3K 密码加密 (与 Rust/macOS 版本完全一致)
  // 1. XOR 加密 (密钥反向索引)
  // 2. 位分割 (低4位 + 0x36, 高4位 + 0x63)
  // 3. 奇偶交替组合

  QByteArray keyBytes = PASSWORD_KEY.toLatin1();
  int keyLen = keyBytes.size();
  QByteArray pwdBytes = password.toLatin1();

  QString result;

  for (int i = 0; i < pwdBytes.size(); ++i) {
    unsigned char c = static_cast<unsigned char>(pwdBytes[i]);

    // 密钥索引: 反向 (与 Rust 版本一致)
    int keyIndex = keyLen - 1 - (i % keyLen);
    unsigned char k = static_cast<unsigned char>(keyBytes[keyIndex]);

    // XOR 运算
    unsigned char ki = c ^ k;

    // 位分割: 低4位 + 0x36, 高4位 + 0x63
    unsigned char lowBits = (ki & 0x0F) + 0x36;
    unsigned char highBits = ((ki >> 4) & 0x0F) + 0x63;

    QChar lowChar(lowBits);
    QChar highChar(highBits);

    // 根据索引奇偶交替组合
    if (i % 2 == 0) {
      result.append(lowChar);
      result.append(highChar);
    } else {
      result.append(highChar);
      result.append(lowChar);
    }
  }

  Logger::debug(QString("加密密码结果: result_len=%1").arg(result.length()));
  return result;
}

QString Encryption::md5Hash(const QString &input) {
  return md5Hash(input.toUtf8());
}

QString Encryption::md5Hash(const QByteArray &input) {
  QByteArray hash = QCryptographicHash::hash(input, QCryptographicHash::Md5);
  return QString::fromLatin1(hash.toHex());
}
