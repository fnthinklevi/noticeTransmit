# Notification Push Helper — Update Server

Version update service, built with Node.js + Express.

> 💡 **Don't want to maintain a server?** This project also supports [GitHub Pages static deployment](GITHUB_PAGES-en.md), zero-maintenance and free. The client auto-compatibles with both modes.

***

## 🚀 Quick Start (5 minutes)

### Step 1: Prepare the Environment

**Node.js 24 LTS or newer is required**: `engines.node` in `server/package.json` is `>=24`, and both CI (`setup-node` in `.github/workflows/analyze.yml`) and the contract tests are verified on Node 24. The old "v14 or above / 18.x / 20.x" wording is obsolete.

**Check if installed:**

```bash
node -v
npm -v
```

The version must be `v24.x` or higher. If you see `v18.x` / `v20.x`, upgrade to 24 LTS before deploying.

**Not installed? Download here:**

- Official site: <https://nodejs.org/> (pick 24 LTS)
- Windows: download the .msi installer, click through
- Linux: recommended to use nvm for multi-version management (`nvm install 24 && nvm use 24`)

### Step 2: Upload Files to Server

Upload the `server` folder to your server, e.g. to `/opt/update-server/`.

> ⚠️ **The protocol contract is *not* inside `server/` — upload it too**: the public face of fnthink push (`/api/fnthink/*`) reads the repository-root file `protocol/fnthink-v1.json`. Uploading only `server/` makes that face **degrade to 503 at startup**, with `[fnthink] 协议入口没有起来` plus the missing file named on the first screen of the log (the admin console and the update channel are unaffected).
>
> That degradation is **deliberate**: a contract that cannot be read must never be treated as "no limits / no checks", so the whole segment is switched off instead. If you want `/api/fnthink/*` to work, upload `protocol/fnthink-v1.json` too — **where you put it is your call**; the code only follows a rule: three levels up from `lib/fnthink`, then `protocol/`, i.e. "a sibling of the code directory" (in the repository, `server/` and `protocol/` are exactly that).
>
> ⚠ **That path is easy to get wrong — set it explicitly**: put `FNTHINK_CONTRACT=<absolute path to your contract>/fnthink-v1.json` in `.env` and the layout stops mattering.
>
> **Re-upload it whenever the contract changes** (new or renamed fields): new code against an old contract throws at startup (e.g. `limits.unauthenticatedPerMinute` missing) and the face degrades to 503 — the error names the missing key.

> ⚠️ **Upload red lines (this project is deployed by *uploading the `server/` folder*, not by `git pull`)**: an upload must **never overwrite or delete** the following — losing them means redoing configuration, or locking the admin out of the console:
>
> - `server/data/` — holds `totp.json` (TOTP secret + recovery-code hashes), `sessions.json`, `blocked_ips.json`, `failed_attempts.json`, `rate_limit.json`, `version.json`. The repository's `data/` contains **only** `version.json`; everything else is runtime state produced on the server. The five fnthink tables (`fnthink_devices.json` / `fnthink_pair_requests.json` / `fnthink_endpoints.json` / `fnthink_nonces.json` / `fnthink_messages.json`) are **identity data** too: losing the device table means every device re-registers, losing the pairing table means every established grant is gone (devices must re-pair by QR code).
> - `server/.env` — live secrets (`ADMIN_TOKEN_HASH` / `ENCRYPTION_KEY`); only `.env.example` is committed.
> - `server/node_modules/` and `package-lock.json` (`.gitignore` excludes `server/node_modules/`).
>
> **Never use a `--delete` style sync** (`rsync --delete`, or the "mirror directory" mode of some SFTP clients): it deletes server-only files such as `data/totp.json`, and the result is **the 2FA secret and all recovery codes are gone — the owner can no longer log into the admin console** (only the "Manually Resetting Two-Step Verification" procedure below recovers access). Overwrite file by file, or only code files (`server.js` / `lib/` / `public/` / `package.json` / docs).

### Step 3: Install Dependencies

On the server, in the `server` directory:

```bash
cd server
npm install
```

When you see `added X packages`, it's done.

After the first deployment, copy `.env.example` to `.env` and fill it in (`ADMIN_TOKEN_HASH` is mandatory — the service exits immediately without it).
**On every later code upload**, reproduce dependencies exactly from the lock file (`npm rebuild` is a fallback when a dependency needs rebuilding across a Node major bump; bcryptjs itself is pure JS):

```bash
npm ci        # installs strictly from package-lock.json (clears node_modules, leaves data/ and .env alone)
# or npm install (installs within the package.json ranges)
```

### Step 4: Start the Service

```bash
npm start
```

When you see output like the following, the service has started (the banner is hardcoded Chinese in `server.js`):

```
==============================
  更新服务已启动          (update service started)
  端口: 3456              (port: 3456)
  时间: ...               (time)
==============================
```

After it, the process lists every endpoint, the 2FA diagnostics line (`二步验证诊断: enabled=… secret=… 恢复码=… ENCRYPTION_KEY=…`) and the `DISABLE_IP_BLOCKING` state — the first place to look when a TOTP code mysteriously fails.

**Default port is 3456**. Change it with the `PORT` environment variable.

### Step 5: Verify the Service

Open in your browser:

```
http://your-server-ip:3456/health
```

If it returns:

```json
{ "status": "ok", "timestamp": "..." }
```

The service is running normally! 🎉

### Step 6: Publish Your First Update

**Publish an APK update:**

