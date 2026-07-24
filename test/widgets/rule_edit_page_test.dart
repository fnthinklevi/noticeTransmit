import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:notice_transmit/pages/rule_edit_page.dart';
import 'package:notice_transmit/models/notification_rule.dart';

void main() {
  group('RuleEditPage – widget smoke tests', () {
    testWidgets('renders in create mode without crash', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RuleEditPage(rule: NotificationRule(id: '', name: '')),
        ),
      );
      expect(find.byType(RuleEditPage), findsOneWidget);
    });

    testWidgets('renders in edit mode with existing rule', (tester) async {
      final rule = NotificationRule(
        id: 'test-rule',
        name: 'Test Rule',
        enabled: true,
        priority: 50,
        conditions: [
          Condition(
            id: 'c1',
            type: ConditionType.titleContains,
            value: '验证码',
          ),
        ],
        actions: [RuleAction(id: 'a1', type: ActionType.push)],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RuleEditPage(rule: rule),
        ),
      );
      expect(find.byType(RuleEditPage), findsOneWidget);
    });
  });
}
