import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/fnthink_shortcuts_page.dart';
import 'package:notice_transmit/services/fnthink_shortcut_registry.dart';
import 'package:notice_transmit/widgets/app_root.dart';

/// 「可被远程打开的入口」那一页（T124 片B 的 `app:launch` 的本机那一半）。
///
/// 钉三件：
///  ① 没登记过时说清"没有它对面那一档什么都不会做"（不是一片空白）；
///  ② 登记过就一行一条（名字 + 目标都看得见）；
///  ③ 加一条要**过校验**：名字或目标不成形时提交那颗是灰的（判据与注册表同源）。
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required List<FnthinkShortcut> rows,
    List<FnthinkShortcut>? saved,
  }) async {
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: FnthinkShortcutsPage(
          load: () async => rows,
          save: (next) async => saved?.addAll(next),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('没登记过 ⇒ 那句话在，且不是空白一片', (tester) async {
    await pump(tester, rows: const []);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(FnthinkShortcutsPage)),
    );
    expect(
      find.byKey(const ValueKey('fnthink-shortcuts-empty')),
      findsOneWidget,
    );
    expect(find.text(l10n.fnthinkShortcutsEmpty), findsOneWidget);
    expect(find.byKey(const ValueKey('fnthink-shortcuts-add')), findsOneWidget);
  });

  testWidgets('登记过的每一行都在（名字与目标都看得见）', (tester) async {
    await pump(
      tester,
      rows: const [
        FnthinkShortcut(name: '开门', target: 'home://gate/open'),
        FnthinkShortcut(name: '相机', target: 'com.android.camera/.Main'),
      ],
    );
    expect(find.byKey(const ValueKey('fnthink-shortcut-开门')), findsOneWidget);
    expect(find.byKey(const ValueKey('fnthink-shortcut-相机')), findsOneWidget);
    expect(find.text('home://gate/open'), findsOneWidget);
  });

  testWidgets('加一条：名字/目标不成形 ⇒ 提交那颗是灰的；填全了才亮', (tester) async {
    final saved = <FnthinkShortcut>[];
    await pump(tester, rows: const [], saved: saved);
    await tester.tap(find.byKey(const ValueKey('fnthink-shortcuts-add')));
    await tester.pumpAndSettle();

    final submit = find.byKey(const ValueKey('fnthink-shortcut-submit'));
    expect(submit, findsOneWidget);
    // 两格都空 ⇒ 灰的（判据与注册表校验同源：不成形就不让提交）。
    expect(tester.widget<CupertinoDialogAction>(submit).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('fnthink-shortcut-name')),
      '开门',
    );
    await tester.pumpAndSettle();
    // 只填了名字、目标还没填 ⇒ 仍是灰的。
    expect(tester.widget<CupertinoDialogAction>(submit).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('fnthink-shortcut-target')),
      '不是目标',
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<CupertinoDialogAction>(submit).onPressed,
      isNull,
      reason: '目标不成形（既不是包名/类名也不是带 scheme 的链接）也要挡住',
    );
    await tester.enterText(
      find.byKey(const ValueKey('fnthink-shortcut-target')),
      'home://gate/open',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<CupertinoDialogAction>(submit).onPressed, isNotNull);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(saved.single.name, '开门');
    expect(saved.single.target, 'home://gate/open');
  });
}
