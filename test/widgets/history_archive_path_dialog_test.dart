import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show AlertDialog, Icons, ModalBarrier;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/notification_service.dart';

import '../test_setup.dart';
import 'package:notice_transmit/services/archive_worker.dart'
    show kArchiveDirModeKey;
import 'package:notice_transmit/widgets/app_root.dart';

/// 历史页「自动保存路径」那一枚（T90 片24）。
///
/// ⚠ 用例里那些中文**必须抄 `app_zh.arb` 的原句**（`选择自定义文件夹` / `恢复默认路径`）——
/// 我第一版凭印象写成「选择文件夹」/「恢复默认」，两条断言当场找不到那一行（又一次"按印象拼文案"）。
/// 这一枚此前**没有页面级用例**（实测 `autoSavePath` / `chooseFolder` / `resetToDefault` /
/// `getArchiveDirectory` 在 `test/` 与 `integration_test/` 里**零命中**），换件只能靠肉眼搬。
/// 搬完之后必须有这样一组用例，因为换件时最容易丢的三件都不是"长得好不好看"：
/// ① **「恢复默认」那一条在还没有自定义目录时根本不该出现**（旧形状是置灰）——
///    `IosPickerOption` 的行是 `CupertinoButton`，没有 `enabled` 这个口 ⇒ 列出来就是
///    一颗「点得动但走不到 `onPressed`」的行，而它的动作是**不可撤销的写盘**（清掉自定义目录）；
/// ② 「现在存到哪儿了」那一行（`_prettyTreeUri` 转出来的路径）不能因为换壳被丢掉；
/// ③ 选中的那一档要真的回到调用点（`pick` → 调原生选目录；`reset` → 清原生目录 + 写 prefs）。
/// 原生那个通道名 —— ⚠ **必须与 `AppChannels.notification` 一字不差**（`com.fnthink.notice/notification`）。
/// 写错的话桩装在另一条通道上，页面那侧 `invokeMethod` 照旧发出去、没人接，
/// 而 `contains('getArchiveDirectory')` 只会在报告里显示"没问原生"（第一版就这么白跑一轮）。
const _archiveChannel = MethodChannel('com.fnthink.notice/notification');

/// 按调用顺序记下原生那一侧被叫了哪些方法 —— 这一组用例要按顺序核对，所以放文件级。
final _nativeCalls = <String>[];

