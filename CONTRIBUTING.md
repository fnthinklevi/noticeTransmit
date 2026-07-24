# 贡献指南（CONTRIBUTING）

[English](CONTRIBUTING-en.md) / 中文

感谢你关注 **通知推送助手（noticeTransmit）**！本文档说明如何在本项目中开发、提交与发版。

> 项目主文档：[README.md](README.md)（中文） / [README-en.md](README-en.md)（English）

---

## 1. 行为准则

本项目遵循[贡献者行为准则](CODE_OF_CONDUCT-zh.md)。参与即表示你同意遵守该准则。

- 请保持友善、尊重，聚焦技术讨论。
- 提交内容须为你本人原创或已获授权，不得包含侵权、恶意或违法代码。
- 报告安全漏洞请通过私密渠道联系维护者，勿在公开 Issue 泄露利用细节。

---

## 2. 开发环境要求

本项目使用 **AGP 9.3.0 + Gradle 9.5.0**，对工具链有最低版本要求：

| 工具 | 最低版本 | 说明 |
|------|----------|------|
| Flutter SDK | 3.44.0 | 自带 Dart 3.12.0 |
| Android Gradle Plugin | 9.3.0 | 不支持 8.x 及以下 |
| Gradle | 9.5.0 | 见 `gradle-wrapper.properties` |
| Kotlin | 2.3.20 | 见 `settings.gradle.kts` |
| JDK | 21 | AGP 9.x 要求 |
| Android SDK | minSdk 24 / compileSdk 37 | 目标 SDK 37 |
| Node.js | 18+ | 仅服务端 `server/` 需要 |

环境准备：

```bash
# Flutter 端
flutter pub get
flutter analyze          # 无 error 才能提交

# 服务端（可选，仅改 server/ 时需要）
cd server && npm install
```

---

## 3. 获取与本地运行

```bash
git clone <your-fork-url> noticeTransmit
cd noticeTransmit
flutter pub get
flutter run               # 连接 Android 设备/模拟器调试

# 启动更新服务（另开终端）
cd server && npm start    # 默认端口 3456，访问 /health 验证
```

---

## 4. 分支与提交流程

1. **Fork** 本仓库并克隆到本地。
2. 从 `main`（或 `develop`）切出 **功能分支**：
   - 功能：`feat/简短描述`，如 `feat/icon-preview`
   - 修复：`fix/简短描述`，如 `fix/battery-cast-crash`
   - 重构/文档：`refactor/...`、`docs/...`
3. 保持分支**单一目标**，一次 PR 解决一类问题。
4. 提交前完成本地校验（见第 6 节）。
5. 发起 PR 到 `main`，描述：改动目的、影响范围、自测情况。
6. 等待 CI（GitHub Actions）通过后再合并。

### 提交信息（Commit Message）

建议遵循 Conventional Commits：

```
<type>(<scope>): <subject>

<可选正文>
```

- `type`：`feat` / `fix` / `refactor` / `docs` / `style` / `test` / `chore`
- `scope`（可选）：`flutter` / `android` / `server` / `docs`
- 示例：`fix(android): 修复电量规则跨进程重建后 webhook 静默失效`

---

## 5. 代码规范

### 5.1 Flutter / Dart（`lib/`）

- **必须通过** `dart format lib/` 与 `flutter analyze`（CI 以 `--set-exit-if-changed` 检查格式，`error` 级问题直接失败）。
- **空安全优先**：禁止对可能为空的数据做硬转换。本项目曾因 `rule['type'] as String` 在旧数据缺字段时整页崩溃——读取外部/存储数据时统一用 `as Type? ?? 默认值` 或 `map['x'] as int? ?? 0`。
- **主题与配色**：统一使用 `AppColors`（Cupertino 风格语义色）与 `AppThemeColors`（`ThemeExtension`），**不要硬编码颜色**，否则深色模式会错。
- **跨端通信**：Flutter ↔ Android 通过 `MethodChannel`（`com.fnthink.notice/notification`）通信，方法名在 `platform_channel.dart` 与原生侧保持一一对应。
- **状态与依赖**：使用 `get_it` 注入的 Service 类，不要在 Widget 中直接 new 单例。
- 文件较大（如 `main_page.dart`、`rule_edit_page.dart`）的改动请确保不破坏既有导航与底部提示条（`_pushPage` / `_showInfo`）行为。

### 5.2 Android 原生（Kotlin，`android/`）

- 协程统一走 `Dispatchers.IO`，网络请求经 `NetworkClient` / `OkHttp`。
- 后台逻辑位于 `NotificationMonitorService` 及各模块（`BatteryMonitor` / `NotificationProcessor` / `WebhookSender` 等），新增能力优先复用既有模块，避免重复实现。
- 图标别名（`activity-alias`）与 `lib` 侧 `IconOption` key 必须**严格对齐**（当前共 17 个）。
- 注意 `onDestroy` 不应留下永久失效的全局状态（本仓库已修复 `NetworkClient.isActive` 的同类问题）。

### 5.3 服务端（`server/`，Node.js + Express）

