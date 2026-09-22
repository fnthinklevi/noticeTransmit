# 通知推送助手 - 更新服务端

版本更新服务，基于 Node.js + Express 实现。

> 💡 **不想维护服务器？** 本项目也支持 [GitHub Pages 静态部署](GITHUB_PAGES.md)，零运维、免费、自动部署。客户端自动兼容两种模式，无需改代码。

***

## 🚀 快速开始（新手 5 分钟上手）

### 第一步：准备环境

必须安装 **Node.js 24 LTS 或更高版本**：`server/package.json` 的 `engines.node` 声明为 `>=24`，CI（`.github/workflows/analyze.yml` 的 `setup-node`）与本地契约测试均按 Node 24 验证。旧文档中的「14 及以上 / 18.x / 20.x」已失效。

**检查是否已安装：**

打开终端（命令行），输入：

```bash
node -v
npm -v
```

版本号需为 `v24.x` 或更高。若看到 `v18.x` / `v20.x`，请先升级到 24 LTS 再部署。

**没有安装？去这里下载：**

- 官网：<https://nodejs.org/> （选择 24 LTS 长期支持版）
- Windows: 下载 .msi 安装包，一路下一步即可
- Linux: 推荐使用 nvm 管理多版本（`nvm install 24 && nvm use 24`）

### 第二步：上传文件到服务器

将 `server` 文件夹上传到你的服务器，例如 `/opt/update-server/` 目录。

> ⚠️ **上传红线（本项目按「上传 server 目录」部署，不是 `git pull`）**：一次上传**绝不能覆盖或删除**以下内容，丢了就要重来一遍配置甚至把管理员锁在后台外：
>
> - `server/data/` —— `totp.json`（TOTP secret + 恢复码哈希）、`sessions.json`、`blocked_ips.json`、`failed_attempts.json`、`rate_limit.json`、`version.json` 全在这里，仓库里的 `data/` 只有 `version.json`，其余是**运行期产物**；
> - `server/.env` —— 真实密钥（`ADMIN_TOKEN_HASH` / `ENCRYPTION_KEY`），仓库只提交 `.env.example`；
> - `server/node_modules/` 与 `package-lock.json`（`.gitignore` 忽略 `server/node_modules/`）。
>
> **严禁使用 `--delete` 类同步**（`rsync --delete`、某些 SFTP 客户端的「镜像/同步目录」模式）：它会把服务器上独有的 `data/totp.json` 等文件删掉，结果是**二步验证密钥与恢复码全丢，owner 无法再登录管理后台**（只能按后文「手动重置二步验证」重绑认证器）。上传时逐文件覆盖，或只覆盖代码文件（`server.js` / `lib/` / `public/` / `package.json` / 文档）。

### 第三步：安装依赖

在服务器上，进入 `server` 目录，执行：

```bash
cd server
npm install
```

等待安装完成，看到 `added X packages` 就说明成功了。

首次部署后需按 `.env.example` 复制并填写 `.env`（`ADMIN_TOKEN_HASH` 必填，否则服务直接退出）。
**后续每次上传代码后**用 lock 文件精确复现依赖，原生依赖（bcryptjs 为纯 JS，无需编译）跨版本升级时可用 `npm rebuild` 兜底：

```bash
npm ci        # 严格按 package-lock.json 安装（会先清空 node_modules，不动 data/ 与 .env）
# 或 npm install（按 package.json 的范围安装）
```

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

1. 把 APK 放到 `server/public/apks/`（本仓库发版脚本按 `server/public/apks/<版本号>/notice_<平台>_<版本号>.apk` 归档），它经根路径直出：`https://你的域名/apks/<版本号>/xxx.apk`（旧写法 `/public/apks/...` 仍兼容）
2. 编辑 `server/data/version.json`（当前契约，四架构 `downloads` / `fileSizes` / `sha256`）：

```json
{
  "latestVersion": "1.2.0",
  "latestBuild": 19,
  "forceUpdate": false,
  "forceUpdateVersion": "1.0.0",
  "forceUpdateBuild": 1,
  "changelog": "1. 新增在线更新功能\n2. 修复若干bug",
  "downloads": {
    "arm64": "https://cdn2.fnthink.top/app/notice/update/1.2.0/notice_arm64_1.2.0.apk",
    "arm32": "https://cdn2.fnthink.top/app/notice/update/1.2.0/notice_arm32_1.2.0.apk",
    "x86_64": "https://cdn2.fnthink.top/app/notice/update/1.2.0/notice_x86_1.2.0.apk",
    "all": "https://cdn2.fnthink.top/app/notice/update/1.2.0/notice_all_1.2.0.apk"
  },
  "fileSizes": {
    "arm64": 27711096,
    "arm32": 23787240,
    "x86_64": 29809646,
    "all": 76161926
  },
  "sha256": {
    "arm64": "<arm64 包的 64 位小写十六进制 sha256>",
    "arm32": "<arm32 包的 sha256>",
    "x86_64": "<x86_64 包的 sha256>",
    "all": "<融合包的 sha256>"
  },
  "minSupportedVersion": "1.0.0"
}
```

`downloads` 各值必须是 `https://` 绝对地址（走 `POST /api/admin/version` 时服务端会校验）；手工编辑文件时相对路径（如 `/public/apks/app-release.apk`）也能被客户端解析成「服务器地址 + 相对路径」，但**不能**通过管理接口提交。

3. 保存文件，**不需要重启服务**（每次请求都会实时读取配置）

***

## 📁 目录结构

