import 'dart:convert';

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

      // v1.5.67：新增预制「应用通知聚合」规则（默认开启），预制规则共 4 条
      expect(rules, hasLength(4));

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

      // 预制聚合规则：默认开启，作用域为全部应用（packageName='*'），动作为 merge
      final mergeRule = rules.firstWhere((r) => r.id == 'merge_burst');
      expect(mergeRule.enabled, true);
      expect(mergeRule.actions.first.type, ActionType.merge);
      expect(mergeRule.actions.first.params['windowSeconds'], 60);
      expect(mergeRule.conditions, hasLength(1));
      expect(mergeRule.conditions.first.type, ConditionType.packageName);
      expect(mergeRule.conditions.first.value, '*');
      // 聚合是「降噪」而非「优先」，优先级应低于验证码(100)与夜间免打扰(200)
      expect(mergeRule.priority, lessThan(smsRule.priority));
    });

    test('missingDefaults 仅补齐缺失 id，尊重用户已关闭的规则', () {
      // 用户已有 sms_code（手动关闭），且缺少其余预制规则
      final existing = [
        NotificationRule(id: 'sms_code', name: '验证码短信优先推送', enabled: false),
      ];
      final missing = NotificationRule.missingDefaults(existing);
      final missingIds = missing.map((r) => r.id).toSet();

      // 不应包含用户已存在的 sms_code（即使是关闭状态）
      expect(missingIds.contains('sms_code'), false);
      expect(missingIds.contains('merge_burst'), true);
      expect(missingIds.contains('marketing_block'), true);
      expect(missingIds.contains('night_dnd'), true);
    });

    test('missingDefaults 全部存在时返回空列表', () {
      final all = NotificationRule.defaultRules();
      expect(NotificationRule.missingDefaults(all), isEmpty);
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

    // ---- 落盘保真契约（回归测试）----
    //
    // 背景：`saveNotificationRules` 走 `jsonEncode(rules.map(toMap))` 持久化，
    // 因此 fromMap→toMap 的往返必须**逐字段无损**。历史缺陷：RuleAction.fromMap
    // 丢弃 params、NotificationRule.fromMap 丢弃 description，后果是用户编辑
    // 任意规则后 merge 的 windowSeconds、delay 的 delaySeconds 被静默清空
    // （原生退回默认 60s），预制规则的说明文案在 UI 上消失。
    // 这类缺陷不会报错、不会崩溃，只能靠本组用例拦住。

    test('落盘保真：description 经 fromMap/toMap 往返不丢失', () {
      final original = NotificationRule(
        id: 'r',
        name: 'n',
        description: '同一应用 60 秒内收到的多条通知合并为一条推送',
      );

      final restored = NotificationRule.fromMap(original.toMap());

      expect(restored.description, original.description);
    });

    test('落盘保真：merge 动作 windowSeconds 往返不丢失', () {
      final original = NotificationRule(
        id: 'merge_burst',
        name: '应用通知聚合',
        actions: [
          RuleAction(
            id: 'a1',
            type: ActionType.merge,
            params: {'windowSeconds': 120},
          ),
        ],
      );

      final restored = NotificationRule.fromMap(original.toMap());

      expect(restored.actions.first.type, ActionType.merge);
      // 关键断言：非默认值 120 必须原样保留（默认值是 60，用默认值做断言会假通过）
      expect(restored.actions.first.params['windowSeconds'], 120);
    });

    test('落盘保真：delay 动作 delaySeconds/scheduleTime 往返不丢失', () {
      final original = NotificationRule(
        id: 'r',
        name: 'n',
        actions: [
          RuleAction(
            id: 'a1',
            type: ActionType.delay,
            params: {'delaySeconds': 300},
          ),
        ],
      );

      final restored = NotificationRule.fromMap(original.toMap());

      expect(restored.actions.first.params['delaySeconds'], 300);

      final scheduled = RuleAction(
        id: 'a2',
        type: ActionType.delay,
        params: {'scheduleTime': '07:30'},
      );
      final restoredSchedule = RuleAction.fromMap(scheduled.toMap());
      expect(restoredSchedule.params['scheduleTime'], '07:30');
    });

    test('落盘保真：全部预制规则往返后字段完全一致', () {
      for (final rule in NotificationRule.defaultRules()) {
        final restored = NotificationRule.fromMap(
          jsonDecode(jsonEncode(rule.toMap())) as Map<String, dynamic>,
        );

        expect(restored.id, rule.id);
        expect(restored.name, rule.name);
        expect(
          restored.description,
          rule.description,
          reason: '${rule.id} 说明丢失',
        );
        expect(restored.enabled, rule.enabled);
        expect(restored.priority, rule.priority);
        expect(restored.conditions.length, rule.conditions.length);
        expect(restored.actions.length, rule.actions.length);
        for (var i = 0; i < rule.actions.length; i++) {
          expect(
            restored.actions[i].params,
            rule.actions[i].params,
            reason: '${rule.id} 动作参数丢失',
          );
        }
      }
    });

    test('RuleAction.fromMap 容忍 params 缺失、异型 Map 与类型化 Map', () {
      // params 缺失 → 空表，不抛异常
      expect(RuleAction.fromMap({'id': 'a', 'type': 'push'}).params, isEmpty);

      // params 为 Map<dynamic, dynamic>（_Map<dynamic, dynamic>）——旧实现会抛
      // TypeError: type '_Map<dynamic, dynamic>' is not a subtype of type
      // 'Map<String, dynamic>?'
      final loose = RuleAction.fromMap({
        'id': 'a',
        'type': 'merge',
        'params': <dynamic, dynamic>{'windowSeconds': 30},
      });
      expect(loose.params['windowSeconds'], 30);

      // params 为类型化 Map<String, int> → 可 cast，但 Map.from 拷贝后更安全
      final typed = RuleAction.fromMap({
        'id': 'a',
        'type': 'merge',
        'params': <String, int>{'windowSeconds': 45},
      });
      expect(typed.params['windowSeconds'], 45);
    });

    test('代码内构造规则经 toMap→fromMap 不抛异常（默认规则的 params 泛型）', () {
      // 回归：`NotificationRule.toMap()` 返回 Map<String, dynamic>，其中
      // actions/conditions 是 List<Map<String, dynamic>>、每个 action 的
      // params 是 Map<String, dynamic>；但 defaultRules() 里写成
      // `params: {'windowSeconds': 60}` 时，字面量的静态类型经构造器形参
      // `Map<String, dynamic> params` 收敛，运行时才是 _Map<String, dynamic>。
      // 真正危险的是**直接对 `defaultRules()` 产物做深拷贝/再解析**的路径。
      for (final rule in NotificationRule.defaultRules()) {
        final map = rule.toMap();
        expect(
          () => NotificationRule.fromMap(map),
          returnsNormally,
          reason: '${rule.id} toMap→fromMap 抛异常',
        );
      }
    });
  });
}
