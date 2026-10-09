/// 「按关键词搜通话记录」那段正文的组装（T124 片C 的 `calls:search`）。
///
/// 纯函数：输入是原生查询交回来的那几行（`{number, name, type, dateMillis, durationMillis}`），
/// 输出是**一条消息的正文**。形状与 `fnthink_sms_search_report.dart` 逐条同源
/// （同一族的两条路：查询在用例里要真权限与真库，组装这两边各自可测）。
///
/// 四条口径与那一份同源：
///  - **不静默截断**：单条超长打省略号，整段放不下明写「另有 N 条未包含」；
///  - **一条都没命中也要回一句**（带那个词）：空表不是失败；
///  - **只带四件**：时间／方向／对方／时长。`_id`、卡槽、地点都不进 ——
///    多带的每个字段都是一次新的对外披露面；
///  - 预算与单条上限是这几个常量（与另两份同值：它们同样装在"一条消息"里）。
library;

/// 与另两份回传报告的预算同值 —— 都装在"一条消息"里。
const int kFnthinkCallLogReportBudgetChars = 3500;

/// 单条里"对方"那一格的上限（姓名或号码；超了打省略号）。
const int kFnthinkCallLogPartyCap = 40;

/// 一条都没命中时回的那句（**带那个词**：对面要能分辨"搜了没有"与"没搜"）。
String fnthinkCallLogSearchEmptyText(String keyword) => '（没有含「$keyword」的通话记录）';

/// 放不下时那句。
String fnthinkCallLogSearchDroppedText(int n) => '（另有 $n 条因体积上限未包含）';

/// [rows] 按时间**倒序**（最新在前，与原生查询的排序一致）。
String formatFnthinkCallLogReport(
  String keyword,
  List<Map<String, Object?>> rows,
) {
  if (rows.isEmpty) return fnthinkCallLogSearchEmptyText(keyword);
  final lines = <String>[];
  var used = 0;
  var dropped = 0;
  for (final row in rows) {
    final line = _line(row);
    if (line.isEmpty) {
      dropped++;
      continue;
    }
    // 第一条无论如何都进去（装不下也不能回一句"什么都没有"）。
    if (lines.isNotEmpty &&
        used + line.length + 1 > kFnthinkCallLogReportBudgetChars) {
      dropped++;
      continue;
    }
    lines.add(line);
    used += line.length + 1;
  }
  if (lines.isEmpty) return fnthinkCallLogSearchEmptyText(keyword);
  if (dropped > 0) lines.add(fnthinkCallLogSearchDroppedText(dropped));
  return lines.join('\n');
}

/// 通话类型（`CallLog.Calls.TYPE`）→ 一个方向符号。
///
/// ⚠ **不用词**（incoming／missed 那种）：这段正文组装在**被查那台**上，而读的人在
/// 另一台 —— 用词就得选一种语言，选哪边都是错的。符号两边都认得（与拨号盘同一套）。
/// 认不出的类型回空串：不猜一个方向，那一格就不显示。
String _direction(Object? type) {
  return switch (type) {
    1 => '↙', // 来电
    2 => '↗', // 去电
    3 => '✗', // 未接
    5 => '✗', // 拒接（与未接同形：结果都是"没接上"）
    6 => '⊗', // 拦截
    _ => '',
  };
}

String _line(Map<String, Object?> row) {
  final name = _cut('${row['name'] ?? ''}', kFnthinkCallLogPartyCap);
  final number = _cut('${row['number'] ?? ''}', kFnthinkCallLogPartyCap);
  final stamp = _stamp(row['dateMillis']);
  final duration = _duration(row['durationMillis']);
  return [
    if (stamp.isNotEmpty) stamp,
    _direction(row['type']),
    if (name.isNotEmpty) name,
    if (number.isNotEmpty) number,
    if (duration.isNotEmpty) duration,
  ].where((s) => s.isNotEmpty).join(' ');
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

/// 时长：只在**有通话时长**的那几种上出现（未接是 0，回 `(0s)` 不如不回）。
String _duration(Object? millis) {
  if (millis is! int || millis <= 0) return '';
  final sec = millis ~/ 1000;
  if (sec < 60) return '(${sec}s)';
  final min = sec ~/ 60;
  final rest = sec % 60;
  if (min < 60) return '(${min}m${rest.toString().padLeft(2, '0')}s)';
  return '(${min ~/ 60}h${(min % 60).toString().padLeft(2, '0')}m)';
}
