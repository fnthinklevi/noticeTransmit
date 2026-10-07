# 通知推送助手 - 更新服务端

版本更新服务，基于 Node.js + Express 实现。

> 💡 **不想维护服务器？** 本项目也支持 [GitHub Pages 静态部署](GITHUB_PAGES.md)，零运维、免费、自动部署。客户端自动兼容两种模式，无需改代码。

## 官方实例与自部署实例的边界（请先读这一节）

文档里出现「官方实例」与「自部署实例」是两类**不同的东西**，它们的差别不是配置项，而是承诺：

| | 官方实例 | 自部署实例（你自己运行的） |
|---|---|---|
| 是什么 | 维护者提供的默认服务地址 | 你自己放到服务器 / NAS / 家宽上的 `server/` |
| 谁维护 | 维护者 | **你自己** |
| 可用性承诺 | 按公开的运行状态说明 | **无** —— 停机、重启、证书过期都由你自己负责 |
| 支持与排障 | 维护者处理 | **不提供支持**，也不代表官方 |
| 版本升级 | 随 App 发布同步升级 | 按下面的「版本策略」自己跟 |

**具体地说，这意味着三件事：**

1. **出问题时先分清是哪一侧。** App 里能看到当前服务地址（幻念推送页 → 设置 → 服务地址）。如果你把服务地址改成了自己的实例，那么"连不上"是你那台服务器的事，本仓库的 issue 不受理。
2. **自部署实例上的一切由你承担。** 它跑的是同一份代码，但它处理的是你的数据：谁能注册、谁能往这台设备发通知、能收到什么，都由你那台实例的配置与口令决定。
3. **你选第三方实例时，正文会经过它。** 幻念推送的消息正文由你所连的那个服务器中转（这一点在应用内隐私说明里也写着）。如果你连的是官方实例，正文经维护者运营的服务中转；如果你连的是别人的实例，**对方能看到消息正文与元数据**，与配置一个 webhook 目标是同一件事。请只连你信得过的实例。

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

> ⚠️ **契约文件不在 `server/` 里，必须一起上传**：幻念推送（fnthink-v1）的公网面读的是**仓库根**的 `protocol/fnthink-v1.json`。只传 `server/` 时协议面会在启动时**降级为 503**，日志第一屏是 `[fnthink] 协议入口没有起来` 加上缺哪份文件（管理后台与升级通道不受影响）。
>
> 那个降级是**故意的**：一份读不出来的契约绝不能被当成"不限流 / 不校验"，所以宁可整段关掉。但你若指望 `/api/fnthink/*` 能用，就得把 `protocol/fnthink-v1.json` 也放到服务器上 —— **放哪由你定**，代码只按规则去找：`lib/fnthink` 往上三级再进 `protocol/`，也就是「与代码目录同级」（本地仓库里 `server/` 与 `protocol/` 正是兄弟关系）。
>
> ⚠️ **这一步容易算错，建议直接显式指定**：在 `.env` 里写 `FNTHINK_CONTRACT=<你放契约的绝对路径>/fnthink-v1.json`，部署布局怎么变都不会失效。
>
> **每次契约有改动（新增字段 / 改名）都要重传这一份**：新代码配上旧契约会在启动时直接抛（例如读不到 `limits.unauthenticatedPerMinute`），协议面照旧降级 503 —— 错误信息会点名缺哪个键。

> ⚠️ **上传红线（本项目按「上传 server 目录」部署，不是 `git pull`）**：一次上传**绝不能覆盖或删除**以下内容，丢了就要重来一遍配置甚至把管理员锁在后台外：
>
> - `server/data/` —— `totp.json`（TOTP secret + 恢复码哈希）、`sessions.json`、`blocked_ips.json`、`failed_attempts.json`、`rate_limit.json`、`version.json` 全在这里，仓库里的 `data/` 只有 `version.json`，其余是**运行期产物**；幻念推送的五张表（`fnthink_devices.json` / `fnthink_pair_requests.json` / `fnthink_endpoints.json` / `fnthink_nonces.json` / `fnthink_messages.json`）也是**身份数据**：删掉设备表每台设备都要重新登记，删掉配对表等于已建立的授权关系全丢（要重新扫码配对）；
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
| `FNTHINK_GEO_HEADER`         | `GET /api/version/region` 的**自定义地理头名**。Cloudflare 那台自带 `cf-ipcountry`，不需要设；另一台（腾讯 EdgeOne）是否回源带地理头要实测之后才填 —— 猜的头名只会让接口恒回 `source:'none'` | 未设（只读 `cf-ipcountry`） |
| `FNTHINK_EDGE`               | 边缘标识的显式标注（如 `edgeone`）。`cf-*` 在场时以请求头自证为准（回 `cloudflare`），这个值只在自证不了的时候用；两者都不满足回 `unknown` —— **不猜**「另一个域名前面一定是某家」，那正是这条接口要测的事 | 未设 |
| `FNTHINK_GEO_ECHO`           | 临时仪器：设 `1` 时该接口额外回**请求头的名字**列表（只有名字、不含值），一次 curl 就能问出链路上那层 CDN 到底带了什么头。**测完必须关掉** | 未设（关） |
| `ALLOWED_ORIGINS`            | CORS 白名单，逗号分隔；无 Origin 的请求（原生 App / curl / 同源）始终放行；`*` 恢复放行所有来源。**不设时，浏览器跨域携带 Origin 的请求会被拒绝**（同源管理后台不受影响） | 空 |
| `DATA_DIR`                   | 运行期状态目录（`version.json` / `totp.json` / `sessions.json` / …），测试隔离用 | `<server>/data` |
| `RATE_LIMIT_GENERAL_MAX`     | 全局限流：每 IP 每「路由桶」每 60 秒的最大请求数 | `60` |
| `RATE_LIMIT_AUTH_MAX`        | `/api/admin` 认证类限流：每 IP 每分钟最大请求数 | `5` |
| `RATE_LIMIT_FNTHINK_MAX`     | 公网面（`/api/fnthink/*`）**整个面**每 IP 每分钟的上限，只当洪水闸用。各端点真正的额度（按 IP 的 `register`＝30/分·3000/天；按设备地址的配对三步与 `/message`＝60/分·5000/天；`poll`/`ack` 从 `presence` 节奏推导＝14/分、无日档）全部从契约 `limits` 段读，**不在这里配** —— 想调它们改契约，改这一项只影响"一个 IP 扇出打全部端点"的兜底 | `300` |
| `FNTHINK_CONTRACT`           | 契约文件路径覆盖。默认从代码位置算：`lib/fnthink` 往上三级进 `protocol/fnthink-v1.json`（仓库里就是根目录那份）。**部署时建议显式写死一个绝对路径** —— 算出来的位置随"server 的内容放在哪一级"而变，写死最不容易错 | 自动定位 |
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
| `downloadUrl`         | string  | （旧契约兼容，仅未提供 `downloads` 时校验）单一下载地址，须为 `https://` 绝对地址 | `"https://cdn.example.com/..."` |
| `fileSize`            | number  | （旧契约兼容）文件大小（字节，非负） | `56623104`                       |

> 已废弃字段：`platform`。服务端既不读取也不接受（不在白名单内），客户端也从不消费——请勿再写入。

***

## 🔌 API 接口文档

所有端点（路由定义见 `lib/routes/version.js` 与 `lib/routes/auth.js`，后者挂载于 `/api/admin`）：