```
server/
├── server.js              # 入口（启动 + 优雅关闭 + 定时持久化）
├── lib/                   # 模块化分层
│   ├── app.js             # 应用组装（CORS/安全头/静态/限流/挂载，导出 app 供测试直连）
│   ├── store.js           # 存储/持久化（限流、会话、IP 封锁、TOTP 配置、恢复码临界区）
│   ├── otp.js             # TOTP 封装（otplib v13，需显式注入 crypto/base32 插件）
│   ├── middleware.js      # 安全头/限流/封锁/鉴权/错误处理
│   └── routes/            # 路由（auth.js / version.js）
├── test/auth.test.js      # HTTP 契约测试（jest + supertest，29 例）
├── package.json           # 依赖与 scripts（engines.node = ">=24"）
├── package-lock.json      # 依赖锁（npm ci 使用）
├── babel.config.js        # Jest ESM 兼容
├── .env.example           # 环境变量模板（复制为 .env 后填写）
├── .env                   # 真实密钥（已被 .gitignore 忽略，切勿提交/覆盖）
├── .prettierrc            # 代码风格（npm run format 使用）
├── README.md / README-en.md
├── GITHUB_PAGES.md / GITHUB_PAGES-en.md
├── data/                  # 运行期状态目录（不存在时自动创建）
│   ├── version.json       # APK 版本配置（唯一入库的文件）
│   ├── totp.json          # TOTP secret（AES-256-GCM 加密）+ 恢复码 bcrypt 哈希
│   ├── sessions.json      # 管理会话（TTL 24h）
│   ├── blocked_ips.json   # IP 封锁记录（内存为准，变更落盘）
│   ├── failed_attempts.json # 2FA 失败计数（10 分钟窗口）
│   └── rate_limit.json    # 限流计数（仅当前窗口内的记录）
└── public/                # 静态资源（随仓库入库，服务不自动创建）
    ├── index.html         # 官网首页
    ├── admin.html         # 管理后台页面
    ├── admin.js           # 管理后台脚本（CSP 要求外置，无内联脚本）
    ├── i18n.js            # 官网中/英字典
    ├── app_icon.png / favicon.ico
    └── apks/              # APK 归档目录（.gitignore 已忽略，不会进仓库）
```

> 💡 提示：只有 `data/` 会在启动时自动创建（`fs.mkdirSync(DATA_DIR, {recursive:true})`）；`public/` 不存在时静态资源只会 404，需要随代码一起上传。
> `data/` 下除 `version.json` 外全部是运行期产物，**不入库、不可被部署覆盖**。

***

## ⚙️ 配置详解

### 环境变量

以 `.env`（模板见 `server/.env.example`）或进程环境变量提供；`.env` 已被 `.gitignore` 忽略。

| 变量名                       | 说明 | 默认值 |
| ---------------------------- | ---- | ------ |
| `PORT`                       | 服务监听端口 | `3456` |
| `ADMIN_TOKEN_HASH`           | 管理员 Token 的 bcrypt 哈希（非明文）。**未配置时服务直接 `process.exit(1)` 不启动** | 无（必填） |
| `ENCRYPTION_KEY`             | TOTP secret 的 AES-256-GCM 密钥，**必须是 64 位十六进制**（32 字节）。格式非法会被忽略并告警，secret 转为明文存储 | 无（强烈建议配置） |
| `NODE_ENV`                   | 运行环境。仅影响错误响应是否回显内部异常细节：`development` 会带 `error` 字段，其他值只回 `服务器内部错误` | 未设（生产按 `.env.example` 写 `production`） |
| `TRUST_PROXY`                | 信任的反向代理跳数。0 = 不信任任何 `X-Forwarded-For`（直连部署的 fail-safe 默认）；Nginx 单层反代需设 `1`，Nginx+CDN 设 `2`。不设则 IP 封锁/限流全部记在代理 IP 上，误设则攻击者可伪造头绕封 | `0` |
| `ALLOWED_ORIGINS`            | CORS 白名单，逗号分隔；无 Origin 的请求（原生 App / curl / 同源）始终放行；`*` 恢复放行所有来源。**不设时，浏览器跨域携带 Origin 的请求会被拒绝**（同源管理后台不受影响） | 空 |
| `DATA_DIR`                   | 运行期状态目录（`version.json` / `totp.json` / `sessions.json` / …），测试隔离用 | `<server>/data` |
| `RATE_LIMIT_GENERAL_MAX`     | 全局限流：每 IP 每「路由桶」每 60 秒的最大请求数 | `60` |
| `RATE_LIMIT_AUTH_MAX`        | `/api/admin` 认证类限流：每 IP 每分钟最大请求数 | `5` |
| `DISABLE_IP_BLOCKING`        | `1` / `true` / `yes` 时关闭 IP 封锁（仍统计失败次数，不执行拦截），用于 NAT 出口误封时应急 | 关闭 |

生成两个密钥（先 `npm install`，占位符自行替换为真实值，**不要写进任何文档或提交**）：

```bash
# ADMIN_TOKEN_HASH：bcrypt cost 10
node -e "console.log(require('bcryptjs').hashSync('<你的管理员令牌>', 10))"
# ENCRYPTION_KEY：64 位十六进制
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

> ⚠️ `ENCRYPTION_KEY` 一旦用于启用二步验证就**不可更换**：换了新密钥后 `data/totp.json` 里的密文解不开，验证会返回 500「服务端二步验证密钥配置错误」（不计失败次数、不封 IP），必须按后文重置二步验证重新绑定。备份 `data/` 时请把 `.env` 里的 `ENCRYPTION_KEY` 一起异地保存。

**修改端口的方式：**

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

服务端 `POST /api/admin/version` 只接受下列 12 个字段（白名单投影），**其余字段一律不落盘**（服务端仅告警 `已忽略未知字段`）。

| 字段                    | 类型      | 说明             | 示例                               |
| --------------------- | ------- | -------------- | -------------------------------- |
| `latestVersion`       | string  | 最新版本号（语义化版本），必填非空 | `"1.2.0"`                        |
| `latestBuild`         | number  | 最新构建号（必填正整数，递增） | `19`                             |
| `forceUpdate`         | boolean | 是否启用强制更新       | `false`                          |
| `forceUpdateVersion`  | string  | 低于此版本强制更新；`forceUpdate=true` 时必填非空 | `"1.0.0"`                        |
| `forceUpdateBuild`    | number  | 低于此构建号强制更新；`forceUpdate=true` 时必填非负整数 | `1`                              |
| `changelog`           | string  | 更新日志，`\n` 表示换行 | `"1. 修复bug"`                     |
| `downloads`           | object  | 各架构下载地址，键 `arm64`/`arm32`/`x86_64`/`all`；提交到管理接口时须为 `https://` 绝对地址，空串表示该架构未发布 | `{"arm64":"https://.../notice_arm64_1.5.74.apk",...}` |
| `fileSizes`           | object  | 各架构文件大小（字节，非负整数） | `{"arm64":27711096,...}`         |
| `sha256`              | object  | 各架构安装包 sha256（64 位**小写**十六进制；空串/缺失 = 该架构跳过校验）。App 下载后、安装前比对（N3 传输层校验）。**管理后台表单不含此字段，但保存时会自动沿用 `version.json` 里的既有值**——sha256 由发版脚本回填文件 | `{"arm64":"<64位小写十六进制>",...}` |
| `minSupportedVersion` | string  | 最低支持版本（原样透传给客户端） | `"1.0.0"`                        |
| `downloadUrl`         | string  | （旧契约兼容，仅未提供 `downloads` 时校验）单一下载地址，须为 `https://` 绝对地址 | `"https://cdn2.fnthink.top/..."` |
| `fileSize`            | number  | （旧契约兼容）文件大小（字节，非负） | `56623104`                       |

