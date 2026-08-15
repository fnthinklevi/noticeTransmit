import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:notice_transmit/l10n/app_localizations_delegate.dart';
import 'package:notice_transmit/pages/rule_edit_page.dart';
import 'package:notice_transmit/models/notification_rule.dart';

Widget _buildApp(Widget home) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
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
}