| 方法 | 路径 | 鉴权 | 说明 |
| ---- | ---- | ---- | ---- |
| `GET`  | `/api/version/check` | 公开（豁免 IP 封锁） | App 检查版本更新 |
| `GET`  | `/api/version/region` | 公开（豁免 IP 封锁） | 地理回读 `{country,source,edge}`：只报边缘看到的国家码，**选哪台由客户端判** |
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
- 现有线上配置指向 CDN（`https://cdn.example.com/app/notice/update/<版本号>/…`），App 另有 GitHub Releases 镜像兜底（`xget.example.com` / `github.com`，同一 `notice_<平台>_<版本号>.apk` 命名）

**步骤 4：更新配置**

两条等价路径：

- **管理后台**：打开 `/admin.html` → 版本管理 → 修改 `latestVersion`、`latestBuild`、`changelog`、`minSupportedVersion`、各架构 `downloads`/`fileSizes`、`forceUpdate`（及其阈值）→ 保存。表单没有 `sha256`，服务端保存时会自动沿用 `version.json` 里已有的值。
- **直接编辑文件**：改 `server/data/version.json`（含 `sha256`），保存即生效。

**步骤 5：保存，完成！**

配置文件保存后立即生效，无需重启服务（每次请求实时读取）。提交进仓库的 `version.json` 变更后，`bash .github/scripts/check_version_consistency.sh` 会校验版本号/构建号一致性与 `sha256` 字段完备性（CI 同一道闸）。

## 🔢 版本策略：跟着升，还是停在原地

**维护者只保证一件事：App 与官方实例同步升级。**

- **官方实例**：跟 App 发布同步。你把 App 升到新版，服务端一定是能配得上它的那一版，不需要你做任何事。
- **自部署实例**：**按你自己选的时候为准。** 本仓库不承诺你的实例与某个 App 版本自动对齐。

这不是"官方不管自部署"，而是这件事在技术上没法替你决定：你可能三个月没登录过那台机器。

### 怎么知道自己该升了

自部署实例上有一条**契约版本闸门**：客户端带来的契约版本，这台服务实现不了就**直接拒绝**，而不是"能解释多少算多少"——半懂不懂地解释一个新协议比直接报错危险得多。所以你会在两处看到信号：

1. App 侧：连不上，或明确提示协议不匹配。
2. 服务侧：`npm run fnthink:doctor` 的结论（下一节）。

### 怎么升

```bash
# 1) 取新的代码（server/ 与 protocol/ **都要**）
# 2) 上传 —— 上传红线见前面那一节，data/ 与 .env 绝不能被覆盖
# 3) 跑一次自检（见下一节）
npm run fnthink:doctor -- --url https://你的实例地址
```

> ⚠ **只上传 `server/` 不上传 `protocol/` 是最常见的错配。** 新代码配旧契约会在启动时抛，
> 表现是"服务起来了但推送功能全 503"。`fnthink:doctor` 报的就是这件事。

***

## 🩺 一条命令自检：`npm run fnthink:doctor`

幻念推送这一层最容易出的问题是**版本错配**——它不报"我坏了"，只表现为"连不上"。这条命令就是为了把那种模糊现象变成一句结论。

```bash
# 只查本地（不需要起服务）
npm run fnthink:doctor

# 再问一个已部署的实例，让它自己报契约版本，并与本地这份对账
npm run fnthink:doctor -- --url https://你的实例地址
```

**退出码分三档**，这是它的全部对外契约：

| 码 | 含义 | 你该做什么 |
| --- | --- | --- |
| `0` | 对得上 | 不用管 |
| `1` | **对不上** | 契约与代码不是同一代。按上面「怎么升」传新版本 |
| `2` | **没法判断** | 文件读不到、或实例连不上。这**不是**版本问题，别去换契约 |

> ⚠ 第 2 档是刻意分出来的：连不上与版本错是两件事，混成一个码时，
> 你会把它当成版本问题去反复重传契约文件，而真正的问题在网络或证书上。

它**只读不写**：不发任何会改状态的请求，也不会碰你的 `data/`。

***

## 🧭 先决定装到什么程度：两种部署形态

| 形态 | 你要做 | 你会得到 | 不做会怎样 |
| --- | --- | --- | --- |
| **A. 只装更新服务**（默认，多数人） | 按「快速开始」六步 | 官网 + 管理后台 + 版本检查 `/api/version/check` + APK 下载 | 无。`/api/fnthink/*` 一律回 **503**，启动日志有 `[fnthink] 协议入口没有起来` |
| **B. 更新服务 + 幻念推送公网面** | A 之外，再加「加装幻念推送」那一章 | 上面全部，另加 `/api/fnthink/{register,poll,ack,message,pair-arm,pair,pair-confirm}` | 无。两部分互不影响 |

> ⚠️ **形态 A 的读者**：`/api/fnthink/*` 回 503 与日志里那行 `[fnthink] 协议入口没有起来` 是**正常现象** ——
> 它说的是"你没装这一段"，不是"服务坏了"。你不必上传协议契约、也不必设 `FNTHINK_CONTRACT`。
> **不要**把契约 JSON 复制进 `server/` 目录：那是一份会被读的**真值**，复制进来之后你改仓库那份不会生效
> （协议面会安静地用着服务器上那份旧副本）。

***

## 🧩 加装幻念推送公网面（在已经跑起来的更新服务上）

这一章是**增量**的：1~3 步可以在线做完（不影响正在服务的更新通道），只有第 4 步会重启进程（1~2 秒）。

**第 1 步：把协议契约传上去。** 契约是仓库根的 `protocol/fnthink-v1.json`，它**不在 `server/` 里**。
放在哪由你定，代码只按规则找：`lib/fnthink` 往上三级进 `protocol/`（即"与代码目录同级"）。

```bash
# 例：放到与代码目录同级的 protocol/ 下（这样连 FNTHINK_CONTRACT 都不用设）
rsync -av ./protocol/fnthink-v1.json user@host:<代码目录的上一级>/protocol/
```

> ⚠️ 这个位置容易算错（取决于你把 `server/` 的内容放在哪一级）。**推荐显式指定**（下一步的 `.env`），
> 写死一个绝对路径，部署布局怎么变都不会失效。

**第 2 步：`.env` 加两行**（都可以不设，但推荐第一行）

```ini
FNTHINK_CONTRACT=<放契约的绝对路径>/fnthink-v1.json   # 显式指定契约位置
#RATE_LIMIT_FNTHINK_MAX=300                          # 公网面整面的每 IP 洪水闸，默认 300/分钟
```

**第 3 步：给推送域名加一个 server block。** 不要把推送域名塞进更新服务那个块里再改它 ——
**新增**一个块、只放两个 location，两个域名的暴露面就靠配置分开了：

```nginx
server {
    listen 443 ssl;
    server_name push.example.com push-cn.example.com;      # 按你实际的推送域名改
    ssl_certificate     /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    client_max_body_size 64k;        # 公网面自己也有 64 KiB 的协议闸；这里设得比它小会先被 Nginx 挡掉

    location /api/fnthink/ { proxy_pass http://127.0.0.1:3456; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; }
    location /health       { proxy_pass http://127.0.0.1:3456; }
    location /             { return 404; }                   # 管理后台/官网只走更新那个域名
}
```

```bash
nginx -t && systemctl reload nginx      # reload，不是 restart
```

**第 4 步：重启并核对启动横幅**

```bash
pm2 restart update-server && pm2 logs update-server --lines 40
```

期望看到（少任何一行都别往下走）：

```
协议面（fnthink-v1，公网可达）:
  POST /api/fnthink/register  - 按 IP 30/分钟 · 3000/天（身份未证明，只能按 IP）
  POST /api/fnthink/poll      - 按设备地址 14/分钟（数字从 presence 节奏推导，验签后计）
  请求体上限（公网面，取自契约 limits.requestBodyMaxBytes）：65536 字节
  突增告警：near 线 = 额度的 50%，同一主体同一结论 300s 内合并，内存环上限 200 条
    ⚠ 告警不落盘（契约 alerts.persistToDisk=false）：列表为空只代表"本进程起来以后没触发"
```