> 已废弃字段：`platform`。服务端既不读取也不接受（不在白名单内），客户端也从不消费——请勿再写入。

***

## 🔌 API 接口文档

所有端点（路由定义见 `lib/routes/version.js` 与 `lib/routes/auth.js`，后者挂载于 `/api/admin`）：

| 方法 | 路径 | 鉴权 | 说明 |
| ---- | ---- | ---- | ---- |
| `GET`  | `/api/version/check` | 公开（豁免 IP 封锁） | App 检查版本更新 |
| `GET`  | `/health` | 公开（豁免 IP 封锁） | 健康检查 `{status:'ok',timestamp}` |
| `POST` | `/api/admin/login` | Token（+ OTP / 恢复码） | 登录，成功返回 `sessionId` |
| `POST` | `/api/admin/logout` | 会话/Token | 吊销当前会话 |
| `GET`  | `/api/admin/totp/setup` | 会话/Token | 未启用时生成 secret + 二维码；已启用时只回状态（不再泄露 secret） |
| `POST` | `/api/admin/totp/enable` | 会话/Token | 校验 OTP 后启用，返回 8 个恢复码，**并吊销全部既有会话** |
| `POST` | `/api/admin/totp/disable` | 会话/Token | 校验 OTP 或恢复码后关闭 |
| `GET`  | `/api/admin/totp/status` | 会话/Token | `{enabled, hasRecoveryCodes}` |
| `POST` | `/api/admin/totp/rebind` | 会话/Token | 提交恢复码（一次性核销）换取新 secret + 二维码，用于换手机 |
| `POST` | `/api/admin/totp/regenerate-recovery` | 会话/Token | 校验 OTP 或恢复码后重发 8 个恢复码 |
| `GET`  | `/api/admin/version` | 会话/Token | 原样回显 `data/version.json` |
| `POST` | `/api/admin/version` | 会话/Token | 字段校验 + 白名单投影后落盘 |

**认证凭据（仅 Header，禁止 URL 传参）：**

- `x-admin-token: <你的管理员令牌>` —— 与 `ADMIN_TOKEN_HASH` 做 bcrypt 比对；
- `x-session-id: <登录返回的 sessionId>` —— 由 `POST /api/admin/login` 响应体的 `sessionId` 给出（纯 Token 访问受保护端点时，服务端会新铸一条会话并经响应头 `x-session-id` 回传）。会话 TTL 固定 **24 小时**、不滑动续期；`POST /api/admin/logout` 后会话立即失效；重启不会踢人——`sessions.json` 在启动时重新载入，只有超过 TTL 的条目会被丢弃。

> 🔒 **二步验证已开启时，只有「OTP 校验过」的会话才有管理员权限**：纯 Token 请求、以及开启 2FA 之前铸造的 Token-only 会话都会收到 `401 {code:-2, require2FA:true}`；`/totp/enable` 成功时会调用 `revokeAllSessions()` 把内存与落盘的会话全清掉，所有人必须「Token + OTP」重新登录。伪造 `x-session-id`（如 `__proto__`、`constructor`）无效：会话表是 `Object.create(null)`，且必须通过 `isValidSession()` 的「自有属性 + `authenticated === true`」判定。

### 1. 检查 APK 版本更新

```
GET /api/version/check
```

**请求参数：**

| 参数         | 类型     | 必填 | 说明              |
| ---------- | ------ | -- | --------------- |
| `version`  | string | 否  | 当前版本号，如 `1.1.7`；缺省/非法按 `0` 参与比较（即恒判定为有更新） |
| `build`    | number | 否  | 当前构建号，如 `18`；缺省按 `0` |
| `platform` | string | 否  | 决定 `downloadUrl`/`fileSize` 取哪个架构：`x86_64` → x86_64、`armeabi-v7a` → arm32、其他任何值（含 App 默认发送的 `android`）→ arm64；命中架构为空时回退 `all` |

`hasUpdate = latestVersion > version || latestBuild > build`；响应的 `forceUpdate` 是「`forceUpdate=true` 且当前版本低于 `forceUpdateVersion`/`forceUpdateBuild`」的计算结果（不是配置文件原值）。

