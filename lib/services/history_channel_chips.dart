/// 历史记录里通道那一族的**排法与统计**（T133 片2 立，T154 片2 改口径；唯一作者）。
///
/// 这一族只决定两件事：
///  ① **顺序**（[orderChannelsByAttention]）—— 子页里按它排，要人动手的排最前；
///  ② **统计**（[tallyDelivery]）—— 行内那一行「共 N 条通道 · X 成功 · …」。
///
/// "送达了吗"与"可以再发一次吗"各有作者
/// （`NotificationService.matchDeliveryFilter` 与 `repush_eligibility.dart`），
/// 本文件不回答它们。三条判据不能合成一个：注意力序要把 `intercepted` 排在前面
/// （那是通道级事实），而重推池必须把它排在外面（那是用户自己定的规则）。
///
/// ⚠ **折法整族在 T154 片2 退休**（`visibleChannelChips` / `foldedChannelChipCount` /
///   `visibleChannelChipCount`）：维护者 2026-10-15 要的是"行内看结论、细节进子页"，
///   行内不再摊 chip ⇒"露几枚"这个上限失去意义，留着就是死代码。
///   它当初（T133 片2）要解的是"通道一多就 N 枚堆叠、真失败那枚被埋在中间"——
///   那个问题现在由"行内根本不摊 chip"从形状上解掉了，比折叠更彻底。
library;

import '../models/delivery_status.dart';

/// 注意力档位（小的在前）。
///
/// - `failed`／`paused` = 要人动手的那两档（与重推池同集合，但**这不是巧合也不是定义** ——
///   把两者绑成一个判据就又长回"一个名字答两个问题"）；
/// - `intercepted` = 被用户自己的规则拦下，看得见就够了，不需要动手；
/// - `sending`／`pending`／**说不清的（含空状态）** = 还没个结论，等一下或本就是"仅记录"；
/// - `success` = 没事，排最后。
int deliveryAttention(String status) {
  const attention = <String, int>{
    'failed': 0,
    'paused': 1,
    'intercepted': 2,
    'sending': 3,
    'pending': 3,
    'success': 4,
  };
  return attention[status] ?? 3;
}

String _statusOf(Map<String, dynamic> deliveryStatus, String channel) {
  final info = deliveryStatus[channel];
  return info is Map ? (info['status']?.toString() ?? '') : '';
}

/// 按注意力排好序的通道名。
///
/// ⚠ **稳定**排序：同档保持记录里的原顺序。否则每次 rebuild 都可能换序，
/// 同一行在两次泵帧之间自己跳 —— 那不是信息，是噪音。
List<String> orderChannelsByAttention(
  List<String> rows,
  Map<String, dynamic> deliveryStatus,
) {
  final indexed = rows.asMap().entries.toList();
  indexed.sort((a, b) {
    final byAttention = deliveryAttention(
      _statusOf(deliveryStatus, a.value),
    ).compareTo(deliveryAttention(_statusOf(deliveryStatus, b.value)));
    return byAttention != 0 ? byAttention : a.key.compareTo(b.key);
  });
  return indexed.map((e) => e.value).toList();
}

/// 一条记录的**送达统计**（T154 片2）。
///
/// 维护者 2026-10-15：「要『共X条通道·Y成功·Z失败·查看详情』子页」——
/// 此前行内把那几枚 chip 全摊开（带折叠），用户的第一个问题是"这条到底成没成"，
/// 而摊开的 chip 只回答"每一格分别是什么"。统计回答前者，子页回答后者。
///
/// ⚠ 三档的**成员判定不在这里写**：成了是 `deliveredStatuses`（本机推成功与
/// 对端已取走都算）、没成是 `notDeliveredStatuses`（三位都在
/// `lib/models/delivery_status.dart`，与历史页筛选、桶值算的是同一张表）。
/// 这里只做"按那张表数一遍"。
/// `queued`（T154 片1 新档）落在 [inFlight]：它没有到对端，但也确实不是失败。
class DeliveryTally {
  const DeliveryTally({
    required this.total,
    required this.done,
    required this.failed,
    required this.inFlight,
  });

  final int total;
  final int done;
  final int failed;
  final int inFlight;

  bool get isEmpty => total == 0;
}

/// 数一遍这条记录的每一格。
DeliveryTally tallyDelivery(Map<String, dynamic> deliveryStatus) {
  var done = 0;
  var failed = 0;
  var other = 0;
  for (final info in deliveryStatus.values) {
    final status = info is Map ? (info['status']?.toString() ?? '') : '';
    if (deliveredStatuses.contains(status)) {
      done++;
    } else if (notDeliveredStatuses.contains(status)) {
      failed++;
    } else {
      // 空状态（仅记录那一档）、`pending`、`queued`、以及任何认不出的词：
      // 都算"还没到对端"。认不出的不许猜成成功也不许猜成失败 —— 与
      // `deliveryBucketOf` 的 fail-closed 是同一个方向（宁可说不清，不许替它判）。
      other++;
    }
  }
  return DeliveryTally(
    total: deliveryStatus.length,
    done: done,
    failed: failed,
    inFlight: other,
  );
}
