import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/notification_rule.dart';

void main() {
  group('ConditionType', () {
    test('value returns correct string', () {
      expect(ConditionType.packageName.value, 'package_name');
      expect(ConditionType.titleContains.value, 'title_contains');
      expect(ConditionType.contentContains.value, 'content_contains');
      expect(ConditionType.priority.value, 'priority');
      expect(ConditionType.timeRange.value, 'time_range');
      expect(ConditionType.regexMatch.value, 'regex_match');
    });

    test('label returns correct display text', () {
      expect(ConditionType.packageName.label, '应用包名');
      expect(ConditionType.titleContains.label, '标题包含');
      expect(ConditionType.contentContains.label, '内容包含');
      expect(ConditionType.priority.label, '通知优先级');
      expect(ConditionType.timeRange.label, '时间范围');
      expect(ConditionType.regexMatch.label, '正则表达式');
    });

    test('fromValue parses correctly', () {
      expect(
        ConditionTypeExtension.fromValue('package_name'),
        ConditionType.packageName,
      );
      expect(
        ConditionTypeExtension.fromValue('title_contains'),
        ConditionType.titleContains,
      );
      expect(
        ConditionTypeExtension.fromValue('title_not_contains'),
        ConditionType.titleNotContains,
      );
      expect(
        ConditionTypeExtension.fromValue('unknown'),
        ConditionType.titleContains,
      );
    });
  });

  group('LogicOperator', () {
    test('value returns correct string', () {
      expect(LogicOperator.and.value, 'and');
      expect(LogicOperator.or.value, 'or');
    });

    test('label returns correct display text', () {
      expect(LogicOperator.and.label, '且');
      expect(LogicOperator.or.label, '或');
    });

    test('fromValue parses correctly', () {
      expect(LogicOperatorExtension.fromValue('and'), LogicOperator.and);
      expect(LogicOperatorExtension.fromValue('or'), LogicOperator.or);
      expect(LogicOperatorExtension.fromValue('unknown'), LogicOperator.and);
    });
  });

  group('Condition', () {
    test('fromMap creates valid instance', () {
      final map = {
        'id': 'c1',
        'type': 'title_contains',
        'value': 'test',
        'logic': 'or',
      };

      final condition = Condition.fromMap(map);

      expect(condition.id, 'c1');
      expect(condition.type, ConditionType.titleContains);
      expect(condition.value, 'test');
      expect(condition.logic, LogicOperator.or);
    });

    test('toMap serializes correctly', () {
      final condition = Condition(
        id: 'c1',
        type: ConditionType.contentContains,
        value: 'keyword',
        logic: LogicOperator.and,
      );

      final map = condition.toMap();

      expect(map['id'], 'c1');
      expect(map['type'], 'content_contains');
      expect(map['value'], 'keyword');
      expect(map['logic'], 'and');
    });

    test('copyWith creates modified copy', () {
      final original = Condition(
        id: 'c1',
        type: ConditionType.titleContains,
        value: 'test',
      );
      final updated = original.copyWith(
        type: ConditionType.contentContains,
        value: 'updated',
      );

      expect(updated.id, 'c1');
      expect(updated.type, ConditionType.contentContains);
      expect(updated.value, 'updated');
    });
  });

  group('ActionType', () {
    test('value returns correct string', () {
      expect(ActionType.push.value, 'push');
      expect(ActionType.silent.value, 'silent');
      expect(ActionType.delay.value, 'delay');
      expect(ActionType.merge.value, 'merge');
      expect(ActionType.record.value, 'record');
    });

    test('label returns correct display text', () {
      expect(ActionType.push.label, '推送通知');
      expect(ActionType.silent.label, '静默忽略');
      expect(ActionType.delay.label, '延迟推送');
      expect(ActionType.merge.label, '合并推送');
      expect(ActionType.record.label, '仅记录');
    });

    test('description returns correct description', () {
      expect(ActionType.push.description, '将通知推送到指定渠道');
      expect(ActionType.silent.description, '不推送，静默处理');
      expect(ActionType.delay.description, '延迟一段时间后推送');
    });

    test('fromValue parses correctly', () {
      expect(ActionTypeExtension.fromValue('push'), ActionType.push);
      expect(ActionTypeExtension.fromValue('silent'), ActionType.silent);
      expect(ActionTypeExtension.fromValue('unknown'), ActionType.push);
    });
  });

  group('RuleAction', () {
    test('fromMap creates valid instance', () {
      final map = {
        'id': 'a1',
        'type': 'silent',
        'params': {'delay': 60},
      };

      final action = RuleAction.fromMap(map);

      expect(action.id, 'a1');
      expect(action.type, ActionType.silent);
      expect(action.params, {'delay': 60});
    });

    test('toMap serializes correctly', () {
      final action = RuleAction(
        id: 'a1',
        type: ActionType.push,
        params: {'channel': 'webhook1'},
      );

      final map = action.toMap();

      expect(map['id'], 'a1');
      expect(map['type'], 'push');
      expect(map['params'], {'channel': 'webhook1'});
    });
  });

  group('NotificationRule', () {
    test('fromMap creates valid instance with conditions and actions', () {
      final map = {
        'id': 'rule1',
        'name': 'Test Rule',
        'description': 'A test rule',
        'enabled': true,
        'priority': 100,
        'conditions': [
          {
            'id': 'c1',
            'type': 'title_contains',
            'value': 'test',
            'logic': 'and',
          },
        ],
        'actions': [
          {'id': 'a1', 'type': 'push'},
        ],
      };

      final rule = NotificationRule.fromMap(map);

      expect(rule.id, 'rule1');
      expect(rule.name, 'Test Rule');
      expect(rule.enabled, true);
      expect(rule.priority, 100);
      expect(rule.conditions.length, 1);
      expect(rule.conditions.first.type, ConditionType.titleContains);
      expect(rule.actions.length, 1);
      expect(rule.actions.first.type, ActionType.push);
    });

    test('toMap serializes correctly with nested objects', () {
      final rule = NotificationRule(
        id: 'rule1',
        name: 'Test Rule',
        enabled: true,
        priority: 50,
        conditions: [
          Condition(
            id: 'c1',
            type: ConditionType.contentContains,
            value: 'keyword',
          ),
        ],
        actions: [RuleAction(id: 'a1', type: ActionType.silent)],
      );

      final map = rule.toMap();

      expect(map['id'], 'rule1');
      expect(map['name'], 'Test Rule');
      expect(map['enabled'], true);
      expect(map['conditions'], hasLength(1));
      expect(map['conditions'][0]['type'], 'content_contains');
      expect(map['actions'], hasLength(1));
      expect(map['actions'][0]['type'], 'silent');
    });

    test('defaultRules returns expected rules', () {
      final rules = NotificationRule.defaultRules();

      expect(rules, hasLength(3));

      final smsRule = rules.firstWhere((r) => r.id == 'sms_code');
      expect(smsRule.name, '验证码短信优先推送');
      expect(smsRule.enabled, true);
      expect(smsRule.priority, 100);

      final marketingRule = rules.firstWhere((r) => r.id == 'marketing_block');
      expect(marketingRule.name, '营销广告拦截');
      expect(marketingRule.actions.first.type, ActionType.silent);

      final nightRule = rules.firstWhere((r) => r.id == 'night_dnd');
      expect(nightRule.name, '夜间免打扰');
      expect(nightRule.priority, 200);
    });

    test('copyWith creates modified copy', () {
      final original = NotificationRule(id: 'rule1', name: 'Original');
      final updated = original.copyWith(name: 'Updated', enabled: false);

      expect(updated.id, 'rule1');
      expect(updated.name, 'Updated');
      expect(updated.enabled, false);
    });

    test('round-trip serialization', () {
      final original = NotificationRule(
        id: 'rule1',
        name: 'Test Rule',
        description: 'Description',
        enabled: false,
        priority: 10,
        conditions: [
          Condition(
            id: 'c1',
            type: ConditionType.packageName,
            value: 'com.test.app',
          ),
        ],
        actions: [RuleAction(id: 'a1', type: ActionType.record)],
      );

      final map = original.toMap();
      final deserialized = NotificationRule.fromMap(map);

      expect(deserialized.id, original.id);
      expect(deserialized.name, original.name);
      expect(deserialized.enabled, original.enabled);
      expect(deserialized.priority, original.priority);
      expect(deserialized.conditions.length, original.conditions.length);
      expect(deserialized.actions.length, original.actions.length);
    });
  });
}
