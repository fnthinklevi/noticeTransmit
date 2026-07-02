<div align="center">

<img src="assets/app_icon.png" width="128" alt="Notification Push Helper">

# Notification Push Helper

**English / [中文](README.md)**

A **notification listener and Webhook push tool** for Android devices, supporting WeChat Work, DingTalk, Feishu and other platforms. Features include app filtering, keyword filtering, battery reminders, dark mode and more.

[![Flutter](https://img.shields.io/badge/Flutter-3.44+-02569B?style=flat-square&logo=flutter)](https://flutter.dev/)
[![AGP](https://img.shields.io/badge/AGP-9.0.1-3DDC84?style=flat-square&logo=android)](https://developer.android.com/build/releases/gradle-plugin)
[![Gradle](https://img.shields.io/badge/Gradle-9.1.0-02303A?style=flat-square&logo=gradle)](https://gradle.org/)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?style=flat-square&logo=android)](#)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](#license)

</div>

## Introduction

Notification Push Helper is an Android application developed with Flutter that listens to system notification messages and pushes them to WeChat Work, DingTalk, Feishu and other platforms via Webhook. It supports multi-channel push, app filtering, keyword filtering, battery reminders and other features. The app adopts iOS-style design, supports dark mode, and has a clean and elegant interface.

## Features

### Core Features

- 🔔 **Notification Listening** - Listen to notification messages from all apps on the system
- 📱 **Multi-type Recognition** - Smart recognition of WeChat, QQ, SMS, phone calls, system notifications, etc.
- 🔗 **Webhook Multi-channel** - Support configuring multiple Webhook URLs simultaneously, each channel has independent on/off switch
- 📤 **Multi-platform Adaptation** - Auto-adapt message format for WeChat Work, DingTalk, Feishu and other platforms

### Advanced Features

- 🔋 **Battery Reminders** - Charging start, full charge, low battery (30%/20%) reminders
- 📋 **History Records** - Locally save notification push history, support search, detail view and export
- 📱 **App Filtering** - Customize which apps need notification push
- 🏷️ **Keyword Filtering** - Support whitelist and blacklist keyword filtering for precise push control

### Experience Optimization

- 🌙 **Dark Mode** - Support light/dark/follow system three theme modes
- 🛡️ **Background Survival** - Foreground service + battery optimization whitelist + boot auto-start
- 🔄 **Online Update** - Support version update and hot update, no need to reinstall APK
- 📲 **iOS Style Design** - Adopt iOS system design language, clean and elegant interface

## Technology Stack

| Module | Technology |
|--------|------------|
| Frontend | Flutter (Dart) |
| Native Service | Kotlin (Android) |
| Notification Listening | NotificationListenerService |
| Background Survival | Foreground Service + WakeLock + WifiLock |
| Cross-platform Communication | MethodChannel |
| Server | Node.js + Express |
| Data Storage | SharedPreferences + File Storage |

## Permission Description

| Permission | Purpose |
|------------|---------|
| `BIND_NOTIFICATION_LISTENER_SERVICE` | Listen to system notifications |
| `FOREGROUND_SERVICE` | Foreground service survival |
| `RECEIVE_BOOT_COMPLETED` | Boot auto-start |
| `READ_SMS` / `READ_PHONE_STATE` | Enhanced SMS/phone call recognition |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Battery optimization whitelist |

## Project Structure

```
noticeTransmit/
├── lib/                          # Flutter code
│   ├── main.dart                 # Main entry
│   └── update_manager.dart       # Update manager
├── android/                      # Android native code
│   └── app/src/main/kotlin/com/fnthink/notice/
│       ├── MainActivity.kt       # Main Activity
│       ├── NotificationMonitorService.kt  # Notification listener service
│       ├── SmsReceiver.kt         # SMS broadcast receiver
│       ├── PhoneCallReceiver.kt   # Phone call broadcast receiver
│       ├── BootReceiver.kt        # Boot broadcast receiver
│       └── WebhookPayloadBuilder.kt  # Webhook message builder
├── server/                       # Server (update service)
│   ├── server.js                # Express service
│   ├── data/                     # Version configuration data
│   │   ├── version.json          # Version info configuration
│   │   └── hotfix.json           # Hotfix configuration
│   └── README.md                # Server deployment documentation
├── assets/                       # Resource files
│   ├── app_icon.png
│   └── app_icon.svg
├── pubspec.yaml                  # Flutter configuration
└── README.md                     # Project documentation
```

## Quick Start

### Environment Requirements

> **Important**: This project uses **AGP 9.0.1** + **Gradle 9.1.0**, which has minimum version requirements for Flutter / Dart / Android Studio.

| Tool | Minimum Version | Recommended Version | Description |
|------|----------------|--------------------|-------------|
| **Flutter SDK** | 3.44.0 | 3.44.x stable | AGP 9.x support starts from Flutter 3.44 |
| **Dart SDK** | 3.12.0 | 3.12.x | Included with Flutter 3.44, no separate installation needed |
| **Android Gradle Plugin (AGP)** | 9.0.0 | 9.0.1 | Already configured in project |
| **Gradle** | 9.1.0 | 9.1.0 | Already configured (see gradle-wrapper.properties) |
| **Android Studio** | Koala (2024.1.1) | Latest stable | Need IDE version that supports AGP 9.x |
| **JDK** | 21 | 21+ | AGP 9.x requires JDK 21+ |
| **Android SDK** | 21 (minSdk) | 37 (compileSdk) | minSdk 21, target Android 15 |

#### Version Compatibility Notes

- **Flutter below 3.44**: Does not support AGP 9.x, build will fail. Please run `flutter upgrade` to upgrade to 3.44+.
- **AGP 8.x and below**: This project has migrated to AGP 9.x, cannot be downgraded.
- **Kotlin**: AGP 9.x uses Built-in Kotlin, no need to configure Kotlin version separately.

### Build APK

```bash
# Install dependencies
flutter pub get

# Code analysis
flutter analyze

# Build release version
flutter build apk --release --target-platform android-arm64
```

### Deploy Server

See [server/README.md](server/README.md) for details.

## Contribution

Welcome to submit Issues and Pull Requests!

## Privacy Notice

### Data Collection Statement

This application values user privacy. The following is a statement about data collection:

| Data Type | Collected | Description |
|-----------|-----------|-------------|
| **Notification Content** | ❌ Not uploaded | All notifications are processed and pushed locally only |
| **Contacts/SMS** | ❌ Not uploaded | Only used locally for push, not uploaded to any server |
| **Device ID** | ⚠️ Only for crash statistics | Used by Bugly SDK for device deduplication |
| **Crash Information** | ✅ Collected | Crash stack collected via Bugly for issue fixing |

### Bugly Crash Statistics

- **Purpose**: Only for collecting app crash information to help developers quickly locate and fix issues
- **Collected Content**: Crash stack, app version, system version, device model, CPU architecture
- **Not Collected**: User contacts, SMS content, notification content, location information or any personal privacy data
- **Provider**: Tencent Bugly ([https://bugly.qq.com](https://bugly.qq.com))

### Push Data

All notification pushes are sent through user-configured Webhook URLs. Developers do not store any push content.

## License

This project is for learning and communication purposes only.
