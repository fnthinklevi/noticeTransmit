# 贡献指南（CONTRIBUTING）

[English](CONTRIBUTING-en.md) / 中文

感谢你关注 **通知推送助手（NoticeTransmit）**！本文档说明如何在本项目中开发、提交与发版。

> 项目主文档：[README.md](README.md)（中文） / [README-en.md](README-en.md)（English）
> 安全政策：[SECURITY.md](SECURITY.md) / [SECURITY-en.md](SECURITY-en.md)

---

## 1. 行为准则

本项目遵循[贡献者行为准则](CODE_OF_CONDUCT-zh.md)。参与即表示你同意遵守该准则。

- 请保持友善、尊重，聚焦技术讨论。
- 提交内容须为你本人原创或已获授权，不得包含侵权、恶意或违法代码。
- 报告安全漏洞请走 [SECURITY.md](SECURITY.md) 第 2 节的私密渠道，勿在公开 Issue 泄露利用细节。

---

## 2. 开发环境要求

本项目使用 **AGP 9.3.0 + Gradle 9.5.0**，对工具链有明确版本要求：

| 工具 | 版本 | 说明 |
|------|------|------|
| Flutter SDK | 3.44.x | `analyze.yml` / `build-apk.yml` 固定 `3.44.4`（stable channel），自带 Dart 3.12.2 |
| Dart SDK | ^3.12.2 | `pubspec.yaml` 的 `environment.sdk` |
| Android Gradle Plugin | 9.3.0 | 见 `android/settings.gradle.kts`，不支持 8.x 及以下 |
| Gradle | 9.5.0 | 见 `android/gradle/wrapper/gradle-wrapper.properties`；请始终用 `./gradlew`，不要用系统 gradle |
| Kotlin | 2.3.20 | 见 `android/settings.gradle.kts` |
| JDK | 21 | AGP 9.x 要求；`compileOptions` 与 `jvmTarget` 均为 21 |
| Android SDK | compileSdk 37 / targetSdk 37 / minSdk 24 | `minSdk = flutter.minSdkVersion`（Flutter 3.44 即 24） |
| Node.js | **24 LTS** | `server/package.json` 的 `engines.node = ">=24"`；CI 与生产（pm2）同为 24。**旧文档中的「Node 18+ / 20」已失效** |
| ktlint | 1.8.0 | 独立 CLI，首次运行由 `check_format.sh` 自动下载到 `~/.cache/ktlint`；规则见仓库根 `.editorconfig` |
| Prettier | 3.9.8 | `server/` 的 devDependency，经 `npm run format` / `npm run format:check` 调用 |

环境准备：

```bash
flutter --version         # 期望 Flutter 3.44.x / Dart 3.12.2
flutter pub get

# 服务端（仅改 server/ 时需要）
cd server && npm ci       # 严格按 package-lock.json 安装
node -v                   # 期望 v24.x
```

补充说明：

- `android/local.properties` 由 Flutter 工具生成（`settings.gradle.kts` 需要其中的 `flutter.sdk`），
  不入库、无需手写。
- **发布签名密钥不是开发前置条件**：本地与 CI 的测试 / lint 任务在无 `android/key.properties`
  时照常放行，详见第 9.1 节。

---

## 3. 获取与本地运行

```bash
git clone <your-fork-url> noticeTransmit
cd noticeTransmit
flutter pub get
flutter run               # 连接 Android 设备/模拟器调试

# 启动更新服务（另开终端）
cd server && npm ci && npm start    # 默认端口 3456（PORT 可覆盖）
curl -s http://127.0.0.1:3456/health # 健康检查验证
```

---

## 4. 分支与提交流程

1. **Fork** 本仓库并克隆到本地。
2. 从 `main`（或 `develop`）切出 **功能分支**：
   - 功能：`feat/简短描述`，如 `feat/icon-preview`
   - 修复：`fix/简短描述`，如 `fix/battery-cast-crash`
   - 重构/文档：`refactor/...`、`docs/...`
3. 保持分支**单一目标**，一次 PR 解决一类问题。
4. 提交前完成本地校验（见第 7 节）。
5. 发起 PR 到 `main`，描述：改动目的、影响范围、自测情况。
6. 等待 CI（`.github/workflows/analyze.yml`）通过后再合并。

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

## 5. 格式闸门：一条脚本管三路

格式化不再是 `dart format` 一件事。**本地与 CI 跑同一支脚本**，避免「本地过了 CI 红」：

