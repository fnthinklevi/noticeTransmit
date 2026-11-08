import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/lockscreen_diagnostic_card.dart';

Widget _buildApp(Widget child) =>
    AppRoot(locale: const Locale('zh'), dark: false, home: child);

LockscreenDiagnosticData _data({
  bool exempt = true,
  int count = 0,
  DateTime? latest,
}) => LockscreenDiagnosticData(
  batteryExempt: exempt,
  failureCount: count,
  latestFailureAt: latest,
);

void main() {
  testWidgets('已豁免：绿字声明 + 不给「去设置」入口', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        CupertinoPageScaffold(
          child: LockscreenDiagnosticCard(
            data: _data(exempt: true),
            onRequestExempt: () {},
          ),
        ),
      ),
    );

    expect(find.text('电池优化白名单：已豁免（深睡下网络可用）'), findsOneWidget);
    expect(find.text('电池优化白名单：未豁免'), findsNothing);
    expect(
      find.byKey(const ValueKey('lockscreen-diag-go-settings')),
      findsNothing,
    );
  });

  testWidgets('未豁免：显示「去设置」并回调用到位', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      _buildApp(
        CupertinoPageScaffold(
          child: LockscreenDiagnosticCard(
            data: _data(exempt: false),
            onRequestExempt: () => pressed++,
          ),
        ),
      ),
    );

    expect(find.text('电池优化白名单：未豁免'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lockscreen-diag-go-settings')));
    expect(pressed, 1);
  });

  testWidgets('无失败：计数行说「无」，不冒充有失败', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        CupertinoPageScaffold(
          child: LockscreenDiagnosticCard(
            data: _data(exempt: true, count: 0),
            onRequestExempt: () {},
          ),
        ),
      ),
    );
    expect(find.text('近 24 小时推送失败：无'), findsOneWidget);
    expect(find.textContaining('近 24 小时推送失败：'), findsOneWidget);
  });

  testWidgets('有失败：计数与最近时刻都画出来', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        CupertinoPageScaffold(
          child: LockscreenDiagnosticCard(
            data: _data(
              exempt: false,
              count: 3,
              latest: DateTime(2026, 11, 7, 9, 5),
            ),
            onRequestExempt: () {},
          ),
        ),
      ),
    );
    expect(find.textContaining('近 24 小时推送失败：3 次'), findsOneWidget);
    expect(find.textContaining('最近一次 11-07 09:05'), findsOneWidget);
  });

  testWidgets('官方语义解释原文在卡上（文案零容忍：逐字可对到 PRD §2 引用）', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        CupertinoPageScaffold(
          child: LockscreenDiagnosticCard(
            data: _data(),
            onRequestExempt: () {},
          ),
        ),
      ),
    );
    expect(
      find.textContaining('Suspends network access'),
      findsOneWidget,
      reason: 'Doze 原文引用必须在卡上',
    );
    expect(
      find.textContaining('自动转入重试队列'),
      findsOneWidget,
      reason: 'T241 的新行为（失败自动补发）必须说出口',
    );
  });
}
