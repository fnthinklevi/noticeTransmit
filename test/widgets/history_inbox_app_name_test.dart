import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_setup.dart';

/// T195：收件历史与详情都要看得见**来源应用名**（维护者 2026-10-25：状态栏能看、进来就没了）。
///
/// 三条判据，各钉一个"不这么做会怎样"：
///  ① 行上有（与状态栏一致的那个名字）—— 缺了就是他现在报的这件事；
///  ② 详情里单列一行「应用：…」—— 行上那枚徽标只有几个字，长应用名会被截；
///  ③ **空串不画**（手动发送／旧发送端／端点消息）—— 画一枚空徽标或一行「应用：」，
///     等于替一条没有来源的消息编一个来源。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  stubNativeChannels();

  setUp(() async {
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<NotificationService>(
      NotificationService(),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  tearDown(() async => GetIt.instance.reset());
  tearDownAll(clearNativeChannelStubs);

  FnthinkInboxMessage row(String id, {String appName = ''}) =>
      FnthinkInboxMessage(
        messageId: id,
        sender: 'endpoint:ep_7',
        type: 'notice',
        item: '',
        title: '机箱温度',
        body: '温度 63 度（$id）',
        receivedAt: 1780000000000,
        direction: kFnthinkDirectionIn,
        appName: appName,
      );

  Future<void> pump(WidgetTester tester, List<FnthinkInboxMessage> rows) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: HistoryPage(
          initialDirection: 'received',
          forwardedLoader: fakeForwardedLoader(const []),
          forwardedCountLoader: () async => 0,
          onClear: () async {},
          onExport: () async => <String, dynamic>{},
          onClearToday: () async => 0,
          onClearLastN: (n) async => 0,
          inboxLoader: () async => rows,
          sentLoader: () async => const [],
          inboxMarkRead: (id) async => false,
          // 详情要按地址码查名单；不注入就会去 GetIt 里取 `FnthinkPeerService`（本用例不装 DI）。
          inboxFindPeer: (address) async => null,
          inboxUnreadCount: () async => 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('收件行与详情都显示来源应用名', (tester) async {
    await pump(tester, [row('m_app', appName: '微信')]);

    expect(find.text('微信'), findsOneWidget, reason: '收件行上没有来源应用名');

    await tester.tap(find.byKey(const ValueKey('fnthink-inbox-row-m_app')));
    await tester.pumpAndSettle();
    expect(find.text('应用：微信'), findsOneWidget, reason: '收件详情里没有单列「应用：…」那一行');
  });

  testWidgets('空来源不画占位（手动发送／旧行／端点）', (tester) async {
    await pump(tester, [row('m_manual')]);

    expect(
      find.textContaining('应用：'),
      findsNothing,
      reason: '详情里出现了空的「应用：」⇒ 给一条没有来源的消息编了来源',
    );
    await tester.tap(find.byKey(const ValueKey('fnthink-inbox-row-m_manual')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('应用：'),
      findsNothing,
      reason: '打开详情之后出现了空的「应用：」行',
    );
  });
}
