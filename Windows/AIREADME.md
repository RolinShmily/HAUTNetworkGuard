# HAUT Network Guard - AI 技术文档 (Windows Qt)

> 本文件用于后续开发快速理解当前 Windows 版本实现。内容已对齐 `v1.3.18`。

## 项目概述

HAUT Network Guard Windows 版本使用 `Qt 6 + C++17` 实现，是当前正式维护的 Windows 客户端。

### 当前版本

- **版本号**: 1.3.18
- **最后更新**: 2026-04
- **构建**: CMake + MSVC + GitHub Actions

## 当前实现

### 技术栈

| 组件 | 技术 | 说明 |
|------|------|------|
| GUI | Qt Widgets | 主窗口 + 系统托盘 |
| HTTP | QNetworkAccessManager | 登录/注销/状态检查 |
| 配置 | QSettings | 凭据、自动登录、开机自启、检测间隔 |
| 日志 | 自定义 Logger | 文件日志 + 级别控制 + 脱敏 |

### 固定端点

- 状态检查: `http://172.16.154.130/cgi-bin/rad_user_info`
- 登录/注销: `http://172.16.154.130:69/cgi-bin/srun_portal`

### 关键模块

- `src/main.cpp`
  - 应用入口
  - 支持 `--startup` 静默托盘启动
- `src/mainwindow.cpp`
  - UI、状态展示、自动登录触发
- `src/api.cpp`
  - 请求发送、响应分类、请求级日志
- `src/protocol_utils.cpp`
  - 登录响应分类
  - JSONP/CSV 状态解析
- `src/config.cpp`
  - `QSettings` 存储
  - 注册表 `Run` 主链路 + Startup 目录兜底脚本
- `src/logger.cpp`
  - 文件日志
  - `HAUT_LOG_LEVEL` 级别控制
  - 用户名脱敏

## 当前行为约定

### 自动登录

- 启动后延迟检测状态
- 检测离线时触发自动登录
- 已有登录流程进行中时不重复触发
- 按检测间隔做最短冷却，默认最少 60 秒

### 开机自启

- 主路径: `HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run`
- 兜底路径:
  - `%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\HAUTNetworkGuard-Startup.vbs`
- 启动参数:
  - `--startup`

### 凭据存储

- 用户名始终持久化
- 密码仅在 `记住密码` 开启时持久化
- 未开启时仅保留当前会话内存密码

## 调试与排障

日志位于 `AppDataLocation/app.log`。

请求日志字段统一遵循:

- `action`
- `phase`
- `class`
- `elapsed_ms`
- `account`

脱敏规则:

- 用户名长度 `<= 4`: 全部替换为 `*`
- 长度 `> 4`: 保留前 2 位和后 2 位

## 构建与发布

### 本地构建

```bash
cd Windows
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

### 云端构建

- GitHub Actions 工作流: `.github/workflows/build.yml`
- 触发方式: 推送 `v*` tag
- 质量门禁:
  - `haut_smoke_tests`
- 发布产物:
  - `HAUTNetworkGuard-Windows.zip`

## 后续开发注意事项

1. 不要改动 `SRUN3K` 加密算法语义，任何修改都必须同步 fixture 与 contract tests。
2. 涉及自动登录、自启动、凭据存储的修改，优先保持日志字段一致。
3. 用户可见行为变更后，同步更新主 README、Release 说明与本文件。
