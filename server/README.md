# 通知推送助手 - 更新服务端

版本更新与热更新服务，基于 Node.js + Express 实现。

***

## 🚀 快速开始（新手 5 分钟上手）

### 第一步：准备环境

确保你的服务器需要安装 **Node.js**（版本 14 及以上）。

**检查是否已安装：**

打开终端（命令行），输入：

```bash
node -v
npm -v
```

如果能看到版本号（如 `v18.17.0`），说明已安装。

**没有安装？去这里下载：**

- 官网：<https://nodejs.org/> （推荐 LTS 长期支持版）
- Windows: 下载 .msi 安装包，一路下一步即可
- Linux: 推荐使用 nvm 管理多版本

### 第二步：上传文件到服务器

将 `server` 文件夹中的所有文件上传到你的服务器。

例如上传到 `/opt/update-server/` 目录。

### 第三步：安装依赖

在服务器上，进入 `server` 目录，执行：

```bash
cd server
npm install
```

等待安装完成，看到 `added X packages` 就说明成功了。

### 第四步：启动服务

```bash
npm start
```

看到类似下面的输出，说明服务启动成功：

```
==============================
  更新服务已启动
  端口: 3456
  时间: ...
==============================
```

**默认端口是 3456**，可以通过环境变量 `PORT` 修改。

### 第五步：验证服务是否正常

在浏览器中访问：

```
http://你的服务器IP:3456/health
```

如果返回：

```json
{ "status": "ok", "timestamp": "..." }
```

说明服务运行正常！🎉

### 第六步：发布第一个更新

**发布 APK 更新：**

1. 把你的 APK 文件重命名为 `app-release.apk`，放到 `server/public/apks/` 目录
2. 编辑 `server/data/version.json` 文件，修改版本信息：

```json
{
  "latestVersion": "1.2.0",
  "latestBuild": 19,
  "forceUpdate": false,
  "forceUpdateVersion": "1.0.0",
  "forceUpdateBuild": 1,
  "changelog": "1. 新增在线更新功能\n2. 新增热更新功能\n3. 修复若干bug",
  "downloadUrl": "/public/apks/app-release.apk",
  "fileSize": 56623104,
  "platform": "android",
  "minSupportedVersion": "1.0.0"
}
```

1. 保存文件，**不需要重启服务**（每次请求都会实时读取配置）

\*\*发布热更新（可选）：

1. 把热更新 ZIP 包放到 `server/public/hotfix/` 目录
2. 编辑 `server/data/hotfix.json`

***

## 📁 目录结构

```
server/
├── server.js              # 主服务文件（入口）
├── package.json           # 项目依赖配置
├── README.md              # 本说明文档
├── data/                  # 配置数据目录（自动创建）
│   ├── version.json       # APK 版本配置
│   └── hotfix.json        # 热更新配置
└── public/                # 静态资源目录（自动创建）
    ├── apks/              # APK 文件存放
    └── hotfix/           # 热更新包存放
```

> 💡 \*\*提示：`data/` 和 `public/` 目录如果不存在，服务启动时会自动创建。

***

## ⚙️ 配置详解

### 环境变量

| 变量名    | 说明     | 默认值    |
| ------ | ------ | ------ |
| `PORT` | 服务监听端口 | `3456` |

\*\*修改端口的方式：

