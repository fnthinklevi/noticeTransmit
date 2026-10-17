import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';

import '../test_setup.dart';

/// T133 量级①：取数循环的三条判据，页面级证据。
///
/// 三条各钉一个"不这么做会怎样"：
/// ① 空页不许停手 —— 粗筛宽、精筛窄，某一页精筛后剩 0 条不等于后面没有了；
///    停手的表现是"这一页没有"被读成"没有更多了"，后面的真命中永远不出来。
/// ② 游标按**粗筛**行数累加 —— 按精筛后的条数累加会把 offset 往回拨，
///    每页只前进"筛中的那几条"：既漏翻，又把同一段粗筛行重复扫一遍。
/// ③ 「没有更多了」只能由粗筛取尽来说 —— 粗筛还有（hasMore=true）时，末尾那格
///    加载指示必须在；取尽了它必须消失，且触底续拉真的把下一页带进来。
///
/// ⚠ 替身不写"死循环"形状：真库的 hasMore 由 `rows.length >= limit` 算出，
///    offset 单调前进 ⇒ 必然取尽。替身与它同形（见 test_setup.dart 的注释）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<NotificationService>(
      NotificationService(),
    );
  });
  tearDown(() async => GetIt.instance.reset());

  NotificationRecord row(String id, {bool failed = false}) =>
      NotificationRecord(
        id: id,
        title: '通知$id',
        content: failed ? '这一条没发出去' : '普通内容',
        subText: '',
        packageName: 'com.example.app',
        appName: '应用',
        type: 'normal',
        postTime: 1780000000000 + int.parse(id.substring(2)) * 1000,
        time: '10:00',
        deviceName: '本机',
        deliveryStatus: failed
            ? {
                'chan:dingtalk': {'status': 'failed', 'message': 'HTTP 500'},
              }
            : {
                'chan:dingtalk': {'status': 'success', 'message': ''},
              },
      );

  Future<void> pumpPage(
    WidgetTester tester, {
    required ForwardedPageLoader loader,
    required Future<int> Function() countLoader,
  }) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: HistoryPage(
          forwardedLoader: loader,
          forwardedCountLoader: countLoader,
          onClear: () async {},
          onExport: () async => <String, dynamic>{},
          onClearToday: () async => 0,
          onClearLastN: (_) async => 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('判据①：粗筛 200 行精筛 0 条的那一页不许收场，后面的真命中要出来', (tester) async {
    // 第一页：粗筛 200 行、**幸存 0 条**（服务层精筛把这一页吃光时的形状），粗筛还有。
    // 第二页：粗筛 3 行、幸存 1 条，取尽。
    // （页面把档名传给读口、读口做精筛 —— 替身直接演"精筛后这一页剩 0 条"。）
    var calls = 0;
    final fetchedOffsets = <int>[];
    Future<(List<NotificationRecord>, bool, int)> loader({
      String? keyword,
      int? startTime,
      int? endTime,
      String? appName,
      String? packageName,
      String? deliveryFilter,
      required int limit,
      required int offset,
    }) async {
      calls++;
      fetchedOffsets.add(offset);
      if (calls == 1) {
        return (<NotificationRecord>[], true, 200);
      }
      return ([row('r_9', failed: true)], false, 3);
    }

    await pumpPage(tester, loader: loader, countLoader: () async => 1);

    expect(calls, 2, reason: '第一页精筛后为 0 条就收场 = 空页冒充了"没有更多了"');
    expect(fetchedOffsets, [0, 200], reason: '第二页的 offset 应是第一页的粗筛行数');
    expect(find.text('通知r_9'), findsOneWidget, reason: '第二页的真命中被空页拦在门外了');
  });

  testWidgets('判据②：翻页 offset 按"累计粗筛行数"走，不按已显示条数走', (tester) async {
    // 三页各自粗筛行数不同、幸存数也不同（30 行幸存 1、25 行幸存 1、40 行幸存 1 取尽）。
    // 若游标按幸存条数累加，第三页请求的 offset 就不会是 0+30+25=55。
    final pages = <(List<NotificationRecord>, bool, int)>[
      (<NotificationRecord>[row('r_1', failed: true)], true, 30),
      (<NotificationRecord>[row('r_2', failed: true)], true, 25),
      (<NotificationRecord>[row('r_3', failed: true)], false, 40),
    ];
    final fetchedOffsets = <int>[];
    var idx = 0;
    Future<(List<NotificationRecord>, bool, int)> loader({
      String? keyword,
      int? startTime,
      int? endTime,
      String? appName,
      String? packageName,
      String? deliveryFilter,
      required int limit,
      required int offset,
    }) async {
      fetchedOffsets.add(offset);
      final p = pages[idx];
      idx++;
      return p;
    }

    await pumpPage(tester, loader: loader, countLoader: () async => 3);

    expect(fetchedOffsets, [0, 30, 55], reason: '游标漂了 = 每页在重复扫同一段粗筛行');
    expect(find.text('通知r_1'), findsOneWidget);
    expect(find.text('通知r_2'), findsOneWidget);
    expect(find.text('通知r_3'), findsOneWidget);
  });

  testWidgets('判据③b：触底续拉把下一页带进来；粗筛取尽后指示格消失', (tester) async {
    // 250 行的表（页大小 200）：首屏 200 条；触底续拉第二页 50 条、取尽 ⇒ 加载格消失。
    // ⚠ "粗筛还有 ⇒ 指示格在场"这一半不在页面层钉：凑满一屏的循环语义决定了
    //   指示格恒在懒构建区（loaded ≥ 200 才撒手），可见窗口只有一帧， finder 钉不住 ——
    //   它的真值在 service 层用真库钉（hasMore == 粗筛未取尽，见
    //   test/services/history_paging_service_test.dart）。
    final rows = List.generate(250, (i) => row('r_${i + 1}'));
    await pumpPage(
      tester,
      loader: fakeForwardedLoader(rows),
      countLoader: () async => rows.length,
    );

    expect(find.text('通知r_1'), findsOneWidget, reason: '无筛选也走分页读路：第一页要在场');
    expect(find.text('通知r_201'), findsNothing);

    // 指示格与第二页的行都在懒构建区，按住**列表那根**滚动条一路拖到底，
    // 让 _onScroll 自己触发续拉。（页面上方向条也是一根 Scrollable 且在树序里更靠前，
    // 按 Scrollable 找会拖错 —— 认 ListView。）
    //
    // ⚠ 这里不用 `dragUntilVisible`：它在每轮之间只 `pump()` 一帧，不等异步续拉落地。
    //   T154 片2 把行内的一串 chip 换成一行统计之后**行变矮**，同样 250 条更早触底 ⇒
    //   续拉更容易在"ListView 正被 loading 态替换"的那一帧被撞上，
    //   于是 `element(view)` 拿到 0 个、抛 `Bad state: No element`（实测过）。
    //   判据不变（触底 → 第二页进来 → 取尽后指示格消失），只是把等待方式换成
    //   `pumpAndSettle`：它等的是"这一轮确实做完了"，而不是"这一帧画完了"。
    for (var i = 0; i < 60 && find.text('通知r_250').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    await tester.pumpAndSettle();

    expect(find.text('通知r_250'), findsOneWidget, reason: '触底续拉没有把第二页带进来');
    // 取尽之后加载格消失：列表回到纯记录，不再有末尾那一格。
    expect(find.byKey(const ValueKey('history-load-more')), findsNothing);
  });

  testWidgets('无筛选时标题数是全表总数（countLoader），不是已加载的条数', (tester) async {
    final rows = List.generate(5, (i) => row('r_${i + 1}'));
    await pumpPage(
      tester,
      loader: fakeForwardedLoader(rows),
      countLoader: () async => 4321,
    );

    // 分页之后 loaded.length 只是"已加载的前几页"；无筛选的标题数必须还是全表总数。
    expect(
      find.text('历史记录 (4321)'),
      findsOneWidget,
      reason: '无筛选标题必须用全表总数（4321），拿 loaded.length 当总数就是骗人（写着 (5)，库里 4321 条）',
    );
  });
}
