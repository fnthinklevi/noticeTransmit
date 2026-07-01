# 通知推送助手

监听 Android 通知栏消息，通过 Webhook 推送到指定渠道（企业微信、钉钉、飞书等）。

## 功能特性

- 🔔 **通知监听**：监听系统所有应用的通知栏消息
- 📱 **多平台支持**：微信、QQ、短信、来电、系统通知等
- 🔗 **Webhook 多通道**：支持同时配置多个 Webhook URL
- 🔋 **电量提醒**：充电、充满、低电量（30%/20%）提醒
- 📋 **历史记录**：本地保存通知推送历史，支持搜索和导出
- 📱 **应用筛选**：自定义选择哪些应用的通知需要推送
- 🏷️ **关键词过滤**：支持白名单和黑名单关键词过滤
- 🛡️ **后台保活**：前台服务 + 电量优化白名单 + 开机自启动
- 📤 **多格式适配**：自动适配企业微信、钉钉、飞书等平台格式
- 🌙 **深色模式**：支持浅色/深色/跟随系统三种主题模式
- 🔄 **在线更新**：支持版本更新与热更新，无需重新安装 APK

## 技术架构

- **前端**：Flutter (Dart)
- **原生服务**：Kotlin (Android)
- **通知监听**：NotificationListenerService
- **后台保活**：Foreground Service + WakeLock + WifiLock
- **跨端通信**：MethodChannel

## 权限说明

- `BIND_NOTIFICATION_LISTENER_SERVICE` — 监听系统通知
- `FOREGROUND_SERVICE` — 前台服务保活
- `RECEIVE_BOOT_COMPLETED` — 开机自启动
- `READ_SMS` / `READ_PHONE_STATE` — 短信/来电增强识别
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` — 电量优化白名单

## 项目结构

```
noticeTransmit/
├── lib/                    # Flutter 端代码
│   ├── main.dart          # 主入口
│   └── update_manager.dart # 更新管理
├── android/                # Android 原生代码
│   └── app/src/main/kotlin/com/fnthink/notice/
│       ├── MainActivity.kt
│       ├── NotificationMonitorService.kt
│       ├── SmsReceiver.kt
│       ├── PhoneCallReceiver.kt
│       ├── BootReceiver.kt
│       └── WebhookPayloadBuilder.kt
├── server/                 # 服务端（更新服务）
│   ├── server.js          # Express 服务
│   ├── data/              # 版本配置数据
│   └── README.md          # 服务端部署文档
└── assets/                 # 资源文件
```

## 签名配置

使用自定义 JKS 密钥进行 release 签名，配置文件位于 `android/key.properties`。
