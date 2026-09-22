import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/notification_record.dart';
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

  group('WebhookChannelType', () {
    test('value getter returns correct string', () {
      expect(WebhookChannelType.generic.value, 'generic');
      expect(WebhookChannelType.wechatWork.value, 'wechat_work');
      expect(WebhookChannelType.dingtalk.value, 'dingtalk');
      expect(WebhookChannelType.feishu.value, 'feishu');
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
      // 精确 host 匹配：weixin.qq.com 非 qyapi.weixin.qq.com → generic
      expect(
        WebhookChannel.detectTypeFromUrl('https://weixin.qq.com/webhook'),
        WebhookChannelType.generic,
      );
    });

    test('detectTypeFromUrl detects dingtalk', () {
      expect(
        WebhookChannel.detectTypeFromUrl(
          'https://oapi.dingtalk.com/robot/send',
        ),
        WebhookChannelType.dingtalk,
      );
      // 精确 host 匹配：dingtalk.com 非 oapi.dingtalk.com → generic
      expect(
        WebhookChannel.detectTypeFromUrl('https://dingtalk.com/webhook'),
        WebhookChannelType.generic,
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
        WebhookChannel.detectTypeFromUrl(
          'https://open.larksuite.com/open-apis/bot/v2/hook/test',
        ),
        WebhookChannelType.feishu,
      );
      // 精确 host 匹配：larksuite.com 非 open.larksuite.com → generic
      expect(
        WebhookChannel.detectTypeFromUrl('https://larksuite.com/webhook'),
        WebhookChannelType.generic,
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
