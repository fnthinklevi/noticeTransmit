import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/webhook_channel.dart';

void main() {
  group('WebhookChannelType', () {
    test('value returns correct string', () {
      expect(WebhookChannelType.generic.value, 'generic');
      expect(WebhookChannelType.wechatWork.value, 'wechat_work');
      expect(WebhookChannelType.dingtalk.value, 'dingtalk');
      expect(WebhookChannelType.feishu.value, 'feishu');
    });

    test('label returns correct display text', () {
      expect(WebhookChannelType.generic.label, '通用 Webhook');
      expect(WebhookChannelType.wechatWork.label, '企业微信群机器人');
      expect(WebhookChannelType.dingtalk.label, '钉钉群机器人');
      expect(WebhookChannelType.feishu.label, '飞书群机器人');
    });
  });

  group('WebhookChannel', () {
    test('detectTypeFromUrl identifies wechat work', () {
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

    test('detectTypeFromUrl identifies dingtalk', () {
      expect(
        WebhookChannel.detectTypeFromUrl(
          'https://oapi.dingtalk.com/robot/send',
        ),
        WebhookChannelType.dingtalk,
      );
      expect(
        WebhookChannel.detectTypeFromUrl(
          'https://dingtalk.example.com/webhook',
        ),
        WebhookChannelType.dingtalk,
      );
    });

    test('detectTypeFromUrl identifies feishu', () {
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

    test('detectTypeFromUrl defaults to generic for unknown urls', () {
      expect(
        WebhookChannel.detectTypeFromUrl('https://example.com/webhook'),
        WebhookChannelType.generic,
      );
      expect(
        WebhookChannel.detectTypeFromUrl('https://api.slack.com/webhook'),
        WebhookChannelType.generic,
      );
    });

    test('fromMap creates valid instance with explicit type', () {
      final map = {
        'id': 'channel1',
        'name': 'My Channel',
        'url': 'https://example.com/webhook',
        'type': 'dingtalk',
        'enabled': true,
      };

      final channel = WebhookChannel.fromMap(map);

      expect(channel.id, 'channel1');
      expect(channel.name, 'My Channel');
      expect(channel.url, 'https://example.com/webhook');
      expect(channel.type, WebhookChannelType.dingtalk);
      expect(channel.enabled, true);
    });

    test('fromMap auto-detects type when not specified', () {
      final map = {'url': 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send'};

      final channel = WebhookChannel.fromMap(map);

      expect(channel.type, WebhookChannelType.wechatWork);
    });

    test('fromMap generates id when not specified', () {
      final map = {'url': 'https://example.com/webhook'};
      final channel = WebhookChannel.fromMap(map);

      expect(channel.id, isNotEmpty);
    });

    test('toMap serializes correctly', () {
      final channel = WebhookChannel(
        id: 'channel1',
        name: 'Test Channel',
        url: 'https://example.com/webhook',
        type: WebhookChannelType.generic,
        enabled: false,
      );

      final map = channel.toMap();

      expect(map['id'], 'channel1');
      expect(map['name'], 'Test Channel');
      expect(map['url'], 'https://example.com/webhook');
      expect(map['type'], 'generic');
      expect(map['enabled'], false);
    });

    test('copyWith creates modified copy', () {
      final original = WebhookChannel(
        id: 'channel1',
        name: 'Original',
        url: 'https://old.example.com/webhook',
        type: WebhookChannelType.generic,
        enabled: true,
      );

      final updated = original.copyWith(
        name: 'Updated',
        url: 'https://new.example.com/webhook',
        enabled: false,
      );

      expect(updated.id, 'channel1');
      expect(updated.name, 'Updated');
      expect(updated.url, 'https://new.example.com/webhook');
      expect(updated.type, WebhookChannelType.generic);
      expect(updated.enabled, false);
    });

    test('round-trip serialization', () {
      final original = WebhookChannel(
        id: 'channel1',
        name: 'My Feishu Bot',
        url: 'https://open.feishu.cn/open-apis/bot/v2/hook/test',
        type: WebhookChannelType.feishu,
        enabled: true,
      );

      final map = original.toMap();
      final deserialized = WebhookChannel.fromMap(map);

      expect(deserialized.id, original.id);
      expect(deserialized.name, original.name);
      expect(deserialized.url, original.url);
      expect(deserialized.type, original.type);
      expect(deserialized.enabled, original.enabled);
    });
  });
}
