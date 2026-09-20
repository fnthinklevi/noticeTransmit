import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/channel_display.dart';

/// 渠道类型显示名测试：覆盖 v1.5.72/73 新增通道（ntfy/Gotify/Slack/Discord/
/// 企业微信自建应用/飞书自建应用）及 DB 存储/历史枚举/Kotlin 回传三种来源。
/// 语言回退：GetIt 未注册 LocaleService 时回退中文。
void main() {
  group('channelTypeDisplayName – F4 通道（v1.5.72）', () {
    test('ntfy 三种来源均识别', () {
      expect(channelTypeDisplayName('ntfy'), 'webhook:ntfy');
      expect(channelTypeDisplayName('NTFY'), 'webhook:ntfy');
    });

    test('gotify 三种来源均识别', () {
      expect(channelTypeDisplayName('gotify'), 'webhook:Gotify');
      expect(channelTypeDisplayName('GOTIFY'), 'webhook:Gotify');
    });

    test('slack 三种来源均识别', () {
      expect(channelTypeDisplayName('slack'), 'webhook:Slack');
      expect(channelTypeDisplayName('SLACK'), 'webhook:Slack');
    });

    test('discord 三种来源均识别', () {
      expect(channelTypeDisplayName('discord'), 'webhook:Discord');
      expect(channelTypeDisplayName('DISCORD'), 'webhook:Discord');
    });
  });

  group('channelTypeDisplayName – 自建应用（v1.5.73）', () {
    test('wecom_app 应用通道前缀为「应用:」而非「webhook:」', () {
      // 自建应用已迁出 webhook 体系，标签前缀改为「应用:」
      expect(channelTypeDisplayName('wecom_app'), '应用:企业微信应用');
      expect(channelTypeDisplayName('wecomApp'), '应用:企业微信应用');
      expect(channelTypeDisplayName('WECOM_APP'), '应用:企业微信应用');
    });

    test('feishu_app 应用通道前缀为「应用:」', () {
      expect(channelTypeDisplayName('feishu_app'), '应用:飞书应用');
      expect(channelTypeDisplayName('feishuApp'), '应用:飞书应用');
      expect(channelTypeDisplayName('FEISHU_APP'), '应用:飞书应用');
    });

    test('未知类型兜底为通用 Webhook', () {
      expect(channelTypeDisplayName('unknown_type'), 'webhook:通用');
      expect(channelTypeDisplayName(''), 'webhook:通用');
    });

    test('旧通道标签不受影响（回归）', () {
      expect(channelTypeDisplayName('wechat_work'), 'webhook:企业微信');
      expect(channelTypeDisplayName('dingtalk'), 'webhook:钉钉');
      expect(channelTypeDisplayName('feishu'), 'webhook:飞书');
      expect(channelTypeDisplayName('telegram'), 'webhook:Telegram');
      expect(channelTypeDisplayName('bark'), 'webhook:Bark');
      expect(channelTypeDisplayName('server_chan'), 'webhook:Server酱');
      expect(channelTypeDisplayName('push_plus'), 'webhook:PushPlus');
      expect(channelTypeDisplayName('email'), '邮件');
      expect(channelTypeDisplayName('sms'), '过滤拦截');
      expect(channelTypeDisplayName('merge'), '合并推送');
    });
  });
}
