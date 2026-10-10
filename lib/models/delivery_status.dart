/// 「这条**送达了吗**」的口径（T133 片3，唯一作者）。
///
/// 一张词表 + 一句精筛判定住在这里，而 SQL 粗筛的 LIKE 参数**由这张表生成**
/// （见 `DatabaseHelper.buildSearchSql`）。两层因此不可能漂开 —— 片1 那轮修的正是
/// 漂开之后的样子：粗筛只 `LIKE '%failed%'`，精筛却认 `failed || intercepted`，
/// 于是只有拦截通道的记录永远进不了候选集，精筛那一半是死的。
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
library;

/// 唯一算"已送达"的那个状态词。
const String deliveredStatus = 'success';

/// 算"没发出去的"那几个状态词 —— 筛选档「没发出去的」与 SQL 粗筛共用这一张表。
const List<String> notDeliveredStatuses = <String>[
  'failed',
  'intercepted',
  'paused',
];

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
  if (status.isEmpty) return false;
  final states = status.values
      .whereType<Map>()
      .map((m) => m['status']?.toString())
      .toList();
  if (filter == deliveryFilterNotDelivered) {
    return states.any(notDeliveredStatuses.contains);
  }
  if (filter == deliveryFilterDelivered) {
    return states.isNotEmpty && states.every((s) => s == deliveredStatus);
  }
  return false;
}
