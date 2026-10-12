import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/widgets/history_row_tile.dart';

import '../support/source_guards.dart';

/// T148 片1（维护者 2026-10-12 第 3 条：「抽象首页推送历史的格式，后面所有历史页照它长」）。
///
/// 通用件抽出来不是为了让代码少几行，是为了**两类读数从此只有一种画法**：
/// 时间那一格（差异②：远程执行那页根本没有时间）与状态那一枚
/// （差异③：三套画法，其中一套把状态拼进正文、还拿 `default:` 兜底）。
/// 这两件都在本件里，所以本文件钉的是它们，不钉字号（字号漂了不影响谁说谎）。
void main() {
  Future<void> pump(WidgetTester tester, Widget row) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      CupertinoApp(
        home: Material(child: ListView(children: [row])),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('时间那一格只有一个作者', () {
    test('0 与 null 都回空串，不画出一个 1970', () {
      expect(historyRowTime(null), '');
      expect(
        historyRowTime(0),
        '',
        reason:
            '0 是"这一条没有时间"，不是 1970-01-01 08:00 —— 把未知画成一个具体时刻，'
            '用户会拿它去排序、去对账',
      );
    });

    test('有值时是 `MM-DD HH:MM`（与首页转发行同一支笔）', () {
      final t = historyRowTime(
        DateTime(2026, 10, 12, 9, 7).millisecondsSinceEpoch,
      );
      expect(t, '10-12 09:07');
    });
  });

  group('行的形状与 key', () {
    testWidgets('给了时间才画那一格；没给就不留空位', (tester) async {
      await pump(
        tester,
        const HistoryRowTile(
          keyNamespace: 'demo-history',
          identity: 'r1',
          title: 'L2 · listener:start',
          time: '10-12 09:07',
        ),
      );
      expect(
        find.byKey(const ValueKey('demo-history-time-r1')),
        findsOneWidget,
      );

      await pump(
        tester,
        const HistoryRowTile(
          keyNamespace: 'demo-history',
          identity: 'r2',
          title: 'L2 · listener:start',
        ),
      );
      expect(
        find.byKey(const ValueKey('demo-history-time-r2')),
        findsNothing,
        reason: '空串占位读起来像"这条真没时间"，而通常是这一页还没把它接进来',
      );

      // 调用方拿到的是 `historyRowTime` 的空串（那一层把 0/null 都收成 `''`），
      // 所以"没给"在现实里有两种写法，两样都不许画出格子。
      await pump(
        tester,
        const HistoryRowTile(
          keyNamespace: 'demo-history',
          identity: 'r5',
          title: 'L2 · listener:start',
          time: '',
        ),
      );
      expect(find.byKey(const ValueKey('demo-history-time-r5')), findsNothing);
    });

    testWidgets('状态那枚：圆点与文字同一支颜色，词由调用方给', (tester) async {
      await pump(
        tester,
        const HistoryRowTile(
          keyNamespace: 'demo-history',
          identity: 'r3',
          title: 'L2 · listener:start',
          status: '执行中',
          statusColor: Color(0xFFFF0000),
        ),
      );
      final dot = tester.widget<Container>(
        find.byKey(const ValueKey('demo-history-status-dot-r3')),
      );
      final status = tester.widget<Text>(
        find.byKey(const ValueKey('demo-history-status-r3')),
      );
      final decoration = dot.decoration! as BoxDecoration;
      expect(
        decoration.shape,
        BoxShape.circle,
        reason: '状态是一枚"点 + 词"，不是拼在正文里的一句（差异③那一套）',
      );
      expect(
        decoration.color,
        status.style!.color,
        reason: '点色与字色分开写，改一处就会出现"红点配绿字"那种对不上号的读数',
      );
      expect(status.data, '执行中');
    });

    testWidgets('正文那一格：给了才画，空串不占行', (tester) async {
      await pump(
        tester,
        const HistoryRowTile(
          keyNamespace: 'demo-history',
          identity: 'r6',
          title: '标题',
          subtitle: '正文摘要',
        ),
      );
      expect(
        find.byKey(const ValueKey('demo-history-subtitle-r6')),
        findsOneWidget,
      );

      await pump(
        tester,
        const HistoryRowTile(
          keyNamespace: 'demo-history',
          identity: 'r7',
          title: '标题',
          subtitle: '',
        ),
      );
      expect(
        find.byKey(const ValueKey('demo-history-subtitle-r7')),
        findsNothing,
        reason: '没有正文的记录（短信验证码那类）留一行空行，读起来像这一页缺了东西',
      );
    });

    testWidgets('标题/来源/状态三行都挂得上 key（页面不许再各拼一份）', (tester) async {
      await pump(
        tester,
        const HistoryRowTile(
          keyNamespace: 'demo-history',
          identity: 'r4',
          title: '标题',
          source: '来自 8K3F',
          status: '已完成',
          statusColor: Color(0xFF34C759),
        ),
      );
      for (final k in const [
        'demo-history-row-r4',
        'demo-history-title-r4',
        'demo-history-source-r4',
        'demo-history-status-r4',
      ]) {
        expect(
          find.byKey(ValueKey(k)),
          findsOneWidget,
          reason: '缺了 $k ⇒ 用例与闸门只能按中文措辞定位，改一个字就瞎',
        );
      }
    });
  });

  group('历史页确实改走了通用件（否则本文件只是自证）', () {
    final root = projectRoot();
    String read(String rel) =>
        stripComments(File('$root/$rel').readAsStringSync());

    test('远程执行历史那一行不再自己拼散文', () {
      final page = read('lib/pages/remote_history_page.dart');
      expect(
        page,
        contains('HistoryRowTile('),
        reason: '这一页是清单上最远的一家（纯文本行）：它接上了，形状才算有第二家在用',
      );
      expect(
        page,
        contains('historyRowTime('),
        reason: '差异②：那一页此前**根本没有时间**这一列',
      );
      expect(
        page,
        isNot(contains(r"' · $state'")),
        reason: '状态回到"拼在正文里"那一套 = 差异③回来，而本件就成了摆设',
      );
    });

    test('转发行那一页的时间不再各写一份笔', () {
      final page = read('lib/pages/history_page.dart');
      expect(
        page,
        contains('historyRowTime('),
        reason: '基座那页也要用同一支笔，否则"照它长"没有参照物',
      );
      expect(
        page,
        isNot(contains('fromMillisecondsSinceEpoch')),
        reason: '页面里再留一份格式化 ⇒ 下一次改格式还是各改各的',
      );
    });

    test('转发行本体走通用件（行壳与四格小字不再自己拼）', () {
      final page = read('lib/pages/history_page.dart');
      final row = blockAfter(page, 'Widget _buildRecordItem(');
      expect(
        row,
        contains('HistoryRowTile('),
        reason: '这一页是通用件的基座；基座自己不走它，"照它长"就没有被照着的那一家',
      );
      expect(
        row,
        isNot(contains('InkWell(')),
        reason: '行壳（点击／长按／圆角／内边距）归件；页面再拼一份就是差异①回到原地',
      );
      expect(
        row,
        isNot(contains('fontSize: 15')),
        reason: '标题字号回到页面里各写一份 ⇒ 下一次改版式还是各改各的',
      );
      expect(
        row,
        isNot(contains('width: 36')),
        reason: '首字母盒的画法归件（差异①那一族的最后一处）',
      );
    });
  });
}