**响应示例（即服务端返回的全部键）：**

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
    "downloadUrl": "https://cdn2.fnthink.top/app/notice/update/1.2.0/notice_arm64_1.2.0.apk",
    "fileSize": 27711096,
    "downloads": {
      "arm64": "https://cdn2.fnthink.top/app/notice/update/1.2.0/notice_arm64_1.2.0.apk",
      "arm32": "https://cdn2.fnthink.top/app/notice/update/1.2.0/notice_arm32_1.2.0.apk",
      "x86_64": "https://cdn2.fnthink.top/app/notice/update/1.2.0/notice_x86_1.2.0.apk",
      "all": "https://cdn2.fnthink.top/app/notice/update/1.2.0/notice_all_1.2.0.apk"
    },
    "fileSizes": {
      "arm64": 27711096,
      "arm32": 23787240,
      "x86_64": 29809646,
      "all": 76161926
    },
    "sha256": {
      "arm64": "<arm64 包的 64 位小写十六进制>",
      "arm32": "<arm32 包的 sha256>",
      "x86_64": "<x86_64 包的 sha256>",
      "all": "<融合包的 sha256>"
    },
    "minSupportedVersion": "1.0.0"
  }
}
```

### 2. 获取版本配置（管理用）

```
GET /api/admin/version
```

需认证。原样返回 `data/version.json` 的内容（不做字段裁剪）。

### 3. 更新版本配置（管理用）

```
POST /api/admin/version
Content-Type: application/json
```

请求体为 version.json 内容（管理后台「版本管理」页提交的就是表单字段集合）。服务端行为：

1. **字段校验**（`lib/routes/version.js` 的 `validateVersionConfig`）：不通过 → `400 {code:-4, message:"字段校验失败: …"}`，逐项列出原因；
2. **白名单投影**：仅保留上文 12 个已知字段，**未知字段既不落盘也不回显**（服务端日志打印 `已忽略未知字段（不落盘）：…`）；
3. **sha256 沿用**：请求体未带 `sha256` 时自动保留文件里既有的值（管理后台表单无此字段，保存不会丢掉发版回填的校验值）；显式提交则可覆盖；
4. 原子写入（先写 `.tmp` 再 `rename`）：成功 `{code:0,message:"保存成功"}`，写盘失败 `{code:-1,message:"保存失败"}`。

> App 拿到 `/api/version/check` 响应后**按自身 ABI 从 `downloads` 选包**（`platform=android` 时服务端给的 `downloadUrl` 只是 arm64 提示值），下载完成后用 `sha256` 对应项做传输层校验，再由原生 `ApkSignatureVerifier` 比对签名（见 `../docs/cert_rotation_runbook.md` 第 7 节）。

### 4. 健康检查

```
GET /health
```

用于监控服务是否存活，返回 `{"status":"ok","timestamp":"…"}`；与 `/api/version/*` 一并豁免 IP 封锁（NAT 共享出口下误封不会殃及全体设备的更新检查）。

### 错误码约定

| HTTP | `code` | 含义 | 处理建议 |
| ---- | ------ | ---- | -------- |
| 200  | `0`    | 成功 | — |
| 401  | `-1`   | 未授权 / 会话已过期 / 验证码错误（登录响应带 `remainingAttempts`） | 重新登录 |
| 401  | `-2`   | 需要二步验证（`require2FA: true`） | 提示输入 OTP，**不要**清空本地会话（前端只在 `-1` 时登出） |
| 403  | `-3`   | IP 已被封锁（`blocked: true`、`remainingHours`） | 等待到期，或按后文「手动解除封锁」 |
| 400  | `-4`   | 字段校验失败 / 请求体非 JSON 对象 | 按 `message` 修正后重试 |
| 429  | `-4`   | 触发限流（带 `retryAfter` 秒数） | 退避后重试 |
| 500  | `-5`   | 服务器内部错误；`-2` 另用于「服务端二步验证密钥配置错误」（`ENCRYPTION_KEY` 缺失或不匹配，不计失败次数、不封 IP） | 查服务端日志与 `ENCRYPTION_KEY` |

### 限流的计数口径

- 限流键为 `IP:路由桶`，桶由 `store.rateLimitBucket()` 把请求者可控的任意路径收敛为三类：`api-admin`（`/api/admin*`）、`api`（其他 `/api/*`）、`static`（其余全部路径）。404 探测串、随机 query 不再各自产生记录。
- 窗口 60 秒：`static` / `api` 桶每 IP 每分钟 `RATE_LIMIT_GENERAL_MAX`（默认 60）次；`/api/admin` 在其之上再叠加 `RATE_LIMIT_AUTH_MAX`（默认 5）次的认证类限流。
- 限流表条目硬上限 20 000：超限时先清理过期项，仍超限则本次不记账（放行而非拒绝），避免内存被打爆。
- 每 60 秒定时清理并落盘 `data/rate_limit.json`（只保存当前窗口内的记录，全部过期即删除该文件）。

***

## 📦 发布更新完整流程

### 发布 APK 版本更新

> 完整的发版编排见仓库根目录 `base.md` 的发版清单；可复用的自动化脚本是 `.github/scripts/release_local.sh`（构建 → ABI 纯净度校验 → 回填 `version.json` 的 `latestVersion`/`latestBuild`/`downloads`/`fileSizes`/`sha256` → 归档到 `server/public/apks/<版本号>/`），CI 侧构建走 `.github/workflows/build-apk.yml`。以下是手工等价流程。

**步骤 1：准备 APK 文件**

编译 release 版 APK，本项目按架构出 4 个包，资产命名规范为 `notice_<平台>_<版本号>.apk`（平台取 `arm64` / `arm32` / `x86` / `all`，`all` 为三架构融合包）。

**步骤 2：计算每个包的大小与 sha256**

- 大小（字节）：Linux `stat -c%s notice_arm64_1.5.74.apk`；Windows 右键 → 属性 → 大小
- 校验值（64 位小写十六进制，客户端下载后安装前比对）：`sha256sum notice_arm64_1.5.74.apk`

**步骤 3：上传安装包**

放到分发地址上，`version.json` 的 `downloads` 写什么，客户端就去哪取：

- 自托管：上传到服务器 `server/public/apks/<版本号>/`，经根路径直出 `https://你的域名/apks/<版本号>/xxx.apk`（该目录已被 `.gitignore` 忽略，只存在于服务器上，**上传部署时不得覆盖/删除**）
- 仓库归档：同步一份到 `server/public/apks/<版本号>/` 供发版脚本与本地验证使用
- 现有线上配置指向 CDN（`https://cdn2.fnthink.top/app/notice/update/<版本号>/…`），App 另有 GitHub Releases 镜像兜底（`xget.fnthink.top` / `github.com`，同一 `notice_<平台>_<版本号>.apk` 命名）

**步骤 4：更新配置**

两条等价路径：

- **管理后台**：打开 `/admin.html` → 版本管理 → 修改 `latestVersion`、`latestBuild`、`changelog`、`minSupportedVersion`、各架构 `downloads`/`fileSizes`、`forceUpdate`（及其阈值）→ 保存。表单没有 `sha256`，服务端保存时会自动沿用 `version.json` 里已有的值。
- **直接编辑文件**：改 `server/data/version.json`（含 `sha256`），保存即生效。

**步骤 5：保存，完成！**

配置文件保存后立即生效，无需重启服务（每次请求实时读取）。提交进仓库的 `version.json` 变更后，`bash .github/scripts/check_version_consistency.sh` 会校验版本号/构建号一致性与 `sha256` 字段完备性（CI 同一道闸）。

## 🔥 生产环境部署（专业运维指南）

以下是生产环境推荐的部署方式，从简单到复杂依次介绍。

### 方案〇：上传 `server/` 目录（本项目实际做法）

本服务的更新方式是**把 `server/` 目录上传到服务器覆盖代码文件**，不是 `git pull`（服务器上没有仓库）。每次上线的固定三步：

```bash
# 1) 只覆盖代码：server.js、lib/、public/、package.json、package-lock.json、*.md
#    ⚠️ 绝不带 --delete（rsync --delete / SFTP「镜像目录」都会删掉 data/ 与 .env）
rsync -av --exclude 'data/' --exclude '.env' --exclude 'node_modules/' ./server/ user@host:/opt/update-server/

# 2) 安装/更新依赖（按 lock 精确复现；不动 data/ 与 .env）
cd /opt/update-server && npm ci        # 必要时 npm rebuild

# 3) 重启进程
pm2 restart update-server && pm2 logs update-server --lines 20
```

> ⚠️ **红线复述（运维事故高发点）**
> - 上传**不得覆盖或删除** `server/data/`：`totp.json` 存的是 TOTP secret 密文 + 恢复码 bcrypt 哈希，丢了 owner 就无法通过二步验证（只能按后文重置二步验证、重新绑定认证器）；`sessions.json` / `blocked_ips.json` / `failed_attempts.json` / `rate_limit.json` 是运行期状态。仓库里的 `data/` 只有 `version.json`，用仓库那份整体覆盖会**把线上 `version.json` 一起回滚**。
> - 上传**不得覆盖** `server/.env`（真实密钥；仓库只有 `.env.example`）。
> - 上传**不得删除** `node_modules/`（除非紧接着 `npm ci`），且不要上传本地的 `node_modules/`。
> - 使用 `--delete` 的同步工具 = 删掉 `data/totp.json` = 把管理员锁在后台外。**禁止**。
> - 重启会重新加载 `data/` 下的持久化状态（会话/封锁/限流计数），已登录的会话在 24h TTL 内继续有效。

### 方案一：PM2 守护进程（推荐中小型项目）

PM2 是 Node.js 进程管理工具，可以：

- 进程守护（崩溃自动重启）
- 日志管理
- 开机自启
- 负载均衡（**本服务不可用**，见「部署边界」：状态在单进程内存）

**安装 PM2：**

```bash
npm install -g pm2
```

**启动服务：**

```bash
cd /opt/update-server   # 换成你实际放置 server 目录的路径
pm2 start server.js --name update-server
```

**常用命令：**

```bash
pm2 list                    # 查看所有进程
pm2 logs update-server      # 查看日志
pm2 restart update-server   # 重启（上传新代码后）
pm2 stop update-server      # 停止
pm2 delete update-server    # 删除进程登记
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

    # 静态文件直接由 Nginx 处理（性能更好；APK 走根路径 /apks/，旧地址 /public/apks/ 兼容）
    location /apks/ {
        alias /opt/update-server/public/apks/;
        expires 7d;  # 缓存 7 天
    }

    location /public/ {
        alias /opt/update-server/public/;
        expires 7d;
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

> ⚠️ **反代部署必须设 `TRUST_PROXY`**：`app.set('trust proxy', Number(process.env.TRUST_PROXY ?? 0))` 默认 **0 = 不信任任何代理头**（直连部署的 fail-safe 默认值）。挂在 Nginx 后面却不设置，IP 封锁与限流看到的就全是 `127.0.0.1`（代理 IP）——误封一次即全站管理接口对所有人关闭；反过来，没挂反代却设了 `TRUST_PROXY`，攻击者伪造 `X-Forwarded-For` 就能绕过封锁。
> 单层 Nginx：`TRUST_PROXY=1`；Nginx + CDN 多级：按跳数递增（如 `2`）。修改后需重启服务生效。
> 若链路上还有 Cloudflare，请把回源 IP 收敛到 CF 的 IP 段并在 Nginx 层处理，`TRUST_PROXY` 只按**你自己的**代理跳数计。

**免费 HTTPS 证书：**
推荐使用 Let's Encrypt 免费证书，配合 certbot 自动续期。证书轮换与固定策略见 `../docs/cert_rotation_runbook.md`。

***

### 方案三：Docker 部署

**创建 Dockerfile：**

```dockerfile
FROM node:24-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
EXPOSE 3456
CMD ["node", "server.js"]
```

> 基础镜像必须是 **node:24**（`engines.node = ">=24"`）。构建上下文里请排除 `.env` 与 `data/`（`.dockerignore`），密钥用 `-e`/secret 注入，配置与状态目录用挂载卷提供，避免把运行期数据烤进镜像。

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
# 反代部署时补一行（跳数按实际链路）：
# Environment=TRUST_PROXY=1

[Install]
WantedBy=multi-user.target
```

`WorkingDirectory` 下的 `.env` 会由 `dotenv` 自动加载（`server.js` 首行 `require('dotenv').config()`），密钥不必写进 unit 文件。

**启动并设置开机自启：**

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

## 🧪 本地开发与自检

`package.json` 提供的脚本（在 `server/` 目录下执行；需 Node 24）：

| 命令 | 实际执行 | 用途 |
|------|----------|------|
| `npm start` | `node server.js` | 启动服务 |
| `npm run dev` | `node server.js` | 同上（无热重载） |
| `npm test` | `jest --verbose` | HTTP 契约测试：`test/auth.test.js` 用 supertest 打真实请求，覆盖安全头、登录/注销/会话过期、版本保存链路、TOTP 全流程、恢复码并发重放、原型键伪造、2FA 连续失败触发封锁 |
| `npm run format` | `prettier --write "lib/**/*.js" server.js "test/**/*.js"` | 格式化 |
| `npm run format:check` | `prettier --check …` | 只检查不改（CI 用） |