**Windows (PowerShell / CMD：**

```powershell
# PowerShell
$env:PORT=8080; npm start
```

```cmd
:: CMD
set PORT=8080 && npm start
```

**Linux / macOS：**

```bash
PORT=8080 npm start
```

### version.json 字段说明（APK 版本配置）

| 字段                    | 类型      | 说明             | 示例                               |
| --------------------- | ------- | -------------- | -------------------------------- |
| `latestVersion`       | string  | 最新版本号（语义化版本）   | `"1.2.0"`                        |
| `latestBuild`         | number  | 最新构建号（整数递增）    | `19`                             |
| `forceUpdate`         | boolean | 是否启用强制更新       | `false`                          |
| `forceUpdateVersion`  | string  | 低于此版本的强制更新     | `"1.0.0"`                        |
| `forceUpdateBuild`    | number  | 低于此构建号的强制更新    | `1`                              |
| `changelog`           | string  | 更新日志，`\n` 表示换行 | `"1. 修复bug"`                     |
| `downloadUrl`         | string  | APK 下载路径       | `"/public/apks/app-release.apk"` |
| `fileSize`            | number  | 文件大小（字节）       | `56623104`                       |
| `platform`            | string  | 平台             | `"android"`                      |
| `minSupportedVersion` | string  | 最低支持版本         | `"1.0.0"`                        |

### hotfix.json 字段说明（热更新配置）

| 字段                     | 类型      | 说明            | 示例                              |
| ---------------------- | ------- | ------------- | ------------------------------- |
| `latestContentVersion` | number  | 最新内容版本号（整数递增） | `3`                             |
| `version`              | string  | 热更新包版本号       | `"1.0.3"`                       |
| `forceUpdate`          | boolean | 是否强制更新        | `false`                         |
| `forceContentVersion`  | number  | 低于此内容版本强制更新   | `1`                             |
| `changelog`            | string  | 更新说明          | `"更新了部分文案"`                     |
| `downloadUrl`          | string  | 热更新包下载路径      | `"/public/hotfix/hotfix_3.zip"` |
| `fileSize`             | number  | 文件大小（字节）      | `1048576`                       |
| `platform`             | string  | 平台            | `"android"`                     |
| `minAppVersion`        | string  | 要求的最低 APP 版本  | `"1.2.0"`                       |

***

## 🔌 API 接口文档

### 1. 检查 APK 版本更新

```
GET /api/version/check
```

\*\*请求参数：

| 参数         | 类型     | 必填 | 说明              |
| ---------- | ------ | -- | --------------- |
| `version`  | string | 是  | 当前版本号，如 `1.1.7` |
| `build`    | number | 是  | 当前构建号，如 `18`    |
| `platform` | string | 否  | 平台，默认 `android` |

**响应示例：**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "hasUpdate": true,
    "latestVersion": "1.2.0",
    "latestBuild": 19,
    "forceUpdate": false,
    "changelog": "1. 新增功能\n2. 修复bug",
    "downloadUrl": "/public/apks/app-release.apk",
    "fileSize": 56623104,
    "platform": "android",
    "minSupportedVersion": "1.0.0"
  }
}
```

### 2. 检查热更新

```
GET /api/hotfix/check
```

**请求参数：**

| 参数               | 类型     | 必填 | 说明              |
| ---------------- | ------ | -- | --------------- |
| `contentVersion` | number | 是  | 当前内容版本号         |
| `platform`       | string | 否  | 平台，默认 `android` |

**响应示例：**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "hasUpdate": true,
    "latestContentVersion": 3,
    "version": "1.0.3",
    "forceUpdate": false,
    "changelog": "更新了部分文案和图标",
    "downloadUrl": "/public/hotfix/hotfix_3.zip",
    "fileSize": 1048576,
    "platform": "android",
    "minAppVersion": "1.2.0"
  }
}
```

### 3. 获取版本配置（管理用）

```
GET /api/admin/version
```

### 4. 更新版本配置（管理用）

```
POST /api/admin/version
Content-Type: application/json
```

请求体为完整的 version.json 内容。

### 5. 获取热更新配置（管理用）

```
GET /api/admin/hotfix
```

### 6. 更新热更新配置（管理用）

```
POST /api/admin/hotfix
Content-Type: application/json
```

请求体为完整的 hotfix.json 内容。

### 7. 健康检查

```
GET /health
```

用于监控服务是否存活。

***

## 📦 发布更新完整流程

### 发布 APK 版本更新

\*\*步骤 1：准备 APK 文件

编译好 release 版本的 APK，例如 `app-release.apk`。

\*\*步骤 2：计算文件大小（字节）

可以用以下方式获取：

- Windows: 右键文件 → 属性 → 大小
- Linux: `ls -l app-release.apk` 或 `stat -c%s app-release.apk`
- 在线工具搜索"文件大小计算器"

\*\*步骤 3：上传文件

将 APK 文件上传到服务器的 `server/public/apks/` 目录。

**步骤 4：修改配置文件**

编辑 `server/data/version.json`，更新以下字段：

- `latestVersion` - 新版本号
- `latestBuild` - 新构建号
- `changelog` - 更新内容
- `fileSize` - 文件大小（字节）
- `forceUpdate` - 是否强制更新（可选）

**步骤 5：保存，完成！**

保存文件后立即生效，无需重启服务。

***

### 发布热更新

\*\*步骤 1：准备热更新包

制作 ZIP 格式的热更新资源包。

**步骤 2：上传文件**

