import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';

import '../test_setup.dart';

/// T208：收件档多选 +「确认已读」＋「⋯→一键已读」。
///
/// 这里的判据都是从"不这么做会怎样"倒推出来的：
///  ① 长按进选择态后**点行只切勾选**（要是照旧打开详情，勾第二条时选择态就"消失"了）；
///  ② 批量写完**重新读表**、并把首页那个数交给 `onInboxChanged` 重算 ——
///     页面自己减未读数，减着减着就与库里对不上（列表本来就只有分页过的那些）；
///  ③ 「一键已读」**只在收件档**出现（发出档没有"未读"这一列）；
///  ④ 取消不写库。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  stubNativeChannels();

  setUp(() async {
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<NotificationService>(
      NotificationService(),
    );
    // 收件档装载时要读「发送人显示档」的偏好；不 mock 会一直等平台通道，
    // 页面就一直停在加载圈上（`pumpAndSettle` 当场超时，而它读起来像"页面挂了"）。
    SharedPreferences.setMockInitialValues(<String, Object>{});
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
        direction: kFnthinkDirectionIn,
      );

  late List<FnthinkInboxMessage> inboxTable;
  late List<List<String>> markManyCalls;
  late int markAllCalls;
  late int inboxLoads;
  late int changedCalls;
  late int unread;

  Future<void> pump(
    WidgetTester tester, {
    String initialDirection = 'received',
  }) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: HistoryPage(
          initialDirection: initialDirection,
          forwardedLoader: fakeForwardedLoader(const []),
          forwardedCountLoader: () async => 0,
          onClear: () async {},
          onExport: () async => <String, dynamic>{},
          onClearToday: () async => 0,
          onClearLastN: (n) async => 0,
          inboxLoader: () async {
            inboxLoads++;
            return List<FnthinkInboxMessage>.of(inboxTable);
          },
          sentLoader: () async => const [],
          inboxMarkRead: (id) async => false,
          inboxMarkReadMany: (ids) async {
            markManyCalls.add(ids);
            return ids.length;
          },
          inboxMarkReadAll: () async {
            markAllCalls++;
            return unread;
          },
          inboxUnreadCount: () async => unread,
          onInboxChanged: () => changedCalls++,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    inboxTable = [row('m_a'), row('m_b'), row('m_c', read: true)];
    markManyCalls = [];
    markAllCalls = 0;
    inboxLoads = 0;
    changedCalls = 0;
    unread = 2;
  });

  testWidgets('长按进选择态：顶栏换成「已选 N 条 / 确认已读」，点行只切勾选', (tester) async {
    await pump(tester);
    await tester.longPress(find.byKey(const ValueKey('fnthink-inbox-row-m_a')));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 条'), findsOneWidget, reason: '长按没有进入选择态');
    expect(
      find.byKey(const ValueKey('history-inbox-mark-read')),
      findsOneWidget,
      reason: '顶栏缺「确认已读」那一枚',
    );

    // 点第二行：只切勾选，不开详情（详情页会有 'fnthink-inbox-reply' 那一族动作）
    await tester.tap(find.byKey(const ValueKey('fnthink-inbox-row-m_b')));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 条'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('fnthink-inbox-reply')),
      findsNothing,
      reason: '选择态下点行把详情打开了 ⇒ 用户勾第二条时"选择态看不见了"',
    );

    await tester.tap(find.byKey(const ValueKey('history-inbox-mark-read')));
    await tester.pumpAndSettle();

    expect(markManyCalls.length, 1, reason: '「确认已读」没有调用批量写口');
    expect(markManyCalls.single.toSet(), {
      'm_a',
      'm_b',
    }, reason: '交给写口的 id 不对（勾了哪几条就该写哪几条）');
    expect(changedCalls, 1, reason: '批量之后没有通知首页重算未读数 ⇒ 首页那一格会一直举着旧数字');
    expect(
      inboxLoads,
      greaterThanOrEqualTo(2),
      reason: '批量之后没有重新读表（未读点只能由"读"消失，不能由"减"消失）',
    );
    expect(find.text('已选 1 条'), findsNothing, reason: '写完还停在选择态');
  });

  testWidgets('取消不写库', (tester) async {
    await pump(tester);
    await tester.longPress(find.byKey(const ValueKey('fnthink-inbox-row-m_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(markManyCalls, isEmpty, reason: '取消之后仍然写了库');
    expect(find.text('已选 1 条'), findsNothing);
  });

  testWidgets('「一键已读」只在收件档出现，且要过一次确认', (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('history-inbox-mark-all'));
    expect(entry, findsOneWidget, reason: '收件档的「⋯」里没有「一键已读」');

    await tester.tap(entry);
    await tester.pumpAndSettle();
    // 确认框：正文里带着"将标 N 条"的那个数（N 由未读数读口现读）
    expect(find.textContaining('2'), findsWidgets, reason: '确认框没有报"将标记几条"');
    await tester.tap(find.text('确认已读').last);
    await tester.pumpAndSettle();
    expect(markAllCalls, 1, reason: '确认之后没有调用一键写口');
    expect(changedCalls, 1);
  });

  testWidgets('发出档看不到「一键已读」', (tester) async {
    inboxTable = [];
    await pump(tester, initialDirection: 'sent');
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('history-inbox-mark-all')),
      findsNothing,
      reason: '发出档出现了「一键已读」⇒ 那一档根本没有"未读"这个概念',
    );
  });
}
