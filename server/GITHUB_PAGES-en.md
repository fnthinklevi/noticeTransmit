# GitHub Pages Deployment Guide

What GitHub Pages can and cannot give you today: it publishes the **static website** (the landing page plus
`/api/version.json`). **The app's update channel needs something that answers `/api/version/check`** — Pages cannot
provide that (see "How the app gets updates today").

## Deployment Mode Comparison

| | Node.js Server | GitHub Pages |
| --- | --- | --- |
| **Runtime** | Requires a Node.js process (Node 24) | Static files, zero ops |
| **In-app update check** | ✅ `/api/version/check` — the **only** path the app uses | ❌ **Does not work**: the app never reads the static `version.json` |
| **Website shows the latest version** | ✅ | ✅ (that `/api/version.json` is published for the landing page) |
| **APK hosting** | ✅ `/apks/` (relative `downloads` entries resolve too) | ❌ No APK in the artifact (`server/public/apks/` is gitignored, so a CI checkout has an empty directory) ⇒ downloads must point at a CDN or Releases |
| **Admin panel** | ✅ Available (`admin.html` + `/api/admin/*`) | ❌ Unavailable (page loads, endpoints do not exist) |
| **Version management** | `POST /api/admin/version` validates then writes; the API computes `hasUpdate` / `forceUpdate` | ❌ Edit the repo file and redeploy; without that API nobody computes `hasUpdate` for you |
| **2FA** | ✅ Supported (TOTP + recovery codes) | ❌ Not available |
| **IP blocking / rate limiting** | ✅ Supported (built in) | ❌ Not available |
| **Geo read-back** (`/api/version/region`, how the app picks a region) | ✅ | ❌ Does not exist — static hosting cannot run logic |
| **Cost** | Server + Nginx + PM2 | Free, zero config |
| **Use case** | **If the app must receive updates, this is the only option** | Static mirror of the website / docs; **not** an app update channel |

## How the app gets updates today (actual behaviour, 2026-10-07)

The client fires **one** request, `GET <the region it picked>/api/version/check?version=…&build=…&platform=android`, with four outcomes:

```
200 + {code:0, data:{…}}         → use the server-computed hasUpdate / forceUpdate; that same request is
                                   also recorded as this host's health
blocked by the CDN (CF 403 …)    → an actionable error right away (every other path on that domain is behind
                                   the same protection, so switching paths cannot help)
any other non-200 / code != 0    → report that answer and stop
network error                    → one retry after a 2 s backoff; if neither went out, report "no reply"
                                   (kept distinct from "it replied 500")
```

⚠ **The old "fall back to `/api/version.json`" static mode was deleted outright** (commit `cbec666`). Not because few
people used it — because **it never worked**: the server has no such route, and both official hosts answer with
Express's own `Cannot GET /api/version.json` (the maintainer confirmed on 2026-10-07 it was deliberately never built).
Its only effect was to make the user wait out a second 15 s timeout and then report the same error.
⇒ **"Deploy Pages only" is therefore not an update channel for the app.**

Which host the app dials comes from the **two regions** in `lib/services/update_server_regions.dart` (mainland /
international, differing only by host name), picked in More → Update server: automatic (probe both, pick by result)
or manual (pinned; nothing may auto-change it). **There is no compile-time `_updateServerUrl` left to edit**, which is
exactly why this page's old advice ("point the constant at the Pages URL and ship a new build") is void.

Downloads are unchanged: the client picks its package from the server-served `downloads` by device ABI, verifies
`sha256` before install (N3), and after the primary CDN tries the GitHub accelerator mirror and the Release direct
link — the mirror keeps **the same asset name as the primary URL**, and the Release tag **carries the `v` prefix**.

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

Example: `https://your-org.github.io/noticeTransmit/`

The Pages site root **includes the repository-name prefix** (`https://your-org.github.io/noticeTransmit`) and that still matters: the landing page resolves its relative addresses (`api/version.json`, in-page links) against the site root, so dropping the prefix 404s them.
⚠ But **the reader is the landing page, not the app's update request** — the app does not read `/api/version.json` (see the section above), so feeding it a Pages URL cannot work.

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

> Note that `api/version.json` is a **synthesized path**: in the repository the file lives at `server/data/version.json`, and on Pages it appears under `/api/`.
> ⚠ Its reader today is the **landing page** (the first of its four-tier data fallback, see `public/index.html`), **not the app** — it used to match the client's static fallback request, and that request was deleted in commit `cbec666` (the server has no such route). The path stays because the website still uses it; do not dismiss it as dead weight.
> Anything you add to `server/public/` ends up in the artifact automatically; files in `server/data/` other than `version.json` (`totp.json`, `sessions.json`, … runtime state) are **never** published.

## Publishing a New Release

### GitHub Pages Mode

1. Edit `server/data/version.json`: `latestVersion`, `latestBuild`, `changelog`, `minSupportedVersion`, `forceUpdate` (with `forceUpdateVersion`/`forceUpdateBuild`), and the four-arch `downloads` / `fileSizes` / `sha256`
2. Upload the APKs to a CDN or GitHub Releases. The app's download order is: the entry in `downloads` (the server-served primary CDN URL) → the GitHub accelerator mirror → the Release direct link. The last two are **synthesised by the client** as `<mirrorBase>/v<version>/<the file name from the primary URL>`:
   - The tag segment **must carry `v`**. `.github/workflows/build-apk.yml` only creates a Release on `v*` tags — this page used to say "the tag must be exactly the version number (no `v`)", which was precisely the defect #234 fixed: the synthesised URL was guaranteed to 404, and it is **only reachable when the primary CDN is already down**, so no everyday test touches it.
   - The file name **is the one from the primary URL** (the release script builds once and archives to both places ⇒ same file). Rename `downloads` and the mirror copy has to be renamed with it. The rule lives in `lib/services/update_download_urls.dart`; do not copy it elsewhere.
