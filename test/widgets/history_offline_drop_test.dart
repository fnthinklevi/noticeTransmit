import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/notification_service.dart';

import '../test_setup.dart';

/// #94-A：原生缓存溢出过的条数必须在推送历史里**看得见一次**，且收下之后不再重复。
///
/// 为什么单独钉这条：丢弃动作发生在原生、用户回到应用时那条通知已经不存在了 ——
/// 列表里"没有那条"与"从来没来过"长得一模一样。没有这条提示，"不静默丢失"就只剩日志。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();
  stubNativeChannels();

  late NotificationService service;

  setUp(() async {
    // reset() 是异步的：不 await 就会把紧随其后注册的单例擦掉（表现为"明明注册了却说没注册"）
    await GetIt.instance.reset();
    service = NotificationService();
    GetIt.instance.registerSingleton<NotificationService>(service);
  });

  tearDown(() async {
    clearNativeChannelStubs();
    await GetIt.instance.reset();
  });

  Future<void> pumpHistory(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: HistoryPage(
          records: const <NotificationRecord>[],
          onClear: () async {},
          onExport: () async => <String, dynamic>{},
          onClearToday: () async => 0,
          onClearLastN: (_) async => 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('溢出过就提示，且把条数说清楚', (tester) async {
    service.pendingOfflineDrops = 5;
    await pumpHistory(tester);

    expect(
      find.byKey(const ValueKey<String>('history-offline-dropped')),
      findsOneWidget,
    );
    expect(
      find.text('离线期间缓存已满，5 条最旧通知没能进历史记录'),
      findsOneWidget,
      reason: '只说"有通知没进来"而不报条数 = 用户无法判断严重程度',
    );
  });

  testWidgets('没溢出过就不许出现这条提示', (tester) async {
    service.pendingOfflineDrops = 0;
    await pumpHistory(tester);

    expect(
      find.byKey(const ValueKey<String>('history-offline-dropped')),
      findsNothing,
    );
  });

  testWidgets('点关闭 ⇒ 提示消失且服务侧清零', (tester) async {
    service.pendingOfflineDrops = 3;
    await pumpHistory(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('history-offline-dropped')),
      findsNothing,
    );
    expect(service.pendingOfflineDrops, 0);
  });
}