1. Place the APK under `server/public/apks/` (this repo's release script archives as `server/public/apks/<version>/notice_<flavour>_<version>.apk`). It is served from the web root: `https://your-domain/apks/<version>/xxx.apk` (the legacy `/public/apks/...` prefix still works).
2. Edit `server/data/version.json` (current contract: four-arch `downloads` / `fileSizes` / `sha256`):

```json
{
  "latestVersion": "1.2.0",
  "latestBuild": 19,
  "forceUpdate": false,
  "forceUpdateVersion": "1.0.0",
  "forceUpdateBuild": 1,
  "changelog": "1. New feature\n2. Bug fixes",
  "downloads": {
    "arm64": "https://cdn.example.com/app/notice/update/1.2.0/notice_arm64_1.2.0.apk",
    "arm32": "https://cdn.example.com/app/notice/update/1.2.0/notice_arm32_1.2.0.apk",
    "x86_64": "https://cdn.example.com/app/notice/update/1.2.0/notice_x86_1.2.0.apk",
    "all": "https://cdn.example.com/app/notice/update/1.2.0/notice_all_1.2.0.apk"
  },
  "fileSizes": {
    "arm64": 27711096,
    "arm32": 23787240,
    "x86_64": 29809646,
    "all": 76161926
  },
  "sha256": {
    "arm64": "<64 lowercase hex chars for the arm64 APK>",
    "arm32": "<sha256 of the arm32 APK>",
    "x86_64": "<sha256 of the x86_64 APK>",
    "all": "<sha256 of the universal APK>"
  },
  "minSupportedVersion": "1.0.0"
}
```

Every `downloads` value must be an absolute `https://` URL when submitted through `POST /api/admin/version` (the server validates it); a relative path (e.g. `/public/apks/app-release.apk`) only works when you hand-edit the file, because the client resolves it as "server URL + relative path".

3. Save the file — **no need to restart the service** (config is read on each request)

***

## 📁 Directory Structure

```
server/
├── server.js              # Entry point (startup + graceful shutdown + periodic persistence)
├── lib/                   # Modular layers
│   ├── app.js             # App assembly (CORS/headers/static/rate limits/mounts; exports app for tests)
│   ├── store.js           # Storage / persistence (rate limits, sessions, IP blocks, TOTP, recovery-code lock)
│   ├── otp.js             # TOTP wrapper (otplib v13, explicit crypto/base32 plugins)
│   ├── middleware.js      # Security headers / rate limit / blocking / auth / errors
│   └── routes/            # Routes (auth.js / version.js)
├── test/auth.test.js      # HTTP contract tests (jest + supertest, 29 cases)
├── package.json           # Dependencies and scripts (engines.node = ">=24")
├── package-lock.json      # Lock file used by npm ci
├── babel.config.js        # Jest ESM compatibility
├── .env.example           # Environment variable template (copy to .env and fill in)
├── .env                   # Live secrets (git-ignored; never commit, never overwrite on deploy)
├── .prettierrc            # Code style (used by npm run format)
├── README.md / README-en.md
├── GITHUB_PAGES.md / GITHUB_PAGES-en.md
├── data/                  # Runtime state directory (auto-created when missing)
│   ├── version.json       # APK version config (the only file tracked in git)
│   ├── totp.json          # TOTP secret (AES-256-GCM) + recovery-code bcrypt hashes
│   ├── sessions.json      # Admin sessions (24h TTL)
│   ├── blocked_ips.json   # IP block list (memory-authoritative, write-behind)
│   ├── failed_attempts.json # 2FA failure counters (10-minute window)
│   └── rate_limit.json    # Rate-limit counters (only entries inside the current window)
└── public/                # Static assets (tracked in the repo; NOT auto-created)
    ├── index.html         # Marketing site
    ├── admin.html         # Admin console page
    ├── admin.js           # Console script (external file, required by the strict CSP)
    ├── i18n.js            # zh/EN dictionary for the marketing site
    ├── app_icon.png / favicon.ico
    └── apks/              # APK archive dir (git-ignored; exists on the server only)
```

> 💡 **Tip**: only `data/` is auto-created on startup (`fs.mkdirSync(DATA_DIR, {recursive:true})` in `lib/store.js`). If `public/` is missing, static files simply 404 — ship it with the code.
> Everything in `data/` except `version.json` is runtime state, not tracked in git, and **must never be overwritten by a deployment upload**.

***

## ⚙️ Configuration Details

### Environment Variables

Provided via `.env` (template: `server/.env.example`) or real environment variables; `.env` is git-ignored.

| Variable | Description | Default |
| --- | --- | --- |
| `PORT` | Server listen port | `3456` |
| `ADMIN_TOKEN_HASH` | bcrypt hash of the admin token (not the plaintext). **If unset, the process logs an error and calls `process.exit(1)`** | none (mandatory) |
| `ENCRYPTION_KEY` | AES-256-GCM key for the TOTP secret, **must be 64 hex characters** (32 bytes). An invalid format is discarded with a warning and the secret is stored in plaintext | none (strongly recommended) |
| `NODE_ENV` | Runtime environment. Only affects whether error responses leak internals: `development` adds the `error` field, anything else returns just "服务器内部错误" | unset (`.env.example` ships `production`) |
| `TRUST_PROXY` | Reverse-proxy hops to trust. `0` = trust no proxy headers (fail-safe default for direct deployments); a single Nginx layer needs `1`, Nginx + CDN needs `2`. Left unset behind a proxy, IP blocking and rate limiting all count the proxy IP; set without a proxy, attackers can spoof `X-Forwarded-For` to evade blocks | `0` |
| `ALLOWED_ORIGINS` | CORS allow-list, comma separated. Requests without an Origin (native app / curl / same-origin) are always allowed; `*` restores allow-all. **Unset means a cross-origin browser request carrying an Origin is refused** (the same-origin console is unaffected) | empty |
| `DATA_DIR` | Runtime state directory (`version.json` / `totp.json` / `sessions.json` / …), used for test isolation | `<server>/data` |
| `RATE_LIMIT_GENERAL_MAX` | Global limit: max requests per IP per **route bucket** per 60 s | `60` |
| `RATE_LIMIT_AUTH_MAX` | Extra limit for `/api/admin`: max requests per IP per minute | `5` |
| `RATE_LIMIT_FNTHINK_MAX` | Rate limit for the **whole** public face (`/api/fnthink/*`), per IP per minute — a flood brake only. The per-endpoint quotas (per IP: `register` = 30/min · 3000/day; per device address: the three pairing steps and `/message` = 60/min · 5000/day; `poll`/`ack` derived from `presence` = 14/min, no daily cap) all come from the contract's `limits` section and are **not** configured here — tune the contract for those; this knob only bounds "one IP fanning out across every endpoint" | `300` |
| `FNTHINK_CONTRACT` | Override for the contract file path. The default is derived from the code location (`lib/fnthink`, three levels up, then `protocol/fnthink-v1.json` — the repo-root copy in the repository). **Set an absolute path explicitly when deploying**: the derived location changes with how deep you place the server code | auto-detected |
| `DISABLE_IP_BLOCKING` | `1` / `true` / `yes` disables IP blocking (failures are still counted, nothing is rejected) — emergency escape hatch for a wrongly blocked NAT egress | off |

Generate the two secrets (after `npm install`; substitute real values, **never paste them into a doc or commit them**):

```bash
# ADMIN_TOKEN_HASH: bcrypt cost 10
node -e "console.log(require('bcryptjs').hashSync('<your-admin-token>', 10))"
# ENCRYPTION_KEY: 64 hex characters
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

> ⚠️ Once `ENCRYPTION_KEY` has been used to enable 2FA it **can never be rotated**: with a different key the ciphertext in `data/totp.json` cannot be decrypted, verification answers 500 "服务端二步验证密钥配置错误" (not counted as a failure, no IP block), and the only way out is the reset procedure below. When you back up `data/`, keep the `ENCRYPTION_KEY` from `.env` in the same off-site backup.

**Changing the port:**

**Windows (PowerShell / CMD):**

```powershell
# PowerShell
$env:PORT=8080; npm start
```

```cmd
:: CMD
set PORT=8080 && npm start
```

**Linux / macOS:**

```bash
PORT=8080 npm start
```

### version.json Fields (APK Version Config)

`POST /api/admin/version` accepts only the 12 fields below (whitelist projection); **any other field is never persisted** (the server logs `已忽略未知字段`).

| Field | Type | Description | Example |
| --- | --- | --- | --- |
| `latestVersion` | string | Latest version number (semver), mandatory non-empty | `"1.2.0"` |
| `latestBuild` | number | Latest build number, mandatory positive integer | `19` |
| `forceUpdate` | boolean | Enable forced update | `false` |
| `forceUpdateVersion` | string | Force update below this version; required non-empty when `forceUpdate=true` | `"1.0.0"` |
| `forceUpdateBuild` | number | Force update below this build; required non-negative integer when `forceUpdate=true` | `1` |
| `changelog` | string | Changelog, `\n` for newlines | `"1. Bug fix"` |
| `downloads` | object | Per-arch download URLs, keys `arm64`/`arm32`/`x86_64`/`all`; absolute `https://` when submitted to the admin API, empty string means the arch is not published | `{"arm64":"https://.../notice_arm64_1.5.74.apk",...}` |
| `fileSizes` | object | Per-arch file sizes in bytes (non-negative integers) | `{"arm64":27711096,...}` |
| `sha256` | object | Per-arch APK sha256 (64 **lowercase** hex chars; empty/absent = that arch skips verification). The app compares it after download, before install (N3 transport-layer check). **The console form has no such field, but the existing value is preserved on save** — sha256 is written by the release script | `{"arm64":"<64 lowercase hex chars>",...}` |
| `minSupportedVersion` | string | Minimum supported version (passed through to the client) | `"1.0.0"` |
| `downloadUrl` | string | (legacy compat, only validated when `downloads` is absent) single download URL, must be absolute `https://` | `"https://cdn.example.com/..."` |
| `fileSize` | number | (legacy compat) file size in bytes, non-negative | `56623104` |

> Deprecated field: `platform`. The server neither reads nor accepts it (not in the whitelist) and the client never consumes it — stop writing it.

***

## 🔌 API Reference

All endpoints (route definitions in `lib/routes/version.js` and `lib/routes/auth.js`; the latter is mounted at `/api/admin`):

| Method | Path | Auth | Description |
| --- | --- | --- | --- |
| `GET`  | `/api/version/check` | public (exempt from IP blocks) | App version check |
| `GET`  | `/health` | public (exempt from IP blocks) | Health check `{status:'ok',timestamp}` |
| `POST` | `/api/admin/login` | Token (+ OTP / recovery code) | Login, returns `sessionId` |
| `POST` | `/api/admin/logout` | Session/Token | Revoke the current session |
| `GET`  | `/api/admin/totp/setup` | Session/Token | Generates secret + QR when 2FA is off; only status when it is on (secret never leaked again) |
| `POST` | `/api/admin/totp/enable` | Session/Token | Verifies the OTP, enables 2FA, returns 8 recovery codes **and revokes every existing session** |
| `POST` | `/api/admin/totp/disable` | Session/Token | Disables 2FA after OTP or recovery code |
| `GET`  | `/api/admin/totp/status` | Session/Token | `{enabled, hasRecoveryCodes}` |
| `POST` | `/api/admin/totp/rebind` | Session/Token | Submits a recovery code (one-time consumption) to get a new secret + QR, e.g. after switching phones |
| `POST` | `/api/admin/totp/regenerate-recovery` | Session/Token | Issues a fresh set of 8 recovery codes after OTP or recovery code |
| `GET`  | `/api/admin/version` | Session/Token | Echoes `data/version.json` verbatim |
| `POST` | `/api/admin/version` | Session/Token | Validates, projects onto the whitelist, then persists |

**Credentials (headers only, never URL parameters):**

- `x-admin-token: <your-admin-token>` — bcrypt-compared against `ADMIN_TOKEN_HASH`;
- `x-session-id: <sessionId from login>` — returned as `sessionId` in the `POST /api/admin/login` response body (when a protected endpoint is hit with a bare token, the server mints a session and echoes it in the `x-session-id` **response header**). Session TTL is a fixed **24 hours** with no sliding renewal; a session dies on `POST /api/admin/logout` or when the TTL lapses, and it **survives a restart** because `sessions.json` is reloaded at startup (entries past the TTL are dropped then).

> 🔒 **Once 2FA is enabled, only OTP-verified sessions carry admin rights**: bare-token requests — and token-only sessions minted before 2FA was switched on — get `401 {code:-2, require2FA:true}`. `/totp/enable` calls `revokeAllSessions()`, clearing both memory and `sessions.json`, so everyone must re-login with Token + OTP. Forging `x-session-id` (`__proto__`, `constructor`, …) does not work: the session table is `Object.create(null)` and every lookup goes through `isValidSession()`, which requires an own property with `authenticated === true`.

### 1. Check APK Version Update

```
GET /api/version/check
```

**Request parameters:**

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `version` | string | No | Current version, e.g. `1.1.7`; missing/invalid compares as `0` (so an update is always reported) |
| `build` | number | No | Current build, e.g. `18`; missing compares as `0` |
| `platform` | string | No | Picks which arch fills `downloadUrl`/`fileSize`: `x86_64` → x86_64, `armeabi-v7a` → arm32, anything else (including the `android` the app sends) → arm64; falls back to `all` when that arch is empty |

`hasUpdate = latestVersion > version || latestBuild > build`; the `forceUpdate` in the response is the computed result of "`forceUpdate` is true **and** the client is below `forceUpdateVersion`/`forceUpdateBuild`", not the raw config value.

**Response example (these are all the keys the server returns):**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "hasUpdate": true,
    "latestVersion": "1.2.0",
    "latestBuild": 19,
    "forceUpdate": false,
    "changelog": "1. New feature\n2. Bug fix",
    "downloadUrl": "https://cdn.example.com/app/notice/update/1.2.0/notice_arm64_1.2.0.apk",
    "fileSize": 27711096,
    "downloads": {
      "arm64": "https://cdn.example.com/app/notice/update/1.2.0/notice_arm64_1.2.0.apk",
      "arm32": "https://cdn.example.com/app/notice/update/1.2.0/notice_arm32_1.2.0.apk",
      "x86_64": "https://cdn.example.com/app/notice/update/1.2.0/notice_x86_1.2.0.apk",
      "all": "https://cdn.example.com/app/notice/update/1.2.0/notice_all_1.2.0.apk"
    },
    "fileSizes": {
      "arm64": 27711096,
      "arm32": 23787240,
      "x86_64": 29809646,
      "all": 76161926
    },
    "sha256": {
      "arm64": "<sha256 of the arm64 APK>",
      "arm32": "<sha256 of the arm32 APK>",
      "x86_64": "<sha256 of the x86_64 APK>",
      "all": "<sha256 of the universal APK>"
    },
    "minSupportedVersion": "1.0.0"
  }
}
```

### 2. Get Version Config (Admin)

```
GET /api/admin/version
```

Requires authentication. Returns the full content of `data/version.json` (no field projection).

### 3. Update Version Config (Admin)

```
POST /api/admin/version
Content-Type: application/json
```

The body is the version.json content (what the console's "版本管理" tab submits). Server behaviour:

1. **Field validation** (`validateVersionConfig` in `lib/routes/version.js`): failures → `400 {code:-4, message:"字段校验失败: …"}` listing every reason;
2. **Whitelist projection**: only the 12 known fields survive — **unknown fields are neither persisted nor echoed back** (the log prints `已忽略未知字段（不落盘）：…`);
3. **sha256 carry-over**: when the body omits `sha256`, the value already in the file is kept (the console form has no such field, so saving never loses the hashes written at release time); an explicit `sha256` still overwrites;
4. Atomic write (`.tmp` then `rename`): `{code:0,message:"保存成功"}` on success, `{code:-1,message:"保存失败"}` if the write fails.

> After receiving `/api/version/check`, the app **picks its own APK from `downloads` by device ABI** (with `platform=android` the server's `downloadUrl` is only an arm64 hint), verifies it against the matching `sha256` entry, and then lets the native `ApkSignatureVerifier` compare signing certificates (see section 7 of `../docs/cert_rotation_runbook.md`).

### 4. Health Check

```
GET /health
```

For monitoring service liveness; returns `{"status":"ok","timestamp":"…"}`. Exempt from IP blocking along with `/api/version/*`, so a wrong block never stops existing devices from checking for updates.

### Error codes

| HTTP | `code` | Meaning | What to do |
| --- | --- | --- | --- |
| 200  | `0`    | Success | — |
| 401  | `-1`   | Unauthorized / session expired / wrong 2FA code (login responses carry `remainingAttempts`) | Log in again |
| 401  | `-2`   | Second factor required (`require2FA: true`) | Prompt for the OTP; **do not** drop the local session (the console only logs out on `-1`) |
| 403  | `-3`   | IP blocked (`blocked: true`, `remainingHours`) | Wait for expiry, or use "Manual Unblock" below |
| 400  | `-4`   | Field validation failed / body is not a JSON object | Fix per `message` and retry |
| 429  | `-4`   | Rate limited (includes `retryAfter` seconds) | Back off and retry |
| 500  | `-5`   | Internal error; `-2` is also used for "服务端二步验证密钥配置错误" (`ENCRYPTION_KEY` missing/mismatched — not counted as a failure, no IP block) | Check the server log and `ENCRYPTION_KEY` |

### How rate limiting counts

- The key is `IP:route-bucket`. `store.rateLimitBucket()` collapses the requester-controlled path into three buckets: `api-admin` (`/api/admin*`), `api` (other `/api/*`), `static` (everything else). Probing random 404 paths no longer creates one entry each.
- 60-second window: `static` / `api` allow `RATE_LIMIT_GENERAL_MAX` (default 60) requests per IP per minute; `/api/admin` additionally gets `RATE_LIMIT_AUTH_MAX` (default 5).
- Hard cap of 20 000 entries in the limit table: on overflow expired entries are purged first, and if still over the cap the request is *not* counted (pass-through rather than self-DoS).
- Every 60 s the counters are cleaned up and flushed to `data/rate_limit.json` (only in-window entries; the file is deleted when everything expired).

***

## 📦 Full Release Workflow

### Publishing an APK Version Update

> The complete choreography lives in `base.md` at the repo root; the reusable automation is `.github/scripts/release_local.sh` (build → ABI purity check → backfill `latestVersion`/`latestBuild`/`downloads`/`fileSizes`/`sha256` into `version.json` → archive into `server/public/apks/<version>/`), with CI builds in `.github/workflows/build-apk.yml`. The manual equivalent:

**Step 1: Prepare the APKs**

Build release APKs. This project ships four flavours, named `notice_<flavour>_<version>.apk` where `<flavour>` is `arm64` / `arm32` / `x86` / `all` (`all` being the universal package).

**Step 2: Compute size and sha256 per package**

- Size (bytes): Linux `stat -c%s notice_arm64_1.5.74.apk`; Windows right-click → Properties → Size
- Checksum (64 lowercase hex chars, verified by the app after download and before install): `sha256sum notice_arm64_1.5.74.apk`

**Step 3: Upload the packages**

Whatever `version.json`'s `downloads` says is where the client goes:

- Self-hosted: put them under `server/public/apks/<version>/`, served from the web root as `https://your-domain/apks/<version>/xxx.apk` (this directory is git-ignored, it exists only on the server — **deployment uploads must not overwrite or delete it**)
- Repo archive: keep a copy in `server/public/apks/<version>/` for the release script and local verification
- The live config points at the CDN (`https://cdn.example.com/app/notice/update/<version>/…`); the app also has GitHub Release mirrors as fallback (`xget.example.com` / `github.com`, same `notice_<flavour>_<version>.apk` naming)

**Step 4: Update the config**

Two equivalent paths:

- **Admin console**: open `/admin.html` → version tab → edit `latestVersion`, `latestBuild`, `changelog`, `minSupportedVersion`, per-arch `downloads`/`fileSizes`, `forceUpdate` (and its thresholds) → Save. The form has no `sha256` field; the server carries the existing value over.
- **Edit the file directly**: change `server/data/version.json` (including `sha256`); saving is enough.

**Step 5: Save — done!**

The file takes effect immediately after saving, no service restart needed (it is read per request). Once `version.json` changes are committed, `bash .github/scripts/check_version_consistency.sh` verifies version/build consistency and `sha256` completeness (the same gate runs in CI).

## 🧭 Decide first: how much are you installing?

| Form | What you do | What you get | What it costs you to skip |
| --- | --- | --- | --- |
| **A. Update service only** (default, most people) | The six Quick-Start steps | Website + admin console + `/api/version/check` + APK downloads | Nothing. `/api/fnthink/*` answers **503**, and the log carries `[fnthink] 协议入口没有起来` |
| **B. Update service + fnthink push public face** | A, plus the "Adding fnthink push" chapter | All of the above plus `/api/fnthink/{register,poll,ack,message,pair-arm,pair,pair-confirm}` | Nothing. The two halves do not interfere |

> ⚠️ **If you are on form A**: `/api/fnthink/*` returning 503 and that log line mean **"this segment is not
> installed"**, not "the server is broken". You do not need the protocol contract and you do not need
> `FNTHINK_CONTRACT`. Do **not** copy the contract JSON into `server/`: it is a *live source of truth*, and a
> copy inside the server folder will silently be the one being read (edits to the repo copy then do nothing).

***

## 🧩 Adding the fnthink push public face (to an already-running update service)

This chapter is **incremental**: steps 1–3 can be done online without touching the update channel; only step 4
restarts the process (a second or two).

**Step 1 — upload the protocol contract.** It is `protocol/fnthink-v1.json` at the repository root and it is
**not inside `server/`**. Where you put it is your call; the code only follows a rule — three levels up from
`lib/fnthink`, then `protocol/`, i.e. "a sibling of the code directory":

```bash
# e.g. a sibling of the code directory, so FNTHINK_CONTRACT is not even needed
rsync -av ./protocol/fnthink-v1.json user@host:<parent of the code directory>/protocol/
```

> ⚠️ That location is easy to get wrong (it depends on how deep you place the server code). **Set it
> explicitly** in the next step; a hard-coded absolute path survives any layout change.

**Step 2 — two lines in `.env`** (both optional; the first is recommended)

```ini
FNTHINK_CONTRACT=<absolute path to your contract>/fnthink-v1.json   # state the location explicitly
#RATE_LIMIT_FNTHINK_MAX=300                                         # whole-face flood brake per IP, default 300/min
```

**Step 3 — a separate server block for the push hostnames.** Do not squeeze the push hostnames into the update
site's block and then edit that block — add a **new** one that serves only what the public face needs, so the
two hostnames are separated by configuration rather than memory:

```nginx
server {
    listen 443 ssl;
    server_name push.example.com push-cn.example.com;      # your actual push hostnames
    ssl_certificate     /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    client_max_body_size 64k;        # the protocol face enforces 64 KiB itself; smaller here means Nginx rejects first

    location /api/fnthink/ { proxy_pass http://127.0.0.1:3456; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; }
    location /health       { proxy_pass http://127.0.0.1:3456; }
    location /             { return 404; }                   # website/admin console stay on the update hostname
}
```

```bash
nginx -t && systemctl reload nginx      # reload, not restart
```

**Step 4 — restart and read the banner**

```bash
pm2 restart update-server && pm2 logs update-server --lines 40
```

Expect these lines (do not continue if any is missing):

```
协议面（fnthink-v1，公网可达）:
  POST /api/fnthink/register  - 按 IP 30/分钟 · 3000/天（身份未证明，只能按 IP）
  POST /api/fnthink/poll      - 按设备地址 14/分钟（数字从 presence 节奏推导，验签后计）
  请求体上限（公网面，取自契约 limits.requestBodyMaxBytes）：65536 字节
```

**Step 5 — acceptance (5 curls, including the "update channel still works" regression)**

```bash
curl -s  https://notice.example.com/health                                   # {"status":"ok",...}
curl -s "https://notice.example.com/api/version/check?version=1.5.76&build=116&platform=android"   # {"code":0,...}  ← regression
curl -s -X POST https://push.example.com/api/fnthink/poll -H 'Content-Type: application/json' -d '{}'
#   403 {"receipt":"rejected_unsigned"} expected; 503 = contract not found; 404 = push hostname missing from server_name
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://push.example.com/api/admin/login    # 404 expected (admin stays on the update host)
curl -s -X POST https://push.example.com/api/fnthink/poll -H 'Content-Type: application/json' -d "{\"pad\":\"$(head -c 70000 /dev/zero | tr '\0' 'x')\"}"
#   413 with body {} expected (protocol shape); an HTML 413 means client_max_body_size is below 64 KiB
```

**Step 6 — how to remove it.** Delete the server block from step 3, reload, move the contract away (or drop the
two `.env` lines) and restart: the face goes back to "503 = not installed", with the update channel untouched
throughout.

***

## 🔥 Production Deployment (Ops Guide)

The following are recommended production deployment options, from simple to advanced.

### Option 0: Uploading the `server/` directory (what this project actually does)

This service is updated by **uploading the `server/` folder and overwriting the code files** — the server has no git checkout, so `git pull` is not the workflow. Every release is these three steps:

```bash
# 1) Overwrite code only: server.js, lib/, public/, package.json, package-lock.json, *.md
#    ⚠️ Never with --delete (rsync --delete / SFTP "mirror directory" wipes data/ and .env)
rsync -av --exclude 'data/' --exclude '.env' --exclude 'node_modules/' ./server/ user@host:/opt/update-server/
# 1b) Contract: the public face (/api/fnthink/*) reads protocol/fnthink-v1.json from the repo root,
#     which is NOT inside server/ ⇒ upload it separately. **Where you put it is your call**; the
#     default rule is "a sibling of the code directory" (lib/fnthink, three levels up, then protocol/).
#     It is easy to get wrong — **set FNTHINK_CONTRACT explicitly in the server .env instead**.
rsync -av ./protocol/fnthink-v1.json user@host:<contract-dir>/
# server .env (path adjusted to where you put it):
#   FNTHINK_CONTRACT=<contract-dir>/fnthink-v1.json

# 2) Install/update dependencies exactly from the lock file (leaves data/ and .env alone)
cd /opt/update-server && npm ci        # npm rebuild if a dependency needs it

# 3) Restart the process
pm2 restart update-server && pm2 logs update-server --lines 20
```

> ⚠️ **Red lines restated (highest-incident operational pitfall)**
> - An upload must **never overwrite or delete `server/data/`**: `totp.json` holds the encrypted TOTP secret plus the recovery-code bcrypt hashes — lose it and the owner cannot pass 2FA (the only recovery is resetting 2FA and re-binding the authenticator). `sessions.json` / `blocked_ips.json` / `failed_attempts.json` / `rate_limit.json` are runtime state. The repository's `data/` contains only `version.json`, so bulk-overwriting from a checkout also rolls the live `version.json` back.
> - The same applies to the five **fnthink tables** under `data/`, which are identity data rather than settings: `fnthink_devices.json` (address code → public key), `fnthink_pair_requests.json` (pending pairing requests), `fnthink_endpoints.json`, `fnthink_nonces.json`, and `fnthink_messages.json` (pending messages with encrypted bodies). Losing the device table means every device has to register again; losing the pairing table means every established grant is gone and devices must re-pair by QR code. They are written 0600 and atomically by `table.js`, are not tracked in git, and **must never be overwritten by a deployment upload**.
> - An upload must **never overwrite `server/.env`** (live keys; the repo ships only `.env.example`).
> - An upload must **never delete `node_modules/`** (unless you immediately run `npm ci`), and don't upload your local `node_modules/`.
> - **Ship the contract JSON together with the code**: it is the single source of truth for the protocol face (rate-limit tiers, status codes and the body-size cap are all read from it). Forgetting it shows up as every `/api/fnthink/*` call returning 503 while everything else works; the `[fnthink] 协议入口没有起来` line names the missing file or key.
> - Using a `--delete` sync = deleting `data/totp.json` = locking the admin out of the console. **Forbidden.**
> - A restart re-reads the persisted state under `data/` (sessions / blocks / counters); sessions logged in beforehand stay valid within their 24h TTL.
>
> After a restart, **check the startup banner**: it now prints, per endpoint, which rate-limit tier applies (per IP / per device address / derived from `presence`), plus the public face's request-body cap in bytes. Seeing `⚠ 请求体上限没挂上` (body cap not mounted) or `（协议面没有起来…）` means step 1b was skipped or the path is wrong.

### Option 1: PM2 Process Manager (Recommended for small/medium projects)

PM2 is a Node.js process manager that provides:

- Process guard (auto-restart on crash)
- Log management
- Boot auto-start
- Load balancing (**unusable for this service** — see "Deployment Boundary": state lives in one process's memory)

**Install PM2:**

```bash
npm install -g pm2
```

**Start the service:**

```bash
cd /opt/update-server   # the path where you actually placed the server directory
pm2 start server.js --name update-server
```

**Common commands:**

```bash
pm2 list                     # View all processes
pm2 logs update-server       # View logs
pm2 restart update-server    # Restart (after uploading new code)
pm2 stop update-server       # Stop
pm2 delete update-server     # Remove the process entry
```

**Configure boot auto-start:**

```bash
pm2 save
pm2 startup
```

After running `pm2 startup`, copy and run the output command.

***

### Option 2: Nginx Reverse Proxy + HTTPS (Recommended for production)

Benefits of using Nginx as a reverse proxy:

- HTTPS support
- Load balancing
- Static file acceleration
- More secure

**Nginx config example:**

```nginx
server {
    listen 80;
    # All three names belong here: notice.* serves the website/admin console; push.* is the
    # public face of fnthink push (the contract's transport.endpoints names these hosts,
    # and the app dials them directly — leaving them out makes that face unreachable).
    server_name notice.example.com push.example.com push-cn.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name notice.example.com push.example.com push-cn.example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/private.key;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;

    # Static files served directly by Nginx (better performance).
    # APKs live under the web root at /apks/; the legacy /public/ prefix still works.
    location /apks/ {
        alias /opt/update-server/public/apks/;
        expires 7d;
    }

    location /public/ {
        alias /opt/update-server/public/;
        expires 7d;
    }

    # Forward other requests to Node.js
    location / {
        proxy_pass http://127.0.0.1:3456;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # ⚠ Request-body cap: this layer must be **no smaller** than the largest body the server
    #   accepts, otherwise Nginx rejects first and the client gets Nginx's HTML 413 instead of the
    #   protocol/admin error shape. The server has two caps: admin (backup import) 1 MB, and the
    #   public face /api/fnthink/* 64 KiB (the app answers those with the protocol's own 413).
    #   The default 1m is exactly enough for admin; only ever raise it.
    client_max_body_size 2m;
}
```

> ⚠ **Redact the pairing-secret path in the access log**: the contract declares
> `transport.secretPlacement = path_segment`, so the pairing code travels as a path segment
> (`/api/fnthink/p/<code>`) — and the contract also declares the prefix to redact,
> `transport.accessLogRedactPathPattern = /api/fnthink/p/`. The default `combined` log would write that
> one-time credential into `access.log` verbatim, i.e. keep a recoverable copy of it. Simplest fix is a
> dedicated log_format for this site:
>
> ```nginx
> map $request_uri $safe_uri {
>     default            $request_uri;
>     ~^/api/fnthink/p/  "/api/fnthink/p/[redacted]";
> }
> log_format safe '$remote_addr - $remote_user [$time_local] "$request_method $safe_uri $server_protocol" '
>                 '$status $body_bytes_sent "$http_referer" "$http_user_agent"';
> access_log /var/log/nginx/notice.access.log safe;
> ```
>
> Moving the secret out of the path would mean changing the contract (`secretPlacement`) — not now:
> relocating the secret is a protocol change.

> ⚠️ **Reverse-proxy deployments must set `TRUST_PROXY`**: `app.set('trust proxy', Number(process.env.TRUST_PROXY ?? 0))` defaults to **0 = trust no proxy headers** (the fail-safe default for direct deployments). Behind Nginx without it, IP blocking and rate limiting see only `127.0.0.1` (the proxy IP) — one false block shuts the admin API for everyone. Conversely, setting it with no proxy lets attackers spoof `X-Forwarded-For` and evade blocks.
> Single Nginx layer: `TRUST_PROXY=1`; Nginx + CDN: one per hop (e.g. `2`). Requires a service restart to take effect.
> If Cloudflare is in front, restrict the origin to CF's IP ranges at the Nginx layer and keep `TRUST_PROXY` counting **your own** hops.

> ⚠️ **Do not entangle the update hostname you already run in production** (written `notice.example.com` throughout below). The division is fixed:
> `notice.example.com` = update check / APK download / admin console (a compile-time constant `_updateServerUrl` in the app; changing it means shipping a new APK);
> `push.example.com` (plus an optional second mainland hostname) = the fnthink push public face (declared in the contract's `transport.endpoints`; the app dials them directly).
> Both chains **share one Node process and one `data/`**, so three rules when touching this layer:
>
> 1. **Smallest change**: add a name to the existing `server_name`, or add a *new* server block — never rewrite the live one. Then `nginx -t` and `systemctl reload nginx` (**reload, not restart**).
> 2. **Verify the update channel right after** (that is the one with real users today):
>    `curl -s "https://notice.example.com/api/version/check?version=1.5.76&build=116&platform=android"` must still return `{"code":0,...}`; glance at `/health` too.
> 3. **Traffic does not bleed either way** (a deliberate #130 isolation): fnthink floods go into their own rate-limit bucket `api-fnthink`, and the global layer skips dedicated prefixes entirely — so hammering the public face leaves the update channel alone. There is a test pinning exactly that (`server/test/fnthink-ratelimit.test.js`, the case named "fnthink flooded, update channel still fine").
>
> Also: if you would rather not expose the admin console on a second hostname, put **only** `/api/fnthink/`,
> `/health` and `/apks/` in the `push.*` server block and `return 404;` for everything else — then the two
> domains are separated by configuration instead of by memory.

**Free HTTPS certificate:**
Recommended Let's Encrypt with certbot for auto-renewal. Certificate rotation and pinning policy: `../docs/cert_rotation_runbook.md`.

***

### Option 3: Docker Deployment

**Create Dockerfile:**

```dockerfile
FROM node:24-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
EXPOSE 3456
CMD ["node", "server.js"]
```

> The base image must be **node:24** (`engines.node = ">=24"`). Keep `.env` and `data/` out of the build context (`.dockerignore`), inject secrets via `-e`/secrets, and provide the state/config directories as mounts so runtime data never gets baked into the image.

**Build and run:**

```bash
docker build -t update-server .
docker run -d \
  --name update-server \
  -p 3456:3456 \
  -v /path/to/data:/app/data \
  -v /path/to/public:/app/public \
  --restart unless-stopped \
  update-server
```

**Using docker-compose:**

Create `docker-compose.yml`:

```yaml
version: '3'
services:
  update-server:
    build: .
    ports:
      - "3456:3456"
    volumes:
      - ./data:/app/data
      - ./public:/app/public
    restart: unless-stopped
```

Start:

```bash
docker-compose up -d
```

***

### Option 4: Systemd Service (Linux)

Create `/etc/systemd/system/update-server.service`:

```ini
[Unit]
Description=Update Server
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/update-server
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT=3456
# Behind a reverse proxy, add one line (hops per your real chain):
# Environment=TRUST_PROXY=1

[Install]
WantedBy=multi-user.target
```

`.env` in the `WorkingDirectory` is loaded automatically by `dotenv` (first line of `server.js`: `require('dotenv').config()`), so keys don't belong in the unit file.

**Start and enable auto-start:**

```bash
systemctl daemon-reload
systemctl start update-server
systemctl enable update-server
```

**Check status and logs:**

```bash
systemctl status update-server
journalctl -u update-server -f
```

***

### Option 5: BT Panel (宝塔面板)

> BT Panel is essentially "Nginx plus a pile of visual managers", so **everything in Option 2 (Nginx) and
> Option 1 (PM2) applies here**; this section only covers the panel-specific traps. **This project needs no
> PHP and no database** — choose the minimal install and ignore the recommended-app list.

**Step 1 — install the panel + Nginx.** Take the **current** install command from the BT Panel official site
(commands change between versions; don't copy them from third-party blog posts). Then confirm **Nginx** is
installed in the App Store. **Do not install PHP / MySQL / phpMyAdmin.**

**Step 2 — Node and a process manager.**
- App Store → search `Node` → install **Node.js Version Manager** (or **PM2 Manager**) → install **24 LTS**;
- Equivalent if the panel UI fights you: use the panel's Terminal, install Node 24 per the NodeSource
  instructions, then `npm i -g pm2`.

**Step 3 — upload the code.**
- Panel way: zip `server/` locally (**excluding `data/`, `.env`, `node_modules/`**) → upload via **Files** to the
  code directory → extract over it. The panel's extract overwrites same-named files and deletes nothing else
  (safer than `--delete`), but **never include your local `data/` or `.env` in the archive**.
- Terminal way: the same two `rsync` commands as Option 0 (code + contract).
- **Put the contract separately**: `protocol/fnthink-v1.json` goes into a `protocol/` **sibling of the code
  directory** (the default location), or point `FNTHINK_CONTRACT` at any absolute path.

**Step 4 — site + reverse proxy.**
1. Websites → Add site: domain `notice.example.com` (**uncheck** FTP / database creation);
2. That site → Reverse Proxy → Add: target URL `http://127.0.0.1:3456`, sent domain `$host`;
3. Open the site's **config file** and verify these three lines — a missing `X-Forwarded-For` **must** be added,
   otherwise `.env`'s `TRUST_PROXY=1` cannot see real client IPs and rate limiting plus IP blocking will all
   count the proxy address:

   ```nginx
   proxy_set_header Host $host;
   proxy_set_header X-Real-IP $remote_addr;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   ```
4. In the same file set `client_max_body_size 2m;` (admin needs ≥1 MB; the public face enforces 64 KiB itself
   and answers in the protocol shape — too small here means Nginx rejects first with an HTML page);
5. SSL: site settings → SSL → Let's Encrypt (enable auto-renew). **Check those three lines again afterwards** —
   applying a certificate rewrites the 443 block and may reorder it.

**Give the push hostnames their own site** (`push.example.com`). This is the part where reverse-proxy details
matter most — three steps:

1. Websites → Add site: put the push hostname(s) in the domain field. **If you deploy only one, write only that
   one** (e.g. `push.example.com`); when a second hostname arrives, add it to `server_name` **and re-issue a
   certificate covering both** (SAN) before reloading.
   ⚠️ Never put a hostname into `server_name` that neither resolves here nor is covered by the certificate: that
   reads as a certificate mismatch the moment DNS starts resolving, and stays invisible until then — keep the
   config equal to reality. **Uncheck** FTP / database, leave the root directory at its default (no files).
2. Reverse Proxy → add **two entries** (the panel adds one at a time):

   | Name | Proxy directory | Target URL | Sent domain |
   | --- | --- | --- | --- |
   | `fnthink` | `/api/fnthink/` | `http://127.0.0.1:3456` | `$host` |
   | `health` | `/health` | `http://127.0.0.1:3456` | `$host` |

   ⚠️ **The proxy directory and the target URL must be a matching pair**: as soon as `proxy_pass` carries a URI
   (even just a single `/`), Nginx **replaces** the part of the path matched by the location with it. For a
   request to `/api/fnthink/poll`:

   | Proxy directory (location) | Target URL (proxy_pass) | Upstream actually receives | |
   | --- | --- | --- | --- |
   | `/api/fnthink/` | `http://127.0.0.1:3456` (**no URI**) | `/api/fnthink/poll` | ✅ recommended |
   | `/api/fnthink/` | `http://127.0.0.1:3456/api/fnthink/` (same length as the prefix) | `/api/fnthink/poll` | ✅ |
   | `/api/fnthink/` | `http://127.0.0.1:3456/` | `/poll` | ❌ prefix eaten |
   | `/api/fnthink` | `http://127.0.0.1:3456/` | `//poll` | ❌ extra slash |
   | `/api/fnthink` | `http://127.0.0.1:3456/api/fnthink/` | `/api/fnthink//poll` | ❌ sides not equal |

   ⇒ **Safest form**: proxy directory `/api/fnthink/` (trailing slash) with the target URL ending at the port
   (`http://127.0.0.1:3456`). ⚠️ What a panel shows is **not necessarily** what lands in the config file, and
   **editing that field in the panel may not stick** (BT Panel appends a `/` back to the target URL: depending on
   whether your proxy directory has a trailing slash, the *visible* symptom changes, but the root cause is always
   that one slash). After saving, open the site's **config file** and check the real `proxy_pass` line — the
   correct shape is `proxy_pass http://127.0.0.1:3456;` (nothing but a semicolon after the port). If the panel
   keeps putting the slash back, **delete those two proxy entries and write the locations by hand in the site
   config file** (Option 2 in this README shows the native form; the `proxy_pass` spelling is the same).

   > 🔎 **Tell-tale sign (one command settles it)**: `https://<push-host>/api/fnthink/poll` answers with
   > **Express's error page** and a wrong path — `Cannot POST /poll` (prefix eaten) or `Cannot POST //poll`
   > (extra slash).
   > ```bash
   > curl -s -X POST https://<push-host>/api/fnthink/poll -H 'Content-Type: application/json' -d '{}' | head -3
   > # wrong: <pre>Cannot POST /poll</pre>      right: {"receipt":"rejected_unsigned"} (HTTP 403)
   > ```
3. In the site's config file, change two things and verify the proxy block:

   ```nginx
   location / { return 404; }      # replace the panel's default location / with this line:
                                   # everything else is refused, so the admin console stays on the update host
   client_max_body_size 64k;       # match the server: the public face enforces 64 KiB itself,
                                   # smaller here means Nginx rejects first with HTML instead of the protocol shape
   ```

   ```nginx
   # verify (the panel template sometimes ships only the first two lines; the third is required —
   # without it, .env's TRUST_PROXY=1 cannot see real client IPs)
   proxy_set_header Host $host;
   proxy_set_header X-Real-IP $remote_addr;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   ```

> 💡 **What the push face does not need**: WebSocket / long-lived connections (`/poll` returns immediately),
> any static directory, PHP, or `proxy_read_timeout`-style tuning. The plainer the block, the better.
>
> ⚠️ **The reverse proxy is the only HTTPS exit**: the server does not check the scheme itself (the contract's
> `transport.httpsOnly=true` is a declaration it never reads), and it listens on `0.0.0.0` — so if port 3456 is
> reachable publicly, plain HTTP delivery works too. That is why step 6 says "open 80 / 443 only".

**Pairing self-check (three calls that separate "which layer answered 404 / 502")**

```bash
# 1) straight to the upstream (bypassing Nginx): expect 403
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:3456/api/fnthink/poll \
     -H 'Content-Type: application/json' -d '{}'
# 2) through Nginx: expect 403 as well
curl -sk -o /dev/null -w '%{http_code}\n' -X POST https://push.example.com/api/fnthink/poll \
     -H 'Content-Type: application/json' -d '{}'
# 3) the admin console must not be reachable here: expect 404
curl -sk -o /dev/null -w '%{http_code}\n' https://push.example.com/admin.html
```

403 on ① but 404 on ② ⇒ the proxy is misconfigured (almost always the trailing slash on the target URL);
502 on ② ⇒ upstream not running / wrong port.

**Step 5 — start the process.**
- Panel: Websites → **Node Project** → Add (startup file `server.js`, port `3456`, run directory = code
  directory, user `www`);
- Equivalent: terminal `cd <code dir> && pm2 start server.js --name update-server && pm2 save`;
- ⚠️ **The run directory must be the code directory**: `.env` is read by `dotenv` relative to the process
  working directory, so a wrong directory means `ADMIN_TOKEN_HASH` is missing and the process exits immediately;
- Autostart: tick it in the Node Project / PM2 Manager, or use `pm2 startup` from the terminal.

**Step 6 — panel-specific security (do not skip).**
- **Do not open port 3456**: the service listens on `0.0.0.0`, so opening it under Security bypasses Nginx's
  HTTPS and rate limiting entirely (`curl http://<your-ip>:3456/admin.html` would reach the admin console).
  Open **80 / 443** only.
- The panel itself: change its default entry path/port and enable two-factor authentication.
- Backups: use Scheduled Tasks to archive **`data/` under the code directory** daily (`totp.json` and the five
  fnthink tables live there). The panel's "site backup" covers the whole site directory — **when restoring,
  restore code only, never `data/`**, or the device table and pairing grants roll back to an old revision.

**Step 7 — acceptance**: the same five `curl`s as the previous section (with your domains), the update-channel
regression included.

**Troubleshooting (panel environments)**

| Symptom | Cause | Fix |
| --- | --- | --- |
| 502 Bad Gateway | Node not running / wrong port | Node Project logs; `pm2 logs update-server` |
| 404 from the site | no reverse proxy, or the domain is not bound to that site | Step 4 |
| Process keeps restarting, log says the key is unset | wrong run directory ⇒ `.env` not read | the ⚠ in Step 5 |
| Let's Encrypt fails | domain not resolving here / port 80 taken | check DNS and ports |
| Every device gets 429 | shared egress behind a proxy and `TRUST_PROXY` unset | set `TRUST_PROXY=1` and restart |

***

## 🧪 Local Development & Self-check

Scripts from `package.json` (run inside `server/`, Node 24 required):

| Command | Actually runs | Purpose |
| --- | --- | --- |
| `npm start` | `node server.js` | Start the service |
| `npm run dev` | `node server.js` | Same (no hot reload) |
| `npm test` | `jest --verbose` | HTTP contract tests: `test/auth.test.js` drives real requests through supertest — security headers, login/logout/session expiry, the version save chain, the full TOTP flow, concurrent recovery-code replay, prototype-key forgery, and the 5-failure IP block |
| `npm run format` | `prettier --write "lib/**/*.js" server.js "test/**/*.js"` | Format |
| `npm run format:check` | `prettier --check …` | Check only (used by CI) |

