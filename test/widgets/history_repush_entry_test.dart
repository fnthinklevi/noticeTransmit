import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/fnthink_card.dart';

import '../test_setup.dart';

/// T133 片1：单条「现在推送」那一枚与批量勾选框，都只认 `repush_eligibility.dart` 那一位作者。
///
/// 这一页级用例盯的是三件事，缺一不可：
/// 1. 入口**出现**的条件 —— 改之前只有 `paused` 才出现，一条真失败的记录在单条这一层没有出口；
/// 2. 入口**不出现**的条件 —— 全部成功、或被用户自己的规则拦下的（那些不该替他推翻）；
/// 3. 批量模式下默认选中的，正是"可再发"的那几条（勾选框与池子同一个作者）。
///
/// 按钮按 `ValueKey('history-push-now-<id>')` 找，不按文案：这一枚每行长得一样。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();
  stubNativeChannels();

  setUp(() async {
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<NotificationService>(
      NotificationService(),
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
    clearNativeChannelStubs();
  });

  NotificationRecord row(
    String id,
    String title,
    Map<String, dynamic> delivery,
  ) {
    return NotificationRecord.fromMap({
      'id': id,
      'title': title,
      'content': '1-2-3456',
      'appName': '驿站',
      'packageName': 'com.example.station',
      'postTime': 1758768000000,
      'time': '2026-10-10 10:00',
      'type': 'normal',
      'deviceName': '测试机',
      'channels': delivery.keys.toList(),
      'deliveryStatus': delivery,
    });
  }

  Future<void> pumpHistory(
    WidgetTester tester,
    List<NotificationRecord> records,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
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
          // 与 `history_row_tile_adoption_test` 同一条理由：详情弹层起来之前要先查送达日志，
          // 真库读口在 widget 测试里永远等不到。注入了它，下面"批量档点行**没**开详情"
          // 才读作"那一格被禁用了"，而不是"这一页的点行本来就打不开东西"。
          deliveryLogsLoader: (_) async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterBatchMode(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量补推'));
    await tester.pumpAndSettle();
  }

  Key pushNowKey(String id) => ValueKey('history-push-now-$id');

  testWidgets('有一条通道失败 ⇒ 这一行给单条出口（改之前只有 paused 才给）', (tester) async {
    await pumpHistory(tester, [
      row('n-failed', '取件码', {
        'chan:dingtalk': {'status': 'success', 'message': 'ok'},
        'chan:email': {'status': 'failed', 'message': '超时'},
      }),
    ]);

    expect(find.byKey(pushNowKey('n-failed')), findsOneWidget);
  });

  testWidgets('暂停期间没发出去的那条同样给出口', (tester) async {
    await pumpHistory(tester, [
      row('n-paused', '取件码', {
        'chan:email': {'status': 'paused', 'message': '转发已暂停'},
      }),
    ]);

    expect(find.byKey(pushNowKey('n-paused')), findsOneWidget);
  });

  testWidgets('T138 ③：暂停那一格说的是「暂停未发送」，带的就是 force 那一发', (tester) async {
    await pumpHistory(tester, [
      row('n-paused', '取件码', {
        'chan:email': {'status': 'paused', 'message': '转发已暂停'},
      }),
    ]);
    final l10n = AppLocalizations.of(tester.element(find.byType(HistoryPage)));

    expect(
      find.text(l10n.deliveryPausedNotSent),
      findsOneWidget,
      reason: '那一格要回答"这条发出去没有"：暂停期间根本没发 —— 不许再只讲开关',
    );
    expect(
      find.text(l10n.pushPausedByUser),
      findsNothing,
      reason: '「已暂停」只说用户动了开关，把它留在送达格里就是把两件事混成一句',
    );
    // 「带 force 那一发」= 片1 的单条出口（它就是那条不受暂停开关限制的路，
    // force=true 在原生那一侧）——这一格上必须摸得到：
    expect(find.byKey(pushNowKey('n-paused')), findsOneWidget);
  });

  testWidgets('被用户自己的规则拦下的那条不给出口 —— 重推不是替他推翻过滤', (tester) async {
    await pumpHistory(tester, [
      row('n-blocked', '取件码', {
        'chan:sms': {'status': 'intercepted', 'message': '黑名单'},
      }),
    ]);

    expect(find.byKey(pushNowKey('n-blocked')), findsNothing);
  });

  testWidgets('全部成功 / 还在途的都不给出口', (tester) async {
    await pumpHistory(tester, [
      row('n-ok', '取件码', {
        'chan:dingtalk': {'status': 'success', 'message': 'ok'},
      }),
      row('n-sending', '取件码2', {
        'chan:dingtalk': {'status': 'sending', 'message': ''},
      }),
    ]);

    expect(find.byKey(pushNowKey('n-ok')), findsNothing);
    expect(find.byKey(pushNowKey('n-sending')), findsNothing);
  });

  testWidgets('批量模式默认只选中可再发的那几条，其余勾选框是死的', (tester) async {
    await pumpHistory(tester, [
      row('n-failed', '取件码', {
        'chan:email': {'status': 'failed', 'message': '超时'},
      }),
      row('n-blocked', '取件码2', {
        'chan:sms': {'status': 'intercepted', 'message': '黑名单'},
      }),
    ]);
    await enterBatchMode(tester);

    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(boxes, hasLength(2));
    // 顺序即列表顺序：第一条可再发、第二条不可
    expect(boxes[0].onChanged, isNotNull, reason: '失败的那条必须可勾选（判据与池子同一个作者）');
    expect(boxes[0].value, isTrue, reason: '进入批量时默认选中的正是可再发的那些');
    expect(boxes[1].onChanged, isNull, reason: '只有拦截通道的那条不该被选进重推池');
    expect(boxes[1].value, isFalse);
  });

  testWidgets('批量底栏「取消」走行内动作件、语义色取中性（T148 片8）', (tester) async {
    await pumpHistory(tester, [
      row('n-failed', '取件码', {
        'chan:email': {'status': 'failed', 'message': '超时'},
      }),
    ]);
    await enterBatchMode(tester);

    // ⚠ 先在进入批量之后解 l10n（这一页还在台上），再断言。
    final l10n = AppLocalizations.of(tester.element(find.byType(HistoryPage)));
    final cancel = tester.widget<FnthinkInlineAction>(
      find.byKey(const ValueKey('history-batch-cancel')),
    );
    expect(
      cancel.label,
      l10n.cancel,
      reason: '那枚 key 不再挂在 `FnthinkInlineAction` 上 ⇒ 底栏又长回一枚自己搭的 Material 文字钮',
    );
    expect(
      cancel.tone,
      FnthinkActionTone.neutral,
      reason: 'tone 回到默认的 action（蓝）⇒ "只退出不改任何一条"这一枚看起来像会动到东西',
    );
  });

  // ── T148 差异⑤：同一行在批量档里的两格语义（F2 的页面级证据）──────────────
  //
  // ⚠ 正面对照不在这两条里，而在 `history_row_tile_adoption_test`：非批量档点行出详情、
  //   长按出动作菜单。那两条绿着，这里的"点行没开详情、长按没弹菜单"才读作**禁用了**
  //   而不是**这两格从来就不通**。
  testWidgets('批量档里点行 = 切换选中，不打开详情', (tester) async {
    await pumpHistory(tester, [
      row('n-failed', '取件码', {
        'chan:email': {'status': 'failed', 'message': '超时'},
      }),
    ]);
    await enterBatchMode(tester);

    final l10n = AppLocalizations.of(tester.element(find.byType(HistoryPage)));
    expect(
      tester.widgetList<Checkbox>(find.byType(Checkbox)).single.value,
      isTrue,
      reason: '前置：进入批量时那条可再发的默认是选中的（否则下面"点一下变不选中"推不出东西）',
    );

    await tester.tap(find.byKey(const ValueKey('history-row-n-failed')));
    await tester.pumpAndSettle();

    expect(
      tester.widgetList<Checkbox>(find.byType(Checkbox)).single.value,
      isFalse,
      reason: '批量档点行必须真的动到"选中"这一格：只改样式不动状态，用户以为取消了勾选',
    );
    expect(
      find.text(l10n.detailInfo),
      findsNothing,
      reason: '勾选的时候点开详情＝在另一层里办另一件事：那一层没有"这条选没选"的读数',
    );
  });

  testWidgets('批量档里长按这一行不出动作菜单（长按那一格禁用）', (tester) async {
    await pumpHistory(tester, [
      row('n-failed', '取件码', {
        'chan:email': {'status': 'failed', 'message': '超时'},
      }),
    ]);
    await enterBatchMode(tester);

    final l10n = AppLocalizations.of(tester.element(find.byType(HistoryPage)));
    await tester.longPress(find.byKey(const ValueKey('history-row-n-failed')));
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.historyActionBlockApp),
      findsNothing,
      reason: '留着长按菜单就是一边勾选一边弹屏蔽项：屏蔽掉的应用与选中的那几条对不上号',
    );
  });

  // ── T148 片15：实心小动作那一档有了唯一作者（差异⑧ 最后两枚登记例外收口）──────
  //
  // ⚠ 两处都按**件**断，不按颜色断：底色/字号/圆角从此由件给，页面里再没有一份可比。
  //   键的宿主是件本身（`FnthinkFilledAction` 收 `super.key`），与同页 `FnthinkNote`
  //   （键挂在内部那枚 Text）相反 ⇒ `find.ancestor` 要带 `matchRoot: true`。
  testWidgets('「现在推送」由实心小动作件给出，且取行内那一档（片15）', (tester) async {
    await pumpHistory(tester, [
      row('n-failed', '取件码', {
        'chan:email': {'status': 'failed', 'message': '超时'},
      }),
    ]);

    final push = tester.widget<FnthinkFilledAction>(
      find.ancestor(
        of: find.byKey(pushNowKey('n-failed')),
        matching: find.byType(FnthinkFilledAction),
        matchRoot: true,
      ),
    );
    expect(
      push.compact,
      isTrue,
      reason:
          '行内那一枚必须取 compact：常规档（15px／竖 10）会把片1〜3 刚统一过的行高顶起来，'
          '而这一行的邻居是 10px 的通道 chip —— 动作件把状态件挤变形，就是"统一"办成了反方向',
    );
    expect(
      push.icon,
      Icons.send,
      reason: '图标由调用方给、形状由件给：丢了它等于用可读性换账面整齐（片8 当初拒绝的那条）',
    );
  });

  testWidgets('底栏那枚「补推」由件画出，且真的画出了可点的宿主（片15）', (tester) async {
    await pumpHistory(tester, [
      row('n-failed', '取件码', {
        'chan:email': {'status': 'failed', 'message': '超时'},
      }),
    ]);
    await enterBatchMode(tester);

    final batch = find.ancestor(
      of: find.byKey(const ValueKey('history-batch-push')),
      matching: find.byType(FnthinkFilledAction),
      matchRoot: true,
    );
    expect(
      batch,
      findsOneWidget,
      reason: '底栏那一枚不再由 `FnthinkFilledAction` 给出 ⇒ 这一页自己那份实心形状又长回来了',
    );
    // ⚠ 这一条钉的是**还在画东西**：件即使 build 成一个空盒子，上面那条按 widget 类型的
    //   查找照样过（节点在树上），只有"有没有可点宿主"这一条看得出。
    expect(
      find.descendant(of: batch, matching: find.byType(CupertinoButton)),
      findsOneWidget,
      reason: '置灰≠消失：把整枚不画了，用户读到的是"选了却没地方按"',
    );
    expect(
      tester.widget<FnthinkFilledAction>(batch).icon,
      Icons.replay,
      reason: '「把这 N 条再发一次」有一半信息量在这个图标上（片8 拒绝丢图标的那条理由）',
    );
  });

  testWidgets('一条都没勾选时底栏那一枚点不动，勾选着时点得动（片15）', (tester) async {
    await pumpHistory(tester, [
      row('n-failed', '取件码', {
        'chan:email': {'status': 'failed', 'message': '超时'},
      }),
    ]);
    await enterBatchMode(tester);

    final batch = find.ancestor(
      of: find.byKey(const ValueKey('history-batch-push')),
      matching: find.byType(FnthinkFilledAction),
      matchRoot: true,
    );
    expect(
      tester.widget<FnthinkFilledAction>(batch).onPressed,
      isNotNull,
      reason: '前置：进入批量时那条可再发的默认选中 ⇒ 此刻这一枚必须点得动，否则批量没有出口',
    );

    await tester.tap(find.byKey(const ValueKey('history-row-n-failed')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<FnthinkFilledAction>(batch).onPressed,
      isNull,
      reason: '一条都没勾选还点得动 ⇒ 点了就是"补推 0 条"，随后那句结论就成了凭空报功',
    );
  });

  testWidgets('没勾选时那一枚还在屏上、只是灰的（置灰不是消失，片15）', (tester) async {
    await pumpHistory(tester, [
      row('n-failed', '取件码', {
        'chan:email': {'status': 'failed', 'message': '超时'},
      }),
    ]);
    await enterBatchMode(tester);
    await tester.tap(find.byKey(const ValueKey('history-row-n-failed')));
    await tester.pumpAndSettle();

    final batch = find.ancestor(
      of: find.byKey(const ValueKey('history-batch-push')),
      matching: find.byType(FnthinkFilledAction),
      matchRoot: true,
    );
    // ⚠ 这一条查的是**还在画**：件就算在不可用时直接返回空盒子，按 widget 类型的查找照样过
    //   （节点在树上）——只有"画出了可点宿主"这一条看得出它是不是消失了。
    expect(
      find.descendant(of: batch, matching: find.byType(CupertinoButton)),
      findsOneWidget,
      reason:
          '不可用 ⇒ 置灰留着。整枚不画，用户读到的是"我勾选了却没地方按"，'
          '而下一次勾选他又得重新找这一枚在哪',
    );
  });
}
