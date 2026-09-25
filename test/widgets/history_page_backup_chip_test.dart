import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/pages/history_page.dart';

import '../test_setup.dart';

/// T12 补充：历史列表要看得出「这条是降级走备用通道发的」。
///
/// 备用通道往往是用户平时不盯的那条（另一个群、邮件）。降级投递本身不是错误，
/// 但悄悄换了出口就等于让用户以为消息还在老地方 —— 与"不静默丢失"冲突。
/// 所以标记只做在 chip 上（一个「备用」小字），不弹提示、不算失败。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();
  stubNativeChannels();
  tearDown(clearNativeChannelStubs);

  NotificationRecord recordWith(Map<String, dynamic> delivery) {
    return NotificationRecord.fromMap({
      'id': 'n-1',
      'title': '取件码',
      'content': '1-2-3456',
      'appName': '驿站',
      'packageName': 'com.example.station',
      'postTime': 1758768000000,
      'time': '2026-09-25 10:00',
      'type': 'normal',
      'deviceName': '测试机',
      'channels': ['chan:dingtalk', 'chan:email'],
      'deliveryStatus': delivery,
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
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: HistoryPage(
          records: [record],
          onClear: () async {},
          onExport: () async => <String, dynamic>{},
          onClearToday: () async => 0,
          onClearLastN: (_) async => 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('走了备用的那条通道标「备用」，没走的通道不标', (tester) async {
    await pumpHistory(
      tester,
      recordWith({
        'chan:dingtalk': {
          'status': 'success',
          'message': 'ok',
          'viaBackup': true,
        },
        'chan:email': {'status': 'success', 'message': 'ok'},
      }),
    );

    expect(
      find.text('备用'),
      findsOneWidget,
      reason: '降级投递过却看不出来 = 用户以为消息发到了主通道',
    );
  });

  testWidgets('未降级的记录不出现「备用」', (tester) async {
    await pumpHistory(
      tester,
      recordWith({
        'chan:dingtalk': {'status': 'success', 'message': 'ok'},
        'chan:email': {'status': 'failed', 'message': '超时'},
      }),
    );

    expect(find.text('备用'), findsNothing);
  });

  testWidgets('老记录（升级前的 delivery_info 没有这个键）照常渲染', (tester) async {
    // 标记是可选字段：缺键必须按"没走备用"处理，而不是抛异常或显示空标记
    await pumpHistory(
      tester,
      recordWith({
        'chan:dingtalk': {'status': 'pending', 'message': ''},
      }),
    );

    expect(find.text('备用'), findsNothing);
    expect(find.text('取件码'), findsOneWidget);
  });
}
