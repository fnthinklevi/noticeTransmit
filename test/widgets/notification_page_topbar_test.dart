import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/pages/notification_page.dart';
import 'package:notice_transmit/widgets/app_root.dart';

/// 首页顶栏**只有标题，不许有按钮**。
///
/// 来历：T43（`fd4fce7`，2026-10-06）曾在这里加过三格（设置／推送历史／添加设备），
/// 维护者当天判为多此一举并全部删除 —— 三格的目标都另有路：设置＝底部「更多」tab，
/// 历史＝本页那张入口卡，配对名单＝幻念推送页与通知引擎页各有一处。
///
/// 这条用例存在的理由不是"测顶栏长什么样"，而是**钉住它别再长回来**：顶栏加按钮
/// 在界面上永远"看起来是好的"，没有任何测试会因为多一个按钮而红。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget page() {
    return AppRoot(
      locale: const Locale('zh'),
      dark: false,
      home: NotificationPage(
        notificationPermissionGranted: true,
        foregroundServiceRunning: true,
        pushActive: true,
        notificationCount: 3,
        onStartService: () {},
        onStopService: () {},
        onResumePush: () {},
        onRefresh: () async {},
        onOpenHistory: () {},
        onOpenPermissionSettings: () {},
        onOpenChannelStatus: () {},
        onToggleSmsMonitor: (_) {},
        onOpenSmsMonitorSettings: () {},
      ),
    );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
  }

  testWidgets('顶栏里一枚按钮都没有（三格已被判为多余并删除）', (tester) async {
    await pump(tester);

    final bar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(
      bar.actions == null || bar.actions!.isEmpty,
      isTrue,
      reason: '首页顶栏又长出按钮了 —— 要加先问维护者，别默认"顶栏空着浪费"。',
    );
    for (final key in [
      'home-bar-settings',
      'home-bar-history',
      'home-bar-add-device',
    ]) {
      expect(
        find.byKey(ValueKey<String>(key)),
        findsNothing,
        reason: '顶栏那一格的 key「$key」又回来了',
      );
    }
  });

  testWidgets('标题仍在，且首页那张历史卡还是唯一的「推送历史」入口', (tester) async {
    await pump(tester);

    final bar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect((bar.title as Text).data, '通知推送助手');
    // 删顶栏不该顺手把入口删掉：历史这件事仍然有一格能进。
    expect(find.text('推送历史'), findsWidgets);
  });
}
