import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
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

  FnthinkInboxMessage row(
    String id, {
    bool read = false,
    String sender = 'endpoint:ep_7',
    String direction = kFnthinkDirectionIn,
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

  /// 一张替身"表"：loader 每次被调用都返回当下的状态，标已读就地改它 ——
  /// 这样"页面重新读表"在测试里是一次真的读表，而不是对写死期望的附和。
  late List<FnthinkInboxMessage> table;
  late List<FnthinkInboxMessage> sentTable;
  late List<String> marked;
  late int loads;
  late int sentLoads;

  /// 「回复 / 重发」要用到的两个替身（T48 收尾）：名单里有没有那一台、以及发出去那一下。
  /// 记账放进 [sent] 是因为这一格的语义全在"发的是谁、标题与正文各是什么"上。
  late List<({String address, String title, String text})> sent;
  late FnthinkSendResult Function() sendResult;
  late List<String> findPeerCalls;

  Future<void> pump(
    WidgetTester tester, {
    String initialDirection = 'forwarded',
    FnthinkPeer? rosterPeer,
    String? focusMessageId,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HistoryPage(
          initialDirection: initialDirection,
          focusMessageId: focusMessageId,
          records: const [],
          onClear: () async {},
          onExport: () async => <String, dynamic>{},
          onClearToday: () async => 0,
          onClearLastN: (_) async => 0,
          inboxLoader: () async {
            loads++;
            return List.of(table);
          },
          // 「我发过的」那一档的替身（T43）：同一张表的另一半，用另一个记账位。
          sentLoader: () async {
            sentLoads++;
            return List.of(sentTable);
          },
          inboxMarkRead: (id) async {
            marked.add(id);
            final at = table.indexWhere((m) => m.messageId == id);
            if (at < 0) return false; // 那行已经不在了（被保留策略裁掉）
            table[at] = row(id, read: true, sender: table[at].sender);
            return true;
          },
          // 名单替身：**只有传了 rosterPeer 才算在册**（生产那边是 `FnthinkPeerService.list`）。
          inboxFindPeer: (address) async {
            findPeerCalls.add(address);
            return rosterPeer != null && rosterPeer.peerAddress == address
                ? rosterPeer
                : null;
          },
          inboxSendTo: ({required peer, required title, required text}) async {
            sent.add((address: peer.peerAddress, title: title, text: text));
            return sendResult();
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
    sentTable = [];
    marked = <String>[];
    loads = 0;
    sentLoads = 0;
    sent = [];
    findPeerCalls = [];
    sendResult = () => const FnthinkSendResult(
      status: FnthinkSendStatus.accepted,
      messageId: 'm_reply_1',
    );
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

  testWidgets('首页那张未读卡把人直接放进收件档：一进来就读表，不等那一次「切」', (tester) async {
    await pump(tester, initialDirection: 'received');
    expect(
      find.text('机箱温度'),
      findsNWidgets(2),
      reason: '没点过方向条就看见收件行 —— 预置档真的生效了',
    );
    expect(loads, 1, reason: 'initState 里读一次。少了这一次读，预置档就是一张永远的空表');
  });

  testWidgets('默认档不预读收件表：进历史页不该顺手查另一张表', (tester) async {
    await pump(tester);
    expect(loads, 0);
  });

  // ── T83：点通知跳进来，展开的就是那一条 ──────────────────────────────
  // 这一族用例钉的是"那一次点击到底被不被接住"。判据③（拿不到 id 不许猜一条）与
  // "读表之前没有行可展开"这两件事，都只有在这里才看得见 —— 原生那一半的接线形状
  // 由 `FnthinkNotificationOpenContractTest` 钉，交付一次即清由 `FnthinkOpenTargetTest` 钉。
  group('点通知跳进来（focusMessageId）', () {
    testWidgets('带着 messageId 进来 ⇒ 读完表就自动展开那一条，并标成已读', (tester) async {
      await pump(
        tester,
        initialDirection: 'received',
        focusMessageId: 'm_unread',
      );
      expect(
        find.text('温度 63 度（m_unread）'),
        findsWidgets,
        reason: '点的是这一条，详情却没起来 ⇒ 那一次点击又被吞了一次',
      );
      expect(marked, ['m_unread'], reason: '跳进来就是看过了：不标已读，首页那个未读数会一直举着');
    });

    testWidgets('那一条已经不在表里 ⇒ 明说"不在了"，不许悄悄停在列表', (tester) async {
      await pump(
        tester,
        initialDirection: 'received',
        focusMessageId: 'm_already_pruned',
      );
      expect(
        find.text(l10n(tester).fnthinkMessageGoneFromHistory),
        findsOneWidget,
        reason: '什么都不显示，用户只会读成"App 坏了" —— 而他刚刚明明点了一条通知',
      );
      expect(
        find.text('温度 63 度（m_unread）'),
        findsNothing,
        reason: '找不到就展开别的行，比什么都不做更糟（判据③：不许猜一条）',
      );
      expect(marked, isEmpty, reason: '没展开的那条不许被标成已读');
    });

    testWidgets('普通进入（没人指定）⇒ 一次弹层都不起，也不说那句"不在了"', (tester) async {
      await pump(tester, initialDirection: 'received');
      expect(
        find.text(l10n(tester).fnthinkMessageGoneFromHistory),
        findsNothing,
        reason: '那句话是一次跳转的答复，不是给每次进页的欢迎语',
      );
      expect(find.text('温度 63 度（m_unread）'), findsNothing);
    });
  });

  group('收件详情里的「回复 / 重发」（T48 收尾）', () {
    const peerAddress = 'PEER00000000000001';
    const peer = FnthinkPeer(
      peerAddress: peerAddress,
      publicKey: 'AAAApeerPublicKeyBytes',
      level: 'L1',
      grantedAt: 1767223200000,
    );

    Future<void> openDetail(WidgetTester tester, String id) async {
      await toInbox(tester);
      await tester.tap(find.byKey(ValueKey('fnthink-inbox-row-$id')));
      await tester.pumpAndSettle();
    }

    testWidgets('发送方在名单里 ⇒ 回复/重发两个入口在；不在名单里 ⇒ 一个都不给', (tester) async {
      // 在册：那一格才有入口
      table = [row('m_from_peer', sender: peerAddress)];
      await pump(tester, rosterPeer: peer);
      await openDetail(tester, 'm_from_peer');
      expect(find.byKey(const ValueKey('fnthink-inbox-reply')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('fnthink-inbox-resend')),
        findsOneWidget,
      );

      // 不在册：连查都不用查第二次 —— 给一个必然 403 的按钮比不给更坏
      await tester.tapAt(const Offset(20, 20)); // 收弹层
      await tester.pumpAndSettle();
      table = [row('m_from_peer', sender: peerAddress)];
      await pump(tester); // 这次不传 rosterPeer ⇒ 替身答"不在册"
      await openDetail(tester, 'm_from_peer');
      expect(find.byKey(const ValueKey('fnthink-inbox-reply')), findsNothing);
      expect(find.byKey(const ValueKey('fnthink-inbox-resend')), findsNothing);
    });

    testWidgets('回复：标题预填「回复：<原标题>」而正文留空 ⇒ 「发送」是灰的', (tester) async {
      table = [row('m_from_peer', sender: peerAddress)];
      await pump(tester, rosterPeer: peer);
      await openDetail(tester, 'm_from_peer');

      await tester.tap(find.byKey(const ValueKey('fnthink-inbox-reply')));
      await tester.pumpAndSettle();
      final title = tester.widget<TextField>(
        find.byKey(const ValueKey('fnthink-send-title')),
      );
      expect(title.controller!.text, l10n(tester).fnthinkReplyTitle('机箱温度'));
      final submit = tester.widget<TextButton>(
        find.byKey(const ValueKey('fnthink-send-submit')),
      );
      expect(
        submit.onPressed,
        isNull,
        reason: '回复的正文是留空的：空正文发出去那边只收到一句空话，而回执照样算"送达"',
      );
    });

    testWidgets('取消 ⇒ 一个字节都不发（草稿不回传）', (tester) async {
      table = [row('m_from_peer', sender: peerAddress)];
      await pump(tester, rosterPeer: peer);
      await openDetail(tester, 'm_from_peer');

      await tester.tap(find.byKey(const ValueKey('fnthink-inbox-reply')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('fnthink-send-body')),
        findsNothing,
        reason: '点了取消弹层还开着 ⇒ 用户以为取消了',
      );
      expect(sent, isEmpty, reason: '取消之后还是发出去了 ⇒ 「取消」说的与做的不一致');
    });

    testWidgets('重发：原文预填进弹层，点发送 ⇒ 发的是这条的标题与正文', (tester) async {
      table = [row('m_from_peer', sender: peerAddress)];
      await pump(tester, rosterPeer: peer);
      await openDetail(tester, 'm_from_peer');

      await tester.tap(find.byKey(const ValueKey('fnthink-inbox-resend')));
      await tester.pumpAndSettle();
      final title = tester.widget<TextField>(
        find.byKey(const ValueKey('fnthink-send-title')),
      );
      final body = tester.widget<TextField>(
        find.byKey(const ValueKey('fnthink-send-body')),
      );
      expect(title.controller!.text, '机箱温度');
      expect(body.controller!.text, '温度 63 度（m_from_peer）');

      await tester.tap(find.byKey(const ValueKey('fnthink-send-submit')));
      await tester.pumpAndSettle();

      expect(sent, hasLength(1));
      expect(sent.single.address, peerAddress, reason: '发的是这条的发送方，不是别人');
      expect(sent.single.title, '机箱温度');
      expect(sent.single.text, '温度 63 度（m_from_peer）');
      expect(
        find.byKey(const ValueKey('fnthink-inbox-send-note')),
        findsOneWidget,
        reason: '结论行必须留在弹层里：用户正看着这一条，才知道自己刚回了什么',
      );
    });

    testWidgets('发送方为空（收件行没有来源）⇒ 根本不查名单，也不给入口', (tester) async {
      table = [row('m_no_sender', sender: '')];
      await pump(tester, rosterPeer: peer);
      await openDetail(tester, 'm_no_sender');
      expect(find.byKey(const ValueKey('fnthink-inbox-reply')), findsNothing);
      expect(
        findPeerCalls,
        isEmpty,
        reason: '没有来源就没有可问的地址：拿空串去查名单是白跑一趟，也说明判据写歪了',
      );
    });
  });
  group('「我发过的」那一档（T43）', () {
    Future<void> toSent(WidgetTester tester) async {
      await tester.tap(find.text(l10n(tester).fnthinkDirSent));
      await tester.pumpAndSettle();
    }

    testWidgets('发出档只列发出那半，对端那一列说的是「收件人」', (tester) async {
      table = [row('m_in')];
      sentTable = [
        row(
          'm_out',
          direction: kFnthinkDirectionOut,
          sender: 'PEER00000000000001',
        ),
      ];
      await pump(tester);
      expect(find.text('机箱温度'), findsNothing, reason: '没切档之前不看幻念那两档');

      await toSent(tester);
      expect(sentLoads, 1, reason: '切到发出档要读那一本账，而不是拿收件那份顶上');
      expect(
        find.byKey(const ValueKey('fnthink-inbox-row-m_out')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('fnthink-inbox-row-m_in')),
        findsNothing,
        reason: '收件那半出现在发出档 ⇒ 两本账混起来了（用户会以为自己也发过这条）',
      );
      expect(
        find.textContaining(l10n(tester).fnthinkRecipient),
        findsOneWidget,
        reason: '发出行上的对端是收件人：只说地址码，用户不知道那是谁',
      );
    });

    testWidgets('发出档的行不画未读点（发出的一条没有「未读」这回事）', (tester) async {
      sentTable = [row('m_out', direction: kFnthinkDirectionOut, read: false)];
      await pump(tester);
      await toSent(tester);
      expect(
        find.byKey(const ValueKey('fnthink-inbox-unread-m_out')),
        findsNothing,
        reason: '画了点 ⇒ 用户以为有一条要去看，而那是他自己发出去的',
      );
    });

    testWidgets('点开一条发出的：不标已读、也不重读收件表', (tester) async {
      sentTable = [row('m_out', direction: kFnthinkDirectionOut)];
      await pump(tester);
      await toSent(tester);
      final inboxLoadsBefore = loads;
      await tester.tap(find.byKey(const ValueKey('fnthink-inbox-row-m_out')));
      await tester.pumpAndSettle();

      expect(marked, isEmpty, reason: '标了已读 ⇒ 首页未读数会被自己发的消息减掉');
      expect(loads, inboxLoadsBefore, reason: '发出档不该去重读收件那张表（两本账各有各的读法）');
    });

    testWidgets('发出的档是空的 ⇒ 说「还没有发过」，不是收件档那句空话', (tester) async {
      await pump(tester);
      await toSent(tester);
      expect(find.text(l10n(tester).fnthinkSentEmpty), findsOneWidget);
      expect(
        find.text(l10n(tester).fnthinkInboxEmpty),
        findsNothing,
        reason: '两档的空态说同一句话 ⇒ 用户分不清这台是没收到过还是没发过',
      );
    });
  });
}
