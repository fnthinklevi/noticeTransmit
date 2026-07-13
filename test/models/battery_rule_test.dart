import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/battery_rule.dart';

void main() {
  group('BatteryRuleType', () {
    test('value returns correct string', () {
      expect(BatteryRuleType.charging.value, 'charging');
      expect(BatteryRuleType.discharging.value, 'discharging');
      expect(BatteryRuleType.levelAbove.value, 'level_above');
      expect(BatteryRuleType.levelBelow.value, 'level_below');
      expect(BatteryRuleType.levelEquals.value, 'level_equals');
    });

    test('label returns correct display text', () {
      expect(BatteryRuleType.charging.label, '开始充电');
      expect(BatteryRuleType.discharging.label, '断开充电');
      expect(BatteryRuleType.levelAbove.label, '高于某值');
      expect(BatteryRuleType.levelBelow.label, '低于某值');
      expect(BatteryRuleType.levelEquals.label, '等于某值');
    });

    test('fromValue parses correctly', () {
      expect(
        BatteryRuleTypeExtension.fromValue('charging'),
        BatteryRuleType.charging,
      );
      expect(
        BatteryRuleTypeExtension.fromValue('level_below'),
        BatteryRuleType.levelBelow,
      );
      expect(
        BatteryRuleTypeExtension.fromValue('unknown'),
        BatteryRuleType.charging,
      );
    });

    test('hasValue returns correct boolean', () {
      expect(BatteryRuleType.charging.hasValue, false);
      expect(BatteryRuleType.discharging.hasValue, false);
      expect(BatteryRuleType.levelAbove.hasValue, true);
      expect(BatteryRuleType.levelBelow.hasValue, true);
      expect(BatteryRuleType.levelEquals.hasValue, true);
    });
  });

  group('BatteryRule', () {
    test('fromMap creates valid instance', () {
      final map = {
        'id': 'low20',
        'type': 'level_below',
        'value': 20,
        'enabled': true,
        'title': '电量低于20%',
        'content': '请及时充电',
      };

      final rule = BatteryRule.fromMap(map);

      expect(rule.id, 'low20');
      expect(rule.type, BatteryRuleType.levelBelow);
      expect(rule.value, 20);
      expect(rule.enabled, true);
      expect(rule.title, '电量低于20%');
      expect(rule.content, '请及时充电');
    });

    test('fromMap handles missing values with defaults', () {
      final map = <String, dynamic>{};

      final rule = BatteryRule.fromMap(map);

      expect(rule.id, '');
      expect(rule.type, BatteryRuleType.charging);
      expect(rule.value, 0);
      expect(rule.enabled, true);
      expect(rule.title, '');
      expect(rule.content, '');
    });

    test('toMap serializes correctly', () {
      final rule = BatteryRule(
        id: 'full',
        type: BatteryRuleType.levelAbove,
        value: 100,
        enabled: true,
        title: '电量充满',
        content: '',
      );

      final map = rule.toMap();

      expect(map['id'], 'full');
      expect(map['type'], 'level_above');
      expect(map['value'], 100);
      expect(map['enabled'], true);
      expect(map['title'], '电量充满');
    });

    test('defaultRules returns expected rules', () {
      final rules = BatteryRule.defaultRules();

      expect(rules, hasLength(5));

      final chargingRule = rules.firstWhere((r) => r.id == 'charging');
      expect(chargingRule.type, BatteryRuleType.charging);
      expect(chargingRule.enabled, true);
      expect(chargingRule.title, '开始充电');

      final fullRule = rules.firstWhere((r) => r.id == 'full');
      expect(fullRule.type, BatteryRuleType.levelAbove);
      expect(fullRule.value, 100);

      final low30Rule = rules.firstWhere((r) => r.id == 'low30');
      expect(low30Rule.type, BatteryRuleType.levelBelow);
      expect(low30Rule.value, 30);

      final dischargingRule = rules.firstWhere((r) => r.id == 'discharging');
      expect(dischargingRule.enabled, false);
    });

    test('copyWith creates modified copy', () {
      final original = BatteryRule(
        id: 'rule1',
        type: BatteryRuleType.charging,
        enabled: true,
      );
      final updated = original.copyWith(
        type: BatteryRuleType.levelBelow,
        value: 15,
      );

      expect(updated.id, 'rule1');
      expect(updated.type, BatteryRuleType.levelBelow);
      expect(updated.value, 15);
      expect(updated.enabled, true);
    });

    test('round-trip serialization', () {
      final original = BatteryRule(
        id: 'custom_rule',
        type: BatteryRuleType.levelEquals,
        value: 50,
        enabled: false,
        title: '电量达到50%',
        content: '自定义规则',
      );

      final map = original.toMap();
      final deserialized = BatteryRule.fromMap(map);

      expect(deserialized.id, original.id);
      expect(deserialized.type, original.type);
      expect(deserialized.value, original.value);
      expect(deserialized.enabled, original.enabled);
      expect(deserialized.title, original.title);
      expect(deserialized.content, original.content);
    });
  });
}
