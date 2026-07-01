<div align="center">

<img src="assets/app_icon.png" width="128" alt="通知推送助手">

# 通知推送助手

为 Android 设备提供的**通知监听与 Webhook 推送工具**，支持企业微信、钉钉、飞书等多平台推送，具备应用筛选、关键词过滤、电量提醒、深色模式等丰富功能。

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter)](https://flutter.dev/)
[![Kotlin](https://img.shields.io/badge/Kotlin-1.x-7F52FF?style=flat-square&logo=kotlin)](https://kotlinlang.org/)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?style=flat-square&logo=android)](#)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](#许可证)

</div>

## 简介

通知推送助手是一款基于 Flutter 开发的 Android 应用，能够监听系统通知栏消息，通过 Webhook 推送到企业微信、钉钉、飞书等平台。支持多通道推送、应用筛选、关键词过滤、电量提醒等功能，采用 iOS 风格设计，支持深色模式，界面简洁优雅。

## 功能特性

### 核心功能

- 🔔 **通知监听** - 监听系统所有应用的通知栏消息
- 📱 **多类型识别** - 智能识别微信、QQ、短信、来电、系统通知等类型
- 🔗 **Webhook 多通道** - 支持同时配置多个 Webhook URL，每个通道独立开关
- 📤 **多平台适配** - 自动适配企业微信、钉钉、飞书等平台消息格式

### 进阶功能

- 🔋 **电量提醒** - 充电开始、电量充满、低电量（30%/20%）提醒
- 📋 **历史记录** - 本地保存通知推送历史，支持搜索、详情查看和导出
- 📱 **应用筛选** - 自定义选择需要推送通知的应用
- 🏷️ **关键词过滤** - 支持白名单和黑名单关键词过滤，精准控制推送内容

### 体验优化

- 🌙 **深色模式** - 支持浅色/深色/跟随系统三种主题模式
- 🛡️ **后台保活** - 前台服务 + 电量优化白名单 + 开机自启动
- 🔄 **在线更新** - 支持版本更新与热更新，无需重新安装 APK
- 📲 **iOS 风格设计** - 采用 iOS 系统设计语言，界面简洁优雅

## 技术栈

| 模块 | 技术 |
|------|------|
| 前端 | Flutter (Dart) |
| 原生服务 | Kotlin (Android) |
| 通知监听 | NotificationListenerService |
| 后台保活 | Foreground Service + WakeLock + WifiLock |
| 跨端通信 | MethodChannel |
| 服务端 | Node.js + Express |
| 数据存储 | SharedPreferences + 文件存储 |

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
│   └── update_manager.dart       # 更新管理
├── android/                      # Android 原生代码
│   └── app/src/main/kotlin/com/fnthink/notice/
│       ├── MainActivity.kt       # 主 Activity
│       ├── NotificationMonitorService.kt  # 通知监听服务
│       ├── SmsReceiver.kt         # 短信广播接收器
│       ├── PhoneCallReceiver.kt   # 来电广播接收器
│       ├── BootReceiver.kt        # 开机广播接收器
│       └── WebhookPayloadBuilder.kt  # Webhook 消息构建器
├── server/                       # 服务端（更新服务）
│   ├── server.js                # Express 服务
│   ├── data/                     # 版本配置数据
│   │   ├── version.json          # 版本信息配置
│   │   └── hotfix.json           # 热更新配置
│   └── README.md                # 服务端部署文档
├── assets/                       # 资源文件
│   ├── app_icon.png
│   └── app_icon.svg
├── pubspec.yaml                  # Flutter 配置
└── README.md                     # 项目说明
```

## 快速开始

### 环境要求

- Flutter SDK 3.x
- Android SDK 21+
- Node.js 14+（服务端）

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

详见 [server/README.md](server/README.md)

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

本项目仅供学习交流使用。
