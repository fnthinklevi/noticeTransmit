# Notification Push Helper — Update Server

Version update service, built with Node.js + Express.

> 💡 **Don't want to maintain a server?** This project also supports [GitHub Pages static deployment](GITHUB_PAGES-en.md), zero-maintenance and free. The client auto-compatibles with both modes.

***

## Quick Start

### Prerequisites

- **Node.js** 18+ (check with `node -v`)
- npm (comes with Node.js)

### Install

```bash
cd server
cp .env.example .env
# Edit .env: set ADMIN_TOKEN_HASH, ENCRYPTION_KEY, TOTP_SECRET etc.
npm install
```

### Run

```bash
# Development
node server.js

# Production (PM2)
pm2 install -g pm2
pm2 start server.js --name notice-server
pm2 save
pm2 startup
```

### Configure Nginx (Production)

```nginx
server {
    listen 443 ssl;
    server_name notice.fnthink.top;

    ssl_certificate     /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://127.0.0.1:3456;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## API Endpoints

| Endpoint | Description |
|---|---|
| `GET /api/version/check` | Check for app version update |
| `POST /api/admin/version` | Update version config (auth required) |

## Admin Panel

Access at `notice.fnthink.top/admin.html` — requires TOTP two-step verification.

## Static Files

- `public/index.html` — project homepage
- `public/admin.html` — admin console
- `data/version.json` — release version configuration

## Deployment Options

| Option | Guide |
|---|---|
| PM2 (recommended) | Run `pm2 start server.js` |
| Systemd | See [server/README.md](README.md) for details |
| Docker | See [server/README.md](README.md) for details |
| GitHub Pages | See [GITHUB_PAGES-en.md](GITHUB_PAGES-en.md) |
