# Notification Push Helper — Update Server

Version update service, built with Node.js + Express.

> 💡 **Don't want to maintain a server?** This project also supports [GitHub Pages static deployment](GITHUB_PAGES-en.md), zero-maintenance and free. The client auto-compatibles with both modes.

***

## 🚀 Quick Start (5 minutes)

### Step 1: Prepare the Environment

Your server needs **Node.js** (v14 or above).

**Check if installed:**

```bash
node -v
npm -v
```

If you see a version number (e.g. `v18.17.0`), it's ready.

**Not installed? Download here:**

- Official site: <https://nodejs.org/> (recommended LTS)
- Windows: download the .msi installer, click through
- Linux: recommended to use nvm for multi-version management

### Step 2: Upload Files to Server

Upload all files from the `server` folder to your server.

e.g. to `/opt/update-server/`.

### Step 3: Install Dependencies

On the server, in the `server` directory:

```bash
cd server
npm install
```

When you see `added X packages`, it's done.

### Step 4: Start the Service

```bash
npm start
```

When you see output like the following, the service has started:

```
==============================
  Update service started
  Port: 3456
  Time: ...
==============================
```

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

1. Rename your APK to `app-release.apk` and put it in `server/public/apks/`
2. Edit `server/data/version.json` with your version info:

```json
{
  "latestVersion": "1.2.0",
  "latestBuild": 19,
  "forceUpdate": false,
  "forceUpdateVersion": "1.0.0",
  "forceUpdateBuild": 1,
  "changelog": "1. New feature\n2. Bug fixes",
  "downloadUrl": "/public/apks/app-release.apk",
  "fileSize": 56623104,
  "platform": "android",
  "minSupportedVersion": "1.0.0"
}
```

3. Save the file — **no need to restart the service** (config is read on each request)

***

## 📁 Directory Structure

```
server/
├── server.js              # Main service file (entry point)
├── package.json           # Project dependency config
├── README.md              # This documentation
├── data/                  # Config data directory (auto-created)
│   └── version.json       # APK version config
└── public/                # Static assets directory (auto-created)
    └── apks/              # APK file storage
```

> 💡 **Tip**: `data/` and `public/` directories are auto-created on startup if they don't exist.

***

## ⚙️ Configuration Details

### Environment Variables

| Variable | Description | Default |
|---|---|---|
| `PORT` | Server listen port | `3456` |
| `ADMIN_TOKEN_HASH` | bcrypt hash of admin token | None |
| `ENCRYPTION_KEY` | TOTP secret encryption key (32-byte hex) | None (optional) |
| `NODE_ENV` | Runtime environment | `production` |

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

| Field | Type | Description | Example |
|---|---|---|---|
| `latestVersion` | string | Latest version number (semver) | `"1.2.0"` |
| `latestBuild` | number | Latest build number (incrementing int) | `19` |
| `forceUpdate` | boolean | Enable forced update | `false` |
| `forceUpdateVersion` | string | Force update below this version | `"1.0.0"` |
| `forceUpdateBuild` | number | Force update below this build | `1` |
| `changelog` | string | Changelog, `\n` for newlines | `"1. Bug fix"` |
| `downloadUrl` | string | APK download path | `"/public/apks/app-release.apk"` |
| `fileSize` | number | File size in bytes | `56623104` |
| `platform` | string | Platform | `"android"` |
| `minSupportedVersion` | string | Minimum supported version | `"1.0.0"` |

***

## 🔌 API Reference

### 1. Check APK Version Update

```
GET /api/version/check
```

**Request parameters:**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `version` | string | Yes | Current version, e.g. `1.1.7` |
| `build` | number | Yes | Current build, e.g. `18` |
| `platform` | string | No | Platform, default `android` |

**Response example:**

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
    "downloadUrl": "/public/apks/app-release.apk",
    "fileSize": 56623104,
    "platform": "android",
    "minSupportedVersion": "1.0.0"
  }
}
```

### 2. Get Version Config (Admin)

```
GET /api/admin/version
```

### 3. Update Version Config (Admin)

```
POST /api/admin/version
Content-Type: application/json
```

Request body is the full `version.json` content.

### 4. Health Check

```
GET /health
```

For monitoring service liveness.

***

## 📦 Full Release Workflow

### Publishing an APK Version Update

**Step 1: Prepare the APK**

Build a release APK, e.g. `app-release.apk`.

**Step 2: Get the file size (bytes)**

- Windows: right-click → Properties → Size
- Linux: `ls -l app-release.apk` or `stat -c%s app-release.apk`

**Step 3: Upload the file**

Upload the APK to the server's `server/public/apks/` directory.

**Step 4: Update the config**

Edit `server/data/version.json`, update these fields:

- `latestVersion` — new version number
- `latestBuild` — new build number
- `changelog` — update content
- `fileSize` — file size in bytes
- `forceUpdate` — whether to force update (optional)

**Step 5: Save — done!**

The file takes effect immediately after saving, no service restart needed.

## 🔥 Production Deployment (Ops Guide)

The following are recommended production deployment options, from simple to advanced.

### Option 1: PM2 Process Manager (Recommended for small/medium projects)

PM2 is a Node.js process manager that provides:

- Process guard (auto-restart on crash)
- Log management
- Boot auto-start
- Load balancing

**Install PM2:**

```bash
npm install -g pm2
```

**Start the service:**

```bash
cd /path/to/server
pm2 start server.js --name update-server
```

**Common commands:**

```bash
pm2 list                     # View all processes
pm2 logs update-server       # View logs
pm2 restart update-server    # Restart
pm2 stop update-server       # Stop
pm2 delete update-server     # Delete
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
    server_name notice.fnthink.top;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name notice.fnthink.top;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/private.key;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;

    # Static files served directly by Nginx (better performance)
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
}
```

**Free HTTPS certificate:**
Recommended Let's Encrypt with certbot for auto-renewal.

***

### Option 3: Docker Deployment

**Create Dockerfile:**

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
EXPOSE 3456
CMD ["node", "server.js"]
```

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

