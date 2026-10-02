import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/pages/notification_page.dart';
import 'package:notice_transmit/widgets/app_root.dart';

/// T48 第二片：首页「幻念收件」那一格。
///
/// 钉的是"这一格什么时候该存在"，而不是它长什么样：
///  ① 没有未读 ⇒ **不画**。这台从没接收过、或都读完了，首页不该多出一格跟他无关的入口
///     （"新功能不许改变用户看到的默认界面"那条不变量）。收件档本身一直能从「推送历史」切过去。
///  ② 有未读 ⇒ 画的那个数**就是注入进来的数** —— 页面不许自己数（数法只有 `unreadCount` 一处）。
///  ③ 出口没接上 ⇒ 不画。画一格点不动的入口比不画更坏（幻念推送页那条"死路按钮"同族）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var inboxTaps = 0;
  var historyTaps = 0;

  Widget page({int unread = 0, bool withInboxEntry = true}) {
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
        onOpenHistory: () => historyTaps++,
        onOpenPermissionSettings: () {},
        onOpenChannelStatus: () {},
        onToggleSmsMonitor: (_) {},
        onOpenSmsMonitorSettings: () {},
        fnthinkInboxUnread: unread,
        onOpenInbox: withInboxEntry ? () => inboxTaps++ : null,
      ),
    );
  }

  Future<void> pump(WidgetTester tester, {required int unread}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(page(unread: unread));
    await tester.pumpAndSettle();
  }

  setUp(() {
    inboxTaps = 0;
    historyTaps = 0;
  });

  testWidgets('一条未读都没有 ⇒ 首页不多出这一格', (tester) async {
    await pump(tester, unread: 0);
    expect(find.text('幻念收件'), findsNothing);
    // 「推送历史」那一格不受影响（它是收件档的远路，一直在）
    expect(find.text('推送历史'), findsOneWidget);
  });

  testWidgets('有未读 ⇒ 画的数就是注入的那个数', (tester) async {
    await pump(tester, unread: 3);
    expect(find.text('幻念收件'), findsOneWidget);
    expect(
      find.text('未读 3 条'),
      findsOneWidget,
      reason: '首页报的数与点进去看到的行数必须同源，否则"3 条未读"点进去只有 2 条',
    );
  });

  testWidgets('点它走收件那一格的去向，不走推送历史', (tester) async {
    await pump(tester, unread: 5);
    await tester.tap(find.text('幻念收件'));
    await tester.pump();
    expect(inboxTaps, 1);
    expect(historyTaps, 0, reason: '两格是两个数据源；把收件也导向推送历史，用户就在转发档里找不到的那几条');
  });

  testWidgets('出口没接上 ⇒ 不画一格点不动的入口', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(page(unread: 7, withInboxEntry: false));
    await tester.pumpAndSettle();
    expect(find.text('幻念收件'), findsNothing);
    expect(find.text('未读 7 条'), findsNothing);
  });
}
