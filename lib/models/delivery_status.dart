/// 「这条**送达了吗**」的口径（T133 片3 立词表，T133 走 (c) 起也是**桶值唯一作者**）。
///
/// 这一层现在有两位：两张状态词表（[deliveredStatuses] / [notDeliveredStatuses]）与
/// 一句"这条落哪个桶"（[deliveryBucketOf]）。SQL 那一层不再自己判 —— 它筛的是
/// `notifications.delivery_bucket` 这个**存好的值**（写入时算、迁移时回填，两处都调 [deliveryBucketOf]），
/// 所以"粗筛宽、精筛窄"那一族缺陷从形状上消失了。
///
/// 来历（为什么这里曾经漂开过）：片1 之前 SQL 只 `LIKE '%failed%'`，而精筛认 `failed || intercepted`，
/// 于是只有拦截通道的记录永远进不了候选集，精筛那一半是死的。当时的修法是"LIKE 参数由这张表生成"；
/// 那是**同一条判据抄两遍再想办法让它们相等**，走 (c) 之后只留一遍。
///
/// ⚠ 这一位与「这条**可以再发一次吗**」（`lib/services/repush_eligibility.dart`）
/// 是两个问题，成员集合**故意不同**：
///
/// | 状态 | 算没送达吗（本表） | 可再发吗（那位） | 为什么可以不同 |
/// |---|---|---|---|
/// | `failed` | 算 | 可 | 发失败了，本来就该能重来 |
/// | `paused` | 算 | 可 | 用户暂停期间根本没发出去 |
/// | `intercepted` | 算 | **不可** | 没送达是事实，但那是用户自己定的过滤规则，替他推翻它不叫重推 |
/// | `sending` / `pending` | 不算 | 不可 | 还在途，既没有结果也不该再发一次 |
/// | `success` | 不算 | 不可 | 已经送达，再发一遍 = 同一条通知推两次 |
/// | `delivered` | 不算 | 不可 | 对端已经取走（`messageId` 回执），再发一遍 = 同一条通知推两次 |
library;

/// 唯一算"已送达"的那个状态词。
const String deliveredStatus = 'success';

/// 端到端「已送达」：对端**取走并 ack 了**（T154 片1 的 `messageId ↔ 通知 id` 回执）。
///
/// 与 [deliveredStatus] 都是"成了"，但主语不同：
/// `success` = 本机把它交给了通道（webhook/邮件的终态；或旧的幻念发送口径）；
/// `delivered` = 对端已经收下（服务端 `/poll` 的 `receipts` 回执）。
/// 分开是因为界面要能回答"发出去了"与"对面收下了"这两件事；筛选与统计把它们都算"送达"。
const String peerDeliveredStatus = 'delivered';

/// 算"已送达"的两枚状态词（[deliveryBucketOf] 与历史页统计共用这一张表）。
const List<String> deliveredStatuses = <String>[
  deliveredStatus,
  peerDeliveredStatus,
];

/// 算"没发出去的"那几个状态词 —— 筛选档「没发出去的」与 SQL 粗筛共用这一张表。
const List<String> notDeliveredStatuses = <String>[
  'failed',
  'intercepted',
  'paused',
];

/// 还没有终态的几档（T175 超时清扫只动这几档）。
const List<String> unsettledStatuses = <String>['pending', 'queued'];

/// 超时清扫写下的原因（历史详情会原样显示）。
const String deliveryNoReceiptReason = 'no-receipt';

/// 一条记录多久仍没有终态就当 `failed(no-receipt)`（T175 ②）。
///
/// ⚠ 刻意写成 `Duration(seconds: 30 * 60)` 而不是 `Duration(minutes: 30)`：
/// 通道健康度那条守卫把后者钉成**全 lib 唯一出处**（`channel_health_store.dart`），
/// 而这两个 30 分钟是两件事（健康度时效 vs 送达清扫时限）—— 借那个字面量会让
/// 守卫把两个无关的数字当成一个，改一处时另一处被误伤。
const Duration kDeliveryNoReceiptAfter = Duration(seconds: 30 * 60);

/// 历史详情里的**补行**档（T175 ③）：记录快照里有这一族，送达表里却没有这一格。
///
/// 它只用于显示，不落库、不进桶值：真正的问题是"这一格从来没被谁写过"，
/// 补一个假状态进库会让下一次真回执对不上。（判据见 `_channelRowsOf`。）
const String notAccountedStatus = 'not_accounted';

