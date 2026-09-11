// 通知推送助手 - 中文/English 国际化
// 遍历正文文本节点，用字典替换所有中文 → English，反之亦然
(function () {
  // ── 完整翻译字典：中文原文 → 英文译文 ──
  var D = {};
D['通知推送助手 · 让每条通知，抵达每个平台'] = 'NoticeTransmit';
D['通知推送助手'] = 'NoticeTransmit';
  D['让每条通知，<br><span class="grad">抵达每个平台</span>'] = 'Every Notification, Every Platform';
  D['让每条通知，'] = 'Every notification,';
  D['抵达每个平台'] = 'every platform.';
  D['开源免费 · 本地处理'] = 'Open Source · Local Processing';
  D['立即下载'] = 'Download Now';
  D['在 GitHub 查看源码'] = 'View on GitHub';
  D['MIT 开源'] = 'MIT Open Source';
  D['Flutter 构建'] = 'Built with Flutter';
  D['无广告 · 无追踪'] = 'No Ads · No Tracking';
  D['通知推送'] = 'Notification Push';
  D['监听中'] = 'Listening';
  D['已推送'] = 'Sent';
  D['已拦截'] = 'Blocked';
  D['微信'] = 'WeChat';
  D['电量提醒'] = 'Battery Alert';
  D['短信验证码'] = 'SMS Code';
  D['来电结束'] = 'Call Ended';
  D['营销广告'] = 'Marketing Ad';
  D['【项目群】发布会 15:00 开始'] = '[Project] Event starts 15:00';
  D['电量已降至 20%，请及时充电'] = 'Battery at 20%, please charge';
  D['验证码 928311，优先推送'] = 'OTP 928311, push priority';
  D['与 138****6021 通话 3 分钟'] = 'Call with 138****6021, 3 min';
  D['已被夜间免打扰规则拦截'] = 'Blocked by DND rule';
  D['企业微信'] = 'WeCom';
  D['钉钉'] = 'DingTalk';
  D['飞书'] = 'Feishu';
  D['主流推送平台'] = 'Platforms Supported';
  D['种通知智能识别'] = 'Notification Types';
  D['款可选应用图标'] = 'App Icon Options';
  D['通知本地处理'] = 'Local Processing';
  D['一个应用，管好所有通知'] = 'One App for All Notifications';
  D['从监听、过滤到推送，每个环节都可精细掌控。为效率而生的完整功能矩阵。'] = 'From listening to filtering to delivery — full control at every stage. A complete toolkit built for efficiency.';
  D['功能'] = 'Features';
  D['工作原理'] = 'How It Works';
  D['安全'] = 'Security';
  D['技术栈'] = 'Tech Stack';
  D['常见问题'] = 'FAQ';
  D['全量通知监听'] = 'Full Notification Listening';
  D['监听系统所有应用的通知栏消息，智能识别微信、QQ、短信、来电、系统等 5 类通知类型。'] = 'Monitors all app notifications, intelligently identifying WeChat, QQ, SMS, calls, system — 5 notification types.';
  D['可视化规则引擎'] = 'Visual Rule Engine';
  D['IF 条件组合 + THEN 动作配置，按通知优先级（高/中/低）分级处理——静默忽略 / 仅记录 / 定时与延迟推送 / 立即推送 / 同应用合并推送（可设窗口期）；内置验证码优先、广告拦截、夜间免打扰等默认规则，开箱即用。'] = 'IF condition + THEN action, tiered by notification priority (high/medium/low) — silent ignore / record only / scheduled & delayed push / push now / same-app merged push (configurable window). Built-in rules for OTP priority, ad blocking, nighttime DND — ready out of the box.';
  D['关键词过滤'] = 'Keyword Filtering';
  D['白名单 + 黑名单双模式关键词过滤，精准控制哪些内容推送、哪些内容拦截。'] = 'Whitelist + blacklist dual-mode keyword filtering for precise push control.';
  D['应用筛选'] = 'App Filtering';
  D['自定义选择需要推送的应用，支持「通知 / 不通知」双模式与一键全选、反选。'] = 'Select apps to push, with Notify/Do Not Notify modes, Select All and Invert.';
  D['自定义电量提醒'] = 'Custom Battery Alerts';
  D['充电 / 断开 / 指定电量阈值全自定义规则，息屏 Doze 下依然可靠推送，可增删改。'] = 'Full custom rules for charging, disconnecting, and battery thresholds. Reliable push even in Doze mode.';
  D['历史记录'] = 'History';
  D['推送历史完整保存于本地（无条数上限），支持全量搜索与按日 / 时间段 / 应用 / 包名 / 送达状态筛选，详情查看与导出，随时回溯每一条通知去向。'] = 'Push history is fully saved locally with no cap — full-history search with day / time-range / app / package / delivery-status filters, detail view, and export. Track every notification.';
  D['深色模式'] = 'Dark Mode';
  D['浅色 / 深色 / 跟随系统三种主题，Cupertino 设计语言，界面简洁优雅。'] = 'Light / Dark / System three themes. Cupertino design language. Clean, elegant interface.';
  D['推送通道类型'] = 'Push Channel Types';
  D['款可选应用图标'] = 'App Icon Variants';
  D['通知本地处理'] = 'Local Processing';
  D['多语言国际化'] = 'Multi-language i18n';
  D['全应用中英双语支持（120+ 处迁移），设置页一键切换语言。'] = 'Full-app Chinese/English bilingual, switch language in settings page.';
  // feature cards — updated v1.5.48
  D['Webhook + 邮件多通道'] = 'Webhook + Email Multi-channel';
  D['Webhook（企业微信 / 钉钉 / 飞书 / Telegram / Bark / Server酱 / PushPlus / 自定义）+ SMTP 邮件（SSL/STARTTLS），每个通道独立开关，主题/正文支持模板变量。'] = 'Webhook (WeCom / DingTalk / Feishu / Telegram / Bark / ServerChan / PushPlus / Custom) + SMTP Email (SSL/STARTTLS), each channel independently toggleable, subject/body support template variables.';
  // how it works — updated v1.5.48
  D['按格式封装，并行推送至 Webhook / 邮件通道'] = 'Packaged per format, pushed in parallel to all Webhook / Email channels';
  D['SMTP 邮件'] = 'SMTP Email';
  D['SSL/STARTTLS 加密'] = 'SSL/STARTTLS Encryption';
  // download buttons
  D['下载 arm64'] = 'Download arm64';
  D['下载 arm32'] = 'Download arm32';
  D['下载 x86_64'] = 'Download x86_64';
  D['下载 全平台'] = 'Download All';
  // hero — updated v1.5.56
  D['通知推送助手是一款 Android 通知监听与推送工具。把手机上的任意通知，通过 Webhook（企业微信 / 钉钉 / 飞书 / Telegram / Bark / Server酱 / PushPlus）或 SMTP 邮件实时转发——支持应用筛选、关键词过滤、可视化规则引擎（通知优先级分级、定时/延迟推送）、桌面小部件一键启停与自定义电量提醒。'] = 'An Android notification listener & push tool. Forward any notification via Webhook (WeCom / DingTalk / Feishu / Telegram / Bark / ServerChan / PushPlus) or SMTP email in real time. App filtering, keyword filtering, visual rule engine (priority levels, scheduled/delayed push), one-tap pause widget & custom battery alerts included.';
  // FAQ — updated v1.5.48
  D['它会不会上传我的通知或短信内容？'] = 'Does it upload my notifications or SMS?';
  D['不会。所有通知、短信、通讯录仅在本地监听、处理与推送，不会上传到任何服务器。推送只通过你自行配置的 Webhook 或 SMTP 邮件通道发出，开发者不存储任何推送内容。仅崩溃统计（腾讯 Bugly）会采集崩溃堆栈用于修复问题。'] = 'No. All notifications, SMS, contacts stay on-device. Push goes only through your configured Webhook or SMTP email. The developer stores nothing. Only crash logs (Tencent Bugly) are collected for bugfixing.';
  D['支持哪些推送平台？'] = 'Which platforms are supported?';
  D['内置适配企业微信群机器人、钉钉自定义机器人、飞书群机器人、Telegram Bot、Bark 服务、Server酱、PushPlus 的消息格式；支持 SMTP 邮件推送（SSL/STARTTLS）；也支持任意自定义 Webhook 地址，可对接兼容的第三方平台或你自己的服务端。'] = 'Built-in support for WeCom group bots, DingTalk custom bots, Feishu group bots, Telegram Bot, Bark service, ServerChan, and PushPlus. Also supports SMTP email push (SSL/STARTTLS) and any custom Webhook URL for third-party services or your own backend.';
  // footer — updated v1.5.48
  D['Android 通知监听与推送工具。开源、免费、本地处理，支持 Webhook 和 SMTP 邮件多通道。让每条通知抵达每个平台。由 幻念团队 fnthinklevi 打造。'] = 'Android notification listener & push tool. Open source, free, local processing. Webhook + SMTP email multi-channel. Every notification to every platform. Built by fnthinklevi.';
  D['后台保活 · 在线更新'] = 'Background Persistence & Updates';
  D['前台服务 + 电量白名单 + 开机自启，稳定常驻；支持版本更新，无需重装。'] = 'Foreground service + battery whitelist + auto-start for reliable persistence. OTA updates supported.';
  D['通知，如何抵达你想要的地方'] = 'How Notifications Reach You';
  D['一条通知从产生到推送，只需毫秒级的四步流转。'] = 'From notification to delivery — four steps in milliseconds.';
  D['捕获通知'] = 'Capture';
  D['系统通知栏产生消息，监听服务实时捕获'] = 'System notification bar generates message, listener captures in real time';
  D['识别分类'] = 'Identify';
  D['解析来源应用与类型，标记微信、短信、来电等'] = 'Parse source app and type, tag WeChat, SMS, calls, etc.';
  D['规则过滤'] = 'Filter';
  D['经规则引擎 + 关键词 + 应用筛选层层判定'] = 'Processed through rule engine + keywords + app filter';
  D['多通道推送'] = 'Push';
  D['按格式封装，并行推送至各 Webhook 通道'] = 'Packaged per format, pushed in parallel to all Webhook channels';
  D['送达确认'] = 'Confirm';
  D['推送结果记入历史，成功失败一目了然'] = 'Push results logged to history, success/failure clearly shown';
  D['群机器人 Webhook'] = 'Group Bot Webhook';
  D['自定义机器人'] = 'Custom Bot';
  D['群自定义机器人'] = 'Group Custom Bot';
  D['自定义 Webhook'] = 'Custom Webhook';
  D['任意兼容平台'] = 'Any compatible platform';
  D['Bot API 推送'] = 'Bot API push';
  D['iOS 推送服务'] = 'iOS push service';
  D['微信推送 SendKey'] = 'WeChat push via SendKey';
  D['微信/邮件多渠道'] = 'WeChat / Email multi-channel';
  D['Server酱'] = 'ServerChan';
  D['把安全，做进每一层'] = 'Security at Every Layer';
  D['通知不上云、管理后台二步验证、敏感数据加密——隐私与安全，从设计之初就被认真对待。'] = 'Notifications stay local, admin 2FA, sensitive data encrypted. Privacy and security taken seriously from day one. Minimal crash logs collected via Bugly for bugfixing.';
  D['二步验证（TOTP）'] = 'Two-Factor Auth (TOTP)';
  D['管理后台登录启用 2FA，兼容 Google Authenticator，防止凭据泄露。'] = 'Admin login with 2FA, compatible with Google Authenticator, prevents credential leaks.';
  D['bcrypt 哈希'] = 'bcrypt Hashing';
  D['Token 使用 bcrypt 哈希验证，抵御暴力破解与彩虹表攻击。'] = 'Tokens verified with bcrypt hashing, resistant to brute-force and rainbow table attacks.';
  D['IP 智能封锁'] = 'IP Intelligent Blocking';
  D['10 分钟内验证码错误 3 次自动封锁 IP，阻断自动化爆破。'] = 'Auto-block IP after 3 wrong code attempts in 10 minutes, stopping automated attacks.';
  D['恢复码机制'] = 'Recovery Codes';
  D['生成 8 个一次性恢复码，设备丢失时安全找回账户。'] = 'Generate 8 one-time recovery codes for safe account recovery if device is lost.';
  D['AES-256-GCM 加密'] = 'AES-256-GCM Encryption';
  D['TOTP secret 等敏感数据加密存储，密钥泄露也无法直接读取。'] = 'Sensitive data like TOTP secrets are encrypted. Even with a leaked key, data remains unreadable.';
  D['通知不上云'] = 'Stay Local';
  D['所有通知、短信、通讯录仅在本地处理与推送，不会上传到任何服务器。推送只经你自己配置的 Webhook 或 SMTP 邮件通道发出。仅崩溃统计（腾讯 Bugly）会采集必要的崩溃堆栈、设备型号、系统版本用于修复问题。'] = 'All notifications, SMS, contacts processed locally. Push goes only through your configured Webhook or SMTP email. Only Bugly collects minimal crash data (stack trace, device model, OS version) for bugfixing.';
  D['现代、可靠的工程底座'] = 'Modern, Reliable Engineering Foundation';
  D['跨端 Flutter + 原生 Kotlin 后台服务 + Node.js 更新服务，全链路开源可审计。'] = 'Cross-platform Flutter + native Kotlin background service + Node.js update server. Full-stack open source, fully auditable.';
  D['现在，就让通知流动起来'] = 'Let Notifications Flow';
  D['下载最新版 APK，几分钟完成配置，再也不错过任何一条重要消息。'] = 'Download the latest APK, configure in minutes, never miss an important message again.';
  D['下载 Android APK'] = 'Download Android APK';
  D['下载 APK'] = 'Download APK';
  D['全部历史版本'] = 'All Releases';
  D['产品'] = 'Product';
  D['功能特性'] = 'Features';
  D['安全加固'] = 'Security';
  D['下载'] = 'Download';
  D['资源'] = 'Resources';
  D['GitHub 仓库'] = 'GitHub Repository';
  D['贡献指南'] = 'Contributing Guide';
  D['安全政策'] = 'Security Policy';
  D['反馈问题'] = 'Report Issue';
  D['© 2026 幻念团队 fnthinklevi · 通知推送助手'] = '© 2026 fnthinklevi · NoticeTransmit';
  D['打开菜单'] = 'Open Menu';
  D['关闭菜单'] = 'Close Menu';
  D['返回顶部'] = 'Back to Top';
  // FAQ
  D['为什么有时候收不到推送？'] = 'Why do I sometimes miss pushes?';
  D['请依次检查：① 通知访问权限是否开启；② 是否已忽略电池优化（应用会在首次启用时引导）；③ 前台服务是否运行；④ 厂商自启动 / 后台权限是否放行；⑤ Webhook 地址是否正确（设置页可测试）；⑥ 是否被应用筛选或关键词过滤拦截。'] = 'Check: ① Notification access granted; ② Battery optimization ignored; ③ Foreground service running; ④ OEM auto-start / background permissions allowed; ⑤ Webhook URL correct (test in settings); ⑥ Not filtered by app selection or keywords.';
  D['需要 root 或特殊权限吗？'] = 'Does it require root?';
  D['无需 root。仅需授予通知监听权限，并按需开启短信 / 来电识别、忽略电池优化、开机自启等常规权限即可稳定运行。'] = 'No root needed. Only notification listener permission is required, plus optional SMS/call permissions, battery optimization ignore, and auto-start for stable operation.';
  D['是免费的吗？开源吗？'] = 'Is it free? Open source?';
  D['完全免费，且在 GitHub 开源（MIT 许可，供学习交流使用）。欢迎提交 Issue 与 Pull Request 参与共建。'] = 'Completely free and open source on GitHub (MIT License). Issues and Pull Requests welcome!';

  // lang toggle 按钮文字（在 applyLang 中直接处理，无需入字典）
  // D['English'] = '中文';  // 移除：避免长句翻译后再次被此 key 替换
  // 版本号与文件大小由 index.html 内联脚本动态获取（同源 API → notice.fnthink.top → GitHub Releases），
  // 文本语言感知生成，不再依赖本字典按发版更新；此处仅覆盖「三源全部失败」时的中性占位。
  D['版本 --'] = 'Version --';
  D['约 -- MB'] = '~-- MB';
  // feature cards — updated v1.5.50
  D['推送模板引擎'] = 'Push Template Engine';
  D['text / markdown / json / xml 四种格式自定义，%appName% 等变量占位符自动替换，每个通道独立配置。'] = 'Custom text / markdown / json / xml formats, %appName% placeholder auto-replacement, configurable per channel.';
  D['一键暂停推送'] = 'One-Tap Pause Push';
  D['前台通知栏按钮或桌面小部件一键暂停 / 恢复推送，监听继续、仅停 Webhook，状态重启后恢复。小部件适配国内外主流品牌手动添加。'] = 'Pause / resume push via the foreground notification button or home-screen widget. Listening continues, only Webhook sending pauses. State persists across restart. Widgets must be added manually on major brands.';
  // feature cards & security — v1.5.64 backup & restore
  D['配置备份与恢复'] = 'Config Backup & Restore';
  D['一键将通道 / 规则 / 关键词等全部配置加密导出为 .nbackup 文件（AES-256-GCM + PBKDF2 口令派生），换机重装输入口令即可还原，覆盖或仅补空缺由你决定。'] = 'Export all configs (channels / rules / keywords) encrypted as a .nbackup file (AES-256-GCM + PBKDF2 key derivation). Restore with your passphrase after switching or reinstalling — overwrite or fill gaps, your choice.';
  // ── v1.5.69 官网内容 ──
  D['IF 条件组合 + THEN 动作配置，按通知优先级（高/中/低）分级处理——静默忽略 / 仅记录 / 定时与延迟推送 / 立即推送 / 同应用合并推送（可设窗口期，支持满 N 条提前触发与按会话分组）；内置验证码优先、广告拦截、夜间免打扰等默认规则，开箱即用。'] = 'IF condition + THEN action, tiered by notification priority (high/medium/low) — silent ignore / record only / scheduled & delayed push / push now / same-app merged push (configurable window, early flush at N items, group by conversation). Built-in rules for OTP priority, ad blocking, nighttime DND — ready out of the box.';
  D['推送历史完整保存于本地（无条数上限），支持全量搜索与按日 / 时间段 / 应用 / 包名 / 送达状态筛选，详情查看与导出，随时回溯每一条通知去向；失败记录支持多选批量补推。'] = 'Push history is fully saved locally with no cap — full-history search with day / time-range / app / package / delivery-status filters, detail view, and export. Track every notification; failed records support multi-select batch re-push.';
  D['text / markdown / json / xml 四种格式自定义，%appName% 等变量占位符自动替换，聚合推送额外提供 %count%（条数）与 %titles%（成员标题摘要）变量，每个通道独立配置。'] = 'Custom text / markdown / json / xml formats, %appName% placeholder auto-replacement, plus %count% (item count) and %titles% (member title digest) for merged pushes — configurable per channel.';
  D['一键将通道 / 规则 / 关键词 / 电池规则 / 设备名 / 主题语言等 11 类配置加密导出为 .nbackup 文件（AES-256-GCM + PBKDF2 口令派生），换机重装输入口令即可还原，覆盖或仅补空缺由你决定；备份格式 v2 向后兼容 v1。'] = 'Export 11 categories of configs (channels / rules / keywords / battery rules / device name / theme & language) encrypted as a .nbackup file (AES-256-GCM + PBKDF2 key derivation). Restore with your passphrase after switching or reinstalling — overwrite or fill gaps, your choice. Backup format v2 is backward compatible with v1.';
  D['规则测试器'] = 'Rule Tester';
  D['输入模拟通知（应用 + 标题 / 内容 / 优先级），实时展示「过滤 → 规则匹配 → 最终动作」完整命中链路，规则为什么不生效一眼看清。'] = 'Enter a simulated notification (app + title / content / priority) and see the full trace in real time — filter → rule matching → final action. See at a glance why a rule did or did not fire.';
  D['推送可靠性 · 自动重试与补扫'] = 'Push Reliability · Auto-retry & Re-scan';
  D['推送失败自动重试（网络恢复 / 服务重启时重发最近失败项）；服务被系统回收后启动时自动补扫通知栏中未处理的驻留通知（最长回溯 6 小时），长时间锁屏后台也少漏通知。'] = 'Failed pushes retry automatically (resent on network recovery / service restart); after the OS recycles the service, startup re-scans still-visible notifications against a persisted watermark (up to 6 hours back) — far fewer missed notifications during long screen-off periods.';
  D['安装包完整性校验 sha256'] = 'APK Integrity Check (sha256)';
  D['应用内更新下载完成后、安装前先比对 version.json 下发的 sha256，不一致即删除并阻止安装——防 CDN 传输损坏或途中篡改，与签名校验（可信根）双层互补。'] = 'After an in-app update is downloaded, the APK sha256 from version.json is verified before installation — mismatches are deleted and blocked, protecting against CDN corruption or in-transit tampering. Complements the signature check (root of trust).';

  D['配置备份加密'] = 'Encrypted Config Backup';
  D['备份文件以 AES-256-GCM 认证加密、PBKDF2（210k 迭代）派生密钥，口令错误或密文被篡改均无法解密。'] = 'Backups are AES-256-GCM authenticated-encrypted with PBKDF2 (210k iterations) key derivation; wrong passphrase or tampered ciphertext cannot be decrypted.';
  D['一键暂停推送'] = 'One-Tap Pause';
  D['前台通知栏按钮或桌面小部件一键暂停 / 恢复推送，监听继续、仅停 Webhook，状态重启后恢复。小部件 2×2/4×2 视觉焕新，支持系统添加弹窗预览；不支持一键添加的桌面自动弹出分品牌分步引导（小米/华为/OPPO/vivo/三星等）。'] = 'One-tap pause/resume from the foreground notification button or home-screen widget — listening continues, only Webhooks pause; state survives restarts. Widgets redesigned (2×2/4×2) with system add-dialog preview; launchers without one-tap pinning get a per-brand step-by-step guide (Xiaomi/Huawei/OPPO/vivo/Samsung, etc.).';
  D['短信监听设置中心'] = 'SMS Monitoring Center';
  D['监听短信 / 验证码监听 / 监听卡选择三大开关集中管理，单卡设备自动灰化选卡；卡槽过滤同时作用于短信与来电，推送正文可附「卡1，运营商」双语信息行。'] = 'Centralized switches for SMS listening / OTP listening / SIM selection; SIM choice is greyed out on single-SIM devices. SIM filtering applies to both SMS and calls, and pushed messages can carry a bilingual SIM line (e.g., SIM 1, Carrier).';
  D['所有通知、短信、通讯录仅在本地处理与推送，不会上传到任何服务器。推送只经你自己配置的 Webhook 或 SMTP 邮件通道发出。崩溃统计（腾讯 Bugly）默认关闭，仅在你在应用内主动开启后采集必要的崩溃堆栈、设备型号、系统版本用于修复问题，可随时关闭。'] = 'All notifications, SMS, and contacts are processed and pushed locally only — nothing is uploaded to any server. Pushes go exclusively through your own Webhook or SMTP channels. Crash reporting (Tencent Bugly) is off by default; only if you enable it in-app does it collect crash stack traces, device model, and OS version for troubleshooting, and you can turn it off anytime.';
  D['不会。所有通知、短信、通讯录仅在本地监听、处理与推送，不会上传到任何服务器。推送只通过你自行配置的 Webhook 或 SMTP 邮件通道发出，开发者不存储任何推送内容。崩溃统计（腾讯 Bugly）默认关闭，仅在你主动开启后采集崩溃堆栈用于修复问题，可随时关闭。'] = 'No. All notifications, SMS, and contacts are monitored, processed, and pushed locally only — nothing is uploaded to any server. Pushes go exclusively through your own Webhook or SMTP channels, and the developer never stores any pushed content. Crash reporting (Tencent Bugly) is off by default; only if you enable it does it collect crash stack traces for troubleshooting, and you can turn it off anytime.';
  D['打开菜单'] = 'Open menu';
  D['下载 APK'] = 'Download APK';
  D['返回顶部'] = 'Back to top';

  // ── 当前语言 ──
  var lang = localStorage.getItem('lang');
  if (!lang) lang = (navigator.language || '').startsWith('zh') ? 'zh' : 'en';

  // ── 存储原始文本用于恢复中文 ──
  // 用 Map 而非普通对象：对象 key 会被 toString 强转（Text 节点都是 "[object Text]"），
  // 导致 originals[node] 互相覆盖，所有节点最终还原成同一个值
  var originals = new Map();
  // 属性原始值：Element → { attr: 原始文本 }（title / aria-label / alt / placeholder）
  var attrOriginals = new Map();

  // 中文 → 英文替换（按 key 长度降序，先长句后短词），文本节点与属性共用
  function zhToEn(text) {
    var keys = Object.keys(D).sort(function(a, b) { return b.length - a.length; });
    var replaced = text;
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i];
      if (replaced.indexOf(k) !== -1) replaced = replaced.split(k).join(D[k]);
    }
    return replaced;
  }

  // 翻译/恢复元素的 title / aria-label / alt / placeholder 属性
  function applyAttrs(l) {
    var els = document.querySelectorAll('[title],[aria-label],[alt],[placeholder]');
    var attrs = ['title', 'aria-label', 'alt', 'placeholder'];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      for (var j = 0; j < attrs.length; j++) {
        var a = attrs[j];
        if (!el.hasAttribute(a)) continue;
        var cur = el.getAttribute(a);
        if (!cur) continue;
        var rec = attrOriginals.get(el);
        if (!rec) { rec = {}; attrOriginals.set(el, rec); }
        if (!(a in rec)) rec[a] = cur; // 首次记录原始值
        if (l === 'en') {
          // 始终从原始值出发替换，重复执行幂等
          el.setAttribute(a, zhToEn(rec[a]));
        } else {
          el.setAttribute(a, rec[a]);
        }
      }
    }
  }

  function walkTextNodes(root, fn) {
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null, false);
    var node;
    while (node = walker.nextNode()) {
      // 跳过 script/style 标签内的文本
      if (node.parentNode && (node.parentNode.tagName === 'SCRIPT' || node.parentNode.tagName === 'STYLE')) continue;
      fn(node);
    }
  }

  function applyLang(l) {
    lang = l;
    localStorage.setItem('lang', l);
    document.documentElement.lang = l === 'zh' ? 'zh-CN' : 'en';

    if (l === 'en') {
      // 切换到英文：遍历所有文本节点，用字典替换
      walkTextNodes(document.body, function(node) {
        var text = node.textContent;
        if (!text || !text.trim()) return;
        // 跳过纯数字/符号/空格
        if (!/[\u4e00-\u9fff]/.test(text)) return;
        // 保存原始文本
        if (!originals.has(node)) originals.set(node, text);
        // 按字符数降序排列键（先匹配长句，避免短字符串提前替换）
        var keys = Object.keys(D).sort(function(a,b){return b.length - a.length;});
        var replaced = text;
        for (var i = 0; i < keys.length; i++) {
          var k = keys[i];
          if (replaced.indexOf(k) !== -1) {
            replaced = replaced.split(k).join(D[k]);
          }
        }
        node.nodeValue = replaced;
      });
    } else {
      // 切换到中文：恢复原始文本
      walkTextNodes(document.body, function(node) {
        if (originals.has(node)) {
          node.nodeValue = originals.get(node);
        }
      });
    }

    // 翻译/恢复 title / aria-label / alt / placeholder 属性
    applyAttrs(l);

    // 更新语言切换按钮文字
    var btn = document.getElementById('langToggle');
    if (btn) btn.textContent = l === 'zh' ? 'English' : '中文';

    // 更新 <title> 和 <meta> description
    document.title = l === 'zh'
      ? '通知推送助手 · 让每条通知，抵达每个平台'
      : 'NoticeTransmit · Every Notification, Every Platform';
    var metaDesc = document.querySelector('meta[name="description"]');
    if (metaDesc) {
      metaDesc.content = l === 'zh'
        ? '通知推送助手 —— Android 通知监听与推送工具。支持 Webhook（企业微信 / 钉钉 / 飞书 / Telegram / Bark / 自定义）和 SMTP 邮件多通道，具备应用筛选、关键词过滤、可视化规则引擎、规则测试器、电量提醒等功能。开源、免费、本地处理。'
        : 'NoticeTransmit — Android notification listener & push tool. Webhook (WeCom / DingTalk / Feishu / Telegram / Bark / Custom) + SMTP email multi-channel. App filtering, keyword filtering, visual rule engine, rule tester, battery alerts. Open source, free, local processing.';
    }
  }

  function toggleLang() {
    applyLang(lang === 'zh' ? 'en' : 'zh');
  }

  window._i18n = { applyLang: applyLang, toggleLang: toggleLang };
  document.addEventListener('DOMContentLoaded', function() { applyLang(lang); });
})();
