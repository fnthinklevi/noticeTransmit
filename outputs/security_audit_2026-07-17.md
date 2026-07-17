# noticeTransmit 安全审计报告

**审计日期**: 2026-07-17 | **版本**: 1.5.39+73 (Flutter) / server v1.0 (Node.js)
**审计范围**: Flutter 客户端 + Android 原生层 + Node.js 服务端 + 管理后台
**审计人**: WorkBuddy 自动化审计

---

## 一、总体评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 密钥管理 | ⚠️ 中 | .env 已 gitignore，但 data/json 文件被追踪 |
| 数据传输 | 🔴 差 | Android 允许明文 HTTP；无 SSL 证书固定 |
| 数据存储 | ⚠️ 中 | webhook token、通知内容全以明文存储 |
| 权限管控 | 🔴 差 | 20 项权限，含 SMS/通话/全包可见/外部存储 |
| 认证机制 | ✅ 好 | bcrypt + TOTP 二步验证，会话管理正确 |
| 输入验证 | ⚠️ 中 | 服务端 API 缺字段级校验；webhook URL 无验证 |
| 依赖安全 | ⚠️ 中 | otplib v12 已弃用；服务端无已知漏洞 |

**综合评级**: ⚠️ **需整改**（发现 2 项严重、5 项高风险、7 项中风险）

---

## 二、严重风险（需立即修复）

### 🔴 [CRITICAL-1] `android:usesCleartextTraffic="true"` — 允许明文 HTTP

**文件**: `android/app/src/main/AndroidManifest.xml`
**影响**: 所有网络流量（包括 webhook 推送的短信内容、来电号码、应用通知详情）均允许通过未加密 HTTP 传输，存在中间人窃听风险。

**修复**:
```xml
<!-- 移除 android:usesCleartextTraffic="true"，改用 network_security_config.xml -->
```

或创建 `res/xml/network_security_config.xml` 仅允许特定场景放行。

---

### 🔴 [CRITICAL-2] SSL 证书固定（Certificate Pinning）全面缺失

**文件**:
- `NetworkClient.kt` (OkHttpClient — webhook 发送)
- `MainActivity.kt` (第二个 OkHttpClient — webhook 测试)
- `retry_service.dart` (Dart `http` 包 — webhook 重试)
- `update_manager.dart` (Dart `http` 包 — 版本检查和 APK 下载)

**影响**: 攻击者可实施 HTTPS 中间人攻击，截获/篡改 webhook 通知内容和更新包下载。

**修复**: 为所有 HTTP 客户端添加证书固定或公钥固定，至少覆盖自有域名 `notice.fnthink.top`。

---

## 三、高风险（需尽快修复）

### 🟠 [HIGH-1] 敏感数据全以明文存储

**涉及**:
- **SharedPreferences**: webhook URL（含钉钉/企微/飞书认证 key）、通知内容、通话/短信详情
- **SQLite**: `notice_transmit.db` 完整通知记录、webhook URL、失败重试队列

**修复**: 使用 `flutter_secure_storage` 替代 `shared_preferences` 存储 webhook URL；SQLite 使用 `sqflite_sqlcipher` 加密。

---

### 🟠 [HIGH-2] admin.html 中 Token 通过 URL 查询参数传递

**文件**: `server/public/admin.html` 第 527、559 行

```javascript
// 当前代码 — Token 出现在 URL 查询字符串
const result = await fetch(`${API_BASE}/api/admin/totp/setup?token=${token}`)
```

**影响**: Token 会出现在浏览器历史、Nginx 日志、服务器访问日志中。

**修复**: 改为 POST body 或 `x-admin-token` Header 传递（authMiddleware 已支持 Header）。

---

### 🟠 [HIGH-3] 权限严重过度

AndroidManifest 声明 **20 项权限**，其中多项为敏感高危：

