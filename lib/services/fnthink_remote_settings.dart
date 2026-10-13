import 'dart:convert';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 远程执行的**设置**（远程执行专用，不与幻念推送的接收开关共用键）。
///
/// ⚠ 为什么这四件不与 `fnthink.receive_enabled` 挤在一个类里：远程执行是"别人能让我这台设备
/// 做事"，接收开关是"这台设备愿不愿意收别人的通知"。合并之后关掉远程执行会连带把接收也关掉，
/// 而这两件事的用户意图完全独立 —— 最坏的那种形状是"用户以为只关了一件事"。
///
/// ⚠ 三件走 **SharedPreferences**（明文 XML，可备份）：`enabled` 与 `delaySeconds` 是**决定**
/// 而不是秘密；凭据（哈希/盐/种子）走 `RemoteCredentialStore`（EncryptedSharedPreferences）——
/// 那三件是**能让人控制这台设备**的东西，明文 XML ��� adb backup 拉走。
class FnthinkRemoteSettings {
  FnthinkRemoteSettings({required this.contract});

  final FnthinkContract contract;

  static const keyEnabled = 'fnthink.remote_execution.enabled';
  static const keyDelaySeconds = 'fnthink.remote_execution.delay_seconds';

  /// 本机通知触发（白名单那一路）的开关 + 「哪些应用的通知才允许」（T145，
  /// 维护者 2026-10-12 裁定 4）。
  ///
  /// ⚠ 这一族**新建三份键**，不复用转发面的 `enabled_packages` / `app_filter_mode`：
  ///   那两张表的语义是"要转发的应用"，一复用就同时改了转发面（用户以为只收窄了
  ///   "通知能不能当指令"，实际把推送名单也换了）。
  ///
  /// ⚠ **原生侧不许读这三个键** —— 这一路的判定只住 Dart 一处
  ///   （`RemoteCommandRecognizer.judge`）。把默认值再写一份到 Kotlin，就成了
  ///   "同一颗开关两处·跨两种语言"，而那一族在本仓砸过脚（短信监听那一路要六条守卫才钉住）。
  static const keyLocalTriggerEnabled =
      'fnthink.remote_execution.local_trigger_enabled';
  static const keyLocalTriggerMode =
      'fnthink.remote_execution.local_trigger_mode';
  static const keyLocalTriggerPackages =
      'fnthink.remote_execution.local_trigger_packages';

  /// 远程执行总开关。**默认关**（契约没写默认值 ⇒ 取"最不让人意外的那一档"；
  /// 与 `fnthink.receive_enabled` 同一条纪律：升级不许悄悄替用户做决定）。
  Future<bool> get enabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyEnabled) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyEnabled, value);
  }

  /// 本机通知触发那颗开关。**默认关** —— 这一路是**无凭据**的 L1 入口（契约
  /// `auth.l2Requires:false`，L1 更不要求），今天的实际语义是"命中关键词的第三方
  /// 通知正文可以被当指令源"。默认开等于把既有行为继续挂在一颗没人点过的开关外面；
  /// 换成关，换来的是一次显式开启（维护者 2026-10-12 裁定 4 的原话）。
  Future<bool> get localTriggerEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyLocalTriggerEnabled) ?? false;
  }

  Future<void> setLocalTriggerEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyLocalTriggerEnabled, value);
  }

  /// 「哪些应用的通知才允许触发」那一份清单（模式 + 包名集）。
  ///
  /// 从没写过 / 值不成形 ⇒ [parseLocalTriggerFilter] 退回**最窄**的那一档（谁都不许），
  /// 而不是"不限"：这一路的判据缺省必须往窄的那一侧（契约 `grantDefaultsWhy` 同一条纪律）。
  Future<FnthinkLocalTriggerFilter> localTriggerFilter() async {
    final prefs = await SharedPreferences.getInstance();
    return parseLocalTriggerFilter(
      mode: prefs.getString(keyLocalTriggerMode),
      rawPackages: prefs.getString(keyLocalTriggerPackages),
    );
  }

  Future<void> setLocalTriggerFilter({
    required String mode,
    required List<String> packages,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      keyLocalTriggerMode,
      mode == 'block' ? 'block' : 'allow',
    );
    await prefs.setString(
      keyLocalTriggerPackages,
      jsonEncode(packages.toList()),
    );
  }

  /// 延时窗口用户选的那一档（秒）。null = 从没选过 ⇒ 用契约的 `delay.defaultSeconds`。
  ///
  /// ⚠ 存"用户选没选过"而不是"当前生效的那个数"：契约调档时这台才跟得上
  /// （与 `FnthinkSettings.pollSeconds` 同一条纪律）。
  Future<int?> get delaySeconds async {
    final prefs = await SharedPreferences.getInstance();
    return _checked(prefs.getInt(keyDelaySeconds));
  }

  Future<void> setDelaySeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    final checked = _checked(seconds);
    if (checked == null) {
      throw const FnthinkRemoteSettingsInvalid('延时窗口的秒数不能是空的');
    }
    await prefs.setInt(keyDelaySeconds, checked);
  }

  /// 抹掉这一档 = 回到"从没选过"，于是契约默认重新生效。
  Future<void> clearDelaySeconds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyDelaySeconds);
  }

  /// 现在真正该用的那一档（用户选的那一档，没选过就是契约默认）。
  Future<int> effectiveDelaySeconds() async {
    final chosen = await delaySeconds;
    return contract.effectiveRemoteExecutionDelaySeconds(chosen);
  }

  /// 界面上延时那一格该显示什么。**范围与生效值都来自契约**，页面不写任何秒数。
  Future<FnthinkRemoteDelaySetting> delaySetting() async {
    final range = delaySecondsRange;
    String? problem;
    int? chosen;
    try {
      chosen = await delaySeconds;
    } on FnthinkRemoteSettingsInvalid catch (e) {
      // prefs 里那一档契约不允许（备份恢复灌回来的那一种）：如实报出来，并按"没选过"处理。
      problem = e.reason;
    }
    return FnthinkRemoteDelaySetting(
      range: range,
      chosen: chosen,
      effective: contract.effectiveRemoteExecutionDelaySeconds(chosen),
      problem: problem,
    );
  }

  /// 范围来自契约；取不到就抛 —— 没有范围就没有可校验的依据，缺省成"随便填"
  /// 等于把用户送到一档协议不许的窗口上去。
  ({int min, int max}) get delaySecondsRange {
    try {
      return contract.remoteExecutionDelayRange;
    } on StateError catch (e) {
      throw FnthinkRemoteSettingsInvalid(e.message);
    }
  }

  /// ⚠ **读的时候也校验**（备份恢复会把 prefs 原样灌回来，不校验的那条路才是漏的那条）。
  int? _checked(int? seconds) {
    if (seconds == null) return null;
    final range = delaySecondsRange;
    if (seconds < range.min || seconds > range.max) {
      throw FnthinkRemoteSettingsInvalid(
        '延时窗口存的是 ${seconds}s，协议只允许 ${range.min}–${range.max}s',
      );
    }
    return seconds;
  }
}

