import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// `docs/roadmap.md` 的 §2 任务表：**每个逻辑任务行恰好 4 格**，且**行尾有收尾竖线**。
///
/// 这条守卫的第一版**自己是错的**，错法值得留在文件里：它用 `split('|')` 数格子，
/// 于是把描述里**已经正确转义**的 `\|` 也当成分隔符 ⇒ T26 / T28 / T91 / T66 四行被报成
/// 「列被切坏」，而它们**本来就没坏**。照那份点名去「修」，会把四个正确的行改坏 ——
/// 我已经走到那一步，被自己叫停了。⇒ 判据的第一条不是「有几格」，而是**按什么切**：
/// **只有不被反斜杠转义的 `|` 才是分隔符**（GFM 规则）。
///
/// 它真正抓到的是这两类：
///  ① **行尾漏了收尾竖线**（GFM 渲染容得过去，按列读会把**下一行吞成接续行**）——
///     T26 / T28 两行，2026-10-06 实测；
///  ② **两行被并进一行** —— 仓库踩过两次：T90 那一行被写成多行（8.192 记过），
///     以及 2026-10-06 我自己改 T35/T36 状态格时把「旧状态」留在中间段、拼出 5 格。
void main() {
  final root = projectRoot();
  final file = File('$root/docs/roadmap.md');

  // ⚠ 助手必须声明在用例之前：Dart 的局部函数不能被前面的语句引用。
  final unescapedPipe = RegExp(r'(?<!\\)\|');

  List<String> allLines() =>
      file.readAsStringSync().replaceAll('\r\n', '\n').split('\n');

  List<String> section2() {
    final lines = allLines();
    final start = lines.indexWhere((l) => l.startsWith('## 2.'));
    final end = lines.indexWhere((l) => l.startsWith('## 3.'));
    expect(start, greaterThanOrEqualTo(0), reason: '找不到 §2 标题');
    expect(end, greaterThan(start), reason: '找不到 §3 标题');
    return lines.sublist(start, end);
  }

  /// 把**接续行**并回上一行，返回 `(起始行号, 各格)`。
  ///
  /// 必须并：markdown 表格的一个格子可以跨行。不合并的话，多行的那条会被读成
  /// 「两行、格数都不对」—— 而它其实只是**行数**不对，当成列坏会把原因指错。
  List<({int line, List<String> cells})> logicalRows(List<String> lines) {
    final out = <({int line, List<String> cells})>[];
    final buf = <String>[];
    var bufLine = 0;

    void flush() {
      if (buf.isEmpty) return;
      final parts = buf.join(' ').split(unescapedPipe);
      out.add((line: bufLine, cells: parts.sublist(1, parts.length - 1)));
      buf.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (!l.trimLeft().startsWith('|')) continue;
      if (buf.isEmpty) bufLine = i + 1;
      buf.add(l.trim());
      if (l.trimRight().endsWith('|')) flush();
    }
    flush();
    return out;
  }

  bool isNoise(String first) =>
      first.isEmpty || first.startsWith('-') || first.startsWith('#');

  test('roadmap 在盘上（读不到就是 ABORT，不许静默跳过）', () {
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'docs/roadmap.md 不在 —— 这条守卫必须为真，'
          '否则它会变成「永远通过」的那一种假绿',
    );
  });

  test('§2 每个逻辑任务行恰好 4 格', () {
    final bad = <String>[];
    for (final row in logicalRows(section2())) {
      final first = row.cells.isEmpty ? '' : row.cells.first.trim();
      if (isNoise(first)) continue;
      if (row.cells.length != 4) {
        bad.add(
          '  第 ${row.line} 行「$first」是 ${row.cells.length} 格（表头 4 列）'
          '⇒ 要么行尾漏了收尾竖线（下一行被吞成接续行），要么两行被并进了一行',
        );
      }
    }
    expect(bad, isEmpty, reason: '这些行按列读会读到错的那一格：\n${bad.join('\n')}');
  });

  test('任务行行尾必须有收尾竖线（漏了就把下一行吞进来）', () {
    final missing = <String>[];
    for (var i = 0; i < section2().length; i++) {
      final l = section2()[i];
      if (!l.trimLeft().startsWith('|')) continue;
      if (l.trimRight().endsWith('|')) continue;
      missing.add('  第 ${i + 1} 行「${l.split('|')[1].trim()}」行尾没有 `|`');
    }
    expect(
      missing,
      isEmpty,
      reason: 'GFM 渲染容得过去，但按列读会把下一行吞成接续行：\n${missing.join('\n')}',
    );
  });

  test('正向锚点：转义过的竖线算内容、不算分隔符（第一版就错在这）', () {
    // 拿一份**已正确转义**的样本当锚。若哪天把切分改回 `split('|')`，
    // 这条当场红 —— 而不是等它把四个正确的行报成坏的。
    const escaped = r'| T66 | 归档名 notice_all\| 加 APK_NAME | — | [x] |';
    expect(escaped.split(unescapedPipe).length - 2, 4);
  });

  test('反向锚点：真能数出 4 格的行（防提取退化成恒真）', () {
    final four = logicalRows(section2())
        .where((r) => r.cells.length == 4 && !isNoise(r.cells.first.trim()))
        .length;
    expect(
      four,
      greaterThan(50),
      reason:
          '§2 里能数出 4 格的任务行只有 $four 条 ——'
          '要么解析退化了，要么表被大面积切坏，两种都要知道',
    );
  });
}
