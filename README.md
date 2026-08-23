<div align="center">

<img src="assets/app_icon.png" width="128" alt="通知推送助手">

# 通知推送助手

**[English](README-en.md) / 中文**

为 Android 设备提供**隐私优先**的通知转发工具。全链路本地处理，数据零上传。支持 Webhook（企业微信 / 钉钉 / 飞书 / Telegram / Bark / Server酱 / PushPlus）和 SMTP 邮件多通道推送，桌面小部件一键启停推送，全部配置 AES-256 加密存储。**全应用中英双语国际化**。

[![Flutter](https://badgen.net/badge/Flutter/3.44%2B/02569B?icon=flutter)](https://flutter.dev/)
[![AGP](https://badgen.net/badge/AGP/9.3.0/3DDC84?icon=android)](https://developer.android.com/build/releases/gradle-plugin)
[![Gradle](https://badgen.net/badge/Gradle/9.5.0/02303A?icon=gradle)](https://gradle.org/)
[![Platform](https://badgen.net/badge/Platform/Android/3DDC84?icon=android)](#)
[![Version](https://badgen.net/badge/Version/1.5.59/007AFF?icon=android)](https://github.com/fnthinklevi/noticeTransmit/releases)
[![License](https://badgen.net/badge/License/MIT/green)](#许可证)

🌐 **官方网站**：[notice.fnthink.top](https://notice.fnthink.top) — 软件介绍、客户端下载与后台管理入口

🌐 **GitHub Pages**：[fnthinklevi.github.io/noticeTransmit](https://fnthinklevi.github.io/noticeTransmit/) — 零运维静态部署（自动同步版本配置）

</div>

## 简介

通知推送助手是一款隐私优先的 Android 通知转发工具（Flutter + Kotlin）。核心能力：监听通知栏消息，通过 Webhook（企业微信 / 钉钉 / 飞书 / Telegram / Bark / Server酱 / PushPlus）或 SMTP 邮件实时推送至目标平台，桌面小部件一键启停推送。全链路本地处理，数据零上传。全应用中英双语国际化。开源 MIT，免费无广告。

## 功能特性

### 核心功能

- 🔔 **通知监听** - 监听系统所有应用的通知栏消息
- 📱 **多类型识别** - 智能识别微信、QQ、短信、来电、系统通知等类型
- 🔗 **Webhook 多通道** - 支持同时配置多个 Webhook URL，每个通道独立开关
- 📧 **SMTP 邮件推送** - 支持 SMTP 邮件转发（SSL/STARTTLS），可自定义主题模板与正文模板
- 📤 **多平台适配** - 自动适配企业微信、钉钉、飞书、Telegram、Bark、Server酱、PushPlus 等平台消息格式

### 进阶功能

- 🔋 **自定义电量提醒** - 支持完全自定义电量通知规则（充电/断开/指定电量阈值等），支持添加、编辑、删除规则，支持左滑删除和长按删除
- 📋 **历史记录** - 本地保存通知推送历史，支持搜索、详情查看和导出
- ✅ **送达状态标注** - 首页推送记录逐条标注各通道送达状态（推送成功/推送失败/发送中/用户暂停推送），按企业微信/飞书/钉钉官方返回码判定，短信/电话通道送达结果实时回传；推送失败原因（如 HTTP 502 / 限流提示）直接内联显示
- 📱 **应用筛选** - 自定义选择需要推送通知的应用
- 🏷️ **关键词过滤** - 支持白名单和黑名单关键词过滤，精准控制推送内容
- 🧠 **规则引擎** - 可视化配置通知规则，支持条件组合（IF）和动作配置（THEN），第一次进入提供功能引导说明，内置验证码优先推送、营销广告拦截、夜间免打扰等默认规则
- 🏷️ **通知优先级分级** - 原生链路提取系统通知优先级（高/中/低），可按「通知优先级」条件匹配规则；规则动作原生真实执行——静默忽略 / 仅记录 / 延迟推送 / 立即推送
- ⏰ **定时/延迟推送** - 规则「延迟推送」动作支持参数配置（延迟秒数 / 定时时间 HH:mm），到点自动补推 webhook 与邮件（深度 Doze 下可能有分钟级延迟），进程被杀/重启后任务自动恢复
- 📝 **推送模板引擎** - 自定义消息格式（text/markdown/json/xml），支持变量占位符（`%appName%`/`%title%`/`%content%` 等），按平台自动包裹 payload 与转义，每个通道独立配置
- 📟 **桌面小部件** - 2×2 / 4×2 双规格，自适应宽度布局，桌面点击一键启停推送；显示当日推送计数（跨天自动重置）；「推送开关」页一键添加到桌面

### 体验优化

- 🌐 **多语言国际化** - 全应用中英双语支持（120+ 处迁移），可在设置页自由切换语言
- 🌙 **深色模式** - 支持浅色/深色/跟随系统三种主题模式
- 🛡️ **后台保活** - 前台服务 + 电量优化白名单 + 开机自启动
- 📡 **监听可靠性增强** - 会话类通知（微信/QQ/Telegram 等）正文仅存在于 MessagingStyle 时自动兜底读取，去重键含通知 tag 防误判漏读；通知使用权被系统回收时前台显示「监听已断开 · 可能漏读通知」警告
- ⏸️ **一键暂停推送** - 前台通知栏 Action 按钮一键暂停/恢复推送（监听继续，仅停止 webhook 发送），状态持久化重启后恢复；暂停期间收到的消息在历史中显示「用户暂停推送」状态，可一键「现在推送」手动补推
- 🔄 **在线更新** - 支持版本更新，无需重新安装 APK；由系统下载器（DownloadManager）后台下载，免存储权限、锁屏后台不中断；多下载源自动回退（CDN / GitHub 加速镜像 / GitHub 直链，按设备架构匹配）；部署模式灵活（Node.js 服务器 / GitHub Pages 静态部署，客户端自动兼容）
- 📲 **Cupertino 设计语言** - 采用 Cupertino（iOS）系统设计语言，界面简洁优雅
- 🔒 **完整隐私政策** - 应用内置 11 章节隐私政策（数据收集边界 / 存储加密 / 信息共享 / 儿童隐私 / 用户权利等），首次启动弹窗征得同意，可随时在「更多」页查看
- 📊 **推送统计统一** - 首页/更多页/状态栏推送统计共用同一数据源，当日计数实时同步

### 安全加固

- 🔐 **二步验证（TOTP）** - 管理后台登录启用二步验证，兼容 Google Authenticator
- 🔑 **bcrypt 哈希** - Token 使用 bcrypt 哈希验证，防暴力破解
- 🛡️ **IP 封锁** - 10分钟内输错3次验证码自动封锁IP 240小时
- 🔢 **恢复码** - 生成8个恢复码，设备丢失时可找回账户
- 🔒 **敏感数据加密** - TOTP secret 使用 AES-256-GCM 加密存储
- 🎭 **混淆规则就绪** - 已配置 ProGuard/R8 混淆规则文件（`proguard-rules.pro`），Release 构建启用代码混淆与资源压缩
- 📡 **Token安全传输** - 仅接受 Header 传递，禁止 URL 参数
- 🎲 **安全随机数** - 使用 crypto.randomUUID() 生成会话 ID
- 🗄️ **SQLite 加密** - 通知记录、Webhook 配置、邮件通道全部 AES-256 加密存储，密钥存于 AndroidKeyStore
- 🔑 **Webhook 密钥安全** - Webhook URL（含钉钉/企微/飞书认证 key）使用 AndroidKeyStore 加密存储
- 🔐 **SSL 证书固定** - `PinnedHttpClient` 基础设施（2 个 HTTP 客户端）已就位，为 HTTPS 证书安全层，当前通过 Cloudflare CDN 间接保护
- 🔒 **HTTPS 强制** - 全站 HTTPS，`network_security_config.xml` 禁止明文传输

## 技术栈

| 模块 | 技术 |
|------|------|
| 前端 | Flutter 3.44+ (Dart 3.12+) |
| 状态管理 | get_it + Service 类 |
| 依赖注入 | get_it (^9.2.1) |
| 本地数据库 | sqflite_sqlcipher (SQLite, AES-256 加密) |
| 键值存储 | shared_preferences |
| 原生服务 | Kotlin 2.3.20 (Android) |
| 网络请求 | http (Dart) / OkHttp 4.12.0 (Kotlin) |
| 通知监听 | NotificationListenerService |
| 后台保活 | Android 原生 Foreground Service + WakeLock + WifiLock |
| 协程 | kotlinx.coroutines (SupervisorJob + Dispatchers.IO) |
| 跨端通信 | MethodChannel (统一声明) |
| 崩溃统计 | 腾讯 Bugly 4.1.9.3 |
| 服务端 | Node.js + Express 4.x (Token鉴权 + 二步验证) / GitHub Pages 静态部署 |
| TOTP验证 | otplib (^12.0.1) |
| 密码哈希 | bcryptjs (^2.4.3) |
| 数据加密 | Node.js crypto (AES-256-GCM) / AndroidKeyStore + flutter_secure_storage |
| 构建工具 | Gradle 9.5.0 + AGP 9.3.0 + JDK 21 |
| CI/CD | GitHub Actions |
| APK签名 | Gradle (apksigner) V1+V2+V3 签名 |

## 权限说明

| 权限 | 用途 |
|------|------|
| `BIND_NOTIFICATION_LISTENER_SERVICE` | 监听系统通知 |
| `FOREGROUND_SERVICE` | 前台服务保活 |
| `RECEIVE_BOOT_COMPLETED` | 开机自启动 |
| `READ_SMS` / `READ_PHONE_STATE` | 短信/来电增强识别 |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | 电量优化白名单 |

## 项目结构

```
noticeTransmit/
├── lib/                          # Flutter 端代码
│   ├── main.dart                 # 主入口
│   ├── update_manager.dart       # 更新管理
│   ├── models/                   # 数据模型
│   │   ├── notification_record.dart  # 通知记录模型
│   │   ├── battery_rule.dart     # 电池规则模型
│   │   ├── webhook_channel.dart  # Webhook 渠道模型
│   │   └── notification_rule.dart # 规则引擎模型
│   ├── pages/                    # 页面组件
│   │   ├── rule_list_page.dart   # 规则列表页
│   │   └── rule_edit_page.dart   # 规则编辑页
│   ├── theme/                    # 主题配置
│   │   ├── app_colors.dart       # 颜色主题
│   │   └── app_theme.dart        # 主题配置
│   ├── pages/                    # 页面组件
│   │   ├── splash_page.dart      # 开屏页
│   │   └── privacy_policy_page.dart  # 隐私政策页
│   ├── services/                 # 服务层（14个文件）
│   ├── widgets/                  # 可复用组件（图标选择器等）
│   │   └── common/               # 通用组件
├── android/                      # Android 原生代码
│   └── app/src/main/kotlin/com/fnthink/notice/
│       ├── MainActivity.kt       # 主 Activity
│       ├── NotificationMonitorService.kt  # 通知监听服务
│       ├── NotificationProcessor.kt       # 通知解析模块
│       ├── BatteryMonitor.kt              # 电量监控模块
│       ├── WebhookSender.kt               # Webhook 推送模块
│       ├── NetworkClient.kt               # 网络请求客户端
│       ├── ConfigManager.kt               # 配置管理模块
│       ├── SmsReceiver.kt         # 短信广播接收器
│       ├── PhoneCallReceiver.kt   # 来电广播接收器
│       ├── BootReceiver.kt        # 开机广播接收器
│       └── WebhookPayloadBuilder.kt  # Webhook 消息构建器
├── server/                       # 服务端（更新服务）
│   ├── server.js                # 服务端入口（启动 + 优雅关闭）
│   ├── lib/                     # 模块化分层（app/store/otp/middleware/routes）
│   ├── data/                     # 版本配置数据
│   │   └── version.json          # 版本信息配置
│   └── README.md                # 服务端部署文档
├── assets/                       # 资源文件
│   ├── app_icon.png
│   └── app_icon.svg
├── pubspec.yaml                  # Flutter 配置
└── README.md                     # 项目说明
```

## 快速开始

### 环境要求

> **重要提示**：本项目使用 **AGP 9.3.0** + **Gradle 9.5.0**，对 Flutter / Dart / Android Studio 版本有最低要求。

| 工具 | 最低版本 | 推荐版本 | 说明 |
|------|----------|----------|------|
| **Flutter SDK** | 3.44.0 | 3.44.x stable | AGP 9.x 支持从 Flutter 3.44 开始 |
| **Dart SDK** | 3.12.0 | 3.12.x | 随 Flutter 3.44 自带 |
| **Android Gradle Plugin (AGP)** | 9.0.0 | 9.3.0 | 项目已配置 |
| **Gradle** | 9.5.0 | 9.5.0 | 项目已配置（gradle-wrapper.properties） |
| **Kotlin** | 2.3.20 | 2.3.20 | 通过 `settings.gradle.kts` 显式声明 `org.jetbrains.kotlin.android` 插件 |
| **Android Studio** | Koala (2024.1.1) | 最新稳定版 | 需支持 AGP 9.x |
| **JDK** | 21 | 21+ | AGP 9.x 要求 JDK 21 及以上 |
| **Android SDK** | 24 (minSdk) | 37 (compileSdk) | minSdk 24，目标 SDK 37 |

#### 版本兼容性说明

- **Flutter 3.44 以下版本**：不支持 AGP 9.x，构建会失败。请先执行 `flutter upgrade` 升级到 3.44+。
- **AGP 8.x 及以下**：本项目已迁移到 AGP 9.x，无法降级使用。
- **Kotlin**：项目通过 `settings.gradle.kts` 显式声明 `org.jetbrains.kotlin.android` 版本 2.3.20，并在 `gradle.properties` 中保留 `android.builtInKotlin=false`、`android.newDsl=false`。

### 构建 APK

```bash
# 安装依赖
flutter pub get

# 代码检查
flutter analyze

# 构建 release 版本
flutter build apk --release --target-platform android-arm64
```

### 部署服务端

支持两种部署模式：

- **Node.js 服务器**（完整功能）：详见 [server/README.md](server/README.md) · [English](server/README-en.md)
- **GitHub Pages**（零运维静态部署）：详见 [server/GITHUB_PAGES.md](server/GITHUB_PAGES.md) · [English](server/GITHUB_PAGES-en.md)

客户端自动兼容两种模式，无需修改代码。

## 贡献

欢迎提交 Issue 和 Pull Request！

- 贡献指南：详见 [CONTRIBUTING.md](CONTRIBUTING.md) · [English](CONTRIBUTING-en.md)
- 安全政策：详见 [SECURITY.md](SECURITY.md) · [English](SECURITY-en.md)
- 行为准则：详见 [CODE_OF_CONDUCT-zh.md](CODE_OF_CONDUCT-zh.md) · [English](CODE_OF_CONDUCT.md)

## 隐私说明

### 数据采集声明

本应用重视用户隐私，关于数据采集的说明如下：

| 数据类型 | 是否采集 | 说明 |
|----------|----------|------|
| **通知内容** | ❌ 不上传 | 所有通知仅在本地处理和推送，不上传到任何服务器 |
| **通讯录/短信** | ❌ 不上传 | 仅本地监听用于推送，不上传到任何服务器 |
| **设备标识** | ⚠️ 仅崩溃统计用 | Bugly SDK 用于设备去重统计 |
| **崩溃信息** | ✅ 采集 | 通过 Bugly 收集崩溃堆栈，用于修复问题 |

### Bugly 崩溃统计

- **用途**：仅用于收集应用崩溃信息，帮助开发者快速定位和修复问题
- **采集内容**：崩溃堆栈、应用版本号、系统版本、设备型号、CPU 架构
- **不采集**：用户通讯录、短信内容、通知内容、位置信息等任何个人隐私数据
- **服务商**：腾讯 Bugly ([https://bugly.qq.com](https://bugly.qq.com))

### 推送数据

所有通知推送均通过用户自行配置的 Webhook URL 发送。仅 Bugly 采集最小必要的崩溃统计（堆栈、设备型号、系统版本、应用版本），不包含任何个人隐私数据。

## 常见问题与排错

### 通知收不到？
1. 通知访问权限是否开启
2. 电池优化是否忽略
3. 前台服务是否运行
4. 厂商自启动/后台权限是否开启
5. Webhook URL 是否正确（可在设置页测试）
6. 应用筛选 / 关键词过滤是否把通知过滤了

## 许可证

本项目基于 [MIT License](LICENSE) 开源。