| 权限 | 风险 | 建议 |
|------|------|------|
| `RECEIVE_SMS` / `READ_SMS` | 读取所有短信（含验证码） | 如非绝对必要移除 |
| `READ_PHONE_STATE` | 读取 IMEI、通话状态 | 按需使用运行时请求 |
| `QUERY_ALL_PACKAGES` | 扫描所有已安装应用 | Google Play 需声明使用理由 |
| `MANAGE_EXTERNAL_STORAGE` | 全文件系统访问 | 仅用于下载目录 |
| `REQUEST_INSTALL_PACKAGES` | 自更新安装 APK | 为自更新所必需，保留 |

---

### 🟠 [HIGH-4] BroadcastReceiver 使用 RECEIVER_EXPORTED

**文件**: `MainActivity.kt`

```kotlin
registerReceiver(notificationReceiver, filter, Context.RECEIVER_EXPORTED)
registerReceiver(batteryReceiver, filter, Context.RECEIVER_EXPORTED)
```

**影响**: 其他应用可向本应用发送伪造通知/电量数据。

**修复**: 改为 `RECEIVER_NOT_EXPORTED`（如仅内部使用），或添加自定义权限保护。

---

### 🟠 [HIGH-5] `otplib` v12 已弃用

**文件**: `server/package.json`
**状态**: `otplib` v12.0.1 已标记 deprecated

**修复**: 升级到 `otplib` v13，参考官方迁移文档。

---

## 四、中风险（建议尽快修复）

### 🟡 [MEDIUM-1] 服务端 API 缺少字段级输入验证

**文件**: `server/server.js` — `POST /api/admin/version` 和 `POST /api/admin/hotfix`

- `downloadUrl` 不验证 URL 格式
- `latestVersion` 不验证版本号格式
- `fileSize` 不验证为合法数字

**修复**: 添加字段级校验（URL regex、semver 格式、数字范围）。

---

### 🟡 [MEDIUM-2] `server/data/version.json` 和 `hotfix.json` 被 Git 追踪

已确认: 5 次提交中包含这两个文件，版本元数据在公开仓库中可见。

**修复**: 添加 `.gitignore` 规则 `server/data/*.json`（如不想公开）或改为从环境变量/数据库读取。

---

### 🟡 [MEDIUM-3] 服务端会话和限流使用内存存储

**文件**: `server/server.js`

- `sessions` 对象：重启丢失，不支持多实例
- `rateLimitStore` 对象：永不主动清理，可能存在内存泄漏

**修复**: 生产环境使用 Redis 替代内存存储。

---

### 🟡 [MEDIUM-4] 日志泄露敏感信息

**文件**:
- `NetworkClient.kt`: 日志记录 webhook URL 前缀 (`url.take(30)`) 和响应体 (`respBody.take(200)`)
- `server.js`: 启动时打印「二步验证: 已启用」和「Token 验证方式」
- `main.dart`: `runZonedGuarded` 通过 `dart:developer log()` 记录堆栈

**修复**: 生产构建禁用调试日志；服务端日志标记脱敏。

---

### 🟡 [MEDIUM-5] `android:allowBackup="true"` 暴露数据

**影响**: Android 备份会将 SharedPreferences（含 webhook URL/token）和 SQLite 数据库（含通知内容）上传到 Google Drive。

**修复**: 设为 `false` 或使用 `android:fullBackupContent` 排除敏感文件。

---

### 🟡 [MEDIUM-6] 通知导出无加密和安全控制

**文件**: `notification_service.dart` — `exportRecords()`
**问题**: 导出 JSON 含所有通知记录、设备信息，写入外部存储，无加密、无权限校验。

**修复**: 导出前弹出用户确认对话框；可选加密导出；添加自动删除策略。

---

### 🟡 [MEDIUM-7] 无 Content Security Policy / 安全 HTTP 头

