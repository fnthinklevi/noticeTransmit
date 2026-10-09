import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/fnthink_read_caps_page.dart';
import 'package:notice_transmit/widgets/app_root.dart';

/// 「可被远程读取的内容」那一页（T124 片C-1；通话记录那一格）。
///
/// 钉四件（这一页的全部判据）：
///  ① **默认关**，且关着时**不碰权限框**；
///  ② 翻到开 ⇒ 先弹系统权限框（申请恰好一次）；**答复没回来时不落开**；
///  ③ 给了权限 ⇒ 落开（持久化为 true）；被拒 ⇒ 保持关 + 说明那一句在；
///  ④ 关掉 ⇒ 立即落盘 false（不再弹框）。
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool stored,
    required Future<bool> Function() isGranted,
    List<bool>? saved,
    List<int>? requested,
  }) async {
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: FnthinkReadCapsPage(
          loadCalls: () async => stored,
          saveCalls: (v) async => saved?.add(v),
          requestPermission: () async => requested?.add(1),
          isGranted: isGranted,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool switchOf(WidgetTester tester) => tester
      .widget<CupertinoSwitch>(
        find.byKey(const ValueKey('fnthink-read-calls-switch')),
      )
      .value;

  testWidgets('默认关；关着时点开关（打开）才弹权限框 —— 初始一次都不弹', (tester) async {
    final requested = <int>[];
    await pump(
      tester,
      stored: false,
      isGranted: () async => false,
      requested: requested,
    );
    expect(switchOf(tester), isFalse, reason: '默认必须是关');
    expect(requested, isEmpty, reason: '进页不弹框');
  });

  testWidgets('打开且系统已给过权限 ⇒ 不重复弹框，直接落开', (tester) async {
    final requested = <int>[];
    final saved = <bool>[];
    await pump(
      tester,
      stored: false,
      isGranted: () async => true,
      saved: saved,
      requested: requested,
    );
    await tester.tap(find.byKey(const ValueKey('fnthink-read-calls-switch')));
    await tester.pumpAndSettle();
    expect(requested, isEmpty, reason: '已有权限不重复弹');
    expect(saved, [true]);
    expect(switchOf(tester), isTrue);
  });

  testWidgets('打开但权限没给 ⇒ 申请恰好一次；答复前**不落开**；答复给了才落开', (tester) async {
    final requested = <int>[];
    final saved = <bool>[];
    var granted = false;
    await pump(
      tester,
      stored: false,
      isGranted: () async => granted,
      saved: saved,
      requested: requested,
    );
    await tester.tap(find.byKey(const ValueKey('fnthink-read-calls-switch')));
    await tester.pumpAndSettle();
    expect(requested.length, 1);
    expect(saved, isEmpty, reason: '答复还没回来，不许先落开');
    expect(switchOf(tester), isFalse, reason: '没给权限就不许画成开');

    // 用户给了权限 ⇒ 从系统框回来（resumed 那一路复核）。
    granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(saved, [true]);
    expect(switchOf(tester), isTrue);
  });

  testWidgets('被拒 ⇒ 保持关，并说清"再点一次重试或去系统设置里打开"', (tester) async {
    final saved = <bool>[];
    await pump(
      tester,
      stored: false,
      isGranted: () async => false,
      saved: saved,
    );
    await tester.tap(find.byKey(const ValueKey('fnthink-read-calls-switch')));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(FnthinkReadCapsPage)),
    );
    expect(switchOf(tester), isFalse);
    expect(saved, isEmpty);
    expect(
      find.byKey(const ValueKey('fnthink-read-calls-denied')),
      findsOneWidget,
    );
    expect(find.text(l10n.fnthinkReadCallsDenied), findsOneWidget);
  });

  testWidgets('关掉 ⇒ 立即落盘 false，且**不再弹**权限框', (tester) async {
    final requested = <int>[];
    final saved = <bool>[];
    await pump(
      tester,
      stored: true,
      isGranted: () async => true,
      saved: saved,
      requested: requested,
    );
    expect(switchOf(tester), isTrue, reason: '存的是开就画成开');
    await tester.tap(find.byKey(const ValueKey('fnthink-read-calls-switch')));
    await tester.pumpAndSettle();
    expect(saved, [false]);
    expect(requested, isEmpty);
    expect(switchOf(tester), isFalse);
  });
}
