# Security Policy (SECURITY)

[中文](SECURITY.md) / English

This document describes the security-support scope, vulnerability-reporting process, and secure-deployment requirements for 通知推送助手 / NoticeTransmit.

---

## 1. Supported Versions

- **Only the latest stable release** receives security fixes. Currently supported: **v1.5.74 (build 113)**.
- Older versions (including those no longer maintained) are not patched — please upgrade to the latest release.
- The server runtime follows the same boundary: `server/package.json` declares `engines.node` as
  **`>=24`** (Node.js 24 LTS). Deployments on EOL Node (18 / 20) are unsupported — the dependency
  chain (Express, otplib, …) stops delivering CVE patches there.

---

## 2. Reporting a Vulnerability

> ⚠️ **Do not disclose exploit details or PoC in public Issues.** Use a **private channel** below to avoid abuse.

**Reporting channels (pick one):**
- GitHub repo **Security → Report a vulnerability** (private security advisory — recommended);
- Or a private message to the maintainer: **j@fnthink.com** (the only contact address registered in this repository, see the Enforcement section of [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)).

**Please include, if possible:**
- Vulnerability type and location (file path / endpoint / module);
- Reproduction steps (environment, trigger conditions);
- Impact scope and severity assessment;
- If available, a suggested fix.

**Response expectations:**
- Initial response target within **72 hours**;
- Once confirmed, coordinate a reasonable public-disclosure timeline following responsible-disclosure principles;
- Please do not disclose details publicly before we agree on a time.

---

## 3. Security Design Overview (Scope)

### 3.1 Client (Flutter + Android)

- **Notification content is processed and forwarded on-device only**: system notifications are matched
  against rules, keyword-filtered and aggregated locally, then forwarded only to the Webhook / SMTP
  targets the user configures — **never uploaded to any third-party server**.
- **No contacts collection**: the manifest never requests `READ_CONTACTS`, and this project's privacy
  policy lists contacts as not collected. SMS is only read for the "verification-code recognition"
  flow after the user explicitly grants `READ_SMS` / `RECEIVE_SMS`.
- **Encrypted local storage**: push history and statistics use SQLCipher (`sqflite_sqlcipher`,
  AES-256); channel credentials and sensitive settings use `flutter_secure_storage` / native
  `SecurePrefs` (AndroidKeyStore-backed EncryptedSharedPreferences, with the same master-key source
  on both sides).
- **Crash reporting (Tencent Bugly) is off by default**: the SDK is initialized only after the user
  opts in on the More page, then collects minimal data (crash stack trace, device model, OS version,
  app version, CPU architecture) and can be disabled at any time; while disabled the SDK never
  initializes and no data leaves the device.
- **Diagnostic logging is off by default**: toggled by tapping the version number **7 times** on the
  More page (native `DiagLog`, state persisted in SharedPreferences). Hard rule: **rule names /
  package names / counters only — never notification titles or bodies**.
- **Webhook signature anti-forgery** (v1.5.49+): WeCom and DingTalk append `timestamp` + `sign` to the
  URL, Feishu adds `timestamp` + `sign` inside the payload (all following each platform's native
  HMAC-SHA256 rule); generic Webhooks use the `X-Signature: sha256=<hex>` + `X-Timestamp` headers —
  prevents push content tampering or forgery.
- **Webhook delivery verification** (v1.5.49+): parses platform response codes (WeCom errcode=0,
  DingTalk errcode=0, Feishu StatusCode=0, Bark code=200, etc.) to determine real delivery status —
  HTTP 2xx with business failure is no longer misreported as "sent". (Fixed in v1.5.69: Bark business
  failures used to be always marked as success because its response has no `ok` field)
- **Push-toggle state isolation** (v1.5.50+): when push is paused via the foreground notification
  action, monitoring continues but webhook sending is skipped; state persists to SharedPreferences and
  survives restarts.
- **Certificate-pinning framework (disabled by default)**: `CERT_PINS` + `ENABLE_CERT_PINNING`
  (OkHttp CertificatePinner on the native side; `pinned_http_client.dart` on the Dart side via
  `--dart-define`). Always off in the debug variant. Enablement and rotation are described in
  `docs/cert_rotation_runbook.md`.

