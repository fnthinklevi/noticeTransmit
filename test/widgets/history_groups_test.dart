import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/history_group_store.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';

import '../test_setup.dart';

/// T147②：历史页把一条规则扇出的成员行折叠成一条组行。
///
/// 三条边界：
///  ① 组行与转发行**混排**，成员行仍在（组行是摘要，不是把成员藏起来）；
///  ② 单成员的组不画（那一条自己就有一行，再画是重复）；
///  ③ 成员全被保留策略裁掉 ⇒ 不画幽灵组行（没有可解释的 X/Y）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  stubNativeChannels();

  setUp(() async {
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<NotificationService>(
      NotificationService(),
    );
  });
  tearDown(() async => GetIt.instance.reset());

  NotificationRecord record(
    String id, {
    String status = 'success',
    int postTime = 1000,
  }) => NotificationRecord(
    id: id,
    title: '通知 $id',
    content: '正文 $id',
    subText: '',
    packageName: 'com.a',
    appName: '应用A',
    type: 'normal',
    postTime: postTime,
    time: '2026-10-18 12:00',
    deviceName: '测试机',
    channels: const ['chan:webhook'],
    deliveryStatus: {
      'chan:webhook': {'status': status, 'message': ''},
    },
  );

  Future<void> pump(
    WidgetTester tester, {
    required List<NotificationRecord> records,
    required List<HistoryGroup> groups,
  }) async {
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
          historyGroupsLoader: () async => groups,
          groupMembersLoader: (ids) async =>
              records.where((r) => ids.contains(r.id)).toList(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  HistoryGroup group({
    String id = 'com.a:merge:1500',
    String kind = 'merge',
    int at = 1500,
    List<String> memberIds = const ['n1', 'n2'],
  }) => HistoryGroup(
    id: id,
    kind: kind,
    at: at,
    appName: '应用A',
    title: '两条通知',
    memberIds: memberIds,
  );

  testWidgets('两成员组：多一条组行，成员行仍在，行内是「扇出 2 · 失败 1」', (tester) async {
    final records = [record('n1'), record('n2', status: 'failed')];
    await pump(tester, records: records, groups: [group()]);

    final l10n = AppLocalizations.of(tester.element(find.byType(HistoryPage)));
    expect(
      find.byKey(const ValueKey('history-group-com.a:merge:1500')),
      findsOneWidget,
      reason: '组行没有画出来 —— 一条规则扇出的那批在历史里仍是一堆成员行',
    );
    expect(find.text(l10n.historyGroupTally(2, 1)), findsOneWidget);
    expect(find.textContaining('通知 n1'), findsWidgets);
    expect(find.textContaining('通知 n2'), findsWidgets);
  });

  testWidgets('X 是组里记下的成员数，不是回表找到的条数', (tester) async {
    await pump(
      tester,
      records: [
        record('n1'),
        record('n2', status: 'failed'),
      ],
      groups: [
        group(memberIds: const ['n1', 'n2', 'gone']),
      ],
    );

    final l10n = AppLocalizations.of(tester.element(find.byType(HistoryPage)));
    expect(
      find.text(l10n.historyGroupTally(3, 1)),
      findsOneWidget,
      reason: '一条成员被保留策略裁掉后，X 仍应是「这批扇出了 3 条」，不是碰巧读到的 2 条',
    );
  });

  testWidgets('失败 Y 数的是没发出去的成员，不是成功的', (tester) async {
    await pump(
      tester,
      records: [
        record('n1'),
        record('n2', status: 'failed'),
        record('n3', status: 'failed'),
      ],
      groups: [
        group(memberIds: const ['n1', 'n2', 'n3']),
      ],
    );

    final l10n = AppLocalizations.of(tester.element(find.byType(HistoryPage)));
    expect(find.text(l10n.historyGroupTally(3, 2)), findsOneWidget);
  });

  testWidgets('单成员组不画（成员自己那一行就是全部）', (tester) async {
    await pump(
      tester,
      records: [record('n1')],
      groups: [
        group(memberIds: const ['n1']),
      ],
    );

    expect(
      find.byKey(const ValueKey('history-group-com.a:merge:1500')),
      findsNothing,
    );
  });

  testWidgets('成员全被裁掉 ⇒ 不画幽灵组行', (tester) async {
    await pump(
      tester,
      records: const [],
      groups: [
        group(memberIds: const ['gone1', 'gone2']),
      ],
    );

    expect(
      find.byKey(const ValueKey('history-group-com.a:merge:1500')),
      findsNothing,
      reason: '回表一条都找不到时没有可解释的 X/Y，画一行只会是空话',
    );
  });

  testWidgets('延迟组用另一句标题，但组行形状相同', (tester) async {
    await pump(
      tester,
      records: [record('n1'), record('n2')],
      groups: [group(id: 'delay:2000', kind: 'delay', at: 2000)],
    );

    final l10n = AppLocalizations.of(tester.element(find.byType(HistoryPage)));
    expect(find.text(l10n.historyGroupDelay), findsOneWidget);
    expect(find.text(l10n.historyGroupTally(2, 0)), findsOneWidget);
  });
}