Tests use a temporary `DATA_DIR` (`os.tmpdir()`), so the live `data/` is never touched. At the repo root there is an additional release gate: `bash .github/scripts/check_version_consistency.sh` (version/build consistency + `sha256` completeness + site i18n coverage + untranslated ARB keys + doc consistency).

CI mirrors it: `.github/workflows/analyze.yml` runs `npm ci --no-audit --no-fund` + `npm test` on Node 24 (step `Server HTTP contract tests`), and `bash .github/scripts/check_format.sh` gates dart format / ktlint / prettier.

***

## ⚠️ Deployment Boundary (Single Instance Only)

**Rate limiting, sessions and IP blocking are authoritative in a single process's memory; the JSON files are only persisted copies** (`sessions.json` / `failed_attempts.json` / `blocked_ips.json` / `rate_limit.json` under `data/`): they are loaded once at startup, every decision afterwards reads memory, and changes/timers write the files back. Consequences:

- The current implementation supports **single-instance deployment only** (one Node process). PM2 cluster mode, multiple Docker replicas or multi-machine load balancing make the instances diverge: independent rate-limit counters, sessions logged in on instance A invalid on instance B, and drifting IP block state.
- **Deleting `data/blocked_ips.json` by hand does not unblock immediately** — a service restart is required (`pm2 restart update-server`), see the IP blocking section. Same for `sessions.json`: deleting the file does not disconnect live sessions because memory still holds them.
- `blocked_ips.json` / `sessions.json` / `failed_attempts.json` are written **on each mutation** (write-behind); `rate_limit.json` is flushed by the 60-second timer in `server.js`.
- A `kill -9` may lose the state written since the last flush (re-login required, rate-limit/block counters reset); normal termination (SIGINT/SIGTERM/SIGHUP) saves rate limits, sessions and failure counters in `onShutdown`.
- To scale horizontally, first externalize state to Redis (or SQLite) and refactor `server/lib/store.js` to centralized storage.