测试用临时 `DATA_DIR`（`os.tmpdir()`）隔离，不会污染线上 `data/`；仓库根目录另有一道发版闸：`bash .github/scripts/check_version_consistency.sh`（版本号/构建号一致性 + `sha256` 字段完备性 + 官网 i18n + 词条漏翻 + 文档一致性）。

CI 侧同源：`.github/workflows/analyze.yml` 在 Node 24 上跑 `npm ci --no-audit --no-fund` + `npm test`（步骤名 `Server HTTP contract tests`），并用 `bash .github/scripts/check_format.sh` 做 dart format / ktlint / prettier 三路格式闸。

***

## ⚠️ 部署边界（仅限单实例）

**限流、会话与 IP 封锁状态以「单进程内存」为准，文件只是落盘副本**（`data/` 下的 `sessions.json` / `failed_attempts.json` / `blocked_ips.json` / `rate_limit.json`）：进程启动时读入一次，此后判定全部走内存，变更/定时再写回文件。由此带来的部署与运维约束：

- 当前实现**仅支持单实例部署**（单 Node 进程）。PM2 cluster 模式、Docker 多副本或多机负载均衡会导致各实例状态不一致：限流计数各自独立、在 A 实例登录的会话到 B 实例无效、IP 封锁状态漂移。
- **手工删 `data/blocked_ips.json` 不会立即解封**——必须重启服务（`pm2 restart update-server`）才生效，详见「IP 封锁机制」。同理，直接删 `sessions.json` 也不会让已登录会话掉线（内存仍在），重启才清。
- `blocked_ips.json` / `sessions.json` / `failed_attempts.json` 为**变更即落盘**（写后台/吊销会话/记失败时同步写文件）；`rate_limit.json` 由 60 秒定时器批量落盘（见 `server.js` 的 `setInterval`）。
- 进程被 `kill -9` 时可能丢失最后一次落盘后的少量状态（需重新登录、限流/封锁计数重置）；正常退出（SIGINT/SIGTERM/SIGHUP）会在 `onShutdown` 里把限流、会话、失败次数全部保存。
- 需要水平扩展时，必须先将状态外置到 Redis（或 SQLite），并改造 `server/lib/store.js` 为集中式存储后，再启用多副本。

