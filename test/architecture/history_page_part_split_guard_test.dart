import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// P1-2 / T184 B：`history_page.dart` 按屏区块拆成 part 之后的结构守卫。
///
/// 拆分本身不是目的：这一条防的是"拆着拆着出现两份实现"与"part 声明漂了但没人发现"。
/// 检查口径一律用 `librarySource`（入口 + 全部 part），负向断言不会因为方法搬进
/// part 文件而变瞎；part 自身再钉"只许是 part of、不许自己 import"。
/// T184 B 另钉入口行数上限（目标 ≤800），防止拆出去一块又被新代码填回来。
void main() {
  final root = projectRoot();
  const entryRel = 'lib/pages/history_page.dart';
  const parts = <String, String>{
    'history_page_actions.dart': '_HistoryPageActions',
    'history_page_filters.dart': '_HistoryPageFilters',
    'history_page_details.dart': '_HistoryPageDetails',
    'history_page_rows.dart': '_HistoryPageRows',
    'history_page_swipe.dart': '_HistoryPageSwipe',
    'history_page_data.dart': '_HistoryPageData',
    'history_page_inbox.dart': '_HistoryPageInbox',
    'history_page_services.dart': '_HistoryPageServices',
  };

  String entrySource() =>
      stripComments(File('$root/$entryRel').readAsStringSync());
  String library() => stripComments(librarySource(root, entryRel));

  test('入口声明的 part 与清单一致，且每个 part 只属于这个 library', () {
    final entry = entrySource();
    final declared = RegExp(
      r"^part\s+'([^']+)'",
      multiLine: true,
    ).allMatches(entry).map((m) => m.group(1)!).toSet();
    expect(
      declared,
      parts.keys.toSet(),
      reason: 'part 声明与拆分台账不一致 ⇒ 要么有文件没接进来，要么入口还挂着旧名字',
    );
    for (final e in parts.entries) {
      final file = File('$root/lib/pages/${e.key}');
      expect(file.existsSync(), isTrue, reason: '${e.key} 不存在');
      final src = stripComments(file.readAsStringSync());
      expect(
        src.contains("part of 'history_page.dart';"),
        isTrue,
        reason: '${e.key} 没有 part of 入口 ⇒ 它会被当成独立 library 编译，私有成员全断',
      );
      expect(
        RegExp(r'^\s*import\s+', multiLine: true).hasMatch(src),
        isFalse,
        reason: '${e.key} 里出现 import ⇒ part 文件只允许复用入口的 import',
      );
      expect(
        src.contains('extension ${e.value} on _HistoryPageState'),
        isTrue,
        reason: '${e.key} 缺 extension ${e.value} on _HistoryPageState',
      );
    }
  });

  test('关键方法在入口 + parts 中恰好一份实现，入口不再保留旧副本', () {
    final lib = library();
    for (final signature in const [
      'Future<void> _handleExport(',
      'Future<void> _runBatchDelete(',
      'Future<void> _showFilterPanel(',
      'Future<void> _showRecordDetail(',
      'Widget _directionBar(',
      'void _setDirection(',
      'Future<void> _loadSearch({',
      'Future<void> _loadInbox(',
      'Future<void> _loadCommandRecords(',
      'Color _getTypeColor(',
    ]) {
      expect(
        RegExp(RegExp.escape(signature)).allMatches(lib).length,
        1,
        reason: '$signature 在入口 + parts 中不是恰好一份 ⇒ 拆分后出现了第二份实现/调用残影',
      );
      expect(
        entrySource().contains(signature),
        isFalse,
        reason: '$signature 仍留在 history_page.dart ⇒ 这一域没有真正搬出去',
      );
    }
  });

  test('入口仍保留 State 字段与生命周期（extension 不能声明字段）', () {
    final entry = entrySource();
    for (final needle in const [
      'class _HistoryPageState extends State<HistoryPage>',
      'bool _selectMode = false;',
      'final Set<String> _selected = {};',
      'final DatabaseHelper _dbHelper = DatabaseHelper();',
      'void initState()',
      'void dispose()',
      'Widget build(BuildContext context)',
    ]) {
      expect(entry.contains(needle), isTrue, reason: '入口缺 $needle');
    }
  });

  test('入口行数 ≤800（T184 B 的拆分目标）', () {
    final lines = File('$root/$entryRel').readAsLinesSync().length;
    expect(
      lines,
      lessThanOrEqualTo(800),
      reason:
          'history_page.dart 现有 $lines 行 ⇒ 超过 T184 B 的 800 行目标；'
          '新逻辑该进对应 part，不要往入口回填',
    );
  });
}
