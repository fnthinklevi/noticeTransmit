import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fnthink_push/fnthink_push.dart';

import 'fnthink_contract_loader.dart';
import 'platform_channel.dart';

/// 「点开的那条配对链接」在 Dart 侧的唯一读点（#176 片4，T28-B 的最后一跳）。
///
/// 原生只负责把那一串交出来（`FnthinkPairLink.take()`，取走即清），**判**全在这里、
/// 而判的口径全在契约里（载荷名单、`v` 必须对上、地址码与口令的形状、档位词表 ——
/// 见 `FnthinkPairingRequest.parse`）。为什么不在 Kotlin 抄一份判据：两份判据可以朝
/// 同一个方向写错，而那时两侧编译与测试都仍然绿（T83 那条 EXTRA 键名守卫同一条理由）。
///
/// ⚠ 一次 `take()` 只能被一个读者拿到：所以这里**不做缓存、不重试读**。第二个读者一旦出现，
///   表现就是同一个链接弹两次输入层，而那枚口令是 singleUse 的。
class FnthinkPairLinkOutcome {
  const FnthinkPairLinkOutcome({this.request, this.reason});

  /// 判对了的那份请求（地址码 / 一次性口令 / 档位）。
  final FnthinkPairingRequest? request;

  /// 只给测试与开发诊断用的原因（`parse` 给的那个词）。
  /// ⚠ **不进文案、不进日志**：`pairing.internalReason` 那条纪律说的是"四种失败塌成一句"，
  ///   这里沿用同一条判据 —— 界面只说"这条链接这台设备用不上"，不教人怎么试出哪种不对。
  final String? reason;

  bool get accepted => request != null;
}

/// 读那条链接并判一次。契约读不到时**不算成功也不算"没有链接"**：那一发不能预填，
/// 而界面上的结论必须是"这台现在没法判这条链接"（与页面其它格子同一条三态纪律）。
class FnthinkPairLinkReader {
  FnthinkPairLinkReader({required this.contracts, MethodChannel? channel})
    : _channel = channel ?? AppChannels.notification;

  final FnthinkContractLoader contracts;
  final MethodChannel _channel;

  /// 返回 null = **没有**待处理的链接（没点过、或已经被别人取走了）。
  /// null 与"有链接但判不过"必须是两件事：后者要说一句话，前者什么都别说。
  Future<FnthinkPairLinkOutcome?> take() async {
    final String? raw;
    try {
      raw = await _channel.invokeMethod<String>('takeFnthinkPairLink');
    } catch (e) {
      // 通道没接（纯 Dart 测试、桌面、旧包）⇒ 按"没有链接"处理：这一发本来就不是必须发生的动作，
      // 把它抛上去会让首页的启动那一串跟着失败。
      debugPrint('[fnthink] 取配对链接失败（按没有待处理的链接处理）: $e');
      return null;
    }
    if (raw == null || raw.isEmpty) return null;
    final FnthinkContract contract;
    try {
      contract = await contracts.load();
    } on FnthinkContractUnavailable catch (e) {
      return FnthinkPairLinkOutcome(
        reason: 'contract-unavailable: ${e.reason}',
      );
    }
    final parsed = FnthinkPairingRequest.parse(contract, raw);
    if (!parsed.ok) {
      return FnthinkPairLinkOutcome(reason: parsed.internalReason);
    }
    return FnthinkPairLinkOutcome(request: parsed.request);
  }
}
