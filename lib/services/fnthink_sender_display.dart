import 'package:shared_preferences/shared_preferences.dart';

/// 收件里「发送人」怎么显示（T172）。
///
/// 三档**至少显示一项**：本机备注与对面报来的设备名都可能为空，而地址码永远在。
/// 所以任何一档的最后回落都是地址码 —— 不出现空字符串，也不把"没名字"演成"未知来源"。
enum FnthinkSenderDisplayMode {
  /// 备注优先：有备注用备注，没备注用设备名，都没有用地址码。
  aliasFirst,

  /// 只看设备名：有设备名用设备名，没设备名回落到备注，再回落到地址码。
  deviceName,

  /// 两者都给：`备注（设备名）`，缺哪一个就只给另一个；都没有给地址码。
  both,
}

/// 偏好键（不带 `flutter.`：这是 Dart 自己写的）。
const String kFnthinkSenderDisplayModeKey = 'fnthink_sender_display_mode';

/// 未知 / 缺失一律回默认档（备注优先）。**不猜一个别的档**：
/// 认不出的值当成用户没选过，而"没选过"与"选过"在界面上是两件事。
FnthinkSenderDisplayMode parseFnthinkSenderDisplayMode(String? raw) {
  for (final mode in FnthinkSenderDisplayMode.values) {
    if (mode.name == raw) return mode;
  }
  return FnthinkSenderDisplayMode.aliasFirst;
}

/// 发送人那一格的**唯一显示作者**（收件行、系统通知、详情共用）。
///
/// [address] 永远在：它是唯一能被核对的那一项；名字只是让人少查一次。
String fnthinkSenderLabel({
  required FnthinkSenderDisplayMode mode,
  required String address,
  required String alias,
  required String peerName,
}) {
  final a = alias.trim();
  final n = peerName.trim();
  final fallback = address.trim();
  switch (mode) {
    case FnthinkSenderDisplayMode.aliasFirst:
      if (a.isNotEmpty) return a;
      if (n.isNotEmpty) return n;
      return fallback;
    case FnthinkSenderDisplayMode.deviceName:
      if (n.isNotEmpty) return n;
      if (a.isNotEmpty) return a;
      return fallback;
    case FnthinkSenderDisplayMode.both:
      if (a.isNotEmpty && n.isNotEmpty && a != n) return '$a（$n）';
      if (a.isNotEmpty) return a;
      if (n.isNotEmpty) return n;
      return fallback;
  }
}

/// 本机记住的那一档。
class FnthinkSenderDisplaySettings {
  FnthinkSenderDisplaySettings(this.mode);

  final FnthinkSenderDisplayMode mode;

  static Future<FnthinkSenderDisplaySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return FnthinkSenderDisplaySettings(
      parseFnthinkSenderDisplayMode(
        prefs.getString(kFnthinkSenderDisplayModeKey),
      ),
    );
  }

  Future<void> setMode(FnthinkSenderDisplayMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kFnthinkSenderDisplayModeKey, mode.name);
  }
}
