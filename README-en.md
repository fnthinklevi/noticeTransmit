<div align="center">

<img src="assets/app_icon.png" width="128" alt="NoticeTransmit">

# NoticeTransmit

**English / [中文](README.md)**

A **privacy-first** notification forwarder for Android. Fully on-device processing — zero data upload (sole exception: crash reporting, off by default; crash logs are uploaded to Tencent Bugly only after you explicitly enable it — see [Privacy Notice](#privacy-notice)). Supports 12 Webhook channel types (Generic / WeCom / DingTalk / Feishu / Telegram / Bark / ServerChan / PushPlus / ntfy / Gotify / Slack / Discord; ntfy/Gotify support self-hosted servers), WeCom/Feishu **self-built app** channels and SMTP email push, one-tap pause/resume via home-screen widget, all configs AES-256 encrypted. **Full-app Chinese/English i18n (853 keys × 2 languages)**.

[![Flutter](https://badgen.net/badge/Flutter/3.44%2B/02569B?icon=flutter)](https://flutter.dev/)
[![AGP](https://badgen.net/badge/AGP/9.3.0/3DDC84?icon=android)](https://developer.android.com/build/releases/gradle-plugin)
[![Gradle](https://badgen.net/badge/Gradle/9.5.0/02303A?icon=gradle)](https://gradle.org/)
[![Platform](https://badgen.net/badge/Platform/Android/3DDC84?icon=android)](#)
[![Version](https://badgen.net/badge/Version/1.5.74/007AFF?icon=android)](https://github.com/fnthinklevi/noticeTransmit/releases)
[![License](https://badgen.net/badge/License/MIT/green)](#license)

🌐 **Official Website**: [notice.fnthink.top](https://notice.fnthink.top) — intro, client download & admin console

🌐 **GitHub Pages**: [fnthinklevi.github.io/noticeTransmit](https://fnthinklevi.github.io/noticeTransmit/) — zero-maintenance static deployment (auto-syncs version config)

</div>

## Introduction

NoticeTransmit is a privacy-first Android notification forwarder (Flutter + Kotlin). It captures system notifications and pushes them via 12 Webhook channel types (Generic / WeCom / DingTalk / Feishu / Telegram / Bark / ServerChan / PushPlus / ntfy / Gotify / Slack / Discord), WeCom/Feishu self-built app channels or SMTP email, with one-tap pause/resume via home-screen widget. Fully on-device processing — zero data upload (crash reporting is off by default; crash logs are uploaded to Tencent Bugly only after being enabled). Full-app Chinese/English i18n. Open source MIT, free, no ads.

## Features

### Core Features

- 🔔 **Notification Listening** - Listen to notification messages from all apps on the system
- 📱 **Multi-type Recognition** - Smart recognition of WeChat, QQ, SMS, phone calls, system notifications, etc.
- 🔗 **Webhook Multi-channel** - 12 channel types (Generic / WeCom / DingTalk / Feishu / Telegram / Bark / ServerChan / PushPlus / ntfy / Gotify / Slack / Discord); configure multiple channels at once, each with an independent on/off switch; hosted endpoints are auto-detected from the URL host, and for self-hosted ntfy/Gotify the manually chosen type is respected across save / send / test
- 📧 **SMTP Email Push** - Support SMTP email forwarding (SSL/STARTTLS), customizable subject template and body template
- 📤 **Multi-platform Adaptation** - Auto-adapt message format for WeChat Work, DingTalk, Feishu, Telegram, Bark, ServerChan, PushPlus, ntfy, Gotify, Slack, Discord and other platforms (ntfy/Gotify support self-hosted servers); in-app update APKs carry sha256 integrity verification (v1.5.69), and Bark business failures are reported truthfully instead of as success
- 🏢 **Self-built App Channels (WeCom / Feishu)** - An "app channel" system independent of Webhooks: send messages as your own app by providing corpsecret / app_secret; WeCom apps can target touser/@all, Feishu apps can specify chat_id/open_id; API base URL can point to self-hosted deployments; secrets are encrypted at rest, and delivery results / retries work the same as Webhook channels; **built-in step-by-step setup guide** (tap "?" on a card for how to obtain corpid/AgentId/Secret or App ID/App Secret, plus notes); **layered list page** shows channel name, type and connection status at a glance (v1.5.74)
- 🌡️ **Device Temperature Push (v1.5.74)** - Three independent dimensions: battery temperature / device overall temperature / screen temperature, with custom threshold rules; 30-minute cooldown prevents repeated pushes from temperature fluctuation; shares the same polling source as battery push (no conflict)
- 💚 **Channel Health Probe (v1.5.73)** - The Webhook settings page light-probes enabled channels (any HTTP response counts as reachable; only timeout / DNS failure / connection refused is judged unreachable); channels stale for over 6 hours are re-probed in the background and persisted, and each card shows a "✓ reachable · latency · probe time" badge; business-level health is reflected by the delivery log of the most recent real push

### Advanced Features

- 🔋 **Custom Battery Reminders** - Fully customizable battery notification rules (charging/discharging/specific battery level thresholds), support add/edit/delete rules, support swipe left to delete and long press to delete
- 📋 **History Records** - Locally save notification push history, support search, detail view and export; long-press for quick block actions (block the app / block notifications containing this content), failed records support batch re-push
- 🗂️ **Daily Auto Archive** - WorkManager exports the previous day's push history as a JSON file every day (the full history stays in the database — archiving is a backup, it never deletes the source records); a custom archive directory (SAF) can be chosen, and foreground startup completes the archive for custom-directory mode
- ✅ **Delivery Status Labeling** - Each push record on the home page is labeled per-channel delivery status (success/failed/sending/user-paused), determined by official return codes from WeChat Work/Feishu/DingTalk; SMS/call delivery results are reported back in real time; failure reasons (e.g. HTTP 502 / rate-limit hints) are shown inline
- 📈 **Delivery Health Dashboard (v1.5.73)** - A new "delivery health" section on the stats page: per-channel success-rate ranking (green / orange / red), top failure reasons clustered by HTTP status (502 / 429 / network failures), and a 24-hour peak-hours bar chart; toggle between the last 7 / 30 days, aggregated from the delivery log and notification records
- 📱 **App Filtering** - Customize which apps need notification push
- 🏷️ **Keyword Filtering** - Support whitelist and blacklist keyword filtering for precise push control
- 🧠 **Rule Engine** - Visual configuration of notification rules, support condition combination (IF) and action configuration (THEN), first-time entry provides feature guide, built-in default rules including verification code priority push, marketing ad blocking, night do not disturb and app notification aggregation (ready out of the box; missing rules are filled in automatically on upgrade); rule priority supports quick presets and custom values (0-500), and each rule can exclude specific apps (a "Quick Select" area auto-detects mainstream messaging/email apps installed on the device, with system SMS & phone components merged into single rows offering three-state group toggles, pinned on top)
- 🧪 **Rule Tester (v1.5.69)** - Enter a simulated notification and see the full trace in real time: filter → rule matching → final action, so rule issues are obvious at a glance
- 📚 **Rule Template Library (v1.5.73)** - Five built-in presets (verification-code priority / marketing ad blocking / night do-not-disturb / social message aggregation / whitelist keyword express) importable in one tap; custom rules can be "saved as template" for reuse (same name overwrites); templates export as a `.json` file, optionally password-protected with the same PBKDF2 210k + AES-256-GCM scheme as config backup, and import auto-detects plain / encrypted format
- 📤 **Batch re-push for failed records (v1.5.69)** - Filter failed records in push history and re-push them in one tap; failed pushes are auto-retried (on network recovery / service restart)
- 📦 **App Notification Aggregation (v1.5.69)** - Notifications from the same app are merged into a single push within a window (60s by default, configurable, 5s minimum), greatly reducing message floods; supports "flush early at N items" (no need to wait for the window) and "group by conversation" (same app, different contacts aggregate separately); custom templates support `%count%`/`%titles%` variables; rule conditions support the `*` wildcard to match any app; a single message during the window is sent as a normal push; while merging, the foreground notification shows the pending list with countdown; whether aggregation succeeds or fails, member content is always saved to push history first, and each member record is labeled with its real delivery status
- 🏷️ **Notification Priority Levels** - System notification priority (high/medium/low) extracted natively, matchable via "notification priority" condition; rule actions truly executed natively — silent ignore / record only / delayed push / push now
- ⏰ **Scheduled / Delayed Push** - "Delayed push" action configurable (delay seconds / schedule HH:mm), auto re-push webhook & email when due (may be delayed by minutes in deep Doze), tasks auto-recover after process kill or reboot
- 📝 **Push Template Engine** - Custom message format (text/markdown/json/xml), supports variable placeholders (`%appName%`/`%title%`/`%content%` etc.), auto-wraps payload per platform with escaping, each channel configured independently
- 📟 **Home Screen Widget** - 2×2 / 4×2 dual sizes with adaptive width layout, one-tap toggle push from the home screen; shows daily push count (auto-resets at midnight); one-tap add to home screen

### Experience Optimization

- 🌐 **Multi-language i18n** - Full-app Chinese/English bilingual support (`app_zh.arb` / `app_en.arb`, 853 keys each, generated by gen-l10n; CI locks both key sets together so nothing goes untranslated), switch language freely in settings; the language label is pushed to the native side so the persistent notification and push copy follow suit
- 🖼️ **Launcher Icon Switching** - 17 icon styles × Chinese/English labels = 34 launcher icon aliases, switched in one tap inside the app (only one alias is enabled at a time, the rest are disabled)
- 📄 **Text Selection Menu Adaptation (v1.5.74)** - Menu button labels (copy/cut/paste/select all/share) for all 36 text fields use app-localized strings, eliminating blank or English labels on vendor ROMs
- 🎨 **Dialog iOS Style Unification (v1.5.74)** - All confirm dialogs use divider button layout (cancel=secondary / confirm=blue / delete=red), adaptive for light/dark themes
- 🔄 **Notification State Machine Optimization (v1.5.74)** - Unified show/hide logic across 5 scenarios (start/stop/process kill/keep-alive/permission missing), persistent notification syncs in real-time with monitoring state
- 🌙 **Dark Mode** - Support light/dark/follow system three theme modes
- 🛡️ **Background Survival** - Foreground service + battery optimization whitelist + boot auto-start; built-in OEM ROM keep-alive guide (battery unrestricted / auto-start / task lock, one-tap jump to vendor settings)
- 📡 **Listener Reliability (v1.5.69)** - Fallback content extraction for conversation-style notifications (WeChat/QQ/Telegram etc.) whose body only exists in MessagingStyle; dedup key includes the notification tag to avoid missed reads; warns "listener disconnected · notifications may be missed" and auto-rebinds when notification access is revoked; **after the OS recycles the service, startup re-scans still-visible notifications against a persisted watermark** (up to 6 hours back), greatly reducing missed notifications during long screen-off/background periods
- 🩺 **Runtime Diagnostics Switch (v1.5.69)** - Tap the version number 7 times on the About page to toggle diagnostic logs (rule/merge `[diag]` logs in logcat, excluding notification titles/bodies) — troubleshoot without reinstalling
- 💾 **Config Backup & Restore (v1.5.69)** - Export **12 categories of configs** (Webhook/email channels with credentials, self-built app channels with credentials, notification rules, SMS settings, app filter, keyword lists, battery rules & switch, device name, theme/language) encrypted as a `.nbackup` file (AES-256-GCM + PBKDF2 210k-iteration passphrase derivation, self-describing KDF header). Restore after switching or reinstalling by picking the file and entering your passphrase; conflict strategy offers "overwrite all / fill gaps only" when existing configs are detected, non-https URLs are skipped automatically; backup format v2 is backward compatible with v1
- 📱 **Home-Screen Widgets Upgraded (v1.5.63)** - Fully redesigned 2×2/4×2 layouts (status ring, hint pill, daily counter); the system pin dialog now shows a preview and description, and launchers without pin support automatically open a brand-specific step-by-step guide. New SMS monitoring settings hub: listening toggle / verification-code toggle / SIM-card selection (auto-disabled on single-SIM devices); card filtering applies to both SMS and call paths, and pushed messages can carry a bilingual "SIM 1, Carrier" info line
- 🔐 **Opt-in Crash Reporting (v1.5.62)** - Bugly crash reporting is off by default and initializes only after user consent; toggleable anytime in settings. Rule engine normalization aligned across Dart/Kotlin (full-width/half-width, whitespace collapsing, value trimming) locked by 51 dual-end golden test cases. Webhook delivery logs are persisted for auditing, and export reads the full database instead of the in-memory cap
- 📩 **SMS Reliability (v1.5.61)** - SMS uses a dual-path design: besides the primary `SMS_RECEIVED` broadcast, a SMS-database ContentObserver catches messages missed by the broadcast; both paths are deduplicated by content fingerprint so nothing is pushed twice. Verification codes are extracted automatically and delivered as a dedicated field
- ⏸️ **One-tap Pause Push** - Pause/resume push via foreground notification action button (monitoring continues, only webhook sending stops), state persists across restarts; messages received while paused show a "user-paused" status in history, with a one-tap "push now" manual resend
- 🔄 **Online Update** - Support version update, no need to reinstall APK; downloads via system downloader (DownloadManager) in background — no storage permission needed, uninterrupted when screen is off; multi-source fallback (CDN / GitHub mirror / GitHub direct, matched by device ABI); flexible deployment modes (Node.js server / GitHub Pages static deployment, client auto-compatibility)
- 📲 **Cupertino Design Language** - Adopt Cupertino (iOS) system design language, clean and elegant interface
- 🔒 **Full Privacy Policy** - In-app 11-chapter privacy policy (data collection scope / encrypted storage / information sharing / children's privacy / user rights, etc.), consent dialog on first launch, viewable anytime from the More page
- 📊 **Unified Push Stats** - Home/More/status bar push stats share the same database source, daily count syncs in real time

### Security

- 🔐 **Two-step Verification (TOTP)** - Admin panel login requires two-step verification, compatible with Google Authenticator
- 🔑 **bcrypt Hashing** - Token verified using bcrypt hashing to prevent brute force attacks
- 🛡️ **IP Blocking** - IP automatically blocked for 1 hour after 5 failed verification attempts within 10 minutes
- 🔢 **Recovery Codes** - 8 recovery codes generated for account recovery when device is lost
- 🔒 **Sensitive Data Encryption** - TOTP secret stored using AES-256-GCM encryption
- 🎭 **Obfuscation Rules Ready** - ProGuard/R8 rules file configured (`proguard-rules.pro`), Release builds enable code obfuscation and resource shrinking
- 📡 **Secure Token Transmission** - Token only accepted via Header, URL parameters disabled
- 🎲 **Cryptographic Randomness** - Session IDs generated using crypto.randomUUID()
- 🗄️ **SQLite Encryption** - Notification records, Webhook/email/self-built app channel configs and the delivery log (schema v10, 6 tables) are all stored with SQLCipher AES-256 encryption; the key is held in AndroidKeyStore via flutter_secure_storage
- 🔑 **Webhook Key Protection** - Webhook URLs (including DingTalk/WeCom/Feishu auth keys) encrypted via AndroidKeyStore
- 🔐 **SSL Certificate Pinning** - Both HTTP clients are ready (Dart `PinnedHttpClient` + the OkHttp `CertificatePinner` in Kotlin `NetworkClient`), forming the HTTPS certificate security layer, **disabled by default** (requires injecting `CERT_PINS` / `ENABLE_CERT_PINNING`; always off in Debug builds), currently protected indirectly via Cloudflare CDN; see [docs/cert_rotation_runbook.md](docs/cert_rotation_runbook.md) for rotation/enablement
- 🧩 **Widget Broadcast Guard** - Home-screen widget toggle broadcasts are protected by the signature-level custom permission `com.fnthink.notice.permission.WIDGET_CONTROL`, so third-party apps cannot forge a `TOGGLE_PUSH` broadcast to silently pause or resume pushes
- 🔒 **Mandatory HTTPS** - Site-wide HTTPS enforced via `network_security_config.xml`

## Technology Stack

| Module | Technology |
|--------|------------|
| Frontend | Flutter 3.44.x (Dart 3.12.2) |
| State Management | get_it + Service Classes |
| Dependency Injection | get_it (^9.2.1) |
| Local Database | sqflite_sqlcipher (^3.4.0) · SQLCipher AES-256 · schema v10 / 6 tables |
| Key-Value Storage | shared_preferences · flutter_secure_storage (^9.2.4) + androidx.security EncryptedSharedPreferences |
| Native Service | Kotlin 2.3.20 (Android), 51 Kotlin files in main sourceset |
| HTTP Client | http (Dart) / OkHttp 4.12.0 (Kotlin) |
| Email Sending | com.sun.mail:android-mail 1.6.7 (SMTP) |
| Notification Listening | NotificationListenerService |
| Background Survival | Android Native Foreground Service + WakeLock (PARTIAL_WAKE_LOCK) |
| Background Tasks | workmanager ^0.6.0 (daily archive) |
| Coroutines | kotlinx.coroutines (SupervisorJob + Dispatchers.IO) |
| Cross-platform Communication | MethodChannel `com.fnthink.notice/notification` (87 methods · 5 native handlers) |
| Internationalization | gen-l10n + ARB (853 keys each for zh / en) |
| Crash Statistics | Tencent Bugly 4.1.9.3 |
| Server | Node.js 24 LTS (engines `>=24`) + Express 5.x (Token Auth + Two-step Verification) / GitHub Pages static deploy |
| TOTP Verification | otplib (^13.0.1) |
| Password Hashing | bcryptjs (^2.4.3) |
| Data Encryption | Node.js crypto (AES-256-GCM) / AndroidKeyStore + flutter_secure_storage |
| Build Tools | Gradle 9.5.0 + AGP 9.3.0 + JDK 21 |
| Code Quality | flutter_lints ^6.0.0 · dart format · ktlint 1.8.0 · prettier 3.9.8 · Android lint (with baseline) |
| Testing | flutter test (Dart) · JUnit (Kotlin JVM) · jest + supertest (server) · integration_test |
| CI/CD | GitHub Actions (analyze / build-apk / integration_test / deploy-pages) |
| APK Signing | Gradle signingConfig: V1+V2+V3 all enabled (`enableV1/V2/V3Signing`); keys injected only via env vars or `android/key.properties` |

## Permission Description

| Permission | Purpose |
|------------|---------|
| `BIND_NOTIFICATION_LISTENER_SERVICE` (service permission) | Listen to system notifications |
| `INTERNET` / `ACCESS_NETWORK_STATE` | Send push requests, detect network recovery |
| `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_DATA_SYNC` / `FOREGROUND_SERVICE_SPECIAL_USE` | Foreground service survival (typed on Android 14+) |
| `WAKE_LOCK` | PARTIAL_WAKE_LOCK while listening / pushing |
| `VIBRATE` | Notification vibration feedback |
| `RECEIVE_BOOT_COMPLETED` | Boot auto-start |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Battery optimization whitelist |
| `POST_NOTIFICATIONS` / `POST_PROMOTED_NOTIFICATIONS` | Persistent and promoted notifications on Android 13+ |
| `SCHEDULE_EXACT_ALARM` | On-time delayed/scheduled pushes (falls back to inexact alarms when not granted) |
| `RECEIVE_SMS` / `READ_SMS` | Dual-path SMS listening (broadcast + SMS provider), verification-code extraction |
| `READ_PHONE_STATE` | Incoming call state detection and push |
| `QUERY_ALL_PACKAGES` | Installed app list (app filter / rule applicable apps) |
| `REQUEST_INSTALL_PACKAGES` | In-app update install confirmation |
| `READ_EXTERNAL_STORAGE` (≤ API 32) / `WRITE_EXTERNAL_STORAGE` (≤ API 28) | Archive/export directory access on legacy devices |
| `com.fnthink.notice.permission.WIDGET_CONTROL` (signature, custom) | Widget toggle broadcast protection against forged broadcasts |

## Project Structure

```
noticeTransmit/
├── lib/                          # Flutter code (69 Dart files)
│   ├── main.dart                 # Entry point (init order + WorkManager registration)
│   ├── update_manager.dart       # In-app update (multi-source fallback + sha256 check)
│   ├── database/                 # Database layer (database_helper.dart, SQLCipher schema v10)
│   ├── di/                       # get_it service registration (service_locator.dart)
│   ├── l10n/                     # i18n (arb/app_zh.arb · app_en.arb, 853 keys each + generated code)
│   ├── models/                   # Data models (4 files)
│   │   ├── notification_record.dart  # Notification record model
│   │   ├── webhook_channel.dart  # Webhook channel model (12 types + message formats)
│   │   ├── email_channel.dart    # Email channel model
│   │   └── notification_rule.dart # Rule engine model (conditions/actions)
│   ├── pages/                    # Pages (27 files)
│   │   ├── main_page*.dart       # Home page (actions / dialogs / update split with same prefix)
│   │   ├── history_page.dart     # History (search / export / batch re-push)
│   │   ├── stats_page.dart       # Stats + delivery health dashboard
│   │   ├── webhook_settings_page.dart · email_settings_page.dart · app_channel_*_page.dart
│   │   ├── rule_list_page.dart · rule_edit_page.dart · rule_tester_page.dart
│   │   ├── battery_page.dart · temperature_page.dart
│   │   ├── sms_monitor_settings_page.dart · app_filter_page.dart · keywords_page.dart
│   │   ├── backup_restore_page.dart · widget_guide_page.dart · permission_settings_page.dart
│   │   └── splash_page.dart · more_page.dart · privacy_policy_page.dart
│   ├── services/                 # Service layer (24 files)
│   │   ├── platform_channel.dart # Unified MethodChannel declaration
│   │   ├── notification_service.dart · webhook_service.dart · app_channel_service.dart
│   │   ├── filter_service.dart   # App filter / keywords / rule matching (Dart side)
│   │   ├── rule_template_service.dart · rule_trace.dart
│   │   ├── battery_service.dart · temperature_service.dart
│   │   ├── sms_service.dart · email_service.dart · backup_service.dart
│   │   ├── archive_worker.dart   # WorkManager daily archive
│   │   ├── pinned_http_client.dart · secure_storage_service.dart
│   │   └── icon_service.dart · locale_service.dart · theme_service.dart · device_info_service.dart …
│   ├── theme/                    # Theme configuration (app_colors.dart / app_theme.dart)
│   └── widgets/                  # Reusable widgets (4: icon picker tile / text selection menu / iOS dialog buttons / template sheet)
├── android/                      # Android native code
│   └── app/src/
│       ├── main/kotlin/com/fnthink/notice/   # Main sourceset (51 Kotlin files)
│       │   ├── MainActivity.kt       # Main Activity (MethodChannel dispatch entry)
│       │   ├── NotificationMonitorService.kt  # Notification listener service
│       │   ├── NotificationProcessor.kt       # Notification processor module
│       │   ├── BatteryMonitor.kt              # Battery / temperature monitor module
│       │   ├── WebhookSender.kt · AppChannelSender.kt  # Webhook and self-built app channel senders
│       │   ├── ChannelRegistry.kt             # Channel descriptor table (single place to add a channel)
│       │   ├── RuleEngine.kt · FilterEngine.kt · TemplateEngine.kt  # Rule / filter / template engines
│       │   ├── RetryQueue.kt · DelayedPushManager.kt · MergePushManager.kt  # Retry / delay / aggregation
│       │   ├── SmsReceiver.kt · SmsObserver.kt · PhoneCallReceiver.kt  # Dual-path SMS / calls
│       │   ├── PushToggleWidgetProvider.kt · PushToggleWidgetWideProvider.kt  # 2×2 / 4×2 widgets
│       │   ├── BootReceiver.kt        # Boot broadcast receiver
│       │   ├── NetworkClient.kt       # OkHttp client (optional cert pinning)
│       │   ├── ConfigManager.kt · SecurePrefs.kt  # Config and encrypted storage
│       │   └── channels/              # MethodChannel handlers (permission 23 / config 30 / device 13 / file 12 / stats 9 = 87 methods)
│       ├── test/                  # Kotlin JVM unit tests (26 test classes / 234 cases) + golden snapshots
│       └── androidTest/           # Instrumented tests (APK signature verification)
├── server/                       # Server (update service + TOTP admin console)
│   ├── server.js                # Server entry point (startup + graceful shutdown)
│   ├── lib/                     # Modular layers (app/store/otp/middleware + routes/)
│   ├── test/                    # jest + supertest HTTP contract tests (29 cases)
│   ├── data/                     # Version configuration data
│   │   └── version.json          # Version info (version/build/sha256/per-ABI download URLs)
│   ├── public/                   # Official site and GitHub Pages static site
│   └── README.md                # Server deployment documentation
├── test/                         # Dart tests (37 files / 379 cases)
├── integration_test/             # On-device smoke test (smoke_test.dart, 7 steps)
├── .github/                      # workflows/ (CI) and scripts/ (format, version consistency, local release)
├── docs/                         # cert_rotation_runbook.md · roadmap.md
├── assets/                       # Resource files
│   ├── app_icon.png
│   ├── app_icon.svg
│   └── icons/
├── pubspec.yaml                  # Flutter configuration (version: 1.5.74+113)
└── README.md                     # Project documentation
```

## Quick Start

### Environment Requirements

> **Important**: This project uses **AGP 9.3.0** + **Gradle 9.5.0**, which has minimum version requirements for Flutter / Dart / Android Studio.

| Tool | Minimum Version | Recommended Version | Description |
|------|----------------|--------------------|-------------|
| **Flutter SDK** | 3.44.0 | 3.44.x stable | AGP 9.x support starts from Flutter 3.44 (CI pins 3.44.4) |
| **Dart SDK** | 3.12.2 | 3.12.x | `pubspec.yaml` declares `sdk: ^3.12.2`, bundled with Flutter 3.44, no separate installation needed |
| **Android Gradle Plugin (AGP)** | 9.0.0 | 9.3.0 | Already configured in project |
| **Gradle** | 9.5.0 | 9.5.0 | Already configured (see gradle-wrapper.properties) |
| **Kotlin** | 2.3.20 | 2.3.20 | Explicitly declared via `org.jetbrains.kotlin.android` plugin in `settings.gradle.kts` |
| **Android Studio** | Koala (2024.1.1) | Latest stable | Need IDE version that supports AGP 9.x |
| **JDK** | 21 | 21+ | AGP 9.x requires JDK 21+ (`compileOptions` / `jvmTarget` are both 21) |
| **Android SDK** | 24 (minSdk) | 37 (compileSdk / targetSdk) | minSdk 24 (`flutter.minSdkVersion`), compileSdk and targetSdk are both 37 |
| **Node.js** (server only) | 24 | 24 LTS | `server/package.json` declares `engines.node >= 24`; CI and production run the same version |

#### Version Compatibility Notes

- **Flutter below 3.44**: Does not support AGP 9.x, build will fail. Please run `flutter upgrade` to upgrade to 3.44+.
- **AGP 8.x and below**: This project has migrated to AGP 9.x, cannot be downgraded.
- **Kotlin**: The project explicitly declares `org.jetbrains.kotlin.android` version 2.3.20 in `settings.gradle.kts`, and keeps `android.builtInKotlin=false` and `android.newDsl=false` in `gradle.properties`.

### Build APK

```bash
# Install dependencies
flutter pub get

# Code analysis
flutter analyze

# Build release version
flutter build apk --release --target-platform android-arm64
```

### Tests & Quality Checks

```bash
# Dart unit tests (37 files / 379 cases)
flutter test

# Kotlin JVM unit tests (26 test classes / 234 cases)
cd android && ./gradlew :app:testDebugUnitTest

# Android lint (errors fail the build; known false positives are held by android/app/lint-baseline.xml)
cd android && ./gradlew :app:lintDebug

# Server HTTP contract tests (29 cases, requires Node.js 24 LTS)
cd server && npm ci && npm test

# Three-way format check (dart format + ktlint 1.8.0 + prettier 3.9.8; add --fix to rewrite files)
bash .github/scripts/check_format.sh

# Version & documentation consistency gate
bash .github/scripts/check_version_consistency.sh

# On-device smoke test (requires a connected device or emulator; CI: integration_test.yml)
flutter test integration_test/smoke_test.dart
```

### Deploy Server

Two deployment modes are supported:

- **Node.js Server** (full features): See [server/README.md](server/README.md) · [server/README-en.md](server/README-en.md)
- **GitHub Pages** (zero-maintenance static): See [server/GITHUB_PAGES.md](server/GITHUB_PAGES.md) · [server/GITHUB_PAGES-en.md](server/GITHUB_PAGES-en.md)

The client automatically falls back between modes with no code changes needed.

## Quality & CI

**Test scale** (all executable; every group except the on-device tests is enforced in the PR gate):

- **Dart unit tests** - 37 test files / 379 cases (`test/`): architecture contracts (bootstrap order, launcher manifest contract, channel-method parity across both ends), database schema and migrations, backup / delivery / filter golden cases, page widget tests
- **Kotlin JVM unit tests** - 26 test classes / 234 cases (`android/app/src/test/`): Dart/Kotlin rule-matching parity is locked by 51 golden cases in `rule_engine_golden.json`, and channel behaviour by byte-exact snapshots in `channel_behavior_golden.json` (48 payloads + 34 response parses)
- **Server contract tests** - 29 cases (`server/test/auth.test.js`, jest + supertest): login / TOTP enable & recovery-code consumption / session invalidation / IP blocking
- **On-device tests** - `integration_test/smoke_test.dart` runs a 7-step main-path smoke test (launch → inject → notification page → delivery status → history → service start/stop → export), plus the `android/app/src/androidTest` instrumented tests, driven by `integration_test.yml` on an API 34 / x86_64 / Pixel 6 emulator

**CI workflows** (`.github/workflows/`, all on `ubuntu-24.04`):

- **`analyze.yml` (PR gate, 16 steps)** - flutter analyze → version consistency → code metrics → Dart tests → Android JVM tests → Android lint → server contract tests → three-way format check → coverage artifact
- **`build-apk.yml` (on `v*` tags or manual, 18 steps)** - pre-flight tests & analyze → arm64 release build → ABI purity & version double gate → GitHub Release
- **`integration_test.yml` (manual, 7 steps)** - emulator smoke test + instrumented tests
- **`deploy-pages.yml` (on changes to `server/public/**` or `server/data/version.json`, or manual, 5 steps)** - zero-maintenance static version source publishing
- **Format unification** - `.github/scripts/check_format.sh` is the same script locally and in CI: `dart format` + ktlint 1.8.0 (rules in `.editorconfig`) + prettier 3.9.8 (config in `server/.prettierrc`)
- **Version consistency gate** - `.github/scripts/check_version_consistency.sh` compares version & build across `pubspec.yaml` / `update_manager.dart` / `MainActivity.kt` / `server/data/version.json`, and additionally validates the sha256 fields of `version.json`, website i18n coverage, README dependency annotations and the zh/en ARB key sets
- **Local release pre-flight** - `.github/scripts/release_local.sh <A.B.C>`: version consistency → format/analyze → 4-ABI APK builds & purity checks → fileSize/sha256 back-fill into version.json → badge and update.md completeness checks

## Contribution

Welcome to submit Issues and Pull Requests!

- Contributing: See [CONTRIBUTING.md](CONTRIBUTING.md) · [English](CONTRIBUTING-en.md)
- Security Policy: See [SECURITY.md](SECURITY.md) · [English](SECURITY-en.md)
- Code of Conduct: See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) · [中文](CODE_OF_CONDUCT-zh.md)

## Privacy Notice

### Data Collection Statement

This application values user privacy. The following is a statement about data collection:

| Data Type | Collected | Description |
|-----------|-----------|-------------|
| **Notification Content** | ❌ Not uploaded | All notifications are processed and pushed locally only |
| **Contacts/SMS** | ❌ Not uploaded | Only used locally for push, not uploaded to any server |
| **Device ID** | ⚠️ Only when crash reporting is on | Used by Bugly SDK for device deduplication; crash reporting is off by default |
| **Crash Information** | ⚠️ Only when crash reporting is on | Collected via Bugly only after user opt-in |

### Bugly Crash Reporting (Off by Default, Opt-in)

- **Default state**: Off. The Bugly SDK is **not initialized** on cold start and makes no network requests; it is initialized only after the "More → Crash Reporting" switch is turned on (treated as user consent)
- **Purpose**: Only for collecting app crash information to help developers quickly locate and fix issues
- **Collected Content**: Crash stack, app version, system version, device model, CPU architecture
- **Log Protection**: Release builds strip all debug/info logs (`Log.v/d/i`) via R8; log output never contains notification titles, SMS bodies, verification codes or phone numbers, and the logs attached to crash reports follow the same rule
- **Data destination**: Uploaded to Tencent Bugly servers ([https://bugly.qq.com](https://bugly.qq.com)), accessible only by the developer for issue analysis
- **Not Collected**: User contacts, SMS content, notification content, location information or any personal privacy data
- **How to disable**: Turn off the "More → Crash Reporting" switch; since the SDK cannot be de-initialized at runtime, disabling takes full effect after the next cold start
- **Compliance**: Disclosed per the minimal-necessity principle of China's PIPL; no data leaves the device before the switch is enabled

### Push Data

All notification pushes are sent through channels you configure yourself (Webhook / self-built app / email); developers do not store any push content. Only after crash reporting is enabled does Bugly collect the minimal necessary crash statistics (stack trace, device model, system version, app version), which contain no personal privacy data.

### Distribution Channels

This app includes sensitive permissions such as `RECEIVE_SMS` / `READ_SMS` / `REQUEST_INSTALL_PACKAGES` (core to its SMS notification recognition/forwarding and in-app update features), which do not comply with Google Play's policy on SMS permissions. It is therefore **not distributed via Google Play**; APKs are distributed through official channels such as the project website and GitHub Releases. Please obtain installation packages only from trusted sources.

## FAQ & Troubleshooting

### Not receiving notifications?
1. Is Notification Access permission enabled
2. Is battery optimization disabled
3. Is foreground service running
4. Is auto-start/background permission enabled for OEM devices
5. Is Webhook URL correct (testable in settings page)
6. Is the notification filtered by app filter / keyword filter

## License

This project is open source under the [MIT License](LICENSE).