- 改动后请执行 `node --check server.js` 确认语法，并本地 `npm start` 后访问 `/health` 自测。
- 管理接口（`/api/admin/*`）改动需同步校验鉴权与请求体。
- **不要在代码或配置中硬编码密钥**；密钥来自环境变量（见第 7 节）。

---

## 6. 提交前本地校验清单

```bash
# Flutter 端
flutter pub get
dart format lib/
flutter analyze                  # 仅允许风格提示，不允许 error
flutter test                    # 若有单元测试

# 服务端（仅改 server/ 时）
cd server
node --check server.js
npm start &                     # 临时启动
curl -s http://127.0.0.1:3456/health
kill %1
```

> CI 还会运行 `dart_code_metrics` 与覆盖率统计；本地可用
> `dart run dart_code_metrics:metrics analyze lib/` 提前自查。

---

## 7. 安全与隐私（重要）

本项目是**通知监听与推送工具**，安全与隐私是底线：

- **通知内容只在本地处理与推送**，不上传到任何第三方服务器（除非用户自行配置的 Webhook）。仅 Bugly 采集最小必要的崩溃统计（堆栈、设备型号、系统版本、应用版本）。
- 不要在日志、崩溃上报或存储中写入通知正文、短信、通讯录等隐私数据。
- **服务器密钥管理（`.env`）**：`server/.env` 已被 `.gitignore` 忽略，不会进入
  仓库；仓库仅保留 `.env.example`（占位/说明）。真实 `.env` 由部署方本地或 CI
  Secret 提供，**切勿将生产密钥（`ADMIN_TOKEN_HASH`、`ENCRYPTION_KEY` 等）提交到仓库**。
  新增环境变量请在 `server/README.md` 的环境变量表中补充。
- 服务端加密（`ENCRYPTION_KEY`）须为 **64 位十六进制**（AES-256-GCM），非法格式会被忽略并以明文存储，提交前请自检。
- CORS 默认仅放行无 `Origin` 的原生请求；跨域 Web 后台访问需显式配置 `ALLOWED_ORIGINS` 白名单。

### 7.1 Android 发布签名密钥（APK）

APK 发布签名遵循**源码零密钥**原则：任何被 Git 跟踪的源文件都不得包含
keystore 路径、密码或别名明文。

- **本地构建**：在 `android/key.properties`（已被 `android/.gitignore` 忽略）中填写
  `storeFile` / `storePassword` / `keyAlias` / `keyPassword`，由
  `android/app/build.gradle.kts` 读取。该文件不进仓库，**切勿提交**。
  仓库内提供无密钥的占位模板 `android/key.properties.example`（可安全提交），
  本地请复制它为 `key.properties` 后再填入真实值。
- **CI 构建**：通过 GitHub Actions Secrets 注入 `KEYSTORE_BASE64`、`KEYSTORE_FILE`、
  `KEYSTORE_PASSWORD`、`KEY_ALIAS`、`KEY_PASSWORD`；工作流将 `KEYSTORE_BASE64`
  解码为 keystore 文件后供 `build.gradle.kts` 使用。
- **缺失即报错**：若既无环境变量也无 `key.properties`，`build.gradle.kts` 会主动抛出
  `GradleException` 中止构建，**绝不使用硬编码兜底密码**。
- **轮换策略**：keystore 文件或密码一旦泄露，立即生成新 keystore 并同步更新本地
  `key.properties` 与 CI Secrets；建议定期轮换并记录失效时间。
- **`.gitignore` 必须覆盖**：`*.jks`、`*.keystore`、`android/key.properties` 等已在
  忽略清单中，提交前用 `git status` 确认无密钥文件被跟踪。

---

## 8. 版本发布流程（五更新流程）

> 仅维护者执行。客户端每发一版，须同步更新记录、版本配置与产物命名。

1. **代码冻结**：完成改动，`dart format` + `flutter analyze` 无 error。
2. **升版本号**：修改 `pubspec.yaml` 的 `version: X.Y.Z+NN`
   （`versionName` 与 `versionCode` 同步递增，如 `1.5.38+72`）。
3. **构建产物**：
   ```bash
   flutter build apk --release --target-platform android-arm64
   ```
4. **记录体积**：取 APK 字节大小，将产物重命名为
   `noticeX.Y.Z.apk` 并放入 `server/public/apks/`；把字节数填入
   `server/data/version.json` 的 `fileSize`。
5. **更新版本配置** `server/data/version.json`：
   `latestVersion` / `latestBuild` / `changelog`。
6. **追加更新记录**：在 Changelog 顶部新增 `### vX.Y.Z - 日期`
   条目，按「功能 / 修复 / 服务端 / 文档」分类说明。
7. **同步文档**：如涉及图标、权限、配置等，更新 `README.md` 中对应说明。
8. **部署服务端**：将 `server/server.js`、`server/data/version.json` 等更新文件同步到服务器并重启（详见 [server/README.md](server/README.md)）。

---

## 9. 许可证

本项目以 **MIT License** 开源（见 [LICENSE](LICENSE)）。提交即表示你同意以该许可证发布你的贡献。

---

再次感谢你的参与！如有疑问，欢迎提 Issue 讨论。