***

## 🔒 Security Hardening

Already built into the server (no extra work needed):

- **Admin endpoint auth**: every `/api/admin/*` route runs `authMiddleware` — bcrypt over `x-admin-token`, or a validated `x-session-id` session; with 2FA enabled the session must additionally be OTP-verified (else `401 code -2`). The session table is `Object.create(null)` plus `isValidSession()`, so the `x-session-id: __proto__` prototype-chain forgery is closed.
- **One-time recovery codes**: consumption happens inside `store.withAuthLock()`'s auth critical section, re-reading the config under the lock, so concurrent replay of the same code can succeed only once.
- **Built-in rate limiting**: 60 requests per IP per 60 s (plus 5/min on `/api/admin`), counted per route bucket; over the limit → `429 {code:-4, retryAfter}`. A Nginx layer adds defence in depth but is not the only line.
- **IP blocking**: 5 consecutive 2FA failures in a 10-minute window block the IP for 1 hour; `/health` and `/api/version*` are exempt, so a false block cannot break client update checks.
- **Security headers**: site-wide `nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy`, HSTS (`max-age=31536000; includeSubDomains`); a strict CSP on `/admin.html` (`default-src 'self'`, `frame-ancestors 'none'`, script externalized in `admin.js`); `Cache-Control: no-store` on `/api/admin/*`.
- **Request body size limit**: `express.json({limit:'1mb'})`.
- **CORS allow-list**: by default only requests without an Origin (native app / curl / same-origin) plus `ALLOWED_ORIGINS` entries pass.
- **No framework fingerprint**: `app.disable('x-powered-by')`.
- **Encryption key**: set `ENCRYPTION_KEY` (64 hex chars) to encrypt the TOTP secret. Generate with:
  ```bash
  node -e "console.log(require('crypto').randomBytes(32).toString('hex'));"
  ```

