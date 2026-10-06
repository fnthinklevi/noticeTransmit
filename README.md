<div align="center">

<img src="assets/app_icon.png" width="128" alt="通知推送助手">

# 通知推送助手

**[English](README-en.md) / 中文**

为 Android 设备提供**隐私优先**的通知转发与设备协同工具。三条主线：

- **通知转发** —— 监听通知栏，经 12 类 Webhook 通道 / 企业微信·飞书自建应用 / SMTP 邮件实时送达
- **幻念推送** —— 两台设备之间直接投递，无第三方账号、无平台转发，签名可验、送达可查
- **远程控制** —— 由另一台已配对设备下发，逐条授权、可撤销、有回执

[![Flutter](https://badgen.net/badge/Flutter/3.44%2B/02569B?icon=flutter)](https://flutter.dev/)
[![AGP](https://badgen.net/badge/AGP/9.3.0/3DDC84?icon=android)](https://developer.android.com/build/releases/gradle-plugin)
[![Gradle](https://badgen.net/badge/Gradle/9.5.0/02303A?icon=gradle)](https://gradle.org/)
[![Platform](https://badgen.net/badge/Platform/Android/3DDC84?icon=android)](#)
[![Version](https://badgen.net/badge/Version/1.5.76/007AFF?icon=android)](https://github.com/fnthinklevi/noticeTransmit/releases)
[![License](https://badgen.net/badge/License/Apache--2.0/green)](#许可证)

🌐 **官方网站**：[notice.fnthink.top](https://notice.fnthink.top) · [notice.fnthink.com](https://notice.fnthink.com) — 软件介绍、客户端下载与后台管理入口

🌐 **GitHub Pages**：[fnthinklevi.github.io/noticeTransmit](https://fnthinklevi.github.io/noticeTransmit/) — 零运维静态部署（自动同步版本配置）

</div>

## 目录

- [简介](#简介)
- [幻念推送](#幻念推送)
- [远程控制](#远程控制)
- [功能特性](#功能特性)
- [技术栈](#技术栈)
- [权限说明](#权限说明)
- [项目结构](#项目结构)
- [快速开始](#快速开始)
- [质量保障与 CI](#质量保障与-ci)
- [隐私说明](#隐私说明)
- [常见问题与排错](#常见问题与排错)
- [贡献](#贡献)
- [许可证](#许可证)

---

## 简介

通知推送助手是一款隐私优先的 Android 通知转发与设备协同工具（Flutter + Kotlin）。

**第一条线：通知转发。** 监听通知栏消息，通过 12 类 Webhook 通道（通用 / 企业微信 / 钉钉 / 飞书 / Telegram / Bark / Server酱 / PushPlus / ntfy / Gotify / Slack / Discord）、企业微信与飞书**自建应用**通道、或 SMTP 邮件实时推送至目标平台；桌面小部件一键启停推送。转发内容全部由用户自己配置的通道承接，开发者不经手。

**第二条线：幻念推送。** 两台设备两两配对后直接投递消息，无第三方账号、无平台转发；每条消息由发送方私钥签名、接收方验签，服务端只存投递元数据不存正文；送达状态机与投递回执让"发出去了"和"收到了"可区分。

**第三条线：远程控制。** 由已配对的另一台设备下发指令，按 L2（应用动作）/ L3（系统设置）分档逐条授权：L2 四项动作、L3 六项设置，每项单独开关、每次执行前有可撤销的延时窗口、执行结果两段回执。

全应用中英双语国际化（1251 词条 × 2 语言）。Apache License 2.0 开源，免费无广告。

---

## 幻念推送

> 完整接入与部署口径见 [docs/server_deploy_and_update_guide.md](docs/server_deploy_and_update_guide.md)；协议契约见 `protocol/fnthink-v1.json`。

### 它解决什么

通知类工具的惯例是"你把内容交给第三方平台，它替你转发"。幻念推送换一条路：**两台设备直接说话**，中间的服务端只做暂存与转发，不持有任何正文，也没有任何第三方账号体系。

- 🔑 **无账号、无第三方** —— 配对码 / 配对链接即可建立关系，每台设备有自己的地址码，不依赖任何平台账号体系
- ✍️ **签名可验** —— 每条消息由发送方 Ed25519 私钥签名，接收方验签后才投递；密钥在 AndroidKeyStore 内生成，私钥不上传
- 🗄️ **服务端不落正文** —— 服务端只保存投递所需的元数据（发件人、类型、时间、状态），不保存消息正文（契约 `privacy.serverStoresBodyPlaintext = false`）
- 🔁 **投递状态机** —— `queued → delivering → delivered → acked`，设备渲染成功后回 ack，**ack 是唯一送达依据**；失败与补发都有明确状态，不靠猜
- ↩️ **可撤销** —— 接收端撤销授权后，配对关系即刻失效，不需要等待对端下线
- 🌐 **双地域** —— 成都 `*.fnthink.com` 与洛杉矶 `*.fnthink.top` 两套服务，用户可在「更多」页选用哪一套；也支持完全自行部署
- 📨 **转发到别处** —— 收到一条幻念推送后，可按配置的**幻念通道**转发给绑定设备或一个 webhook 地址

### 能力分级

| 档位 | 含义 | 获取方式 |
|------|------|----------|
| **L1** | 消息 | 配对即有，无需逐条勾选 |
| **L2** | 应用动作 | 逐条勾选 |
| **L3** | 系统设置 | 默认全关、逐条单独开、每次执行前都有可撤销窗口 |

**授权存在被投的那台设备上**（配对时由接收端确认并写入），发送方自己的记录里没有授权可读 —— 这条不是设计偏好：收单读的就是接收端那一份。

---

## 远程控制

> 权威口径是契约 `capabilities.remoteExecution` / `.l2` / `.l3` 三段；下面是它们的散文版。

### 两档能做什么（**封闭词表**，不在表内的一律拒）

**L2 应用动作（4 项）**

| item | 动作 | 参数 |
|------|------|------|
| `listener:start` | 启动通知监听 | — |
| `listener:stop` | 停止通知监听 | — |
| `channel:toggle` | 开关某一条转发通道 | 通道标识（**必填**，不填不执行） |
| `device_state:push` | 推送整份设备状态 | — |

**L3 系统设置（6 项）**

| item | 动作 | 模式 | 落在哪 |
|------|------|------|----------|
| `notification` | 通知监听授权 | `grant` | 跳系统设置页请用户自己点 |
| `exact_alarm` | 精确闹钟 | `grant` | 跳系统设置页 |
| `battery_optimization` | 电池优化豁免 | `grant` | 跳系统设置页 |
| `autostart` | 厂商自启动 | `grant` | 按厂商分流跳各家页面（小米/魅族/华为/OPPO/vivo 各不相同） |
| `monitoring` | 本机监控开关 | `toggle` | 本机 prefs |
| `collect_inbox` | 幻念收件开关 | `toggle` | 本机 prefs |

⚠ **模式只有两种**：`grant` 是"把一项授权交给这台设备"（不可逆动作在系统那边，必须用户点）；`toggle` 是"翻这台设备自己的一项开关"。**没有第三种"静默改系统设置"** —— 原生侧至今没有这个能力，写成有就是对外承诺一件做不到的事。认不出的 item / action 一律 `reject`，绝不"认不出就先跳过"。

### 安全模型（每一格都不是装饰）

- 🔑 **凭据**：高级密钥（远程执行专用，≥ 8 字符，接收端生成、只存哈希）或 TOTP（6 位 / 30 秒，接收端生成、**不经服务器**，当面扫码交给发送端）。L2 可带可不带；**L3 必须带其一**，缺失或错误一律拒
- ⏱️ **延时窗口**：执行前默认 10 秒（0–60 可调），窗口内可经**状态栏通知**与**界面顶端横幅**两个入口取消，超时默认执行。用户在不在设备前**不影响计时** —— 这是"给用户的一次可见撤销机会"，不是"再确认一次"
- 🚫 **不许绕过**：`allowSkipConfirm: false` —— 这道窗口不能被关掉或跳过
- 🧯 **熔断**：每分钟失败 5 次自动降级到 L1
- 🔄 **幂等**：投递是 at-least-once，所以 L3 的 `toggle` 可以带目标值（`on` / `off`）—— 重投一次不会翻回去；不带的老写法仍按"读当前再翻"接收，**老对端不必升级**
- 📜 **状态机**：`pending → executing → done / failed / cancelled`，五个状态封闭；`cancelled`（你在窗口内撤销）与 `failed`（执行了没成）**刻意分开**
- 🧾 **两段回执**：收到即回 `started`、执行完回 `finished` 带结果，走**回发给发送方的消息**而不是 ack —— ack 只回答"我收到了这条投递"，回执回答"我把这件事做到哪了"，混在一起会被重投污染
- 🚫 **接入端点只到 L1**：第三方平台转发进来的消息**最高只能到 L1**；webhook 只认"幻念推送自己的 webhook"当指令源，别人的 webhook 一律不当（载荷字段是第三方随手写的，把"能发指令"挂在它身上等于把指令格式的解释权交给别人）
- 📍 **本机触发不回执**：本机白名单应用的通知触发的指令没有远端发送方可回，只进本地远程执行历史

### 凭据授权的两把钥匙不是同一把

- **设备身份私钥** —— 证明"我是这台设备"
- **远程执行高级密钥 / TOTP** —— 授权"这条远程指令"

⚠ 不再设"开启 L3 要过本机锁屏/生物认证"那一道：它在代码里**从来没接过**（全仓唯一实现永远回"这台没有认证器"），留着等于让契约宣称一个不存在的动作。L3 的安全度**只**由"对面在指令里带对凭据"承担。

---

## 功能特性

### 通知监听与识别

- 🔔 **通知监听** —— 监听系统所有应用的通知栏消息
- 📱 **多类型识别** —— 智能识别微信、QQ、短信、来电、系统通知等类型
- 📩 **短信双链路** —— `SMS_RECEIVED` 广播为主链路，短信库 ContentObserver 兜底捕获广播漏掉的短信；两条链路按内容指纹去重不会重复推送；支持自动提取验证码并以独立字段下发
- 📞 **来电识别** —— 监听来电状态并推送，正文可带"卡 1，运营商"双语信息行
- 🎚️ **卡槽过滤** —— 短信与电话链路共用卡槽过滤，单卡设备自动灰化
- 🛡️ **监听可靠性增强** —— 会话类通知正文仅存在于 MessagingStyle 时自动兜底读取；去重键含通知 tag 防误判漏读；通知使用权被系统回收时前台显示"监听已断开 · 可能漏读通知"并自动重连；**服务被回收后重启时按持久化水位自动补扫**未处理的驻留通知（最长回溯 6 小时）
- 🔋 **自定义电量提醒** —— 充电/断开/指定电量阈值等规则完全自定义，支持增删改与左滑删除
- 🌡️ **手机温度推送** —— 电池温度 / 设备整体温度 / 屏幕温度三维度独立规则，自定义阈值；30 分钟冷却防温度波动重复推送；与电量推送同源同轮询

### 转发通道族

- 🔗 **Webhook 12 类** —— 通用 / 企业微信 / 钉钉 / 飞书 / Telegram / Bark / Server酱 / PushPlus / ntfy / Gotify / Slack / Discord；可同时配置多条、每条独立开关；官方托管地址按 URL host 自动识别类型，自建 ntfy/Gotify 手动选定类型后保存/发送/测试全链路生效
- 🏢 **自建应用通道（企业微信 / 飞书）** —— 独立于 Webhook 的应用通道体系：填 corpsecret / app_secret 等凭据即可让应用自身发消息（企微可定向 touser/@all，飞书可指定 chat_id/open_id）；API 地址可改私有化部署地址；密钥加密存储，送达结果与失败重试同 Webhook 通道；**内置分步接入引导**（右上角「?」查看 corpid/AgentId/Secret 或 App ID/App Secret 的获取步骤）；**分层列表页**总览通道名称、类型与连接状态
- 📧 **SMTP 邮件推送** —— SSL / STARTTLS，可自定义主题模板与正文模板
- 📨 **幻念推送通道** —— 第四个转发族：可建多条通道，目标是一台已勾选的绑定设备或一个 webhook 地址；收到通知后自动转发（见 [幻念推送](#幻念推送)）
- 📤 **多平台适配** —— 自动适配各平台消息格式（ntfy/Gotify 支持自建服务器）
- 💚 **通道健康探测** —— 对启用通道做轻量连通探测（任何 HTTP 响应即视为连通，仅超时 / DNS 失败 / 连接拒绝判为不可达）；超过 6 小时未探测自动后台补探并持久化；通道卡片显示「✓ 连通 · 延迟 · 探测时间」徽标

### 规则与自动化

- 🧠 **规则约束** —— 可视化配置条件组合（IF）与动作（THEN），条件支持应用 / 关键词 / 通知优先级 / 时段等；动作原生真实执行：静默忽略 / 仅记录 / 延迟推送 / 立即推送
- 🧪 **规则测试器** —— 输入模拟通知，实时展示「过滤 → 规则匹配 → 最终动作」完整命中链路
- 📚 **规则模板库** —— 内置 5 套预设（验证码优先推送 / 营销广告拦截 / 夜间免打扰 / 社交消息聚合 / 白名单关键词直通）一键导入；自定义规则可存为模板；模板可导出 `.json` 分享，导出时可设口令加密（PBKDF2 210k + AES-256-GCM）
- 📦 **应用通知聚合** —— 同一应用的通知在窗口期内（默认 60 秒，最小 5 秒）合并为一条；支持「满 N 条提前推送」与「按会话分组」；模板支持 `%count%`/`%titles%` 变量；聚合期间前台实时展示待合并列表；无论成败成员内容都先完整入历史并逐条标注真实送达状态
- 🏷️ **通知优先级分级** —— 原生链路提取系统通知优先级（高/中/低），可作为规则匹配条件
- ⏰ **定时 / 延迟推送** —— 延迟秒数或定时时间 HH:mm，到点自动补推 webhook 与邮件；进程被杀或重启后任务自动恢复
- 📝 **推送模板引擎** —— 自定义消息格式（text/markdown/json/xml），变量占位符（`%appName%`/`%title%`/`%content%`），按平台自动包裹 payload 与转义，每条通道独立配置
- 📱 **应用筛选** / 🏷️ **关键词过滤** —— 白名单与黑名单，精准控制推送内容

### 历史、统计与健康

- 📋 **历史记录** —— 本地保存推送历史，支持搜索、详情查看与导出；长按快捷屏蔽（该应用 / 含此内容的通知）
- ✅ **送达状态标注** —— 首页推送记录逐条标注各通道送达状态（成功/失败/发送中/用户暂停推送），按各平台官方返回码判定；失败原因（如 HTTP 502 / 限流提示）直接内联显示
- 📈 **送达健康仪表盘** —— 各通道成功率排行（绿/橙/红分级）、失败原因 TOP（按 HTTP 状态码聚类）、24 小时高峰分布；支持近 7 天 / 30 天切换
- 📤 **失败记录批量补推** —— 筛选失败记录后多选一键重推；推送失败自动重试（网络恢复 / 服务重启时重发最近失败项）
- 🗂️ **每日自动归档** —— WorkManager 每日把前一日历史导出为 JSON（历史全量保留在库里，归档只备份不删源）；支持自定义归档目录（SAF），自定义目录场景由前台启动兜底

### 体验与界面

- 📲 **Cupertino 设计语言** —— 全应用采用 iOS 设计语言，根组件统一走 `AppRoot` 一个装配点
- 🎨 **弹窗 iOS 风格统一** —— 全部确认弹窗统一为分割线按钮布局（取消=次要色 / 确认=蓝色 / 删除=红色），深浅色自适应
- 📟 **桌面小部件** —— 2×2 / 4×2 双规格，自适应宽度布局，点击一键启停推送；显示当日推送计数（跨天自动重置）；「推送开关」页一键添加到桌面
- 📱 **桌面小组件升级** —— 布局与视觉全面美化（状态圆环 / 提示胶囊 / 当日计数），系统添加弹窗带预览与说明，不支持一键添加的桌面自动弹出分品牌分步引导；短信监听设置中心（监听开关 / 验证码开关 / 监听卡选择）
- 🖼️ **桌面图标切换** —— 内置 17 款图标 × 中英双语标签 = 34 个 launcher 图标别名，应用内一键切换
- 🌙 **深色模式** —— 浅色 / 深色 / 跟随系统三种
- 🌐 **多语言国际化** —— 中英双语（`app_zh.arb` / `app_en.arb` 各 1251 词条，gen-l10n 生成，CI 锁定两侧键集合一致），设置页自由切换；语言标签同步下发原生侧，常驻通知与推送文案随之切换
- 📄 **文本选择菜单多机型适配** —— 全部 36 处文本组件的选择菜单按钮文案（复制/剪切/粘贴/全选/分享）统一为应用内词条，消除厂商 ROM 上按钮显示英文或空白的问题
- 📊 **推送统计统一** —— 首页 / 更多页 / 状态栏三处统计共用同一数据源，当日计数实时同步
- ⏸️ **一键暂停推送** —— 常驻通知 Action 按钮暂停/恢复（监听继续，仅停止发送），状态持久化；暂停期间的消息在历史中标为"用户暂停推送"，可一键"现在推送"补推
- 🔄 **常驻通知状态机** —— 开始/停止/进程终止/自启动保活/权限缺失 5 场景统一显隐逻辑
- 🩺 **诊断日志运行时开关** —— 「更多」页连点版本号 7 次开关诊断日志（输出规则/聚合链路，不含通知标题与正文），排查无需重装
- 🔄 **在线更新** —— 系统下载器（DownloadManager）后台下载，免存储权限、锁屏不中断；多下载源自动回退（CDN / GitHub 加速镜像 / 直链，按设备架构匹配）；安装包带 sha256 完整性校验；部署模式灵活（Node.js 服务器 / GitHub Pages 静态，客户端自动兼容）

### 配置与备份

- 💾 **配置备份与恢复** —— 一键将 12 类配置（Webhook / 邮件通道含凭据 / 自建应用通道含凭据 / 通知规则 / 短信设置 / 应用过滤 / 黑白名单 / 电池规则与电量开关 / 温度规则 / 设备名 / 主题语言 / 幻念配置）加密导出为 `.nbackup`（AES-256-GCM + PBKDF2 210k 迭代口令派生，文件头自描述 KDF 参数）；换机后选文件 + 输入口令即可还原；冲突策略「覆盖全部 / 仅导入空缺项」；备份格式 v2 向后兼容 v1
- 🔐 **崩溃上报合规开关** —— 默认关闭、同意后才初始化，设置页可随时关闭；release 构建通过 R8 移除全部调试级日志

### 后台保活

- 🛡️ **后台保活** —— 前台服务 + 电量优化白名单 + 开机自启动；内置国产 ROM 保活引导（省电无限制 / 自启动 / 任务锁定，一键跳转厂商设置）
- 🔋 **兜底唤醒** —— 精确闹钟 + WorkManager 双保险，被杀后仍能按时醒来取件；重启后闹钟自动补排

### 安全加固

- 🔐 **二步验证（TOTP）** —— 管理后台登录启用，兼容 Google Authenticator
- 🔑 **bcrypt 哈希** —— Token 使用 bcrypt 哈希验证，防暴力破解
- 🛡️ **IP 封锁** —— 10 分钟内输错 5 次验证码自动封锁 IP 1 小时
- 🔢 **恢复码** —— 生成 8 个恢复码，设备丢失时可找回账户
- 🔒 **敏感数据加密** —— TOTP secret 使用 AES-256-GCM 加密存储
- 🎭 **混淆规则就绪** —— 已配置 ProGuard/R8 规则（`proguard-rules.pro`），release 启用代码混淆与资源压缩
- 📡 **Token 安全传输** —— 仅接受 Header 传递，禁止 URL 参数
- 🎲 **安全随机数** —— 使用 `crypto.randomUUID()` 生成会话 ID
- 🗄️ **SQLite 加密** —— 通知记录、通道配置与送达日志（schema v20，16 张表）全部经 SQLCipher AES-256 加密，密钥由 flutter_secure_storage 托管于 AndroidKeyStore
- 🔑 **Webhook 密钥安全** —— Webhook URL（含钉钉/企微/飞书认证 key）使用 AndroidKeyStore 加密存储
- 🔐 **SSL 证书固定** —— 双端 HTTP 客户端（Dart `PinnedHttpClient` + Kotlin `NetworkClient` 的 OkHttp `CertificatePinner`）均已就位，**默认未启用**（须注入 `CERT_PINS` / `ENABLE_CERT_PINNING`，Debug 构建恒关闭），当前通过 CDN 间接保护；轮换与启用流程见 [docs/cert_rotation_runbook.md](docs/cert_rotation_runbook.md)
- 🧩 **小部件广播防护** —— 桌面小部件的启停广播受签名级自定义权限 `com.fnthink.notice.permission.WIDGET_CONTROL` 保护，第三方应用因签名不匹配无法伪造 `TOGGLE_PUSH`
- 🔒 **HTTPS 强制** —— `network_security_config.xml` 禁止明文传输
- 🔒 **完整隐私政策** —— 应用内置 11 章节隐私政策，首次启动弹窗征得同意，可随时在「更多」页查看

---

## 技术栈

| 模块 | 技术 |
|------|------|
| 前端 | Flutter 3.44.x（Dart 3.12.2） |
| 状态管理 / 依赖注入 | get_it (^9.2.1) + Service 类 |
| 本地数据库 | sqflite_sqlcipher (^3.4.0) · SQLCipher AES-256 · schema v20 / 16 张表 |
| 键值存储 | shared_preferences · flutter_secure_storage (^9.2.4) + androidx.security EncryptedSharedPreferences |
| 原生服务 | Kotlin 2.3.20（Android），主源码 78 个 Kotlin 文件 |
| 网络请求 | http（Dart） / OkHttp 4.12.0（Kotlin） |
| 邮件发送 | com.sun.mail:android-mail 1.6.7（SMTP） |
| 通知监听 | NotificationListenerService |
| 后台保活 | Foreground Service + WakeLock (PARTIAL_WAKE_LOCK) |
| 后台任务 | workmanager ^0.6.0（每日归档 + 兜底唤醒） |
| 协程 | kotlinx.coroutines（SupervisorJob + Dispatchers.IO） |
| 跨端通信 | MethodChannel `com.fnthink.notice/notification`（113 个方法 · 7 个原生 handler） |
| **协议契约** | `protocol/fnthink-v1.json`（单一真值）＋ `protocol/fnthink-vectors-v1.json`（跨端向量表） |
| **共享协议包** | `packages/fnthink_push`（24 个 Dart 文件，两端与 CLI 共读同一份契约与向量） |
| **身份与签名** | Ed25519（AndroidKeyStore 硬件背书，API 33+；30–32 走 KeyStore 包裹软件密钥） |
| 国际化 | gen-l10n + ARB（zh / en 各 1251 词条） |
| 崩溃统计 | 腾讯 Bugly 4.1.9.3（默认关闭） |
| 服务端 | Node.js 24 LTS（`engines: >=24`）+ Express 5.x（Token 鉴权 + 二步验证 + 幻念协议面）/ GitHub Pages 静态部署 |
| 服务端依赖 | bcryptjs · cors · dotenv · express · otplib · qrcode |
| TOTP / 密码哈希 | otplib (^13.0.1) / bcryptjs (^2.4.3) |
| 数据加密 | Node.js crypto（AES-256-GCM）/ AndroidKeyStore + flutter_secure_storage |
| 构建工具 | Gradle 9.5.0 + AGP 9.3.0 + JDK 21 · minSdk 24 / compileSdk 37 / targetSdk 37 |
| 代码质量 | flutter_lints ^6.0.0 · dart format · ktlint 1.8.0 · prettier 3.9.8 · Android lint（含 baseline） |
| 测试 | flutter test（Dart 2063 例）· JUnit（Kotlin JVM 478 例）· jest + supertest（服务端 599 例）· integration_test |
| CI/CD | GitHub Actions（analyze / build-apk / integration_test / deploy-pages） |
| APK 签名 | Gradle signingConfig：V1+V2+V3 全开，密钥仅由环境变量或 `android/key.properties` 注入 |

---

## 权限说明

| 权限 | 用途 |
|------|------|
| `BIND_NOTIFICATION_LISTENER_SERVICE`（服务权限） | 监听系统通知 |
| `INTERNET` / `ACCESS_NETWORK_STATE` | 发送推送请求、网络恢复判定 |
| `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_DATA_SYNC` / `FOREGROUND_SERVICE_SPECIAL_USE` | 前台服务保活（Android 14+ 按类型细分） |
| `WAKE_LOCK` | 监听/推送期间的 PARTIAL_WAKE_LOCK |
| `VIBRATE` | 通知振动反馈 |
| `RECEIVE_BOOT_COMPLETED` | 开机自启动 |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | 电量优化白名单 |
| `POST_NOTIFICATIONS` / `POST_PROMOTED_NOTIFICATIONS` | Android 13+ 常驻通知与提升型通知 |
| `SCHEDULE_EXACT_ALARM` | 延迟/定时推送准时触发（未授予时降级为非精确闹钟） |
| `RECEIVE_SMS` / `READ_SMS` | 短信广播 + 短信库双链路监听、验证码提取 |
| `READ_PHONE_STATE` | 来电状态识别与推送 |
| `QUERY_ALL_PACKAGES` | 已安装应用列表（应用筛选 / 规则适用应用） |
| `REQUEST_INSTALL_PACKAGES` | 应用内更新的安装确认 |
| `READ_EXTERNAL_STORAGE`（≤ API 32）/ `WRITE_EXTERNAL_STORAGE`（≤ API 28） | 旧机型的归档/导出目录读写 |
| `com.fnthink.notice.permission.WIDGET_CONTROL`（signature，自定义） | 小部件启停广播防护，防第三方伪造 |

---

## 项目结构

```
noticeTransmit/
├── lib/                                  # Flutter 端（150 个 Dart 文件）
│   ├── main.dart                         # 主入口（初始化顺序 + WorkManager 注册）
│   ├── update_manager.dart               # 应用内更新（多源回退 + sha256 校验）
│   ├── database/database_helper.dart     # SQLCipher schema v20（16 张表）
│   ├── di/service_locator.dart           # get_it 服务注册
│   ├── l10n/arb/                         # app_zh.arb · app_en.arb（各 1251 词条 + 生成代码）
│   ├── models/                           # 数据模型（10 个文件）
│   ├── pages/                            # 页面（40 个文件）
│   │   ├── main_page*.dart               # 首页（actions / dialogs / update 同前缀拆分）
│   │   ├── fnthink_push_page.dart · fnthink_channel_list_page.dart · fnthink_receive_page.dart
│   │   │                                 # 幻念推送：开关 / 通道 / 收货（远程控制指令从这一档进）
│   │   ├── history_page.dart             # 历史记录（搜索 / 导出 / 批量补推 / 方向筛选）
│   │   ├── stats_page.dart               # 统计 + 送达健康仪表盘
│   │   ├── webhook_settings_page.dart · email_settings_page.dart · app_channel_*_page.dart
│   │   ├── rule_list_page.dart · rule_edit_page.dart · rule_tester_page.dart
│   │   ├── battery_page.dart · temperature_page.dart · device_state_page.dart
│   │   ├── sms_monitor_settings_page.dart · app_filter_page.dart · keywords_page.dart
│   │   └── backup_restore_page.dart · permission_settings_page.dart · privacy_policy_page.dart · more_page.dart
│   ├── services/                         # 服务层（69 个文件）
│   │   ├── platform_channel.dart         # MethodChannel 统一声明
│   │   ├── fnthink_receive_coordinator.dart  # 幻念协调者（发货 / 收货 / 轮询 / 记录）
│   │   ├── fnthink_channel_mirror.dart   # 幻念通道配置的跨端镜像（原生读它参与主备路由）
│   │   ├── fnthink_fanout_entrypoint.dart# 收到通知后转发的后台入口
│   │   ├── fnthink_l2_actions.dart · fnthink_l3_executor.dart  # 远程控制执行器
│   │   ├── notification_service.dart · webhook_service.dart · app_channel_service.dart
│   │   ├── filter_service.dart · rule_template_service.dart · rule_trace.dart
│   │   └── archive_worker.dart · pinned_http_client.dart · secure_storage_service.dart · icon_service.dart …
│   ├── theme/                            # 主题（app_colors.dart / app_theme.dart）
│   └── widgets/                          # 可复用组件（21 个：AppRoot 装配点 + iOS 弹层族 + 选择菜单）
├── packages/fnthink_push/                # 共享协议包（24 个 Dart 文件）
│   └── lib/src/                          # 契约读取 / 校验 / 向量，两端与 CLI 共读
├── protocol/                             # 协议契约（单一真值）
│   ├── fnthink-v1.json                   # 幻念协议（能力表、限流、私信边界…）
│   └── fnthink-vectors-v1.json           # 跨端向量表（两端各断言一遍）
├── android/app/src/
│   ├── main/kotlin/com/fnthink/notice/   # 原生主源码（78 个 Kotlin 文件）
│   │   ├── MainActivity.kt               # MethodChannel 分发入口
│   │   ├── NotificationMonitorService.kt  # 通知监听服务（含幻念族的主备路由与转发）
│   │   ├── NotificationProcessor.kt · BatteryMonitor.kt
│   │   ├── FnthinkIdentityCodec.kt       # 身份策略（原生 / KeyStore 包裹两条路径）
│   │   ├── FnthinkFanoutQueue.kt · FnthinkFanoutWorker.kt   # 收到通知后的转发队列 + 后台引擎
│   │   ├── FnthinkPresenceAlarm.kt · FnthinkPresenceWorker.kt # 兜底唤醒（闹钟 + 一次性任务）
│   │   ├── RuleEngine.kt · FilterEngine.kt · TemplateEngine.kt
│   │   ├── RetryQueue.kt · DelayedPushManager.kt · MergePushManager.kt
│   │   ├── ConfigManager.kt · SecurePrefs.kt · NetworkClient.kt
│   │   └── channels/                     # 7 个 handler（配置 34 / 权限 26 / 设备 15 / 文件 13
│   │                                     #   / 幻念 11 / 统计 9 / 远程执行 5 ＝ 113 个方法）
│   ├── test/                             # Kotlin JVM 单测（55 个测试类 / 478 用例）
│   └── androidTest/                      # 仪器测试（6 个文件）
├── server/                               # 服务端（更新服务 + TOTP 后台 + 幻念协议面）
│   ├── server.js · lib/                  # 入口 + 模块化分层（29 个 JS）
│   ├── lib/fnthink/                     # 幻念协议面（配对 / 投递 / 能力 / 端点 / 运维 …）
│   ├── test/                            # jest + supertest 契约测试（34 个文件 / 599 例）
│   ├── public/                          # 官网与 GitHub Pages 静态站点
│   ├── data/version.json                # 版本信息（版本/构建号/sha256/多架构下载地址）
│   └── README.md · GITHUB_PAGES.md       # 部署文档（中英各一份）
├── test/                                # Dart 测试（170 个文件 / 2063 用例）
├── integration_test/                    # 设备侧冒烟（5 个文件，含发版闸门）
├── docs/                                # roadmap.md · server_deploy_and_update_guide.md · cert_rotation_runbook.md
├── .github/                             # workflows/（CI）与 scripts/（格式、版本一致性、本地发版）
├── assets/                              # 图标资源
├── pubspec.yaml                         # version: 1.5.76+116
└── README.md
```

---

## 快速开始

### 环境要求

> **重要提示**：本项目使用 **AGP 9.3.0** + **Gradle 9.5.0**，对 Flutter / Dart / Android Studio 版本有最低要求。

| 工具 | 最低版本 | 推荐版本 | 说明 |
|------|----------|----------|------|
| **Flutter SDK** | 3.44.0 | 3.44.x stable | AGP 9.x 支持从 Flutter 3.44 开始（CI 固定 3.44.4） |
| **Dart SDK** | 3.12.2 | 3.12.x | `pubspec.yaml` 声明 `sdk: ^3.12.2`，随 Flutter 3.44 自带 |
| **Android Gradle Plugin (AGP)** | 9.0.0 | 9.3.0 | 项目已配置 |
| **Gradle** | 9.5.0 | 9.5.0 | 项目已配置（gradle-wrapper.properties） |
| **Kotlin** | 2.3.20 | 2.3.20 | 通过 `settings.gradle.kts` 显式声明插件版本 |
| **Android Studio** | Koala (2024.1.1) | 最新稳定版 | 需支持 AGP 9.x |
| **JDK** | 21 | 21+ | AGP 9.x 要求 JDK 21 及以上（`compileOptions` / `jvmTarget` 均为 21） |
| **Android SDK** | 24 (minSdk) | 37 (compileSdk / targetSdk) | minSdk 24，compileSdk 与 targetSdk 均为 37 |
| **Node.js**（仅服务端） | 24 | 24 LTS | `server/package.json` 声明 `engines.node >= 24`，CI 与生产同版本 |

#### 版本兼容性说明

- **Flutter 3.44 以下版本**：不支持 AGP 9.x，构建会失败。请先执行 `flutter upgrade` 升级到 3.44+。
- **AGP 8.x 及以下**：本项目已迁移到 AGP 9.x，无法降级使用。
- **Kotlin**：项目通过 `settings.gradle.kts` 显式声明 `org.jetbrains.kotlin.android` 版本 2.3.20，并在 `gradle.properties` 中保留 `android.builtInKotlin=false`、`android.newDsl=false`。

### 构建 APK

```bash
flutter pub get        # 安装依赖
flutter analyze       # 代码检查
flutter build apk --release --target-platform android-arm64
```

### 运行测试与质量校验

```bash
# Dart 单元测试（170 个文件 / 2063 用例）
flutter test

# 嵌套协议包单测（在包目录里跑）
cd packages/fnthink_push && dart test && cd ../..

# Kotlin JVM 单元测试（55 个测试类 / 478 用例）
cd android && ./gradlew :app:testDebugUnitTest

# Android lint（error 即失败，已知误报由 android/app/lint-baseline.xml 兜住）
cd android && ./gradlew :app:lintDebug

# 服务端契约测试（599 例，需 Node.js 24 LTS）
cd server && npm ci && npm test

# 三路格式校验（dart format + ktlint 1.8.0 + prettier 3.9.8；加 --fix 就地格式化）
bash .github/scripts/check_format.sh

# 版本与文档一致性闸门
bash .github/scripts/check_version_consistency.sh

# 设备侧冒烟测试（需连接真机或模拟器；CI 见 integration_test.yml）
flutter test integration_test/smoke_test.dart
```

### 部署服务端

支持两种部署模式，客户端自动兼容、无需改代码：

- **Node.js 服务器**（完整功能）—— [server/README.md](server/README.md) · [English](server/README-en.md)
- **GitHub Pages**（零运维静态部署）—— [server/GITHUB_PAGES.md](server/GITHUB_PAGES.md) · [English](server/GITHUB_PAGES-en.md)

幻念推送的部署口径（含双地域、契约文件上传位置、反代与 `TRUST_PROXY`）见 [docs/server_deploy_and_update_guide.md](docs/server_deploy_and_update_guide.md)。

---

## 质量保障与 CI

**测试规模**（均为可执行用例；除设备侧测试外，其余全部纳入 CI 门禁强制执行）：

- **Dart 单元测试** —— 170 个测试文件 / 2063 用例（`test/`）：架构契约（启动顺序、launcher manifest、跨端通道方法齐平、幻念镜像键名守卫）、数据库 schema 与迁移、备份/送达/过滤黄金用例、页面 widget 测试
- **共享协议包测试** —— `packages/fnthink_push`：契约校验与向量断言，两端各跑一遍
- **Kotlin JVM 单元测试** —— 55 个测试类 / 478 用例（`android/app/src/test/`）：双端规则匹配一致性由 `rule_engine_golden.json` 51 条黄金用例锁定，通道行为由 `channel_behavior_golden.json` 逐字节快照锁定
- **服务端契约测试** —— 599 例（`server/test/`，jest + supertest）：登录 / TOTP 启用与恢复码消费 / 会话失效 / IP 封锁，以及幻念协议面七条路由
- **设备侧测试** —— `integration_test/smoke_test.dart` 主链路冒烟（启动 → 注入 → 通知页 → 送达状态 → 历史 → 服务启停 → 导出），加 `android/app/src/androidTest` 仪器测试，由 `integration_test.yml` 在 API 34 / x86_64 / Pixel 6 模拟器上触发

**CI 工作流**（`.github/workflows/`，均运行于 `ubuntu-24.04`）：

- **`analyze.yml`（PR 门禁）** —— `flutter analyze --fatal-infos`（按退出码判红）→ 版本一致性 → 发版闸门行为测试 → Dart 单测 → 嵌套包单测 → Android JVM 单测 → Android lint → 服务端契约测试 → 三路格式校验 → 覆盖率产物
- **`build-apk.yml`（`v*` tag 或手动触发）** —— 前置测试与 analyze → arm64 release 打包 → ABI 纯净度与版本号双闸 → GitHub Release
- **`integration_test.yml`（每周二 03:00 UTC + 手动触发）** —— 模拟器冒烟测试 + 仪器测试
- **`deploy-pages.yml`（`server/public/**` 或 `server/data/version.json` 变更 / 手动触发）** —— 零运维静态版本源发布
- **格式统一** —— `.github/scripts/check_format.sh` 本地与 CI 跑同一支：`dart format` + ktlint 1.8.0 + prettier 3.9.8
- **版本一致性闸门** —— `.github/scripts/check_version_consistency.sh` 比对 `pubspec.yaml` / `update_manager.dart` / `MainActivity.kt` / `server/data/version.json` 四处版本与 build 号，并校验 `version.json` 的 sha256 字段完备性、官网 i18n 覆盖、README 依赖标注与 zh/en ARB 键集合一致
- **本地发版预检** —— `.github/scripts/release_local.sh <A.B.C>`：版本一致性 → format/analyze → 4 个架构 APK 构建与纯净度验证 → version.json 的 fileSize/sha256 回填 → 徽章与 update.md 缺项检查

---

## 隐私说明

### 三条主线各自的数据边界

| 主线 | 内容去哪 | 服务端是否落正文 |
|------|----------|------------------|
| **通知转发**（Webhook / 自建应用 / SMTP 邮件） | 用户自己配置的通道，直连目标 | 不经本项目任何服务器 |
| **幻念推送**（含转发到设备或 webhook） | 用户选定的那台幻念服务器（官方实例或自部署） | **否** —— 只存投递元数据，不存正文（契约 `privacy.serverStoresBodyPlaintext = false`） |
| **远程控制** | 同上 | **否** —— 指令正文加密传输，凭据与指令内容均不进审计 |

⚠ **必须说清的一句**：幻念推送与远程控制会把内容发往**你选择的那台服务器**（官方实例或你自部署的那台）。这不是"数据零上传"—— 通知转发那条线才是零上传。区别在于**那台服务器由谁运行**：官方实例由我们运行，自部署则完全在你自己的基础设施内，两种形态下服务端都不保存明文正文。

### 数据采集声明

| 数据类型 | 是否采集 | 说明 |
|----------|----------|------|
| **通知内容** | ⚠️ 取决于你启用的通道 | 经通道族与幻念通道**发往你指定的目标**，开发者不经手、不落库；幻念链路服务端只存元数据 |
| **通讯录 / 短信** | ❌ 不上传 | 仅本地监听用于推送 |
| **设备标识** | ⚠️ 仅崩溃上报开启时 | Bugly SDK 用于设备去重统计；崩溃上报默认关闭 |
| **崩溃信息** | ⚠️ 仅崩溃上报开启时 | 用户主动开启后才通过 Bugly 收集崩溃堆栈 |
| **幻念投递元数据** | ✅ 是 | 发件人地址码、消息类型、时间、投递状态。**不含正文**，且配对关系与授权清单存在被投的那台设备上，不在服务端 |

### Bugly 崩溃上报（默认关闭，需用户同意）

- **默认状态**：关闭。应用冷启动**不会初始化** Bugly SDK，不出网；仅在「更多 → 崩溃上报」开关开启（视为用户同意）后才初始化
- **用途**：仅用于收集崩溃信息，帮助开发者快速定位与修复
- **采集内容**：崩溃堆栈、应用版本号、系统版本、设备型号、CPU 架构
- **日志保护**：release 构建通过 R8 移除全部调试/信息级日志；日志输出不含通知标题、短信正文、验证码、号码等敏感内容
- **数据去向**：上传至腾讯 Bugly 服务器（[https://bugly.qq.com](https://bugly.qq.com)），仅开发者可访问
- **不采集**：通讯录、短信内容、通知内容、位置信息等任何个人隐私数据
- **如何关闭**：关闭「更多 → 崩溃上报」开关即可；因 SDK 无反初始化能力，关闭在下次冷启动后完全生效
- **合规依据**：上述范围按《个人信息保护法》(PIPL) 最小必要原则披露；未开启开关前不发生任何数据出网

### 分发渠道说明

本应用包含 `RECEIVE_SMS` / `READ_SMS` / `REQUEST_INSTALL_PACKAGES` 等敏感权限（短信通知识别转发与应用内更新为其核心功能），不符合 Google Play 政策对短消息类权限的发行要求，因此**不通过 Google Play 分发**，采用官网与 GitHub Releases 等自有渠道分发 APK。安装前请从可信渠道获取安装包。

---

## 常见问题与排错

### 通知收不到？

1. 通知访问权限是否开启
2. 电池优化是否忽略
3. 前台服务是否运行
4. 厂商自启动 / 后台权限是否开启
5. Webhook URL 是否正确（可在设置页测试）
6. 应用筛选 / 关键词过滤是否把通知过滤了

### 幻念推送连不上？

1. 「更多」页选的服务地址是否是当前网络可达的那一套（大陆 / 海外两套）
2. 设备自登记是否成功（幻念推送页能看到自己的身份）
3. 对端是否在你的**配对名单**里、且已勾选"允许转发"
4. 证书与系统时间是否正确（签名对时间敏感）

### 远程控制指令没反应？

1. 接收端是否授予了对应档位（L2 逐条勾选；L3 默认全关）
2. L3 是否带了高级密钥或 TOTP —— **L3 必须带其一**
3. 延时窗口内是否被取消（状态栏或顶端横幅都可撤销）
4. 指令里的 item / action 是否在封闭词表内（不在表内一律拒，回执里会写明）

---

## 贡献

欢迎提交 Issue 和 Pull Request！

- 贡献指南：[CONTRIBUTING.md](CONTRIBUTING.md) · [English](CONTRIBUTING-en.md)
- 安全政策：[SECURITY.md](SECURITY.md) · [English](SECURITY-en.md)
- 行为准则：[CODE_OF_CONDUCT-zh.md](CODE_OF_CONDUCT-zh.md) · [English](CODE_OF_CONDUCT.md)

## 许可证

本项目基于 [Apache License 2.0](LICENSE) 开源，并附带 [NOTICE](NOTICE)（第三方组件声明）。由 MIT 改为 Apache-2.0 的生效日期与范围见 [LICENSE_CHANGE.md](LICENSE_CHANGE.md)。