**第 5 步：验收（5 条，含"更新通道没被弄坏"的回归）**

```bash
curl -s  https://notice.example.com/health                                   # {"status":"ok",...}
curl -s "https://notice.example.com/api/version/check?version=1.5.76&build=116&platform=android"   # {"code":0,...}  ← 回归
curl -s -X POST https://push.example.com/api/fnthink/poll -H 'Content-Type: application/json' -d '{}'
#   期望 403 {"receipt":"rejected_unsigned"}；503 = 契约不可用（见下方"503 的两种原因"）；404 = server_name 漏了推送域名
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://push.example.com/api/admin/login    # 期望 404（管理面不从这里进）
curl -s -X POST https://push.example.com/api/fnthink/poll -H 'Content-Type: application/json' -d "{\"pad\":\"$(head -c 70000 /dev/zero | tr '\0' 'x')\"}"
#   期望 413 且 body 是 {}（协议形状）；若是 Nginx 的 HTML 413 ⇒ client_max_body_size 比 64 KiB 小
```

**第 6 步：不想用了怎么退。** 删掉第 3 步那个 server block、`reload`，再把契约文件移走（或删 `.env` 里那两行）后重启 ——
推送面回到"503 = 没装"，更新通道全程不受影响。

**503 的两种原因，日志点名的是不同的一句话。** 别把它们当成同一件事去修：

| 启动日志 | 原因 | 处置 |
| --- | --- | --- |
| `读不到契约文件 …` | 文件真的不在（`FNTHINK_CONTRACT` 没指对，或只上传了 `server/`） | 把仓库根 `protocol/fnthink-v1.json` 传上去，或把那个变量指向它 |
| `契约文件在、也能解析，但内容缺这台服务端要读的数` | **代码是本批、契约是上一批**（每次服务端读新增的契约键都会撞到） | 把**本批**那份契约一起上传后重启；不用管 `.env` |

两种都只降级 `/api/fnthink/*` 这一段，`/api/version` 与管理后台照常 —— 这是设计行为，不是"整台坏了"。

### 第 7 步：上线之后怎么知道"有人在被拦住"（突增告警）

限流与配额拦下一条请求之后，默认**什么都不留**：计数器在内存里，一次 429 之后没有任何一处能回答
"是谁、受哪一档管、从什么时候开始的"。而现场症状永远是"我朋友的推送进不来了"，不是"有人被限流了"。
所以这一层专门管"说出来"：

```bash
# 登录拿 sessionId（用的就是管理后台那个口令 + 二步验证；未启用 2FA 时这一步直接返回 sessionId）
SESSION=$(curl -s -X POST https://notice.example.com/api/admin/login -H 'Content-Type: application/json' \
  -d '{"token":"<管理口令>"}' | sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p')
curl -s https://notice.example.com/api/admin/fnthink/alerts -H "x-session-id: $SESSION"
```

期望输出（形状，不是内容）：

```json
{"code":0,"message":"success","data":{"generatedAt":1760000000000,"persisted":false,
 "nearQuotaRatio":0.5,"cooldownSeconds":300,"maxActiveAlerts":200,"count":1,
 "alerts":[{"subjectKind":"device","subject":"<18 位地址码>","kind":"message","window":"minute",
            "outcome":"near","count":32,"limit":60,"times":4,"firstAt":…,"lastAt":…}]}}
```

读法与三条边界：

- **两种结论**：`near` = 计数已经到达该档额度的 `nearQuotaRatio`（还没被拒，值得看一眼）；
  `denied` = 已经被 429 拒过。两者对同一主体各记一条，因为"快满了"与"正在拒人"的处置不同。
- **`persisted:false` 是关键**：告警只在当前进程内存里，**重启即空**。所以 `count:0` 的含义是
  "这个进程起来以后没触发过"，**不是**"没有异常"。这条不是疏忽：公网未认证面上每一次写盘都是一个
  请求换一次磁盘写的放大器（本仓在拒收计数那处已做过同一条取舍），而告警的用途是"现在去看一眼"，
  审计账本是另一件事。
- **`times` 而不是重复条目**：同一主体、同一档、同一结论在 `cooldownSeconds` 内合并，总数照加。
  没有这条，告警的输出速率与请求速率成正比 ⇒ 它自己就是第二种洪水。
- 反代/CDN 之后 `subjectKind:"ip"` 那批条目的 `subject` 会是代理的地址（可能成片的 CDN 段）。
  那不是告警的问题，是"源站看不到真实客户端 IP"的问题 —— 修法见下一节 Nginx 里的 XFF 两条。

阈值只有一份来源：契约 `alerts` 段（`nearQuotaRatio` / `cooldownSeconds` / `maxActiveAlerts` /
`persistToDisk`）。改环境变量不管用，改它要连同那份 JSON 一起上传。
这个口**只读**：解除冻结、吊销设备是另一组动作（见下一节），
两件事不混在一个口里 —— 误点一次"全部失效"的代价是一整个设备群失联。

### 第 8 步：看过之后要动手（运维处置口）

上面那条告警告诉你"某台设备正在被自己拦住"，接下来通常是三种处置：先冻住它、解开、或者吊销它。

```bash
# 先看现在都是什么状态（statuses 覆盖契约里的每一档，哪怕计数是 0）
curl -s https://notice.example.com/api/admin/fnthink/devices -H "x-session-id: $SESSION"

# 冻住一台（记录与公钥都留着，一条都不投，随时可解 —— 所以它不要确认）
curl -s -X POST https://notice.example.com/api/admin/fnthink/devices/freeze \
  -H "x-session-id: $SESSION" -H 'Content-Type: application/json' \
  -d '{"addressCode":"<18 位地址码>"}'

# 解开
curl -s -X POST https://notice.example.com/api/admin/fnthink/devices/resume \
  -H "x-session-id: $SESSION" -H 'Content-Type: application/json' \
  -d '{"addressCode":"<18 位地址码>"}'

# 吊销一台 / 一键全部失效：这两类必须带 confirm:true，否则 400 且表一个字节都不动
curl -s -X POST https://notice.example.com/api/admin/fnthink/devices/revoke \
  -H "x-session-id: $SESSION" -H 'Content-Type: application/json' \
  -d '{"addressCode":"<18 位地址码>","confirm":true}'
curl -s -X POST https://notice.example.com/api/admin/fnthink/devices/revoke-all \
  -H "x-session-id: $SESSION" -H 'Content-Type: application/json' -d '{"confirm":true}'
```

期望与判读：

- 每条成功都是 `{"code":0,…,"data":{"action":"…","affected":N,…}}`。**`affected` 是"被改动的台数"**，
  不是表里的台数：`revoke-all` 再按一次应当是 `affected: 0` 而 `total` 不变 —— 那才是"没有可动的了"，
  而不是"这个钮没反应"。
- 单台动作回 `data.device`，只有 `addressCode / name / status / createdAt / lastSeenAt / statusChangedAt`
  六个键。**公钥、配对口令摘要、授权表都不在这里**（地址码是公开标识，"这台设备收了谁的授权"不是）。
- 哪些动作要确认，判据是"误点之后能不能原地撤销"：`freeze / resume` 不要（随时可解、不丢数据），
  `revoke / revokeAll / rebuildInvalidation` 要（对方必须重新配对）。名单在契约 `ops.confirmationRequiredFor`。