Still on the operator:

1. **Enable HTTPS**: production must use HTTPS to prevent tampering (the app requires `https://` in `downloads`).
2. **Defence in depth for the admin API**: if the admin entry point is fixed, add an IP allow-list or Basic Auth for `/api/admin/` in Nginx.
3. **Static directory permissions**: `public/` must be read-only static content with no execution; `data/` must never be reachable through any web path (the static mount only points at `public/`).
4. **Regular backups**: back up `data/` off-site (especially `totp.json` and `version.json`) together with `ENCRYPTION_KEY` from `.env` — in the same batch, otherwise the secret cannot be decrypted on a restored host.
5. **Use CDN**: large downloads belong on a CDN or object storage.
6. **Token transport**: headers only (`x-admin-token` / `x-session-id`), never URL parameters; the same applies to recovery codes (`POST /api/admin/totp/rebind`; `GET /totp/setup?recoveryCode=` is refused by the server).
7. **Correct proxy hop count**: `TRUST_PROXY` must match the real chain, otherwise blocks/limits land on the proxy IP.

***

## 📱 Client Configuration

The app's update server URL is the compile-time constant `AppUpdateManager._updateServerUrl` in `lib/update_manager.dart` (currently `https://notice.example.com`). **There is no in-app setting to change it**; pointing the app elsewhere means editing that constant and shipping a new build, or switching to [GitHub Pages static deployment](GITHUB_PAGES-en.md) and pointing the constant there.

