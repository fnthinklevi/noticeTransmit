import 'package:flutter/foundation.dart';
import 'package:fnthink_push/fnthink_push.dart';

/// 一轮收到的「投递回执」落到本机两本账上的**唯一作者**（T194）。
///
/// 两本账：
///  - `fnthink_messages` 的 ack 那一对列（[recordAck]）—— in 方向写的是「我报出去的
///    时刻」，out 方向写的是「它收下的时刻」；
///  - 通知历史里幻念那一格（[recordDelivery]）—— T154 端到端「已送达」。
///
/// 收货循环与「发件回执看守」都走这一处：两条路各抄一份的话，某一天一边补了
/// 「没带时刻就不写」，另一边没补，表现就是「锁屏时收到的回执不落历史、回前台才落」
/// 这种按入口分裂的事实。
///
/// 单条失败不打断整轮：本轮里还有别的消息要落库与 ack。
Future<int> applyFnthinkReceipts({
  required Iterable<FnthinkReceipt> receipts,
  Future<bool> Function({
    required String messageId,
    required String result,
    required int at,
  })?
  recordAck,
  Future<void> Function(String messageId, String receipt)? recordDelivery,
}) async {
  var applied = 0;
  for (final receipt in receipts) {
    // 时刻只影响 `fnthink_messages` 那一对列（不许拿 nowMs 凑）；端到端那一格
    // 不需要时刻，照样要落 —— 否则旧服务端不回时刻时「已送达」永远不出现。
    if (receipt.at <= 0) {
      debugPrint('[fnthink] 回执没带时刻，不猜一个：${receipt.messageId}');
    } else {
      final write = recordAck;
      if (write != null) {
        try {
          await write(
            messageId: receipt.messageId,
            result: receipt.receipt,
            at: receipt.at,
          );
        } catch (e) {
          debugPrint('[fnthink] 回执没记进本机历史：${receipt.messageId} $e');
        }
      }
    }
    final apply = recordDelivery;
    if (apply != null) {
      try {
        await apply(receipt.messageId, receipt.receipt);
      } catch (e) {
        debugPrint('[fnthink] 端到端回执没写进通知历史：${receipt.messageId} $e');
      }
    }
    applied++;
  }
  return applied;
}