将 ZIP 文件上传到服务器的 `server/public/hotfix/` 目录。

**步骤 3：修改配置**

编辑 `server/data/hotfix.json`，更新以下字段：

- `latestContentVersion` - 内容版本号（整数，每次 +1）
- `version` - 热更新包版本号
- `changelog` - 更新说明
- `fileSize` - 文件大小（字节）

**步骤 4：保存，完成！**

> ⚠️ **注意：** 热更新的内容版本号是独立于 APK 版本号。APK 更新后，内容版本号会重置。所以发布新 APK 时，请确保 `minAppVersion` 字段设置正确，避免低版本 APK 收到不兼容的热更新。

***

## 🔥 生产环境部署（专业运维指南）

以下是生产环境推荐的部署方式，从简单到复杂依次介绍。

### 方案一：PM2 守护进程（推荐中小型项目）

PM2 是 Node.js 进程管理工具，可以：

- 进程守护（崩溃自动重启）
- 日志管理
- 开机自启
- 负载均衡

\*\*安装 PM2：

```bash
npm install -g pm2
```

**启动服务：**

```bash
cd /server #此处根据你所放的server目录
pm2 start server.js --name update-server
```

**常用命令：**

```bash
pm2 list                    # 查看所有进程
pm2 logs update-server       # 查看日志
pm2 restart update-server    # 重启
pm2 stop update-server       # 停止
pm2 delete update-server  # 删除
```

**设置开机自启：**

```bash
pm2 save
pm2 startup
```

执行 `pm2 startup` 后会输出一条命令，复制粘贴执行即可。

***

### 方案二：Nginx 反向代理 + HTTPS（推荐生产环境）

使用 Nginx 作为反向代理，好处：

- 支持 HTTPS
- 负载均衡
- 静态文件加速
- 更安全

**Nginx 配置示例：**

```nginx
server {
    listen 80;
    server_name notice.fnthink.top;

    # 重定向到 HTTPS
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name notice.fnthink.top;

    # SSL 证书配置（使用你的证书路径）
    ssl_certificate /path/to/your/cert.pem;
    ssl_certificate_key /path/to/your/private.key;

    # 安全头
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;

    # 静态文件直接由 Nginx 处理（性能更好
    location /public/ {
        alias /opt/update-server/public/;
        expires 7d;  # 缓存 7 天
    }

    # 其他请求转发给 Node.js
    location / {
        proxy_pass http://127.0.0.1:3456;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**免费 HTTPS 证书：**
推荐使用 Let's Encrypt 免费证书，配合 certbot 自动续期。

***

### 方案三：Docker 部署

**创建 Dockerfile：**

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
EXPOSE 3456
CMD ["node", "server.js"]
```

**构建并运行：**

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

**使用 docker-compose：**

创建 `docker-compose.yml`：

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

启动：

```bash
docker-compose up -d
```

***

### 方案四：Systemd 系统服务（Linux）

创建 `/etc/systemd/system/update-server.service`：

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

\*\*启动并设置开机自启：

```bash
systemctl daemon-reload
systemctl start update-server
systemctl enable update-server
```

**查看状态和日志：**

```bash
systemctl status update-server
journalctl -u update-server -f
```

***

## 🔒 安全加固建议

1. **启用 HTTPS**：生产环境务必使用 HTTPS，防止数据篡改
2. **管理接口鉴权**：`/api/admin/*` 接口建议增加身份验证，例如：
   - IP 白名单限制
   - API Key 验证
   - 放在 Nginx 后面加 Basic Auth
3. **文件上传安全**：确保 public 目录只允许静态文件访问，禁止执行权限
4. **定期备份**：定期备份 `data/` 目录的配置文件
5. **使用 CDN**：大文件下载建议使用 CDN 或对象存储，减轻源站压力
6. **限制访问频率**：使用 Nginx 或其他工具限制 API 调用频率，防止滥用

***

## 📱 客户端配置

APP 默认服务器地址：`https://notice.fnthink.top`

在 APP 的「设置」→「其他设置」页面中，可以查看或修改更新服务器地址。

APP 会自动拼接以下接口路径：

- 版本检查：`/api/version/check`
- 热更新检查：`/api/hotfix/check`

**注意：** 如果你的服务端使用 HTTPS，请确保证书有效。

***

## ❓ 常见问题

### Q: 修改了 version.json 为什么客户端没生效？