The app appends these paths automatically:

- Version check (API mode): `/api/version/check?version=…&build=…&platform=android`
- Static fallback (Pages / static hosting): `/api/version.json` (raw file, compared on the device)
- Relative download URLs: resolved as "server URL + relative path" (so `/apks/...` works, but the admin API only accepts absolute `https://`)
- Download fallbacks: after the CDN, the GitHub accelerator mirror (`xget.example.com`) and the official GitHub Release direct link are tried (same `notice_<flavour>_<version>.apk` naming)

**Note:** With HTTPS on the server side, ensure the certificate is valid. The app performs standard TLS validation by default; certificate pinning is off unless `CERT_PINS` is injected (see `../docs/cert_rotation_runbook.md`).

***

## ❓ FAQ

### Q: I modified version.json but the client didn't see the update?

A: The service reads the config file in real time on each request, so changes take effect immediately. If the client doesn't see the update, check:

1. The file is valid JSON (e.g. `node -e "JSON.parse(require('fs').readFileSync('data/version.json','utf8'))"`)
2. Client-side caching: the app checks at most once every 24 hours (force-stop and reopen it)
3. Whether the request even arrives: the server prints **no access log** (no morgan). Use Nginx `access.log`, or the PM2/systemd stdout of the process (the startup banner and the `[auth]` / `[version]` runtime warnings all go to stdout/stderr)