/// 装上 `getArchiveDirectory` / `pickArchiveDirectory` / `clearArchiveDirectory` 三个答复。
void _stubArchiveChannel(Future<Object?> Function(MethodCall) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_archiveChannel, (call) async {
        _nativeCalls.add(call.method);
        return handler(call);
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // ⚠ 与 `history_page_all_tab_test` 同一套前置：`HistoryPage.initState` 要从 GetIt 取
  // `NotificationService`，不登记就会在构建时抛（第一次跑就撞到）。页面其余读口都走
  // 构造参数，不开真库。
  stubNativeChannels();

  /// 原生给的当前归档目录（null = 还是默认目录）。逐条用例可改。
  String? currentArchive;

  setUp(() async {
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<NotificationService>(
      NotificationService(),
    );
    currentArchive = null;
    _nativeCalls.clear();
    SharedPreferences.setMockInitialValues({});
    _stubArchiveChannel((call) async {
      switch (call.method) {
        case 'getArchiveDirectory':
          return currentArchive;
        case 'pickArchiveDirectory':
          return 'content://x/tree/primary%3ADownload%2Fnotify';
        case 'clearArchiveDirectory':
          currentArchive = null;
          return null;
      }
      return null;
    });
  });

  tearDown(() async {
    // ⚠ 只撤自己那一枚桩：全局那套 `clearNativeChannelStubs` 留给 tearDownAll。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_archiveChannel, null);
    await GetIt.instance.reset();
  });
  tearDownAll(clearNativeChannelStubs);

  /// 打开历史页 → 顶部更多菜单 → 「自动保存路径」。
  Future<void> openArchiveDialog(WidgetTester tester) async {
    // ⚠ **每一条用例都要重装一遍**：`stubNativeChannels()`（main 里装的那套）给同一个通道
    // 也装了桩，而 `setMockMethodCallHandler` 是**后者覆盖前者** —— 只在 setUp 装一次的话，
    // 打开弹层问原生拿到的是全局那套的答复，`getArchiveDirectory` 压根不会被记下来（第一版即如此）。
    _stubArchiveChannel((call) async {
      switch (call.method) {
        case 'getArchiveDirectory':
          return currentArchive;
        case 'pickArchiveDirectory':
          return 'content://x/tree/primary%3ADownload%2Fnotify';
        case 'clearArchiveDirectory':
          currentArchive = null;
          return null;
      }
      return null;
    });

    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: HistoryPage(
          initialDirection: 'all',
          records: const [],
          onClear: () async {},
          onExport: () async => <String, dynamic>{},
          onClearToday: () async => 0,
          onClearLastN: (n) async => 0,
          // ⚠ 收件那本账走 GetIt 的 [FnthinkInboxService]（不登记就在 `initState` 里抛），
          // 所以这里必须把两个读口换成页面构造参数 —— 与 `history_page_all_tab_test` 同一套做法。
          inboxLoader: () async => const [],
          sentLoader: () async => const [],
          inboxMarkRead: (id) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    final row = find.text('自动保存路径');
    expect(row, findsOneWidget, reason: '更多菜单里没有「自动保存路径」⇒ 入口定位失效');
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  group('自动保存路径那一枚（片24 换件后的页面级证据）', () {
    testWidgets('弹层是现成那件，且没有 Material AlertDialog', (tester) async {
      await openArchiveDialog(tester);

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('自动保存路径'), findsOneWidget);
      expect(
        _nativeCalls,
        contains('getArchiveDirectory'),
        reason: '没问原生要当前目录 ⇒ 弹层里那句「现在存到哪儿了」必然是假的',
      );
    });

    testWidgets('还没有自定义目录时，「恢复默认」那一条整个不出现', (tester) async {
      currentArchive = null;
      await openArchiveDialog(tester);

      expect(find.text('选择自定义文件夹'), findsOneWidget);
      expect(
        find.text('恢复默认路径'),
        findsNothing,
        reason:
            '旧形状是**置灰**（saved == null 时 onTap: null）；换成 CupertinoButton 之后'
            '那一行没有 enabled 口 ⇒ 列出来就是「点得动但不走 onPressed」，'
            '而它的动作是不可撤销的写盘（清掉自定义目录）',
      );
      expect(find.byKey(const ValueKey('ios-picker-reset')), findsNothing);
    });

    testWidgets('已经有自定义目录时，那一条出现且路径那一行说得出来源', (tester) async {
      currentArchive = 'content://x/tree/primary%3ADownload%2Fnotify';
      await openArchiveDialog(tester);

      expect(find.byKey(const ValueKey('ios-picker-reset')), findsOneWidget);
      // ⚠ 期望值是 `存储根目录/primary/Download`，两步都来自源码而不是印象：
      //   ① `content://x/tree/primary%3ADownload%2Fnotify` 里 `_prettyTreeUri` 取 `/tree/` 之后、
      //      **到第一个 `/` 为止**的一段（⇒ `primary%3ADownload`，不是整条目录名）；
      //   ② 解码后第一个 `:` 换成 `/` 得到 `/primary/Download`，它以 `/` 开头 ⇒ 走
      //      `l10n.storageRootPath`，而 app_zh.arb 里那句是 `存储根目录{path}`。
      //   ⚠ 第三次：这一步**不走** `storageRootPath` —— `%2F` 是编码的，
      //      取到 `/tree/` 之后到**第一个未编码的 `/`**，而 `part` 里并没有那个 `/`，
      //      所以 `part2` = `primary%3ADownload%2Fnotify` 整段 → 解码后只换第一个 `:` 得 `/primary/Download`。
      //      前两次我写的是 `Download/notify`（当目录全名）与 `存储根目录/...`（多加了前缀），都零命中。
      expect(
        find.text('primary/Download/notify'),
        findsOneWidget,
        reason: '「现在存到哪儿了」那一行被换件丢了 ⇒ `_prettyTreeUri` 也变成死代码',
      );
    });

    testWidgets('选「恢复默认」⇒ 原生那一侧被清掉、prefs 写成 default', (tester) async {
      currentArchive = 'content://x/tree/primary%3ADownload%2Fnotify';
      await openArchiveDialog(tester);

      await tester.tap(find.byKey(const ValueKey('ios-picker-reset')));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(
        _nativeCalls,
        contains('clearArchiveDirectory'),
        reason: '选了「恢复默认」而原生那一侧没被清 ⇒ 自定义目录还在被用着',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(kArchiveDirModeKey),
        'default',
        reason: 'prefs 那一格没写成 default ⇒ 下次启动还按自定义目录走',
      );
    });

    testWidgets('选「选择文件夹」⇒ 走原生选目录那一发', (tester) async {
      await openArchiveDialog(tester);

      await tester.tap(find.byKey(const ValueKey('ios-picker-pick')));
      await tester.pumpAndSettle();

      expect(
        _nativeCalls,
        contains('pickArchiveDirectory'),
        reason: '那一档带回的值没落到「调原生选目录」那条路上 ⇒ 换了壳之后按了没反应',
      );
    });

    testWidgets('这一枚点外面关得掉（照旧那枚 Material 框的行为）', (tester) async {
      await openArchiveDialog(tester);
      // ⚠ 这里**只断屏障可点穿这一位**（与片22/23 同一块石头：`CupertinoAlertDialog` 铺满视口时
      // 坐标那按落不到「外面」）。「点外面回 null」这一件在 widget 测试里不可观察，已登记在案。
      expect(
        tester
            .widgetList<ModalBarrier>(find.byType(ModalBarrier))
            .where((b) => b.dismissible)
            .toList(),
        isNotEmpty,
        reason: '点外面关不掉 ⇒「看一眼又想收回去」这条路没了',
      );
    });
  });
}