- **吊销不删记录**（契约 `revocation.dataNeverDeletedByRevoke`）：吊销回答的是"还能不能收到我"，
  清历史是另一次显式操作。所以吊销后仍然看得见"曾经是谁"，也能重新配对回去。
- 列状态的上限取契约 `ops.listMaxRows`（请求里给更大的数会被夹住），响应里 `truncated` 会明确说
  有没有列全 —— 一份"没列全"的列表和一份"就只有这些"的列表，读起来是相反的两个结论。
- 不在表里的地址码是 404 并点名是哪台（这个口已经鉴过权，同形规则是给未认证面的）；
  地址码形状不对是 400，不会拿着一串垃圾去查表。

⚠ 这一组只在管理面。设备侧自己要的动作（重置配对口令、重建身份密钥、划掉某个发送方）走的是
设备签名的协议事件，不是这几个 HTTP 口 —— 让它们从服务端代做，等于给服务端添一把新的签名钥匙。

⚠ 设备状态的名字（可投递 / 冻结 / 吊销 / 待重建）全部来自契约 `revocation` 那四个键
（`resumableStatus` / `frozenStatus` / `revokedStatus` / `afterRebuildStatus`）。改档位名要连同契约一起改，
实现里没有一份"看不见的缺省"。

### 接入端点：这一批做到哪儿了（T38–T41）

端点是"第三方往这台实例推通知"的长期口令入口（NAS、脚本、监控平台）。把已做的和没做的分清楚，
比写一份"看起来完整"的文档有用：

| 能力 | 现在 | 差什么 |
| --- | --- | --- |
| 端点表（只存摘要、命名、所属设备、`postOnly`、IP 白名单、有界调用日志） | ✅ 已有 | — |
| 创建 / 轮换 / 吊销 / 改策略的**存储层函数**（含轮换宽限期） | ✅ 已有 | — |
| 运维看端点：`GET /api/admin/fnthink/endpoints` | ✅ 已有 | 响应里没有口令也没有摘要 |
| 运维吊销：`POST /api/admin/fnthink/endpoints/revoke`（要 `confirm`） | ✅ 已有 | — |
| 运维铸口令：`POST /api/admin/fnthink/endpoints/create` / `/rotate` / `/policy` | ✅ 已有 | — |
| 第三方能推的两条入口：`GET /api/fnthink/p/<id>/<口令>` 与 `POST /api/fnthink/p/<id>` + `Authorization: Bearer` | ✅ 已有 | — |
| 字段别名容错、按端点的配额、只产 L1、HTTPS-only、口令不进日志与 kind | ✅ 已有 | — |
| 接收端**自己**建端点的入口（App 内「我的端点」） | ⬜ 还没有 | 与设备侧客户端同批 |

所以现在的真相是：**运维能铸口令、第三方能推，但接收端还没地方自助创建**。
下面第一小节给运维，后三节给"手上已经有一条口令"的人。

#### 运维怎么铸一条口令（这三个口为什么必须存在）

收单入口挂上公网之后，如果管理面仍然只能"列"与"吊销"，那部署好的实例上就**没有任何办法铸出口令** ——
"第三方能推"会只是一句文档话。所以这一组写入口与那两条入口是同一件事的两半：

```bash
# 铸一条：owner 必须是**已经登记过**的设备地址码
curl -sS -X POST "https://push.example.com/api/admin/fnthink/endpoints/create" \
  -H "x-session-id: <会话>" -H "Content-Type: application/json" \
  -d '{"owner":"8K3FJ6QPTM9WZ4VHNS","name":"家里 NAS"}'
# → {"code":0,"data":{"action":"createEndpoint","endpoint":{...},"secret":"…","secretShownOnce":true}}
```

- ⚠ **`secret` 只在这一次响应里出现**。表里存的是摘要，列表口拿不到明文，也没有任何接口能把它再取回来
  —— 忘了就只有一条路：`/rotate` 换一把新的（旧的那把在宽限期内还能用，所以别慌，但要去第三方把那份改掉）。
  这三个口的日志留痕只打 id，不打返回体。
- 要求 owner 先登记，是因为对着一个还不存在的收件人铸入口，表现是第三方拿到 `202`、屏幕上什么都不出现，
  而消息一直排到过期 —— 那比"现在就报错"难解释得多。
- `ipAllowlist` 每一项必须是一整个 IPv4/IPv6 地址，**不收 CIDR**（`10.0.0.0/24` 会被 400 拒掉）。
  理由不在这条规则好不好写，而在写进去也白写：白名单为空才是"不限来源"，而抄错一项的表现是"口令明明对却一律 401"，
  那条与口令错同形，排查的人只会怀疑口令、不会怀疑自己抄错的那一行。
- `/rotate` **不需要** `confirm`（`/revoke` 需要）：判据是"误点能不能原地撤销" —— 轮换后旧口令在宽限期内照样能推，
  而吊销要对方重新配对。

#### 两条入口怎么选

```bash
# ① 口令在路径段里：方便抄一行 curl，代价是整条 URL 会被 access log / 浏览器历史 / 中间代理各留一份副本
curl -sS "https://push.example.com/api/fnthink/p/ep_xxxxxxxx/<口令>?title=机箱&body=温度%2063%20度"

# ② 口令在 Authorization 里（推荐）：新建端点默认 postOnly=true，①那条会被拒成 405
curl -sS -X POST "https://push.example.com/api/fnthink/p/ep_xxxxxxxx" \
  -H "Authorization: Bearer <口令>" -H "Content-Type: application/json" \
  -d '{"title":"备份","body":"第 3 盘完成了"}'
```

字段别名由契约 `fieldTolerance` 管，按顺序取**第一个非空**：标题 `title|message|text|msg`，
正文 `body|content|description`；纯空白不算非空。别名表之外的键一概不看、也不回显。
POST 正文覆盖同名的 query 参数。投递目标**不能**由请求指定：只能投到这条端点所属的那台设备。

#### 结论怎么读（这一面不是探针）

| 结论 | 含义 | 响应体 |
| --- | --- | --- |
| `202` | 已排队。回 `{messageId, action, evicted}`；`action` 是 `new` / `refreshed`（同 `dedupe` 那条还在排队 ⇒ 换正文，不新增）/ `duplicate`（已经发出去了 ⇒ 判重，一个字都不改） | 有 |
| `401` | **端点不存在 / 口令不对 / 来源 IP 不在白名单**，三者逐字节同形 | `{}` |
| `403` | 明文 http 且没开逃生阀；或超出能力边界；或端点没绑到一台合法设备 | 能力那条是 `{"receipt":"rejected_capability"}`，其余 `{}` |
| `405` | 这条端点关了 GET 形态（`postOnly`） | `{}` |
| `400` | 标题与正文都空；或超过 `maxTitleChars` / `maxBodyChars`（**不截断后收下**） | `{}` |
| `429` | 配额到顶，带 `Retry-After` | `{}` |

`401` 那三者同形是有意的 —— 能分辨就等于一台"哪些端点存在 / 哪个来源被允许"的枚举器。
所以**排查不要看响应体，看端点的调用日志**：`GET /api/admin/fnthink/endpoints` 里每条端点带
`calls`，只有 `at` / `ip` / `outcome` 三个键。`outcome` 是内部词（不进对外响应，也不在契约
`receipts` 里）：`queued`、`duplicate`、`rate_limited`、`rejected_ip`、`rejected_method`、
`rejected_capability`、`rejected_transport`、`empty_payload`、`payload_too_large`、
`unbound_endpoint`，以及口令错那一支的 `unknown_endpoint`。**日志里没有正文、没有标题、没有口令、没有路径。**

#### 配额、能力边界与明文