### 3.2 Admin server (`server/`, Node.js 24 + Express 5)

- **Login authentication**: the admin token is compared with bcrypt against `ADMIN_TOKEN_HASH`; no
  plaintext credential lives in the repo or in logs. TOTP two-factor authentication is supported
  (otplib v13, compatible with Google Authenticator).
- **TOTP secret stored encrypted**: AES-256-GCM with the key from `ENCRYPTION_KEY`; if the key is
  missing or malformed the code refuses to use it, warns loudly, and stores the secret in plaintext
  (see 4.2).
- **One-time recovery codes**: enabling 2FA generates **8** recovery codes (stored as bcrypt hashes),
  for device-loss recovery only. Consumption re-reads the config inside a critical section and is
  **one-time**, so concurrent replays of the same code can succeed only once. Old codes are invalidated
  by `POST /api/admin/totp/regenerate-recovery`.
- **Credentials travel only in headers / POST bodies**: the token and session are accepted only via
  HTTP headers (`x-admin-token` / `x-session-id`), **never as URL parameters**; recovery codes are the
  same (`GET /api/admin/totp/setup` returns 400 when it detects a `recoveryCode` query parameter and
  points to `POST /api/admin/totp/rebind`), keeping them out of access logs and browser history.
- **Session security**: session IDs come from `crypto.randomUUID()`; a fixed 24-hour TTL that is
  **never extended by activity**; `POST /api/admin/logout` revokes the current session;
  **enabling 2FA revokes all sessions** (`revokeAllSessions`), and `authMiddleware` additionally
  rejects token-only sessions minted before 2FA was enabled, so "turning 2FA on later" cannot be
  bypassed by an existing session.
- **Rate limiting counts per route bucket**: each IP is accounted per bucket in a 60-second window
  (`RATE_LIMIT_GENERAL_MAX` default 60, auth bucket `RATE_LIMIT_AUTH_MAX` default 5) rather than per
  exact path — otherwise arbitrary 404s and random query strings would inflate the in-memory table and
  its persisted file. The table also has a hard entry cap, cleaned before refusing to account.
- **IP blocking**: **5 failed 2FA attempts within a 10-minute window block that IP for 1 hour**.
  Blocked-IP state is **memory-authoritative** and written through on change (no per-request synchronous
  file read on the event loop). Public endpoints (`/health`, `/api/version/*`) are exempt from blocking
  and rate limiting, so an accidental block behind a shared NAT egress cannot break everyone's update
  checks. `DISABLE_IP_BLOCKING=1` temporarily counts without blocking, for incident response.
- **Security response headers**: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
  `Referrer-Policy`, `X-Permitted-Cross-Domain-Policies: none`, HSTS; the admin page (`admin.html`)
  additionally gets a strict CSP (`script-src 'self'`, `object-src 'none'`, `frame-ancestors 'none'`,
  `form-action 'self'`), and `/api/admin/*` responses are cache-disabled.
- **Version-config writes are a whitelist projection**: `POST /api/admin/version` persists only keys
  registered in `VERSION_CONFIG_FIELDS` (`latestVersion`, `latestBuild`, `forceUpdate*`, `changelog`,
  `downloads`, `fileSizes`, `sha256`, `minSupportedVersion`, plus the legacy-client compatibility
  fields `downloadUrl` / `fileSize`); unregistered keys are ignored, per-field type validation must pass
  before the file is written, and every per-ABI download URL must be `https://`.

---

## 4. Secure Deployment & Operations

### 4.1 Secret Management (Important)

`server/.env` holds the real secrets (`ADMIN_TOKEN_HASH` and `ENCRYPTION_KEY`); **do not commit it to the repo** (it is ignored by `.gitignore`; the repo keeps only the `.env.example` placeholder template).

Deployment rules:

1. The real `.env` is **not under version control** — it exists on the deploy host only; never commit it;
2. Inject secrets via environment variables; **never hardcode** them in code or config. When
   `ADMIN_TOKEN_HASH` is missing the server exits immediately instead of booting with empty credentials (fail-closed);
3. Rotate secrets periodically to reduce long-term exposure; APK signing keys are covered separately in 4.5;
4. The same applies to Android release signing material: locally via the ignored
   `android/key.properties`, and in CI only `build-apk.yml` receives it from GitHub Actions Secrets —
   the PR-gate workflow holds no signing material at all.

