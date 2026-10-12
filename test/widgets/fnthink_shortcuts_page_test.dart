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
    bool fail = false,
  }) async {
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: FnthinkShortcutsPage(
          // 读名单失败那一档要走 `_error != null` 那条分支：只能从 `load` 里抛，
          // 页面没有第二个入口能把状态摆成"读不出来"。
          load: () async {
            if (fail) throw StateError('读不到');
            return rows;
          },
          save: (next) async => saved?.addAll(next),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('没登记过 ⇒ 那一行状态原话在，且不是空白一片', (tester) async {
    await pump(tester, rows: const []);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(FnthinkShortcutsPage)),
    );
    expect(
      find.byKey(const ValueKey('fnthink-shortcuts-empty')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.fnthinkShortcutsEmptyShort),
      findsOneWidget,
      reason: '"还没有登记任何入口"是状态原话，必须留在页面上（搬走就等于把事实藏了）',
    );
    expect(
      find.text(l10n.fnthinkShortcutsEmpty),
      findsNothing,
      reason: '后面那半句解释（没有它对面什么都不会做）归问号，不摊在页面上',
    );
    expect(find.byKey(const ValueKey('fnthink-shortcuts-add')), findsOneWidget);
  });

  testWidgets('点空态那枚问号 ⇒ 整句读得到（只挪位置，正文不许被删）', (tester) async {
    await pump(tester, rows: const []);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(FnthinkShortcutsPage)),
    );
    await tester.tap(
      find.byKey(const ValueKey('fnthink-shortcuts-empty-help')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.fnthinkShortcutsEmpty),
      findsOneWidget,
      reason: '那半句是"为什么这一格非填不可"，丢了它就只剩一句状态、没人知道后果',
    );
  });

  testWidgets('页顶那句「为什么有这一页」只剩一行短说，整段在问号里', (tester) async {
    await pump(
      tester,
      rows: const [FnthinkShortcut(name: '开门', target: 'home://gate/open')],
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(FnthinkShortcutsPage)),
    );

    expect(find.text(l10n.fnthinkShortcutsWhyShort), findsOneWidget);
    expect(
      find.text(l10n.fnthinkShortcutsWhy),
      findsNothing,
      reason: '那 54 字教的是怎么填（名字 + 目标两种形状），摊在卡顶上就是小字论文',
    );

    await tester.tap(find.byKey(const ValueKey('fnthink-shortcuts-why-help')));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.fnthinkShortcutsWhy),
      findsOneWidget,
      reason: '「包名/类名」这一种写法只有那半句说得出，丢掉就等于少一种填法',
    );
  });

  testWidgets('读名单失败 ⇒ 页面上是状态原话，「读不出来≠没有」那半句进问号', (tester) async {
    await pump(tester, rows: const [], fail: true);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(FnthinkShortcutsPage)),
    );

    expect(
      find.byKey(const ValueKey('fnthink-shortcuts-error')),
      findsOneWidget,
      reason: '错误态那一格必须在场 —— 让它消失就是把失败读成空',
    );
    expect(find.text(l10n.remotePeersReadFailedShort), findsOneWidget);
    expect(find.text(l10n.remotePeersReadFailed), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('fnthink-shortcuts-error-help')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.remotePeersReadFailed),
      findsOneWidget,
      reason: '"这不是还没配对过，先去设备绑定那页看一眼"是下一步指引，删了就剩一句状态',
    );
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
