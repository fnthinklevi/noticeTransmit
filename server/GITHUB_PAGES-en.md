# GitHub Pages Deployment Guide

Deploy the update service via GitHub Pages as a lightweight alternative to a Node.js server.

## Deployment Mode Comparison

| | Node.js Server | GitHub Pages |
| --- | --- | --- |
| **Runtime** | Requires a Node.js process (Node 24) | Static files, zero ops |
| **Admin panel** | ✅ Available (`admin.html` + `/api/admin/*`) | ❌ Unavailable (page loads, endpoints do not exist) |
| **Version management** | Server computes `hasUpdate`/`forceUpdate` | Client reads the raw JSON and compares locally |
| **2FA** | ✅ Supported (TOTP + recovery codes) | ❌ Not available |
| **IP blocking / rate limiting** | ✅ Supported (built in) | ❌ Not available |
| **Writing version.json** | ✅ `POST /api/admin/version` (with validation) | ❌ Edit the repo file and redeploy |
| **Cost** | Server + Nginx + PM2 | Free, zero config |
| **Use case** | Production | Personal / small-scale |

## Client Compatibility

`lib/update_manager.dart` handles both modes automatically (`_updateServerUrl` is a compile-time constant):

```
1. Try /api/version/check?version=X&build=Y&platform=android   (API mode)
   ├─ 200 + JSON {code:0, data:{…}}  → use the server-computed hasUpdate / forceUpdate
   ├─ network error                   → retry once after a 2s backoff, then fall back
   ├─ blocked by the CDN (Cloudflare 403 etc.) → no fallback (the static endpoint sits behind
   │    the same domain and protection, so it would fail too); show an actionable error
   └─ any other non-200 / code != 0   → fall back

2. Fallback to /api/version.json (no query parameters)                (static mode)
   └─ 200 + raw version.json → the client compares version/build itself and computes forceUpdate
```

No client code changes are needed — whichever URL returns valid JSON, the two modes switch automatically. In **both** modes the client selects the package from `downloads` by device ABI and verifies it against `sha256` before install (N3), so static mode **equally requires complete `downloads` / `fileSizes` / `sha256` maps**.

## What the Deployment Workflow Actually Does

The Pages site is published by `.github/workflows/deploy-pages.yml` (workflow name `Deploy to GitHub Pages`). **It publishes a `_pages/` directory assembled at build time — not any directory that exists in the repository:**

| Aspect | Implementation |
| --- | --- |
| Trigger | `push` to `main` touching `server/data/version.json` or `server/public/**`; also manual via **Actions → Deploy to GitHub Pages → Run workflow** (`workflow_dispatch`) |
| Runner | `ubuntu-24.04`, 7 steps (`actions/checkout@v7` + `configure-pages@v5` + `upload-pages-artifact@v3` + `deploy-pages@v4`) |
| Permissions | `contents: read`, `pages: write`, `id-token: write` |
| Concurrency | `group: pages` with `cancel-in-progress: true` (a newer push cancels the running deploy) |
| Artifact assembly | `mkdir -p _pages/api` → `cp -r server/public/* _pages/` → `cp server/data/version.json _pages/api/version.json` → `touch _pages/.nojekyll` (keeps Jekyll from mangling the JSON) |
| Upload / deploy | `upload-pages-artifact@v3` with `path: _pages`, then `deploy-pages@v4` (`enablement: true`, using `GITHUB_TOKEN`) |

> ⚠️ **The artifact contains no APKs**: `server/public/apks/` is git-ignored, so it is empty in a CI checkout. APKs must live on a CDN or in GitHub Releases (see "Notes").

## Quick Start (3 Steps)

### 1. Enable GitHub Pages

1. Go to repo → **Settings** → **Pages**
2. **Build and deployment** → Source: **GitHub Actions**
3. **Important**: Check "Allow GitHub Actions to publish to Pages" if prompted
4. The workflow `.github/workflows/deploy-pages.yml` will be automatically recognized

> ⚠️ **One-time setup only.** Thereafter, GitHub Actions auto-deploys on every relevant push.
> Pushes that only touch `README`, `docs/`, etc. do **not** trigger a deployment — the `paths` filter watches only `server/data/version.json` and `server/public/**`.

### 2. Push to Deploy

Changes to `server/data/version.json` or files under `server/public/**` pushed to the `main` branch trigger automatic deployment.

