<div align="center">

<img src="assets/app_icon.png" width="128" alt="Notice Push Assistant">

# Notice Push Assistant

**[English](README-en.md) / 中文**

A privacy-first Android notification forwarding and device collaboration tool. Three tracks:

- **Notification forwarding** — listen to the notification shade and deliver through 12 Webhook channel types, WeCom/Feishu self-built app channels, or SMTP mail
- **Fnthink Push** — direct device-to-device delivery: no third-party account, no platform relay, signed and verifiable, with real delivery receipts
- **Remote Control** — issued from another paired device, per-item authorization, cancellable, with receipts

[![Flutter](https://badgen.net/badge/Flutter/3.44%2B/02569B?icon=flutter)](https://flutter.dev/)
[![AGP](https://badgen.net/badge/AGP/9.3.0/3DDC84?icon=android)](https://developer.android.com/build/releases/gradle-plugin)
[![Gradle](https://badgen.net/badge/Gradle/9.5.0/02303A?icon=gradle)](https://gradle.org/)
[![Platform](https://badgen.net/badge/Platform/Android/3DDC84?icon=android)](#)
[![Version](https://badgen.net/badge/Version/1.5.76/007AFF?icon=android)](https://github.com/fnthinklevi/noticeTransmit/releases)
[![License](https://badgen.net/badge/License/Apache--2.0/green)](#license)

🌐 **Official site**: [notice.fnthink.top](https://notice.fnthink.top) · [notice.fnthink.com](https://notice.fnthink.com) — introduction, client download and admin console

🌐 **GitHub Pages**: [fnthinklevi.github.io/noticeTransmit](https://fnthinklevi.github.io/noticeTransmit/) — zero-ops static deployment (auto-syncs version config)

</div>

## Table of Contents

- [Introduction](#introduction)
- [Features](#features)
- [Fnthink Push](#fnthink-push)
- [Remote Control](#remote-control)
- [Technology Stack](#technology-stack)
- [Permission Description](#permission-description)
- [Project Structure](#project-structure)
- [Quick Start](#quick-start)
- [Quality & CI](#quality--ci)
- [Privacy Notice](#privacy-notice)
- [FAQ & Troubleshooting](#faq--troubleshooting)
- [Contribution](#contribution)
- [License](#license)

---

## Introduction

Notice Push Assistant is a privacy-first Android notification forwarding and device collaboration tool (Flutter + Kotlin).

**Track 1 — Notification forwarding.** Listen to notification-shade messages and deliver them in real time through 12 Webhook channel types (Generic / WeCom / DingTalk / Feishu / Telegram / Bark / ServerChan / PushPlus / ntfy / Gotify / Slack / Discord), WeCom & Feishu **self-built app channels**, or SMTP mail; the home-screen widget toggles push with one tap. Forwarded content always goes to channels you configured yourself — the developer never handles it.

**Track 2 — Fnthink Push.** Two devices talk directly after pairing, with no third-party account and no platform relay; every message is signed with the sender's Ed25519 private key and verified by the receiver, and the server stores delivery metadata only — never the body. A delivery state machine plus receipts make "sent" and "received" distinguishable.

**Track 3 — Remote Control.** Instructions issued from another paired device, split into L2 (app actions) and L3 (system settings): four L2 actions and six L3 settings, each granted individually, each with a cancellable delay window before execution and two-stage receipts afterwards.

Fully bilingual (1251 keys × 2 languages). Apache License 2.0, free and ad-free.

---

## Features

### Listening & Recognition

- 🔔 **Notification Listening** — listen to notification messages from all apps on the system
- 📱 **Multi-type Recognition** — smart recognition of WeChat, QQ, SMS, phone calls, system notifications, etc.
- 📩 **SMS dual-path** — `SMS_RECEIVED` broadcast is the primary path, with an SMS-database ContentObserver catching messages the broadcast misses; both paths are deduplicated by content fingerprint so nothing is pushed twice; verification codes are extracted automatically and delivered as a dedicated field
- 📞 **Call recognition** — incoming-call state is monitored and pushed, optionally with a bilingual "SIM 1, Carrier" info line
- 🎚️ **SIM filtering** — SIM-slot filtering shared by the SMS and call paths; auto-disabled on single-SIM devices
- 🛡️ **Listener Reliability** — fallback content extraction for conversation-style notifications whose body only exists in MessagingStyle; the dedup key includes the notification tag to avoid missed reads; warns "listener disconnected · notifications may be missed" and auto-rebinds when notification access is revoked; **after the OS recycles the service, startup re-scans still-visible notifications against a persisted watermark** (up to 6 hours back), greatly reducing missed notifications during long screen-off / background periods
- 🔋 **Custom Battery Reminders** — fully customizable battery rules (charging / discharging / level thresholds), add / edit / delete, swipe-left and long-press to delete
- 🌡️ **Device Temperature Push** — three independent dimensions (battery temperature / device overall temperature / screen temperature) with custom thresholds; 30-minute cooldown prevents repeated pushes from fluctuation; shares the same polling source with battery push (no conflict)

### Forwarding channel families

- 🔗 **Webhook, 12 types** — Generic / WeCom / DingTalk / Feishu / Telegram / Bark / ServerChan / PushPlus / ntfy / Gotify / Slack / Discord; configure multiple channels at once, each with an independent on/off switch; hosted endpoints are auto-detected from the URL host, and for self-hosted ntfy / Gotify the manually chosen type is respected across save / send / test
- 🏢 **Self-built App Channels (WeCom / Feishu)** — an app-channel system independent of Webhooks: send as your own app by providing corpsecret / app_secret; WeCom can target touser / @all, Feishu can specify chat_id / open_id; the API base URL can point at self-hosted deployments; secrets are encrypted at rest and delivery / retry behave the same as Webhook channels; **built-in step-by-step setup guide** (tap "?" on a card for how to obtain corpid / AgentId / Secret or App ID / App Secret, plus notes); **layered list page** shows channel name, type and connection status at a glance
- 📧 **SMTP Email Push** — SMTP forwarding (SSL / STARTTLS), customizable subject and body templates
- 📨 **Fnthink Push channel** — a fourth forwarding family: multiple channels, each targeting either a checked bound device or a webhook address; incoming notifications are forwarded automatically (see [Fnthink Push](#fnthink-push))
- 📤 **Multi-platform Adaptation** — auto-adapt message format for WeChat Work, DingTalk, Feishu, Telegram, Bark, ServerChan, PushPlus, ntfy, Gotify, Slack, Discord and other platforms (ntfy / Gotify support self-hosted servers); in-app update APKs carry sha256 integrity verification, and Bark business failures are reported truthfully instead of as success
- 💚 **Channel Health Probe** — the Webhook settings page light-probes enabled channels (any HTTP response counts as reachable; only timeout / DNS failure / connection refused is judged unreachable); channels stale for over 6 hours are re-probed in the background and persisted, and each card shows a "✓ reachable · latency · probe time" badge; business-level health is reflected by the delivery log of the most recent real push

### Rules & Automation

- 🧠 **Rule Constraints** — visual configuration of notification rules, condition combination (IF) and action configuration (THEN), a feature guide on first entry, built-in default rules including verification-code priority push, marketing ad blocking, night do-not-disturb and app notification aggregation (ready out of the box; missing rules are filled in automatically on upgrade); rule priority supports quick presets and custom values (0-500), and each rule can exclude specific apps (a "Quick Select" area auto-detects mainstream messaging / email apps installed on the device, with system SMS & phone components merged into single rows offering three-state group toggles, pinned on top)
- 🧪 **Rule Tester** — enter a simulated notification and see the full trace in real time: filter → rule matching → final action, so rule issues are obvious at a glance
- 📚 **Rule Template Library** — five built-in presets (verification-code priority / marketing ad blocking / night do-not-disturb / social message aggregation / whitelist keyword express) importable in one tap; custom rules can be saved as templates for reuse (same name overwrites); templates export as a `.json` file, optionally password-protected with the same PBKDF2 210k + AES-256-GCM scheme as config backup, and import auto-detects plain / encrypted format
- 📤 **Batch re-push for failed records** — filter failed records in push history and re-push them in one tap; failed pushes are auto-retried (on network recovery / service restart)
- 📦 **App Notification Aggregation** — notifications from the same app are merged into a single push within a window (60 s by default, configurable, 5 s minimum), greatly reducing message floods; supports "flush early at N items" (no need to wait for the window) and "group by conversation" (same app, different contacts aggregate separately); custom templates support `%count%` / `%titles%` variables and rule conditions support the `*` wildcard to match any app; a single message during the window is sent as a normal push; while merging, the foreground notification shows the pending list with a countdown; whether aggregation succeeds or fails, member content is always saved to push history first, and each member record is labeled with its real delivery status
- 🏷️ **Notification Priority Levels** — system notification priority (high / medium / low) extracted natively, matchable via the "notification priority" condition; rule actions truly executed natively — silent ignore / record only / delayed push / push now
- ⏰ **Scheduled / Delayed Push** — "delayed push" action configurable (delay seconds / schedule HH:mm), auto re-push webhook & mail when due (may be delayed by minutes in deep Doze), tasks auto-recover after process kill or reboot
- 📝 **Push Template Engine** — custom message format (text / markdown / json / xml), variable placeholders (`%appName%` / `%title%` / `%content%`), auto-wrapped and escaped per platform, configured independently per channel
- 📟 **Home Screen Widget** — 2×2 / 4×2 dual sizes with adaptive width layout, one-tap push toggle from the home screen; shows daily push count (auto-resets at midnight); one-tap add to home screen
- 📱 **App Filtering** — customize which apps need notification push
- 🏷️ **Keyword Filtering** — whitelist and blacklist keyword filtering for precise push control

### History, Stats & Health

- 📋 **History Records** — locally save push history, support search, detail view and export; long-press for quick block actions (block the app / block notifications containing this content)
- ✅ **Delivery Status Labeling** — each push record on the home page is labeled per-channel delivery status (success / failed / sending / user-paused), determined by official return codes from WeChat Work / Feishu / DingTalk; SMS / call delivery results are reported back in real time; failure reasons (e.g. HTTP 502 / rate-limit hints) are shown inline
- 📈 **Delivery Health Dashboard** — a "delivery health" section on the stats page: per-channel success-rate ranking (green / orange / red), top failure reasons clustered by HTTP status (502 / 429 / network failures), and a 24-hour peak-hours bar chart; toggle between the last 7 / 30 days, aggregated from the delivery log and notification records
- 🗂️ **Daily Auto Archive** — WorkManager exports the previous day's push history as a JSON file every day (the full history stays in the database — archiving is a backup, it never deletes the source records); a custom archive directory (SAF) can be chosen, and foreground startup completes the archive for custom-directory mode

### Experience & Interface

- 🌐 **Multi-language i18n** — Chinese / English (`app_zh.arb` / `app_en.arb`, 1251 keys each, generated by gen-l10n; CI locks both key sets together so nothing goes untranslated), switch language freely in settings; the language label is pushed to the native side so the persistent notification and push copy follow suit
- 🖼️ **Launcher Icon Switching** — 17 icon styles × Chinese/English labels = 34 launcher icon aliases, switched in one tap inside the app (only one alias is enabled at a time, the rest are disabled)
- 📄 **Text Selection Menu Adaptation** — menu button labels (copy / cut / paste / select all / share) for all 36 text fields use app-localized strings, eliminating blank or English labels on vendor ROMs
- 🎨 **Dialog iOS Style Unification** — all confirm dialogs use divider button layout (cancel = secondary / confirm = blue / delete = red), adaptive for light / dark themes
- 🔄 **Notification State Machine Optimization** — unified show / hide logic across 5 scenarios (start / stop / process kill / keep-alive / permission missing), the persistent notification syncs in real time with the monitoring state
- 🌙 **Dark Mode** — light / dark / follow system three theme modes
- 📲 **Cupertino Design Language** — the whole app uses the iOS design language through a single `AppRoot` assembly point, with a clean and elegant interface
- 🛡️ **Background Survival** — foreground service + battery optimization whitelist + boot auto-start; built-in OEM ROM keep-alive guide (battery unrestricted / auto-start / task lock, one-tap jump to vendor settings)
- 🩺 **Runtime Diagnostics Switch** — tap the version number 7 times on the More page to toggle diagnostic logs (rule / merge `[diag]` logs in logcat, excluding notification titles / bodies) — troubleshoot without reinstalling
- 💾 **Config Backup & Restore** — export **12 categories of configs** (Webhook / mail channels with credentials, self-built app channels with credentials, notification rules, SMS settings, app filter, keyword lists, battery rules & switch, temperature rules, device name, theme / language, Fnthink config) encrypted as a `.nbackup` file (AES-256-GCM + PBKDF2 210k-iteration passphrase derivation, self-describing KDF header). Restore after switching or reinstalling by picking the file and entering your passphrase; conflict strategy offers "overwrite all / fill gaps only" when existing configs are detected, non-https URLs are skipped automatically; backup format v2 is backward compatible with v1
- 📱 **Home-Screen Widgets Upgraded** — fully redesigned 2×2 / 4×2 layouts (status ring, hint pill, daily counter); the system pin dialog now shows a preview and description, and launchers without pin support automatically open a brand-specific step-by-step guide. New SMS monitoring settings hub: listening toggle / verification-code toggle / SIM-card selection (auto-disabled on single-SIM devices); card filtering applies to both SMS and call paths, and pushed messages can carry a bilingual "SIM 1, Carrier" info line
- 🔐 **Opt-in Crash Reporting** — off by default and initializes only after user consent; toggleable anytime in settings; release builds strip all debug / info logs via R8, and logs never contain notification titles, SMS bodies, verification codes or phone numbers
- ⏸️ **One-tap Pause Push** — pause / resume via the foreground notification action button (monitoring continues, only webhook sending stops), state persists across restarts; messages received while paused show a "user-paused" status in history, with a one-tap "push now" manual resend
- 🔄 **Online Update** — no need to reinstall the APK; downloads via the system downloader (DownloadManager) in the background — no storage permission needed, uninterrupted when the screen is off; multi-source fallback (CDN / GitHub mirror / GitHub direct, matched by device ABI); flexible deployment modes (Node.js server / GitHub Pages static deployment, client auto-compatibility)
- 🔒 **Full Privacy Policy** — in-app 11-chapter privacy policy (data collection scope / encrypted storage / information sharing / children's privacy / user rights, etc.); the first-launch dialog carries a tappable "Privacy Policy" link, so the full text is readable **before** you consent, and it stays available anytime from the More page
- 📊 **Unified Push Stats** — home / More / status bar push stats share the same database source, daily count syncs in real time
- 🔋 **Wake-up Fallback** — exact alarms plus a one-shot WorkManager task, so a killed process still wakes up on time; the alarm is re-armed after reboot

### Security

- 🔐 **Two-step Verification (TOTP)** — admin panel login requires two-step verification, compatible with Google Authenticator
- 🔑 **bcrypt Hashing** — token verified using bcrypt hashing to prevent brute force attacks
- 🛡️ **IP Blocking** — IP automatically blocked for 1 hour after 5 failed verification attempts within 10 minutes
- 🔢 **Recovery Codes** — 8 recovery codes generated for account recovery when device is lost
- 🔒 **Sensitive Data Encryption** — TOTP secret stored using AES-256-GCM encryption
- 🎭 **Obfuscation Rules Ready** — ProGuard / R8 rules file configured (`proguard-rules.pro`), release builds enable code obfuscation and resource shrinking
- 📡 **Secure Token Transmission** — token only accepted via Header, URL parameters disabled
- 🎲 **Cryptographic Randomness** — session IDs generated using `crypto.randomUUID()`
- 🗄️ **SQLite Encryption** — notification records, Webhook / mail / self-built app channel configs and the delivery log (schema v20, 16 tables) are all stored with SQLCipher AES-256 encryption; the key is held in AndroidKeyStore via flutter_secure_storage
- 🔑 **Webhook Key Protection** — Webhook URLs (including DingTalk / WeCom / Feishu auth keys) encrypted via AndroidKeyStore
- 🔐 **SSL Certificate Pinning** — both HTTP clients are ready (Dart `PinnedHttpClient` + the OkHttp `CertificatePinner` in Kotlin `NetworkClient`), forming the HTTPS certificate security layer, **disabled by default** (requires injecting `CERT_PINS` / `ENABLE_CERT_PINNING`; always off in Debug builds), currently protected indirectly via Cloudflare CDN; see [docs/cert_rotation_runbook.md](docs/cert_rotation_runbook.md) for rotation / enablement
- 🧩 **Widget Broadcast Guard** — home-screen widget toggle broadcasts are protected by the signature-level custom permission `com.fnthink.notice.permission.WIDGET_CONTROL`, so third-party apps cannot forge a `TOGGLE_PUSH` broadcast to silently pause or resume pushes
- 🔒 **Mandatory HTTPS** — site-wide HTTPS enforced via `network_security_config.xml`

---

## Fnthink Push

> Setup and deployment: [docs/server_deploy_and_update_guide.md](docs/server_deploy_and_update_guide.md). Protocol contract: `protocol/fnthink-v1.json`.

### What problem it solves

The usual convention for notification tools is "you hand your content to a third-party platform and it forwards for you". Fnthink Push takes a different route: **two devices talk to each other directly**. The server in the middle only buffers and relays — it holds no body text and there is no third-party account system at all.

- 🔑 **No account, no third party** — a pairing code or pairing link is all it takes; each device has its own address code, independent of any platform account system
- ✍️ **Verifiable signatures** — every message is signed with the sender's Ed25519 private key and verified before delivery; the key is generated inside AndroidKeyStore and never uploaded
- 🗄️ **Server keeps no message body** — only delivery metadata (sender, type, time, state); body text is never stored (contract `privacy.serverStoresBodyPlaintext = false`)
- 🔁 **Delivery state machine** — `queued → delivering → delivered → acked`; the receiver acks after rendering, and **the ack is the only delivery evidence**; failures and resends have explicit states rather than guesswork
- ↩️ **Revocable** — revoking on the receiver side takes effect immediately, no need to wait for the peer to go offline
- 🌐 **Two regions** — Chengdu `*.fnthink.com` and Los Angeles `*.fnthink.top`; pick one from the More page. Fully self-hostable
- 📨 **Forward onward** — after receiving a message, forward it through your configured **Fnthink channels** to a bound device or a webhook address

### Capability levels

| Level | Meaning | How it is obtained |
|-------|---------|--------------------|
| **L1** | Messages | Granted by pairing, no per-item selection |
| **L2** | App actions | Granted item by item |
| **L3** | System settings | Off by default, each item enabled separately, a cancellable window before every execution |

**The grant lives on the receiving device** (confirmed by the receiver at pairing time and written into its own `grantsBy`). The sender's own record carries no grant to read — that is not a stylistic choice: the receiving side reads exactly that one copy.

---

## Remote Control

> The authoritative source is the contract's `capabilities.remoteExecution` / `.l2` / `.l3` sections; below is their prose equivalent.

### What each level can do (**closed vocabulary** — anything outside it is rejected)

**L2 app actions (4)**

| item | action | argument |
|------|--------|----------|
| `listener:start` | Start notification listening | — |
| `listener:stop` | Stop notification listening | — |
| `channel:toggle` | Toggle one forwarding channel | channel id (**required**) |
| `device_state:push` | Push the full device snapshot | — |

**L3 system settings (6)**

| item | action | mode | lands on |
|------|--------|------|-----------|
| `notification` | Notification listener access | `grant` | jump to the system settings page for the user to tap |
| `exact_alarm` | Exact alarms | `grant` | jump to the system settings page |
| `battery_optimization` | Battery optimization exemption | `grant` | jump to the system settings page |
| `autostart` | OEM auto-start | `grant` | vendor-specific pages (Xiaomi / Meizu / Huawei / OPPO / vivo each differ) |
| `monitoring` | Local monitoring switch | `toggle` | local prefs |
| `collect_inbox` | Fnthink inbox switch | `toggle` | local prefs |

⚠ **There are exactly two modes**: `grant` hands an authorization to this device (irreversible on the system side — the user must tap), `toggle` flips one of this device's own switches. **There is no third "silently change system settings" mode** — the native side has never had that capability, so claiming it would promise something that cannot be done. Unknown items / actions are `reject`ed, never "skip what we don't recognize".

### Security model (every cell is load-bearing)

- 🔑 **Credentials**: an advanced key (remote-control specific, ≥ 8 chars, generated by the receiver and stored only as a hash) or TOTP (6 digits / 30 s, generated by the receiver and **never passing through the server**, handed over in person via QR code or link). L2 may carry either or neither; **L3 must carry one of them** — missing or wrong is rejected
- ⏱️ **Delay window**: 10 seconds by default (0–60 configurable) before execution; during the window it can be cancelled from **the status-bar notification** or **the in-app banner**; on timeout it executes by default. Whether the user is standing at the device **does not affect timing** — this is a visible chance to revoke, not a second confirmation dialog
- 🚫 **Not bypassable**: `allowSkipConfirm: false` — the window cannot be turned off or skipped
- 🧯 **Circuit breaker**: 5 failures per minute downgrades to L1
- 🔄 **Idempotent**: delivery is at-least-once, so an L3 `toggle` may carry a target value (`on` / `off`) — a redelivery will not flip it back; the old form without a target is still accepted and read-modify-flips, so **older peers need no upgrade**
- 📜 **State machine**: `pending → executing → done / failed / cancelled`; five closed states, and `cancelled` (you revoked in the window) is deliberately separate from `failed` (it ran and did not succeed)
- 🧾 **Two-stage receipts**: `started` on receipt and `finished` with the result on completion, both sent as **messages back to the sender**, not as acks — an ack only answers "I received this delivery", a receipt answers "how far did I get with this task"; mixing them lets at-least-once redelivery pollute "executing"
- 🚫 **Endpoints cap at L1**: messages arriving through a third-party platform endpoint reach **at most L1**; webhook is only trusted as an instruction source when it is the Fnthink channel's own webhook — a foreign webhook is never a source, because its payload fields are written by a third party and treating it as an instruction source hands them control of the instruction format
- 📍 **Local triggers get no receipt**: instructions triggered by a local whitelisted app's notification have no remote sender to answer, so they only land in the local remote-execution history

### The two kinds of keys are not the same key

- **Device identity private key** — proves "I am this device"
- **Remote-control advanced key / TOTP** — authorizes "this remote instruction"

⚠ There is deliberately **no "unlock L3 with a local lockscreen or biometric"** step: it was never wired up (the only implementation in the repo always answers "this device has no authenticator"), so keeping it would advertise an action that does not exist. L3's security rests solely on the peer presenting a valid credential.

---

## Technology Stack

| Module | Technology |
|--------|------------|
| Frontend | Flutter 3.44.x (Dart 3.12.2) |
| State Management / DI | get_it (^9.2.1) + Service classes |
| Local Database | sqflite_sqlcipher (^3.4.0) · SQLCipher AES-256 · schema v20 / 16 tables |
| Key-Value Storage | shared_preferences · flutter_secure_storage (^9.2.4) + androidx.security EncryptedSharedPreferences |
| Native Service | Kotlin 2.3.20 (Android), 78 Kotlin files in the main sourceset |
| HTTP Client | http (Dart) / OkHttp 4.12.0 (Kotlin) |
| Email Sending | com.sun.mail:android-mail 1.6.7 (SMTP) |
| Notification Listening | NotificationListenerService |
| Background Survival | Android native Foreground Service + WakeLock (PARTIAL_WAKE_LOCK) |
| Background Tasks | workmanager ^0.6.0 (daily archive + wake-up fallback) |
| Coroutines | kotlinx.coroutines (SupervisorJob + Dispatchers.IO) |
| Cross-platform Communication | MethodChannel `com.fnthink.notice/notification` (113 methods · 7 native handlers) |
| **Protocol Contract** | `protocol/fnthink-v1.json` (single source of truth) + `protocol/fnthink-vectors-v1.json` (cross-side vectors) |
| **Shared Protocol Package** | `packages/fnthink_push` (24 Dart files; both ends and the CLI read one contract and one vector table) |
| **Identity & Signature** | Ed25519 (AndroidKeyStore-backed, API 33+; 30–32 use a KeyStore-wrapped software key) |
| Internationalization | gen-l10n + ARB (1251 keys each for zh / en) |
| Crash Statistics | Tencent Bugly 4.1.9.3 (off by default) |
| Server | Node.js 24 LTS (`engines: >=24`) + Express 5.x (token auth + two-step verification + the Fnthink protocol surface) / GitHub Pages static deploy |
| Server Dependencies | bcryptjs · cors · dotenv · express · otplib · qrcode |
| TOTP / Password Hashing | otplib (^13.0.1) / bcryptjs (^2.4.3) |
| Data Encryption | Node.js crypto (AES-256-GCM) / AndroidKeyStore + flutter_secure_storage |
| Build Tools | Gradle 9.5.0 + AGP 9.3.0 + JDK 21 · minSdk 24 / compileSdk 37 / targetSdk 37 |
| Code Quality | flutter_lints ^6.0.0 · dart format · ktlint 1.8.0 · prettier 3.9.8 · Android lint (with baseline) |
| Testing | flutter test (Dart 2063 cases) · JUnit (Kotlin JVM 478 cases) · jest + supertest (server 599 cases) · integration_test |
| CI/CD | GitHub Actions (analyze / build-apk / integration_test / deploy-pages) |
| APK Signing | Gradle signingConfig: V1+V2+V3 all enabled (`enableV1/V2/V3Signing`); keys injected only via env vars or `android/key.properties` |

---

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
| `SCHEDULE_EXACT_ALARM` | On-time delayed / scheduled pushes (falls back to inexact alarms when not granted) |
| `RECEIVE_SMS` / `READ_SMS` | Dual-path SMS listening (broadcast + SMS provider), verification-code extraction |
| `READ_PHONE_STATE` | Incoming call state detection and push |
| `QUERY_ALL_PACKAGES` | Installed app list (app filter / rule applicable apps) |
| `REQUEST_INSTALL_PACKAGES` | In-app update install confirmation |
| `READ_EXTERNAL_STORAGE` (≤ API 32) / `WRITE_EXTERNAL_STORAGE` (≤ API 28) | Archive / export directory access on legacy devices |
| `com.fnthink.notice.permission.WIDGET_CONTROL` (signature, custom) | Widget toggle broadcast protection against forged broadcasts |

---

## Project Structure

```
noticeTransmit/
├── lib/                                  # Flutter code (150 Dart files)
│   ├── main.dart                         # Entry point (init order + WorkManager registration)
│   ├── update_manager.dart               # In-app update (multi-source fallback + sha256 check)
│   ├── database/database_helper.dart     # Database layer (SQLCipher schema v20, 16 tables)
│   ├── di/service_locator.dart           # get_it service registration
│   ├── l10n/arb/                         # app_zh.arb · app_en.arb (1251 keys each + generated)
│   ├── models/                           # Data models (10 files)
│   ├── pages/                            # Pages (40 files)
│   │   ├── main_page*.dart               # Home page (actions / dialogs / update split with same prefix)
│   │   ├── fnthink_push_page.dart · fnthink_channel_list_page.dart · fnthink_receive_page.dart
│   │   │                                 # Fnthink Push: switch / channels / inbox (remote-control instructions land here)
│   │   ├── history_page.dart             # History (search / export / batch re-push / direction filter)
│   │   ├── stats_page.dart               # Stats + delivery health dashboard
│   │   ├── webhook_settings_page.dart · email_settings_page.dart · app_channel_*_page.dart
│   │   ├── rule_list_page.dart · rule_edit_page.dart · rule_tester_page.dart
│   │   ├── battery_page.dart · temperature_page.dart · device_state_page.dart
│   │   ├── sms_monitor_settings_page.dart · app_filter_page.dart · keywords_page.dart
│   │   └── backup_restore_page.dart · permission_settings_page.dart · privacy_policy_page.dart · more_page.dart
│   ├── services/                         # Service layer (69 files)
│   │   ├── platform_channel.dart         # Unified MethodChannel declaration
│   │   ├── fnthink_receive_coordinator.dart  # Fnthink coordinator (send / receive / poll / record)
│   │   ├── fnthink_channel_mirror.dart   # Cross-end mirror of Fnthink channel configs (native reads it for primary/backup routing)
│   │   ├── fnthink_fanout_entrypoint.dart# Background entry for forwarding an incoming notification
│   │   ├── fnthink_l2_actions.dart · fnthink_l3_executor.dart  # Remote-control executors
│   │   ├── notification_service.dart · webhook_service.dart · app_channel_service.dart
│   │   ├── filter_service.dart · rule_template_service.dart · rule_trace.dart
│   │   └── archive_worker.dart · pinned_http_client.dart · secure_storage_service.dart · icon_service.dart …
│   ├── theme/                            # Theme configuration (app_colors.dart / app_theme.dart)
│   └── widgets/                          # Reusable widgets (21: AppRoot assembly point + iOS dialog family + selection menus)
├── packages/fnthink_push/                # Shared protocol package (24 Dart files)
│   └── lib/src/                          # Contract reading / validation / vectors, shared by both ends and the CLI
├── protocol/                             # Protocol contract (single source of truth)
│   ├── fnthink-v1.json                   # Fnthink protocol (capability table, limits, privacy boundary, …)
│   └── fnthink-vectors-v1.json           # Cross-side vector table (asserted on both ends)
├── android/app/src/
│   ├── main/kotlin/com/fnthink/notice/   # Main sourceset (78 Kotlin files)
│   │   ├── MainActivity.kt               # Main Activity (MethodChannel dispatch entry)
│   │   ├── NotificationMonitorService.kt  # Listener service (incl. primary/backup routing + forwarding for the Fnthink family)
│   │   ├── NotificationProcessor.kt · BatteryMonitor.kt
│   │   ├── FnthinkIdentityCodec.kt       # Identity policy (native / KeyStore-wrapped paths)
│   │   ├── FnthinkFanoutQueue.kt · FnthinkFanoutWorker.kt   # Forward queue + background engine
│   │   ├── FnthinkPresenceAlarm.kt · FnthinkPresenceWorker.kt # Wake-up fallback (alarm + one-shot task)
│   │   ├── RuleEngine.kt · FilterEngine.kt · TemplateEngine.kt
│   │   ├── RetryQueue.kt · DelayedPushManager.kt · MergePushManager.kt
│   │   ├── SmsReceiver.kt · SmsObserver.kt · PhoneCallReceiver.kt
│   │   ├── PushToggleWidgetProvider.kt · PushToggleWidgetWideProvider.kt
│   │   ├── BootReceiver.kt · NetworkClient.kt · ConfigManager.kt · SecurePrefs.kt
│   │   └── channels/                     # 7 handlers (config 34 / permission 26 / device 15 / file 13
│   │                                     #   / Fnthink 11 / stats 9 / remote-exec 5  = 113 methods)
│   ├── test/                             # Kotlin JVM unit tests (55 classes / 478 cases) + golden snapshots
│   └── androidTest/                      # Instrumented tests (6 files)
├── server/                               # Server (update service + TOTP console + Fnthink protocol surface)
│   ├── server.js · lib/                  # Entry point + modular layers (29 JS files)
│   │   └── lib/fnthink/                  # Fnthink surface (pairing / delivery / capabilities / endpoints / ops)
│   ├── test/                             # jest + supertest contract tests (34 files / 599 cases)
│   ├── public/                           # Official site and GitHub Pages static site
│   ├── data/version.json                 # Version info (version/build/sha256/per-ABI download URLs)
│   └── README.md · GITHUB_PAGES.md       # Deployment docs (zh + en each)
├── test/                                 # Dart tests (170 files / 2063 cases)
├── integration_test/                     # On-device smoke (5 files, includes the release gate)
├── docs/                                 # server_deploy_and_update_guide.md · cert_rotation_runbook.md (internal ledgers stay out of the repo)
├── .github/                              # workflows/ (CI) and scripts/ (format, version consistency, local release)
├── assets/                               # Resource files
├── pubspec.yaml                          # Flutter configuration (version: 1.5.76+116)
└── README.md
```

---

## Quick Start

### Environment Requirements

> **Important**: This project uses **AGP 9.3.0** + **Gradle 9.5.0**, which has minimum version requirements for Flutter / Dart / Android Studio.

| Tool| Tool | Minimum Version | Recommended Version | Description |
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
# Dart unit tests (170 files / 2063 cases)
flutter test

# Shared protocol package tests (must run inside the package directory)
cd packages/fnthink_push && dart test && cd ../..

# Kotlin JVM unit tests (55 test classes / 478 cases)
cd android && ./gradlew :app:testDebugUnitTest

# Android lint (errors fail the build; known false positives are held by android/app/lint-baseline.xml)
cd android && ./gradlew :app:lintDebug

# Server HTTP contract tests (599 cases, requires Node.js 24 LTS)
cd server && npm ci && npm test

# Three-way format check (dart format + ktlint 1.8.0 + prettier 3.9.8; add --fix to rewrite files)
bash .github/scripts/check_format.sh

# Version & documentation consistency gate
bash .github/scripts/check_version_consistency.sh

# On-device smoke test (requires a connected device or emulator; CI: integration_test.yml)
flutter test integration_test/smoke_test.dart
```

### Deploy Server

Two deployment modes are supported, and the client auto-detects between them with no code changes:

- **Node.js Server** (full features) — See [server/README.md](server/README.md) · [English](server/README-en.md)
- **GitHub Pages** (zero-maintenance static) — See [server/GITHUB_PAGES.md](server/GITHUB_PAGES.md) · [English](server/GITHUB_PAGES-en.md)

Fnthink Push deployment (two regions, where to upload the contract file, reverse proxy and `TRUST_PROXY`) is documented in [docs/server_deploy_and_update_guide.md](docs/server_deploy_and_update_guide.md).

---

## Quality & CI

**Test scale** (all executable; every group except the on-device tests is enforced in the PR gate):

- **Dart unit tests** — 170 test files / 2063 cases (`test/`): architecture contracts (bootstrap order, launcher manifest contract, channel-method parity across both ends, the Fnthink mirror key-name guard), database schema and migrations, backup / delivery / filter golden cases, page widget tests
- **Shared protocol package tests** — `packages/fnthink_push`: contract validation and vector assertions, run on both ends
- **Kotlin JVM unit tests** — 55 test classes / 478 cases (`android/app/src/test/`): Dart/Kotlin rule-matching parity is locked by 51 golden cases in `rule_engine_golden.json`, and channel behaviour by byte-exact snapshots in `channel_behavior_golden.json` (48 payloads + 34 response parses)
- **Server contract tests** — 599 cases (`server/test/`, jest + supertest): login / TOTP enable & recovery-code consumption / session invalidation / IP blocking, plus the seven Fnthink protocol routes
- **On-device tests** — `integration_test/smoke_test.dart` runs the main-path smoke test (launch -> inject -> notification page -> delivery status -> history -> service start/stop -> export), plus the `android/app/src/androidTest` instrumented tests, driven by `integration_test.yml` on an API 34 / x86_64 / Pixel 6 emulator

**CI workflows** (`.github/workflows/`, all on `ubuntu-24.04`):

- **`analyze.yml` (PR gate)** — `flutter analyze --fatal-infos` (verdict = exit code) -> version consistency -> release-gate behavior test -> Dart tests -> shared package tests -> Android JVM tests -> Android lint -> server contract tests -> three-way format check -> coverage artifact
- **`build-apk.yml` (on `v*` tags or manual)** — pre-flight tests & analyze -> arm64 release build -> ABI purity & version double gate -> GitHub Release
- **`integration_test.yml` (weekly, Tue 03:00 UTC + manual)** — emulator smoke test + instrumented tests
- **`deploy-pages.yml` (on changes to `server/public/**` or `server/data/version.json`, or manual)** — zero-maintenance static version source publishing
- **Format unification** — `.github/scripts/check_format.sh` is the same script locally and in CI: `dart format` + ktlint 1.8.0 (rules in `.editorconfig`) + prettier 3.9.8 (config in `server/.prettierrc`)
- **Version consistency gate** — `.github/scripts/check_version_consistency.sh` compares version & build across `pubspec.yaml` / `update_manager.dart` / `MainActivity.kt` / `server/data/version.json`, and additionally validates the sha256 fields of `version.json`, website i18n coverage, README dependency annotations and the zh/en ARB key sets
- **Local release pre-flight** — `.github/scripts/release_local.sh <A.B.C>`: version consistency -> format/analyze -> 4-ABI APK builds & purity checks -> fileSize/sha256 back-fill into version.json -> badge and update.md completeness checks

## Contribution

Welcome to submit Issues and Pull Requests!

- Contributing: See [CONTRIBUTING.md](CONTRIBUTING.md) · [English](CONTRIBUTING-en.md)
- Security Policy: See [SECURITY.md](SECURITY.md) · [English](SECURITY-en.md)
- Code of Conduct: See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) · [中文](CODE_OF_CONDUCT-zh.md)

## Privacy Notice

### Data boundary per track

| Track | Where content goes | Does the server store bodies |
|-------|-------------------|------------------------------|
| **Notification forwarding** (Webhook / self-built app / SMTP mail) | channels you configured, direct to the target | never touches any of our servers |
| **Fnthink Push** (including forwarding to a device or webhook) | the Fnthink server **you** selected (official instance or self-hosted) | **No** — only delivery metadata, never bodies (contract `privacy.serverStoresBodyPlaintext = false`) |
| **Remote Control** | the same | **No** — instruction bodies travel encrypted; credentials and instruction content never enter the audit log |

⚠ **One thing that must be said plainly**: Fnthink Push and Remote Control send content to **the server you chose** (the official instance, or one you host yourself). This is not "zero data upload" — that applies to the notification-forwarding track. The difference lies in **who runs that server**: the official instance is run by us, a self-hosted one lives entirely inside your own infrastructure, and under both forms the server never stores plaintext bodies.

### Data Collection Statement

This application values user privacy. The following is a statement about data collection:

| Data Type | Collected | Description |
|-----------|-----------|-------------|
| **Notification Content** | ⚠️ Depends on the channels you enable | Sent through the channel family or Fnthink channel **to the destination you specify**; the developer neither handles nor stores it; on the Fnthink path the server keeps metadata only |
| **Contacts/SMS** | ❌ Not uploaded | Only used locally for push |
| **Device ID** | ⚠️ Only when crash reporting is on | Used by Bugly SDK for device deduplication; crash reporting is off by default |
| **Crash Information** | ⚠️ Only when crash reporting is on | Collected via Bugly only after user opt-in |
| **Fnthink delivery metadata** | ✅ Yes | Sender address code, message type, time, delivery state. **No body text**, and the pairing relation plus the grant list live on the receiving device, not on the server |

### Bugly Crash Reporting (Off by Default, Opt-in)

- **Default state**: Off. The Bugly SDK is **not initialized** on cold start and makes no network requests; it is initialized only after the "More → Crash Reporting" switch is turned on (treated as user consent)
- **Purpose**: Only for collecting app crash information to help developers quickly locate and fix issues
- **Collected Content**: Crash stack, app version, system version, device model, CPU architecture
- **Log Protection**: Release builds strip all debug/info logs (`Log.v/d/i`) via R8; log output never contains notification titles, SMS bodies, verification codes or phone numbers, and the logs attached to crash reports follow the same rule
- **Data destination**: Uploaded to Tencent Bugly servers ([https://bugly.qq.com](https://bugly.qq.com)), accessible only by the developer for issue analysis
- **Not Collected**: User contacts, SMS content, notification content, location information or any personal privacy data
- **How to disable**: Turn off the "More → Crash Reporting" switch; since the SDK cannot be de-initialized at runtime, disabling takes full effect after the next cold start
- **Compliance**: Disclosed per the minimal-necessity principle of China's PIPL; no data leaves the device before the switch is enabled

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

### Fnthink Push will not connect?
1. Is the service address selected on the More page reachable from the current network (mainland / overseas)
2. Did device self-registration succeed (the Fnthink page can show its own identity)
3. Is the peer in your **pairing list**, and is forwarding checked for it
4. Are the certificate and system time correct (signatures are time-sensitive)

### A remote-control instruction does nothing?
1. Was the matching level granted on the receiver (L2 per item; L3 off by default)
2. Does the instruction carry an advanced key or TOTP — **L3 must carry one of them**
3. Was it cancelled inside the delay window (status bar or the top banner can cancel)
4. Is the item / action inside the closed vocabulary (anything outside is rejected and the receipt says so)

## License

This project is open source under the [Apache License 2.0](LICENSE), with a companion [NOTICE](NOTICE) file for third-party attributions. See [LICENSE_CHANGE-en.md](LICENSE_CHANGE-en.md) for when this took effect and its scope.
