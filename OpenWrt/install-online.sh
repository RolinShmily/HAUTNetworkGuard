#!/bin/sh
# HAUT Network Guard - OpenWrt 一键安装脚本
# 用法:
#   最新 main: wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/OpenWrt/install-online.sh | sh
#   固定版本:   wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/v1.3.14/OpenWrt/install-online.sh | sh -s -- v1.3.14

set -e

REPO_REF="${1:-main}"
REPO_URL="https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/${REPO_REF}/OpenWrt"
INSTALL_DIR="/usr/lib/haut-network-guard"

download_file() {
    url="$1"
    dest="$2"
    tmp="${dest}.tmp"

    curl -fsSL "$url" -o "$tmp"
    mv "$tmp" "$dest"
}

echo "=========================================="
echo "  HAUT Network Guard - OpenWrt 一键安装"
echo "=========================================="
echo ""
echo "源版本: $REPO_REF"
echo ""

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 root 权限运行"
    exit 1
fi

# 安装依赖
echo "[1/5] 安装依赖..."
opkg update >/dev/null 2>&1 || true
opkg install lua curl >/dev/null 2>&1 || {
    echo "警告: 部分依赖可能已安装"
}

# 创建目录
echo "[2/5] 创建目录..."
mkdir -p "$INSTALL_DIR"

# 下载文件
echo "[3/5] 下载程序文件..."
download_file "$REPO_URL/files/usr/lib/haut-network-guard/crypto.lua" "$INSTALL_DIR/crypto.lua"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/api.lua" "$INSTALL_DIR/api.lua"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/log.lua" "$INSTALL_DIR/log.lua"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/main.lua" "$INSTALL_DIR/main.lua"

echo "[4/5] 下载配置文件..."
download_file "$REPO_URL/files/etc/init.d/haut-network-guard" "/etc/init.d/haut-network-guard"
download_file "$REPO_URL/files/etc/config/haut-network-guard" "/etc/config/haut-network-guard"

# 设置权限
echo "[5/5] 设置权限..."
chmod +x /etc/init.d/haut-network-guard
chmod 600 /etc/config/haut-network-guard

# 启用服务
/etc/init.d/haut-network-guard enable >/dev/null 2>&1

echo ""
echo "=========================================="
echo "  安装完成! (v1.3.14)"
echo "=========================================="
echo ""
echo "下一步 - 配置账号:"
echo ""
echo "  uci set haut-network-guard.main.username='你的学号'"
echo "  uci set haut-network-guard.main.password='你的密码'"
echo "  uci commit haut-network-guard"
echo "  /etc/init.d/haut-network-guard start"
echo ""
echo "查看日志: logread | grep haut-network-guard"
echo ""
