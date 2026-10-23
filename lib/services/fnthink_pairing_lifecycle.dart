import 'package:shared_preferences/shared_preferences.dart';

/// 配对口令在**本机屏幕上**的四种说法（T171）。
///
/// ⚠ 这里判的不是服务器那条真值：`expired` 只是"看起来过期"（本机时间 + 契约 TTL），
/// `consumed` 是本机记下的"刚刚成功配对过一次"，`notPublished` 是"这一枚没上到服务器"。
/// 真正的可用性仍由服务器判 —— 所以界面说的是"看起来/本机记下"，不是"服务器已确认"。
enum FnthinkPairingLifecycle {
  active,
  consumed,
  expired,
  notPublished,
  unknown,
}

/// 本机那一枚口令成功配对过的标记。键名不带 `flutter.`：这是 Dart 自己写的。
const String kFnthinkPairingConsumedKey = 'fnthink_pairing_consumed_at';

/// 纯函数：三份事实 → 屏幕上那一档。顺序即优先级：
/// 用过 > 过期 > 没上到服务器 > 有效 > 不知道。
FnthinkPairingLifecycle fnthinkPairingLifecycleOf({
  required bool consumed,
  required bool? looksExpired,
  required bool? acked,
}) {
  if (consumed) return FnthinkPairingLifecycle.consumed;
  if (looksExpired == true) return FnthinkPairingLifecycle.expired;
  if (acked == false) return FnthinkPairingLifecycle.notPublished;
  if (looksExpired == null || acked == null) {
    return FnthinkPairingLifecycle.unknown;
  }
  return FnthinkPairingLifecycle.active;
}

class FnthinkPairingLifecycleStore {
  static Future<void> markConsumed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      kFnthinkPairingConsumedKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<bool> isConsumed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(kFnthinkPairingConsumedKey) != null;
  }

  /// 重新挂一枚口令时清掉：上一枚用过，不等于这一枚也用过。
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kFnthinkPairingConsumedKey);
  }
}
