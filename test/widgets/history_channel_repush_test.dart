import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/fnthink_card.dart';
import 'package:notice_transmit/widgets/primary_action_button.dart';

import '../test_setup.dart';

/// T154 片3：送达详情子页里的**逐格重推**（维护者 2026-10-15：「只有整条一个『再发一次』，
/// 要『共X条通道·Y成功·Z失败·查看详情』子页」的后一半）。
///
/// 这一族盯的是五件事，缺一件就有一类错法能静默回来：
/// 1. **每一格都有一枚**，包括已送达的 —— 逐格比行内那一枚更严的话，界面上会出现
///    「我能一次重推全部，却不能只重推其中一条」，与本片要修的那条是同一个反方向；
/// 2. 按下去交回的是**那一格**，一格不多（多一格就是"多点一下多收一条"）；
/// 3. **已删除的通道**：钮**置灰留着**而不是消失，且底部有一句说清为什么 ——
///    原生只对配着的通道扇出，放行一枚按了不动的钮 = 那一格永远停在「发送中」
///    （T150 片1 修的正是这一族）；
/// 4. 底部「全部重推」交回的是**可再发的那几格**（不是全部，也不是空）；
/// 5. 页面**不自己判**"哪些发得出去" —— 那是服务层 `canRepushChannelIndividually` 的活，
///    页面只把它读出来画成灰的。
///
/// 按 key 找，不按文案：子页里「重推此通道」每格都长得一样。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();
  stubNativeChannels();

  tearDown(() async {
    await GetIt.instance.reset();
    clearNativeChannelStubs();
  });

  setUp(() async {
    await GetIt.instance.reset();
    // 与 `history_repush_entry_test` 同一条：这一页自己会去取 NotificationService。
    GetIt.instance.registerSingleton<NotificationService>(
      NotificationService(),
    );
  });

  NotificationRecord row(String id, Map<String, dynamic> delivery) {
    return NotificationRecord.fromMap({
      'id': id,
      'title': '取件码',
      'content': '1-2-3456',
      'appName': '驿站',
      'packageName': 'com.example.station',
      'postTime': 1758768000000,
      'time': '2026-10-15 10:00',
      'type': 'normal',
      'deviceName': '测试机',
      'channels': delivery.keys.toList(),
      'deliveryStatus': delivery,
    });
  }

  /// 页面实际交回去的那几发（`recordId → 范围`），顺序按发生次序。
  late List<(String, List<String>)> pushed;
  late Set<String> available;

  Future<void> pumpHistory(
    WidgetTester tester,
    List<NotificationRecord> records, {
    bool wire = true,
  }) async {
    pushed = [];
    available = {'chan:dingtalk', 'chan:email'};
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: HistoryPage(
          forwardedLoader: fakeForwardedLoader(records),
          forwardedCountLoader: () async => records.length,
          onClear: () async {},
          onExport: () async => <String, dynamic>{},
          onClearToday: () async => 0,
          onClearLastN: (_) async => 0,
          onPushNow: (_) async {},
          channelRepushAvailable: (c) => available.contains(c),
          onPushChannels: wire
              ? (record, channels) async => pushed.add((record.id, channels))
              : null,
          // 与 `history_repush_entry_test` 同一条理由：详情弹层起来之前要先查送达日志。
          deliveryLogsLoader: (_) async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester, String recordId) async {
    await tester.tap(find.byKey(ValueKey('history-delivery-detail-$recordId')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('history-delivery-detail-title')),
      findsOneWidget,
      reason: '前置：子页没开起来 ⇒ 下面全部是空断言',
    );
  }

  Key chipRepushKey(String recordId, String channel) =>
      ValueKey('history-channel-repush-$recordId-$channel');

  FnthinkInlineAction chipAction(
    WidgetTester tester,
    String recordId,
    String channel,
  ) => tester.widget<FnthinkInlineAction>(
    find.byKey(chipRepushKey(recordId, channel)),
  );

  testWidgets('每一格都有一枚「重推此通道」，已送达的那格也不例外', (tester) async {
    await pumpHistory(tester, [
      row('n-1', {
        'chan:dingtalk': {'status': 'success', 'message': 'ok'},
        'chan:email': {'status': 'failed', 'message': '超时'},
      }),
    ]);
    await openSheet(tester, 'n-1');

    expect(
      find.byKey(chipRepushKey('n-1', 'chan:dingtalk')),
      findsOneWidget,
      reason: '成功的通道没有钮 ⇒ 「我能一次重推全部，却不能只重推其中一条」',
    );
    expect(
      chipAction(tester, 'n-1', 'chan:dingtalk').onPressed,
      isNotNull,
      reason: '钮在但点不动 = 同一种错，只是更隐蔽（用户读成 App 坏了）',
    );
  });

  testWidgets('逐格那一枚走公共件且取 action 档（不留自搭壳、不冒充中性）', (tester) async {
    await pumpHistory(tester, [
      row('n-1', {
        'chan:email': {'status': 'failed', 'message': '超时'},
      }),
    ]);
    await openSheet(tester, 'n-1');

    final action = chipAction(tester, 'n-1', 'chan:email');
    expect(action.tone, FnthinkActionTone.action);
    expect(
      action.label,
      AppLocalizations.of(tester.element(find.byType(HistoryPage)))
          .historyChannelRepush,
      reason: '文案取词表那一位，不在页面里写字面量',
    );
  });

  testWidgets('按某一格 ⇒ 交回的就是那一格，一格不多', (tester) async {
    await pumpHistory(tester, [
      row('n-1', {
        'chan:dingtalk': {'status': 'success', 'message': 'ok'},
        'chan:email': {'status': 'failed', 'message': '超时'},
      }),
    ]);
    await openSheet(tester, 'n-1');

    await tester.tap(find.byKey(chipRepushKey('n-1', 'chan:email')));
    await tester.pumpAndSettle();

    expect(pushed, hasLength(1));
    expect(pushed.single.$1, 'n-1');
    expect(pushed.single.$2, [
      'chan:email',
    ], reason: '多带一格 = 用户多点一下，收件端就多收一条 —— 这正是本片要修的那条');
    expect(
      find.byKey(const ValueKey('history-delivery-detail-title')),
      findsNothing,
      reason: '这一发之后那一行会变「发送中」，留在屏上给的是发之前那一帧的读数',
    );
  });

  testWidgets('已删除的通道：那枚置灰留着，底部有一句说清为什么', (tester) async {
    await pumpHistory(tester, [
      row('n-1', {
        'chan:dingtalk': {'status': 'success', 'message': 'ok'},
        'chan:email': {'status': 'failed', 'message': '超时'},
      }),
    ]);
    available = {'chan:email'};
    await tester.pumpAndSettle();
    await openSheet(tester, 'n-1');

    expect(
      find.byKey(chipRepushKey('n-1', 'chan:dingtalk')),
      findsOneWidget,
      reason: '置灰 ≠ 消失：整枚不画，用户读到的是"这里没有这个功能"',
    );
    expect(chipAction(tester, 'n-1', 'chan:dingtalk').onPressed, isNull);
    expect(
      find.byKey(const ValueKey('history-delivery-gone-note')),
      findsOneWidget,
      reason: '灰着却不给理由 = 界面替本机撒了一次谎（用户会以为 App 出 bug）',
    );
  });

  testWidgets('底部「全部重推」交回的是可再发的那几格，不是全部、也不是空', (tester) async {
    await pumpHistory(tester, [
      row('n-1', {
        'chan:dingtalk': {'status': 'success', 'message': 'ok'},
        'chan:email': {'status': 'failed', 'message': '超时'},
      }),
    ]);
    available = {'chan:email'};
    await tester.pumpAndSettle();
    await openSheet(tester, 'n-1');

    await tester.tap(find.byKey(const ValueKey('history-delivery-repush-all')));
    await tester.pumpAndSettle();

    expect(pushed.single.$2, ['chan:email']);
    expect(
      pushed.single.$2,
      isNot(contains('chan:dingtalk')),
      reason: '名字叫"全部"却带了发不出去的那一格 ⇒ 那一格会被抹成 pending 且永远没有回执',
    );
  });

  testWidgets('一格都不可再发 ⇒ 底部那枚置灰留着（不藏）', (tester) async {
    await pumpHistory(tester, [
      row('n-1', {
        'chan:dingtalk': {'status': 'success', 'message': 'ok'},
      }),
    ]);
    available = <String>{};
    await tester.pumpAndSettle();
    await openSheet(tester, 'n-1');

    final all = tester.widget<PrimaryActionButton>(
      find.byKey(const ValueKey('history-delivery-repush-all')),
    );
    expect(all.onPressed, isNull);
    expect(
      find.byKey(const ValueKey('history-delivery-repush-all')),
      findsOneWidget,
      reason: '置灰不等于消失（同上）',
    );
  });

  testWidgets('这一页没接补推（onPushChannels 为 null）⇒ 逐格与底部都置灰', (tester) async {
    await pumpHistory(tester, [
      row('n-1', {
        'chan:email': {'status': 'failed', 'message': '超时'},
      }),
    ], wire: false);
    await openSheet(tester, 'n-1');

    expect(chipAction(tester, 'n-1', 'chan:email').onPressed, isNull);
    expect(
      tester
          .widget<PrimaryActionButton>(
            find.byKey(const ValueKey('history-delivery-repush-all')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('判据来自注入的那一位：页面不自己问"这一族还在不在"', (tester) async {
    await pumpHistory(tester, [
      row('n-1', {
        'chan:telegram': {'status': 'failed', 'message': '超时'},
      }),
    ]);
    // `chan:telegram` 是真族，但**不在 `available` 里**（这一族现在没配着通道）
    await openSheet(tester, 'n-1');

    expect(chipAction(tester, 'n-1', 'chan:telegram').onPressed, isNull);
  });

  testWidgets('channels 为空的那一条回退到 deliveryStatus 的键（T154 片3）', (tester) async {
    // 老记录与「无真实通道、只留拦截标记」那一类就是这个形状（迁移注释点名过）。
    // ⚠ 不回退的话子页顶上一句「共 1 条通道」而下面一格都不画 —— 自己跟自己打架。
    final bare = NotificationRecord.fromMap({
      'id': 'n-bare',
      'title': '取件码',
      'content': '1-2-3456',
      'appName': '驿站',
      'packageName': 'com.example.station',
      'postTime': 1758768000000,
      'time': '2026-10-15 10:00',
      'type': 'normal',
      'deviceName': '测试机',
      'channels': <String>[],
      'deliveryStatus': <String, dynamic>{
        'chan:blocked': {'status': 'intercepted', 'message': '命中关键词'},
      },
    });
    await pumpHistory(tester, [bare]);
    await openSheet(tester, 'n-bare');

    expect(
      find.byKey(chipRepushKey('n-bare', 'chan:blocked')),
      findsOneWidget,
      reason: '那一格没画出来 ⇒ 子页显示「共 1 条通道」而下面是空的，且"全部重推"范围为空',
    );
    expect(
      tester
          .widget<PrimaryActionButton>(
            find.byKey(const ValueKey('history-delivery-repush-all')),
          )
          .onPressed,
      isNull,
      reason: '拦截那一族不配着通道 ⇒ 置灰（可按会把那一格写成 pending 且永远没有回执）',
    );
  });
}