Manual trigger: **Actions** → **Deploy to GitHub Pages** → **Run workflow**.

### 3. Get the URL

```
https://<username>.github.io/<repository>/
```

Example: `https://fnthinklevi.github.io/noticeTransmit/`

For the client to read the static config, `_updateServerUrl` must include the repository-name prefix (the fallback request is `$_updateServerUrl/api/version.json`), i.e. `https://fnthinklevi.github.io/noticeTransmit`.

## Static File Structure

The `_pages/` directory assembled by the workflow (i.e. the Pages site root):

```
/
├── index.html              ← homepage (copied from server/public/)
├── admin.html              ← admin panel page (static; no API behind it)
├── admin.js                ← console script (external file, required by the CSP)
├── i18n.js                 ← zh/EN dictionary for the homepage
├── app_icon.png / favicon.ico
├── .nojekyll               ← disables Jekyll processing
└── api/
    └── version.json        ← version config (copied from server/data/version.json)
```

> Note that `api/version.json` is a **synthesized path**: in the repository the file lives at `server/data/version.json`, and on Pages it appears under `/api/` purely to match the client's fallback request. Anything you add to `server/public/` ends up in the artifact automatically; files in `server/data/` other than `version.json` (`totp.json`, `sessions.json`, … runtime state) are **never** published.

## Publishing a New Release

### GitHub Pages Mode

1. Edit `server/data/version.json`: `latestVersion`, `latestBuild`, `changelog`, `minSupportedVersion`, `forceUpdate` (with `forceUpdateVersion`/`forceUpdateBuild`), and the four-arch `downloads` / `fileSizes` / `sha256`
2. Upload the APKs to a CDN or GitHub Releases. The app's download order is `downloads` from version.json (CDN) → the GitHub accelerator mirror → the GitHub direct link, the last two built as `releases/download/<version>/notice_<arm64|arm32|x86|all>_<version>.apk`: for the mirrors to work, **the Release tag must be exactly the version number (no `v`) and the assets must use that naming**. (Heads-up: `.github/workflows/build-apk.yml` only creates a Release on `v*` tags and names its asset `notice<version>.apk`, which does not match this pattern — don't expect CI output to feed the mirror fallback.)
3. Run the local gate first: `bash .github/scripts/check_version_consistency.sh` (checks version/build consistency plus `sha256` format and completeness). In static mode no server validates anything for you.
4. Commit and push to `main`
5. GitHub Actions deploys to Pages; verify `https://<site>/api/version.json` already serves the new version

### Node.js Server Mode

1. Edit `server/data/version.json` (edit the repo copy and deploy it, or edit the file on the server)
2. Submit it from the console at `/admin.html` via `POST /api/admin/version` — effective on save, no restart; the server validates fields, projects onto the whitelist and carries the existing `sha256` over
3. Or edit the file on the server directly — it is also read per request, no restart needed

## Hybrid Deployment (Recommended — the current setup)

- **GitHub Pages** as the static marketing site (`fnthinklevi.github.io/noticeTransmit`)
- **Node.js server** for the API and the admin console (`notice.fnthink.top`)
- The client's `_updateServerUrl` points at the Node server: API results when available, Pages static mode as the fallback path

If the Node server / CDN is unreachable, point `_updateServerUrl` at the Pages address and ship a new build (it is a compile-time constant, not an in-app setting).

## Notes

1. **GitHub Pages has a 1 GB storage limit and 100 GB/month bandwidth**, and is not suited to large files — APK download URLs must point to a CDN or GitHub Releases
2. **JSON updates may have a 1–2 minute CDN cache delay**; after a release, fetch `https://<site>/api/version.json` first to confirm it has refreshed before testing the client
3. **The admin panel (`admin.html`) opens on GitHub Pages but every `/api/admin/*` request 404s** (`admin.js` builds URLs from `window.location.origin`): login, version editing and 2FA are all unusable there
4. **Static mode has zero server-side validation**: a bad `version.json` (non-integer `latestBuild`, uppercase `sha256`, `http://` in `downloads`) is parsed by each client's own tolerance and reaches every user — always run `check_version_consistency.sh` first
5. **Runtime state under `server/data/` is never published**, and Pages obviously has no 2FA, sessions, IP blocking or rate limiting — those exist only in the Node.js server
