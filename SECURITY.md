# 安全政策（SECURITY）

[English](SECURITY-en.md) / 中文

本文档说明通知推送助手（NoticeTransmit）的安全支持范围、漏洞报告方式与安全部署要求。

---

## 1. 支持版本

- **仅最新正式版本**接收安全修复。当前受支持版本：**v1.5.74（build 113）**。
- 更早版本（含已停止维护的版本）不再提供安全更新，请尽快升级到最新版。
- 服务端运行时的支持边界与客户端一致：`server/package.json` 的 `engines.node` 声明为
  **`>=24`**（Node.js 24 LTS）。在 EOL 的 Node 版本（18 / 20）上部署不在支持范围内——
  那意味着依赖链（Express、otplib 等）的CVE 补丁也不会再送达。

---

## 2. 如何报告漏洞

> ⚠️ **请勿在公开 Issue 中披露漏洞利用细节或 PoC**，以免被滥用。请通过以下**私密渠道**报告。

**报告渠道（任选其一）：**
- GitHub 仓库的 **Security → Report a vulnerability**（私密安全公告，推荐）；
- 或私信维护者：**j@fnthink.com**（本仓库唯一登记的联系邮箱，见 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) 的 Enforcement 一节）。

**报告中请尽量包含：**
- 漏洞类型与所在位置（文件路径 / 接口 / 模块）；
- 复现步骤（含环境、触发条件）；
- 影响范围与严重程度评估；
- 如有可能，附上修复建议。

**响应约定：**
- 目标在 **72 小时**内给出首次响应；
- 确认后协商合理的公开披露时间，遵循「负责任披露」原则；
- 未与我们约定时间前，请勿公开披露细节。

---

## 3. 安全设计概览（范围）

### 3.1 客户端（Flutter + Android）

- **通知内容仅本地处理与转发**：系统通知在设备本地完成规则匹配、关键词过滤与聚合，再按用户自行
  配置的 Webhook / SMTP 地址转发，**不上传到任何第三方服务器**。
- **不采集通讯录**：清单未申请 `READ_CONTACTS`，本项目的隐私政策也明确列为不采集项。
  短信仅在用户显式授权（`READ_SMS` / `RECEIVE_SMS`）后用于「短信验证码识别」链路。
- **本地加密存储**：推送历史与统计走 SQLCipher（`sqflite_sqlcipher`，AES-256）；
  通道凭据与敏感配置走 `flutter_secure_storage` / 原生 `SecurePrefs`
  （AndroidKeyStore 支撑的 EncryptedSharedPreferences，两侧主密钥同源）。
- **崩溃上报（腾讯 Bugly）默认关闭**：仅当用户在「更多」页主动开启后才初始化 SDK，采集最小必要信息
  （崩溃堆栈、设备型号、系统版本、应用版本、CPU 架构），可随时关闭；未开启时 SDK 不初始化、数据不出网。
- **诊断日志默认关闭**：「更多」页连点版本号 **7 次**切换（原生 `DiagLog`，状态存于
  SharedPreferences）。红线：**只记录规则名/包名/计数等轻量信息，不含通知标题与正文**。
- **Webhook 签名防伪造**（v1.5.49+）：企微/钉钉在 URL 追加 `timestamp` + `sign`，飞书在 payload 内加
  `timestamp` + `sign`（均为各平台原生 HMAC-SHA256 规则），通用 Webhook 走
  `X-Signature: sha256=<hex>` + `X-Timestamp` 头，防止推送内容被篡改或伪造。
- **Webhook 送达校验**（v1.5.49+）：解析平台返回码（企微 errcode=0、钉钉 errcode=0、飞书
  StatusCode=0、Bark code=200 等）判断真实送达结果，HTTP 2xx 但业务失败不再误报为「已发送」。
  （v1.5.69 修复：Bark 业务失败原先因响应无 `ok` 字段被恒判成功）
- **推送启停状态隔离**（v1.5.50+）：前台通知一键暂停推送时，监听继续但 webhook 发送被跳过，状态持久化到 SharedPreferences，重启后恢复。
- **证书固定框架（默认关闭）**：`CERT_PINS` + `ENABLE_CERT_PINNING`（原生 OkHttp
  CertificatePinner；Dart 侧 `pinned_http_client.dart` 经 `--dart-define` 注入）。Debug 变体恒关闭。
  启用与轮换流程见 `docs/cert_rotation_runbook.md`。