- 配额**按端点**计（契约 `endpoint.ingress.quota`，当前 15/分 · 500/天），且只在口令验完之后记一发。
  按 IP 计会让"一个 NAS 出口后面挂三个端点"互相挤额度；按**未验证**的 `endpointId` 计更糟 ——
  那是 DoS 转移：拿别人的端点 id 发洪水，被 429 的是那个受害者。启动横幅里这一档写作
  `按端点 15/分钟 · 500/天（口令验完后由端点收单计，不占 IP 那三档）`，它不在 `limits` 那三份名单里。
- 端点只能产 **L1 通知**：`type=action`、外部自称的 `level` 高于 L1、带 `item`（设备侧的动作钩子）
  一律 `403 + rejected_capability`，且**一条消息都不产生**。`item` 那一支值得单独说一句：
  档位裁决只在需要逐条清单的那一档才查它，所以 L1 这条路不会自动拦 —— 收下再擦掉就是静默丢，
  写集成的人会以为钩子生效了。
- HTTPS-only 默认生效，明文 http 直接被拒。本地或内网直连要显式开 `FNTHINK_ALLOW_INSECURE_ENDPOINT=1`
  —— 这个开关放在环境变量而不是契约里，因为它是**部署事实**不是协议事实。
- 口令轮换后有宽限期（`endpoint.rotation.graceSeconds`，当前 3600 秒）：旧口令在宽限期内仍能推，
  不至于"换钥匙那一刻所有集成同时 401"，从而让运维学会"先不换了"。

#### 远程控制落在哪几条路由上

远程控制**没有自己的端点** —— 现读 `server/lib/fnthink/routes.js`，它注册的是
/message、/poll、/ack、/register、/pair-arm、/pair、/pair-confirm、/pair-revoke、
/endpoint-create、/endpoint-list、/endpoint-revoke、/endpoint-rotate 这几条，加上三个接入端点入口。
指令本身是一条**签名消息**：发送方按与通知同形的信封发到 `/message`，被控设备从 `/poll` 取到、
执行后回 `/ack`。对运维来说这意味着三件事：

- **启用远程控制不需要改任何配置**。它随幻念推送公网面一起可用，关掉的办法是在**接收端设备**上
  撤销 L2/L3 授权或在服务端删掉那条配对关系（`/pair-revoke`），不是改服务端开关。
- **凭据不进服务端**。高级密钥与 TOTP 随指令走**加密正文**，服务端只在验签时用设备公钥核对签名；
  契约 `capabilities.remoteExecution.auth` 钉的是"L3 必须带其中之一"，而带没带在**设备侧**判。
  ⇒ 审计日志里永远看不到凭据，这是设计，不是遗漏。
- **审计只落元数据**（发件人地址码、类型、时间、状态），**不含指令正文**
  （契约 `privacy.auditStoresMetadataOnly = true`、`capabilities.execution.storesBody = false`）。

⚠ **第三档封顶那条要盯住**：接入端点（`/p/...` 那三条）进来的消息**最高只到 L1** ——
`type=action` 一律 `403 + rejected_capability`。所以"让 NAS/脚本顺带下发一条开灯指令"这条路
今天不通；远程控制只从**已配对的设备**发起。

***

## 🔥 生产环境部署（专业运维指南）

以下是生产环境推荐的部署方式，从简单到复杂依次介绍。

### 方案〇：上传 `server/` 目录（本项目实际做法）

本服务的更新方式是**把 `server/` 目录上传到服务器覆盖代码文件**，不是 `git pull`（服务器上没有仓库）。每次上线的固定三步：

```bash
# 1) 只覆盖代码：server.js、lib/、public/、package.json、package-lock.json、*.md
#    ⚠️ 绝不带 --delete（rsync --delete / SFTP「镜像目录」都会删掉 data/ 与 .env）
rsync -av --exclude 'data/' --exclude '.env' --exclude 'node_modules/' ./server/ user@host:/opt/update-server/
# 1b) 契约：公网面（/api/fnthink/*）读的是仓库根的 protocol/fnthink-v1.json，它**不在 server/ 里**
#     ⇒ 单独上传一次。**放哪由你定**，默认查找规则是"与代码目录同级"（lib/fnthink 往上三级
#     再进 protocol/）。
#     ⚠ 这个位置容易算错，**推荐在服务器 .env 里显式写 FNTHINK_CONTRACT**（见 .env.example）。
rsync -av ./protocol/fnthink-v1.json user@host:<放契约的目录>/
# 服务器 .env 里加一行（路径换成你实际放的位置）：
#   FNTHINK_CONTRACT=<放契约的目录>/fnthink-v1.json

# 2) 安装/更新依赖（按 lock 精确复现；不动 data/ 与 .env）
cd /opt/update-server && npm ci        # 必要时 npm rebuild

# 3) 重启进程
pm2 restart update-server && pm2 logs update-server --lines 20
```

