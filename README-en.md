<div align="center">

<img src="assets/app_icon.png" width="128" alt="Notification Push Helper">

# Notification Push Helper

**English / [中文](README.md)**

A **notification listener and Webhook push tool** for Android devices, supporting WeChat Work, DingTalk, Feishu and other platforms. Features include app filtering, keyword filtering, custom battery reminders, dark mode and more.

[![Flutter](https://img.shields.io/badge/Flutter-3.44+-02569B?style=flat-square&logo=flutter)](https://flutter.dev/)
[![AGP](https://img.shields.io/badge/AGP-9.0.1-3DDC84?style=flat-square&logo=android)](https://developer.android.com/build/releases/gradle-plugin)
[![Gradle](https://img.shields.io/badge/Gradle-9.1.0-02303A?style=flat-square&logo=gradle)](https://gradle.org/)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?style=flat-square&logo=android)](#)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](#license)

</div>

## Introduction

Notification Push Helper is an Android application developed with Flutter that listens to system notification messages and pushes them to WeChat Work, DingTalk, Feishu and other platforms via Webhook. It supports multi-channel push, app filtering, keyword filtering, custom battery reminders and other features. The app adopts iOS-style design, supports dark mode, and has a clean and elegant interface.

## Features

### Core Features

- 🔔 **Notification Listening** - Listen to notification messages from all apps on the system
- 📱 **Multi-type Recognition** - Smart recognition of WeChat, QQ, SMS, phone calls, system notifications, etc.
- 🔗 **Webhook Multi-channel** - Support configuring multiple Webhook URLs simultaneously, each channel has independent on/off switch
- 📤 **Multi-platform Adaptation** - Auto-adapt message format for WeChat Work, DingTalk, Feishu and other platforms

### Advanced Features

- 🔋 **Custom Battery Reminders** - Fully customizable battery notification rules (charging/discharging/specific battery level thresholds), support add/edit/delete rules, support swipe left to delete and long press to delete
- 📋 **History Records** - Locally save notification push history, support search, detail view and export
- 📱 **App Filtering** - Customize which apps need notification push
- 🏷️ **Keyword Filtering** - Support whitelist and blacklist keyword filtering for precise push control
- 🧠 **Rule Engine** - Visual configuration of notification rules, support condition combination (IF) and action configuration (THEN), first-time entry provides feature guide, built-in default rules including verification code priority push, marketing ad blocking, night do not disturb

### Experience Optimization

- 🌙 **Dark Mode** - Support light/dark/follow system three theme modes
- 🛡️ **Background Survival** - Foreground service + battery optimization whitelist + boot auto-start
- 🔄 **Online Update** - Support version update and hot update, no need to reinstall APK
- 📲 **iOS Style Design** - Adopt iOS system design language, clean and elegant interface

### Security

- 🔐 **Two-step Verification (TOTP)** - Admin panel login requires two-step verification, compatible with Google Authenticator
- 🔑 **bcrypt Hashing** - Token verified using bcrypt hashing to prevent brute force attacks
- 🛡️ **IP Blocking** - IP automatically blocked for 240 hours after 3 failed verification attempts within 10 minutes
- 🔢 **Recovery Codes** - 8 recovery codes generated for account recovery when device is lost
- 🔒 **Sensitive Data Encryption** - TOTP secret stored using AES-256-GCM encryption
- 🎭 **Code Obfuscation** - R8 code obfuscation and resource shrinking enabled
- 📡 **Secure Token Transmission** - Token only accepted via Header, URL parameters disabled
- 🎲 **Cryptographic Randomness** - Session IDs generated using crypto.randomUUID()

## Technology Stack

| Module | Technology |
|--------|------------|
| Frontend | Flutter (Dart) |
| State Management | get_it + Service Classes |
| Dependency Injection | get_it |
| Native Service | Kotlin (Android) |
| Notification Listening | NotificationListenerService |
| Background Survival | Android Native Foreground Service + WakeLock + WifiLock |
| Cross-platform Communication | MethodChannel |
| Crash Statistics | Tencent Bugly |
| Server | Node.js + Express (Token Auth + Two-step Verification) |
| Data Storage | SharedPreferences + SQLite |

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
│   ├── update_manager.dart       # Update manager
│   ├── models/                   # Data models
│   │   ├── notification_record.dart  # Notification record model
│   │   ├── battery_rule.dart     # Battery rule model
│   │   ├── webhook_channel.dart  # Webhook channel model
│   │   └── notification_rule.dart # Rule engine model
│   ├── pages/                    # Page components
│   │   ├── rule_list_page.dart   # Rule list page
│   │   └── rule_edit_page.dart   # Rule edit page
│   ├── theme/                    # Theme configuration
│   │   ├── app_colors.dart       # Color themes
│   │   └── app_theme.dart        # Theme configuration
│   ├── pages/                    # Page components
│   │   ├── splash_page.dart      # Splash page
│   │   └── privacy_policy_page.dart  # Privacy policy page
│   ├── services/                 # Service layer (reserved)
│   ├── state/                    # State management (reserved)
│   └── widgets/                  # Widget layer (reserved)
│       └── common/               # Common widgets
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

## FAQ & Troubleshooting

### Not receiving notifications?
1. Is Notification Access permission enabled
2. Is battery optimization disabled
3. Is foreground service running
4. Is auto-start/background permission enabled for OEM devices
5. Is Webhook URL correct (testable in settings page)
6. Is the notification filtered by app filter / keyword filter

### Hotfix not working?
1. Check if `flutter_contentVersion` is updated
2. Check if files exist in `app_flutter/hotfix/` directory
3. Check logcat for `RELOAD_HOTFIX` broadcast
4. Verify JSON format is correct

### Data lost after restart?
- **Issue**: Battery rules, keyword filters, push history and other data lost after app restart
- **Cause**: Service initialization process not fully executed, data not properly loaded
- **Solution**: Ensure app starts normally and wait for SplashPage initialization to complete before operating

## License

This project is for learning and communication purposes only.