3. Run the local gate first: `bash .github/scripts/check_version_consistency.sh` (checks version/build consistency plus `sha256` format and completeness) — the Pages copy is a static file, so once published nothing on the server side validates those fields for you.
4. Commit and push to `main`
5. GitHub Actions deploys to Pages; verify `https://<site>/api/version.json` already serves the new version
6. ⚠ **the app still cannot see the new release after this step** (it does not read the static file — see above). For the app, the **server's** `version.json` must change: `POST /api/admin/version` from the console, or edit the file on the server (read per request, no restart)

### Node.js Server Mode

1. Edit `server/data/version.json` (edit the repo copy and deploy it, or edit the file on the server)
2. Submit it from the console at `/admin.html` via `POST /api/admin/version` — effective on save, no restart; the server validates fields, projects onto the whitelist and carries the existing `sha256` over
3. Or edit the file on the server directly — it is also read per request, no restart needed

## Hybrid Deployment (the current setup)

- **GitHub Pages** = static mirror of the website (`your-org.github.io/<repo>`); its `/api/version.json` is read by the **landing page**
- **Node.js server** = the app's update channel and the admin console (written `notice.example.com` / `notice.example.top` below; the two regions differ only by host name)
- The app dials **whichever of the two regions was picked** (More → Update server, automatic or manual), **always via `/api/version/check`**

⚠ This section used to read "the client's `_updateServerUrl` points at the Node server, Pages static mode as the fallback path; if the Node server / CDN is unreachable, point the constant at the Pages address and ship a new build".
**That path no longer exists**: the constant was removed in T95 slice 2 and the static fallback in `cbec666` ⇒ Pages cannot serve as a backup update channel for the app.
The only "other host" that actually takes effect on the app side is **the other region in that table** — which is another Node instance, not Pages.

## What this page does not cover: fnthink Push, and why

GitHub Pages is **purely static**: it can publish JSON files, but it cannot run logic. The fnthink Push server side — registration, pairing, inbox, long-polling, signature verification, rate limiting, 2FA — is **all logic**.

So:

| Capability | GitHub Pages | Node.js self-hosted |
|---|---|---|
| Website shows the latest version / manual download entry | ✅ | ✅ |
| **In-app update check** | ❌ **does not work**: the app only requests `/api/version/check`, it never reads the static JSON | ✅ |
| fnthink Push (`/api/fnthink/*`) | ❌ **does not exist at all** | ✅ available once the contract is installed |

⚠ **Pages has neither a "lite" fnthink Push nor a degraded update channel.** It has static files: that `/api/version.json`
is read by the landing page (the app does not read it), and there is not even a `/health`. If you want the app to receive
new versions, or want push, you have to run the Node.js copy yourself (see the README's "installing the fnthink Push
public surface" and the comparison table above).

### Boundary statement (same as the README section)

- The **official instance** is the maintainer's default service address, upgraded in step with App releases. A **self-hosted instance** is yours: no availability promise, no support, and it does not represent the official one.
- A **Pages site is only a static publishing channel** — neither an official instance nor a "service instance"; it does not even have `/health`.
- If you point the client's fnthink Push service address at a third-party instance, **they can read the message body and metadata** (the in-app privacy notice says so too).

### Version policy

Only the **App and the official instance** are guaranteed to upgrade together. The Pages site and self-hosted instances are yours to track; when a self-hosted contract and its code are from different generations, that server **refuses outright** (rather than making the best of it) — `npm run fnthink:doctor` tells you in one step (details in the README).

## Notes

1. **GitHub Pages has a 1 GB storage limit and 100 GB/month bandwidth**, and is not suited to large files — APK download URLs must point to a CDN or GitHub Releases
2. **JSON updates may have a 1–2 minute CDN cache delay**; after a release, fetch `https://<site>/api/version.json` to confirm it refreshed, then **reload the website**
   (⚠ the reader to check is the website, not the app: the app never reads this file. Its path goes through the server's `/api/version/check`, and both official hosts answer `Cache-Control: no-cache` ⇒ every call revalidates with the origin, so "Pages refreshed, so the app will see it" is not a thing)
3. **The admin panel (`admin.html`) opens on GitHub Pages but every `/api/admin/*` request 404s** (`admin.js` builds URLs from `window.location.origin`): login, version editing and 2FA are all unusable there
4. **The static file on Pages gets no server-side validation at all**: a bad `version.json` (non-integer `latestBuild`, uppercase `sha256`, `http://` in `downloads`) is parsed with whatever tolerance the **landing page** has ⇒ the symptom is "the page shows a wrong version / size / link".
   ⚠ Do not confuse that with "reaches every user": today that sentence only holds for the **server's copy** (the app reads `/api/version/check`). But both copies come from one place — the file you `rsync` from the repo *is* the server's — so **always run `check_version_consistency.sh` before releasing**. (The admin API `POST /api/admin/version` does validate and project onto a whitelist; editing the file directly does not.)
5. **Runtime state under `server/data/` is never published**, and Pages obviously has no 2FA, sessions, IP blocking or rate limiting — those exist only in the Node.js server