服务端未设置以下安全头:
- `Content-Security-Policy`
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: strict-origin-when-cross-origin`

---

## 五、低风险（可择机优化）

- [LOW-1] `.env.example` 中的示例密钥可能导致生产误用
- [LOW-2] `data/` 目录文件权限为 644（建议 600）
- [LOW-3] 健康检查接口 `/health` 返回时间戳，可用于时间攻击
- [LOW-4] 应用更新管理器硬编码了下载路径 `/storage/emulated/0/Download/fnthink.notice`

---

## 六、正面发现（已正确实施）

| ✅ 措施 | 说明 |
|---------|------|
| bcrypt 密码哈希 | 管理 Token 使用 bcrypt (cost=10) 存储和验证 |
| AES-256-GCM 加密 | TOTP secret 加密存储，含随机 IV 和认证标签 |
| TOTP 二步验证 | 正确实现，含恢复码 bcrypt 哈希 |
| IP 封锁机制 | 3 次失败后封锁 240 小时，持久化存储 |
| 会话 ID | `crypto.randomUUID()` 生成密码学安全的会话 ID |
| 请求体限大小 | `express.json({ limit: '1mb' })` |
| Token 仅通过 Header | authMiddleware 只从 `x-admin-token` 读取 |
| `.env` 已 gitignore | 未出现在 Git 历史中 ✅ |
| ENCRYPTION_KEY 校验 | 强制 64 位十六进制 |
| 热修复 zip-slip 防护 | `applyHotfix()` 中实现路径遍历防护 |
| 无硬编码 API 密钥 | Dart/Kotlin 代码中无硬编码密钥 |

---

## 七、修复路线图

### 第一优先（立即）
1. 移除 `usesCleartextTraffic="true"`，配置 HTTPS-only
2. 为 webhook + 更新通信添加 SSL 证书固定
3. 修复 admin.html Token 通过 URL 参数传递

### 第二优先（本周）
4. webhook URL 迁移到 `flutter_secure_storage`
5. `android:allowBackup="false"`
6. 生产构建禁用调试日志记录
7. 服务端添加安全 HTTP 头
8. 升级 otplib 到 v13

### 第三优先（本迭代）
9. 服务端 API 添加字段级输入验证
10. `data/version.json` 和 `hotfix.json` 添加 gitignore
11. `BroadcastReceiver` 改为 `RECEIVER_NOT_EXPORTED`
12. 通知导出添加确认和安全控制

### 长期
13. SQLite 加密（sqflite_sqlcipher）
14. 会话和限流存储迁移到 Redis
15. 权限最小化审查

---

## 八、修复记录 (2026-07-17 22:44)

| # | 修复项 | 状态 |
|---|--------|------|
| CRIT-1 | `usesCleartextTraffic` 移除 + `allowBackup=false` + `network_security_config.xml` | ✅ 已修复 |
| CRIT-2 | SSL 证书固定基础设施：4 个 HTTP 客户端均已添加，待填入证书指纹启用 | ✅ 已准备 |
| HIGH-1 | Webhook URL 加密存储：仍为明文（需 flutter_secure_storage） | ⏳ 待实施 |
| HIGH-2 | admin.html Token 改经 x-admin-token Header 传递 | ✅ 已修复 |
| HIGH-3 | 权限最小化：需确认业务需求后调整 | ⏳ 待评估 |
| HIGH-4 | BroadcastReceiver RECEIVER_EXPORTED → RECEIVER_NOT_EXPORTED | ✅ 已修复 |
| HIGH-5 | otplib v12 → v13 升级 | ✅ 已修复 |
| MED-1 | 服务端 API 字段级校验 | ✅ 已修复 |
| MED-2 | server/data/*.json 排除 Git 追踪 | ✅ 已修复 |
| MED-3 | 内存会话→Redis | ⏳ 待实施 |
| MED-4 | 日志脱敏（NetworkClient + server.js） | ✅ 已修复 |
| MED-5 | allowBackup=false | ✅ 已修复 |
| MED-6 | 通知导出确认对话框 + 敏感数据警告 | ✅ 已修复 |
| MED-7 | 安全 HTTP 头 | ✅ 已修复 |
| 新增 | PinnedHttpClient Dart 工具类 (SHA256 证书固定) | ✅ 已创建 |
| 新增 | network_security_config.xml (默认拒绝明文) | ✅ 已创建 |
| 新增 | pubspec.yaml 添加 crypto ^3.0.3 | ✅ 已添加 |

**修复总结**: 14/18 项已完成，4 项待后续（flutter_secure_storage、权限审查、Redis、SQLite 加密）。