A: 服务每次请求都会实时读取配置文件，修改后立即生效。如果客户端没收到更新，请检查：

1. 文件是否保存正确
2. 客户端是否有缓存（可以强制停止 APP 再打开）
3. 检查服务器日志看是否访问日志

### Q: 下载 APK 很慢怎么办？

A: 推荐：

1. 使用 CDN 加速下载
2. 使用 Nginx 直接提供静态文件服务
3. 压缩 APK 大小

### Q: 如何查看访问日志？

A: 如果用 PM2：

```bash
pm2 logs update-server
```

如果用 systemd：

```bash
journalctl -u update-server -f
```

### Q: 端口被占用了怎么办？

A: 修改端口号，用环境变量指定其他端口：

```bash
PORT=3457 npm start
```

或者找到占用端口的进程：

```bash
# Linux
lsof -i :3456
# 或
netstat -tlnp | grep 3456
```

### Q: 热更新包支持更新哪些内容？

A: 热更新目前主要用于资源文件和配置文件的热更新。不支持更新：

- 文案配置文件
- 图片等资源文件
- 其他静态配置

**注意：** Dart 代码的逻辑修改需要通过 APK 更新，热更新无法实现代码热更新需要配合 Flutter 的代码热更新能力。

***

## � 二步验证（TOTP）

### 功能说明

- 首次登录必须设置二步验证
- 启用后每次登录需要输入 6 位验证码
- 支持 Google Authenticator、Microsoft Authenticator 等应用
- 提供 8 个恢复码用于设备丢失时登录
- 10 分钟内连续输错 3 次验证码，IP 会被封锁 240 小时

### 首次登录流程

1. 打开管理后台：`https://your-domain.com/public/admin.html`
2. 输入管理员 Token
3. 点击「首次登录 - 设置二步验证」
4. 扫描二维码到认证应用
5. 输入生成的 6 位验证码
6. **保存恢复码**（非常重要！）
7. 完成设置

### 后续登录流程

1. 输入管理员 Token
2. 输入二步验证验证码
3. 登录成功

### 使用恢复码登录

1. 输入管理员 Token
2. 点击「使用恢复码」
3. 输入之前保存的 8 位恢复码
4. 登录成功

### 禁用二步验证

在管理后台「安全设置」标签页中操作，需要输入当前二步验证验证码或恢复码。

### 手动重置二步验证

如果丢失设备且没有恢复码：

```bash
rm /opt/update-server/data/totp.json
pm2 restart update-server
```

---

## 🛡️ IP 封锁机制

### 安全策略

| 规则 | 配置 |
|------|------|
| 最大失败次数 | 3 次 |
| 时间窗口 | 10 分钟 |
| 封锁时长 | 240 小时（10 天） |
| 解封方式 | 自动到期解封 |

### 触发条件

- 10 分钟内连续输错 3 次二步验证验证码
- IP 被封锁后，所有管理接口（`/api/admin/*`）和管理后台页面都无法访问

### 手动解除封锁

```bash
# 查看被封锁的 IP
cat /opt/update-server/data/blocked_ips.json

# 删除封锁记录（重启服务后生效）
rm /opt/update-server/data/blocked_ips.json
pm2 restart update-server
```

---

## 📁 数据文件说明

| 文件 | 生成时机 | 说明 |
|------|----------|------|
| `data/version.json` | 首次访问版本检查接口 | 版本配置 |
| `data/hotfix.json` | 首次访问热更新检查接口 | 热更新配置 |
| `data/totp.json` | 首次启用二步验证时 | 二步验证密钥和恢复码 |
| `data/blocked_ips.json` | 首次封锁 IP 时 | 被封锁的 IP 列表 |

这些文件在服务运行时自动创建，无需手动创建。

---

## �📝 更新日志

### 服务端版本：1.1.0

- ✅ 添加二步验证（TOTP）功能
- ✅ 添加 IP 封锁机制（3次失败/10分钟窗口/240小时封锁）
- ✅ 添加管理后台页面（`/public/admin.html`）
- ✅ 添加登录接口（`/api/admin/login`）
- ✅ 添加二步验证相关 API 接口
- ✅ 添加 Token 鉴权中间件
- ✅ 添加 dotenv 环境变量支持

### 服务端版本：1.0.0

- 初始版本
- 支持 APK 版本检查和下载
- 支持热更新检查和下载
- 支持强制更新配置
- 提供管理 API

