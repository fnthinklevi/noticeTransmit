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