### 3.2 管理端（`server/`，Node.js 24 + Express 5）

- **登录鉴权**：管理 Token 以 bcrypt 哈希比对（`ADMIN_TOKEN_HASH`），仓库与日志中都不出现明文口令；
  支持 TOTP 二步验证（otplib v13，兼容 Google Authenticator）。
- **TOTP secret 加密存储**：AES-256-GCM，密钥来自 `ENCRYPTION_KEY`；密钥缺失或格式非法时
  明确降级为明文存储并告警（见 4.2）。
- **一次性恢复码**：启用 2FA 时生成 **8 个**恢复码（bcrypt 哈希存储），仅用于设备丢失找回；
  核销在临界区内重读配置后**一次性消费**，同一码并发重放只能成功一次；
  可通过 `POST /api/admin/totp/regenerate-recovery` 重新签发（旧码全部作废）。
- **凭据仅经 Header / POST 传输**：Token 与会话只接受 HTTP Header
  （`x-admin-token` / `x-session-id`），**禁止 URL 参数携带**；恢复码同样只走 POST body
  （`GET /api/admin/totp/setup` 检出 `recoveryCode` 查询参数会直接 400 并指引改用
  `POST /api/admin/totp/rebind`），避免留在访问日志与浏览器历史里。
- **会话安全**：会话 ID 由 `crypto.randomUUID()` 生成；固定 24 小时 TTL 且**不随使用续期**；
  `POST /api/admin/logout` 主动吊销当前会话；**启用 2FA 会吊销全部会话**
  （`revokeAllSessions`），并且 `authMiddleware` 会拒绝 2FA 开启前铸造的「仅凭 Token」会话，
  防止「事后开启 2FA」被旧会话绕过。
- **限流按路由桶计数**：每个 IP 在每类路由桶上按 60 秒窗口记账
  （`RATE_LIMIT_GENERAL_MAX` 默认 60、认证类 `RATE_LIMIT_AUTH_MAX` 默认 5），
  而不是按精确路径——否则任意 404/随机 query 都能撑大内存与落盘文件。
  表条目另有硬上限，超限先清过期。
- **IP 封锁**：**10 分钟窗口内二步验证连续失败 5 次 → 封锁该 IP 1 小时**；
  封锁状态以**内存为准**并变更即落盘（避免逐请求同步读文件把 IO 压在事件循环上）；
  公开接口（`/health`、`/api/version/*`）豁免封锁与限流，NAT 共享出口下误封不会殃及全体用户的版本检查。
  应急可用 `DISABLE_IP_BLOCKING=1` 临时只计数不封锁。
- **安全响应头**：`X-Content-Type-Options: nosniff`、`X-Frame-Options: DENY`、
  `Referrer-Policy`、`X-Permitted-Cross-Domain-Policies: none`、HSTS；管理页
  （`admin.html`）叠加严格 CSP（`script-src 'self'`、`object-src 'none'`、
  `frame-ancestors 'none'`、`form-action 'self'`），`/api/admin/*` 响应禁缓存。
- **版本配置写入是白名单投影**：`POST /api/admin/version` 只落盘 `VERSION_CONFIG_FIELDS` 中登记的键
  （`latestVersion`、`latestBuild`、`forceUpdate*`、`changelog`、`downloads`、`fileSizes`、
  `sha256`、`minSupportedVersion`，以及旧客户端兼容的 `downloadUrl` / `fileSize`），
  未登记的键一律忽略；字段级类型校验通过才写文件，各架构下载地址强制 `https://`。

---

## 4. 安全部署与运维要求

### 4.1 密钥管理（重要）

`server/.env` 存放真实密钥（`ADMIN_TOKEN_HASH` 与 `ENCRYPTION_KEY`），**请勿将其提交到仓库**（已在 `.gitignore` 中忽略，仓库仅保留 `.env.example` 占位模板）。

部署规范：

1. 真实 `.env` **不纳入版本控制**，仅本地/部署机存在，切勿提交；
2. 通过环境变量注入密钥，**切勿硬编码**到代码或配置中；`ADMIN_TOKEN_HASH` 缺失时服务直接退出，
   不会以空凭据启动（fail-closed）；
3. 建议定期轮换密钥，降低长期暴露风险；APK 签名密钥的轮换另见 4.5；
4. Android 发布签名材料同理：本地走被忽略的 `android/key.properties`，CI 只在
   `build-apk.yml` 里从 GitHub Secrets 注入，PR 门禁工作流不持有任何签名材料。

