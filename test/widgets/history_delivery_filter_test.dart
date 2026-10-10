import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';

import '../test_setup.dart';

/// T133 片3：筛选面板里那一档的名字必须就是说的那句话。
///
/// 盯两件事：
/// 1. 「仅成功／仅失败」那两枚没了 —— 旧档名叫"失败"却认两种状态，而暂停的记录
///    既不进这一档也不进"成功"那一档，于是**两档都找不到它**（名字与口径不符）；
/// 2. 新的三档（全部／已送达／没发出去的）在场且互不相同。
///
/// ⚠ 这一页**不**断"选中哪一档"：档 id 一路传到 DB 的 LIKE 参数，那条链今天要在真库上才看得见
/// （widget 测试不开真库）。它的口径由 `delivery_status_test` +
/// `repush_predicate_single_author_test` 那两条同源守卫钉着，这里只钉名字。
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

  Future<void> openFilterSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
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
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
  }

  testWidgets('送达状态那一档改叫「没发出去的」，旧的「仅失败」「仅成功」都不在', (tester) async {
    await openFilterSheet(tester);

    expect(find.text('没发出去的'), findsOneWidget);
    expect(find.text('已送达'), findsOneWidget);
    expect(find.text('仅失败'), findsNothing);
    expect(find.text('仅成功'), findsNothing);
  });

  testWidgets('那一组三档彼此不同名、顺序是 全部 → 已送达 → 没发出去的', (tester) async {
    await openFilterSheet(tester);

    // ⚠ 按"那一组"取，不按全页文案：来源那一轴也有一枚「全部」，
    //   全页 find.text('全部') 必然是多枚 —— 那不是缺陷，是两轴同词。
    final group = find.ancestor(
      of: find.text('没发出去的'),
      matching: find.byType(Wrap),
    );
    expect(group, findsOneWidget, reason: '这一档不在自己那一组里（面板形状漂了）');

    final labels = tester
        .widgetList<Text>(
          find.descendant(of: group, matching: find.byType(Text)),
        )
        .map((t) => t.data)
        .toList();
    expect(labels, ['全部', '已送达', '没发出去的']);
  });
}
