import '../models/notification_record.dart';

/// 「回传最近 N 条通知原文」那段正文的组装（T124 片B，`notifications:report`）。
///
/// 纯函数：输入是库里那几行（已归一的 [NotificationRecord]），输出是**一条消息的正文**。
/// 为什么拆成纯函数：回传格式是**对端会读到**的形状，而读库那一步在用例里要开真 sqlite
/// —— 形状与读口分开，两边各自可测（与 `fnthink_l2_actions.dart` 顶部那条同一理由）。
///
/// 四条口径：
///  - **不静默截断**：单条超长在正文里明写省略号，整段放不下时明写「另有 N 条未包含」
///    —— 与协议那条「不静默丢」同一条不变量（对面读到的必须是"这台真的有这些、
///    少的那些是为什么少的"）；
///  - **一条都没有也回一句**：空表不是失败。回空串的话，对面读起来与"这一步没做成"
///    分不开（而执行链那边空串**就是**失败）；
///  - **只带原文要用的四个字段**：时间／应用／标题／正文。设备名、包名、送达状态、
///    优先级都不进 —— 回传的是"通知原文"，多带的每个字段都是一次新的对外披露面；
///  - 预算是这一个常量（契约 `l2.reportsWhy` 只写"固定字符预算"，具体的数只在这里）。
const int kFnthinkReportBudgetChars = 3500;

/// 单条里标题／应用名的上限（超了打省略号）。
const int kFnthinkReportFieldCap = 60;

/// 单条里正文的上限（比别的字段宽 —— 正文才是"原文"）。
const int kFnthinkReportContentCap = 120;

/// 一条都没有时回的那句（**不是空串**：见文件头第二条口径）。
const String kFnthinkReportEmptyText = '（这台设备暂时没有可回传的通知）';

/// 放不下时那句。`{n}` 是被挤掉的那几条的条数。
String fnthinkReportDroppedText(int n) => '（另有 $n 条因体积上限未包含）';

String formatFnthinkNotificationReport(List<NotificationRecord> rows) {
  if (rows.isEmpty) return kFnthinkReportEmptyText;
  final lines = <String>[];
  var used = 0;
  var dropped = 0;
  for (final row in rows) {
    final line = _line(row);
    if (line.isEmpty) {
      dropped++;
      continue;
    }
    // +1 是换行。放不下就从这个位置开始全部记成"未包含"（不静默丢：下面会明写条数）。
    // ⚠ `lines.isNotEmpty` 那一半是刻意的：**第一条无论如何都要进去** —— 单条各项
    //   都有上限（60/60/120），正常配置下第一条必然装得下；真装不下时也不能回一句
    //   "什么都没有"，那会让"这台有东西、只是太长"读成"这台空的"。
    if (lines.isNotEmpty &&
        used + line.length + 1 > kFnthinkReportBudgetChars) {
      dropped++;
      continue;
    }
    lines.add(line);
    used += line.length + 1;
  }
  if (lines.isEmpty) {
    // 全被预算挤掉（理论上不可达：单条本身超预算时也要留一条 —— 那是"这台真的有"）。
    return kFnthinkReportEmptyText;
  }
  if (dropped > 0) lines.add(fnthinkReportDroppedText(dropped));
  return lines.join('\n');
}

/// 单条的写法：`时间 应用 标题：正文`（缺哪段少哪段，不补占位符）。
///
/// ⚠ 时间优先用记录里的 `time`（原生落库时已经按用户时区排好的一份）；
/// 它空着才现算 `postTime` —— 现算那一份按**本机时区**，而回传是发给另一台的，
/// 两台的时区可能不同，所以能用落库那份就不自己算。
String _line(NotificationRecord row) {
  final stamp = row.time.isNotEmpty ? row.time : _stamp(row.postTime);
  final app = _cut(
    row.appName.isNotEmpty ? row.appName : row.packageName,
    kFnthinkReportFieldCap,
  );
  final title = _cut(row.title, kFnthinkReportFieldCap);
  final content = _cut(row.content, kFnthinkReportContentCap);
  final body = [
    if (title.isNotEmpty) title,
    if (content.isNotEmpty) content,
  ].join('：');
  return [
    if (stamp.isNotEmpty) stamp,
    if (app.isNotEmpty) app,
    if (body.isNotEmpty) body,
  ].join(' ');
}

/// 超长就截到 [cap] 并**明写省略号**（截在哪、截了没有，读的人一眼看得到）。
String _cut(String s, int cap) {
  if (s.length <= cap) return s;
  return '${s.substring(0, cap)}…';
}

/// `MM-dd HH:mm`（不引 intl：这一处只要一个稳定形状，两位补零自己写）。
String _stamp(int millis) {
  if (millis <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  String two(int v) => v < 10 ? '0$v' : '$v';
  return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
