# HAUTNetworkGuard 基线与下一阶段方案

日期: 2026-04-11
状态: Phase A-D 收口进行中，当前工作树目标版本为 `v1.3.15`

## 1. 当前基线

- 当前工作树目标版本: `v1.3.15`
- 本轮开始时远端最新已发布版本: `v1.3.14`
- 最近一次已确认的远端 Release:
  - <https://github.com/yellowpeachxgp/HAUTNetworkGuard/releases/tag/v1.3.14>
- 待本轮收口后验证的工作流:
  - `validate-openwrt`
  - `build-windows-qt`
  - `build-macos`
  - `release`
- macOS 本地构建已验证通过:
  - `macOS/build/HAUTNetworkGuard.app`

本轮已确认的问题闭环:

- OpenWrt 自动登录在特定固件下循环报 `login_error#E2531:User not found`
- Windows 开机自启动失效
- Windows 未勾选记住密码仍持久化
- 三端调试日志不足
- Release 页面 OpenWrt 安装链路与版本 tag 漂移
- GitHub Actions 缺少 OpenWrt 基础脚本校验

## 2. 仓库结构

### 2.1 主目录

- `macOS/`: Swift 菜单栏应用
- `Windows/`: Qt 6 Widgets 桌面应用
- `OpenWrt/`: Lua + procd 守护进程
- `.github/workflows/`: GitHub Actions 构建发布
- `Windows-Rust-Deprecated/`: 已弃用的旧实现，仅作历史参考

### 2.2 代码规模快照

- 总计约 `5691` 行主代码/脚本/文档
- Windows 核心:
  - `Windows/src/mainwindow.cpp`: `431` 行
  - `Windows/src/api.cpp`: `350` 行
  - `Windows/src/config.cpp`: `264` 行
- macOS 核心:
  - `macOS/Sources/StatusBarController.swift`: `446` 行
  - `macOS/Sources/SrunAPI.swift`: `433` 行
  - `macOS/Sources/UpdateWindow.swift`: `297` 行
- OpenWrt 核心:
  - `OpenWrt/files/usr/lib/haut-network-guard/main.lua`: `284` 行
  - `OpenWrt/files/usr/lib/haut-network-guard/api.lua`: `276` 行
  - `OpenWrt/files/usr/lib/haut-network-guard/log.lua`: `90` 行

## 3. 三端实现现状

### 3.1 Windows

关键文件:

- `Windows/src/main.cpp`
- `Windows/src/mainwindow.cpp`
- `Windows/src/api.cpp`
- `Windows/src/config.cpp`
- `Windows/src/logger.cpp`
- `Windows/src/protocol_utils.cpp`
- `Windows/src/trayicon.cpp`

当前实现特点:

- Qt 6 + `QNetworkAccessManager` 异步请求
- `QSettings` 存储配置
- 登录、注销、状态检查均已带请求级日志
- 自动登录增加并发保护和退避
- 开机自启采用注册表 `Run` + Startup 目录 `vbs` 兜底

当前状态判断:

- 功能面已经可用，属于当前三端里结构最清晰的一端
- 仍有技术债未清理:
  - 加密与网络协议逻辑与其他平台重复维护
  - UI、状态机、网络层耦合在 `MainWindow`
  - 日志脱敏仍需二次排查，避免边角路径泄漏原始账号

### 3.2 macOS

关键文件:

- `macOS/Sources/AppDelegate.swift`
- `macOS/Sources/StatusBarController.swift`
- `macOS/Sources/Logger.swift`
- `macOS/Sources/SrunProtocol.swift`
- `macOS/Sources/SrunAPI.swift`
- `macOS/Sources/DirectHTTPClient.swift`
- `macOS/Sources/LaunchManager.swift`
- `macOS/Sources/SettingsWindow.swift`

当前实现特点:

- 菜单栏应用，无常驻 Dock 窗口依赖
- 自定义 `DirectHTTPClient` 通过物理接口直连，绕过代理/TUN
- `LaunchManager` 使用 LaunchAgent 管理开机自启
- 更新检测与更新窗口已经成体系
- 自动登录逻辑已具备启动、掉线、离线重试三类触发

当前状态判断:

- 功能相对完整，是三端里“用户体验最完整”的一端
- 仍有技术债未清理:
  - 协议、日志、状态机仍是平台内局部拆分，尚未抽到共享规范层
  - 配置、UI、监控调度仍偏单体
  - 文档远落后于代码现状

### 3.3 OpenWrt

关键文件:

- `OpenWrt/files/usr/lib/haut-network-guard/main.lua`
- `OpenWrt/files/usr/lib/haut-network-guard/api.lua`
- `OpenWrt/files/usr/lib/haut-network-guard/log.lua`
- `OpenWrt/files/usr/lib/haut-network-guard/protocol.lua`
- `OpenWrt/files/etc/init.d/haut-network-guard`
- `OpenWrt/install-online.sh`

