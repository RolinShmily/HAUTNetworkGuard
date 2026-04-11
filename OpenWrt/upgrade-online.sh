#!/bin/sh
# HAUT Network Guard - OpenWrt 一键升级脚本
# 用法:
#   最新 main: wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/OpenWrt/upgrade-online.sh | sh
#   固定版本:   wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/v1.3.15/OpenWrt/upgrade-online.sh | sh -s -- v1.3.15

set -e

REPO_REF="${1:-main}"
REPO_URL="https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/${REPO_REF}/OpenWrt"
INSTALL_DIR="/usr/lib/haut-network-guard"
MAIN_LUA="$INSTALL_DIR/main.lua"

download_file() {
    url="$1"
    dest="$2"
    tmp="${dest}.tmp"

    curl -fsSL "$url" -o "$tmp"
    mv "$tmp" "$dest"
}

echo "=========================================="
echo "  HAUT Network Guard - OpenWrt 升级检查"
echo "=========================================="
echo ""
echo "源版本: $REPO_REF"
echo ""

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 root 权限运行"
    exit 1
fi

# 获取本地版本
LOCAL_VERSION="未安装"
if [ -f "$MAIN_LUA" ]; then
    LOCAL_VERSION=$(grep -o 'VERSION = "[^"]*"' "$MAIN_LUA" 2>/dev/null | grep -o '"[^"]*"' | tr -d '"')
    [ -z "$LOCAL_VERSION" ] && LOCAL_VERSION="未知"
fi
echo "本地版本: $LOCAL_VERSION"

# 获取远端版本
echo "正在检查最新版本..."
REMOTE_MAIN=$(curl -fsSL --connect-timeout 10 "$REPO_URL/files/usr/lib/haut-network-guard/main.lua")
if [ -z "$REMOTE_MAIN" ]; then
    echo "错误: 无法连接到 GitHub，请检查网络"
    exit 1
fi

REMOTE_VERSION=$(echo "$REMOTE_MAIN" | grep -o 'VERSION = "[^"]*"' | grep -o '"[^"]*"' | tr -d '"')
if [ -z "$REMOTE_VERSION" ]; then
    echo "错误: 无法解析远端版本号"
    exit 1
fi
echo "最新版本: $REMOTE_VERSION"
echo ""

# 比较版本
if [ "$LOCAL_VERSION" = "$REMOTE_VERSION" ]; then
    echo "当前已是最新版本，无需升级。"
    exit 0
fi

if [ "$LOCAL_VERSION" = "未安装" ]; then
    echo "未检测到安装，请先运行安装脚本。"
    exit 1
fi

echo "发现新版本: $LOCAL_VERSION -> $REMOTE_VERSION"
echo "正在升级..."
echo ""

# 停止服务
echo "[1/4] 停止服务..."
/etc/init.d/haut-network-guard stop 2>/dev/null || true

# 下载新文件（不覆盖配置）
echo "[2/4] 下载程序文件..."
download_file "$REPO_URL/files/usr/lib/haut-network-guard/crypto.lua" "$INSTALL_DIR/crypto.lua"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/api.lua" "$INSTALL_DIR/api.lua"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/log.lua" "$INSTALL_DIR/log.lua"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/protocol.lua" "$INSTALL_DIR/protocol.lua"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/main.lua" "$INSTALL_DIR/main.lua"

echo "[3/4] 更新服务脚本..."
download_file "$REPO_URL/files/etc/init.d/haut-network-guard" "/etc/init.d/haut-network-guard"
chmod +x /etc/init.d/haut-network-guard

# 重启服务
echo "[4/4] 重启服务..."
/etc/init.d/haut-network-guard start

echo ""
echo "=========================================="
echo "  升级完成! ($LOCAL_VERSION -> $REMOTE_VERSION)"
echo "=========================================="
echo ""
echo "配置文件已保留，无需重新配置。"
echo "查看日志: logread | grep haut-network-guard"
echo ""
