import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/pull_to_refresh_list.dart';

/// 下拉刷新壳（#182）。
///
/// ⚠ 这一份 harness 用**真的 `AppRoot`**（不是 `MaterialApp`）：根组件刚换成 CupertinoApp，
/// 而 `CupertinoSliverRefreshControl` 恰恰是那种"在 Material 壳里看着能用、在 Cupertino 壳里
/// 才见真形态"的控件。往后的逐屏用例请照这一份抄，别再各 pump 一个 MaterialApp。
void main() {
  Widget wrap(Widget child) =>
      AppRoot(locale: const Locale('zh'), dark: false, home: child);

  List<Widget> rows(int n) => [
    for (var i = 0; i < n; i++)
      SizedBox(key: ValueKey('row-$i'), height: 80, width: double.infinity),
  ];

  Future<void> pull(WidgetTester tester) async {
    await tester.fling(
      find.byType(CustomScrollView).first,
      const Offset(0, 240),
      1200,
    );
    await tester.pump();
  }

  group('下拉刷新壳', () {
    testWidgets('拉一下 ⇒ 作者的 onRefresh 恰好跑一次', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        wrap(
          CupertinoPageScaffold(
            child: PullToRefreshList(
              onRefresh: () async {
                calls++;
              },
              children: rows(12),
            ),
          ),
        ),
      );

      await pull(tester);
      expect(calls, 1, reason: '手势没作者 = 这一页根本没有"现在就重探"的入口');
      await tester.pumpAndSettle();
    });

    testWidgets('空态也在这个壳里：没内容可滚时下拉照样触发', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        wrap(
          CupertinoPageScaffold(
            child: PullToRefreshList(
              onRefresh: () async {
                calls++;
              },
              emptyChild: const Center(child: Text('空的')),
              children: rows(0),
            ),
          ),
        ),
      );

      expect(find.text('空的'), findsOneWidget);
      await pull(tester);
      expect(
        calls,
        1,
        reason:
            '空态若画在滚动壳外面（旧写法是一条 Center 分支），列表为空时用户拉不出任何东西 —— '
            '而"一条通道都还没配"恰恰是最想立刻重试的那个人',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('children 逐条画出、顺序即屏幕顺序', (tester) async {
      await tester.pumpWidget(
        wrap(
          CupertinoPageScaffold(
            child: PullToRefreshList(onRefresh: () async {}, children: rows(3)),
          ),
        ),
      );

      for (var i = 0; i < 3; i++) {
        expect(
          find.byKey(ValueKey('row-$i')),
          findsOneWidget,
          reason: '第 $i 条没被画出来 = delegate 用错了（SliverList 的两种构造容易混）',
        );
      }
    });
  });
}
