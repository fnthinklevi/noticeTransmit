import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_channel.dart';

/// 「让这台响一条」（T124 片B 的 `alert:ring`；实现在 `FnthinkAlertDisplay.kt`）。
///
/// 它是唯一一个**不产出任何东西**的"通知类"动作：让这台设备响铃＋震动＋弹一条
/// 高优先横幅，好让拿着这台手机的人注意到（"我手机在哪"那类用法）。
///
/// ⚠ 回 false = **没显示**（通知权限被关 / 那枚渠道被系统禁用）—— 执行链据此把这一步
/// 记成失败：对面收到 `done` 会以为这台的用户被提醒过了，而用户什么都没看到。
/// 不抛（与 `FnthinkInboxDisplay.show` 同一纪律）：一条显示失败不该让整轮收货崩在半路。
///
/// ⚠ **全屏那半没做**：Android 14 起 `setFullScreenIntent` 要 `USE_FULL_SCREEN_INTENT`
/// 这份清单权限 + 用户的特殊授权（"全屏通知"那一档）。那不是"零新权限"（片B 的前提），
/// 而是一条**新的权限面决定** —— 要加得按片C 那套来（清单＋申请入口＋隐私政策三处＋默认关）。
/// 现在交付的是响铃＋震动＋高优先横幅（`IMPORTANCE_HIGH` 渠道，与收件同一条）。
class FnthinkAlertDisplay {
  FnthinkAlertDisplay({MethodChannel? channel})
    : _channel = channel ?? AppChannels.notification;

  final MethodChannel _channel;

  Future<bool> ring() async {
    try {
      final shown = await _channel.invokeMethod<bool>('showFnthinkAlert');
      return shown ?? false;
    } catch (e) {
      debugPrint('[fnthink] 响铃显示调用失败（按未显示处理）: $e');
      return false;
    }
  }
}
