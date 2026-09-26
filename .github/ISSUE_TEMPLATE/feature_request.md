---
name: 功能请求 / Feature request
about: 为此项目提出一个想法 / Suggest an idea for this project
title: "[Feature] "
labels: ''
assignees: ''

---

**你的功能请求是否与某个问题相关？请描述。**
**Is your feature request related to a problem? Please describe.**
清晰简洁地描述问题是什么。例如：当 [...] 时我总是感到困扰。
A clear and concise description of what the problem is. Ex. I'm always frustrated when [...]

**希望的功能落点 / Where the feature should live**
- [ ] 规则约束与推送链路 / Rule constraints & push pipeline
- [ ] 通道类型（Webhook / 邮件 / 企业微信、飞书等自建应用） / Channel types (Webhook / email / WeCom, Feishu app channels)
- [ ] 短信与验证码识别 / SMS & verification-code parsing
- [ ] 温度、电量等系统监控 / Temperature, battery and other system monitoring
- [ ] 备份恢复与历史查询 / Backup, restore & history
- [ ] 应用内更新与服务端 / In-app update & server
- [ ] 官网 / 文档 / Website & docs
- [ ] 界面、主题与本地化（中/英） / UI, theme & localization (zh/en)
- [ ] 其他 / Other:

**描述你希望的解决方案 / Describe the solution you'd like**
清晰简洁地描述你希望发生的事情。若涉及新权限或新的数据采集，请说明必要性与替代方案。
A clear and concise description of what you want to happen. If it requires new permissions or new data collection, explain why it is necessary and what the alternative would be.

**描述你考虑过的替代方案 / Describe alternatives you've considered**
清晰简洁地描述你考虑过的任何替代解决方案或功能。
A clear and concise description of any alternative solutions or features you've considered.

**影响范围与兼容性 / Impact & compatibility**
 - 是否需要改动本地数据库结构（表/字段、`dbVersion` 迁移）？
   Does it change the local database schema (tables/columns, `dbVersion` migration)?
 - 是否影响既有规则/通道的行为或推送格式（老配置是否仍可用）？
   Does it change existing rule/channel behavior or payload format (will old configs keep working)?
 - 是否需要新增/调整 MethodChannel 方法、服务端接口或环境变量？
   Does it need new/changed MethodChannel methods, server endpoints or environment variables?
 - 是否涉及隐私边界（通知正文、短信内容、崩溃上报）？
   Does it touch privacy boundaries (notification bodies, SMS content, crash reporting)?

**附加上下文 / Additional context**
在此处添加有关此功能请求的任何其他上下文或截图。
Add any other context or screenshots about the feature request here.

**你愿意提交 PR 吗？/ Are you willing to send a PR?**
- [ ] 是 / Yes（请先阅读 CONTRIBUTING.md / CONTRIBUTING-en.md：PR 门禁要求
  `flutter analyze`、`flutter test`、`:app:testDebugUnitTest`、`:app:lintDebug`、`server` 的
  `npm test` 与三路格式闸门 `bash .github/scripts/check_format.sh` 全部通过）
- [ ] 否 / No
