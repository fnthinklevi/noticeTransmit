/// 「按关键词搜短信」那段正文的组装（T124 片B 的 `sms:search`）。
///
/// 纯函数：输入是原生查询交回来的那几行（`{address, body, dateMillis}`），输出是**一条消息的正文**。
/// 为什么拆成纯函数：与 `fnthink_notification_report.dart` 同一理由 —— 回传格式是**对端会读到**
/// 的形状，而查询那一步在用例里要真权限与真库，两边各自可测。
///
/// 四条口径与那一份同源（那是这一族的规矩，不是巧合）：
///  - **不静默截断**：单条超长在正文里明写省略号，整段放不下时明写「另有 N 条未包含」；
///  - **一条都没命中也要回一句**（带那个词）：空表不是失败，对面要知道"搜了、没有"；
///  - **只带三件**：时间／号码／正文。`_id`、会话线程、SIM 槽位都不进 ——
///    回传的是"命中的那几条短信"，多带的每个字段都是一次新的对外披露面；
///  - 预算与单条上限是这几个常量（与通知那一份同值：它们同样装在"一条消息"里）。
library;

/// 与 `fnthink_notification_report.dart` 的预算同值 —— 两条路都装在"一条消息"里。
const int kFnthinkSmsReportBudgetChars = 3500;

/// 单条里号码那一格的上限（超了打省略号；号码正常远短于此）。
const int kFnthinkSmsReportAddressCap = 40;

/// 单条里正文的上限（正文才是"原文"，比别的字段宽）。
const int kFnthinkSmsReportContentCap = 120;

/// 一条都没命中时回的那句（**带那个词**：对面要能分辨"搜了没有"与"没搜"）。
String fnthinkSmsSearchEmptyText(String keyword) => '（没有含「$keyword」的短信）';

/// 放不下时那句。
String fnthinkSmsSearchDroppedText(int n) => '（另有 $n 条因体积上限未包含）';

/// [rows] 按时间**倒序**（最新在前，与原生查询的排序一致）。
String formatFnthinkSmsSearchReport(
  String keyword,
  List<Map<String, Object?>> rows,
) {
  if (rows.isEmpty) return fnthinkSmsSearchEmptyText(keyword);
  final lines = <String>[];
  var used = 0;
  var dropped = 0;
  for (final row in rows) {
    final line = _line(row);
    if (line.isEmpty) {
      dropped++;
      continue;
    }
    // 第一条无论如何都进去（见通知那一份同名注释：装不下也不能回一句"什么都没有"）。
    if (lines.isNotEmpty &&
        used + line.length + 1 > kFnthinkSmsReportBudgetChars) {
      dropped++;
      continue;
    }
    lines.add(line);
    used += line.length + 1;
  }
  if (lines.isEmpty) return fnthinkSmsSearchEmptyText(keyword);
  if (dropped > 0) lines.add(fnthinkSmsSearchDroppedText(dropped));
  return lines.join('\n');
}

String _line(Map<String, Object?> row) {
  final address = _cut('${row['address'] ?? ''}', kFnthinkSmsReportAddressCap);
  final body = _cut('${row['body'] ?? ''}', kFnthinkSmsReportContentCap);
  final stamp = _stamp(row['dateMillis']);
  return [
    if (stamp.isNotEmpty) stamp,
    if (address.isNotEmpty) address,
    if (body.isNotEmpty) body,
  ].join(' ');
}

String _cut(String s, int cap) {
  if (s.length <= cap) return s;
  return '${s.substring(0, cap)}…';
}

String _stamp(Object? millis) {
  if (millis is! int || millis <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  String two(int v) => v < 10 ? '0$v' : '$v';
  return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