```bash
bash .github/scripts/check_format.sh          # 只校验，有违规 exit 1
bash .github/scripts/check_format.sh --fix    # 就地格式化（三路一并修）
```

它覆盖三路：

| 语言 | 工具 | 作用域 / 配置 |
|------|------|----------------|
| Dart | `dart format`（Flutter SDK 自带） | `lib test`（注意：不止 `lib/`） |
| Kotlin | ktlint 1.8.0 独立 CLI（fat jar，不侵入 `build.gradle.kts`） | `android/app/src/**/*.kt`，规则见仓库根 `.editorconfig` |
| 服务端 JS | Prettier 3.9.8 | 复用 `server/package.json` 的 `format` / `format:check`（作用域见 `server/.prettierignore`） |

> `.editorconfig` 刻意关掉了 ktlint 的换行/续行类规则。原因见第 8.3 节：本仓库有大量
> 「按源文本断言」的静态守卫，格式化重排代码会直接改掉守卫的断言语义。

---

## 6. 代码规范

### 6.1 Flutter / Dart（`lib/`）

- **必须通过** `bash .github/scripts/check_format.sh` 与 `flutter analyze`。CI 只在 analyze
  输出里出现 `error •` 时判红，风格提示（info/warning）不阻塞合入。
- **空安全优先**：禁止对可能为空的数据做硬转换。本项目曾因 `rule['type'] as String` 在旧数据缺字段时整页崩溃——读取外部/存储数据时统一用 `as Type? ?? 默认值` 或 `map['x'] as int? ?? 0`。
- **主题与配色**：统一使用 `AppColors`（Cupertino 风格语义色，`lib/theme/app_colors.dart`）与 `AppThemeColors`（`ThemeExtension`，`lib/theme/app_theme.dart`），**不要硬编码颜色**，否则深色模式会错。
- **跨端通信**：Flutter ↔ Android 走单通道 `MethodChannel('com.fnthink.notice/notification')`
  （Dart 侧常量在 `lib/services/platform_channel.dart`）。原生侧按域拆成 5 个 handler
  （`android/app/src/main/kotlin/com/fnthink/notice/channels/` 下的 Config / Device / File /
  Permission / Stats），共 **87** 个方法名，由 `test/services/channel_method_parity_test.dart`
  钉住双端契约（新增/重命名方法必须同时更新 Dart 调用与该测试的期望总数）。
- **状态与依赖**：使用 `get_it` 注入的 Service 类（注册于 `lib/di/service_locator.dart`），不要在 Widget 中直接 new 单例。
- **日志**：`analysis_options.yaml` 启用 `avoid_print`，统一用 `debugPrint`。
- 文件较大（如 `main_page.dart`、`rule_edit_page.dart`）的改动请确保不破坏既有导航与底部提示条（`_pushPage` / `_showInfo`）行为。

### 6.2 Android 原生（Kotlin，`android/`）

- 协程统一走 `Dispatchers.IO`，网络请求经 `NetworkClient` / `OkHttp`。
- 后台逻辑位于 `NotificationMonitorService` 及各模块（`BatteryMonitor` / `NotificationProcessor` / `WebhookSender` 等），新增能力优先复用既有模块，避免重复实现。
- 桌面图标别名：`IconOption` 有 17 个 key（`lib/services/icon_service.dart`），清单里是 **17 图标 × 2 语言 = 34 个 `activity-alias`**，必须严格对齐。规模常量单一维护点是 `test/architecture/launcher_manifest_contract_test.dart` 里的 `launcherIconCount = 17`；合并产物的实测口径用 `python tools/check_launcher_manifest.py <manifest 路径>`。
  ⚠ 该契约还规定 `src/main` 保留带 MAIN/LAUNCHER 的 `.MainActivity`（供 `flutter test integration_test/...` 发现启动入口），release/profile 变体用 manifest overlay 移除它——改动前务必读那段注释，否则会退化成「集成测试跑不起来」或「桌面双图标」。
- **Android lint 是 PR 门禁**：`./gradlew :app:lintDebug` 以 `abortOnError = true` 运行，
  已知误报由 `android/app/lint-baseline.xml` 兜住（只放已核对的历史项，**新增 error 依旧红**）。
  不要为了让 CI 变绿而往 baseline 里塞新条目，应先修代码。
- 注意 `onDestroy` 不应留下永久失效的全局状态（本仓库已修复 `NetworkClient.isActive` 的同类问题）。

