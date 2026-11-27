import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';
import '../models/delivery_status.dart';
import 'channel_display.dart';

/// `messageId → 本地通知记录 id` 的映射（T154 片1 的端到端回执）。
///
/// 为什么需要它：转发那一路只把 `messageId` 交给服务端，而本机历史那一格挂在
/// **通知记录 id** 上。服务端把「对端取走了」的回执按 `messageId` 交回来
/// （`/poll` 的 `receipts`），没有这枚映射就对不上本地那一行。
///
/// 存储走 Dart SharedPreferences（不新增 DB 列）：
///  - 后台转发 isolate 写、收货 isolate 读 ⇒ 读之前 `reload()`（跨 isolate 的
///    SharedPreferences 各有一份缓存，不 reload 会永远读不到对方刚写的那一条）；
///  - 上限 500 条，最旧的先丢：一条消息的回执正常几轮内就到；没到的（对端一直不上线、
///    或本机没开接收循环）也不该让 prefs 无界增长。
class FnthinkDeliveryLinkStore {
  FnthinkDeliveryLinkStore({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  static const String prefsKey = 'fnthink.delivery.links.v1';
  static const int maxLinks = 500;

  final Future<SharedPreferences> Function() _prefs;

  Future<void> link({
    required String messageId,
    required String recordId,
  }) async {
    if (messageId.isEmpty || recordId.isEmpty) return;
    try {
      final prefs = await _prefs();
      // 另一个 isolate 可能刚写过；先 reload 再读改写，别把它的映射覆盖掉。
      await prefs.reload();
      final links = _read(prefs);
      links.removeWhere((e) => e.messageId == messageId);
      links.add(
        _Link(
          messageId: messageId,
          recordId: recordId,
          at: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (links.length > maxLinks) {
        links.removeRange(0, links.length - maxLinks);
      }
      await prefs.setString(
        prefsKey,
        jsonEncode([for (final e in links) e.toJson()]),
      );
    } catch (e) {
      debugPrint('[fnthink] 送达映射写入失败（端到端那一格暂缺）: $e');
    }
  }

  /// 取走并删除这一条映射。null = 没有映射（手动发的/旧版本发的/已被取走）。
  ///
  /// ⚠ P1-4 之后**生产代码不再走它**：它先消耗再交给调用方，而调用方接下来那一步
  /// （写 DB）会失败 —— DB 写失败时映射已经没了，那条回执就再也改不动历史那一行
  /// （审计叫"状态幽灵"）。生产走 [peekRecordId] + 写成功后再 [forgetRecordId]。
  /// 这里保留是因为它表达的"一次消耗"语义本身没有错，只是不该由回执那条路用。
  Future<String?> takeRecordId(String messageId) async {
    if (messageId.isEmpty) return null;
    try {
      final prefs = await _prefs();
      await prefs.reload();
      final links = _read(prefs);
      final at = links.indexWhere((e) => e.messageId == messageId);
      if (at < 0) return null;
      final recordId = links.removeAt(at).recordId;
      await prefs.setString(
        prefsKey,
        jsonEncode([for (final e in links) e.toJson()]),
      );
      return recordId.isEmpty ? null : recordId;
    } catch (e) {
      debugPrint('[fnthink] 送达映射读取失败（按没有映射处理）: $e');
      return null;
    }
  }

  /// **读**这一条映射但**不删**它（P1-4）。
  ///
  /// 与 [takeRecordId] 的差别只有一处：调用方拿到 recordId 之后还要落一次 DB，
  /// 那一步可能失败。先删再写的话，写失败时这一条回执就永远对不上历史那一行了。
  /// 现在只在**DB 写成功之后**才 [forgetRecordId]。
  ///
  /// 重复回执不会因此重复改历史：`applyFnthinkReceiptToDelivery` 对"已经是那个状态"
  /// 返回 null（不降级、不重写），所以留着映射是安全的。
  Future<String?> peekRecordId(String messageId) async {
    if (messageId.isEmpty) return null;
    try {
      final prefs = await _prefs();
      await prefs.reload();
      final links = _read(prefs);
      final at = links.indexWhere((e) => e.messageId == messageId);
      if (at < 0) return null;
      final recordId = links[at].recordId;
      return recordId.isEmpty ? null : recordId;
    } catch (e) {
      debugPrint('[fnthink] 送达映射读取失败（按没有映射处理）: $e');
      return null;
    }
  }

  /// 删掉这一条映射（P1-4：只在**历史那一行真的写成功之后**调）。
  ///
  /// 删不掉不算错：留着的最坏后果是同一条回执下次再被读一次，而那时
  /// `applyFnthinkReceiptToDelivery` 会判成"已经是那个状态"返回 null。
  Future<void> forgetRecordId(String messageId) async {
    if (messageId.isEmpty) return;
    try {
      final prefs = await _prefs();
      await prefs.reload();
      final links = _read(prefs);
      final before = links.length;
      links.removeWhere((e) => e.messageId == messageId);
      if (links.length == before) return;
      await prefs.setString(
        prefsKey,
        jsonEncode([for (final e in links) e.toJson()]),
      );
    } catch (e) {
      debugPrint('[fnthink] 送达映射清理失败（下次那条回执还会被读一次，无害）: $e');
    }
  }

  List<_Link> _read(SharedPreferences prefs) {
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return <_Link>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <_Link>[];
      final out = <_Link>[];
      for (final item in decoded) {
        final link = _Link.fromJson(item);
        if (link != null) out.add(link);
      }
      return out;
    } catch (e) {
      debugPrint('[fnthink] 送达映射不是合法 JSON（按没有处理）: $e');
      return <_Link>[];
    }
  }
}

class _Link {
  const _Link({
    required this.messageId,
    required this.recordId,
    required this.at,
  });

  final String messageId;
  final String recordId;
  final int at;

  Map<String, Object?> toJson() => <String, Object?>{
    'm': messageId,
    'r': recordId,
    't': at,
  };

  static _Link? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final messageId = '${raw['m'] ?? ''}'.trim();
    final recordId = '${raw['r'] ?? ''}'.trim();
    if (messageId.isEmpty || recordId.isEmpty) return null;
    return _Link(
      messageId: messageId,
      recordId: recordId,
      at: (raw['t'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 这条回执是不是一个**终态**（服务端 `receiptsForSender` 只回终态）。
///
/// `displayed` 与 `delivered` 都算"对端收下了"：前者是阅读回执那一族的口径预留，
/// 后者是本仓投递状态机的终态。两个都不是终态的（`queued`/`waiting_online`/未知词）
/// 不许拿来改送达格 —— 那会把"还在路上"写成失败或成功。
bool fnthinkReceiptIsTerminal(String receipt) {
  return receipt == 'delivered' ||
      receipt == 'displayed' ||
      receipt == 'expired' ||
      receipt == 'dropped';
}

/// 把一条服务端回执落到通知记录的 `delivery_info` 上（T154 端到端）。
///
/// 返回 null = 这条回执不该改这一格（非终态 / 本地已是「已送达」）。
/// 纯函数：只算新 map，不写库；写库由 [applyFnthinkDeliveryReceipt] 负责。
Map<String, dynamic>? applyFnthinkReceiptToDelivery(
  Map<String, dynamic> delivery,
  String receipt,
) {
  if (!fnthinkReceiptIsTerminal(receipt)) {
    // 非终态回执（旧服务端/新状态）不猜：宁可不改，也不把「还在路上」写成失败。
    return null;
  }
  final key = channelDeliveryKey(kFnthinkChannelSlug);
  final previous = delivery[key];
  // 一台设备取走就够了：多目标里后到的失败回执不许把「已送达」降级。
  if (previous is Map && previous['status'] == peerDeliveredStatus) return null;
  final String status;
  if (receipt == 'delivered' || receipt == 'displayed') {
    status = peerDeliveredStatus;
  } else {
    status = 'failed';
  }
  final next = Map<String, dynamic>.from(delivery);
  next[key] = <String, dynamic>{
    'status': status,
    'message': 'receipt: $receipt',
    // 与 applyDelivery 同一条粘滞规矩：这一发确实走了备用，后续回执不许把它抹掉。
    if (previous is Map && previous['viaBackup'] == true) 'viaBackup': true,
  };
  return next;
}

/// 通知历史里幻念那一格是否还停在「在路上」（T194 发件回执看守的判据）。
///
/// 读的是**同一份送达模型**（`unsettledStatuses` 与 `channelDeliveryKey`），不在看守里
/// 自己解释一遍字符串 —— 那种第二份解释改一处忘一处，表现是「看守以为没有在等的，
/// 而历史页还画着发送中」。
bool fnthinkDeliveryStillAwaitingReceipt(Map<String, dynamic> delivery) {
  final info = delivery[channelDeliveryKey(kFnthinkChannelSlug)];
  if (info is! Map) return false;
  return unsettledStatuses.contains(info['status']?.toString() ?? '');
}

/// 端到端回执的落库口：`messageId → 记录 id → delivery_info`。
///
/// 生产装配给收件循环的 `recordDelivery`。失败只打印：一条回执写不进历史，
/// 不该让整轮收货停摆；那一格留在 `queued`（"本机交出去了，还不知道对面取没取"）
/// 仍然是一句真话。
///
/// P1-4：这里改成**先读映射 → 写 DB → 写成功才删映射**。原来是先 `takeRecordId`
/// 消耗映射再写 DB，DB 写失败时映射已经没了 ⇒ 那条回执再也改不动历史那一行
/// （审计叫"状态幽灵"：发送端历史永远停在 queued，而对面其实早已收下）。
Future<void> applyFnthinkDeliveryReceipt(
  String messageId,
  String receipt,
) async {
  // 先判词再取映射：一条非终态回执不该碰任何状态 —— 否则同一个 messageId
  // 后面那条真正的 delivered 就再也对不上本机那一行了。
  if (!fnthinkReceiptIsTerminal(receipt)) return;
  final store = FnthinkDeliveryLinkStore();
  final recordId = await store.peekRecordId(messageId);
  if (recordId == null) return;
  try {
    final db = DatabaseHelper();
    final row = await db.getNotificationById(recordId);
    if (row == null) {
      // 那一行已经不在（保留策略裁掉/用户删了）：映射留着也没用，可以清。
      // ⚠ 这是唯一一处"写没发生也删映射"的分支，因为它已经对不上任何行了。
      await store.forgetRecordId(messageId);
      return;
    }
    Map<String, dynamic> info = <String, dynamic>{};
    final raw = row['delivery_info'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          info = Map<String, dynamic>.from(decoded);
        }
      } catch (e) {
        debugPrint('[fnthink] 送达格里的旧值读不出来，按空表重写：$e');
      }
    }
    final next = applyFnthinkReceiptToDelivery(info, receipt);
    if (next == null) {
      // 这一格已经是那个状态（重复回执 / 已到终态不许降级）：账也结完了，删映射。
      await store.forgetRecordId(messageId);
      return;
    }
    await db.updateNotificationDelivery(recordId, next);
    // 写成功了才删映射 —— 这一行的顺序就是 P1-4 的整个要点。
    await store.forgetRecordId(messageId);
  } catch (e) {
    debugPrint('[fnthink] 端到端回执写不进历史（那一格留在原状态，映射保留待下轮重试）: $e');
  }
}
