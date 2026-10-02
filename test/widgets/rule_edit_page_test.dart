import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/cupertino.dart';
// 值输入格现在仍是 Material 的 `TextField`（`_buildTextFieldSection`，属于还没迁的那一屏）
// ⇒ 按类型找它得引 material 的这一名；用 show 限定，避免与 cupertino 的同名件冲突。
import 'package:flutter/material.dart'
    show IconButton, Icons, InkWell, TextButton, TextField;
import 'package:notice_transmit/pages/rule_edit_page.dart';
import 'package:notice_transmit/models/notification_rule.dart';
import 'package:notice_transmit/widgets/app_root.dart';

Widget _buildApp(Widget home) {
  return AppRoot(locale: const Locale('zh'), dark: false, home: home);
}

void main() {
  group('RuleEditPage – widget smoke tests', () {
    testWidgets('renders in create mode without crash', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          RuleEditPage(
            rule: NotificationRule(id: '', name: ''),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RuleEditPage), findsOneWidget);
    });

    testWidgets('renders in edit mode with existing rule', (tester) async {
      final rule = NotificationRule(
        id: 'test-rule',
        name: 'Test Rule',
        enabled: true,
        priority: 50,
        conditions: [
          Condition(id: 'c1', type: ConditionType.titleContains, value: '验证码'),
        ],
        actions: [RuleAction(id: 'a1', type: ActionType.push)],
      );

      await tester.pumpWidget(_buildApp(RuleEditPage(rule: rule)));
      await tester.pumpAndSettle();
      expect(find.byType(RuleEditPage), findsOneWidget);
    });
  });

  // 维护者 1.5.76 反馈 #1：优先级只有点预置档位有效，点「自定义…」毫无反应。
  // 根因不在优先级那一段，而在通用 picker 的 onTap 顺序（先回调后 pop）：
  // 只有这一档的 onChanged 会同步压入新对话框，于是 pop 弹掉的是刚压进来的那一个。
  group('规则优先级 picker', () {
    Future<void> openPriorityPicker(
      WidgetTester tester, {
      int priority = 50,
    }) async {
      await tester.pumpWidget(
        _buildApp(
          RuleEditPage(
            rule: NotificationRule(id: 'r1', name: 'R', priority: priority),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('低 (50)'));
      await tester.pumpAndSettle();
      expect(find.text('自定义…'), findsOneWidget, reason: 'picker 没打开');
    }

    testWidgets('点「自定义…」会打开输入框（修复前：同一帧被 pop 掉）', (tester) async {
      await openPriorityPicker(tester);

      await tester.tap(find.text('自定义…'));
      await tester.pumpAndSettle();

      expect(
        find.text('自定义优先级'),
        findsOneWidget,
        reason:
            '这就是那条反馈的现象：输入框没出现。picker 的 onTap 若在 onChanged 之后才 pop，'
            '弹掉的就是刚压进来的输入框（pop 弹栈顶，不是弹 picker）。',
      );
    });

    testWidgets('自定义值确认后写回字段并回显', (tester) async {
      await openPriorityPicker(tester);
      await tester.tap(find.text('自定义…'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(CupertinoTextField).last, '123');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(
        find.text('自定义… (123)'),
        findsOneWidget,
        reason: '123 不在标准档位里 ⇒ 字段回显"自定义 (N)"，这条断言同时证明值真写进了 _rule',
      );
    });

    testWidgets('非法自定义值就地提示、不写回、输入框不关', (tester) async {
      await openPriorityPicker(tester);
      await tester.tap(find.text('自定义…'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(CupertinoTextField).last, '999');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(find.text('请输入 0-500 的整数'), findsOneWidget);
      expect(find.text('自定义优先级'), findsOneWidget, reason: '判错时不许关框，否则用户得重来一遍');
      expect(find.text('低 (50)'), findsOneWidget, reason: '原值不能被越界输入改掉');
    });

    testWidgets('预置档位仍然有效（pop 顺序换了不许碰坏这条）', (tester) async {
      await openPriorityPicker(tester);

      await tester.tap(find.text('高 (200)'));
      await tester.pumpAndSettle();

      expect(find.text('高 (200)'), findsOneWidget, reason: 'picker 该关，字段该显示新值');
      expect(find.text('低 (50)'), findsNothing);
    });
  });

  // #200：这四枚表单弹层在 T90 片12 换外壳前后**都没有页面级用例**（grep ruleAddCondition /
  // ConditionAdd 在 test/ 与 integration_test/ 零命中）。外壳自己的形状由 ios_form_dialog_test 钉，
  // 但"用户填完按添加，条件真的多出一条"这一层一直没有读者 —— 那正是片12 留下的缺口，这里补上。
  group('条件/动作表单真的落盘', () {
    Future<void> openPage(WidgetTester tester, NotificationRule rule) async {
      await tester.pumpWidget(_buildApp(RuleEditPage(rule: rule)));
      await tester.pumpAndSettle();
      expect(find.text('添加条件'), findsOneWidget);
    }

    testWidgets('条件区那颗「添加」按下去 ⇒ 表单弹层出现（分组标题不是按钮）', (tester) async {
      await openPage(tester, NotificationRule(id: 'r1', name: 'R'));

      // ⚠ 页面上「添加条件」是**分组标题**，按钮文案是「添加」，且条件区与动作区各一颗
      //   ⇒ 必须限定作用域并按顺序取，裸 find.text('添加') 会一次命中多颗。
      final addBtns = find.widgetWithText(TextButton, '添加');
      expect(addBtns, findsNWidgets(2), reason: '条件区与动作区各应有一颗「添加」');
      await tester.tap(addBtns.first);
      await tester.pumpAndSettle();

      expect(
        find.byType(CupertinoAlertDialog),
        findsOneWidget,
        reason: '「添加条件」的表单弹层没出现 ⇒ 片12 换外壳把它换断了',
      );
      expect(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text('条件类型'),
        ),
        findsOneWidget,
        reason: '弹层里没有条件类型那一格 ⇒ 字段没挂上外壳',
      );
    });

    testWidgets('添加条件全流程：选类型 + 填值 + 按弹层里那颗「添加」⇒ 页面真的多出一行', (tester) async {
      await openPage(tester, NotificationRule(id: 'r1', name: 'R'));
      await tester.tap(find.widgetWithText(TextButton, '添加').first);
      await tester.pumpAndSettle();

      // ⚠ 可点的是那一行（`InkWell`），label 只是它上方的标题文字 ⇒ 点 label 什么都不会发生
      //   （第一版就栽在这里）。弹层里第一颗 InkWell 就是类型那一格。
      await tester.tap(
        find
            .descendant(
              of: find.byType(CupertinoAlertDialog),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ios-picker-ConditionType.titleContains')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.byType(TextField),
        ),
        '验证码',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text('添加'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(CupertinoAlertDialog),
        findsNothing,
        reason: '提交后弹层要自己下场（#103 那一类「点了没反应」就是它没退）',
      );
      expect(
        find.text('标题包含'),
        findsOneWidget,
        reason: '条件行没出现 ⇒ 这一发只是把表单关了，什么都没落',
      );
      expect(find.text('验证码'), findsOneWidget);
    });

    testWidgets('添加动作全流程：选类型 + 按「添加」⇒ 页面真的多出一行动作', (tester) async {
      await openPage(tester, NotificationRule(id: 'r1', name: 'R'));

      // 动作区那颗是第二颗「添加」（第一颗属于条件区）
      // ⚠ 它在 800×600 的测试视口外（实测中心 Offset(736,755)）⇒ 不先滚进视野这发 tap 打空，
      //   对话框根本没被按出来。这和首页那次的教训同一条：视口外的格子躺在那儿但点不到。
      final actionAddBtn = find.widgetWithText(TextButton, '添加').last;
      await tester.ensureVisible(actionAddBtn);
      await tester.pumpAndSettle();
      await tester.tap(actionAddBtn);
      await tester.pumpAndSettle();
      expect(
        find.byType(CupertinoAlertDialog),
        findsOneWidget,
        reason: '动作表单弹层没出现 ⇒ 「添加」那一发没接到 _addAction',
      );

      await tester.tap(
        find
            .descendant(
              of: find.byType(CupertinoAlertDialog),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final firstOption = find.byKey(
        const ValueKey('ios-picker-ActionType.push'),
      );
      expect(firstOption, findsOneWidget, reason: '动作类型 picker 没打开');
      await tester.tap(firstOption);
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text('添加'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(
        find.text('推送通知'),
        findsWidgets,
        reason: '动作行没出现 ⇒ 提交链断了（类型标签在行内与别处都可能出现，故 findsWidgets）',
      );
    });
  });

  // #201：上面那组只钉了「新增」那两枚。`ruleEditCondition` / `ruleEditAction` 这两枚表单
  // 在 test/ 与 integration_test/ 里实测零命中（grep 已核）⇒ 换外壳那一片对它们同样是空白。
  // 「编辑」比「新增」多一条会静默坏掉的判据：**取消不许写回**，而保存要真的替换那一行。
  group('编辑条件/编辑动作真的写回', () {
    // 一条件 + 一动作：页面上正好两颗编辑钮，文档顺序＝条件在前、动作在后
    NotificationRule oneEach() => NotificationRule(
      id: 'r1',
      name: 'R',
      conditions: [
        Condition(id: 'c1', type: ConditionType.titleContains, value: '验证码'),
      ],
      actions: [RuleAction(id: 'a1', type: ActionType.push)],
    );

    Future<void> openEditForm(
      WidgetTester tester, {
      required bool action,
    }) async {
      await tester.pumpWidget(_buildApp(RuleEditPage(rule: oneEach())));
      await tester.pumpAndSettle();
      final editBtns = find.widgetWithIcon(IconButton, Icons.edit);
      expect(editBtns, findsNWidgets(2), reason: '条件行与动作行各应有一颗编辑钮');
      final target = action ? editBtns.last : editBtns.first;
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(
        find.byType(CupertinoAlertDialog),
        findsOneWidget,
        reason:
            '${action ? '编辑动作' : '编辑条件'}表单没出现 ⇒ 那颗编辑钮没接到 _editAction/_editCondition',
      );
    }

    Future<void> submitForm(
      WidgetTester tester, {
      required String button,
    }) async {
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text(button),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('编辑条件：改值后按「保存」⇒ 那一行真的换成新值，旧值不再出现', (tester) async {
      await openEditForm(tester, action: false);

      await tester.enterText(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.byType(TextField),
        ),
        '登录提醒',
      );
      await submitForm(tester, button: '保存');

      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(
        find.text('登录提醒'),
        findsOneWidget,
        reason: '新值没出现在页面上 ⇒ onSave 收到了却什么都没写',
      );
      expect(
        find.text('验证码'),
        findsNothing,
        reason: '旧值还在 ⇒ 写回的是「多加一条」而不是「替换那一条」',
      );
    });

    testWidgets('编辑条件：按「取消」⇒ 那一行还是旧值（取消不许写回）', (tester) async {
      await openEditForm(tester, action: false);

      await tester.enterText(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.byType(TextField),
        ),
        '登录提醒',
      );
      await submitForm(tester, button: '取消');

      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(find.text('验证码'), findsOneWidget);
      expect(
        find.text('登录提醒'),
        findsNothing,
        reason: '取消那条路也把值写进去了 ⇒ 用户以为没改，规则却已经改了',
      );
    });

    testWidgets('编辑动作：换类型后按「保存」⇒ 那一行真的变成新档位', (tester) async {
      await openEditForm(tester, action: true);

      await tester.tap(
        find
            .descendant(
              of: find.byType(CupertinoAlertDialog),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ios-picker-ActionType.delay')),
      );
      await tester.pumpAndSettle();
      await submitForm(tester, button: '保存');

      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(
        find.text('延迟推送'),
        findsWidgets,
        reason: '动作行的档位没换 ⇒ 编辑那一路的 onSave 断了',
      );
    });
  });
}