### Q: APK download is slow?

A: Recommendations:

1. Use a CDN to accelerate downloads
2. Let Nginx serve the static files directly (`location /apks/`)
3. Reduce APK size (per-arch packages instead of the universal one)

### Q: How to view access logs?

A: With PM2:

```bash
pm2 logs update-server
```

With systemd:

```bash
journalctl -u update-server -f
```

### Q: Port already in use?

A: Change the port via environment variable:

```bash
PORT=3457 npm start
```

Or find the process occupying the port:

```bash
# Linux
lsof -i :3456
# or
netstat -tlnp | grep 3456
```

***

## Two-Step Verification (TOTP)

### Feature Description

- 2FA is **off by default** (the admin Token alone logs you in); enabling it right after the first login is strongly recommended but not enforced by the service.
- Once enabled, every login needs "Token + 6-digit code", and `authMiddleware` rejects any session that has not been OTP-verified — including token-only sessions minted before 2FA was enabled.
- **A successful `POST /api/admin/totp/enable` calls `revokeAllSessions()`**, wiping both memory and `sessions.json`: everyone must log in again with Token + OTP.
- Compatible with Google Authenticator, Microsoft Authenticator and other standard TOTP apps (6 digits, 30-second step).
- **8 recovery codes** are issued (each 8 hex characters, stored as bcrypt hashes) for lost-device logins, and each is **one-time**: it is removed from the set on use, and the consumption runs inside the auth critical section, so concurrent replay of the same code succeeds at most once.
- The server's TOTP time tolerance is `epochTolerance: 30` seconds (`lib/otp.js`): clock drift on the phone or the server is the first thing to suspect when a correct code keeps failing.
- 5 wrong codes within a 10-minute window block that IP for 1 hour (next section).
- Session TTL is a fixed 24 hours and does not slide with use.

### First Login Flow (enabling 2FA)

1. Open the console: `https://your-domain/admin.html` (same origin as the site root)
2. Enter the admin Token
3. Click "First login — set up two-step verification" (also reachable from the "Security Settings" tab)
4. Scan the QR code with an authenticator app (or type the `manualCode` secret by hand)
5. Confirm with the 6-digit code the app generates
6. **Save the 8 recovery codes shown right there** (offline copy; plaintext is shown only at this moment — the server stores hashes)
7. Done — note that all pre-existing sessions are revoked at this point, so re-login with Token + OTP

### Subsequent Login Flow

1. Enter the admin Token
2. Enter the two-step verification code
3. Login successful (`sessionId` returned; send it as `x-session-id` afterwards)

### Using Recovery Codes

1. Enter the admin Token
2. Click "Use Recovery Code"
3. Enter a saved recovery code (8 hex chars; case-insensitive — the server normalizes with `trim().toUpperCase()`)
4. Login successful, and that code is consumed (8 → 7)