> ⚠️ **红线复述（运维事故高发点）**
> - 上传**不得覆盖或删除** `server/data/`：`totp.json` 存的是 TOTP secret 密文 + 恢复码 bcrypt 哈希，丢了 owner 就无法通过二步验证（只能按后文重置二步验证、重新绑定认证器）；`sessions.json` / `blocked_ips.json` / `failed_attempts.json` / `rate_limit.json` 是运行期状态。仓库里的 `data/` 只有 `version.json`，用仓库那份整体覆盖会**把线上 `version.json` 一起回滚**。
> - 同上，`data/` 下那五张**幻念推送的表也是身份数据**，丢了的代价不是"重配一下"：`fnthink_devices.json`（设备地址码 → 公钥）、`fnthink_pair_requests.json`（待确认的配对请求）、`fnthink_endpoints.json`、`fnthink_nonces.json`、`fnthink_messages.json`（待投消息与正文密文）。删掉设备表 = 每台设备都要重新登记，删掉配对表 = 已建立的授权关系全没了（要重新扫码配对）。它们由 `table.js` 以 0600 原子写入，**不进仓库、不可被部署覆盖**。
> - 上传**不得覆盖** `server/.env`（真实密钥；仓库只有 `.env.example`）。
> - 上传**不得删除** `node_modules/`（除非紧接着 `npm ci`），且不要上传本地的 `node_modules/`。
> - **契约那份 JSON 要跟着代码走**：它是协议面的唯一真值（限流档位、状态码、体积上限都从它读）。忘了传的表现是 `/api/fnthink/*` 全部 503 而其余一切正常，日志里那行 `[fnthink] 协议入口没有起来` 会点名缺哪份文件或哪个键。
> - 使用 `--delete` 的同步工具 = 删掉 `data/totp.json` = 把管理员锁在后台外。**禁止**。
> - 重启会重新加载 `data/` 下的持久化状态（会话/封锁/限流计数），已登录的会话在 24h TTL 内继续有效。
>
> 重启后**核对启动横幅**：它现在逐条打印每个端点受哪一档限流（按 IP / 按设备地址 / 从 presence 推导），以及公网面的请求体上限字节数。若看到 `⚠ 请求体上限没挂上` 或 `（协议面没有起来…）`，就是上面第 1b 步没做或路径不对。

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
    # 三个域名都写在这里：notice.* 是官网/管理后台；push.* 是幻念推送的公网面
    #（契约 transport.endpoints 声明了这两个域名，App 按它们拨号 —— 漏了它们等于公网面不可达）
    server_name notice.example.com push.example.com push-cn.example.com;

    # 重定向到 HTTPS
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name notice.example.com push.example.com push-cn.example.com;

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

    # ⚠ 请求体上限：Nginx 这一层必须**不小于**服务端会收的最大 body，
    #   否则先被 Nginx 挡掉，客户端收到的是 Nginx 的 HTML 413 而不是协议/管理接口的形状。
    #   服务端两个口径：管理面（备份导入）1 MB；公网面 /api/fnthink/* 64 KiB（由应用自己按契约回 413）。
    #   默认值 1m 刚好够管理面；要动它请只往上调。
    client_max_body_size 2m;
}
```

> ⚠️ **访问日志必须给配对口令那条路径脱敏**：契约 `transport.secretPlacement = path_segment`，
> 配对口令是**路径段**（`/api/fnthink/p/<口令>`），而契约同时声明了要脱敏的前缀
> `transport.accessLogRedactPathPattern = /api/fnthink/p/`。默认的 `combined` 日志会把口令原样写进
> `access.log` —— 那是一枚一次性凭证，写进日志就等于留了一份可被翻出来的副本。最省事的做法是给
> 这个站点单独用一份 log_format（把 URI 换成脱敏后的）：
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
> 另一条路是让应用完全不把口令放在路径里 —— 那要改契约（`secretPlacement`），当前**不改**：改口令位置等于改协议。

> ⚠️ **反代部署必须设 `TRUST_PROXY`**：`app.set('trust proxy', Number(process.env.TRUST_PROXY ?? 0))` 默认 **0 = 不信任任何代理头**（直连部署的 fail-safe 默认值）。挂在 Nginx 后面却不设置，IP 封锁与限流看到的就全是 `127.0.0.1`（代理 IP）——误封一次即全站管理接口对所有人关闭；反过来，没挂反代却设了 `TRUST_PROXY`，攻击者伪造 `X-Forwarded-For` 就能绕过封锁。
> 单层 Nginx：`TRUST_PROXY=1`；Nginx + CDN 多级：按跳数递增（如 `2`）。修改后需重启服务生效。
> 若链路上还有 Cloudflare，请把回源 IP 收敛到 CF 的 IP 段并在 Nginx 层处理，`TRUST_PROXY` 只按**你自己的**代理跳数计。
> ⚠️ **不处理的表现不止是日志失真**：源站看到的对端是 CF，而 CF 会用它自己的**多个** IP 回源 ⇒ **按 IP 的限流与封锁会被打散到好几个桶里** —— 该限的限不住（实测：外网连发 31 次 `/register`，契约额度是 30/分/IP，却一次 429 都没出现）、该封的封不准。
> 修法（二选一，在源站站点/反代段里）：
> ```nginx
> proxy_set_header X-Forwarded-For $http_cf_connecting_ip;   # ① 用 CF 给的头覆盖 XFF（与 TRUST_PROXY=1 配套）
> # ② 或 http 段 set_real_ip_from <CF 各段>; real_ip_header CF-Connecting-IP; 再把 XFF 设成 $remote_addr
> ```
> 验证要**绕开 CF**：在服务器上直连上游连发 31 次，看第 31 次是不是 429（见 `server/README.md` 的部署验收一节）。

> ⚠️ **别把你已经上线的更新域名卷进来**（下文示例统一写作 `notice.example.com`）。三个域名的分工是固定的：
> `notice.example.com` = App 检查更新 / 下载 APK / 管理后台（App 里是编译期常量 `_updateServerUrl`，换地址要重新出包）；
> `push.example.com`（以及可选的第二个大陆域名）= 幻念推送的公网面（契约 `transport.endpoints` 声明，App 按它们拨号）。
> 两条链路**共用同一个 Node 进程与同一份 `data/`**，所以改这一层时守住三条：
>
> 1. **最小改动**：只在既有 server block 的 `server_name` 里加名字，或**新增**一个 server block；
>    不要重写线上那个块。改完 `nginx -t` 通过再 `systemctl reload nginx`（**reload，不是 restart**）。
> 2. **改完立刻回归验证更新通道**（它才是现在有真实用户的那条）：
>    `curl -s "https://notice.example.com/api/version/check?version=1.5.76&build=116&platform=android"`
>    仍应返回 `{"code":0,...}`；顺手看一眼 `/health`。
> 3. **流量层不会互相拖累**（这是 #130 特意做的隔离）：幻念面的洪水走独立限流桶 `api-fnthink`，
>    而全局那层对专职路径直接跳过 —— 所以 fnthink 被打满时升级通道照常，有用例钉着
>    （`server/test/fnthink-ratelimit.test.js` 里那条「fnthink 被打满之后，升级通道照常」）。
>
> 另外：如果你不想让管理后台多出一个入口域名，可以在 `push.*` 那个 server block 里**只放**
> `/api/fnthink/`、`/health` 与 `/apks/`，其余一律 `return 404;` —— 这样两个域名在配置上就彻底分开了，
> 不靠人记。


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

### 方案五：宝塔面板（BT Panel）

> 宝塔本质是「Nginx + 一堆可视化管理器」，所以**方案二（Nginx 反代）与方案一（PM2）的要点在这里全部成立**，
> 下面只写面板特有的坑。**本项目不需要 PHP / 数据库** —— 装面板时选最小组件，别被推荐清单带着装一堆。

**第 1 步：装面板 + Nginx**
从宝塔官网取**当前**安装命令（各版本会变，别抄第三方文章里的旧命令）。装完在「软件商店」确认 **Nginx** 已安装；
**PHP / MySQL / phpMyAdmin 一律不装**。

**第 2 步：Node 与进程管理器**
- 软件商店搜 `Node` → 装 **Node.js 版本管理器**（或 **PM2 管理器**）→ 安装 **24 LTS**；
- 面板点不出来时的等价做法：用面板「终端」按 NodeSource 官方说明装 Node 24，再 `npm i -g pm2`。

**第 3 步：上传代码**
- 面板方式：本地把 `server/` 打成 zip（**排除 `data/`、`.env`、`node_modules/`**）→ 「文件」上传到代码目录 → 解压覆盖。
  面板解压只覆盖同名文件、不删别的文件（比 `--delete` 安全），但**不要把本地 `data/` 与 `.env` 打进包里**。
- 终端方式：同方案〇 的两条 `rsync`（代码 + 契约）。
- **契约单独放**：`protocol/fnthink-v1.json` 放在**代码目录的同级** `protocol/`（默认位置），
  或在 `.env` 里用 `FNTHINK_CONTRACT` 指到任意绝对路径。

**第 4 步：建站 + 反向代理**
1. 网站 → 添加站点：域名 `notice.example.com`（**不要**勾建 FTP / 数据库）；
2. 该站点 → 反向代理 → 添加：目标 URL `http://127.0.0.1:3456`，发送域名 `$host`；
3. 打开站点「配置文件」核对反代段有这三行 —— 缺 `X-Forwarded-For` **必须补**，否则 `.env` 里 `TRUST_PROXY=1`
   拿不到真实 IP，限流与 IP 封锁会全部记在代理 IP 上：

   ```nginx
   proxy_set_header Host $host;
   proxy_set_header X-Real-IP $remote_addr;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   ```
4. 同一份配置文件里设 `client_max_body_size 2m;`（管理面要 ≥1 MB；公网面 64 KiB 由应用自己按契约回 413，
   这里设小了会先被 Nginx 挡掉、回的是 HTML 而不是协议形状）；
5. SSL：站点设置 → SSL → Let's Encrypt 申请（勾自动续期）。**申请完回去再看一眼第 3 步那三行** ——
   面板改 443 段时可能重排配置。

**推送域名单独建一个站点**（`push.example.com`）。这一节是反代的重点，分三步：

