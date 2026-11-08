import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// UI 主 isolate 的存活心跳（T197 片3）。
///
/// 服务里的常驻无头引擎要回答一个问题：**现在该由谁持有收货循环？**
/// UI 的心跳新鲜 ⇒ UI 那台引擎还活着，服务引擎别抢（两条循环同时 poll 会重复 ack、
/// 未读数上下跳）；心跳过期 ⇒ UI 已被系统收走，服务引擎接管。
///
/// 键**不带** `flutter.` 前缀：SharedPreferences 落盘时自己加，原生读的是
/// `flutter.fnthink_ui_alive_at`（与收货/转发 handle 同一形状）。
const String kFnthinkUiAliveKey = 'fnthink_ui_alive_at';

/// 心跳多久算新鲜。UI 每 10 秒写一次，30 秒的窗口给系统调度留 2 次余量。
const Duration kFnthinkUiAliveFreshness = Duration(seconds: 30);

/// 纯判据：`at` 是 UI 最后一次心跳（毫秒），`now` 是当下。0/null 一律不新鲜。
bool fnthinkUiAlive(int? at, int now) {
  if (at == null || at <= 0) return false;
  return now - at < kFnthinkUiAliveFreshness.inMilliseconds;
}

Timer? _heartbeat;

/// 在 UI 主 isolate 里起心跳。**幂等**：重复调用不会叠出第二个 Timer。
///
/// 它只回答"UI 引擎还活着"，不回答"收货开关开着"——所以即使用户关掉了收货，
/// 心跳照写：服务引擎看到新鲜心跳只会停自己的循环，不会替用户去收。
void startFnthinkUiHeartbeat() {
  if (_heartbeat != null) return;
  void write() {
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          kFnthinkUiAliveKey,
          DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {
        // 心跳写失败只影响"谁持有循环"的判断，不影响收货本身；
        // 服务引擎读不到新鲜心跳会接管，那一侧仍有自己的失败日志。
      }
    }());
  }

  write();
  _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) => write());
}