### 6.3 服务端（`server/`，Node.js 24 + Express 5）

- 代码结构：入口 `server/server.js`（组装 + 进程生命周期），逻辑在 `server/lib/`
  ——`app.js`（Express 装配与 CORS）、`middleware.js`（安全头 / 限流 / IP 封锁 / 鉴权）、
  `store.js`（状态持久化、加密、失败计数）、`otp.js`（otplib v13 封装）、
  `routes/auth.js`（挂载于 `/api/admin`）、`routes/version.js`（版本检查与管理接口）。
- 改动后请执行：
  ```bash
  cd server
  node --check server.js      # 语法自检
  npm test                    # HTTP 契约测试（jest，29 例）
  npm run format:check        # Prettier；或 npm run format 就地修
  npm start                   # 本地起服务，访问 /health 自测
  ```
- 管理接口（`/api/admin/*`）改动需同步校验鉴权与请求体；版本配置的写入是**白名单投影**
  （`routes/version.js` 的 `VERSION_CONFIG_FIELDS`，未登记的键一律不落盘），新增字段须显式登记。
- **不要在代码或配置中硬编码密钥**；密钥来自环境变量（见第 9 节）。
- 新增环境变量请同步补进 `server/README.md` 的环境变量表（`server/README-en.md` 是镜像）。

---

## 7. 提交前本地校验清单（等价于 PR 门禁）

PR 门禁是 `.github/workflows/analyze.yml`（16 步）。本地按下面顺序跑一遍即可等价复现：

```bash
# 1) Dart 静态分析（出现 error 即红）
flutter pub get
flutter analyze --no-pub

# 2) 版本/文档一致性闸（pubspec ↔ update_manager ↔ MainActivity.kt ↔ version.json，
#    另含 version.json sha256 完备性、官网 i18n 覆盖、l10n zh/en 键集合一致）
bash .github/scripts/check_version_consistency.sh

# 3) Dart 单元测试（379 例 / 37 文件）+ 覆盖率
flutter test --no-pub --coverage

# 4) Android JVM 单元测试（234 例 / 26 类，JDK 21；无需签名密钥）
cd android && ./gradlew :app:testDebugUnitTest --console=plain

# 5) Android lint（debug 变体，error 即红）
./gradlew :app:lintDebug --console=plain

# 6) 服务端契约测试（29 例，Node 24）
cd ../server && npm ci && npm test

# 7) 三路格式闸门（Dart / Kotlin / JS）
cd .. && bash .github/scripts/check_format.sh
```

CI 额外做的事（本地可选）：

- 覆盖率报告与上传：`genhtml coverage/lcov.info -o coverage/html`，随后作为
  `coverage-report` 工件上传。
- `dart run dart_code_metrics:metrics analyze lib/ --reporter=github`：该步在 CI 里被
  `set +e` 包住、**不参与判红**。在 Dart 3.12 工具链上它目前会直接抛
  `Null check operator used on a null value`（与新版 analyzer 不兼容），因此不要把它当本地闸门，
  也不要因为它的输出修改代码风格判断。
- 集成冒烟测试**不在 PR 门禁内**（见第 8.2 节）。

---

## 8. 测试体系与守卫约定

### 8.1 测试基线

| 层 | 数量 | 入口 |
|----|------|------|
| Dart 单元测试 | **379 例 / 37 文件** | `flutter test --no-pub`（`test/` 下按 `architecture` / `database` / `models` / `services` / `theme` / `widgets` / `support` 分目录） |
| Kotlin JVM 单元测试 | **234 例 / 26 类** | `cd android && ./gradlew :app:testDebugUnitTest`（报告在 `build/app/test-results/testDebugUnitTest/`） |
| 服务端契约测试 | **29 例** | `cd server && npm test`（`server/test/auth.test.js`） |
| l10n 词条 | **853 键 × 2（zh / en）** | `lib/l10n/arb/app_zh.arb`、`lib/l10n/arb/app_en.arb` |

跑测试前 `flutter pub get`；Dart 与 Kotlin 两侧的用例数会随功能增长，若你新增/删除测试，
请同步更新本表的数字（它是文档口径，不是 CI 断言）。

### 8.2 设备侧测试（手动触发）

- `integration_test/smoke_test.dart` 是 7 步主链路冒烟测试。CI 由
  `.github/workflows/integration_test.yml` 运行，该工作流 **只有 `workflow_dispatch`
  触发**（模拟器按分钟计费，不挂 PR）。
