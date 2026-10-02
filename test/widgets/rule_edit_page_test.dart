import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/rule_edit_page.dart';
import 'package:notice_transmit/models/notification_rule.dart';

Widget _buildApp(Widget home) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh'), Locale('en')],
    locale: const Locale('zh'),
    home: home,
  );
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
}
