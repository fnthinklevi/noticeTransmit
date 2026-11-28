import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'platform_channel.dart';

/// UI 主 isolate 的存活心跳（T197 片3）。
///
/// 服务里的常驻无头引擎要回答一个问题：**现在该由谁持有收货循环？**
/// UI 的心跳新鲜 ⇒ UI 那台引擎还活着，服务引擎别抢（两条循环同时 poll 会重复 ack、
/// 未读数上下跳）；心跳过期 ⇒ UI 已被系统收走，服务引擎接管。
///
/// 键**不带** `flutter.` 前缀：SharedPreferences 落盘时自己加，原生读的是
/// `flutter.fnthink_ui_alive_at`（与收货/转发 handle 同一形状）。
const String kFnthinkUiAliveKey = 'fnthink_ui_alive_at';

/// UI 心跳周期。旧接线是 10 秒一次：主 isolate 每 10 秒写一次 prefs，服务引擎每
/// 10 秒读一次；两条链在后台纯粹为了"谁持有循环"反复唤醒。现在正常交接走
/// **事件**（`setFnthinkUiReceiveActive`），这里只留 60 秒一次的兜底：
/// UI isolate 被系统冻住/写事件失败时，服务引擎仍能在一个可接受的窗口内接管。
const Duration kFnthinkUiHeartbeatInterval = Duration(seconds: 60);

/// 心跳多久算新鲜。60 秒一次的心跳给三拍余量（180 秒）：两拍整时，服务兜底同步
/// 恰好落在第二拍还没写下去的边界上会误判"UI 已死"；事件通道正常时根本用不到它。
const Duration kFnthinkUiAliveFreshness = Duration(seconds: 180);

/// 纯判据：`at` 是 UI 最后一次心跳（毫秒），`now` 是当下。0/null 一律不新鲜。
bool fnthinkUiAlive(int? at, int now) {
  if (at == null || at <= 0) return false;
  return now - at < kFnthinkUiAliveFreshness.inMilliseconds;
}

Timer? _heartbeat;

/// 测试可关：周期 Timer 会挂在 `testWidgets` 的收尾检查上；生产默认开。
bool debugFnthinkUiHeartbeatEnabled = true;

/// 把"UI 这边有没有收货循环"立刻告诉原生。服务引擎靠这一发做**即时交接**；
/// prefs 心跳只是事件丢失时的兜底，不再承担主路径。
///
/// 通道失败不影响收货：下一拍心跳仍会被服务引擎读到；因此这里和心跳写入一样只吞。
Future<void> publishFnthinkUiReceiveActive(bool active) async {
  try {
    await AppChannels.notification.invokeMethod<void>(
      'setFnthinkUiReceiveActive',
      <String, dynamic>{'active': active},
    );
  } catch (_) {
    // 事件丢一拍只影响交接时延，不影响收货本身；兜底心跳仍在。
  }
}

/// 在 UI 主 isolate 里起心跳。**幂等**：重复调用不会叠出第二个 Timer。
///
/// 它只回答"UI 收货循环在跑"，不回答"收货开关开着"——循环停了心跳就停，
/// 服务引擎才会在窗口过期后接管。
void startFnthinkUiHeartbeat() {
  if (!debugFnthinkUiHeartbeatEnabled) return;
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
  unawaited(publishFnthinkUiReceiveActive(true));
  _heartbeat = Timer.periodic(kFnthinkUiHeartbeatInterval, (_) => write());
}

/// 停心跳。**不清掉那枚时刻**：事件通道正常时服务引擎立刻接管；事件失败时它自然
/// 过期（180 秒窗口）。清 0 会与紧接着的 `start` 写时间戳形成先后不确定的竞态 ——
/// 新循环已经起来、旧 `stop` 的 0 后落地，兜底同步就会误判 UI 已死。
///
/// 语义是"UI 收货循环停了"，不是"UI isolate 死了"：循环自己停（用户关开关、
/// 起链失败、内部异常）时心跳必须跟着停，否则服务引擎会以为 UI 还在收货而一直让位。
void stopFnthinkUiHeartbeat() {
  _heartbeat?.cancel();
  _heartbeat = null;
  unawaited(publishFnthinkUiReceiveActive(false));
}