/// 一条记录的**超时清扫**（T175 ②）：超过 [olderThan] 仍是 `pending`/`queued` 的格子
/// 改成 `failed(no-receipt)`。返回 null = 这一条没有要改的格子。
///
/// 为什么只动这两档：`success`/`delivered` 是终态；`failed`/`paused`/`intercepted`
/// 也是终态。只有"还在路上"会永远停在发送中 —— 而它缺的是一次真实的回执，
/// 不是再来一轮发送。
///
/// 判据放在这里而不是页面：历史页、启动清扫、回前台清扫要读同一份规则。
Map<String, dynamic>? sweepStaleDelivery(
  Map<String, dynamic> delivery, {
  required int postTimeMs,
  required int nowMs,
  required Duration olderThan,
  String reason = deliveryNoReceiptReason,
}) {
  if (postTimeMs <= 0 || nowMs - postTimeMs < olderThan.inMilliseconds) {
    return null;
  }
  var changed = false;
  final next = <String, dynamic>{};
  for (final entry in delivery.entries) {
    final info = entry.value;
    if (info is Map) {
      final status = info['status']?.toString() ?? '';
      if (unsettledStatuses.contains(status)) {
        next[entry.key] = <String, dynamic>{
          ...Map<String, dynamic>.from(info),
          'status': 'failed',
          'message': reason,
        };
        changed = true;
        continue;
      }
    }
    next[entry.key] = info;
  }
  return changed ? next : null;
}

/// 送达状态筛选档的 id（跨层字符串：筛选面板 → service → DB 的 `deliveryFilter` 参数）。
///
/// 名字必须与"这一档回答哪个问题"一致：原先叫 `failed` 而那一档认两种状态，
/// 于是"筛得出、选不中"这类自相矛盾只能靠人记住口径 —— 现在档名直接说"没发出去的"。
const String deliveryFilterAll = 'all';
const String deliveryFilterDelivered = 'delivered';
const String deliveryFilterNotDelivered = 'not_delivered';

/// 一条记录的送达状态 map 落进哪一档（jsonDecode 已由 `NotificationRecord.fromMap` 完成）。
///
/// ⚠ 认不出的档名返回 false（fail-closed）：那一档**什么都不给看**。
/// 宁可看不见，也不要"看起来筛过了其实没筛" —— 后者会把没过滤的结果当成过滤后的读数。
bool matchDeliveryFilter(Map<String, dynamic> status, String filter) {
  // 判据不再在这里写第二遍：这一位只是把桶值与档名比一下（T133 走 (c)）。
  final bucket = deliveryBucketOf(status);
  return switch (filter) {
    deliveryFilterNotDelivered => bucket == deliveryBucketNotDelivered,
    deliveryFilterDelivered => bucket == deliveryBucketDelivered,
    _ => false,
  };
}

/// 送达状态这一问的**第三个去处**：既不是"已送达"也不是"没发出去的"（在途、空 map、脏数据）。
///
/// 它与 DB 列 `delivery_bucket` 的**默认值 `''` 不是一回事**：`''` 说的是"这一行没人算过桶"，
/// 而 `'none'` 说的是"算过了，两个档都不落"。把这两件事分开，写漏桶的 bug 才有被查出来的可能
/// （见 `test/architecture/delivery_bucket_in_sql_test.dart` ④）。
const String deliveryBucketNone = 'none';

/// 两个档各自的桶值 —— **直接复用档名那两颗常量**，不再造第三套词。
const String deliveryBucketDelivered = deliveryFilterDelivered;
const String deliveryBucketNotDelivered = deliveryFilterNotDelivered;

/// 一条记录的送达状态 map 落进哪个桶（T133 走 (c)：这一位是**唯一作者**）。
///
/// 为什么要把"算桶"这一发单独存在而不只是留 `matchDeliveryFilter`：
/// 历史页那一档筛选过去是**两层**的 —— SQL 拿 `delivery_info` 文本 LIKE 粗筛、Dart 再 jsonDecode
/// 精筛。粗筛必然宽于精筛 ⇒ 一页取回 200 行、精筛后只剩 6 行，而"还有没有下一页"是按那 200 行算的，
/// 用户翻到的每一页条数都在跳（分页游标还按粗筛行数列走，于是"第 3 页"根本没有定义）。
/// 把判定结果**存成一列**（写入时就地算、迁移时回填），SQL 那一层就能等值筛 `delivery_bucket`，
/// 两层合成一层 —— 而算桶的那句判据还是这里这一句，两边不可能漂开。
///
/// ⚠ 返回的三值之一就是 DB 里存的那一份，也是 `buildSearchSql` 拿去比的那一份：
///   改这一句的语义 = 改历史页每一档的行数；不改语义就不要动 `delivery_bucket` 的存量值
///   （存量是上一次回填算的，语义一变就得再回填一次，而那要有迁移号可花）。
String deliveryBucketOf(Map<String, dynamic> status) {
  if (status.isEmpty) return deliveryBucketNone;
  final states = status.values
      .whereType<Map>()
      .map((m) => m['status']?.toString())
      .toList();
  // 顺序有意：先认"没发出去的"（任一命中）再认"已送达"（全部相等）。
  // 一条既有 failed 又有 success 的记录，用户要看到的是"它没全送出去"，不是"它送出去过"。
  if (states.any(notDeliveredStatuses.contains)) {
    return deliveryBucketNotDelivered;
  }
  if (states.isNotEmpty && states.every(deliveredStatuses.contains)) {
    return deliveryBucketDelivered;
  }
  return deliveryBucketNone;
}