- 本地跑（需真机或模拟器）：
  ```bash
  flutter devices                                  # 取设备 id
  flutter test integration_test/smoke_test.dart -d <device-id>
  ```
- 同一工作流还会在存活的模拟器上跑仪表测试：`cd android && ./gradlew connectedDebugAndroidTest`
  （含 `ApkSignatureVerifierInstrumentedTest`）。
- 若改动导致启动入口结构变化，参见 6.2 关于 MAIN/LAUNCHER overlay 的说明。

### 8.3 静态源码守卫与双份 golden fixture（改行为前必读）

本仓库大量测试是「读源文件 + 对文本断言」的守卫（契约测试），改动实现时若只想着「让测试变绿」，
很容易踩到两类真实事故：

1. **共享的去注释工具**：守卫必须先剥注释再断言，否则注释里的组件名/方法名会污染结果。
   - Dart：`test/support/source_guards.dart`（`stripComments` / `stripXmlComments` / `blockAfter` / `projectRoot`）
   - Kotlin：`android/app/src/test/java/com/fnthink/notice/SourceGuards.kt`（`stripComments`）
   新写守卫请复用它们，不要各写一份正则。这也解释了第 5 节里 `.editorconfig` 为什么关掉 ktlint 的
   重排类规则。
2. **两份必须逐字节一致的 golden fixture**：
   - `test/fixtures/rule_engine_golden.json`（Flutter 侧 `test/services/filter_service_golden_test.dart` 读取）
   - `android/app/src/test/resources/rule_engine_golden.json`（原生侧 `RuleEngineTest.kt` 读取）

   二者是**同步副本**，`RuleEngineTest.goldenFixtureCopiesAreIdentical` 会断言两份内容相同。
   改规则引擎/通道行为时**必须两份一起改**：只改一份会让双端跑在不同用例集上，而两侧各自都显示通过，
   属最难发现的假保护。另有原生侧单端快照 `android/app/src/test/resources/channel_behavior_golden.json`
   （`ChannelBehaviorGoldenTest.kt` 读取），改通道外发行为时需按该测试的说明重生成。
3. **守卫要做反向验证**：新增或修改守卫后，先把你要防的缺陷**植入**被测实现，确认守卫确实变红，
   再撤销缺陷。路径探测（`projectRoot()` / Kotlin 侧的 cwd 候选列表）写错时，断言可能根本没执行
   而测试仍然绿。

### 8.4 本地化（l10n）

词条源文件在 `lib/l10n/arb/`，模板是 `app_zh.arb`（配置见 `l10n.yaml`），生成物
`lib/l10n/app_localizations*.dart` **随仓库提交**。因此：

```bash
# 编辑 app_zh.arb / app_en.arb 之后必须重新生成，否则 CI 编译失败
flutter gen-l10n
```

- zh / en 两份键集合必须一致，`bash .github/scripts/check_version_consistency.sh` 会比对并漏报失败。
- 生成物要一起提交（只交 ARB 不交生成物会让 `flutter test` 在 CI 上编译不过）。

### 8.5 数据库

`lib/database/database_helper.dart` 的 `dbVersion = 11`，当前 6 张表（`notifications`、
`pending_notifications`、`email_channels`、`webhook_channels`、`webhook_delivery_log`、
`app_channels`）。新增表/字段必须递增 `dbVersion` 并补 `onUpgrade` 分支；**只改存量数据的值**
（如 v11 把送达键从本地化显示名改写为 `chan:<slug>`）同样要递增版本号并补分支，
且必须幂等（重复执行结果一致）、坏数据跳过而非抛出——`onUpgrade` 抛错的后果是
「备份原库 + 重建空库」，等于清空用户历史。
`test/database/database_helper_test.dart` 钉住了版本号与建表增量一致，也禁止迁移期建库使用字面量版本。
推送历史使用 SQLCipher（`sqflite_sqlcipher`）加密存储，改动请一并保持加密开关语义。

---

## 9. 安全与隐私（重要）

本项目是**通知监听与推送工具**，安全与隐私是底线（完整政策见 [SECURITY.md](SECURITY.md)）：

- **通知内容只在本地处理与转发**，不上传到任何第三方服务器（除非用户自行配置的 Webhook / SMTP 目标）。
  崩溃统计（腾讯 Bugly）**默认关闭**，仅当用户在「更多」页主动开启后才初始化 SDK 并上传最小必要信息
  （堆栈、设备型号、系统版本、应用版本、CPU 架构）。
