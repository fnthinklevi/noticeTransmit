import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/notification_service.dart';

import '../test_setup.dart';

/// T48 收件展示层：历史页的「收件（幻念）」那一档。
///
/// 两条各对应一个"写歪了用户会怎么被骗"：
///  ① 方向是**数据源切换**，不是又一个筛选条件 —— 收件行与转发记录来自两张表、分页口径不同，
///     拼进同一条时间线的表现是"翻页时同一条出现两次、或整条一次都不出现"；
///  ② 未读点只跟着表里 `read` 那一列，页面**不自建第二份"看没看过"** —— 点完一条就重新读表。
///     已读就**不画**这个点（不画 ≠ 画一个透明的占位），所以断言看的是"点在不在"。
///
/// ⚠ 这里刻意**不开真库**：收件那两件事走页面构造参数注入的那对来源。
/// 上一版把 `test/database` 那套 `createSchemaForTest + debugDatabase` 搬进 `testWidgets`，
/// 结果整份用例卡在 00:00 —— 那条路要向平台通道要真实库路径，而桩答 null 就永远等不到。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  stubNativeChannels();

  setUp(() async {
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<NotificationService>(
      NotificationService(),
    );
  });
  tearDown(() async => GetIt.instance.reset());
  tearDownAll(clearNativeChannelStubs);

  FnthinkInboxMessage row(String id, {bool read = false}) =>
      FnthinkInboxMessage(
        messageId: id,
        sender: 'endpoint:ep_7',
        type: 'notice',
        item: '',
        title: '机箱温度',
        body: '温度 63 度（$id）',
        receivedAt: 1780000000000,
        read: read,
        ackResult: 'displayed',
      );

  /// 一张替身"表"：loader 每次被调用都返回当下的状态，标已读就地改它 ——
  /// 这样"页面重新读表"在测试里是一次真的读表，而不是对写死期望的附和。
  late List<FnthinkInboxMessage> table;
  late List<String> marked;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HistoryPage(
          records: const [],
          onClear: () async {},
          onExport: () async => <String, dynamic>{},
          onClearToday: () async => 0,
          onClearLastN: (_) async => 0,
          inboxLoader: () async => List.of(table),
          inboxMarkRead: (id) async {
            marked.add(id);
            final at = table.indexWhere((m) => m.messageId == id);
            if (at < 0) return false; // 那行已经不在了（被保留策略裁掉）
            table[at] = row(id, read: true);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(HistoryPage)));

  Future<void> toInbox(WidgetTester tester) async {
    await tester.tap(find.text(l10n(tester).fnthinkDirInbox));
    await tester.pumpAndSettle();
  }

  setUp(() {
    table = [row('m_unread'), row('m_read', read: true)];
    marked = <String>[];
  });

  testWidgets('默认停在「转发」档：表里有收件也不混进这张列表', (tester) async {
    await pump(tester);
    expect(find.text(l10n(tester).fnthinkDirInbox), findsOneWidget);
    expect(find.text('机箱温度'), findsNothing, reason: '两张表不拼同一条时间线：没切到收件档就不该看见它');
  });

  testWidgets('切到收件档 ⇒ 未读那行有圆点，已读那行根本不画点', (tester) async {
    await pump(tester);
    await toInbox(tester);
    expect(find.text('机箱温度'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('fnthink-inbox-unread-m_unread')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('fnthink-inbox-unread-m_read')),
      findsNothing,
      reason: '不画 ≠ 画一个透明的点：圆点的有无就是 read 那一列的投影',
    );
  });

  testWidgets('收件表是空的 ⇒ 明说"还没有收到过"，不是一片白', (tester) async {
    table = [];
    await pump(tester);
    await toInbox(tester);
    expect(find.text(l10n(tester).fnthinkInboxEmpty), findsOneWidget);
  });

  testWidgets('点开一条 ⇒ 详情读得到全文，已读是"写表 + 重新读表"的结果', (tester) async {
    await pump(tester);
    await toInbox(tester);
    await tester.tap(find.byKey(const ValueKey('fnthink-inbox-row-m_unread')));
    await tester.pumpAndSettle();
    expect(
      find.text('温度 63 度（m_unread）'),
      findsWidgets,
      reason: '列表只给一行，详情要能读全文',
    );
    expect(marked, ['m_unread']);

    // 收起弹层：它占底部 70%，左上角那一下落在它的 barrier 上。
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fnthink-inbox-unread-m_unread')),
      findsNothing,
      reason: '页面没自己抹状态：它重新读了一次表，而表里 read 已经是 1',
    );
  });

  testWidgets('那行在点开的一瞬间被裁掉了 ⇒ 列表不留下点不开的幽灵行', (tester) async {
    await pump(tester);
    await toInbox(tester);
    // 与点开同一瞬间发生：另一头把它裁掉了，于是标已读回 false。
    table.removeWhere((m) => m.messageId == 'm_unread');
    await tester.tap(find.byKey(const ValueKey('fnthink-inbox-row-m_unread')));
    await tester.pumpAndSettle();
    expect(marked, ['m_unread']);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fnthink-inbox-row-m_unread')),
      findsNothing,
      reason: '表里没有了还挂在界面上，等于让用户去点一条不存在的东西',
    );
  });
}
