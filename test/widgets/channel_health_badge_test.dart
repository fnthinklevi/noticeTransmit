import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/widgets/channel_health_badge.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 健康徽标组件自身的显示契约（三族通道页共用它，T04 把两份抄本合成这一份）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChannelHealth health({
    required bool reachable,
    int latencyMs = 42,
    int? probedAt,
  }) => ChannelHealth.fromMap(
    jsonDecode(
          jsonEncode({
            'reachable': reachable,
            'latencyMs': latencyMs,
            'httpCode': reachable ? 200 : 0,
            'probedAt': probedAt ?? DateTime.now().millisecondsSinceEpoch,
          }),
        )
        as Map<String, dynamic>,
  );

  Future<void> show(
    WidgetTester tester,
    ChannelHealth? h, {
    double? width,
    String? absentText,
  }) async {
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: Scaffold(
          body: SizedBox(
            // 列表行副标题的实际可用宽度：手机宽度扣掉图标与右侧开关后只剩 ~170dp。
            width: width,
            child: ChannelHealthBadge(health: h, absentText: absentText),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ChannelHealthBadge', () {
    testWidgets('没有探测记录时不画任何东西（从没测过就什么都不断言）', (tester) async {
      await show(tester, null);
      expect(find.byType(ChannelHealthBadge), findsOneWidget);
      expect(find.byType(Row), findsNothing);
      // ⚠ 光断"没有 Row"不够（反证 G3 证伪过：把 `SizedBox.shrink()` 换成
      //   `SizedBox(height: 1)` 仍然没有 Row ⇒ 假绿）。断的是**占位为零**：
      //   没记录时这一格不占任何高度，行不会为它留出那一行空。
      expect(tester.getSize(find.byType(ChannelHealthBadge)), const Size(0, 0));
    });

    testWidgets('交来 absentText ⇒ 没记录也说话（T103：幻念那一族没有自动探针）', (tester) async {
      // 那一族的记录只能由详情页那一发「仅探测／探测并保存」写入，下拉也刻意不重探。
      // 于是"空白"读起来是"这一族没有健康度"，而真话是"还没测过，要人点一次"——
      // 缺省仍然是不吭声（上面那条钉着），说话与否由调用方决定。
      await show(tester, null, absentText: '从未探测');
      expect(find.text('从未探测'), findsOneWidget);
    });

    testWidgets('absentText 那一格在窄约束下也不溢出（列表行副标题只有 ~170dp）', (tester) async {
      await show(tester, null, width: 170, absentText: '从未探测从未探测从未探测');
      expect(tester.takeException(), isNull);
    });

    testWidgets('可达：画状态与耗时；不可达：画故障', (tester) async {
      await show(tester, health(reachable: true));
      expect(find.textContaining('连通'), findsOneWidget);
      expect(find.textContaining('42 ms'), findsOneWidget);

      await show(tester, health(reachable: false));
      expect(find.text('连接失败'), findsOneWidget);
    });

    testWidgets('有记录但已过期 ⇒ 画灰色「未知」，不替用户宣称正常', (tester) async {
      final stale = health(
        reachable: true,
        probedAt: DateTime.now()
            .subtract(const Duration(hours: 7))
            .millisecondsSinceEpoch,
      );
      await show(tester, stale);
      expect(find.text('状态未知'), findsOneWidget);
      expect(find.textContaining('连通'), findsNothing);
    });

    testWidgets('窄约束（列表行副标题的真实宽度）下不得溢出', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // T07-B 的模拟器闸门红过一轮：状态文字 + "多少分钟前探测"两段都是自然宽度，
      // 在 170dp 的行副标题里放不下 ⇒ `RenderFlex overflowed by 43 pixels`。
      // 桌面尺寸的页面测试看不见这件事（测试视口比手机宽得多）。
      await show(tester, health(reachable: true), width: 170);
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(Row),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Text &&
                (w.overflow == TextOverflow.ellipsis || !w.softWrap!),
          ),
        ),
        findsWidgets,
        reason: '两段文字都得允许收缩，否则放不下的那一版又会把行撑破',
      );
    });
  });
}