- 不要在日志、崩溃上报或存储中写入通知正文、短信正文等隐私数据。原生侧诊断日志（`DiagLog`，
  「更多」页连点版本号 7 次开启，默认关闭）的红线是**只记录规则名/包名/计数等轻量信息，不含通知标题与正文**。
- **服务器密钥管理（`.env`）**：`server/.env` 已被 `.gitignore` 忽略，不会进入仓库；
  仓库仅保留 `server/.env.example`（占位/说明）。真实 `.env` 由部署方本地或 CI Secret 提供，
  **切勿将生产密钥（`ADMIN_TOKEN_HASH`、`ENCRYPTION_KEY` 等）提交到仓库**。
  新增环境变量请在 `server/README.md` 的环境变量表中补充。
- 服务端加密（`ENCRYPTION_KEY`）须为 **64 位十六进制**（AES-256-GCM），非法格式会被忽略并以明文存储 TOTP secret，提交前请自检。
- CORS 默认仅放行无 `Origin` 的请求（原生 App / curl）；浏览器跨域访问需显式配置 `ALLOWED_ORIGINS` 白名单，不要设为 `*`。
- 证书固定（`CERT_PINS` + `ENABLE_CERT_PINNING`，Dart 侧走 `--dart-define`）是**默认关闭的框架**，
  启用与轮换流程见 `docs/cert_rotation_runbook.md`，不要把 pin 值写进任何入库文件。

### 9.1 Android 发布签名：PR 工作不需要密钥

APK 发布签名遵循**源码零密钥**原则：任何被 Git 跟踪的源文件都不得包含 keystore 路径、密码或别名明文。

**贡献者需要知道的结论**：签名守卫只在「本次调用真要产出 release 包」时中止
（`android/app/build.gradle.kts` 依据 `gradle.startParameter.taskNames` 判定
assemble / bundle / package + release），因为该段代码在配置期执行，若无条件抛异常，
PR 门禁的 `:app:testDebugUnitTest`、`:app:lintDebug` 与仪器测试在没有密钥时会被一并打死。

因此以下命令在**完全没有密钥**的环境下可以正常执行（只会打印一条 warn 日志）：

```bash
cd android
./gradlew :app:testDebugUnitTest --console=plain
./gradlew :app:lintDebug --console=plain
./gradlew connectedDebugAndroidTest          # 需连接设备
```

需要密钥的只有 release 打包，且**必须走 Flutter 入口**：

```bash
flutter build apk --release --target-platform android-arm64
```

- ⚠ 不要用裸 `./gradlew :app:assembleRelease` 打 release：`integration_test` 是
  `dev_dependencies`，release classpath 缺失会让 `GeneratedPluginRegistrant` 编译失败。
  `flutter build apk` 才会正确装配插件与 `FLUTTER_TARGET_PLATFORM`（后者决定 ABI 过滤）。
- **本地构建**：把 `android/key.properties.example`（可安全提交的占位模板）复制为
  `android/key.properties`，填写 `storeFile` / `storePassword` / `keyAlias` / `keyPassword`。
  该文件被 `android/.gitignore` 与根 `.gitignore` 双重忽略，**切勿提交**。
- **CI**：只有 `.github/workflows/build-apk.yml` 需要签名材料，它从 GitHub Actions Secrets
  注入 `KEYSTORE_BASE64`、`KEYSTORE_FILE`、`KEYSTORE_PASSWORD`、`KEY_ALIAS`、`KEY_PASSWORD`，
  并把 `KEYSTORE_BASE64` 解码成 keystore 文件供 `build.gradle.kts` 使用。
  `analyze.yml`（PR 门禁）**不持有签名材料**，这是设计意图，不要为了「让它也走 release」去加 secret。
- **缺失即报错**：若既无环境变量也无 `key.properties`，且任务确为 release 打包，
  `build.gradle.kts` 抛出 `GradleException` 中止；另有 `afterEvaluate` + `findByName("packageRelease")`
  的惰性兜底守卫，确保未签名包绝不静默归档。禁止改成硬编码兜底密码，也禁止用
  `tasks.matching {}` 写兜底（它会立即实体化任务，实测在无关调用里强建 `assembleRelease` 并触发 AGP 内部报错）。
