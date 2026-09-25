import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/widgets/channel_health_badge.dart';
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
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: SizedBox(
            // 列表行副标题的实际可用宽度：手机宽度扣掉图标与右侧开关后只剩 ~170dp。
            width: width,
            child: ChannelHealthBadge(health: h),
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