/// 「延时执行」那一格的完整读数。
class FnthinkRemoteDelaySetting {
  const FnthinkRemoteDelaySetting({
    required this.range,
    required this.chosen,
    required this.effective,
    this.problem,
  });

  final ({int min, int max}) range;
  final int? chosen;
  final int effective;

  /// 非 null = prefs 里存着的那一档协议不允许，此时 [chosen] 按"没选过"处理。
  final String? problem;
}

/// 设置里的值不可用（输入错、或备份恢复灌回来一个坏值）。
class FnthinkRemoteSettingsInvalid implements Exception {
  const FnthinkRemoteSettingsInvalid(this.reason);

  final String reason;

  @override
  String toString() => '远程执行的设置不可用：$reason';
}

/// 「哪些应用的通知才允许触发本机远程执行」那一档的读数。
class FnthinkLocalTriggerFilter {
  const FnthinkLocalTriggerFilter({required this.mode, required this.packages});

  /// `'allow'` = 只有清单里的应用可以；`'block'` = 除清单里的应用之外都可以。
  final String mode;
  final Set<String> packages;
}

/// 从 prefs 的两个键解析出 [FnthinkLocalTriggerFilter]。**纯函数**（页面与判据共用一份读法）。
///
/// ⚠ 坏值不抛：这一档是**收窄**用的，读不出来就退回最窄的那一档（谁都不许），
///   而不是把一条通知放行。备份恢复灌回来一个畸形 JSON 时，"判不了就不许"是唯一
///   不会替用户做决定的方向。
FnthinkLocalTriggerFilter parseLocalTriggerFilter({
  String? mode,
  String? rawPackages,
}) {
  final normalizedMode = mode == 'block' ? 'block' : 'allow';
  final encoded = rawPackages;
  if (encoded == null || encoded.isEmpty) {
    return FnthinkLocalTriggerFilter(mode: normalizedMode, packages: const {});
  }
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      return FnthinkLocalTriggerFilter(
        mode: normalizedMode,
        packages: const {},
      );
    }
    return FnthinkLocalTriggerFilter(
      mode: normalizedMode,
      packages: {
        for (final item in decoded)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      },
    );
  } on FormatException {
    return FnthinkLocalTriggerFilter(mode: normalizedMode, packages: const {});
  }
}

/// 这一条通知的**来源应用**能不能触发本机远程执行。
///
/// ⚠ 与转发面那条"空集 = 不限"（`FilterEngine` 的 `enabledPackages.isEmpty` 那一支）
///   **刻意不同**：转发少推一条是吵到用户，这一路多执行一条是替他动一次手，
///   所以 allow + 空集在这里读成"谁都不许"。开着的开关 + 空清单 = 界面上必须
///   明说"等于都不触发"，别让它静默长成"全允许"。
/// ⚠ 空包名 ⇒ 不许：包名是这一发唯一的判据输入，拿不到就是拿不到（原生那一路
///   必然带着它，带不上说明交接坏了）。
bool localTriggerAllows(FnthinkLocalTriggerFilter filter, String packageName) {
  final pkg = packageName.trim();
  if (pkg.isEmpty) return false;
  if (filter.mode == 'block') return !filter.packages.contains(pkg);
  return filter.packages.contains(pkg);
}