When the codes run out: while logged in, use "Regenerate recovery codes" in Security Settings (`POST /api/admin/totp/regenerate-recovery`, needs the current OTP or one still-valid recovery code) to get a brand-new set of 8; the old ones are all invalid afterwards.

### Changing Phones (re-binding the authenticator)

`POST /api/admin/totp/rebind` with a recovery code in the **body** (`GET /totp/setup?recoveryCode=` is rejected with `400`, because query strings land in access logs and browser history). It returns a new secret + QR code; then call `/totp/enable` with a code from the new authenticator to finish the swap. A wrong recovery code counts towards the 2FA failure counter and is subject to IP blocking.

### Disabling Two-Step Verification

In the console's "Security Settings" tab; requires the current TOTP code or a recovery code. Note: disabling only flips the `enabled` flag — it does **not** revoke sessions and does not clear the recovery-code set.

### Manually Resetting Two-Step Verification (device lost, no recovery codes)

Delete the TOTP config file on the server. The config is **read per request**, so this takes effect immediately — no restart needed to fall back to token-only login:

```bash
rm /opt/update-server/data/totp.json
```

If you also need to drop every live session (e.g. a suspected token leak), delete `sessions.json` **and restart** — sessions are memory-authoritative, so removing the file alone does nothing:

```bash
rm /opt/update-server/data/sessions.json
pm2 restart update-server
```

> ⚠️ Don't treat this as a backup strategy: the secret inside `totp.json` is encrypted with `ENCRYPTION_KEY`. Lose `.env` and the ciphertext cannot be decrypted (login returns 500 "服务端二步验证密钥配置错误", which is **not** counted as a failure and does not block the IP) — deleting `totp.json` and re-binding is the only way forward.

---

## 🛡️ IP Blocking

### Security Policy

| Rule | Config | Source |
| --- | --- | --- |
| Max failed attempts | 5 | `store.MAX_FAILED_ATTEMPTS` |
| Failure window | 10 minutes (from the first failure) | `store.FAILURE_WINDOW_MINUTES` |
| Block duration | 1 hour (re-triggering extends it) | `store.BLOCK_DURATION_HOURS` |
| Unblock | Automatic expiry (pruned and rewritten on the next visit) | `store.isIpBlocked()` |
| Emergency switch | `DISABLE_IP_BLOCKING=1` disables blocking (failures still counted, nothing rejected) | `.env` |

### Trigger Conditions

- 5 accumulated **two-step verification** failures inside a 10-minute window: a wrong OTP/recovery code on `POST /api/admin/login`, or a wrong recovery code on `POST /api/admin/totp/rebind`.
  **A wrong admin Token is not counted** (it returns `401 {code:-1, message:"Token 错误"}`) and never triggers a block; a server-side `ENCRYPTION_KEY` decryption failure returns 500 without counting.
- Once blocked, requests get `403 {code:-3, blocked:true, remainingHours}`. Blocking is per IP and applies to **every path except the public ones**: `/api/admin/*`, the console page `/admin.html`, and other static paths.
- Public endpoints are exempt (`middleware.ipBlockMiddleware` returns early): `/health` and `/api/version*` — a false block therefore cannot break update checks on existing devices.
- This all assumes the client IP is correct: reverse-proxy deployments must set `TRUST_PROXY`, otherwise every request is attributed to the proxy IP and a single false block locks everyone out.

### Manual Unblock

> ⚠️ **`blocked_ips` is memory-authoritative with write-behind to disk**: the file is loaded on the first lookup after startup and afterwards the decision only reads memory. **Deleting `data/blocked_ips.json` does not unblock anything until the service restarts.**

```bash
# View blocked IPs (observation only; the live truth is in the process's memory)
cat /opt/update-server/data/blocked_ips.json

# Unblock immediately: delete the file + restart (restart reloads the cache from the file = empty)
rm /opt/update-server/data/blocked_ips.json
pm2 restart update-server
```

If your own egress IP got blocked and a restart is inconvenient, set `DISABLE_IP_BLOCKING=1` and restart (emergency only — remember to remove it afterwards).

---

## 📁 Data File Reference

| File | Created when | Authoritative source | Description |
| --- | --- | --- | --- |
| `data/version.json` | **Shipped with the repo** (written by the release script or the admin API) | Disk (read per request) | Version config. Effective as soon as it is saved, no restart |
| `data/totp.json` | First `/api/admin/totp/enable` | Disk (read per request) | `enabled` flag + AES-256-GCM encrypted secret + recovery-code bcrypt hashes. **Irrecoverable if lost** |
| `data/sessions.json` | First login / on every session change | **Memory** (loaded at startup) | Admin sessions (24h TTL). Deleting the file needs a restart |
| `data/blocked_ips.json` | First IP block | **Memory** (loaded on first access, written back on change) | Blocked IP list. Deleting the file needs a restart |
| `data/failed_attempts.json` | First 2FA failure | **Memory** (loaded at startup) | Failure counters within the 10-minute window |
| `data/rate_limit.json` | Flushed by the 60-second timer | **Memory** (loaded at startup) | Rate-limit counters, only in-window entries; deleted once everything expired |

`data/` is created automatically when missing (`DATA_DIR` relocates it). Everything except `version.json` is runtime state and is not tracked in git — **deployment uploads must avoid this directory entirely**.

---

## 📝 Changelog

### Server v1.1.1 (synchronized with app v1.5.33)

- ✅ TOTP secret stored with AES-256-GCM encryption
- ✅ Recovery codes stored with bcrypt hashing
- ✅ Session IDs generated with crypto.randomUUID()
- ✅ Token only accepted via Header, URL parameters disabled
- ✅ Global async error handler middleware added
- ✅ trust proxy configured, real IP via req.ip (defaults to 0 = trust no proxy header; set `TRUST_PROXY=1` explicitly behind a reverse proxy, see `.env.example`)
- ✅ Request body size limited to 1MB
- ✅ OkHttp auto-retry disabled to avoid double retries

### Server v1.1.0

- ✅ Added two-step verification (TOTP)
- ✅ Added IP blocking (**at the time** 3 failures / 10-minute window / 240-hour block; today it is 5 / 10 minutes / 1 hour — `server/lib/store.js` is the source of truth)
- ✅ Added admin panel page (`/admin.html`)
- ✅ Added login endpoint (`/api/admin/login`)
- ✅ Added TOTP-related API endpoints
- ✅ Added Token auth middleware
- ✅ Added dotenv environment variable support

### Server v1.0.0

- Initial release
- APK version check and download
- Force update support
- Admin API provided

---

## 🧱 Recent Server-Side Hardening (all active, consistent with the sections above)

- ✅ **Node 24 baseline**: `engines.node = ">=24"`, CI pinned to Node 24.
- ✅ **Layered code**: routes/storage/middleware split into `lib/` (`app.js` assembly, `store.js` persistence, `otp.js` TOTP, `middleware.js`, `routes/`); `server.js` only handles startup and lifecycle. Tests `require('./lib/app')` and issue real HTTP.
- ✅ **Session security**: `Object.create(null)` session table plus the three-part `isValidSession()` check closes the `x-session-id: __proto__` bypass; with 2FA on, non-OTP sessions get `401 code -2`; `/totp/enable` calls `revokeAllSessions()`.
- ✅ **Atomic recovery-code consumption**: read → bcrypt compare → consume → persist inside `store.withAuthLock()`, re-reading the config under the lock, so concurrent replay of the same code succeeds once.
- ✅ **Rate limiting per route bucket**: `api-admin` / `api` / `static` plus a 20 000-entry hard cap, so arbitrary paths can no longer inflate memory and `rate_limit.json`.
- ✅ **IP block state moved to memory with write-behind**: `blocked_ips` is loaded once instead of being read synchronously per request (that per-request file IO was a self-inflicted DoS); the trade-off is that deleting the file needs a restart.
- ✅ **Whitelist projection on version save**: `POST /api/admin/version` persists only the 12 known fields, unknown ones are ignored and never echoed back through the public endpoint; an omitted `sha256` keeps the existing value.
- ✅ **Proportionate blocking**: 5 failures / 10 minutes / 1 hour, with `/health` and `/api/version*` exempt so a false block never stops updates.
- ✅ **Diagnosable 2FA misconfiguration**: a decryption failure answers 500 with an explicit message, without counting failures or blocking; the startup banner prints the TOTP diagnostics and `DISABLE_IP_BLOCKING` state.
- ✅ **Recovery codes via POST only**: `/totp/rebind` replaced `GET /totp/setup?recoveryCode=` (query strings leak into access logs / history).
- ✅ Express 5 + otplib 13 (pluggable crypto/base32) and the fail-safe `trust proxy` default of 0.
