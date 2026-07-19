# GitHub Pages Deployment Guide

Deploy the update service via GitHub Pages as a lightweight alternative to a Node.js server.

## Deployment Mode Comparison

| | Node.js Server | GitHub Pages |
|---|---|---|
| **Runtime** | Requires Node.js process | Static files, zero ops |
| **Admin Panel** | ✅ Supported | ❌ Not available |
| **Version Management** | Server-side comparison | Client-side comparison |
| **2FA / IP Blocking** | ✅ Supported | ❌ Not available |
| **Cost** | Server + Nginx + PM2 | Free, zero config |
| **Use Case** | Production | Personal / small-scale |

## Client Compatibility

The client (`update_manager.dart`) automatically handles both modes:

```
1. Try /api/version/check?version=X&build=Y  (API mode)
   └─ 200 + JSON → use server result
   └─ 404 / timeout → fallback

2. Fallback to /api/version.json            (static mode)
   └─ 200 + raw JSON → client-side comparison
```

Hotfix: `/api/hotfix/check` → `/api/hotfix.json`. No client code changes needed.

## Quick Start (3 Steps)

### 1. Enable GitHub Pages

1. Go to repo → **Settings** → **Pages**
2. **Build and deployment** → Source: **GitHub Actions**
3. **Important**: Check "Allow GitHub Actions to publish to Pages" if prompted
4. The workflow `.github/workflows/deploy-pages.yml` will be automatically recognized

> ⚠️ **One-time setup only.** Thereafter, GitHub Actions auto-deploys on every relevant push.

### 2. Push to Deploy

Changes to `server/data/version.json`, `server/data/hotfix.json`, or `server/public/**` on the `main` branch trigger automatic deployment.

Manual trigger: **Actions** → **Deploy to GitHub Pages** → **Run workflow**.

### 3. Get the URL

```
https://<username>.github.io/<repository>/
```

Example: `https://fnthinklevi.github.io/noticeTransmit/`

## Static File Structure

```
/
├── index.html              ← homepage (copied from server/public/)
├── admin.html              ← admin panel (static, no API)
├── .nojekyll               ← disables Jekyll processing
└── api/
    ├── version.json        ← version config (copied from server/data/)
    └── hotfix.json         ← hotfix config (copied from server/data/)
```

## Publishing a New Release

### GitHub Pages Mode

1. Edit `server/data/version.json` (version, changelog, downloadUrl, fileSize)
2. Upload APK to CDN or GitHub Releases
3. Commit and push to `main`
4. GitHub Actions auto-deploys

### Node.js Server Mode

1. Edit `server/data/version.json`
2. Update via admin panel API (hot-reload, no restart)
3. Or edit file directly and restart the service

## Hybrid Deployment (Recommended)

- **GitHub Pages**: main site (`username.github.io/repo`)
- **Node.js server**: admin panel + API (`your-domain.com`)
- Client `_updateServerUrl` points to either one

## Notes

1. **GitHub Pages has a 1 GB storage limit and 100 GB/month bandwidth**
2. **JSON updates may have 1–2 minute CDN cache delay**
3. **The admin panel (`admin.html`) can open on GitHub Pages but API calls will fail**
4. **APK download URLs must still point to CDN or GitHub Releases** (GitHub Pages is not suitable for large file hosting)
