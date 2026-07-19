# Contributing (CONTRIBUTING)

[中文](CONTRIBUTING.md) / English

Thanks for your interest in **通知推送助手 / Notice Transmit**! This document explains how to develop, submit, and release for this project.

> Main documentation: [README.md](README.md) (中文) / [README-en.md](README-en.md) (English)
> Architecture & design baseline: [base.md](base.md)

---

## 1. Code of Conduct

- Be friendly and respectful, and keep discussions technical.
- Submissions must be original work or properly licensed; no infringing, malicious, or illegal code.
- Report security vulnerabilities through a private channel. Do **not** disclose exploit details in public Issues.

---

## 2. Development Environment

This project uses **AGP 9.0.1 + Gradle 9.4.1**, which imposes minimum toolchain versions:

| Tool | Minimum | Notes |
|------|----------|-------|
| Flutter SDK | 3.44.0 | Bundles Dart 3.12.0 |
| Android Gradle Plugin | 9.0.1 | No AGP 8.x or below |
| Gradle | 9.4.1 | See `gradle-wrapper.properties` |
| Kotlin | 2.3.20 | See `settings.gradle.kts` |
| JDK | 21 | Required by AGP 9.x |
| Android SDK | minSdk 24 / compileSdk 37 | Targets SDK 37 |
| Node.js | 18+ | Only needed for `server/` |

Preparation:

```bash
# Flutter side
flutter pub get
flutter analyze          # must have no errors before submitting

# Server side (optional, only when changing server/)
cd server && npm install
```

---

## 3. Get and Run Locally

```bash
git clone <your-fork-url> noticeTransmit
cd noticeTransmit
flutter pub get
flutter run               # attach an Android device/emulator for debugging

# Start the update server (separate terminal)
cd server && npm start    # default port 3456; verify with /health
```

---

## 4. Branching & Commit Workflow

1. **Fork** this repo and clone it locally.
2. Branch off `main` (or `develop`) with a **focused branch name**:
   - Feature: `feat/short-desc`, e.g. `feat/icon-preview`
   - Fix: `fix/short-desc`, e.g. `fix/battery-cast-crash`
   - Refactor/docs: `refactor/...`, `docs/...`
3. Keep each branch to a single goal — one PR solves one class of problem.
4. Complete local validation before submitting (see Section 6).
5. Open a PR to `main` describing: purpose, scope of impact, and self-testing.
6. Wait for CI (GitHub Actions) to pass before merging.

### Commit Message

Follow Conventional Commits:

```
<type>(<scope>): <subject>

<optional body>
```

- `type`: `feat` / `fix` / `refactor` / `docs` / `style` / `test` / `chore`
- `scope` (optional): `flutter` / `android` / `server` / `docs`
- Example: `fix(android): prevent webhook silent failure after in-process service recreate`

---

## 5. Code Style

### 5.1 Flutter / Dart (`lib/`)

- **Must pass** `dart format lib/` and `flutter analyze` (CI checks formatting with `--set-exit-if-changed`; `error`-level issues fail the build).
- **Null-safety first**: never hard-cast data that may be absent. This project once crashed an entire page due to `rule['type'] as String` when legacy data lacked a field — always read external/stored data with `as Type? ?? default` (e.g. `map['x'] as int? ?? 0`).
- **Theme & colors**: use `AppColors` (iOS-style semantic colors) and `AppThemeColors` (`ThemeExtension`). **Do not hardcode colors**, or dark mode will break.
- **Cross-platform comms**: Flutter ↔ Android communicate via `MethodChannel` (`com.fnthink.notice/notification`); method names must stay in sync between `platform_channel.dart` and the native side.
- **State & DI**: use the `get_it`-injected Service classes; do not `new` singletons inside Widgets.
- For large files (e.g. `main_page.dart`, `rule_edit_page.dart`), ensure changes don't break existing navigation or the bottom SnackBar behavior (`_pushPage` / `_showInfo`).

