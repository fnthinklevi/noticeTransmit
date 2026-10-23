import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/services/fnthink_remote_action_categories.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/fnthink_grant_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final contract = FnthinkContract.readFile();

  Future<AppLocalizations> pump(
    WidgetTester tester, {
    List<String> initialItems = const [],
    ValueChanged<Set<String>>? onChanged,
  }) async {
    // 权限表有十几行 + 参数控件：默认 800×600 的视口只会 build 前几行，
    // 后面那些 key 找不到（而它们其实存在）。给一块够高的屏，测的是控件不是滚动。
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: CupertinoPageScaffold(
          child: ListView(
            children: [
              FnthinkGrantEditor(
                contract: contract,
                initialItems: initialItems,
                busy: false,
                onChanged: onChanged ?? (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(FnthinkGrantEditor)));
  }

  testWidgets('非高级组默认展开；高级组默认收起，标题上写着「高级」', (tester) async {
    final l10n = await pump(tester);
    // alert:ring 属于「设备动作」那组（默认展开）。
    expect(
      find.byKey(const ValueKey('fnthink-grant-item-alert:ring')),
      findsOneWidget,
    );
    // 手机号 / 联系人这些读本机隐私的项在 search 组，默认收起。
    expect(
      find.byKey(const ValueKey('fnthink-grant-item-sms:search')),
      findsNothing,
      reason: '高级项默认收起：一屏铺开十几项正是维护者反馈⑥说的"太抽象"',
    );
    final advanced = find.byKey(
      const ValueKey('fnthink-grant-group-${'search'}'),
    );
    expect(advanced, findsOneWidget);
    expect(
      find.textContaining(l10n.fnthinkPeerGrantAdvanced),
      findsWidgets,
      reason: '收起了却不说，用户会以为这一族没有权限项',
    );
    expect(kFnthinkGrantCollapsedGroups.contains('search'), isTrue);
  });

  testWidgets('展开高级组 ⇒ 那一项出现，开关默认是「不允许」', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('fnthink-grant-group-search')));
    await tester.pumpAndSettle();
    final sw = find.byKey(const ValueKey('fnthink-grant-item-sms:search'));
    expect(sw, findsOneWidget);
    expect(tester.widget<CupertinoSwitch>(sw).value, isFalse);
    expect(
      tester.widget<CupertinoSwitch>(sw).onChanged,
      isNull,
      reason: '要参数却没给参数 ⇒ 这一格勾不上（那一串线上永远对不上）',
    );
  });

  testWidgets('打开一项 ⇒ 交给外面的清单里是契约拼出的整串', (tester) async {
    Set<String>? last;
    await pump(tester, onChanged: (v) => last = v);
    final sw = find.byKey(const ValueKey('fnthink-grant-item-alert:ring'));
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(last, contains('alert:ring'));
  });

  testWidgets('已经有那项 ⇒ 开关画成允许（不把已授权的项读成没给）', (tester) async {
    await pump(tester, initialItems: const ['alert:ring']);
    expect(
      tester
          .widget<CupertinoSwitch>(
            find.byKey(const ValueKey('fnthink-grant-item-alert:ring')),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('通道目标：参数填全之后才勾得上，出去的是三段整串', (tester) async {
    Set<String>? last;
    await pump(tester, onChanged: (v) => last = v);
    final sw = find.byKey(const ValueKey('fnthink-grant-item-channel:toggle'));
    await tester.ensureVisible(sw);
    expect(
      tester.widget<CupertinoSwitch>(sw).onChanged,
      isNull,
      reason: '族有默认值、号与目标档还没有 ⇒ 这一串拆不开',
    );
    final field = find.byKey(
      const ValueKey('fnthink-grant-arg-channel:toggle-id'),
    );
    await tester.ensureVisible(field);
    await tester.enterText(field, 'acme');
    await tester.pumpAndSettle();
    expect(tester.widget<CupertinoSwitch>(sw).onChanged, isNull);

    final on = find.byKey(
      const ValueKey('fnthink-grant-arg-channel:toggle-on'),
    );
    await tester.ensureVisible(on);
    await tester.tap(on);
    await tester.pumpAndSettle();
    await tester.ensureVisible(sw);
    expect(tester.widget<CupertinoSwitch>(sw).onChanged, isNotNull);
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(
      last,
      contains('channel:toggle/webhook:acme:on'),
      reason: '勾的是那条通道 + 那一档，不是动作名',
    );
  });

  testWidgets('参数一改，先前那个勾就掉（旧串不许留在答案里）', (tester) async {
    Set<String>? last;
    await pump(
      tester,
      initialItems: const ['sms:search/abc'],
      onChanged: (v) => last = v,
    );
    // search 组默认收起 ⇒ 先展开。
    await tester.tap(find.byKey(const ValueKey('fnthink-grant-group-search')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('fnthink-grant-arg-sms:search'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'abd');
    await tester.pumpAndSettle();
    expect(last, isNot(contains('sms:search/abc')));
  });
}
