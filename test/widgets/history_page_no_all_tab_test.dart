import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';

import '../support/source_guards.dart';
import '../test_setup.dart';

/// T193：「全部」档**取消**了（维护者 2026-10-25 拍板）—— 这一条是它的棘轮。
///
/// 为什么不是"删掉旧用例就完事"：`fnthinkDirAll` 那一档当初是为了"三本账同屏"加的（T84），
/// 而它在**转发那本账分页**的前提下必然出问题（`_onScroll` 每翻一页都把新的转发页插到
/// 幻念两段之前 ⇒ 收件/发出被无限推后）。取消它的理由不是"不好用"，是**那个位置给不出
/// 完整列表**。所以这里钉三件：
///  ① 页面上只有三档芯片，`direction-chip-all` 不许回来；
///  ② 源码里 `_buildAllView` / `_allIn` / `_allOut` / `'all'` 那一支不许回来
///     （回来就等于把那套"两本账 + 转发页插队"的形状又装回去）；
///  ③ 词条也不许回来（`fnthinkDirAll` 等 5 条已按死词条棘轮删除）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  stubNativeChannels();

  final root = projectRoot();
  String read(String rel) =>
      File('$root/$rel').readAsStringSync().replaceAll('\r\n', '\n');

  setUp(() async {
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<NotificationService>(
      NotificationService(),
    );
  });
  tearDown(() async => GetIt.instance.reset());
  tearDownAll(clearNativeChannelStubs);

  group('T193「全部」档已取消（棘轮）', () {
    test('历史页源码里那套全部档的实现不许回来', () {
      final code = stripComments(read('lib/pages/history_page.dart'));
      for (final needle in const [
        'direction-chip-all',
        '_buildAllView',
        '_allScopeNote',
        '_allIn',
        '_allOut',
        'fnthinkDirAll',
      ]) {
        expect(
          code.contains(needle),
          isFalse,
          reason: '`$needle` 又出现在历史页里 ⇒ 「全部」档（两本账 + 转发页插队）正在被装回来',
        );
      }
      // 方向只有三档：值域就是这三个字符串字面量。
      expect(code.contains("'received'"), isTrue);
      expect(code.contains("'sent'"), isTrue);
      expect(code.contains("'forwarded'"), isTrue);
    });

    test('词条也不许回来（中英各一遍）', () {
      for (final p in const [
        'lib/l10n/arb/app_zh.arb',
        'lib/l10n/arb/app_en.arb',
      ]) {
        final json = read(p);
        for (final key in const [
          'fnthinkDirAll',
          'fnthinkTagForwarded',
          'fnthinkTagInbox',
          'fnthinkTagSent',
          'fnthinkAllScopeNote',
        ]) {
          expect(
            json.contains('"$key"'),
            isFalse,
            reason: '$p 里 `$key` 又长回来了 ⇒ 死词条棘轮被绕过',
          );
        }
      }
    });

    testWidgets('页面上只有三档芯片，默认停在转发档', (tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        AppRoot(
          locale: const Locale('zh'),
          dark: false,
          home: HistoryPage(
            forwardedLoader: fakeForwardedLoader(const []),
            forwardedCountLoader: () async => 0,
            onClear: () async {},
            onExport: () async => <String, dynamic>{},
            onClearToday: () async => 0,
            onClearLastN: (n) async => 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final key in const [
        'direction-chip-forwarded',
        'direction-chip-received',
        'direction-chip-sent',
      ]) {
        expect(
          find.byKey(ValueKey(key)),
          findsOneWidget,
          reason: '`$key` 不在了 ⇒ 三档缺一档',
        );
      }
      expect(
        find.byKey(const ValueKey('direction-chip-all')),
        findsNothing,
        reason: '「全部」档芯片又出现了',
      );
      // 默认第一档：转发那本账的读口被叫过一次（不是收件/发出）。
      expect(
        find.byKey(const ValueKey('history-all-note')),
        findsNothing,
        reason: '全部档顶部那句"三源并排"的说明又出现了',
      );
    });
  });
}