1. 网站 → 添加站点：域名填推送域名。**只部署一个就只写那一个**（例：`push.example.com`）；以后要加第二个域名，
   回来把它加进 `server_name` 并**重新签一张覆盖两个域名的证书**（SAN）再 `reload`。
   ⚠️ 别把还没解析、也没进证书的域名写进 `server_name`：那种配置在浏览器/客户端看来是"证书不匹配"，
   而 DNS 没解析时又完全看不出问题 —— 配置要与事实一致。**不勾** FTP / 数据库，根目录留默认（不放文件）。
2. 反向代理 → 添加**两条**（面板一次只能加一条）：

   | 名称 | 代理目录 | 目标 URL | 发送域名 |
   | --- | --- | --- | --- |
   | `fnthink` | `/api/fnthink/` | `http://127.0.0.1:3456` | `$host` |
   | `health` | `/health` | `http://127.0.0.1:3456` | `$host` |

   ⚠️ **代理目录与目标 URL 必须"成对"**：`proxy_pass` 里**只要出现 URI**（哪怕只是一个 `/`），Nginx 就会用
   它**替换** location 匹配到的那一段前缀。请求 `/api/fnthink/poll` 时：

   | 代理目录（location） | 目标 URL（proxy_pass） | 上游实际收到 | |
   | --- | --- | --- | --- |
   | `/api/fnthink/` | `http://127.0.0.1:3456`（**不写 URI**） | `/api/fnthink/poll` | ✅ 推荐 |
   | `/api/fnthink/` | `http://127.0.0.1:3456/api/fnthink/`（与前缀等长） | `/api/fnthink/poll` | ✅ |
   | `/api/fnthink/` | `http://127.0.0.1:3456/` | `/poll` | ❌ 前缀被吃 |
   | `/api/fnthink` | `http://127.0.0.1:3456/` | `//poll` | ❌ 多一个斜杠 |
   | `/api/fnthink` | `http://127.0.0.1:3456/api/fnthink/` | `/api/fnthink//poll` | ❌ 两侧不等长 |

   ⇒ **最稳的写法**：代理目录带尾斜杠 `/api/fnthink/`，目标 URL **只写到端口**（`http://127.0.0.1:3456`）。
   ⚠️ 面板输入框显示的值**不一定等于**写进配置文件的值，而且**在面板里改这个字段可能改不动**（宝塔会
   给目标 URL 补回一个 `/`：把代理目录写成带尾斜杠、或不带尾斜杠，外面看到的错法会变，但错误的根都在
   同一个斜杠上）。⇒ 改完请点 **【配置文件】核对真实的 `proxy_pass` 那一行**：正确形状是
   `proxy_pass http://127.0.0.1:3456;`（分号前没有任何路径）。若面板反复补回，就**把这两条反向代理删掉、
   直接在站点配置文件里手写 location**（本仓 README 方案二给的就是原生的那几行，`proxy_pass` 写法一致）。

   > 🔧 **宝塔生成的反代块里，要改两行**（这是它的模板，别只看面板）：
   > ```nginx
   > proxy_pass http://127.0.0.1:3456/;        # ← 删掉结尾的 `/`
   > proxy_set_header Host 127.0.0.1;          # ← 改成 $host（面板里叫"发送域名"）
   > ```
   > 第一行决定路径怎么拼（见上表），第二行决定上游看到的 Host（服务端目前不依赖它，但日志与将来
   > 按域名分流的实现会依赖；默认写成 `127.0.0.1` 是个静默的坑）。
   >
   > 🔧 **还有 location 的尾斜杠**：宝塔会把"代理目录"规范化成带尾斜杠的形式 —— 你填 `/health`，它生成的是
   > `location ^~ /health/`。对 `/api/fnthink/` 无害（本来就带），但对**单词路径**有害：`^~ /health/`
   > **不匹配裸 `/health`**，于是请求落到站点根的静态逻辑、被 **301 到 `/health/`**（若站点根下恰好有同名
   > 目录）或直接 404。想让裸路径直接通，就把那一行的尾斜杠删掉：`location ^~ /health { … }`。

   > 🔎 **识别特征（照响应一眼判死）**：
   > - **Express 的错误页**、路径不对 ⇒ **反代配错**：`Cannot POST /poll`（前缀被吃）或 `Cannot POST //poll`（多一个斜杠）；
   > - **503 + `{"error":"fnthink_protocol_unavailable"}`** ⇒ **反代已经通了**，只是**契约这一层不可用**
   >   （两种原因：文件不在，或文件在但内容是上一批、缺这台服务端要读的键 —— 启动日志那两行分别点名）
   >   （默认位置是代码目录上一级的 `protocol/`，或用 `FNTHINK_CONTRACT` 指过去）；
   > - **403 + `{"receipt":"rejected_unsigned"}`** ⇒ 协议面活着（这一步就是要的结果）。
   > ```bash
   > curl -s -X POST https://<推送域名>/api/fnthink/poll -H 'Content-Type: application/json' -d '{}'
   > # 404 <pre>Cannot POST /poll</pre> → 反代错；503 {"error":"fnthink_protocol_unavailable"} → 缺契约；
   > # 403 {"receipt":"rejected_unsigned"} → ✅
   > ```
3. 站点「配置文件」里改两处，并核对反代段：

   ```nginx
   location / { return 404; }      # ⚠ 这一行是**必须**，不是可选加固：宝塔建站默认把「网站目录」
                                   # 当静态根，而公网面站点的目录就是**代码目录** ⇒
                                   # /server.js、/lib/**、/data/totp.json、/data/sessions.json
                                   # 会变成**可直接下载**的静态文件（本仓实测过，见下）。
                                   # 换成这一行之后：其余路径一律 404，管理后台只从更新域名进，
                                   # 裸 /health 也不再被"目录补斜杠"逻辑 301。
   client_max_body_size 64k;       # 与服务端一致：公网面协议闸也是 64 KiB，
                                   # 这里设小了会先被 Nginx 挡掉、回的是 HTML 而不是协议形状
   ```

   > 🔴 **为什么这行必须**：公网面站点的"网站目录"通常指向代码目录，而代码目录里有 `server.js`、
   > `lib/**`、`data/**`。不写 `return 404` 时，Nginx 会把这些**当静态资源直出** ——
   > 实测可下载的包括 `server.js`、`lib/store.js`、`lib/routes/auth.js`、
   > **`data/totp.json`（TOTP 材料）与 `data/sessions.json`（活跃会话表）**。
   > 验证一条命令就够：
   > ```bash
   > curl -s -o /dev/null -w '%{http_code}\n' https://<推送域名>/server.js     # 必须 404
   > curl -s -o /dev/null -w '%{http_code}\n' https://<推送域名>/data/totp.json # 必须 404
   > ```
   >
   > ⚠️ **配套**：若站点配置里有 `error_page 404 /404.html;`，`return 404` 仍会正常返回 404（实测；`error_page`
   > 只把这一次响应内部改成去取 `/404.html`），但那样会多一次无意义的内部跳转、且 `/404.html` 一旦真的存在
   > 就会把站点里的那个页面端出去 —— 所以**建议把它注释掉**。若你看到的是 **500**（`rewrite or internal
   > redirection cycle`），那说明这个组合在你的 Nginx 上进了内部重定向循环，注释掉 `error_page 404` 即可。
   > 双保险（推荐）：把该站点的**网站目录**改成一个空目录，别指向代码目录 —— 这样即便 `location /`
   > 漏写，静态直出也拿不到任何源码或数据。
   >
   > 💡 **想让根路径有点内容（介绍页/跳主站）也可以，且不必放开静态目录**：用**精确匹配**单独放行根路径，
   > 其余仍然是 404：
   > ```nginx
   > location = / { return 302 https://<你的主站域名>/; }              # 想了解的人送去官网（零静态文件）
   > # 或：location = / { default_type text/plain; return 200 "fnthink push endpoint\n"; }
   > location / { return 404; }                                         # 其余一律 404（含 /index.html）
   > ```
   > `location = /` 是精确匹配、优先级最高，不会被 `location /` 抢走；`^~ /api/fnthink/` 与 `^~ /health`
   > 也照常。真要放静态介绍页，就把该站点网站目录指向**一个新的空目录**（不要是代码目录），再补
   > `location = /index.html { root <新目录>; }` —— 注意 `location = /` 里的 `index index.html` 会内部跳到
   > `/index.html`，那一条必须显式放行，否则它又落回 `location /` 变 404。

   ```nginx
   # 核对（宝塔模板有时只带前两行，缺第三行必须补 —— 否则 .env 里 TRUST_PROXY=1 拿不到真实 IP）
   proxy_set_header Host $host;
   proxy_set_header X-Real-IP $remote_addr;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   ```