当前实现特点:

- procd 守护进程 + UCI 配置
- 每轮循环重读配置并做清洗
- 登录请求使用临时文件 + `curl --data-binary`
- 自动重连已有连续失败退避
- 日志支持级别刷新、配置快照、请求摘要与响应预览

当前状态判断:

- 已修复最关键的现场兼容问题
- 仍有技术债未清理:
  - 仍以 shell + curl 方式组装 HTTP，请求可靠性与可测试性一般
  - 升级/卸载链路仍偏脚本化，缺少统一版本治理
  - 行为级测试基本为空

## 4. 文档与流程现状

### 4.1 已经可靠的部分

- `README.md` 的版本历史已经覆盖到 `v1.3.15`
- `.github/workflows/build.yml` 已补齐 OpenWrt contract 校验、Windows smoke tests 与 macOS smoke tests
- macOS 本地 smoke tests、构建与代码签名验证已完成

### 4.2 明显过期或失真的部分

- 已在 `v1.3.15` 修正主 README、OpenWrt README 与平台 AIREADME 的主要失真内容
- 仍需后续维护文档与代码同步，避免再次漂移

## 5. 当前工程风险

### 5.1 高优先级

- 三端仍是重复实现，缺少真正共享的运行时代码
- 回归保障已补到 contract 测试层，但行为级测试仍不充分
- 本地 git transport 环境异常，导致“本地对象库精确对齐远端 commit”不稳定

### 5.2 中优先级

- 本地 git transport 环境仍不稳定
- 三端日志字段已完成第一轮统一，但还没有完全共享实现
- Windows/macOS 已有 smoke tests，但行为级回归仍不充分

### 5.3 低优先级

- 目录层级还没有统一的 `docs/` 治理规范
- Windows-Rust-Deprecated 仍保留较多历史产物

## 6. 下一阶段开发方案

`v1.3.15` 当前处于第一轮 Phase A-D 收口尾声，建议在发布后转入第二轮增量治理与真实环境复测。

### 阶段 A: 环境与治理收口

目标:

- 修正文档失真
- 清理仓库卫生问题
- 统一下一阶段开发基线

任务:

- 修订主 README、OpenWrt README、平台 AIREADME
- 处理被追踪的历史二进制和无关构建产物
- 统一版本/资产命名说明
- 解决本地 GitHub 远端同步链路异常

交付:

- 文档基线可信
- 仓库更干净
- 后续开发不再被错误说明误导

### 阶段 B: 协议与日志统一

目标:

- 把三端“协议实现一致性”和“日志字段一致性”拉齐

任务:

- 抽出一套跨平台 SRUN3K 协议行为说明
- 统一状态检查、登录、注销三类日志字段:
  - request id
  - action
  - elapsed ms
  - response classification
  - masked account
- 检查并修复日志脱敏漏洞

交付:

- 三端日志可以互相对照排障
- 协议问题不再靠人工比对三套代码猜测

### 阶段 C: 回归保障

目标:

- 把当前“靠现场验证”的模式升级到“本地/CI 可提前发现回归”

任务:

- Windows:
  - 凭据保存/不保存分支测试
  - 自动登录冷却与状态请求并发保护测试
- macOS:
  - 版本比较、更新检测、自动登录节流逻辑测试
  - LaunchAgent 生成内容校验
- OpenWrt:
  - UCI 配置清洗测试
  - 登录响应分类测试
  - 升级/安装脚本 smoke test

交付:

- 发布前的回归面更清晰
- 新增需求不易打坏已有修复

### 阶段 D: 架构演进

目标:

- 降低三端重复维护成本

任务:

- 先抽象协议文档和共享测试样例
- 再逐步抽离“响应分类/字段映射/错误码规则”为共享规范
- 重构 Windows `MainWindow` 与 macOS `StatusBarController` 的状态机边界

交付:

- 后续新增功能可以三端同步推进
- 排障成本和重构风险下降

## 7. 推荐的立即执行顺序

建议下一轮开发按下面顺序直接开工:

1. 真实环境复测:
   - OpenWrt `R23.1.1 / LuCI Master`
   - Windows 开机自启
   - macOS LaunchAgent 与断线重连
2. 行为级测试:
   - Windows 自动登录/凭据分支
   - macOS 更新检测与 LaunchAgent 生成
3. 协议共性抽象:
   - 继续推进共享 fixture 与共享规则层
4. 环境收口:
   - 解决本地 git transport / refs 同步异常

## 8. 本地仓库说明

- 已保留本地备份分支:
  - `backup/local-main-before-realign-20260411`
- 当前工作区内容已基于 `v1.3.15` 继续演进
- 但本地 `main` 仍显示 `ahead 2`
  - 原因不是文件内容不一致，而是当前本地对象库未完整持有远端最终 commit 对象，属于环境同步问题
  - 该问题不影响继续读代码与本地开发，但在正式继续提交前应先收口
