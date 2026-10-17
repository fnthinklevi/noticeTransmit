import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/fnthink_card.dart'
    show
        FnthinkActionTone,
        FnthinkInlineAction,
        FnthinkMarkRole,
        FnthinkStatusMark;

import '../test_setup.dart';

/// T133 片2 立、T154 片2 改形状：一条记录有多个通道时，**行内只留结论、细节进子页**。
///
/// 页面级证据盯四件事（都对应维护者点名的形状）：
/// 1. 行内那一行统计**对得上**（共 N 条 = 成了 + 没成 + 在途，一个都不许漏）；
/// 2. 行内**不再摊 chip**（通道名与每格状态收进子页）；
/// 3. 子页里**出问题的排在前**（原先抄配置顺序 ⇒ 真失败那枚埋在中间）；
/// 4. 失败原因在子页里不截成一行。
///
/// ⚠ T154 片2 删掉的四条（折叠可开可收 / 折的是尾部 / 不超过上限不画折叠 / 折叠走件）：
///   折法整族退休，那四条用例测的能力**不存在了** —— 不是被改写成了别的东西。
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

  const longReason =
      'SMTP 连接超时：connect to smtp.example.org:465 failed (timed out)';

  /// 配置顺序**故意**排成"没事的在前"：Slack 成 / 钉钉败 / ntfy 成 / 邮件暂停 / Gotify 成 / Bark 拦
  /// ⇒ 三成、三没成（失败 + 被拦 + 暂停都算没成，同 `notDeliveredStatuses`）。
  NotificationRecord sixChannelRecord() {
    return NotificationRecord.fromMap({
      'id': 'n-many',
      'title': '取件码',
      'content': '1-2-3456',
      'appName': '驿站',
      'packageName': 'com.example.station',
      'postTime': 1758768000000,
      'time': '2026-10-10 10:00',
      'type': 'normal',
      'deviceName': '测试机',
      'channels': [
        'chan:slack',
        'chan:dingtalk',
        'chan:ntfy',
        'chan:email',
        'chan:gotify',
        'chan:bark',
      ],
      'deliveryStatus': <String, dynamic>{
        'chan:slack': {'status': 'success', 'message': 'ok'},
        'chan:dingtalk': {'status': 'failed', 'message': longReason},
        'chan:ntfy': {'status': 'success', 'message': 'ok'},
        'chan:email': {'status': 'paused', 'message': '转发已暂停'},
        'chan:gotify': {'status': 'success', 'message': 'ok'},
        'chan:bark': {'status': 'intercepted', 'message': '黑名单'},
      },
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

  final detailKey = find.byKey(
    const ValueKey('history-delivery-detail-n-many'),
  );

  testWidgets('行内是一行统计：三成三没成，且不再摊通道名', (tester) async {
    await pumpHistory(tester, sixChannelRecord());

    expect(
      find.textContaining('共 6 条通道'),
      findsOneWidget,
      reason: '这一行要回答"这条到底成没成"，而摊开的 chip 只回答"每格分别是什么"',
    );
    expect(find.textContaining('3 成功'), findsOneWidget);
    expect(find.textContaining('3 失败'), findsOneWidget);
    // 行内不再有通道名：那些收进子页（否则"摘要"和"细节"同时摊着，摘要就没意义了）。
    for (final name in const ['Slack', '钉钉', 'ntfy', '邮件', 'Gotify', 'Bark']) {
      expect(find.text(name), findsNothing, reason: '行内还摊着 $name ⇒ chip 没收进子页');
    }
  });

  testWidgets('「查看详情」开出子页：六枚全露（含没事的那几枚）', (tester) async {
    await pumpHistory(tester, sixChannelRecord());
    await tester.tap(detailKey);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('history-delivery-detail-title')),
      findsOneWidget,
      reason: '子页没开出来',
    );
    for (final name in const ['Slack', '钉钉', 'ntfy', '邮件', 'Gotify', 'Bark']) {
      expect(
        find.text(name),
        findsOneWidget,
        reason: '$name 在子页里也该在 —— 详情的意思就是"一个都不落"',
      );
    }
  });

  testWidgets('子页里出问题的排在前（被拦的排在成功的之前）', (tester) async {
    await pumpHistory(tester, sixChannelRecord());
    await tester.tap(detailKey);
    await tester.pumpAndSettle();

    // 排序生效的证据：配置里排最后的 Bark（被拦）要排在前面的 Slack（成功）之前。
    final barkY = tester.getTopLeft(find.text('Bark')).dy;
    final slackY = tester.getTopLeft(find.text('Slack')).dy;
    expect(
      barkY,
      lessThanOrEqualTo(slackY),
      reason: '只按配置顺序画的话正好相反 —— 真出问题的那枚会被埋进中间',
    );
  });

  testWidgets('子页里失败原因不被截成一行', (tester) async {
    await pumpHistory(tester, sixChannelRecord());
    await tester.tap(detailKey);
    await tester.pumpAndSettle();

    final reason = tester.widget<Text>(find.text(longReason));
    expect(
      reason.maxLines,
      greaterThanOrEqualTo(2),
      reason: '一行截断让"SMTP 连接超时"和别的长原因长得一模一样，等于没写',
    );
  });

  testWidgets('「查看详情」由行内动作件画出，且取中性档（T148 片14 的判据换对象）', (tester) async {
    await pumpHistory(tester, sixChannelRecord());

    // ⚠ 钉的是**件**不是 key：key 字符串逐字在册（`history-delivery-detail-*`），
    //   所以"换回自搭壳"这一种坏法只能靠 widget 类型逮。
    // ⚠ `matchRoot: true` 必须有：那枚件收 `super.key`＝**键就是件本身**，
    //   默认口径只往"祖先"找，恒得 0（片11 在同一族上红过一次，那是尺站错了地方）。
    final action = find.ancestor(
      of: detailKey,
      matching: find.byType(FnthinkInlineAction),
      matchRoot: true,
    );
    expect(action, findsOneWidget, reason: '那一枚不是公共件画的 ⇒ 行内动作这一族在这一页长出第二个作者');
    expect(
      tester.widget<FnthinkInlineAction>(action).tone,
      FnthinkActionTone.neutral,
      reason: '它只展开细节、不动任何一条记录 ⇒ 蓝那一档会说成"做了一件会留痕的事"',
    );
  });

  testWidgets('通道 chip 由徽标件画出：壳、次级字与状态圆点都归件（T148 片16，现在在子页里）', (tester) async {
    await pumpHistory(tester, sixChannelRecord());
    await tester.tap(detailKey);
    await tester.pumpAndSettle();

    final marks = tester
        .widgetList<FnthinkStatusMark>(find.byType(FnthinkStatusMark))
        .toList();
    expect(
      marks.where((m) => m.role == FnthinkMarkRole.channel),
      isNotEmpty,
      reason:
          '通道 chip 不再由 `FnthinkStatusMark` 给出 ⇒ 壳又回到页面自己搭，'
          '而同一行里「高优」那类属性徽标与它是两份 padding／圆角／淡底 α',
    );
    // 次级字（状态读数＋圆点）必须**在件里面**，不是件外面另摆一行。
    // ⚠ 文字取自 `deliveryStatusText`（唯一作者），这里现取现比，不抄字面量。
    final l10n = AppLocalizations.of(tester.element(find.byType(HistoryPage)));
    final failedText = l10n.deliveryFailed;
    final failed = marks.firstWhere(
      (m) => m.submarks.any((s) => s.label == failedText),
    );
    expect(
      failed.submarks.firstWhere((s) => s.label == failedText).dotColor,
      isNotNull,
      reason: '状态读数没有圆点 ⇒ 只剩文字，与同行那枚"色 + 字"的读数不再是同一格事实',
    );
  });

  testWidgets('没送达记录的通道照旧说「无推送通道」（不是"共 0 条通道"）', (tester) async {
    await pumpHistory(
      tester,
      NotificationRecord.fromMap({
        'id': 'n-none',
        'title': '取件码',
        'content': '1-2-3456',
        'appName': '驿站',
        'packageName': 'com.example.station',
        'postTime': 1758768000000,
        'time': '2026-10-10 10:00',
        'type': 'normal',
        'deviceName': '测试机',
        'channels': <String>[],
        'deliveryStatus': <String, dynamic>{},
      }),
    );

    final l10n = AppLocalizations.of(tester.element(find.byType(HistoryPage)));
    expect(find.text(l10n.noChannels), findsOneWidget);
    expect(
      find.textContaining('共 0 条通道'),
      findsNothing,
      reason: '"一条通道都没走过"与"走了 0 条通道"不是同一句话 —— 后者是替一件没发生的事算了个数',
    );
  });
}
