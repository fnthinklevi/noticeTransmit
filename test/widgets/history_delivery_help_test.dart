import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';

import '../test_setup.dart';

/// T202：送达详情里那句「自动重试与回执」必须**点得开**，并把三种事实分开说。
///
/// 这一条钉的不是措辞好不好看，而是三件会误导人的事不许再混成「失败」两个字：
///  ① 会重试（网络/HTTP/限流，本机 3 次 + 跨进程重放）；
///  ② 不重试（业务拒绝，重试不会成功）；
///  ③ `no-receipt` 只是「本机没拿到结论」，且清扫只在打开 App / 回前台时跑。
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
    GetIt.instance.registerSingleton<NotificationService>(
      NotificationService(),
    );
  });

  testWidgets('点开问号能看到三种事实与「30 分钟 / 只在观察时清扫」', (tester) async {
    final record = NotificationRecord.fromMap({
      'id': 'n-1',
      'title': '取件码',
      'content': '1-2-3456',
      'appName': '驿站',
      'packageName': 'com.example.station',
      'postTime': 1758768000000,
      'time': '2026-10-15 10:00',
      'type': 'normal',
      'deviceName': '测试机',
      'channels': ['chan:email'],
      'deliveryStatus': {
        'chan:email': {'status': 'failed', 'message': '超时'},
      },
    });
    tester.view.physicalSize = const Size(1080, 3000);
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
          deliveryLogsLoader: (_) async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('history-delivery-detail-n-1')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('history-delivery-retry-note')),
      findsOneWidget,
      reason: '前置：送达详情没开起来 / 那行说明没挂上',
    );

    await tester.tap(find.byKey(const ValueKey('history-delivery-retry-help')));
    await tester.pumpAndSettle();
    for (final needle in const [
      '会重试',
      '不重试',
      '邮件通道没有出站队列',
      '30 分钟',
      '只在打开 App / 回到前台时清扫',
      '它不等于通道失败',
    ]) {
      expect(
        find.textContaining(needle),
        findsWidgets,
        reason: '帮助正文少了「$needle」⇒ 三种事实仍会被读成同一句「失败」',
      );
    }
  });
}