> 💡 **推送面不需要配的**：WebSocket / 长连接（`/poll` 是立即返回的短请求）、任何静态目录、PHP、
> `proxy_read_timeout` 之类的调优。反代块越朴素越好。
>
> ⚠️ **反代是 HTTPS 的唯一出口**：服务端自己不判 scheme（契约里的 `transport.httpsOnly=true` 是声明，
> 服务端不读它），而它监听 `0.0.0.0` —— 所以 3456 一旦对公网开放，明文 HTTP 也能投递。这也是第 6 步
> 「只放行 80 / 443」的原因。

**配对自检（三条，能把"哪一层的 404 / 502"分开）**

```bash
# ① 直连上游（绕开 Nginx）：应 403
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:3456/api/fnthink/poll \
     -H 'Content-Type: application/json' -d '{}'
# ② 经 Nginx：也应 403
curl -sk -o /dev/null -w '%{http_code}\n' -X POST https://push.example.com/api/fnthink/poll \
     -H 'Content-Type: application/json' -d '{}'
# ③ 管理面不该从这里进：应 404
curl -sk -o /dev/null -w '%{http_code}\n' https://push.example.com/admin.html
```

① 403 而 ② 404 ⇒ 反代配错（多半是目标 URL 带了尾斜杠）；② 502 ⇒ 上游没起 / 端口不对。

**第 5 步：启动进程**
- 面板：网站 → **Node 项目** → 添加（启动文件 `server.js`、端口 `3456`、运行目录 = 代码目录、用户 `www`）；
- 等价：终端 `cd <代码目录> && pm2 start server.js --name update-server && pm2 save`；
- ⚠️ **运行目录必须是代码目录**：`.env` 是 `dotenv` 按进程工作目录读的，目录不对 ⇒ `ADMIN_TOKEN_HASH`
  读不到 ⇒ 进程启动即退出；
- 开机自启：面板 Node 项目 / PM2 管理器里勾；终端方式用 `pm2 startup`。

**第 6 步：宝塔特有的安全项（别漏）**
- **不要放行 3456 端口**：本服务监听 `0.0.0.0`，一旦在「安全」页放行，就绕过了 Nginx 的 HTTPS 与限流
  （`curl http://<你的IP>:3456/admin.html` 能直接打开管理后台）。只放行 **80 / 443**。
- 面板自身：改默认入口路径 / 端口、开二次验证。
- 备份：用「计划任务」把代码目录下的 **`data/`** 每日打包（`totp.json` 与幻念那五张表都在里面）。
  面板的「网站备份」备份的是整个站点目录，**恢复时只恢复代码、不要把 `data/` 一起恢复** ——
  那会把设备表与配对关系回滚到旧版本。

**第 7 步：验收**：同上一节的 5 条 `curl`（域名换成你的），其中「更新通道仍然正常」那条是回归项。

**排障（面板环境常见）**

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 502 Bad Gateway | Node 没起 / 端口不对 | 面板 Node 项目日志；终端 `pm2 logs update-server` |
| 站点 404 | 反代没配 / 域名没绑到该站点 | 第 4 步 |
| 进程反复重启且日志说密钥未配置 | 运行目录不对 ⇒ `.env` 没读到 | 第 5 步的 ⚠ |
| Let's Encrypt 申请失败 | 域名没解析到本机 / 80 端口被占 | 检查解析与端口 |
| 所有设备 429 | 反代后共用出口，`TRUST_PROXY` 没设 | `.env` 设 `TRUST_PROXY=1` 并重启 |

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

APP 默认服务器地址：`https://notice.example.com`

APP 的更新服务器地址是 `lib/update_manager.dart` 里的编译期常量 `AppUpdateManager._updateServerUrl`（当前值 `https://notice.example.com`），**应用内不提供修改入口**；换地址要改代码重新出包，或走 [GitHub Pages 静态部署](GITHUB_PAGES.md)（把该常量指向 Pages 地址）。

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

## 🧪 中文乱码分诊：怎么一眼分清是设备侧还是传输侧

> 本节对应客户端任务 T86。「换设备后第一条必乱码」这个报障的**前提已经被实测推翻了**，
> 这里保留的是推翻了什么、以及下一次再遇到时怎么在**一分钟内**定位到层。

### 已定位的根因：发送侧手法，不是设备

2026-10-01 三发对照读数（同一台设备、同一个接收端）：

| 发法 | 读数 |
|---|---|
| `curl -d '<中文>'`（命令行内联中文） | **乱码** |
| `curl --data-binary @<UTF-8 落盘的文件>` | 正常 |
| 请求体零非 ASCII、中文全走 `\u` 转义 | 正常 |

**「首次必坏」与设备新旧无关**，与「发的人第一次内联中文、踩了 GBK 再改文件」同形：
Windows 上 `curl.exe` 收到的 argv 按 ANSI(GBK) 编码，服务端按 UTF-8 解那些非法字节 ⇒ 替换符。
（发中文的姿势固化在内部手册 `docs/server_deploy_and_update_guide.md` §4.1。）

### 设备侧四条候选的逐条结论

报障时登记了四条设备侧候选。**没有一条能产生乱码**，逐条给结论而不是"试过就好了"：

1. **收件通知的标题兜底**（`FnthinkInboxDisplay.specFor` 里标题为空时取正文首行）——
   只改**标题取自哪一段**，一个字节都不改。它能解释"第一条看起来不一样"，**不能**解释乱码。
2. **冷启动那一轮 poll 与契约就绪的先后** —— 影响字段齐不齐（标题/正文可能缺），
   同样不改字节。字段缺失与乱码在界面上很好分：一个是空的，一个是替换符。
3. **首次建库与迁移**（`sqflite_sqlcipher`）—— 该路径上没有任何 charset 转换
   （全文件唯一命中是 `json.decode`，那是 JSON 解析，不是编码）。
4. **isolate 冷启动后第一次 MethodChannel 的编码往返** —— `StandardMessageCodec`
   两端都按 UTF-8 传，**没有 charset 协商环节**，不存在"第一次按另一种编码走"。

### 一分钟分诊

- 看见 `�` / `??` ⇒ **传输侧**：先查**发出去的那一串字节**是什么编码。
  `xxd` 看请求体；`--data-binary @文件` 重发一次就好 ⇒ 传输侧已坐实，不用动设备。
- 界面某段**内容为空 / 少字段**，但没有任何替换符 ⇒ 设备侧的时序或兜底分支，按上面第 1、2 条查。
- 要在服务端侧自查响应：`curl` 读回时**终端是 GBK 不算证据**，用 `iconv -f UTF-8` 或按字节判。

### 验收口径（光修现象不算完）

**同一台新设备上连推三条中文，第一条与第二、三条必须逐字符一致。**
不一致就是还没修好 —— 不接受"重推一次就好了"这种交法。