***

## 🔒 安全加固建议

服务端**已经**内置下列防护（无需另做）：

- **管理接口鉴权**：`/api/admin/*` 全部走 `authMiddleware` —— bcrypt 比对 `x-admin-token`，或校验 `x-session-id` 会话；二步验证开启后额外要求该会话经 OTP 验证（否则 `401 code -2`）。会话表为 `Object.create(null)` 且经 `isValidSession()` 三重判定，`x-session-id: __proto__` 这类原型链伪造已无法绕过认证。
- **恢复码一次性**：核销在 `store.withAuthLock()` 的认证临界区内完成并在锁内重读配置，并发重放同一个恢复码只可能成功一次（契约测试有覆盖）。
- **内置限流**：每 IP 每 60 秒 60 次（`/api/admin` 另限 5 次），按路由桶计数；超限返回 `429 {code:-4, retryAfter}`。Nginx 层可再叠加一道做纵深防御，但不是唯一依赖。
- **IP 封锁**：2FA 连续失败 5 次（10 分钟窗口）封锁 1 小时；`/health` 与 `/api/version/*` 豁免，误封不影响客户端更新检查。
- **安全响应头**：全站 `nosniff` / `X-Frame-Options: DENY` / `Referrer-Policy` / HSTS（`max-age=31536000; includeSubDomains`）；`/admin.html` 另有严格 CSP（`default-src 'self'`、`frame-ancestors 'none'`，脚本外置于 `admin.js`）；`/api/admin/*` 响应 `Cache-Control: no-store`。
- **请求体大小限制**：`express.json({limit:'1mb'})`，防超大请求。
- **CORS 白名单**：默认只放行无 Origin 的请求（原生 App / curl / 同源）与 `ALLOWED_ORIGINS` 列出的来源。
- **不暴露指纹**：`app.disable('x-powered-by')`。
- **配置加密密钥**：设置 `ENCRYPTION_KEY`（64 位十六进制）加密 TOTP secret，生成方式：
  ```bash
  node -e "console.log(require('crypto').randomBytes(32).toString('hex'));"
  ```

仍需运维侧配合的：

1. **启用 HTTPS**：生产环境务必 HTTPS，防止数据篡改（App 侧 `downloads` 强制 `https://`）。
2. **纵深防御管理接口**：如管理入口固定，可在 Nginx 对 `/api/admin/` 追加 IP 白名单或 Basic Auth。
3. **静态目录权限**：确保 `public/` 只允许静态文件访问、无执行权限；`data/` 目录**不得**暴露到任何 Web 路径（当前静态映射只指向 `public/`）。
4. **定期备份**：异地备份 `data/`（尤其 `totp.json`、`version.json`）与 `.env` 里的 `ENCRYPTION_KEY`——两者必须同批备份，否则换机后 secret 解不开。
5. **使用 CDN**：大文件下载走 CDN 或对象存储，减轻源站压力。
6. **Token 安全传输**：仅通过 `x-admin-token` / `x-session-id` Header 传递，禁止 URL 参数（恢复码同理：走 `POST /api/admin/totp/rebind`，`GET /totp/setup?recoveryCode=` 已被服务端拒绝）。
7. **反代跳数正确**：`TRUST_PROXY` 必须与实际链路一致，否则封锁/限流打在代理 IP 上。

***

## 📱 客户端配置

APP 默认服务器地址：`https://notice.fnthink.top`

APP 的更新服务器地址是 `lib/update_manager.dart` 里的编译期常量 `AppUpdateManager._updateServerUrl`（当前值 `https://notice.fnthink.top`），**应用内不提供修改入口**；换地址要改代码重新出包，或走 [GitHub Pages 静态部署](GITHUB_PAGES.md)（把该常量指向 Pages 地址）。

APP 会自动拼接以下路径：

- 版本检查（API 模式）：`/api/version/check?version=…&build=…&platform=android`
- 静态回退（Pages/纯静态模式）：`/api/version.json`（原样读取 version.json 后在本地比对版本号）
- 相对下载地址：以「服务器地址 + 相对路径」解析（所以 `downloads` 写 `/apks/...` 也可用，但管理接口只接受 `https://` 绝对地址）
- 下载兜底源：CDN 失败后依次尝试 GitHub 加速镜像与官方 Releases 直链（同一 `notice_<平台>_<版本号>.apk` 命名）

**注意：** 服务端使用 HTTPS 时请确保证书有效（App 侧默认仅做标准 TLS 验证，证书固定默认关闭，见 `../docs/cert_rotation_runbook.md`）。

***

## ❓ 常见问题

### Q: 修改了 version.json 为什么客户端没生效？

