/// 「这台已监听的短信留存」这一路怎么读、两路结果怎么并成一条回复（T124 ①）。
///
/// ## 为什么**不新建表**
/// 留存这件事今天就在发生：监听到的短信由 `SmsDispatcher.kt` 出成 `type=sms` 那一发，
/// 跟着历史队列落进 `notifications` 表（正文在 `content` 那一列，v1 起就有）。
/// 再造一张"短信留存表"＝同一份正文在盘上存**两处**，而两处各有各的清除路径 ——
/// 那才是真的把隐私面放大。所以这一路读的就是既有那一格，识别用的还是既有那一列（`type`）。
/// ⚠ 这一句推翻了 `service_locator.dart` 与 `SmsSearch.kt` 里原先那句
/// 「SMS 一进一出、正文不落库」—— 现读：`database_helper.dart` 的 `notifications` 有
/// `content TEXT NOT NULL` 与 `type TEXT NOT NULL`，而 `SmsDispatcher` 写的就是 `type='sms'`。
///
/// ## 这一枚开关回答的不是"存不存"，是"对面能不能读这一格"
/// 存与不存由短信监听那一族决定（那是转发的必需品，本片一字未动）；
/// 本片的默认关那一枚（`fnthink.read.sms_retention`）只管**远端搜索**要不要把这一格算进来源。
/// 关掉时连这一格都不查 ⇒ 与本片落地前的行为逐字相同。
///
/// ## 两路都要带来源，不带就是撒谎
/// 「搜了、没有」在两路上的含义不同：直查那一路空 = 系统库里没有；留存那一路空 = 这台没监听到过。
/// 混成一串回给对面，读的人会以为只有一个来源。所以合并后的每一条带 `source`，
/// 而报告那一格（`fnthink_sms_search_report.dart`）把它画出来。
///
/// ## 转义表与 Kotlin 同源
/// `SmsSearch.escapeLike` 那份钉死了 `\` `%` `_` 三字符（顺序：先转 `\` 本身）。
/// 这一路是 Dart 直接对 SQLite 发 SQL，所以要**再写一份** —— 两处的字面必须逐字符相等，
/// 由 `test/architecture/fnthink_sms_retention_guard_test.dart` 从 Kotlin 源码现取着钉；
/// 上限同理（两路合起来最多带几条，不因来源不同而变）。
library;

/// 留存那一格在 `notifications` 表里的识别值（跨端：作者 `SmsDispatcher.kt` 写的那个 `type`）。
const String kFnthinkSmsRetentionType = 'sms';

/// 一次搜索最多回几条（跨端与 `SmsSearch.LIMIT` 同值；守卫钉着）。
const int kFnthinkSmsSearchTotalLimit = 20;

/// 两路来源的取值（报告与守卫都从这一处取，不各写一份字面量）。
const String kFnthinkSmsSourceDirect = 'direct';
const String kFnthinkSmsSourceRetained = 'retained';

/// LIKE 的字面量化：与 Kotlin 那份同一张三字符表，顺序同样是"先转 `\` 本身"
/// （反过来会把刚加上的转义符再转一遍）。
String escapeFnthinkSmsLike(String keyword) => keyword
    .replaceAll(r'\', r'\\')
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');

/// 留存那一路的 WHERE 与参数（纯函数：SQL 形状单独可测，真库那一发在 `DatabaseHelper`）。
///
/// 参数一律走绑定（`?`），关键词**永不**拼进 SQL 串 —— 这一格装的是别人发来的原文。
({String where, List<Object?> args}) smsRetentionQueryFor(String keyword) => (
  where: r"type = ? AND content LIKE ? ESCAPE '\'",
  args: [kFnthinkSmsRetentionType, '%${escapeFnthinkSmsLike(keyword)}%'],
);

/// 把库里取回的留存行映射成与直查那一路同形的行。
///
/// ⚠ `address` 那一格装的是**通知标题**（短信通知里通常是发件人，可能是一个名字而不是号码）——
/// 这一路没有系统库那个 `address` 列可读，把标题塞进号码位而不说，比说清更糟，
/// 所以来源标记必须一起带上（见 [mergeFnthinkSmsHits]）。
Map<String, Object?> retainedRowFromNotification(Map<String, Object?> row) => {
  'address': row['title'] ?? '',
  'body': row['content'] ?? '',
  'dateMillis': row['post_time'] is int ? row['post_time'] as int : 0,
  'source': kFnthinkSmsSourceRetained,
};

/// 两路合并：**去重 → 按时间倒序 → 截上限**，每条带 [kFnthinkSmsSourceDirect] 或
/// [kFnthinkSmsSourceRetained]。
///
/// 同一条短信完全可能两处都有（系统库里那一行 + 当时监听到的那一行）。去重键取
/// **时间戳 + 正文**这两件，不取号码：两处给的地址那一格常常不同形（系统库是号码，
/// 通知标题可能是名字），把号码算进键就等于"看着是同一条、各回一次"。
/// 时间与正文都逐字相同的两条，本来也没有区分价值 ⇒ 留直查那一条（权威副本）。
List<Map<String, Object?>> mergeFnthinkSmsHits({
  List<Map<String, Object?>> direct = const [],
  List<Map<String, Object?>> retained = const [],
  int limit = kFnthinkSmsSearchTotalLimit,
}) {
  final tagged = <Map<String, Object?>>[
    for (final r in direct) {...r, 'source': kFnthinkSmsSourceDirect},
    for (final r in retained) {...r, 'source': kFnthinkSmsSourceRetained},
  ];
  final seen = <String>{};
  final out = <Map<String, Object?>>[];
  for (final row in tagged) {
    final key = '${row['dateMillis']}|${row['body']}';
    if (!seen.add(key)) continue;
    out.add(row);
  }
  int millis(Map<String, Object?> r) =>
      r['dateMillis'] is int ? r['dateMillis'] as int : 0;
  int rank(Map<String, Object?> r) =>
      r['source'] == kFnthinkSmsSourceDirect ? 0 : 1;
  out.sort((a, b) {
    final byTime = millis(b).compareTo(millis(a));
    return byTime != 0 ? byTime : rank(a).compareTo(rank(b));
  });
  if (limit >= 0 && out.length > limit) return out.sublist(0, limit);
  return out;
}
