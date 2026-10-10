import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';

import '../test_setup.dart';

/// T133 片2：一条记录有多个通道时，那一串 chip 要**看得出问题在哪**、
/// 而且不能把行挤成不定高的一堆。
///
/// 页面级证据盯四件事（都对应维护者点名的形状）：
/// 1. 出问题的排在前（原先抄配置顺序 ⇒ 真失败那枚埋在中间）；
/// 2. 超过一屏放得下的枚数折起来，折的是尾部"没事"那几枚；
/// 3. 折叠那枚**点了能开、开了能收**（用"露出的那几枚"判可折就会收不回去）；
/// 4. 失败原因不再截成一行。
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
          records: [record],
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

  final foldKey = find.byKey(const ValueKey('history-chip-fold-n-many'));

  testWidgets('六枚只画四枚，且画出来的是"有问题"那几枚在前', (tester) async {
    await pumpHistory(tester, sixChannelRecord());

    // 排序生效的证据：配置里排第 3 的 ntfy（成功）被折走，而排最后却"被拦"的 Bark 露出来。
    // 只按配置顺序画的话正好相反 —— ntfy 在、Bark 不在。
    expect(find.text('钉钉'), findsOneWidget);
    expect(find.text('邮件'), findsOneWidget);
    expect(find.text('Bark'), findsOneWidget, reason: '被拦的那枚该露出来');
    expect(find.text('Slack'), findsOneWidget);
    expect(find.text('ntfy'), findsNothing, reason: '没事的通道折在尾部');
    expect(find.text('Gotify'), findsNothing);
    expect(find.text('还有 2 个通道'), findsOneWidget);
  });

  testWidgets('折叠那枚点了展开：六枚全露，标签换成「收起」', (tester) async {
    await pumpHistory(tester, sixChannelRecord());
    await tester.tap(foldKey);
    await tester.pumpAndSettle();

    expect(find.text('ntfy'), findsOneWidget);
    expect(find.text('Gotify'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);
    expect(find.text('还有 2 个通道'), findsNothing);
  });

  testWidgets('展开之后还收得回去（折叠可用性按全集判，不按露出的那几枚判）', (tester) async {
    await pumpHistory(tester, sixChannelRecord());
    await tester.tap(foldKey);
    await tester.pumpAndSettle();
    expect(find.text('收起'), findsOneWidget);

    await tester.tap(foldKey);
    await tester.pumpAndSettle();

    expect(foldKey, findsOneWidget);
    expect(find.text('还有 2 个通道'), findsOneWidget);
    expect(find.text('ntfy'), findsNothing);
  });

  testWidgets('不超过一屏枚数时不画折叠那枚（不许凭空多一枚按钮）', (tester) async {
    await pumpHistory(
      tester,
      NotificationRecord.fromMap({
        'id': 'n-three',
        'title': '取件码',
        'content': '1-2-3456',
        'appName': '驿站',
        'packageName': 'com.example.station',
        'postTime': 1758768000000,
        'time': '2026-10-10 10:00',
        'type': 'normal',
        'deviceName': '测试机',
        'channels': ['chan:dingtalk', 'chan:email', 'chan:bark'],
        'deliveryStatus': <String, dynamic>{
          'chan:dingtalk': {'status': 'success', 'message': 'ok'},
          'chan:email': {'status': 'success', 'message': 'ok'},
          'chan:bark': {'status': 'success', 'message': 'ok'},
        },
      }),
    );

    expect(
      find.byKey(const ValueKey('history-chip-fold-n-three')),
      findsNothing,
    );
    expect(find.text('钉钉'), findsOneWidget);
  });

  testWidgets('失败原因不再被截成一行', (tester) async {
    await pumpHistory(tester, sixChannelRecord());

    final reason = tester.widget<Text>(find.text(longReason));
    expect(
      reason.maxLines,
      greaterThanOrEqualTo(2),
      reason: '一行截断让"SMTP 连接超时"和别的长原因长得一模一样，等于没写',
    );
  });
}