A: 服务每次请求都会实时读取配置文件，修改后立即生效。如果客户端没收到更新，请检查：

1. 文件是否保存正确（JSON 能否被 `node -e "JSON.parse(require('fs').readFileSync('data/version.json','utf8'))"` 解析）
2. 客户端是否有缓存（App 每 24 小时检查一次，可强制停止 APP 再打开）
3. 请求是否到达服务端：服务本身**不打印访问日志**（未挂 morgan 等），请看 Nginx `access.log`，或 PM2/systemd 的进程日志（启动横幅、`[auth]`、`[version]` 等运行期告警都走 stdout/stderr）

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

***

## 二步验证（TOTP）

### 功能说明

- 二步验证**默认未启用**（仅管理员 Token 即可登录）；强烈建议首次登录就启用，服务本身不强制。
- 启用后每次登录必须「Token + 6 位验证码」；`authMiddleware` 会拒绝一切未过 OTP 的会话，包括开启前用纯 Token 铸造的旧会话。
- **`POST /api/admin/totp/enable` 成功时会调用 `revokeAllSessions()` 吊销全部会话**（内存 + `sessions.json`），所有人都要用 OTP 重新登录。
- 支持 Google Authenticator、Microsoft Authenticator 等标准 TOTP 应用（6 位验证码、30 秒步长）。
- 提供 **8 个恢复码**（每个 8 位十六进制字符，bcrypt 哈希存储）用于设备丢失时登录，**一次性**：用过即从集合中移除，且核销在认证临界区内完成，并发重放同一码只可能成功一次。
- 服务端对 TOTP 的时间容差为 `epochTolerance: 30` 秒（`lib/otp.js`）：手机/服务器时钟漂移过大是「验证码明明没错却失败」的首要原因。
- 10 分钟窗口内连续 5 次验证码错误 → 该 IP 封锁 1 小时（见下节）。
- 会话 TTL 固定 24 小时，不因持续使用而续期。

### 首次登录流程（启用二步验证）

1. 打开管理后台：`https://你的域名/admin.html`（同源部署时就是站点根下的 `/admin.html`）
2. 输入管理员 Token
3. 点击「首次登录 - 设置二步验证」（后台的「安全设置」标签页里也能进入）
4. 用认证器 App 扫描二维码（或复制 `manualCode` 手输 secret）
5. 输入 App 生成的 6 位验证码确认
6. **立刻保存页面展示的 8 个恢复码**（离线保存；服务端只存 bcrypt 哈希，此刻是它们唯一可见明文的时机——后续「重新生成恢复码」同样只在那一次返回明文）
7. 设置完成——注意此刻既有会话已被全部吊销，需重新以 Token + OTP 登录

### 后续登录流程

1. 输入管理员 Token
2. 输入二步验证验证码
3. 登录成功（返回 `sessionId`，后续请求以 `x-session-id` 携带）

### 使用恢复码登录

1. 输入管理员 Token
2. 点击「使用恢复码」
3. 输入之前保存的恢复码（8 位十六进制，大小写不敏感——服务端会 `trim().toUpperCase()` 归一）
4. 登录成功，该恢复码同时被核销（8 → 7）

恢复码用完后：登录后到「安全设置」执行「重新生成恢复码」（`POST /api/admin/totp/regenerate-recovery`，需当前 OTP 或一个仍有效的恢复码），会得到全新 8 个，旧的全部作废。

### 换手机（重新绑定认证器）

`POST /api/admin/totp/rebind` 提交一个恢复码（**必须走 POST body**，`GET /totp/setup?recoveryCode=` 会被服务端 `400` 拒绝，因为 query 会留在访问日志/浏览器历史），返回新 secret + 二维码；随后用新认证器生成的验证码调用 `/totp/enable` 完成替换。恢复码错误会计入 2FA 失败次数并受 IP 封锁保护。

### 禁用二步验证

在管理后台「安全设置」标签页操作，需要输入当前二步验证验证码或恢复码。注意：禁用只改 `enabled` 标记，**不吊销会话**，也不清除已核销过的恢复码集合。

### 手动重置二步验证（丢设备且无恢复码）

服务器上删除 TOTP 配置文件即可，配置是**每次请求实时读取**的，删除后立即生效（无需重启就能回到「仅 Token」登录）：

```bash
rm /opt/update-server/data/totp.json
```

若同时要踢掉所有在线会话（例如怀疑 Token 已泄露），一并删除 `sessions.json` **并重启**——会话以内存为准，只删文件不重启无效：

```bash
rm /opt/update-server/data/sessions.json
pm2 restart update-server
```

> ⚠️ 别把这条当成常规备份手段：`totp.json` 里的 secret 是用 `ENCRYPTION_KEY` 加密的，`.env` 丢了 = 密文解不开（登录会返回 500「服务端二步验证密钥配置错误」，且**不计失败次数、不封 IP**），只能删 `totp.json` 重新绑定。

---

## 🛡️ IP 封锁机制

### 安全策略

| 规则 | 配置 | 来源 |
|------|------|------|
| 最大失败次数 | 5 次 | `store.MAX_FAILED_ATTEMPTS` |
| 失败计数窗口 | 10 分钟（自首次失败起算） | `store.FAILURE_WINDOW_MINUTES` |
| 封锁时长 | 1 小时（再次触发会顺延） | `store.BLOCK_DURATION_HOURS` |
| 解封方式 | 自动到期解封（下次访问时剔除并回写文件） | `store.isIpBlocked()` |
| 应急开关 | `DISABLE_IP_BLOCKING=1` 关闭封锁（仍统计失败次数，不拦截） | `.env` |

### 触发条件

- 10 分钟窗口内累计 5 次**二步验证**失败：`POST /api/admin/login` 带错误 OTP / 恢复码，或 `POST /api/admin/totp/rebind` 的恢复码错误。
  **Token 本身错误不计入**（返回 `401 {code:-1, message:"Token 错误"}`），也不触发封锁；服务端 `ENCRYPTION_KEY` 不匹配导致的解密失败返回 500 且不计数。
