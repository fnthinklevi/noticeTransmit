---
name: Bug 报告 / Bug Report
about: 创建报告以帮助我们改进 / Create a report to help us improve
title: "[Bug] "
labels: ''
assignees: ''

---

<!--
提示 / Tips：
- 请勿在公开 Issue 中粘贴通知正文、短信内容或其他个人隐私数据。
  Please do not paste notification bodies, SMS content or other private data into a public issue.
- 安全类问题（鉴权、服务端漏洞等）请按 SECURITY.md / SECURITY-en.md 的私密渠道报告。
  Security issues must be reported through the private channel described in SECURITY.md.
-->

**描述 Bug / Describe the bug**
清晰简洁地描述该 bug 是什么。
A clear and concise description of what the bug is.

**复现步骤 / To Reproduce**
重现此行为的步骤：
Steps to reproduce the behavior:
1. 前往 '...' / Go to '...'
2. 点击 '....' / Click on '....'
3. 发现错误 / See error

**预期行为 / Expected behavior**
清晰简洁地描述你期望发生的事情。
A clear and concise description of what you expected to happen.

**受影响的功能面 / Affected area**
- [ ] 通知监听与转发 / Notification listening & forwarding
- [ ] 规则约束（关键词/聚合/延迟等） / Rule constraints (keywords, merge, delay, …)
- [ ] 短信识别 / SMS verification-code parsing
- [ ] 通道配置（Webhook / 邮件 / 自建应用） / Channels (Webhook / email / app channels)
- [ ] 温度与电量监控 / Temperature & battery monitoring
- [ ] 备份与恢复 / Backup & restore
- [ ] 应用内更新 / In-app update
- [ ] 界面与本地化 / UI & localization
- [ ] 服务端 / 管理后台 / Server & admin console
- [ ] 其他 / Other:

**环境信息 / Environment:**
 - 设备型号与厂商 / Device model & vendor: [如 e.g. Xiaomi 14 / HyperOS；华为、OPPO、vivo、魅族、三星等请注明]
 - Android 版本（API 级别）/ Android version (API level): [如 e.g. Android 15 (API 35)；本应用最低支持 Android 7.0（minSdk 24）]
 - 应用版本 / App version: [「更多」页底部显示，如 e.g. v1.5.74]
 - 构建号 / Build number: [如已知，如 e.g. 113（对应 pubspec 的 1.5.74+113；连接 adb 抓 logcat 时，
   tag `flutter` 的 "Version from native: 1.5.74 build 113" 一行可见 / when logcat is attached, the
   `flutter` tag prints "Version from native: ... build ...")]
 - 安装来源 / Install source: [应用内更新 / in-app update、GitHub Release、官网 APK、其他]
 - 语言设置 / App language: [中文 / English]
 - 是否有其他应用干扰 / Other apps interfering: [如 e.g. 是/否，省电优化、清理类工具等]
 - 厂商权限是否已授予 / Vendor permissions granted: [自启动、后台活动、电池白名单等 / auto-start, background activity, battery whitelist]

**诊断日志与崩溃上报状态 / Diagnostic log & crash reporting status**
 - 开发者诊断日志 / Diagnostic logging: [关闭（默认）/ 开启 —— 在「更多」页连点版本号 7 次切换，不含通知标题与正文]
   Toggle by tapping the version number 7 times on the More page. Off by default; never records notification titles or bodies.
   如已开启，请附上复现时段的 logcat（过滤 tag：`DiagLog`、`NotificationMonitorService`）。
   If enabled, attach logcat for the reproducing window (filter tags: `DiagLog`, `NotificationMonitorService`).
 - 崩溃上报（腾讯 Bugly）/ Crash reporting (Tencent Bugly): [关闭（默认）/ 开启 —— 「更多」页内主动开启后才上传崩溃堆栈等最小信息]
   Off by default; only enabled after you turn it on in the More page.

**截图 / Screenshots**
如适用，请添加截图以帮助解释你的问题（请先遮挡通知正文等隐私内容）。
If applicable, add screenshots to help explain your problem (redact notification bodies and other private content first).

**日志 / Logs**
「历史」页可导出记录（JSON）。如需附到 Issue，请务必先删除其中的通知正文。
Push history can be exported as JSON from the History page. Redact notification bodies before attaching it.

**附加上下文 / Additional context**
在此处添加有关此问题的任何其他上下文（例如最近是否升级到该版本、是否使用了自建 Webhook/私有化部署等）。
Add any other context about the problem here (e.g. whether it appeared right after an update, whether a private/self-hosted endpoint is used).
