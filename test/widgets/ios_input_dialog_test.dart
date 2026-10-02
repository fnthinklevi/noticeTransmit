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
    bool trim = false,
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
                      trim: trim,
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
    testWidgets('画的是一件 Cupertino 的；显式要 trim 的那一格回去空格后的值', (tester) async {
      final seen = <String?>[];
      await openDialog(
        tester,
        (v) => seen.add(v),
        initialText: '旧名字',
        trim: true,
      );

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

      expect(seen, ['闸门改名'], reason: '设备名那一格换件之前就是先 trim 再判空的 ⇒ trim 由调用点显式要');
    });

    testWidgets('默认**不** trim —— 口令两端空格是口令的一部分', (tester) async {
      final seen = <String?>[];
      await openDialog(tester, (v) => seen.add(v), obscureText: true);

      await tester.enterText(field(), ' 口令带空格 ');
      await tester.tap(confirmBtn());
      await tester.pumpAndSettle();

      expect(
        seen,
        [' 口令带空格 '],
        reason:
            '悄悄 trim 会做出最难查的那种 bug：口令本来就带首尾空格的人，'
            '导出的备份能写、回来却解不开（报"口令错误或文件已损坏"），'
            '而他会开始怀疑自己记错了口令',
      );
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
      // 设备名那一格就是这对参数（requiredField + trim）：空值与全空格都不许把它保存掉。
      await openDialog(
        tester,
        (v) => seen.add(v),
        requiredField: true,
        trim: true,
      );

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

  group('调用点要的那几件', () {
    testWidgets('提示写在框下面、三行输入、关掉自动纠错、key 由调用点给', (tester) async {
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) => CupertinoPageScaffold(
              child: Center(
                child: CupertinoButton(
                  onPressed: () => showIosInputDialog(
                    ctx,
                    title: '拉黑这一条',
                    initialText: '验证码',
                    maxLines: 3,
                    autocorrect: false,
                    supportingText: '只按这一条文字拦，改一个字就不再命中',
                    fieldKeyValue: 'history-block-keyword-input',
                  ),
                  child: const Text('开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('开'));
      await tester.pumpAndSettle();

      final keyed = find.byKey(const ValueKey('history-block-keyword-input'));
      expect(
        keyed,
        findsOneWidget,
        reason: '调用点给的 key 不生效 ⇒ 页面级用例与闸门会一起找不到这一格',
      );
      final field = tester.widget<CupertinoTextField>(keyed);
      expect(field.maxLines, 3, reason: '提示语要能写三行，压回一行就成了看不全的输入框');
      expect(
        field.autocorrect,
        isFalse,
        reason: '关键词/主机名被自动纠错换掉字，症状是"配了却不生效"，最难往输入框上想',
      );

      final hint = find.text('只按这一条文字拦，改一个字就不再命中');
      expect(hint, findsOneWidget);
      expect(
        tester.getTopLeft(hint).dy,
        greaterThan(tester.getBottomLeft(keyed).dy),
        reason: '这句是"写完之后再想想"的说明，画到框上面就把"输入"这一步挤到下面去了',
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