- 命中封锁后返回 `403 {code:-3, blocked:true, remainingHours}`。封锁按 IP 维度作用于**除公开接口外的全部路径**：管理接口 `/api/admin/*`、管理后台页面 `/admin.html`，以及其它静态路径都会被拦。
- 公开接口豁免（`middleware.ipBlockMiddleware` 提前放行）：`/health` 与 `/api/version*` —— 因此误封不会打断存量设备的更新检查。
- 前提是 IP 取对了：反代部署必须设 `TRUST_PROXY`，否则所有请求都记在代理 IP 上，一次误封 = 所有人被拦。

### 手动解除封锁

> ⚠️ **`blocked_ips` 以内存为准、变更时才写盘（write-behind）**：进程启动后首次访问读入 `data/blocked_ips.json`，之后判定只看内存。**手工删文件不会立即解封**，必须重启服务才会重新读盘。

```bash
# 查看被封锁的 IP（仅供观察；运行期真值在进程内存里）
cat /opt/update-server/data/blocked_ips.json

# 立即解封：删除文件 + 重启（重启后内存缓存重新从文件加载 = 空）
rm /opt/update-server/data/blocked_ips.json
pm2 restart update-server
```

若只是被自己的出口 IP 误封、又不便重启，可临时设 `DISABLE_IP_BLOCKING=1` 后重启（应急用，别忘了改回来）。

---

## 📁 数据文件说明

| 文件 | 生成时机 | 权威来源 | 说明 |
|------|----------|----------|------|
| `data/version.json` | **仓库自带**（发版脚本或管理接口写入） | 磁盘（每次请求实时读） | 版本配置。改完即生效，无需重启 |
| `data/totp.json` | 首次 `/api/admin/totp/enable` | 磁盘（每次请求实时读） | `enabled` 标记 + AES-256-GCM 加密的 secret + 恢复码 bcrypt 哈希。**丢了无法找回** |
| `data/sessions.json` | 首次登录 / 每次会话变更 | **内存**（启动时读入） | 管理会话（TTL 24h）。删文件须重启才生效 |
| `data/blocked_ips.json` | 首次触发封锁 | **内存**（启动后首次访问读入，变更写回） | 被封锁 IP 列表。删文件须重启才生效 |
| `data/failed_attempts.json` | 首次 2FA 失败 | **内存**（启动时读入） | 10 分钟窗口内的失败计数 |
| `data/rate_limit.json` | 60 秒定时器落盘 | **内存**（启动时读入） | 限流计数，只保留当前窗口内的记录；全部过期时删除该文件 |

`data/` 目录不存在时由 `store.js` 自动创建（`DATA_DIR` 可改路径）；除 `version.json` 外均为运行期产物、不入库，**部署上传时必须整体避开该目录**。

---

## 📝 更新日志

### 服务端版本：1.1.1（v1.5.33 同步）

- ✅ TOTP secret 使用 AES-256-GCM 加密存储
- ✅ 恢复码使用 bcrypt 哈希存储
- ✅ 会话 ID 使用 crypto.randomUUID() 生成
- ✅ Token 仅接受 Header 传递，禁止 URL 参数
- ✅ 添加全局异步错误处理中间件
- ✅ 配置 trust proxy，使用 req.ip 获取真实 IP（默认 0 不信任代理头，反代部署需显式设 `TRUST_PROXY=1`，见 `.env.example`）
- ✅ 请求体大小限制为 1MB
- ✅ 关闭 OkHttp 自动重试，避免双重重试

### 服务端版本：1.1.0

- ✅ 添加二步验证（TOTP）功能
- ✅ 添加 IP 封锁机制（**当时**为 3 次失败 / 10 分钟窗口 / 240 小时封锁；现为 5 次 / 10 分钟 / 1 小时，以 `server/lib/store.js` 为准）
- ✅ 添加管理后台页面（`/admin.html`）
- ✅ 添加登录接口（`/api/admin/login`）
- ✅ 添加二步验证相关 API 接口
- ✅ 添加 Token 鉴权中间件
- ✅ 添加 dotenv 环境变量支持

### 服务端版本：1.0.0

- 初始版本
- 支持 APK 版本检查和下载
- 支持强制更新配置
- 提供管理 API

---

## 🧱 近期服务端加固（行为已生效，与上文各节一致）

- ✅ **Node 24 基线**：`engines.node = ">=24"`，CI 同步 Node 24。
- ✅ **代码分层**：路由/存储/中间件拆分到 `lib/`（`app.js` 组装、`store.js` 持久化、`otp.js` TOTP、`middleware.js`、`routes/`），`server.js` 只管启动与生命周期；测试直接 `require('./lib/app')` 走真实 HTTP。
- ✅ **会话安全**：会话表 `Object.create(null)` + `isValidSession()` 三重判定，堵死 `x-session-id: __proto__` 原型链伪造；2FA 开启后未过 OTP 的会话一律 `401 code -2`；`/totp/enable` 调用 `revokeAllSessions()` 吊销全部既有会话。
- ✅ **恢复码原子核销**：`store.withAuthLock()` 认证临界区内「读 → bcrypt 校验 → 核销 → 落盘」并锁内重读配置，并发重放同一码只能成功一次。
- ✅ **限流收敛为路由桶**：`api-admin` / `api` / `static` 三桶 + 20 000 条目硬上限，杜绝任意路径撑爆内存与 `rate_limit.json`。
- ✅ **IP 封锁读盘改内存为准**：`blocked_ips` 启动后首次访问载入，此后不再逐请求同步 IO（原实现在事件循环上读文件 = 自我 DoS）；副作用是手工删文件必须重启才生效。
- ✅ **版本保存白名单投影**：`POST /api/admin/version` 只落 12 个已知字段，未知字段忽略且不经公开接口回显；请求体缺省 `sha256` 时沿用既有值。
- ✅ **封锁罚不当罪修正**：5 次 / 10 分钟 / 1 小时，且 `/health`、`/api/version*` 豁免（NAT 出口误封不再影响全体设备更新）。
- ✅ **2FA 密钥误配置可诊断**：解密失败返回 500 + 明确提示，不计失败次数、不封 IP；启动横幅输出二步验证诊断与 `DISABLE_IP_BLOCKING` 状态。
- ✅ **恢复码改走 POST**：`/totp/rebind` 取代 `GET /totp/setup?recoveryCode=`（避免留在访问日志/浏览器历史）。
- ✅ Express 5 + otplib 13（插件化 crypto/base32）、`trust proxy` 默认 0 的 fail-safe 默认值。

