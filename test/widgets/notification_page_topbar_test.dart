import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/pages/notification_page.dart';
import 'package:notice_transmit/widgets/app_root.dart';

/// T43：首页顶栏那三格（维护者 2026-10-06 定，右→左：添加设备 → 推送历史 → 设置）。
///
/// 钉三件事，每一件都对应一种"看起来还是好的、其实没接上"的失败：
///  ① **三格都在、顺序是从右往左**（任务书写的是右→左；顺序反了用户点到的就是另一格）；
///  ② **每格点了真的叫到自己的回调** —— 三格共用一条接线时，最容易出现的是
///     「三格都跳同一个地方」，而界面上完全看不出来；
///  ③ **回调没接 ⇒ 那一格不画**（画一个点了没反应的按钮比不画更坏）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var peersTaps = 0;
  var allHistoryTaps = 0;
  var settingsTaps = 0;
  var forwardedTaps = 0;

  Widget page({bool withBar = true}) {
    return AppRoot(
      locale: const Locale('zh'),
      dark: false,
      home: NotificationPage(
        notificationPermissionGranted: true,
        foregroundServiceRunning: true,
        notificationCount: 3,
        onStartService: () {},
        onStopService: () {},
        onRefresh: () async {},
        // 首页那张入口卡仍然是「我转发出去的」—— 顶栏那一格是另一格，别把它的语义改掉。
        onOpenHistory: () => forwardedTaps++,
        onOpenPermissionSettings: () {},
        onOpenChannelStatus: () {},
        onToggleSmsMonitor: (_) {},
        onOpenSmsMonitorSettings: () {},
        onOpenPeers: withBar ? () => peersTaps++ : null,
        onOpenAllHistory: withBar ? () => allHistoryTaps++ : null,
        onOpenSettings: withBar ? () => settingsTaps++ : null,
      ),
    );
  }

  Future<void> pump(WidgetTester tester, {bool withBar = true}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(page(withBar: withBar));
    await tester.pumpAndSettle();
  }

  setUp(() {
    peersTaps = 0;
    allHistoryTaps = 0;
    settingsTaps = 0;
    forwardedTaps = 0;
  });

  testWidgets('三格都在，且顺序是从右往左（添加设备 → 推送历史 → 设置）', (tester) async {
    await pump(tester);

    final add = find.byKey(const ValueKey<String>('home-bar-add-device'));
    final history = find.byKey(const ValueKey<String>('home-bar-history'));
    final settings = find.byKey(const ValueKey<String>('home-bar-settings'));
    expect(add, findsOneWidget);
    expect(history, findsOneWidget);
    expect(settings, findsOneWidget);

    double xOf(Finder f) => tester.getCenter(f).dx;
    expect(
      xOf(add) > xOf(history) && xOf(history) > xOf(settings),
      isTrue,
      reason:
          '任务书写的是右→左；顺序反了用户点到的就是另一格'
          '（现在 添加设备 x=${xOf(add)} 历史 x=${xOf(history)} 设置 x=${xOf(settings)}）',
    );
  });

  testWidgets('三格各叫各的回调，没有三格共用一条接线', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey<String>('home-bar-add-device')));
    await tester.tap(find.byKey(const ValueKey<String>('home-bar-history')));
    await tester.tap(find.byKey(const ValueKey<String>('home-bar-settings')));
    await tester.pumpAndSettle();

    expect(peersTaps, 1, reason: '「添加设备」必须走配对页那一格');
    expect(allHistoryTaps, 1, reason: '「推送历史」必须走含收发那一格');
    expect(settingsTaps, 1, reason: '「设置」必须走设置功能那一格');
    expect(forwardedTaps, 0, reason: '顶栏不该经过首页那张入口卡的回调（它是「我转发出去的」，另一件事）');
  });

  testWidgets('回调没接 ⇒ 那三格都不画（不留点了没反应的按钮）', (tester) async {
    await pump(tester, withBar: false);

    expect(
      find.byKey(const ValueKey<String>('home-bar-add-device')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('home-bar-history')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('home-bar-settings')),
      findsNothing,
    );
  });
}
