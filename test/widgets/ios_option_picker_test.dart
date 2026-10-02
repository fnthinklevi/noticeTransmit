import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show AlertDialog;
import 'package:flutter_test/flutter_test.dart';

import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/ios_option_picker.dart';

/// 选项弹层（T90 片6，全站唯一装配点）。
///
/// harness 用真的 `AppRoot`（样板见 `pull_to_refresh_list_test.dart`）：这一件存在的理由
/// 就是"根组件是 CupertinoApp"，在 `MaterialApp` 壳里测它，测的是另一套外观。
void main() {
  Widget wrap(Widget child) =>
      AppRoot(locale: const Locale('zh'), dark: false, home: child);

  const small = <IosPickerOption<String>>[
    IosPickerOption(value: 'a', label: '甲档'),
    IosPickerOption(value: 'b', label: '乙档', description: '乙档做什么'),
    IosPickerOption(value: 'c', label: '丙档'),
  ];

  /// 一屏：点「开」弹出选档，把选中的值与页面 context 交给 [onDone]
  /// （context 只有「回调里再压一层」那条用例用得上，别的使用者忽略它）。
  Future<void> openWith(
    WidgetTester tester,
    List<IosPickerOption<String>> options,
    void Function(String? picked, BuildContext ctx) onDone, {
    String? selected,
  }) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (ctx) => CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                onPressed: () async {
                  onDone(
                    await showIosOptionPicker<String>(
                      ctx,
                      title: '挑一档',
                      options: options,
                      selectedValue: selected,
                    ),
                    ctx,
                  );
                },
                child: const Text('开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开'));
    await tester.pumpAndSettle();
  }

  group('列出与选中线索', () {
    testWidgets('每一档都列出，副文案跟着走，且只有一档打勾', (tester) async {
      var calls = 0;
      await openWith(tester, small, (v, ctx) => calls++, selected: 'b');

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason:
            '选档弹层又用回 Material 那件 ⇒ 纯 Cupertino 树里缺 MaterialLocalizations 会红屏',
      );
      for (final option in small) {
        expect(
          find.byKey(ValueKey('ios-picker-${option.value}')),
          findsOneWidget,
          reason: '${option.label} 没被列出来 = 少一档就少一条可选项',
        );
      }
      expect(find.text('乙档做什么'), findsOneWidget);
      expect(
        find.byIcon(CupertinoIcons.check_mark),
        findsOneWidget,
        reason: '当前档位必须唯一可见 —— 两处打勾等于没有打勾',
      );
      expect(calls, 0, reason: '还没点，就不该有任何值传出去');
    });

    testWidgets('没有当前值时不报错，也不许出现勾', (tester) async {
      await openWith(tester, small, (v, ctx) {});
      expect(
        find.byIcon(CupertinoIcons.check_mark),
        findsNothing,
        reason: '没有当前值却画了勾 ⇒ 用户会以为自己已经选过',
      );
    });
  });

  group('返回值与顺序', () {
    testWidgets('点某一行 ⇒ 把那一档的值传出来，且弹层收掉', (tester) async {
      final seen = <String?>[];
      await openWith(tester, small, (v, ctx) => seen.add(v));

      await tester.tap(find.byKey(const ValueKey('ios-picker-c')));
      await tester.pumpAndSettle();

      expect(seen, ['c'], reason: '值没传出来 = 调用方只知道"用户点了点什么"，不知道点了哪一档');
      expect(
        find.byType(CupertinoAlertDialog),
        findsNothing,
        reason: '选完还盖着 ⇒ 后面每一格控件都在弹层底下找',
      );
    });

    testWidgets('点 barrier（没选）⇒ 返回 null，不许读成"选了当前那一档"', (tester) async {
      final seen = <String?>[];
      await openWith(tester, small, (v, ctx) => seen.add(v), selected: 'a');

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(
        seen,
        [null],
        reason:
            '两件事一起钉：① `showCupertinoDialog` 的 `barrierDismissible` **默认是 false**，'
            '不显式打开就没有"点外面收回去"这条出路 —— 而这批选档弹层根本没有取消按钮，'
            '"点开看看又想收回"恰恰是主题/语言那两格最常见的动作（换过来的第一版就这样丢了它，'
            '是这一条用例把它喊回来的）；② 没选必须回 null —— 把 barrier 读成"选了当前那一档"'
            '会凭空改写一次设置',
      );
    });

    testWidgets('回调里再压一层，那一层必须活着（#103 那一类）', (tester) async {
      // 真实形态是规则优先级：选一档 ⇒ 回调里同步压入自定义输入框。旧写法把顺序写成
      // "先回调再 pop"，于是那一下 pop 弹掉的正是刚压进来的那一层 ⇒ 用户看到"点自定义没反应"。
      // 这里不断"回调那一刻弹层在不在树上"（pop 动画里 future 的完成本来就可能早于拆树，
      // 那是框架的实现细节，不是行为契约），断的是唯一有意义的那件事：**那一层还在不在**。
      await openWith(tester, small, (picked, ctx) {
        if (picked != 'c') return;
        showCupertinoDialog<void>(
          context: ctx,
          barrierDismissible: false,
          builder: (dialogCtx) => CupertinoAlertDialog(
            title: const Text('自定义值'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('关掉'),
              ),
            ],
          ),
        );
      });

      await tester.tap(find.byKey(const ValueKey('ios-picker-c')));
      await tester.pumpAndSettle();

      expect(
        find.text('自定义值'),
        findsOneWidget,
        reason: '回调里压进来的那一层被弹掉了 ⇒ 就是 #103 那条真机反馈的复现',
      );
      await tester.tap(find.text('关掉'));
      await tester.pumpAndSettle();
      expect(find.text('自定义值'), findsNothing);
    });
  });

  group('装得下', () {
    testWidgets('十几档 + 矮屏：不溢出，最后一档滚得到也点得到', (tester) async {
      // 故意给一张**矮画布**（360×480 逻辑）：14 档约 700 高，屏只有 480。
      // ⚠ 第一版这条断的是"有没有 overflow 异常"，反证 PK5 当场证明那是**假绿**：
      // 我当时自己套的 ConstrainedBox + SingleChildScrollView 摘掉后一条都不红 ——
      // `CupertinoAlertDialog` 早就把 content 放在有界可滚的位置里了。那层包裹因此被删掉，
      // 这一条留下的判据是唯一的可观察事实：**最后一档够得着**（滚得动 + 点得到）。
      // 它今天没有对应的坏法可植（滚动不归我方代码管）⇒ 属纵深防御，如实登记，不算"已验证的闸"。
      tester.view.physicalSize = const Size(360, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final many = <IosPickerOption<String>>[
        for (var i = 0; i < 14; i++)
          IosPickerOption<String>(value: 'o$i', label: '第 $i 档'),
      ];
      await openWith(tester, many, (v, ctx) {});

      expect(tester.takeException(), isNull, reason: '矮屏上十四档把弹层顶穿也算这一屏的红');
      final last = find.byKey(const ValueKey('ios-picker-o13'));
      expect(last, findsOneWidget);
      await tester.ensureVisible(last);
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });
  });
}