### 4.2 Encryption & Transport

- `ENCRYPTION_KEY` must be **64 hex characters** (AES-256-GCM needs 32 bytes). An invalid format is ignored and the TOTP secret is stored in **plaintext** — self-check before committing.
- CORS by default **allows only origin-less (native / curl) requests**; browser cross-origin access to the web admin requires an explicit `ALLOWED_ORIGINS` allowlist — **do not set it to `*`**.
- Behind a reverse proxy (e.g. Nginx), configure proxy hops via `TRUST_PROXY` (default `0` = trust no `X-Forwarded-For`). Leaving it unset accounts all IP blocking/rate limiting against the proxy IP (hurting every user); setting it too loosely lets attackers forge headers to bypass blocks.
- Admin endpoints (`/api/admin/*`) must sit on a trusted network or behind extra access control (e.g. internal-only bind, WAF / credential gateway).
- The server **supports single-instance deployment only**: rate-limit counters, sessions and IP blocks live in process memory, so PM2 cluster mode, Docker multi-replica or multi-host load balancing make state drift (a session created on instance A is invalid on B, blocks drift).
- Pin the runtime to Node.js 24 LTS (`engines.node >= 24`); CI and production match, so the authentication chain never runs on an EOL runtime.

### 4.3 Client

- Release builds enable R8 obfuscation and resource shrinking (`isMinifyEnabled` / `isShrinkResources` + `proguard-rules.pro`); keep the deobfuscation mapping file for readable crash logs.
- Notification-listener, battery-optimization whitelist, and auto-start permissions are granted by the user; missing permissions are functional limitations, not security vulnerabilities.
- The app requests only what its features need (no contacts, location or call-log permissions in the manifest; `QUERY_ALL_PACKAGES` is used only for the "filter by app" rule configuration).

### 4.4 APK Integrity Verification — sha256 (v1.5.69+)

- **Transport-layer additional check**: `server/data/version.json` carries the sha256 of each ABI's
  APK (64-char lowercase hex). The app computes the value natively after download and **before**
  signature verification.
- **Behavior**: mismatch → delete the APK and block installation (fail-closed); field absent on the server → skipped (legacy server compatibility, the signature check remains the root of trust); verification channel error → skipped.
- **Positioning**: the signature check is the root of trust (independent of the distribution server); sha256 protects against CDN corruption / in-transit tampering — the two layers complement each other.
- `bash .github/scripts/release_local.sh` backfills the `sha256` field automatically, and
  `bash .github/scripts/check_version_consistency.sh` verifies that all four ABI entries exist and are
  well-formed.

### 4.5 APK Signing Keys & In-App Updates (Important)

In-app updates trust **whether the downloaded package's signing certificate matches the installed app**
(`ApkSignatureVerifier`, fail-closed: any parse/read error counts as a failure), and additionally reject
version downgrades (any `versionCode` lower than the installed one is refused). This root of trust is
independent of the distribution server, which defends against a compromised server, poisoned mirrors and
CDN hijacking.

> ⚠️ **Operational risk**: precisely because the root of trust is the on-device signature,
> **rotating the signing key makes existing users unable to upgrade via in-app update forever**
> (the new package's signature necessarily mismatches — they must uninstall and reinstall).
> Before rotating, read Section 7 of `docs/cert_rotation_runbook.md` and use the
> **multi-signing transition**.

If you must switch keys immediately (e.g. after a leak) with no transition window, state clearly in the release notes that users must uninstall and reinstall.

---

## 5. Out of Scope

- Security of third-party Webhook / SMTP targets configured by the user.
- Local data protection after the device is rooted / privilege-escalated.
- Functional failures caused by missing system permissions (not a security vulnerability).
- Configuration defects of a self-hosted instance (a guessable admin token, `.env` or recovery codes pasted into a public channel, etc.): still welcome to report, but triaged as a configuration issue rather than a vulnerability in this project (see 4.1 for the configuration requirements).
- Upstream vulnerabilities in dependencies: report via the dependency's own channel and upgrade in this project accordingly.

---

## 6. Acknowledgments

Thanks to every security researcher who reports issues through responsible disclosure.
