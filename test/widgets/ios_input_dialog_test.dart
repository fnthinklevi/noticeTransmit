import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show AlertDialog;
import 'package:flutter_test/flutter_test.dart';

import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/ios_input_dialog.dart';

/// 单字段输入弹层（T90 片7，全站唯一装配点）。
///
/// harness 用真的 `AppRoot`（样板 `pull_to_refresh_list_test.dart`）。
/// 这一片最要紧的两条行为都容易在"换个壳"时被顺手改坏，所以各钉一条：
/// **判错不关框**（用户改一个字就能重交）与**取消/点外面回 null**（不许读成"存了个空值"）。
void main() {
  Widget wrap(Widget child) =>
      AppRoot(locale: const Locale('zh'), dark: false, home: child);

  Future<void> openDialog(
    WidgetTester tester,
    void Function(String? value) onDone, {
    String title = '起个名字',
    String initialText = '',
    bool requiredField = false,
    String? Function(String value)? validate,
    bool obscureText = false,
  }) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (ctx) => CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                onPressed: () async {
                  onDone(
                    await showIosInputDialog(
                      ctx,
                      title: title,
                      initialText: initialText,
                      hintText: '在这里输入',
                      requiredField: requiredField,
                      validate: validate,
                      obscureText: obscureText,
                    ),
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

  Finder field() => find.byKey(const ValueKey('ios-input-field'));
  Finder confirmBtn() => find.byKey(const ValueKey('ios-input-confirm'));
  Finder cancelBtn() => find.byKey(const ValueKey('ios-input-cancel'));

  group('取值', () {
    testWidgets('画的是一件 Cupertino 的，保存回的是**去掉首尾空格**的值', (tester) async {
      final seen = <String?>[];
      await openDialog(tester, (v) => seen.add(v), initialText: '旧名字');

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason:
            '输入弹层用回 Material 那件 ⇒ 纯 Cupertino 树里缺 MaterialLocalizations 会红屏',
      );
      // 预填：这一格改的是"已有的值"，空着进来等于让用户重打一遍。
      expect(
        tester.widget<CupertinoTextField>(field()).controller?.text,
        '旧名字',
      );

      await tester.enterText(field(), '  闸门改名  ');
      await tester.tap(confirmBtn());
      await tester.pumpAndSettle();

      expect(seen, ['闸门改名'], reason: '没 trim ⇒ 存进去的名字带空格，推送标题前缀与导出文件名都会跟着带');
    });

    testWidgets('取消那颗回 null，不写任何东西', (tester) async {
      final seen = <String?>[];
      await openDialog(tester, (v) => seen.add(v), initialText: '旧名字');

      await tester.enterText(field(), '改到一半');
      await tester.tap(cancelBtn());
      await tester.pumpAndSettle();

      expect(seen, [null], reason: '取消被读成"存了改到一半"就是替用户改了设置');
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });
  });

  group('判错不关框', () {
    testWidgets('validate 报错 ⇒ 那句话出现在框里、弹层还在、改一个字错误就擦掉', (tester) async {
      final seen = <String?>[];
      await openDialog(
        tester,
        (v) => seen.add(v),
        validate: (v) => v == '999' ? '请输入 0-500 的整数' : null,
      );

      await tester.enterText(field(), '999');
      await tester.tap(confirmBtn());
      await tester.pumpAndSettle();

      expect(find.text('请输入 0-500 的整数'), findsOneWidget);
      expect(
        find.byType(CupertinoAlertDialog),
        findsOneWidget,
        reason: '判错就关框 ⇒ 用户得从头再输一遍（这一支历史上红过一次，别退回）',
      );
      expect(seen, isEmpty, reason: '没通过校验就不该有任何值传出去');

      await tester.enterText(field(), '123');
      await tester.pump();
      expect(
        find.text('请输入 0-500 的整数'),
        findsNothing,
        reason: '已经改对了还挂着那句红字 ⇒ 用户不敢再按保存',
      );

      await tester.tap(confirmBtn());
      await tester.pumpAndSettle();
      expect(seen, ['123']);
    });

    testWidgets('requiredField：空值点保存什么都不发生（不关框、不回值）', (tester) async {
      final seen = <String?>[];
      await openDialog(tester, (v) => seen.add(v), requiredField: true);

      await tester.enterText(field(), '   ');
      await tester.tap(confirmBtn());
      await tester.pumpAndSettle();

      expect(seen, isEmpty);
      expect(
        find.byType(CupertinoAlertDialog),
        findsOneWidget,
        reason: '空值直接关框 ⇒ 把设备名存成空串（这一格没有专门的提示文案，措辞由维护者定）',
      );
    });
  });

  group('口令那一类', () {
    testWidgets('obscureText ⇒ 真正渲染那一位的是密文', (tester) async {
      await openDialog(tester, (v) {}, obscureText: true);
      await tester.enterText(field(), 'hunter2hunter2');
      await tester.pump();

      // ⚠ 这里**不能用 `find.text('hunter2hunter2')` 断"明文没出现"**：`find.text` 连
      // `EditableText` 里那份值一起匹配， obscure 与否都命中 ⇒ 那条断言恒红（我第一版就是它），
      // 而写成 findsNothing 更是永远证明不了任何事。要验就验**渲染那一位**的属性。
      final editable = tester.widget<EditableText>(
        find.descendant(of: field(), matching: find.byType(EditableText)),
      );
      expect(
        editable.obscureText,
        isTrue,
        reason: '口令框把值直接画出来 ⇒ 旁边看一眼、或截一张图，口令就出去了',
      );
      expect(
        tester.widget<CupertinoTextField>(field()).obscureText,
        isTrue,
        reason: '外壳那层的开关也要在（回归时最容易被顺手关掉的是这一层）',
      );
    });
  });
}
