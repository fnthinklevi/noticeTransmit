import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/notification_rule.dart';
import 'package:notice_transmit/services/filter_service.dart';

/// 构造一条模拟通知 Map，便于在测试中向 evaluateRule 传参。
Map<String, dynamic> makeNotification({
  String packageName = 'com.example.app',
  String title = 'Test Title',
  String content = 'Test Content',
  int priority = 0,
  String time = '',
}) {
  return {
    'packageName': packageName,
    'title': title,
    'content': content,
    'priority': priority,
    'time': time,
  };
}

/// 创建一个单条件的规则，logic 默认为 AND。
NotificationRule makeRule({
  String id = 'r1',
  String name = 'TestRule',
  bool enabled = true,
  ConditionType type = ConditionType.titleContains,
  String value = 'Test',
  LogicOperator logic = LogicOperator.and,
}) {
  return NotificationRule(
    id: id,
    name: name,
    enabled: enabled,
    priority: 10,
    conditions: [
      Condition(id: 'c1', type: type, value: value, logic: logic),
    ],
  );
}

void main() {
  late FilterService service;

  setUp(() {
    service = FilterService();
  });

  group('evaluateRule – basic logic', () {
    test('disabled rule returns false', () {
      final rule = makeRule(enabled: false);
      expect(
        service.evaluateRule(rule, makeNotification(title: 'Test')),
        false,
      );
    });

    test('rule with empty conditions returns false', () {
      final rule = NotificationRule(
        id: 'r1',
        name: 'Empty',
        enabled: true,
        conditions: [],
      );
      expect(service.evaluateRule(rule, makeNotification()), false);
    });

    test('single AND condition matched → true', () {
      final rule = makeRule(
        type: ConditionType.titleContains,
        value: 'Hello',
      );
      expect(
        service.evaluateRule(rule, makeNotification(title: 'Hello World')),
        true,
      );
    });

    test('single AND condition not matched → false', () {
      final rule = makeRule(
        type: ConditionType.titleContains,
        value: 'Hello',
      );
      expect(
        service.evaluateRule(rule, makeNotification(title: 'World')),
        false,
      );
    });
  });

  group('evaluateRule – condition types', () {
    test('packageName matches exactly', () {
      final rule = makeRule(type: ConditionType.packageName, value: 'com.a');
      expect(
        service.evaluateRule(rule, makeNotification(packageName: 'com.a')),
        true,
      );
      expect(
        service.evaluateRule(rule, makeNotification(packageName: 'com.b')),
        false,
      );
    });

    test('titleContains case-insensitive', () {
      final rule = makeRule(
        type: ConditionType.titleContains,
        value: 'hello',
      );
      expect(
        service.evaluateRule(rule, makeNotification(title: 'HELLO')),
        true,
      );
    });

    test('titleNotContains', () {
      final rule = makeRule(
        type: ConditionType.titleNotContains,
        value: 'spam',
      );
      expect(
        service.evaluateRule(rule, makeNotification(title: 'Hello')),
        true,
      );
      expect(
        service.evaluateRule(rule, makeNotification(title: 'SPAM Mail')),
        false,
      );
    });

    test('contentContains', () {
      final rule = makeRule(
        type: ConditionType.contentContains,
        value: '验证码',
      );
      expect(
        service.evaluateRule(
          rule,
          makeNotification(content: '您的验证码是 123456'),
        ),
        true,
      );
    });

    test('contentNotContains', () {
      final rule = makeRule(
        type: ConditionType.contentNotContains,
        value: '广告',
      );
      expect(
        service.evaluateRule(rule, makeNotification(content: '正常消息')),
        true,
      );
      expect(
        service.evaluateRule(rule, makeNotification(content: '优惠广告')),
        false,
      );
    });

    test('regexMatch – valid pattern', () {
      final rule = makeRule(
        type: ConditionType.regexMatch,
        value: r'验证码|校验码',
      );
      expect(
        service.evaluateRule(
          rule,
          makeNotification(title: '您的校验码是 888888'),
        ),
        true,
      );
      expect(
        service.evaluateRule(
          rule,
          makeNotification(title: 'Hello World'),
        ),
        false,
      );
    });

    test('regexMatch – invalid pattern silently returns false', () {
      final rule = makeRule(type: ConditionType.regexMatch, value: r'[unclosed');
      expect(
        service.evaluateRule(rule, makeNotification(title: 'anything')),
        false,
      );
    });

    test('priority – high / medium / low', () {
      final high = makeRule(type: ConditionType.priority, value: 'high');
      final medium = makeRule(type: ConditionType.priority, value: 'medium');
      final low = makeRule(type: ConditionType.priority, value: 'low');

      // FilterService 实现中: high=priority>=2, medium=1, low=0
      expect(
        service.evaluateRule(high, makeNotification(priority: 2)),
        true,
      );
      expect(
        service.evaluateRule(high, makeNotification(priority: 0)),
        false,
      );
      expect(
        service.evaluateRule(medium, makeNotification(priority: 1)),
        true,
      );
      expect(
        service.evaluateRule(medium, makeNotification(priority: 2)),
        false,
      );
      expect(
        service.evaluateRule(low, makeNotification(priority: 0)),
        true,
      );
      expect(
        service.evaluateRule(low, makeNotification(priority: 1)),
        false,
      );
    });

    test('timeRange – within range', () {
      final now = DateTime.now();
      final startH = ((now.hour - 1 + 24) % 24)
          .toString()
          .padLeft(2, '0');
      final endH = ((now.hour + 1) % 24).toString().padLeft(2, '0');
      final rule = makeRule(
        type: ConditionType.timeRange,
        value: '$startH:00-$endH:00',
      );
      expect(
        service.evaluateRule(rule, makeNotification(time: '')),
        true,
      );
    });
  });

  group('evaluateRule – AND / OR combinations', () {
    test('two conditions AND → both must match', () {
      final rule = NotificationRule(
        id: 'r1',
        name: 'AND Rule',
        enabled: true,
        priority: 10,
        conditions: [
          Condition(
            id: 'c1',
            type: ConditionType.packageName,
            value: 'com.wx',
            logic: LogicOperator.and,
          ),
          Condition(
            id: 'c2',
            type: ConditionType.titleContains,
            value: '验证码',
            logic: LogicOperator.and,
          ),
        ],
      );
      expect(
        service.evaluateRule(
          rule,
          makeNotification(packageName: 'com.wx', title: '验证码通知'),
        ),
        true,
      );
      expect(
        service.evaluateRule(
          rule,
          makeNotification(packageName: 'com.wx', title: '普通消息'),
        ),
        false,
      );
    });

    test('two conditions OR → either match is enough', () {
      // evaluateRule 中 condition.logic 是连接当前条件与前一个条件的运算符。
      // 第一个条件 logic=or 开始新组，第二个条件 logic=or 是 OR 连接。
      final rule = NotificationRule(
        id: 'r1',
        name: 'OR Rule',
        enabled: true,
        priority: 10,
        conditions: [
          Condition(
            id: 'c1',
            type: ConditionType.titleContains,
            value: '优惠',
            logic: LogicOperator.or,
          ),
          Condition(
            id: 'c2',
            type: ConditionType.titleContains,
            value: '验证码',
            logic: LogicOperator.or,
          ),
        ],
      );
      // 第一个条件作为第一组（isFirstCondition）
      expect(
        service.evaluateRule(
          rule,
          makeNotification(title: '优惠活动'),
        ),
        true,
      );
      // 第二个条件（logic=or → 新组）独立匹配
      expect(
        service.evaluateRule(
          rule,
          makeNotification(title: '我的验证码'),
        ),
        true,
      );
      // 两组都不匹配
      expect(
        service.evaluateRule(
          rule,
          makeNotification(title: '普通消息'),
        ),
        false,
      );
    });

    test('AND group then OR group', () {
      final rule = NotificationRule(
        id: 'r1',
        name: 'Mixed',
        enabled: true,
        priority: 10,
        conditions: [
          Condition(
            id: 'c1',
            type: ConditionType.packageName,
            value: 'com.wx',
            logic: LogicOperator.and,
          ),
          Condition(
            id: 'c2',
            type: ConditionType.titleContains,
            value: '验证码',
            logic: LogicOperator.and,
          ),
          // OR separator
          Condition(
            id: 'c3',
            type: ConditionType.packageName,
            value: 'com.sms',
            logic: LogicOperator.or,
          ),
          Condition(
            id: 'c4',
            type: ConditionType.titleContains,
            value: '验证码',
            logic: LogicOperator.and,
          ),
        ],
      );
      // 第一组：com.wx AND titleContains验证码 → 匹配
      expect(
        service.evaluateRule(
          rule,
          makeNotification(packageName: 'com.wx', title: '验证码'),
        ),
        true,
      );
      // 第二组：com.sms AND titleContains验证码 → 匹配
      expect(
        service.evaluateRule(
          rule,
          makeNotification(packageName: 'com.sms', title: '验证码'),
        ),
        true,
      );
      // 两组都不匹配
      expect(
        service.evaluateRule(
          rule,
          makeNotification(packageName: 'com.other', title: '普通'),
        ),
        false,
      );
    });
  });

  group('evaluateRule – edge cases', () {
    test('null/empty notification fields do not crash', () {
      final rule = makeRule(type: ConditionType.titleContains, value: 'test');
      final notif = <String, dynamic>{};
      expect(service.evaluateRule(rule, notif), false); // title defaults to ''
    });

    test('timeRange – null time string handled gracefully', () {
      final rule = makeRule(
        type: ConditionType.timeRange,
        value: '09:00-18:00',
      );
      // time is empty string → _evaluateTimeRangeCondition uses DateTime.now()
      final notif = makeNotification(time: '');
      final result = service.evaluateRule(rule, notif);
      expect(result, isA<bool>()); // should not throw
    });
  });
}
