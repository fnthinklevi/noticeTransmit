<div align="center">

<img src="assets/app_icon.png" width="128" alt="通知推送助手">

# 通知推送助手

**[English](README-en.md) / 中文**

为 Android 设备提供**隐私优先**的通知转发工具。全链路本地处理，数据零上传（唯一例外为崩溃上报：默认关闭，仅在您主动开启后向腾讯 Bugly 上报崩溃日志，详见[隐私说明](#隐私说明)）。支持 12 类 Webhook 通道（通用 / 企业微信 / 钉钉 / 飞书 / Telegram / Bark / Server酱 / PushPlus / ntfy / Gotify / Slack / Discord，ntfy/Gotify 支持自建服务器）、企业微信/飞书**自建应用**通道与 SMTP 邮件多通道推送，桌面小部件一键启停推送，全部配置 AES-256 加密存储。**全应用中英双语国际化（853 词条 × 2 语言）**。

[![Flutter](https://badgen.net/badge/Flutter/3.44%2B/02569B?icon=flutter)](https://flutter.dev/)
[![AGP](https://badgen.net/badge/AGP/9.3.0/3DDC84?icon=android)](https://developer.android.com/build/releases/gradle-plugin)
[![Gradle](https://badgen.net/badge/Gradle/9.5.0/02303A?icon=gradle)](https://gradle.org/)
[![Platform](https://badgen.net/badge/Platform/Android/3DDC84?icon=android)](#)
[![Version](https://badgen.net/badge/Version/1.5.74/007AFF?icon=android)](https://github.com/fnthinklevi/noticeTransmit/releases)
[![License](https://badgen.net/badge/License/MIT/green)](#许可证)

🌐 **官方网站**：[notice.fnthink.top](https://notice.fnthink.top) — 软件介绍、客户端下载与后台管理入口

🌐 **GitHub Pages**：[fnthinklevi.github.io/noticeTransmit](https://fnthinklevi.github.io/noticeTransmit/) — 零运维静态部署（自动同步版本配置）

</div>

## 简介

通知推送助手是一款隐私优先的 Android 通知转发工具（Flutter + Kotlin）。核心能力：监听通知栏消息，通过 12 类 Webhook 通道（通用 / 企业微信 / 钉钉 / 飞书 / Telegram / Bark / Server酱 / PushPlus / ntfy / Gotify / Slack / Discord）、企业微信/飞书自建应用通道或 SMTP 邮件实时推送至目标平台，桌面小部件一键启停推送。全链路本地处理，数据零上传（崩溃上报默认关闭，开启后才向腾讯 Bugly 上报崩溃日志）。全应用中英双语国际化。开源 MIT，免费无广告。

## 功能特性

### 核心功能

- 🔔 **通知监听** - 监听系统所有应用的通知栏消息
- 📱 **多类型识别** - 智能识别微信、QQ、短信、来电、系统通知等类型
- 🔗 **Webhook 多通道** - 12 类通道类型（通用 / 企业微信 / 钉钉 / 飞书 / Telegram / Bark / Server酱 / PushPlus / ntfy / Gotify / Slack / Discord），可同时配置多个通道、每个通道独立开关；官方托管地址按 URL host 自动识别类型，自建 ntfy/Gotify 手动选定类型后保存/发送/测试全链路生效
- 📧 **SMTP 邮件推送** - 支持 SMTP 邮件转发（SSL/STARTTLS），可自定义主题模板与正文模板
- 📤 **多平台适配** - 自动适配企业微信、钉钉、飞书、Telegram、Bark、Server酱、PushPlus、ntfy、Gotify、Slack、Discord 等平台消息格式（ntfy/Gotify 支持自建服务器）；应用内更新安装包带 sha256 完整性校验（v1.5.69），Bark 业务失败如实呈现不再误报成功
- 🏢 **自建应用通道（企业微信 / 飞书）** - 独立于 Webhook 的「应用通道」体系：填 corpsecret / app_secret 等凭据即可让应用自身发消息（企微自建应用可定向 touser/@all，飞书可指定 chat_id/open_id）；API 地址可改为私有化部署地址；密钥加密存储，送达结果与失败重试同 Webhook 通道；**内置分步接入引导**（卡片右上角「?」查看 corpid/AgentId/Secret 或 App ID/App Secret 的获取步骤与注意事项）；**分层列表页**（v1.5.74）总览通道名称、类型与连接状态，点击进入详情编辑
- 🌡️ **手机温度推送（v1.5.74）** - 支持电池温度 / 设备整体温度 / 屏幕温度三维度独立规则，自定义阈值触发推送；30 分钟冷却防温度波动重复推送；与电量推送同源同轮询（联动不冲突）
- 💚 **通道健康探测（v1.5.73）** - Webhook 设置页对启用通道做轻量连通探测（任何 HTTP 响应即视为连通，仅超时 / DNS 失败 / 连接拒绝判为不可达），超过 6 小时未探测自动后台补探并持久化，通道卡片显示「✓ 连通 · 延迟 · 探测时间」徽标；业务层健康由最近一次真实推送的送达日志反映

### 进阶功能

- 🔋 **自定义电量提醒** - 支持完全自定义电量通知规则（充电/断开/指定电量阈值等），支持添加、编辑、删除规则，支持左滑删除和长按删除
- 📋 **历史记录** - 本地保存通知推送历史，支持搜索、详情查看和导出；长按快捷屏蔽（屏蔽该应用 / 屏蔽含此内容的通知），失败记录支持批量补推
- 🗂️ **每日自动归档** - WorkManager 每日把前一日推送历史导出为 JSON 文件（历史全量保留在数据库，归档只备份、不删源记录）；支持选择自定义归档目录（SAF），自定义目录场景由前台启动兜底完成
- ✅ **送达状态标注** - 首页推送记录逐条标注各通道送达状态（推送成功/推送失败/发送中/用户暂停推送），按企业微信/飞书/钉钉官方返回码判定，短信/电话通道送达结果实时回传；推送失败原因（如 HTTP 502 / 限流提示）直接内联显示
- 📈 **送达健康仪表盘（v1.5.73）** - 统计页新增「送达健康」区：各通道推送成功率排行（绿 / 橙 / 红分级）、失败原因 TOP（按 HTTP 状态码聚类，如 502 / 429 / 网络失败）、24 小时高峰分布柱状图；支持近 7 天 / 30 天切换，数据来自送达日志与通知记录聚合
- 📱 **应用筛选** - 自定义选择需要推送通知的应用
- 🏷️ **关键词过滤** - 支持白名单和黑名单关键词过滤，精准控制推送内容
- 🧠 **规则引擎** - 可视化配置通知规则，支持条件组合（IF）和动作配置（THEN），第一次进入提供功能引导说明，内置验证码优先推送、营销广告拦截、夜间免打扰、应用通知聚合等默认规则（开箱即用，升级自动补齐缺失项）；规则优先级支持快捷档位与自定义数值（0-500），每条规则可单独排除不适用的应用（「快速选择」自动识别本机已安装的主流通讯/邮箱应用，系统短信/电话组件聚合为单行、三态整组开关，置顶展示）
- 🧪 **规则测试器（v1.5.69）** - 输入模拟通知，实时展示「过滤 → 规则匹配 → 最终动作」的完整命中链路，规则配置问题一眼定位
- 📚 **规则模板库（v1.5.73）** - 内置 5 套预设模板（验证码优先推送 / 营销广告拦截 / 夜间免打扰 / 社交消息聚合 / 白名单关键词直通）一键导入；自定义规则可「存为模板」长期复用（同名覆盖）；模板可导出 `.json` 文件分享，导出时可设口令加密（PBKDF2 210k 迭代 + AES-256-GCM，与配置备份同源算法），导入自动识别明文 / 加密格式
- 📤 **失败记录批量补推（v1.5.69）** - 推送历史筛选失败记录后多选一键重推；推送失败自动重试（网络恢复/服务重启时重发最近失败项）
- 📦 **应用通知聚合（v1.5.69）** - 同一应用的通知在窗口期内（默认 60 秒，可配置，最小 5 秒）自动合并为一条推送，显著减少高频消息轰炸；支持「满 N 条提前推送」（不等窗口到点）与「按会话分组」（同应用不同联系人分开聚合）；自定义模板支持 `%count%`/`%titles%` 变量；规则条件支持 `*` 通配匹配任意应用；窗口期内仅一条消息时按普通推送直发；聚合期间前台通知实时展示待合并列表与剩余时间；无论聚合成功或失败，成员内容都会先完整保存到推送历史，且各成员记录逐条如实标注真实送达状态
- 🏷️ **通知优先级分级** - 原生链路提取系统通知优先级（高/中/低），可按「通知优先级」条件匹配规则；规则动作原生真实执行——静默忽略 / 仅记录 / 延迟推送 / 立即推送
- ⏰ **定时/延迟推送** - 规则「延迟推送」动作支持参数配置（延迟秒数 / 定时时间 HH:mm），到点自动补推 webhook 与邮件（深度 Doze 下可能有分钟级延迟），进程被杀/重启后任务自动恢复
- 📝 **推送模板引擎** - 自定义消息格式（text/markdown/json/xml），支持变量占位符（`%appName%`/`%title%`/`%content%` 等），按平台自动包裹 payload 与转义，每个通道独立配置
- 📟 **桌面小部件** - 2×2 / 4×2 双规格，自适应宽度布局，桌面点击一键启停推送；显示当日推送计数（跨天自动重置）；「推送开关」页一键添加到桌面

### 体验优化

- 🌐 **多语言国际化** - 全应用中英双语（`app_zh.arb` / `app_en.arb` 各 853 词条，gen-l10n 生成，CI 锁定两侧键集合一致防漏翻），可在设置页自由切换语言；语言标签同步下发原生侧，常驻通知与推送文案随之切换
- 🖼️ **桌面图标切换** - 内置 17 款图标 × 中 / 英双语标签 = 34 个 launcher 图标别名，应用内一键切换（同一时刻仅启用一个别名，其余禁用）
- 📄 **文本选择菜单多机型适配（v1.5.74）** - 全部 36 处文本组件的选择菜单按钮文案（复制/剪切/粘贴/全选/分享）统一为应用内词条，彻底消除厂商 ROM 上按钮显示英文或空白的问题
- 🎨 **弹窗 iOS 风格统一（v1.5.74）** - 全部确认弹窗统一为分割线按钮布局（取消=次要色 / 确认=蓝色 / 删除=红色），深浅色主题自适应
- 🔄 **常驻通知状态机优化（v1.5.74）** - 开始/停止/进程终止/自启动保活/权限缺失 5 场景统一显隐逻辑，通知栏常驻通知随监听状态实时同步
- 🌙 **深色模式** - 支持浅色/深色/跟随系统三种主题模式
- 🛡️ **后台保活** - 前台服务 + 电量优化白名单 + 开机自启动；内置国产 ROM 保活引导（省电无限制/自启动/任务锁定，一键跳转厂商设置）
- 📡 **监听可靠性增强（v1.5.69）** - 会话类通知（微信/QQ/Telegram 等）正文仅存在于 MessagingStyle 时自动兜底读取，去重键含通知 tag 防误判漏读；通知使用权被系统回收时前台显示「监听已断开 · 可能漏读通知」警告并自动重连；**服务被系统回收后启动时按持久化水位自动补扫通知栏中未处理的驻留通知**（最长回溯 6 小时），大幅减少长时间锁屏/后台的漏通知
- 🩺 **诊断日志运行时开关（v1.5.69）** - 「更多」页连点版本号 7 次即可开关诊断日志（logcat 输出规则/聚合链路 `[diag]` 日志，不含通知标题/正文），排查问题无需重新安装
- 💾 **配置备份与恢复（v1.5.69）** - 一键将 **12 类配置**（Webhook/邮件通道含凭据、**自建应用通道含凭据**、通知规则、短信设置、应用过滤、黑白名单、电池规则与电量开关、设备名、主题/语言）加密导出为 `.nbackup` 文件（AES-256-GCM + PBKDF2 210k 迭代口令派生，文件头自描述 KDF 参数），换机/重装后选文件 + 输入口令即可还原；检测到现有配置时支持「覆盖全部 / 仅导入空缺项」冲突策略，非 https 地址自动跳过；备份格式 v2 向后兼容 v1
- 📱 **桌面小组件全新升级（v1.5.63）** - 2×2/4×2 布局与视觉全面美化（状态圆环/提示胶囊/当日计数），系统添加弹窗带预览与说明，不支持一键添加的桌面自动弹出分品牌分步引导；短信监听设置中心上线：监听开关 / 验证码开关 / 监听卡选择（单卡设备自动灰化），卡槽过滤同时作用于短信与电话链路，推送正文支持「卡1，运营商」双语信息行
- 🔐 **崩溃上报合规开关（v1.5.62）** - Bugly 崩溃上报默认关闭、同意后才初始化，设置页可随时关闭；双端规则引擎归一化对齐（全角转半角/空白折叠/条件值 trim），51 条双端黄金用例锁定匹配一致性；Webhook 送达日志落地可审计，导出全量直读数据库不受内存上限约束
- 📩 **短信可靠性增强（v1.5.61）** - 短信采用「广播 + 短信库监听」双链路：除 `SMS_RECEIVED` 广播主链路外，短信库 ContentObserver 会兜底捕获广播漏掉的短信，两条链路按内容指纹去重、不会重复推送；支持自动提取验证码并以独立字段下发
- ⏸️ **一键暂停推送** - 前台通知栏 Action 按钮一键暂停/恢复推送（监听继续，仅停止 webhook 发送），状态持久化重启后恢复；暂停期间收到的消息在历史中显示「用户暂停推送」状态，可一键「现在推送」手动补推
- 🔄 **在线更新** - 支持版本更新，无需重新安装 APK；由系统下载器（DownloadManager）后台下载，免存储权限、锁屏后台不中断；多下载源自动回退（CDN / GitHub 加速镜像 / GitHub 直链，按设备架构匹配）；部署模式灵活（Node.js 服务器 / GitHub Pages 静态部署，客户端自动兼容）
- 📲 **Cupertino 设计语言** - 采用 Cupertino（iOS）系统设计语言，界面简洁优雅
- 🔒 **完整隐私政策** - 应用内置 11 章节隐私政策（数据收集边界 / 存储加密 / 信息共享 / 儿童隐私 / 用户权利等），首次启动弹窗征得同意，可随时在「更多」页查看
- 📊 **推送统计统一** - 首页/更多页/状态栏推送统计共用同一数据源，当日计数实时同步

### 安全加固

- 🔐 **二步验证（TOTP）** - 管理后台登录启用二步验证，兼容 Google Authenticator
- 🔑 **bcrypt 哈希** - Token 使用 bcrypt 哈希验证，防暴力破解
- 🛡️ **IP 封锁** - 10分钟内输错5次验证码自动封锁IP 1小时
- 🔢 **恢复码** - 生成8个恢复码，设备丢失时可找回账户
- 🔒 **敏感数据加密** - TOTP secret 使用 AES-256-GCM 加密存储
- 🎭 **混淆规则就绪** - 已配置 ProGuard/R8 混淆规则文件（`proguard-rules.pro`），Release 构建启用代码混淆与资源压缩
- 📡 **Token安全传输** - 仅接受 Header 传递，禁止 URL 参数
- 🎲 **安全随机数** - 使用 crypto.randomUUID() 生成会话 ID
- 🗄️ **SQLite 加密** - 通知记录、Webhook/邮件/自建应用通道配置与送达日志（schema v10，6 张表）全部经 SQLCipher AES-256 加密存储，密钥由 flutter_secure_storage 托管于 AndroidKeyStore
- 🔑 **Webhook 密钥安全** - Webhook URL（含钉钉/企微/飞书认证 key）使用 AndroidKeyStore 加密存储
- 🔐 **SSL 证书固定** - 双端 HTTP 客户端（Dart `PinnedHttpClient` + Kotlin `NetworkClient` 的 OkHttp `CertificatePinner`）均已就位，为 HTTPS 证书安全层，**默认未启用**（须注入 `CERT_PINS` / `ENABLE_CERT_PINNING`，Debug 构建恒关闭），当前通过 Cloudflare CDN 间接保护；证书轮换/启用流程见 [docs/cert_rotation_runbook.md](docs/cert_rotation_runbook.md)
- 🧩 **小部件广播防护** - 桌面小部件的启停广播受签名级自定义权限 `com.fnthink.notice.permission.WIDGET_CONTROL` 保护，第三方应用因签名不匹配无法伪造 `TOGGLE_PUSH` 广播静默开关推送
- 🔒 **HTTPS 强制** - 全站 HTTPS，`network_security_config.xml` 禁止明文传输

## 技术栈

| 模块 | 技术 |
|------|------|
| 前端 | Flutter 3.44.x (Dart 3.12.2) |
| 状态管理 | get_it + Service 类 |
| 依赖注入 | get_it (^9.2.1) |
| 本地数据库 | sqflite_sqlcipher (^3.4.0) · SQLCipher AES-256 · schema v10 / 6 张表 |
| 键值存储 | shared_preferences · flutter_secure_storage (^9.2.4) + androidx.security EncryptedSharedPreferences |
| 原生服务 | Kotlin 2.3.20 (Android)，主源码 51 个 Kotlin 文件 |
| 网络请求 | http (Dart) / OkHttp 4.12.0 (Kotlin) |
| 邮件发送 | com.sun.mail:android-mail 1.6.7 (SMTP) |
| 通知监听 | NotificationListenerService |
| 后台保活 | Android 原生 Foreground Service + WakeLock (PARTIAL_WAKE_LOCK) |
| 后台任务 | workmanager ^0.6.0（每日归档） |
| 协程 | kotlinx.coroutines (SupervisorJob + Dispatchers.IO) |
| 跨端通信 | MethodChannel `com.fnthink.notice/notification`（87 个方法 · 5 个原生 handler） |
| 国际化 | gen-l10n + ARB（zh / en 各 853 词条） |
| 崩溃统计 | 腾讯 Bugly 4.1.9.3 |
| 服务端 | Node.js 24 LTS (engines `>=24`) + Express 5.x (Token鉴权 + 二步验证) / GitHub Pages 静态部署 |
| TOTP验证 | otplib (^13.0.1) |
| 密码哈希 | bcryptjs (^2.4.3) |
| 数据加密 | Node.js crypto (AES-256-GCM) / AndroidKeyStore + flutter_secure_storage |
| 构建工具 | Gradle 9.5.0 + AGP 9.3.0 + JDK 21 |
| 代码质量 | flutter_lints ^6.0.0 · dart format · ktlint 1.8.0 · prettier 3.9.8 · Android lint（含 baseline） |
| 测试 | flutter test（Dart）· JUnit（Kotlin JVM）· jest + supertest（服务端）· integration_test |
| CI/CD | GitHub Actions（analyze / build-apk / integration_test / deploy-pages） |
| APK签名 | Gradle signingConfig：V1+V2+V3 全开（`enableV1/V2/V3Signing`），密钥仅由环境变量或 `android/key.properties` 注入 |

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

## 项目结构

```
noticeTransmit/
├── lib/                          # Flutter 端代码（69 个 Dart 文件）
│   ├── main.dart                 # 主入口（初始化顺序 + WorkManager 注册）
│   ├── update_manager.dart       # 应用内更新（多源回退 + sha256 校验）
│   ├── database/                 # 数据库层（database_helper.dart，SQLCipher schema v10）
│   ├── di/                       # get_it 服务注册（service_locator.dart）
│   ├── l10n/                     # 国际化（arb/app_zh.arb · app_en.arb 各 853 词条 + 生成代码）
│   ├── models/                   # 数据模型（4 个文件）
│   │   ├── notification_record.dart  # 通知记录模型
│   │   ├── webhook_channel.dart  # Webhook 渠道模型（12 类通道 + 消息格式）
│   │   ├── email_channel.dart    # 邮件通道模型
│   │   └── notification_rule.dart # 规则引擎模型（条件/动作）
│   ├── pages/                    # 页面（27 个文件）
│   │   ├── main_page*.dart       # 首页（actions / dialogs / update 拆分同前缀）
│   │   ├── history_page.dart     # 历史记录（搜索 / 导出 / 批量补推）
│   │   ├── stats_page.dart       # 统计 + 送达健康仪表盘
│   │   ├── webhook_settings_page.dart · email_settings_page.dart · app_channel_*_page.dart
│   │   ├── rule_list_page.dart · rule_edit_page.dart · rule_tester_page.dart
│   │   ├── battery_page.dart · temperature_page.dart
│   │   ├── sms_monitor_settings_page.dart · app_filter_page.dart · keywords_page.dart
│   │   ├── backup_restore_page.dart · widget_guide_page.dart · permission_settings_page.dart
│   │   └── splash_page.dart · more_page.dart · privacy_policy_page.dart
│   ├── services/                 # 服务层（24 个文件）
│   │   ├── platform_channel.dart # MethodChannel 统一声明
│   │   ├── notification_service.dart · webhook_service.dart · app_channel_service.dart
│   │   ├── filter_service.dart   # 应用过滤 / 关键词 / 规则匹配（Dart 侧）
│   │   ├── rule_template_service.dart · rule_trace.dart
│   │   ├── battery_service.dart · temperature_service.dart
│   │   ├── sms_service.dart · email_service.dart · backup_service.dart
│   │   ├── archive_worker.dart   # WorkManager 每日归档
│   │   ├── pinned_http_client.dart · secure_storage_service.dart
│   │   └── icon_service.dart · locale_service.dart · theme_service.dart · device_info_service.dart …
│   ├── theme/                    # 主题配置（app_colors.dart / app_theme.dart）
│   └── widgets/                  # 可复用组件（4 个：图标选择 / 文本选择菜单 / iOS 弹窗按钮 / 模板面板）
├── android/                      # Android 原生代码
│   └── app/src/
│       ├── main/kotlin/com/fnthink/notice/   # 主源码（51 个 Kotlin 文件）
│       │   ├── MainActivity.kt       # 主 Activity（MethodChannel 分发入口）
│       │   ├── NotificationMonitorService.kt  # 通知监听服务
│       │   ├── NotificationProcessor.kt       # 通知解析模块
│       │   ├── BatteryMonitor.kt              # 电量 / 温度监控模块
│       │   ├── WebhookSender.kt · AppChannelSender.kt  # Webhook 与自建应用通道发送
│       │   ├── ChannelRegistry.kt             # 通道描述符表（新增通道的唯一改动点）
│       │   ├── RuleEngine.kt · FilterEngine.kt · TemplateEngine.kt  # 规则 / 过滤 / 模板引擎
│       │   ├── RetryQueue.kt · DelayedPushManager.kt · MergePushManager.kt  # 重试 / 延迟 / 聚合
│       │   ├── SmsReceiver.kt · SmsObserver.kt · PhoneCallReceiver.kt  # 短信双链路 / 来电
│       │   ├── PushToggleWidgetProvider.kt · PushToggleWidgetWideProvider.kt  # 2×2 / 4×2 小部件
│       │   ├── BootReceiver.kt        # 开机广播接收器
│       │   ├── NetworkClient.kt       # OkHttp 客户端（可选证书固定）
│       │   ├── ConfigManager.kt · SecurePrefs.kt  # 配置与加密存储
│       │   └── channels/              # MethodChannel handler（权限 23 / 配置 30 / 设备 13 / 文件 12 / 统计 9 = 87 方法）
│       ├── test/                  # Kotlin JVM 单元测试（26 个测试类 / 234 用例）+ 黄金快照资源
│       └── androidTest/           # 仪表测试（APK 签名校验）
├── server/                       # 服务端（更新服务 + TOTP 管理后台）
│   ├── server.js                # 服务端入口（启动 + 优雅关闭）
│   ├── lib/                     # 模块化分层（app/store/otp/middleware + routes/）
│   ├── test/                    # jest + supertest HTTP 契约测试（29 用例）
│   ├── data/                     # 版本配置数据
│   │   └── version.json          # 版本信息（版本/构建号/sha256/多架构下载地址）
│   ├── public/                   # 官网与 GitHub Pages 静态站点
│   └── README.md                # 服务端部署文档
├── test/                         # Dart 测试（37 个文件 / 379 用例）
├── integration_test/             # 设备侧冒烟测试（smoke_test.dart，7 步主链路）
├── .github/                      # workflows/（CI）与 scripts/（格式、版本一致性、本地发版）
├── docs/                         # cert_rotation_runbook.md · roadmap.md
├── assets/                       # 资源文件
│   ├── app_icon.png
│   ├── app_icon.svg
│   └── icons/
├── pubspec.yaml                  # Flutter 配置（version: 1.5.74+113）
└── README.md                     # 项目说明
```

## 快速开始

### 环境要求

> **重要提示**：本项目使用 **AGP 9.3.0** + **Gradle 9.5.0**，对 Flutter / Dart / Android Studio 版本有最低要求。

| 工具 | 最低版本 | 推荐版本 | 说明 |
|------|----------|----------|------|
| **Flutter SDK** | 3.44.0 | 3.44.x stable | AGP 9.x 支持从 Flutter 3.44 开始（CI 固定 3.44.4） |
| **Dart SDK** | 3.12.2 | 3.12.x | `pubspec.yaml` 声明 `sdk: ^3.12.2`，随 Flutter 3.44 自带 |
| **Android Gradle Plugin (AGP)** | 9.0.0 | 9.3.0 | 项目已配置 |
| **Gradle** | 9.5.0 | 9.5.0 | 项目已配置（gradle-wrapper.properties） |
| **Kotlin** | 2.3.20 | 2.3.20 | 通过 `settings.gradle.kts` 显式声明 `org.jetbrains.kotlin.android` 插件 |
| **Android Studio** | Koala (2024.1.1) | 最新稳定版 | 需支持 AGP 9.x |
| **JDK** | 21 | 21+ | AGP 9.x 要求 JDK 21 及以上（`compileOptions` / `jvmTarget` 均为 21） |
| **Android SDK** | 24 (minSdk) | 37 (compileSdk / targetSdk) | minSdk 24（`flutter.minSdkVersion`），compileSdk 与 targetSdk 均为 37 |
| **Node.js**（仅服务端） | 24 | 24 LTS | `server/package.json` 声明 `engines.node >= 24`，CI 与生产同版本 |

#### 版本兼容性说明

- **Flutter 3.44 以下版本**：不支持 AGP 9.x，构建会失败。请先执行 `flutter upgrade` 升级到 3.44+。
- **AGP 8.x 及以下**：本项目已迁移到 AGP 9.x，无法降级使用。
- **Kotlin**：项目通过 `settings.gradle.kts` 显式声明 `org.jetbrains.kotlin.android` 版本 2.3.20，并在 `gradle.properties` 中保留 `android.builtInKotlin=false`、`android.newDsl=false`。

### 构建 APK

```bash
# 安装依赖
flutter pub get

# 代码检查
flutter analyze

# 构建 release 版本
flutter build apk --release --target-platform android-arm64
```

### 运行测试与质量校验

```bash
# Dart 单元测试（37 个文件 / 379 用例）
flutter test

# Kotlin JVM 单元测试（26 个测试类 / 234 用例）
cd android && ./gradlew :app:testDebugUnitTest

# Android lint（error 即失败，已知误报由 android/app/lint-baseline.xml 兜住）
cd android && ./gradlew :app:lintDebug

# 服务端 HTTP 契约测试（29 用例，需 Node.js 24 LTS）
cd server && npm ci && npm test

# 三路格式校验（dart format + ktlint 1.8.0 + prettier 3.9.8；加 --fix 就地格式化）
bash .github/scripts/check_format.sh

# 版本与文档一致性闸门
bash .github/scripts/check_version_consistency.sh

# 设备侧冒烟测试（需连接真机或模拟器；CI 见 integration_test.yml）
flutter test integration_test/smoke_test.dart
```

### 部署服务端

支持两种部署模式：

- **Node.js 服务器**（完整功能）：详见 [server/README.md](server/README.md) · [English](server/README-en.md)
- **GitHub Pages**（零运维静态部署）：详见 [server/GITHUB_PAGES.md](server/GITHUB_PAGES.md) · [English](server/GITHUB_PAGES-en.md)

客户端自动兼容两种模式，无需修改代码。

## 质量保障与 CI

**测试规模**（均为可执行用例；除设备侧测试外，其余全部纳入 CI 门禁强制执行）：

- **Dart 单元测试** - 37 个测试文件 / 379 用例（`test/`）：架构契约（启动顺序、launcher manifest 契约、双端通道方法齐平）、数据库 schema 与迁移、备份/送达/过滤黄金用例、页面 widget 测试
- **Kotlin JVM 单元测试** - 26 个测试类 / 234 用例（`android/app/src/test/`）：双端规则匹配一致性由 `rule_engine_golden.json` 51 条黄金用例锁定，通道行为由 `channel_behavior_golden.json`（48 条载荷 + 34 条响应解析）逐字节快照锁定
- **服务端契约测试** - 29 用例（`server/test/auth.test.js`，jest + supertest）：登录 / TOTP 启用与恢复码消费 / 会话失效 / IP 封锁
- **设备侧测试** - `integration_test/smoke_test.dart` 7 步主链路冒烟（启动 → 注入 → 通知页 → 送达状态 → 历史 → 服务启停 → 导出），加 `android/app/src/androidTest` 仪表测试，由 `integration_test.yml` 在 API 34 / x86_64 / Pixel 6 模拟器上触发

**CI 工作流**（`.github/workflows/`，均运行于 `ubuntu-24.04`）：

- **`analyze.yml`（PR 门禁，16 步）** - flutter analyze → 版本一致性 → 代码度量 → Dart 单测 → Android JVM 单测 → Android lint → 服务端契约测试 → 三路格式校验 → 覆盖率产物
- **`build-apk.yml`（`v*` tag 或手动触发，18 步）** - 前置测试与 analyze → arm64 release 打包 → ABI 纯净度与版本号双闸 → GitHub Release
- **`integration_test.yml`（手动触发，7 步）** - 模拟器冒烟测试 + 仪表测试
- **`deploy-pages.yml`（`server/public/**` 或 `server/data/version.json` 变更 / 手动触发，5 步）** - 零运维静态版本源发布
- **格式统一** - `.github/scripts/check_format.sh` 本地与 CI 跑同一支：`dart format` + ktlint 1.8.0（规则见 `.editorconfig`）+ prettier 3.9.8（配置见 `server/.prettierrc`）
- **版本一致性闸门** - `.github/scripts/check_version_consistency.sh` 比对 `pubspec.yaml` / `update_manager.dart` / `MainActivity.kt` / `server/data/version.json` 四处版本与 build 号，并校验 `version.json` 的 sha256 字段完备性、官网 i18n 覆盖、README 依赖标注与 zh/en ARB 键集合一致
- **本地发版预检** - `.github/scripts/release_local.sh <A.B.C>`：版本一致性 → format/analyze → 4 个架构 APK 构建与纯净度验证 → version.json 的 fileSize/sha256 回填 → 徽章与 update.md 缺项检查

## 贡献

欢迎提交 Issue 和 Pull Request！

- 贡献指南：详见 [CONTRIBUTING.md](CONTRIBUTING.md) · [English](CONTRIBUTING-en.md)
- 安全政策：详见 [SECURITY.md](SECURITY.md) · [English](SECURITY-en.md)
- 行为准则：详见 [CODE_OF_CONDUCT-zh.md](CODE_OF_CONDUCT-zh.md) · [English](CODE_OF_CONDUCT.md)

## 隐私说明

### 数据采集声明

本应用重视用户隐私，关于数据采集的说明如下：

| 数据类型 | 是否采集 | 说明 |
|----------|----------|------|
| **通知内容** | ❌ 不上传 | 所有通知仅在本地处理和推送，不上传到任何服务器 |
| **通讯录/短信** | ❌ 不上传 | 仅本地监听用于推送，不上传到任何服务器 |
| **设备标识** | ⚠️ 仅崩溃上报开启时 | Bugly SDK 用于设备去重统计；崩溃上报默认关闭 |
| **崩溃信息** | ⚠️ 仅崩溃上报开启时 | 用户主动开启后才通过 Bugly 收集崩溃堆栈 |

### Bugly 崩溃上报（默认关闭，需用户同意）

- **默认状态**：关闭。应用冷启动**不会初始化** Bugly SDK，不出网；仅在「更多 → 崩溃上报」开关开启（视为用户同意）后才初始化并开始上报
- **用途**：仅用于收集应用崩溃信息，帮助开发者快速定位和修复问题
- **采集内容**：崩溃堆栈、应用版本号、系统版本、设备型号、CPU 架构
- **日志保护**：release 构建通过 R8 移除全部调试/信息级日志（`Log.v/d/i`），日志输出不含通知标题、短信正文、验证码、号码等敏感内容；崩溃上报附带的日志同样不包含这些信息
- **数据去向**：上传至腾讯 Bugly 服务器（[https://bugly.qq.com](https://bugly.qq.com)），仅开发者可访问，用于问题分析
- **不采集**：用户通讯录、短信内容、通知内容、位置信息等任何个人隐私数据
- **如何关闭**：关闭「更多 → 崩溃上报」开关即可；因 SDK 无反初始化能力，关闭在下次冷启动后完全生效
- **合规依据**：上述范围按《个人信息保护法》(PIPL) 最小必要原则披露；未开启开关前不发生任何数据出网

### 推送数据

所有通知推送均由用户自行配置的通道发出（Webhook / 企业微信·飞书自建应用 / SMTP 邮件），请求直接发往您指定的目标，开发者不存储任何推送内容。仅在崩溃上报开启后，Bugly 采集最小必要的崩溃统计（堆栈、设备型号、系统版本、应用版本），不包含任何个人隐私数据。

### 分发渠道说明

本应用包含 `RECEIVE_SMS` / `READ_SMS` / `REQUEST_INSTALL_PACKAGES` 等敏感权限（短信通知识别转发与应用内更新为其核心功能），不符合 Google Play 政策对短消息类权限的发行要求，因此**不通过 Google Play 分发**，采用官网与 GitHub Releases 等自有渠道分发 APK。安装前请从可信渠道获取安装包。

## 常见问题与排错

### 通知收不到？
1. 通知访问权限是否开启
2. 电池优化是否忽略
3. 前台服务是否运行
4. 厂商自启动/后台权限是否开启
5. Webhook URL 是否正确（可在设置页测试）
6. 应用筛选 / 关键词过滤是否把通知过滤了

## 许可证

本项目基于 [MIT License](LICENSE) 开源。
