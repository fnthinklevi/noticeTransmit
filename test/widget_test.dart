import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/models/battery_rule.dart';
import 'package:notice_transmit/models/webhook_channel.dart';

void main() {
  group('NotificationRecord', () {
    test('fromMap handles null values', () {
      final record = NotificationRecord.fromMap({});
      expect(record.id, '');
      expect(record.title, '');
      expect(record.content, '');
      expect(record.subText, '');
      expect(record.packageName, '');
      expect(record.appName, '');
      expect(record.type, 'normal');
      expect(record.postTime, 0);
      expect(record.time, '');
      expect(record.deviceName, '');
    });

    test('fromMap with partial data', () {
      final record = NotificationRecord.fromMap({
        'id': 'test-123',
        'title': 'Test Title',
        'type': 'sms',
        'postTime': 1609459200000,
      });
      expect(record.id, 'test-123');
      expect(record.title, 'Test Title');
      expect(record.type, 'sms');
      expect(record.postTime, 1609459200000);
      expect(record.content, '');
      expect(record.appName, '');
    });

    test('toMap round-trip', () {
      final original = NotificationRecord(
        id: 'test-1',
        title: 'Test',
        content: 'Content',
        subText: 'Sub',
        packageName: 'com.test',
        appName: 'Test App',
        type: 'normal',
        postTime: 1234567890,
        time: '2024-01-01 12:00:00',
        deviceName: 'Device',
      );
      final map = original.toMap();
      final deserialized = NotificationRecord.fromMap(map);
      expect(deserialized.id, original.id);
      expect(deserialized.title, original.title);
      expect(deserialized.content, original.content);
      expect(deserialized.subText, original.subText);
      expect(deserialized.packageName, original.packageName);
      expect(deserialized.appName, original.appName);
      expect(deserialized.type, original.type);
      expect(deserialized.postTime, original.postTime);
      expect(deserialized.time, original.time);
      expect(deserialized.deviceName, original.deviceName);
    });

    test('copyWith works correctly', () {
      final original = NotificationRecord(
        id: 'id-1',
        title: 'Original',
        content: '',
        subText: '',
        packageName: '',
        appName: '',
        type: 'normal',
        postTime: 0,
        time: '',
        deviceName: '',
      );
      final updated = original.copyWith(title: 'Updated', type: 'sms');
      expect(updated.id, 'id-1');
      expect(updated.title, 'Updated');
      expect(updated.type, 'sms');
      expect(updated.content, '');
    });
  });

  group('BatteryRuleType', () {
    test('fromValue returns correct type', () {
      expect(
        BatteryRuleTypeExtension.fromValue('charging'),
        BatteryRuleType.charging,
      );
      expect(
        BatteryRuleTypeExtension.fromValue('discharging'),
        BatteryRuleType.discharging,
      );
      expect(
        BatteryRuleTypeExtension.fromValue('level_above'),
        BatteryRuleType.levelAbove,
      );
      expect(
        BatteryRuleTypeExtension.fromValue('level_below'),
        BatteryRuleType.levelBelow,
      );
      expect(
        BatteryRuleTypeExtension.fromValue('level_equals'),
        BatteryRuleType.levelEquals,
      );
    });

    test('fromValue handles unknown value', () {
      expect(
        BatteryRuleTypeExtension.fromValue('unknown'),
        BatteryRuleType.charging,
      );
    });

    test('value getter returns correct string', () {
      expect(BatteryRuleType.charging.value, 'charging');
      expect(BatteryRuleType.discharging.value, 'discharging');
      expect(BatteryRuleType.levelAbove.value, 'level_above');
      expect(BatteryRuleType.levelBelow.value, 'level_below');
      expect(BatteryRuleType.levelEquals.value, 'level_equals');
    });

    test('label getter returns correct label', () {
      expect(BatteryRuleType.charging.label, '开始充电');
      expect(BatteryRuleType.discharging.label, '断开充电');
      expect(BatteryRuleType.levelAbove.label, '高于某值');
      expect(BatteryRuleType.levelBelow.label, '低于某值');
      expect(BatteryRuleType.levelEquals.label, '等于某值');
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
    test('fromMap handles null values', () {
      final rule = BatteryRule.fromMap({});
      expect(rule.id, '');
      expect(rule.type, BatteryRuleType.charging);
      expect(rule.value, 0);
      expect(rule.enabled, true);
      expect(rule.title, '');
      expect(rule.content, '');
    });

    test('fromMap with partial data', () {
      final rule = BatteryRule.fromMap({
        'id': 'low20',
        'type': 'level_below',
        'value': 20,
        'enabled': false,
      });
      expect(rule.id, 'low20');
      expect(rule.type, BatteryRuleType.levelBelow);
      expect(rule.value, 20);
      expect(rule.enabled, false);
    });

    test('toMap round-trip', () {
      final original = BatteryRule(
        id: 'rule-1',
        type: BatteryRuleType.levelBelow,
        value: 20,
        enabled: true,
        title: '低电量提醒',
        content: '电量低于20%',
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

    test('copyWith works correctly', () {
      final original = BatteryRule(
        id: 'id-1',
        type: BatteryRuleType.charging,
        enabled: true,
      );
      final updated = original.copyWith(
        type: BatteryRuleType.levelBelow,
        value: 30,
        enabled: false,
      );
      expect(updated.id, 'id-1');
      expect(updated.type, BatteryRuleType.levelBelow);
      expect(updated.value, 30);
      expect(updated.enabled, false);
    });

    test('defaultRules returns correct rules', () {
      final rules = BatteryRule.defaultRules();
      expect(rules.length, 5);
      expect(rules[0].type, BatteryRuleType.charging);
      expect(rules[1].type, BatteryRuleType.levelAbove);
      expect(rules[1].value, 100);
      expect(rules[2].type, BatteryRuleType.levelBelow);
      expect(rules[2].value, 30);
      expect(rules[3].type, BatteryRuleType.levelBelow);
      expect(rules[3].value, 20);
      expect(rules[4].type, BatteryRuleType.discharging);
      expect(rules[4].enabled, false);
    });
  });

  group('WebhookChannelType', () {
    test('value getter returns correct string', () {
      expect(WebhookChannelType.generic.value, 'generic');
      expect(WebhookChannelType.wechatWork.value, 'wechat_work');
      expect(WebhookChannelType.dingtalk.value, 'dingtalk');
      expect(WebhookChannelType.feishu.value, 'feishu');
    });

    test('label getter returns correct label', () {
      expect(WebhookChannelType.generic.label, '通用 Webhook');
      expect(WebhookChannelType.wechatWork.label, '企业微信群机器人');
      expect(WebhookChannelType.dingtalk.label, '钉钉群机器人');
      expect(WebhookChannelType.feishu.label, '飞书群机器人');
    });
  });

  group('WebhookChannel', () {
    test('detectTypeFromUrl detects wechat work', () {
      expect(
        WebhookChannel.detectTypeFromUrl(
          'https://qyapi.weixin.qq.com/cgi-bin/webhook/send',
        ),
        WebhookChannelType.wechatWork,
      );
      expect(
        WebhookChannel.detectTypeFromUrl('https://weixin.qq.com/webhook'),
        WebhookChannelType.wechatWork,
      );
    });

    test('detectTypeFromUrl detects dingtalk', () {
      expect(
        WebhookChannel.detectTypeFromUrl(
          'https://oapi.dingtalk.com/robot/send',
        ),
        WebhookChannelType.dingtalk,
      );
      expect(
        WebhookChannel.detectTypeFromUrl('https://dingtalk.com/webhook'),
        WebhookChannelType.dingtalk,
      );
    });

    test('detectTypeFromUrl detects feishu', () {
      expect(
        WebhookChannel.detectTypeFromUrl(
          'https://open.feishu.cn/open-apis/bot/v2/hook/test',
        ),
        WebhookChannelType.feishu,
      );
      expect(
        WebhookChannel.detectTypeFromUrl('https://larksuite.com/webhook'),
        WebhookChannelType.feishu,
      );
    });

    test('detectTypeFromUrl defaults to generic', () {
      expect(
        WebhookChannel.detectTypeFromUrl('https://example.com/webhook'),
        WebhookChannelType.generic,
      );
    });

    test('fromMap with explicit type', () {
      final channel = WebhookChannel.fromMap({
        'id': 'channel-1',
        'name': '测试通道',
        'url': 'https://example.com/webhook',
        'type': 'dingtalk',
        'enabled': true,
      });
      expect(channel.id, 'channel-1');
      expect(channel.name, '测试通道');
      expect(channel.url, 'https://example.com/webhook');
      expect(channel.type, WebhookChannelType.dingtalk);
      expect(channel.enabled, true);
    });

    test('fromMap detects type from URL when type is not provided', () {
      final channel = WebhookChannel.fromMap({
        'url': 'https://oapi.dingtalk.com/robot/send',
      });
      expect(channel.type, WebhookChannelType.dingtalk);
    });

    test('fromMap generates UUID when id is not provided', () {
      final channel = WebhookChannel.fromMap({
        'url': 'https://example.com/webhook',
      });
      expect(channel.id.isNotEmpty, true);
      expect(channel.id.length, 36);
    });

    test('toMap round-trip', () {
      final original = WebhookChannel(
        id: 'channel-1',
        name: 'Test',
        url: 'https://example.com/webhook',
        type: WebhookChannelType.dingtalk,
        enabled: false,
      );
      final map = original.toMap();
      final deserialized = WebhookChannel.fromMap(map);
      expect(deserialized.id, original.id);
      expect(deserialized.name, original.name);
      expect(deserialized.url, original.url);
      expect(deserialized.type, original.type);
      expect(deserialized.enabled, original.enabled);
    });

    test('copyWith works correctly', () {
      final original = WebhookChannel(
        id: 'id-1',
        url: 'https://old.com',
        type: WebhookChannelType.generic,
        enabled: true,
      );
      final updated = original.copyWith(
        url: 'https://new.com',
        type: WebhookChannelType.dingtalk,
        enabled: false,
      );
      expect(updated.id, 'id-1');
      expect(updated.url, 'https://new.com');
      expect(updated.type, WebhookChannelType.dingtalk);
      expect(updated.enabled, false);
    });
  });
}
