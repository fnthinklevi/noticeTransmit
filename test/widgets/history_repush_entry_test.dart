import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';

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
          records: records,
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
}