### 4.2 加密与传输

- `ENCRYPTION_KEY` 必须为 **64 位十六进制**（AES-256-GCM 需要 32 字节）。格式不合法时会被忽略，TOTP secret 将以**明文**存储，请提交前自检。
- CORS 默认**仅放行无 `Origin` 的请求**（原生 App / curl）；浏览器跨域访问 Web 后台需显式配置 `ALLOWED_ORIGINS` 白名单，**不要设为 `*`**。
- 经反向代理（如 Nginx）部署时，通过 `TRUST_PROXY` 配置代理跳数（默认 `0` = 不信任任何
  `X-Forwarded-For`）；不设则 IP 封锁与限流全部记在代理 IP 上（误伤全体用户），乱设则攻击者可伪造头绕过封锁。
- 管理接口（`/api/admin/*`）务必置于可信网络，或叠加额外访问控制（如只监听内网、加 WAF / 口令网关）。
- 服务端**仅支持单实例部署**：限流计数、会话与 IP 封锁都在进程内存里，PM2 cluster / Docker 多副本 /
  多机负载均衡会造成状态不一致（A 实例的会话到 B 实例无效、封锁漂移）。
- 运行时版本固定为 Node.js 24 LTS（`engines.node >= 24`）；CI 与生产保持一致，避免用 EOL 运行时承载鉴权链路。

### 4.3 客户端

- 发布构建已启用 R8 混淆与资源压缩（`isMinifyEnabled` / `isShrinkResources` + `proguard-rules.pro`）；请同步保管反混淆映射文件以确保崩溃日志可读。
- 通知监听、电池白名单、自启动等系统权限由用户授予；权限缺失属于功能受限，不视为安全漏洞。
- 应用只申请功能所需权限（清单内无通讯录、定位、通话记录等采集类权限；`QUERY_ALL_PACKAGES`
  仅用于「按应用过滤」的规则配置场景）。

### 4.4 安装包完整性校验 sha256（v1.5.69+）

- **传输层附加校验**：`server/data/version.json` 携带各架构安装包的 sha256（64 位小写十六进制），
  App 下载完成后、签名校验前用原生通道计算实际值比对。
- **行为约定**：不一致 → 删除安装包并阻止安装（fail-closed）；服务端数据无该字段 → 跳过
  （旧服务端兼容，签名校验可信根兜底）；校验通道异常 → 跳过。
- **定位**：签名校验是可信根（独立于分发服务器），sha256 防的是 CDN 传输损坏/途中篡改，两层互补。
- 发版工具的 `sha256` 回填由 `bash .github/scripts/release_local.sh` 自动完成，
  `bash .github/scripts/check_version_consistency.sh` 会校验四架构字段完备且格式合法。

### 4.5 APK 签名密钥与应用内更新（重要）

应用内更新以下载包的**签名证书是否与当前已安装应用一致**作为可信根
（`ApkSignatureVerifier`，fail-closed：任何解析/读取异常一律判不通过），并额外禁止版本降级
（`versionCode` 低于当前版本一律拒绝）。该可信根独立于分发服务器，可抵御服务器被入侵、镜像被投毒、CDN 被劫持等场景。

> ⚠️ **运维风险**：正因为可信根是本机签名，**更换签名密钥会导致存量用户永远无法通过
> 应用内更新升级**（新包签名必然不匹配，只能卸载重装）。
> 轮换前务必阅读 `docs/cert_rotation_runbook.md` 第 7 节，采用**多签名过渡**方案。

若因密钥泄露等原因必须立即换密钥且无法过渡，请在发布说明中明确告知用户需卸载重装。

---

## 5. 不在范围内（Out of Scope）

- 用户自行配置的第三方 Webhook / SMTP 目标的服务端安全性。
- 设备已被 root / 提权后的本地数据保护。
- 因未授予必要系统权限导致的功能失效（非安全漏洞）。
- 自部署实例的配置缺陷（把管理员 Token 设成可猜值、把 `.env` 或恢复码贴进公开渠道等）：仍欢迎报告，
  但按配置问题而非本项目漏洞评估（配置要求见 4.1）。
- 依赖项上游漏洞：请通过对应上游渠道报告，并在本项目同步升级。

---

## 6. 致谢

感谢每一位以「负责任披露」方式报告问题的安全研究者。