- **轮换策略**：keystore 或密码泄露时立即生成新 keystore，并同步更新本地 `key.properties` 与 CI Secrets。
  ⚠ 应用内更新以「本机已安装应用的签名证书」为可信根，换密钥会让存量用户无法通过应用内更新升级——
  轮换前必读 `docs/cert_rotation_runbook.md` 第 7 节（多签名过渡方案）。
- 提交前用 `git status` 确认没有 `*.jks` / `*.keystore` / `android/key.properties` 被跟踪。

---

## 10. 版本发布流程（标准发版流程）

> 仅维护者执行。客户端每发一版，须同步更新版本常量、版本配置与产物归档。

### 10.1 版本号同步（四处 + 文档）

版本号不只在 `pubspec.yaml`。以下必须一致，否则 `check_version_consistency.sh` 判失败：

1. `pubspec.yaml` 的 `version: X.Y.Z+NN`（`versionName` 与 `versionCode` 同步递增，当前为 `1.5.74+113`）；
2. `lib/update_manager.dart` 的 `_fallbackVersion` / `_fallbackBuild`；
3. `android/app/src/main/kotlin/com/fnthink/notice/MainActivity.kt` 的 `FALLBACK_VERSION` / `FALLBACK_BUILD`；
4. `server/data/version.json` 的 `latestVersion` / `latestBuild`；
5. 外加文档口径：`README.md` / `README-en.md` 的 Version 徽章、`update.md` 顶部条目。

```bash
bash .github/scripts/check_version_consistency.sh   # 任一不符即 exit 1
```

### 10.2 半自动发版脚本（推荐）

```bash
bash .github/scripts/release_local.sh <A.B.C>       # 例：release_local.sh 1.5.74
```

它固化了已验证的机械步骤：

- **阶段 0** 版本号同步预检（含 `update.md` 条目、README 双语徽章）；
- **阶段 1** `dart format`（`lib` 与 `test`）+ `flutter analyze`（要求 `No issues found`）；
- **阶段 2** 逐个构建 **4 个 release APK**：arm64 / arm32 / x86_64 / 三架构融合，
  产物命名为 `notice_arm64_X.Y.Z.apk`、`notice_arm32_X.Y.Z.apk`、`notice_x86_X.Y.Z.apk`、
  `notice_all_X.Y.Z.apk`，落在 `build/app/outputs/flutter-apk/vX.Y.Z/`；
- **步骤 6.5** 用 `python` 解压校验 ABI 纯净度（单架构包只含一种 `.so`）与 versionName；
- **阶段 3** 回填 `server/data/version.json`：`latestVersion` / `latestBuild` /
  `downloads`（各架构下载地址）/ `fileSizes`（字节数）/ `sha256`（各架构 64 位十六进制），
  并把 APK 同步到 `server/public/apks/X.Y.Z/`；
- **阶段 4** 文档缺项检查（`update.md`、README 徽章）；
- **阶段 5** CI 等价自检（`flutter test`、`:app:testDebugUnitTest`、
  `check_version_consistency.sh`、format、analyze、`server` 的 `npm test`）。

**不覆盖**的人工步骤：`update.md` / `base.md` 文案撰写与审计、官网内容完备性判断、
git 提交打 tag、服务端部署。

### 10.3 发布与部署

1. 提交并打 tag `vX.Y.Z` → `.github/workflows/build-apk.yml`（tag 触发）构建 arm64 包，
   上传工件并在 GitHub Release 挂包（`softprops/action-gh-release`）。
2. 把 `server/data/version.json`（以及需要时 `server/public/**`）推到 `main` →
   `deploy-pages.yml` 自动发布 GitHub Pages 静态回退模式（客户端先请求
   `/api/version/check`，失败后回退 `/api/version.json`）。
3. 自有 Node 服务器部署与重启：详见 [server/README.md](server/README.md)
   （English：[server/README-en.md](server/README-en.md)）。服务端**仅支持单实例部署**
   （限流计数、会话、IP 封锁都在进程内存里），PM2 cluster / 多副本会导致状态漂移。

---

## 11. Issue 与反馈

提 Bug / 功能请优先使用 `.github/ISSUE_TEMPLATE/` 下的模板（Bug 模板会要求应用版本与构建号、
Android 版本、设备与厂商、以及诊断日志开关状态）。信息完备的 Issue 会被优先处理。

---

## 12. 许可证

本项目以 **MIT License** 开源（见 [LICENSE](LICENSE)）。提交即表示你同意以该许可证发布你的贡献。

---

再次感谢你的参与！如有疑问，欢迎提 Issue 讨论。
