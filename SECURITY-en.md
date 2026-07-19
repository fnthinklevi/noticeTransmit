# Security Policy (SECURITY)

[中文](SECURITY.md) / English

This document describes the security-support scope, vulnerability-reporting process, and secure-deployment requirements for 通知推送助手 / Notice Transmit.

---

## 1. Supported Versions

- **Only the latest stable release** receives security fixes. Currently supported: **v1.5.38 (build 72)**.
- Older versions (including those no longer maintained) are not patched — please upgrade to the latest release.

---

## 2. Reporting a Vulnerability

> ⚠️ **Do not disclose exploit details or PoC in public Issues.** Use a **private channel** below to avoid abuse.

**Reporting channels (pick one):**
- GitHub repo **Security → Report a vulnerability** (private security advisory — recommended);
- Or private message to the maintainer: **(maintainer: fill in email / contact here)**.

**Please include, if possible:**
- Vulnerability type and location (file path / endpoint / module);
- Reproduction steps (environment, trigger conditions);
- Impact scope and severity assessment;
- If available, a suggested fix.

**Response expectations:**
- Initial response target within **72 hours**;
- Once confirmed, coordinate a reasonable public-disclosure timeline following responsible-disclosure principles.

---

## 3. Security Design Overview (Scope)

- **Notification content is processed and forwarded locally only**: all system notifications, SMS, and contacts are parsed and forwarded on-device, **never uploaded to any third-party server** (except the user-configured Webhook target). Only Bugly collects minimal crash data (stack trace, device model, OS version, app version) for bugfixing.
- **User-configured Webhooks**: forwarding URLs are entered by the user; the server stores no forwarded content.
- **Admin auth**: login Token uses bcrypt hashing; TOTP two-factor auth is supported (compatible with Google Authenticator); the TOTP secret is stored encrypted with **AES-256-GCM** (key from `ENCRYPTION_KEY`).
- **Token transport**: accepted only via HTTP Header; **never** in URL parameters.
- **Brute-force protection**: 3 failed code attempts within 10 minutes auto-blocks the IP for 240 hours; 8 recovery codes are provided for device-loss recovery.
- **Secure randomness**: session IDs use `crypto.randomUUID()`.

---

## 4. Secure Deployment & Operations

### 4.1 Secret Management (Important)

`server/.env` holds the real secrets (`ADMIN_TOKEN_HASH` and `ENCRYPTION_KEY`); **do not commit it to the repo** (it is ignored by `.gitignore`; the repo keeps only the `.env.example` placeholder template).

Deployment rules:

1. The real `.env` is **not under version control** — it exists locally only; never commit it;
2. Inject secrets via environment variables; **never hardcode** them in code or config;
3. Periodically rotate secrets to reduce long-term exposure.

### 4.2 Encryption & Transport

- `ENCRYPTION_KEY` must be **64 hex characters** (AES-256-GCM needs 32 bytes). An invalid format is ignored and the TOTP secret is stored in **plaintext** — self-check before committing.
- CORS by default **allows only origin-less (native) requests**; cross-origin web-admin access requires an explicit `ALLOWED_ORIGINS` allowlist — **do not set it to `*`**.
- Behind a reverse proxy (e.g. Nginx), configure proxy hops via `TRUST_PROXY`; misconfiguration amplifies IP-spoofing / `X-Forwarded-For` rate-limit bypass risks.
- Admin endpoints (`/api/admin/*`) must sit on a trusted network or behind extra access control (e.g. internal-only bind, WAF / credential gateway).

### 4.3 Client

- Release builds disable R8 obfuscation and resource shrinking by default (see `proguard-rules.pro`; enable as needed) — if enabled, securely store the deobfuscation mapping.
- Notification-listener, battery-optimization whitelist, and auto-start permissions are granted by the user; missing permissions are functional limitations, not security vulnerabilities.

---

## 5. Out of Scope

- Security of third-party Webhook targets configured by the user.
- Local data protection after the device is rooted / privilege-escalated.
- Functional failures caused by missing system permissions (not a security vulnerability).
- Upstream vulnerabilities in dependencies: report via the dependency's own channel and upgrade in this project accordingly.

---

## 6. Acknowledgments

Thanks to every security researcher who reports issues through responsible disclosure.
