import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/filter_service.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_setup.dart';

/// T148 片2（维护者 2026-10-12 第 3 条的后半：「后面其他模块要新增历史记录页了，
/// 都按推送历史的样式和内容来」—— 基座这一页自己也得真的走那个件）。
///
/// 片1 立了件、接了最远的一家（远程执行页），本片把**基座那页的转发行本体**换上去。
/// 这一组用例盯的不是像素，而是换壳之后**才会存在**的读数：
/// ① 每一格有自己的 key（页面再自己拼小字，key 形状就跟着措辞漂）；
/// ② 长按语义还挂在这一行上（差异⑤：可点与长按"有的有、有的没有"）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  setUp(() async {
    await GetIt.instance.reset();
    // 桩必须挂在 setUp 里：`clearNativeChannelStubs()` 在 tearDown 把它摘掉，
    // 写在 main 体内只有**第一条**用例有桩 —— 之后的用例里 `getEnabledPackages`
    // 那次 invokeMethod 永远不返回，表现是"长按没反应"，而不是"通道没桩"。
    stubNativeChannels();
    // 长按菜单第一件事是读筛选设置（`_filterService.loadSettings()`），它先等 SharedPreferences；
    // 没 mock 的话回调卡在 await 上 —— 同样是"长按没反应"，而真原因是装配缺件。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GetIt.instance.registerSingleton<NotificationService>(
      NotificationService(),
    );
    GetIt.instance.registerSingleton<FilterService>(FilterService());
  });

  tearDown(() async {
    await GetIt.instance.reset();
    clearNativeChannelStubs();
  });

  NotificationRecord oneRecord() {
    return NotificationRecord.fromMap({
      'id': 'n-adopt',
      'title': '取件码',
      'content': 'A-1-2345',
      'appName': '驿站',
      'packageName': 'com.example.station',
      'postTime': 1758768000000,
      'time': '2026-10-10 10:00',
      'type': 'normal',
      'deviceName': '测试机',
      'channels': <String>[],
      'deliveryStatus': <String, dynamic>{},
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

  testWidgets('那一行有行 key 与标题 key（定位不再靠中文措辞）', (tester) async {
    await pumpHistory(tester, oneRecord());

    expect(
      find.byKey(const ValueKey('history-row-n-adopt')),
      findsOneWidget,
      reason: '行本体没有 key ⇒ 用例与闸门只能按标题文字定位这一行',
    );
    expect(find.byKey(const ValueKey('history-title-n-adopt')), findsOneWidget);
  });

  testWidgets('那一行的正文格由通用件画出来（页面不再拼小字）', (tester) async {
    await pumpHistory(tester, oneRecord());

    expect(
      find.byKey(const ValueKey('history-subtitle-n-adopt')),
      findsOneWidget,
      reason: '正文那一格由通用件画：页面再抄一份 Text，下一次改版式就还是各改各的',
    );
    expect(find.text('A-1-2345'), findsOneWidget);
  });

  testWidgets('来源那一格走通用件的 source', (tester) async {
    await pumpHistory(tester, oneRecord());

    expect(
      find.byKey(const ValueKey('history-source-n-adopt')),
      findsOneWidget,
      reason: '「谁发的」是 source 格，不再挤进正文（差异①里那三种行容器的其中一种）',
    );
    expect(find.text('驿站'), findsOneWidget);
  });

  testWidgets('时间那一格走通用件（与远程执行页同一支笔）', (tester) async {
    await pumpHistory(tester, oneRecord());

    expect(find.byKey(const ValueKey('history-time-n-adopt')), findsOneWidget);
    expect(find.text('09-25 10:40'), findsOneWidget);
  });

  testWidgets('长按那一行还是出菜单（换壳不许把差异⑤换没了）', (tester) async {
    await pumpHistory(tester, oneRecord());

    await tester.longPress(find.byKey(const ValueKey('history-row-n-adopt')));
    await tester.pumpAndSettle();

    expect(
      find.text('屏蔽该应用的通知'),
      findsOneWidget,
      reason:
          '长按菜单是这一行唯一的"就地处置"入口；行壳交给通用件时漏传 onLongPress，'
          '这一格就在页面上静默消失（本仓"装配点漏传不报编译错"那一族的第三次形状）',
    );
  });
}
