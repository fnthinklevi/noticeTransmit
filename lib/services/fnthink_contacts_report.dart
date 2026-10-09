/// 「按关键词搜通讯录」那段正文的组装（T124 片C-4 的 `contacts:search`）。
///
/// 纯函数：输入是原生查询交回来的那几行（`{name, number}`），输出是**一条消息的正文**。
/// 形状与短信/通话记录那两份逐条同源。
///
/// 四条口径与那两份同源：
///  - **不静默截断**：单条超长打省略号，整段放不下明写「另有 N 条未包含」；
///  - **一条都没命中也要回一句**（带那个词）：空表不是失败；
///  - **只带两件**：姓名与号码。联系人 id、头像、备注、地址都不进 ——
///    多带的每个字段都是一次新的对外披露面（通讯录比短信更宽，这条更要紧）；
///  - 预算与单条上限是这几个常量（与另三份同值：它们同样装在"一条消息"里）。
library;

/// 与另三份回传报告的预算同值 —— 都装在"一条消息"里。
const int kFnthinkContactsReportBudgetChars = 3500;

/// 单条里姓名那一格的上限。
const int kFnthinkContactsNameCap = 40;

/// 单条里号码那一格的上限（号码正常远短于此）。
const int kFnthinkContactsNumberCap = 40;

/// 一条都没命中时回的那句（**带那个词**：对面要能分辨"搜了没有"与"没搜"）。
String fnthinkContactsSearchEmptyText(String keyword) => '（没有含「$keyword」的联系人）';

/// 放不下时那句。
String fnthinkContactsSearchDroppedText(int n) => '（另有 $n 条因体积上限未包含）';

/// [rows] 按原生交回的次序（按姓名排序，与原生查询一致）。
String formatFnthinkContactsSearchReport(
  String keyword,
  List<Map<String, Object?>> rows,
) {
  if (rows.isEmpty) return fnthinkContactsSearchEmptyText(keyword);
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
        used + line.length + 1 > kFnthinkContactsReportBudgetChars) {
      dropped++;
      continue;
    }
    lines.add(line);
    used += line.length + 1;
  }
  if (lines.isEmpty) return fnthinkContactsSearchEmptyText(keyword);
  if (dropped > 0) lines.add(fnthinkContactsSearchDroppedText(dropped));
  return lines.join('\n');
}

String _line(Map<String, Object?> row) {
  final name = _cut('${row['name'] ?? ''}', kFnthinkContactsNameCap);
  final number = _cut('${row['number'] ?? ''}', kFnthinkContactsNumberCap);
  return [if (name.isNotEmpty) name, if (number.isNotEmpty) number].join(' ');
}

String _cut(String s, int cap) {
  if (s.length <= cap) return s;
  return '${s.substring(0, cap)}…';
}
