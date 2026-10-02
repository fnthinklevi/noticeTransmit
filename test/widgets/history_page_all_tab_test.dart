import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';

import '../test_setup.dart';

/// T84「全部」档：三本账**并排**看，而不是拼成同一条时间线。
///
/// 三条判据各钉一个"洗成一类会怎样"：
///  ① 每行带来源标识 —— 分组标题会被滚出屏幕，那时"这条属于哪本账"必须还在；
///     转发条目没有对端、幻念条目没有应用来源，混成一堆之后用户会按错类别去筛。
///  ② 标已读只对收件行有意义 —— 转发与发出两类都没有 `read` 这一列，
///     给它们画未读点或点开就标已读，等于替用户"看过"了一条根本没有读状态的东西。
///  ③ 不新增第四种计数 —— AppBar 那个数仍是转发那本账的；三张表分页口径不同，
///     "全部 = 三者之和"当下就不准（这也是为什么分组标题上不写数字）。
///
/// ⚠ 与收件档那组用例一样**不开真库**：三本账都走页面构造参数注入的读口。
/// ⚠ 这里**不点转发行**：那一行走 `_showRecordDetail`，里面要向平台通道问真实库路径，
///    在 `testWidgets` 绑定下那个 `await` 永远不返回（本仓库撞过两次，见 base.md（53）（54））。
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

  FnthinkInboxMessage row(
    String id, {
    bool read = false,
    String sender = 'endpoint:ep_7',
    required String direction,
  }) => FnthinkInboxMessage(
    messageId: id,
    sender: sender,
    type: 'notice',
    item: '',
    title: '机箱温度',
    body: '温度 63 度（$id）',
    receivedAt: 1780000000000,
    read: read,
    ackResult: direction == kFnthinkDirectionOut ? '' : 'displayed',
    direction: direction,
  );

  NotificationRecord record(String id) => NotificationRecord(
    id: id,
    title: '短信验证码',
    content: '转发出去的那一条（$id）',
    subText: '',
    packageName: 'com.example.sms',
    appName: '信息',
    type: 'sms',
    postTime: 1780000001000,
    time: '10:00',
    deviceName: '本机',
  );

  late List<FnthinkInboxMessage> inboxTable;
  late List<FnthinkInboxMessage> sentTable;
  late List<String> marked;
  late int inboxLoads;
  late int sentLoads;

  Future<void> pump(
    WidgetTester tester, {
    String initialDirection = 'all',
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
          records: [record('r_1')],
          onClear: () async {},
          onExport: () async => <String, dynamic>{},
          onClearToday: () async => 0,
          onClearLastN: (_) async => 0,
          inboxLoader: () async {
            inboxLoads++;
            return List.of(inboxTable);
          },
          sentLoader: () async {
            sentLoads++;
            return List.of(sentTable);
          },
          inboxMarkRead: (id) async {
            marked.add(id);
            final at = inboxTable.indexWhere((m) => m.messageId == id);
            if (at < 0) return false;
            inboxTable[at] = row(
              id,
              read: true,
              sender: inboxTable[at].sender,
              direction: kFnthinkDirectionIn,
            );
            return true;
          },
          inboxFindPeer: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(HistoryPage)));

  setUp(() {
    inboxTable = [row('m_in', direction: kFnthinkDirectionIn)];
    sentTable = [row('m_out', direction: kFnthinkDirectionOut)];
    marked = <String>[];
    inboxLoads = 0;
    sentLoads = 0;
  });

  group('「全部」档（T84）', () {
    testWidgets('一屏里同时看得见三本账各一行，且**两本幻念账各读各的**', (tester) async {
      await pump(tester);
      // 转发那行（正文只在详情里出现？不：行标题是 title，副行含内容预览）
      expect(find.text('短信验证码'), findsOneWidget, reason: '转发段没把那张表列出来');
      // 收件与发出两段都在（标题同为「机箱温度」⇒ 两行而不是零行或一行）
      expect(
        find.text('机箱温度'),
        findsNWidgets(2),
        reason: '收件与发出是两本账：只列出一本就是把另一本洗没了',
      );
      expect(inboxLoads, 1, reason: '全部档读收件那本，一次');
      expect(sentLoads, 1, reason: '全部档读发出那本，一次');
    });

    testWidgets('每行前面都有一枚来源标识：三个来源三枚，不是一堆同类（判据①）', (tester) async {
      await pump(tester);
      final t = l10n(tester);
      expect(
        find.byKey(ValueKey('history-all-tag-${t.fnthinkTagForwarded}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('history-all-tag-${t.fnthinkTagInbox}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('history-all-tag-${t.fnthinkTagSent}')),
        findsOneWidget,
      );
      // 分段标题也要在（它们与行首那枚是两套线索：标题会被滚出屏幕）
      expect(
        find.byKey(const ValueKey('history-all-header-forwarded')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('history-all-header-inbox')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('history-all-header-sent')),
        findsOneWidget,
      );
    });

    testWidgets('未读点只画在收件那一行；转发与发出两类根本没有这个入口（判据②）', (tester) async {
      await pump(tester);
      expect(
        find.byKey(const ValueKey('fnthink-inbox-unread-m_in')),
        findsOneWidget,
        reason: '收件行没未读点 ⇒ 这一档把"看过没有"这件事弄丢了',
      );
      expect(
        find.byKey(const ValueKey('fnthink-inbox-unread-m_out')),
        findsNothing,
        reason: '发出的一条没有"未读"这回事',
      );
      // 转发那行的第一枚标记是应用色块（宽 36），不是未读点：整屏只该有上面那一枚未读点。
      expect(find.byIcon(Icons.circle), findsNothing, reason: '转发与发出行不许长出未读点');
    });

    testWidgets('点开收件行会标已读；点开发出行不会（判据②的另一半）', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('fnthink-inbox-row-m_out')));
      await tester.pumpAndSettle();
      expect(marked, isEmpty, reason: '发出的一条被标成已读 = 替用户"看过"了一条没有读状态的东西');
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('fnthink-inbox-row-m_in')));
      await tester.pumpAndSettle();
      expect(marked, ['m_in'], reason: '收件行点开就是看过了：这一段必须仍走原来那一条咽喉');
    });

    testWidgets('没有第四种计数：标题上的数仍是转发那本账，段标题不带数字（判据③）', (tester) async {
      await pump(tester);
      final t = l10n(tester);
      expect(
        find.text(t.historyTitle(1)),
        findsOneWidget,
        reason: 'AppBar 那个数只能还是转发那张表的条数（与各档同一口径）',
      );
      // 段标题就是方向名本身：一旦写成「收件（幻念） 1」这种形状，就是长出了第四种计数
      String headerOf(String kind) => tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(ValueKey('history-all-header-$kind')),
              matching: find.byType(Text),
            ),
          )
          .map((w) => w.data ?? '')
          .join();
      expect(
        headerOf('inbox'),
        t.fnthinkDirInbox,
        reason: '段标题上不许有数字：三张表分页口径不同，"全部 = 三者之和"当下就不准',
      );
      expect(headerOf('sent'), t.fnthinkDirSent);
      expect(headerOf('forwarded'), t.fnthinkDirForwarded);
    });

    testWidgets('顶部那行说明在位：搜索与筛选只作用于「转发」那一段（判据③的另一半）', (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('history-all-note')), findsOneWidget);
      expect(find.text(l10n(tester).fnthinkAllScopeNote), findsOneWidget);
    });

    testWidgets('切到全部档 ⇒ 两本账都读；切回转发档 ⇒ 一次都不多读', (tester) async {
      await pump(tester, initialDirection: 'forwarded');
      expect(inboxLoads, 0, reason: '停在转发档不该顺手查另一张表（与收件档同一条纪律）');
      await tester.tap(find.text(l10n(tester).fnthinkDirAll));
      await tester.pumpAndSettle();
      expect(inboxLoads, 1);
      expect(sentLoads, 1);
      await tester.tap(find.byKey(const ValueKey('direction-chip-forwarded')));
      await tester.pumpAndSettle();
      expect(
        find.text('机箱温度'),
        findsNothing,
        reason: '换档 = 换账本：幻念那两段不许在转发档上留着',
      );
    });
  });
}
