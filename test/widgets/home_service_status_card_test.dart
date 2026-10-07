import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/notification_page.dart';
import 'package:notice_transmit/theme/app_colors.dart';
import 'package:notice_transmit/widgets/app_root.dart';

/// 首页那一颗圈的三态：颜色、那句话、点下去做什么，三者必须同时成立。
///
/// 存在的理由（维护者 2026-10-07）：从通知栏或桌面小部件把推送暂停之后，
/// 首页原本只说两句话之一 ——「正在运行，点击可停止」或「未启动，点击可启动」，
/// 而此刻的事实是**监听还在读、发送被暂停**，两句都不对；更要紧的是那一下点击
/// 应该是"恢复推送"，不是"把监听关掉"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var startTaps = 0;
  var stopTaps = 0;
  var resumeTaps = 0;

  Widget page({required bool running, required bool? pushActive}) {
    startTaps = 0;
    stopTaps = 0;
    resumeTaps = 0;
    return AppRoot(
      locale: const Locale('zh'),
      dark: false,
      home: NotificationPage(
        notificationPermissionGranted: true,
        foregroundServiceRunning: running,
        pushActive: pushActive,
        notificationCount: 3,
        onStartService: () => startTaps++,
        onStopService: () => stopTaps++,
        onResumePush: () => resumeTaps++,
        onRefresh: () async {},
        onOpenHistory: () {},
        onOpenPermissionSettings: () {},
        onOpenChannelStatus: () {},
        onToggleSmsMonitor: (_) {},
        onOpenSmsMonitorSettings: () {},
      ),
    );
  }

  /// 那一圈此刻的颜色。⚠ 这里钻 `decoration.color` 是有意的：这一格的判据就是"什么色说什么话"，
  /// 只断文案的话，橙色底配一句"正在运行"照样能过。
  Color circleColor(WidgetTester tester) {
    final box = tester.widget<Container>(
      find.byKey(const ValueKey<String>('service-toggle')),
    );
    return (box.decoration! as BoxDecoration).color!;
  }

  Future<void> tapCircle(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('service-toggle')));
    await tester.pumpAndSettle();
  }

  testWidgets('监听开着、推送暂停 ⇒ 橙色 +「已暂停」+ 那句"继续读取但不推送"', (tester) async {
    await tester.pumpWidget(page(running: true, pushActive: false));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NotificationPage)),
    );

    expect(circleColor(tester), AppColors.orange);
    expect(find.text(l10n.pushPausedShort), findsOneWidget);
    expect(find.text(l10n.servicePausedWhileListening), findsOneWidget);
    // 那句"正在运行，点击可停止"与"未启动，点击可启动"都不许在场：两句都是假话。
    expect(find.text(l10n.serviceRunning), findsNothing);
    expect(find.text(l10n.serviceStopped), findsNothing);
  });

  testWidgets('暂停态那一下点的是"恢复推送"，**不是**停止监听', (tester) async {
    await tester.pumpWidget(page(running: true, pushActive: false));
    await tester.pumpAndSettle();

    await tapCircle(tester);

    expect(resumeTaps, 1, reason: '点它不恢复推送 ⇒ 这一格就是个摆设，用户还得去下拉栏找那枚按钮');
    expect(stopTaps, 0, reason: '把"恢复发送"做成"停止监听"：用户只想把验证码收回来，通知却整台不再读了');
    expect(startTaps, 0);
  });

  testWidgets('监听开着、推送也开着 ⇒ 回到原来的绿色与"点击可停止"', (tester) async {
    await tester.pumpWidget(page(running: true, pushActive: true));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NotificationPage)),
    );

    expect(circleColor(tester), AppColors.green);
    expect(find.text(l10n.running), findsOneWidget);
    expect(find.text(l10n.serviceRunning), findsOneWidget);

    await tapCircle(tester);
    expect(stopTaps, 1, reason: '恢复之后那一格必须回到原有语义，否则"停掉监听"就没有入口了');
    expect(resumeTaps, 0);
  });

  testWidgets('监听没跑 ⇒ 红色那一句，推送开关不许插嘴', (tester) async {
    await tester.pumpWidget(page(running: false, pushActive: false));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NotificationPage)),
    );

    expect(circleColor(tester), AppColors.red);
    expect(find.text(l10n.serviceStopped), findsOneWidget);
    expect(find.text(l10n.servicePausedWhileListening), findsNothing);

    await tapCircle(tester);
    expect(startTaps, 1);
    expect(resumeTaps, 0);
  });

  testWidgets('读不到推送开关 ⇒ 不凭空宣布暂停（通道没接上时按原来两态走）', (tester) async {
    await tester.pumpWidget(page(running: true, pushActive: null));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NotificationPage)),
    );

    expect(circleColor(tester), AppColors.green);
    expect(find.text(l10n.serviceRunning), findsOneWidget);
    expect(find.text(l10n.servicePausedWhileListening), findsNothing);

    await tapCircle(tester);
    expect(stopTaps, 1, reason: '没读到就仍按"点击可停止"办，动作与屏幕上那句得是同一件');
    expect(resumeTaps, 0);
  });
}
