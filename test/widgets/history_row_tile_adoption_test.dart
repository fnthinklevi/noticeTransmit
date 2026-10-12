import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/filter_service.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/history_row_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_setup.dart';

/// T148 片2（维护者 2026-10-12 第 3 条的后半：「后面其他模块要新增历史记录页了，
/// 都按推送历史的样式和内容来」—— 基座这一页自己也得真的走那个件）。
///
/// 片1 立了件、接了最远的一家（远程执行页），片2 把**基座那页的转发行本体**换上去，
/// 片3 换的是同一页的**收件/发出行**（`_inboxRow`）—— 那张页上从此只有一种行容器。
/// 这一组用例盯的不是像素，而是换壳之后**才会存在**的读数：
/// ① 每一格有自己的 key（页面再自己拼小字，key 形状就跟着措辞漂）；
/// ② 长按语义还挂在这一行上（差异⑤：可点与长按"有的有、有的没有"）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  setUp(() async {
    await GetIt.instance.reset();
    // 桩必须挂在 setUp 里：`clearNativeChannelStubs()` 在 tearDown 把它摘掉，
    // 写在 main 体内只有**第一条**用例有桩 —— 之后的用例里 `getEnabledPackages`
    // 那次 invokeMethod 永远不返回，表现是"长按没反应"，而不是"通道没桩"。
    stubNativeChannels();
    // 长按菜单第一件事是读筛选设置（`_filterService.loadSettings()`），它先等 SharedPreferences；
    // 没 mock 的话回调卡在 await 上 —— 同样是"长按没反应"，而真原因是装配缺件。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GetIt.instance.registerSingleton<NotificationService>(
      NotificationService(),
    );
    GetIt.instance.registerSingleton<FilterService>(FilterService());
  });

  tearDown(() async {
    await GetIt.instance.reset();
    clearNativeChannelStubs();
  });

  NotificationRecord oneRecord() {
    return NotificationRecord.fromMap({
      'id': 'n-adopt',
      'title': '取件码',
      'content': 'A-1-2345',
      'appName': '驿站',
      'packageName': 'com.example.station',
      'postTime': 1758768000000,
      'time': '2026-10-10 10:00',
      'type': 'normal',
      'deviceName': '测试机',
      'channels': <String>[],
      'deliveryStatus': <String, dynamic>{},
    });
  }

  Future<void> pumpHistory(
    WidgetTester tester,
    NotificationRecord record,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: HistoryPage(
          forwardedLoader: fakeForwardedLoader([record]),
          forwardedCountLoader: () async => 1,
          onClear: () async {},
          onExport: () async => <String, dynamic>{},
          onClearToday: () async => 0,
          onClearLastN: (_) async => 0,
          onPushNow: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('那一行有行 key 与标题 key（定位不再靠中文措辞）', (tester) async {
    await pumpHistory(tester, oneRecord());

    expect(
      find.byKey(const ValueKey('history-row-n-adopt')),
      findsOneWidget,
      reason: '行本体没有 key ⇒ 用例与闸门只能按标题文字定位这一行',
    );
    expect(find.byKey(const ValueKey('history-title-n-adopt')), findsOneWidget);
  });

  testWidgets('那一行的正文格由通用件画出来（页面不再拼小字）', (tester) async {
    await pumpHistory(tester, oneRecord());

    expect(
      find.byKey(const ValueKey('history-subtitle-n-adopt')),
      findsOneWidget,
      reason: '正文那一格由通用件画：页面再抄一份 Text，下一次改版式就还是各改各的',
    );
    expect(find.text('A-1-2345'), findsOneWidget);
  });

  testWidgets('来源那一格走通用件的 source', (tester) async {
    await pumpHistory(tester, oneRecord());

    expect(
      find.byKey(const ValueKey('history-source-n-adopt')),
      findsOneWidget,
      reason: '「谁发的」是 source 格，不再挤进正文（差异①里那三种行容器的其中一种）',
    );
    expect(find.text('驿站'), findsOneWidget);
  });

  testWidgets('时间那一格走通用件（与远程执行页同一支笔）', (tester) async {
    await pumpHistory(tester, oneRecord());

    expect(find.byKey(const ValueKey('history-time-n-adopt')), findsOneWidget);
    expect(find.text('09-25 10:40'), findsOneWidget);
  });

  testWidgets('长按那一行还是出菜单（换壳不许把差异⑤换没了）', (tester) async {
    await pumpHistory(tester, oneRecord());

    await tester.longPress(find.byKey(const ValueKey('history-row-n-adopt')));
    await tester.pumpAndSettle();

    expect(
      find.text('屏蔽该应用的通知'),
      findsOneWidget,
      reason:
          '长按菜单是这一行唯一的"就地处置"入口；行壳交给通用件时漏传 onLongPress，'
          '这一格就在页面上静默消失（本仓"装配点漏传不报编译错"那一族的第三次形状）',
    );
  });

  // ── 片3：同一页的收件/发出行也换到那个件上 ────────────────────────────────
  //
  // 这一族的判据②（未读点只跟着表里 `read` 那一列）此前住在 `ListTile` 的 `leading:` 上；
  // 换壳时它必须**原样**活着 —— 件不认得"未读"，所以那一枚仍由页面自己画、经 `badges` 挂进来。
  // ⚠ 行 key 逐字不变（`fnthink-inbox-row-<messageId>`）：闸门与 `history_page_fnthink_inbox_test`
  //   都按它定位，改 key 等于把那一批证据全数作废，而那不是本片要付的代价。
  FnthinkInboxMessage inboxMessage(
    String id, {
    bool read = false,
    bool outgoing = false,
    bool viaBackup = false,
    String ackResult = 'delivered',
  }) => FnthinkInboxMessage(
    messageId: id,
    sender: 'endpoint:ep_7',
    type: 'notice',
    item: '',
    title: '机箱温度',
    body: '温度 63 度（$id）',
    receivedAt: 1780000000000,
    read: read,
    ackResult: outgoing ? '' : ackResult,
    direction: outgoing ? kFnthinkDirectionOut : kFnthinkDirectionIn,
    viaBackup: viaBackup,
  );

  Future<void> pumpInbox(
    WidgetTester tester,
    List<FnthinkInboxMessage> rows, {
    String direction = 'received',
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: HistoryPage(
          initialDirection: direction,
          forwardedLoader: fakeForwardedLoader(const []),
          forwardedCountLoader: () async => 0,
          onClear: () async {},
          onExport: () async => <String, dynamic>{},
          onClearToday: () async => 0,
          onClearLastN: (_) async => 0,
          inboxLoader: () async => List.of(rows),
          sentLoader: () async => List.of(rows),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppLocalizations zh(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(HistoryPage)));

  testWidgets('收件行的四格各有 key（时间不再挤在那串散文里）', (tester) async {
    await pumpInbox(tester, [inboxMessage('m-in')]);

    for (final cell in ['row', 'title', 'time', 'source']) {
      expect(
        find.byKey(ValueKey('fnthink-inbox-$cell-m-in')),
        findsOneWidget,
        reason: '$cell 那一格没有 key ⇒ 页面还在自己拼小字，key 形状跟着措辞漂',
      );
    }
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('fnthink-inbox-time-m-in')))
          .data,
      historyRowTime(1780000000000),
      reason: '时间格交给件里那支笔（差异②：各页时间列不一致）',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('fnthink-inbox-source-m-in')))
          .data,
      'endpoint:ep_7',
      reason: '来源格里只有对端：时间与「备用」都各有自己的格子，不再拼成一串',
    );
  });

  testWidgets('未读点仍只跟着 read 那一列（已读就不画）', (tester) async {
    await pumpInbox(tester, [
      inboxMessage('m-unread'),
      inboxMessage('m-read', read: true),
    ]);

    expect(
      find.byKey(const ValueKey('fnthink-inbox-unread-m-unread')),
      findsOneWidget,
      reason: '换壳时未读点被漏传 ⇒ 这一族再也看不出哪条没读过，而页面一切照常',
    );
    expect(
      find.byKey(const ValueKey('fnthink-inbox-unread-m-read')),
      findsNothing,
    );
  });

  testWidgets('本机报出去的那一串走状态原话那一格', (tester) async {
    await pumpInbox(tester, [inboxMessage('m-in')]);

    expect(
      find.byKey(const ValueKey('fnthink-inbox-status-message-m-in')),
      findsOneWidget,
      reason: '回执不再用 trailing 小字另画一份（差异③：状态三套画法）',
    );
    expect(find.text('delivered'), findsOneWidget);
  });

  testWidgets('发出档：来源那一格说清是收件人，且不画未读点、不画回执', (tester) async {
    await pumpInbox(tester, [
      inboxMessage('m-out', outgoing: true),
    ], direction: 'sent');

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('fnthink-inbox-source-m-out')),
          )
          .data,
      '${zh(tester).fnthinkRecipient}：endpoint:ep_7',
      reason: '发出行上的对端是收件人：只给地址码，用户不知道那是谁',
    );
    expect(
      find.byKey(const ValueKey('fnthink-inbox-unread-m-out')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('fnthink-inbox-status-message-m-out')),
      findsNothing,
    );
  });

  testWidgets('走了备用路由的那一条带「备用」徽标（与另外三族同一个词条）', (tester) async {
    await pumpInbox(tester, [
      inboxMessage('m-backup', outgoing: true, viaBackup: true),
    ], direction: 'sent');

    expect(
      find.text(zh(tester).deliveryViaBackupTag),
      findsOneWidget,
      reason:
          '这一族此前不标，于是同一屏里"webhook 标了、幻念没标"看起来像随机丢；'
          '换壳时它从散文里挪进 badge 口，挪丢了就没人知道',
    );
  });
}