### 5.2 Android Native (Kotlin, `android/`)

- Coroutines should run on `Dispatchers.IO`; network requests go through `NetworkClient` / `OkHttp`.
- Background logic lives in `NotificationMonitorService` and its modules (`BatteryMonitor` / `NotificationProcessor` / `WebhookSender`, etc.); prefer reusing existing modules over reimplementing.
- Launcher-icon aliases (`activity-alias`) must **strictly match** the `IconOption` keys on the Dart side (currently 17).
- `onDestroy` must not leave any globally permanent disabled state (this repo already fixed a similar `NetworkClient.isActive` issue).

### 5.3 Server (`server/`, Node.js + Express)

- After changes, run `node --check server.js` for syntax, then `npm start` locally and verify with `/health`.
- Changes to admin endpoints (`/api/admin/*`) must preserve auth and request-body validation.
- **Do not hardcode secrets** in code or config; secrets come from environment variables (see Section 7).

---

## 6. Pre-submit Local Checklist

```bash
# Flutter side
flutter pub get
dart format lib/
flutter analyze                  # style hints only; no errors allowed
flutter test                    # if unit tests exist

# Server side (only when changing server/)
cd server
node --check server.js
npm start &                     # temporary
curl -s http://127.0.0.1:3456/health
kill %1
```

> CI also runs `dart_code_metrics` and coverage. Run locally with
> `dart run dart_code_metrics:metrics analyze lib/` to self-check.

---

## 7. Security & Privacy (Important)

This project is a **notification listener & forwarder**; security and privacy are non-negotiable:

- **Notification content is processed and forwarded locally only**, never uploaded to any third-party server (except the user-configured Webhook).
- Do not write notification bodies, SMS, or contacts into logs, crash reports, or storage.
- **Secret management**: `server/.env` is currently tracked by Git and contains real secrets (`ADMIN_TOKEN_HASH`, `ENCRYPTION_KEY`). **Do not commit production secrets.**
  Recommended approach: commit only `.env.example` (placeholders/notes) and add the real `.env` to `.gitignore`, provided locally by the deployer. Document any new environment variable in `server/README.md`'s env table.
- Server encryption (`ENCRYPTION_KEY`) must be **64 hex chars** (AES-256-GCM); an invalid format is ignored and the TOTP secret is stored in plaintext — self-check before committing.
- CORS allows only origin-less (native) requests by default; cross-origin web admin access requires an explicit `ALLOWED_ORIGINS` allowlist.

---

## 8. Release Flow (Five-Update Flow)

> Maintainer-only. Each client release must synchronously update the changelog, version config, and artifact naming.

1. **Code freeze**: changes done; `dart format` + `flutter analyze` clean.
2. **Bump version**: edit `pubspec.yaml` `version: X.Y.Z+NN` (`versionName` and `versionCode` increment together, e.g. `1.5.38+72`).
3. **Build artifact**:
   ```bash
   flutter build apk --release --target-platform android-arm64
   ```
4. **Record size**: take the APK byte size, rename it to `noticeX.Y.Z.apk` and place it in `server/public/apks/`; put the byte count into `server/data/version.json`'s `fileSize`.
5. **Update version config** `server/data/version.json`: `latestVersion` / `latestBuild` / `changelog` (consistent with `update.md`).
6. **Append changelog**: add `### vX.Y.Z (build NN) - date` at the top of `update.md`, categorized as Features / Fixes / Server / Docs (follow existing entry format).
7. **Sync docs**: if icons, permissions, or config changed, update the corresponding notes and footer version in `base.md` / `README.md`.
8. **Deploy server**: sync the updated files (e.g. `server/server.js`, `server/data/version.json`) to the server and restart (see [server/README.md](server/README.md)).

---

## 9. License

This project is open source under the **MIT License** (see [LICENSE](LICENSE)). By contributing, you agree to release your contribution under this license.

---

Thanks again for participating! If you have questions, feel free to open an Issue for discussion.
