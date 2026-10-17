import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';

import '../test_setup.dart';

/// T12 补充：历史要看得出「这条是降级走备用通道发的」。
///
/// 备用通道往往是用户平时不盯的那条（另一个群、邮件）。降级投递本身不是错误，
/// 但悄悄换了出口就等于让用户以为消息还在老地方 —— 与"不静默丢失"冲突。
/// 所以标记只做在 chip 上（一个「备用」小字），不弹提示、不算失败。
///
/// ⚠ T154 片2：通道细节（连同这枚「备用」）从行内收进了**详情子页** ——
///   三条用例因此都要先开子页再断言。这不只是补一次 tap：
///   若仍断在行内，`findsNothing` 那两条会因为"那地方本来就不画 chip"而**恒绿**。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();
  stubNativeChannels();

  setUp(() async {
    // #94-A 之后 HistoryPage 在 initState 里就要读 NotificationService 的溢出计数 ⇒
    // 任何 pump 它的测试都得提供这个单例（不是防御，是页面新增的前置条件）。
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<NotificationService>(
      NotificationService(),
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
    clearNativeChannelStubs();
  });

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

  /// 打开这条记录的详情子页 —— chip（含「备用」标）在那里面。
  Future<void> openDetail(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('history-delivery-detail-n-1')));
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
    await openDetail(tester);

    expect(
      find.text('备用'),
      findsOneWidget,
      reason: '降级投递过却看不出来 = 用户以为消息发到了主通道',
    );
    // 反向自证：两枚 chip 都在（"整段没画出来"也会让 findsOneWidget 以外的一切变得没意义）。
    expect(find.text('钉钉'), findsOneWidget);
    expect(find.text('邮件'), findsOneWidget);
  });

  testWidgets('未降级的记录不出现「备用」', (tester) async {
    await pumpHistory(
      tester,
      recordWith({
        'chan:dingtalk': {'status': 'success', 'message': 'ok'},
        'chan:email': {'status': 'failed', 'message': '超时'},
      }),
    );
    await openDetail(tester);

    expect(find.text('备用'), findsNothing);
    // 反向自证：子页确实画了（否则这条"没有备用"是空断言）。
    expect(find.text('钉钉'), findsOneWidget);
  });

  testWidgets('老记录（升级前的 delivery_info 没有这个键）照常渲染', (tester) async {
    // 标记是可选字段：缺键必须按"没走备用"处理，而不是抛异常或显示空标记
    await pumpHistory(
      tester,
      recordWith({
        'chan:dingtalk': {'status': 'pending', 'message': ''},
      }),
    );
    // 行内统计照常（这条记录只有一枚通道有状态 ⇒ 共 1 条通道）
    expect(find.text('取件码'), findsOneWidget);
    await openDetail(tester);

    expect(find.text('备用'), findsNothing);
    expect(find.text('钉钉'), findsOneWidget);
  });
}
