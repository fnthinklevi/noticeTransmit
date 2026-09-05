# 大型重构方案（P1 遗留项）

> 状态：**方案文档，本轮不实施**。对应代码审查 P1-1 / P1-2 / P1-7 三项可维护性债务。
> 原则：遵守 base.md 强制规范（Cupertino UI、flutter analyze 零问题、CI 等价自检、版本四处同步）；每一步重构保持可回滚、可独立回归。

---

## 方案一：MainActivity 拆分（当前 1855 行 / 单 when 约 70 分支）

### 现状
单个 `MethodChannel("com.fnthink.notice/notification")` 的 `when(call.method)` 堆积了权限 / 配置 / 设备 / 文件 / 下载 / 统计 / Bugly / 小部件等全部桥接分支，另含 receiver 注册、Bugly 初始化、桌面别名等 Activity 生命周期职责。

### 目标形态 A（推荐，低风险）：单通道 + 按域委托 Handler
channel 名与 Dart 端**完全不变**，把 `when` 分支按域搬进独立 Handler：

```
android/app/src/main/kotlin/com/fnthink/notice/channels/
├── ChannelDispatcher.kt        # 遍历 handlers，首个消费者返回
├── PermissionChannelHandler.kt # is/requestXxxPermission、ROM 保活、精确闹钟
├── ConfigChannelHandler.kt     # set/getAppFilter、黑白名单、规则、locale、崩溃上报
├── DeviceChannelHandler.kt     # 版本、电池、SIM、设备名、桌面别名
├── FileChannelHandler.kt       # saveFile、下载、安装、下载目录
└── StatsChannelHandler.kt      # 计数、归档、同步当日计数
```

Handler 统一签名：`fun handle(call: MethodCall, result: MethodChannel.Result): Boolean`（false = 不归我管）。MainActivity 只保留：engine 装配、receiver 注册、`maybeInitCrashReport`、`FALLBACK_VERSION`。

- 优点：Dart 零改动、base.md 通道表零改动、可分域逐步搬（每次一个域 + 回归）
- 后续可选形态 B：拆成多个独立 MethodChannel（PermissionChannel/...），Dart `platform_channel.dart` 与 base.md 同步改；仅当形态 A 完成且仍需解耦时再做

### 迁移步骤
1. 建 `ChannelDispatcher` + 空壳 Handler，MainActivity 分发器兜底保留旧 `when`（新旧并存，Handler 优先）。
2. 逐域迁移（建议顺序：Device → Stats → File → Config → Permission，权限域最敏感放最后）。
3. 每域迁移后跑：`flutter analyze`、`gradlew testDebugUnitTest`、真机回归该域功能。
4. 清空旧 `when` 后删除兜底。

### 风险与回归清单
- 权限域依赖 `Activity` 承接系统弹窗与 `onRequestPermissionsResult` → Handler 持有 Activity 引用（弱引用或构造传入）。
- 回归：splash 权限引导 → 各权限开关状态刷新、通知监听跳转、短信/电话权限弹窗、导出 saveFile、应用内更新下载安装、统计页、小部件启停、崩溃上报开关。

---

## 方案二：UI 三页瘦身（rule_edit 1444 / webhook_settings 1288 / main 1203 行）

### 现状
业务逻辑与 Widget 耦合，主要靠 `setState` + 单例；provider 已在依赖中但基本未用。

### 目标形态：Controller（ChangeNotifier）+ 子组件拆分
- 每页抽 `XxxPageController extends ChangeNotifier`：持有状态与业务方法（含 MethodChannel/DB 调用），Widget 只 build + 监听。
- 三页各自拆分：
  - `rule_edit_page` → 条件编辑器 / 动作编辑器 / 时间与正则输入组件 + Controller
  - `webhook_settings_page` → 通道列表 / 通道编辑表单（按类型字段差异）/ 测试发送区 + Controller
  - `main_page` → 通道状态头 / 记录列表 / MethodChannel 事件接线（移入 NotificationService）+ Controller
- 状态管理引入 provider（已在依赖中）：`ChangeNotifierProvider` 包裹页面，子组件 `context.watch` / `context.read`。

### 迁移步骤（每页独立、可随时暂停）
1. 抽 Controller：把 `setState` 的 state 字段与业务方法原样搬入，页面改为 `AnimatedBuilder`/`Consumer` 监听（行为零变化）。
2. 拆子组件文件（纯搬运 build 代码，传参显式化）。
3. 真机回归该页全交互。

### 回归清单
- rule_edit：八类条件逐个增删改、AND/OR 分组、动作参数（延迟秒数/定时）、保存后规则引擎双端生效
- webhook_settings：七类通道增删改测、签名/模板字段按类型显隐、保存后原生同步
- main：实时通知回传刷新、送达状态更新、暂停/恢复推送、导出与多种清除

---

## 方案三：本地化迁移 ARB + flutter gen-l10n（app_localizations.dart 1712 行手写）

### 现状
`_zh` / `_en` 两张手写 Map + 444 个手写 getter + `{n}` 占位符自实现替换；无 l10n.yaml、无 ARB；漏翻只能靠人工比对。

### 迁移步骤
1. 配置 `l10n.yaml`（arb-dir: lib/l10n/arb；template: app_zh.arb；output-localization-file: app_localizations.dart；nullable-getter: false）。
2. 一次性脚本把两张 Map 转成 `app_zh.arb` / `app_en.arb`：键值 1:1 迁移；`{n}`/`{m}` 占位符改写为 ARB placeholders（int）。
3. `flutter gen-l10n` 生成官方类，全库替换 import 与调用点（`l10n.ruleCount(n)` 签名由生成器决定）。
4. 删除手写 `app_localizations.dart`，`MaterialApp` 接 `generatedLocalizationsDelegate`。
5. CI 增加漏翻检查：比对两个 ARB 的 key 集合（可用 `flutter gen-l10n` 的报错 + 简单 diff 脚本双重保障）。

### 风险
- 444 个键 + 占位符语法转换属机械操作，但调用点替换需全量 grep；建议脚本生成 + 编译器报错驱动补齐。
- 迁移后需真机过一遍双语主流程（splash/主页/规则/通道/更多/隐私政策长文本）。
- 收益：官方工具链、类型安全占位符、漏翻检测自动化、后续加语言成本骤降。

---

## 优先级建议

| 方案 | 预估 | 收益/风险 | 建议 |
|------|------|-----------|------|
| 一（形态 A） | ≈1 天 | 高收益/低风险 | 最先做，纯原生改动可单测 |
| 二 | 每页 1–2 天 | 高收益/中风险（需真机回归） | 逐页推进，先 main_page |
| 三 | 2–3 天 | 中收益/低风险（机械迁移） | 版本窗口期做，避免与功能并行 |

规则/过滤引擎语义本轮已通过双端黄金用例（`test/fixtures/rule_engine_golden.json`）锁定，上述重构**不得**触碰 `FilterEngine.normalize` 与 `RuleEngine.evaluate` 语义；如需改动，必须先同步修改两份黄金 fixture。