[Install]
WantedBy=multi-user.target
```

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

## 🔒 Security Hardening

1. **Enable HTTPS**: Production must use HTTPS to prevent data tampering
2. **Admin endpoint auth**: `/api/admin/*` endpoints should add identity verification:
   - IP whitelist
   - API key verification
   - Basic Auth behind Nginx
3. **File upload security**: ensure public directory allows static file access only, disable execution permissions
4. **Regular backups**: regularly back up the `data/` directory config files
5. **Use CDN**: large file downloads recommended via CDN or object storage to offload origin server load
6. **Rate limiting**: use Nginx or other tools to limit API call frequency to prevent abuse
7. **Encryption key**: set `ENCRYPTION_KEY` to encrypt TOTP secret. Generate with:
   ```bash
   node -e "console.log(require('crypto').randomBytes(32).toString('hex'));"
   ```
8. **Token security**: only accept via `x-admin-token` Header, never via URL parameters
9. **Request body size limit**: default 1MB, prevents large request attacks

***

## 📱 Client Configuration

Default server URL in the app: `https://notice.fnthink.top`

In the app's Settings → Other Settings page, you can view or change the update server URL.

The app automatically appends these endpoints:

- Version check: `/api/version/check`

**Note:** If using HTTPS, ensure your certificate is valid.

***

## ❓ FAQ

### Q: I modified version.json but the client didn't see the update?

A: The service reads config in real-time on each request. Changes take effect immediately. If the client doesn't see the update, check:

1. Is the file saved correctly?
2. Does the client have a cache? (force-stop and reopen the app)
3. Check server logs for incoming requests

### Q: APK download is slow?

A: Recommendations:
1. Use CDN to accelerate downloads
2. Use Nginx to serve static files directly
3. Compress APK size

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

- Two-step verification must be set up on first login
- Each login requires a 6-digit code after enabling
- Compatible with Google Authenticator, Microsoft Authenticator, etc.
- 8 recovery codes provided for lost-device login
- After 3 consecutive wrong codes within 10 minutes, IP is blocked for 240 hours

### First Login Flow

1. Open admin panel: `https://your-domain.com/admin.html`
2. Enter admin Token
3. Click "First Login — Set Up Two-Step Verification"
4. Scan the QR code into your auth app
5. Enter the generated 6-digit code
6. **Save your recovery codes** (very important!)
7. Setup complete

### Subsequent Login Flow

1. Enter admin Token
2. Enter two-step verification code
3. Login successful

### Using Recovery Codes

1. Enter admin Token
2. Click "Use Recovery Code"
3. Enter a previously saved 8-character recovery code
4. Login successful

### Disabling Two-Step Verification

In the admin panel "Security Settings" tab, requires the current verification code or recovery code.

### Manually Resetting Two-Step Verification

If you lose your device and have no recovery codes:

```bash
rm /opt/update-server/data/totp.json
pm2 restart update-server
```

---

## 🛡️ IP Blocking

### Security Policy

| Rule | Config |
|------|------|
| Max failed attempts | 3 |
| Time window | 10 minutes |
| Block duration | 240 hours (10 days) |
| Unblock | Auto-expiry |

### Trigger Conditions

- 3 consecutive wrong TOTP codes within 10 minutes
- Blocked IPs cannot access any admin endpoints (`/api/admin/*`) or the admin panel page

### Manual Unblock

```bash
# View blocked IPs
cat /opt/update-server/data/blocked_ips.json

# Delete block records (effective after restart)
rm /opt/update-server/data/blocked_ips.json
pm2 restart update-server
```

---

## 📁 Data File Reference

| File | Created When | Description |
|------|-------------|-------------|
| `data/version.json` | First version check request | Version config |
| `data/totp.json` | First TOTP setup | TOTP key and recovery codes |
| `data/blocked_ips.json` | First IP block | Blocked IP list |

These files are auto-created at runtime; no manual creation needed.

---

## 📝 Changelog

### Server v1.1.1 (synchronized with v1.5.33)

- ✅ TOTP secret stored with AES-256-GCM encryption
- ✅ Recovery codes stored with bcrypt hashing
- ✅ Session IDs generated with crypto.randomUUID()
- ✅ Token only accepted via Header, URL parameters disabled
- ✅ Global async error handler middleware added
- ✅ trust proxy configured, real IP via req.ip
- ✅ Request body size limited to 1MB
- ✅ OkHttp auto-retry disabled to avoid double retries

### Server v1.1.0

- ✅ Added two-step verification (TOTP)
- ✅ Added IP blocking (3 fails / 10min window / 240h block)
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
