import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/services/channel_display.dart';
import 'package:notice_transmit/services/locale_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 通道身份（送达键）与显示名的契约测试。
///
/// 两条不可让的不变式：
/// 1. **送达键与语言无关**：切换软件语言只换显示名，`deliveryStatus` /
///    `webhook_delivery_log.tag` 的键不变（历史上键就是显示名，切语言即分裂成
///    中英双键 ⇒ 历史页重复徽标、旧键永远「发送中」）。
/// 2. **读旧数据必须认全部历史拼写**：DB 值、Kotlin 枚举名、驼峰、早期数字序号、
///    旧本地化键（中/英）都得归一到同一 slug，否则整条通道被读成 `generic`。
///
/// 未注册 LocaleService 时显示名回退中文（GetIt 未初始化的极早期调用路径）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('channelKey – 同一通道的全部历史拼写归一', () {
    void expectAllSpellings(String slug, List<String> spellings) {
      for (final raw in spellings) {
        expect(channelKey(raw), slug, reason: '拼写 $raw 应归一为 $slug');
      }
    }

    test('webhook 平台：DB snake / Kotlin 枚举名 / 驼峰 / 旧本地化键', () {
      expectAllSpellings('wechat_work', [
        'wechat_work',
        'WECHAT_WORK',
        'wechatWork',
        'webhook:企业微信',
        'webhook:WeCom',
        '企业微信',
        'WeCom',
        'chan:wechat_work',
      ]);
      expectAllSpellings('dingtalk', [
        'dingtalk',
        'DINGTALK',
        'webhook:钉钉',
        'webhook:DingTalk',
        '钉钉',
        'chan:dingtalk',
      ]);
      expectAllSpellings('feishu', [
        'feishu',
        'FEISHU',
        'webhook:飞书',
        'webhook:Feishu',
        '飞书',
      ]);
      expectAllSpellings('server_chan', [
        'server_chan',
        'SERVER_CHAN',
        'serverChan',
        'webhook:Server酱',
        'webhook:ServerChan',
        'Server酱',
      ]);
      expectAllSpellings('push_plus', [
        'push_plus',
        'PUSH_PLUS',
        'pushPlus',
        'webhook:PushPlus',
      ]);
      expectAllSpellings('telegram', [
        'telegram',
        'TELEGRAM',
        'webhook:Telegram',
      ]);
      expectAllSpellings('bark', ['bark', 'BARK', 'webhook:Bark']);
      expectAllSpellings('ntfy', ['ntfy', 'NTFY', 'webhook:ntfy']);
      expectAllSpellings('gotify', ['gotify', 'GOTIFY', 'webhook:Gotify']);
      expectAllSpellings('slack', ['slack', 'SLACK', 'webhook:Slack']);
      expectAllSpellings('discord', ['discord', 'DISCORD', 'webhook:Discord']);
      expectAllSpellings('generic', [
        'generic',
        'GENERIC',
        'webhook:通用',
        'webhook:Generic',
        '通用 Webhook',
      ]);
    });

    test('自建应用通道：与同名 webhook 不合并', () {
      expectAllSpellings('wecom_app', [
        'wecom_app',
        'WECOM_APP',
        'wecomApp',
        '应用:企业微信应用',
        'App:WeCom App',
        '企业微信应用',
        // 早期首页手打的废弃写法（'自建应用:企微'，剥前缀后剩 '企微'）
        '自建应用:企微',
      ]);
      expectAllSpellings('feishu_app', [
        'feishu_app',
        'FEISHU_APP',
        'feishuApp',
        '应用:飞书应用',
        'App:Feishu App',
        '飞书应用',
      ]);
      expect(channelKey('wecom_app'), isNot(channelKey('wechat_work')));
    });

    test('数字序号与 ConfigManager.parseWebhookType 同表', () {
      // 注意：这套序号 **不等于** Dart 侧下拉列表的下标（3=generic、4=telegram）
      const digits = {
        '0': 'wechat_work',
        '1': 'dingtalk',
        '2': 'feishu',
        '3': 'generic',
        '4': 'telegram',
        '5': 'bark',
        '6': 'server_chan',
        '7': 'push_plus',
        '8': 'ntfy',
        '9': 'gotify',
        '10': 'slack',
        '11': 'discord',
      };
      digits.forEach((digit, slug) {
        expect(channelKey(digit), slug, reason: '序号 $digit');
      });
    });

    test('邮件与拦截/聚合伪通道', () {
      expectAllSpellings('email', [
        'email',
        'EMAIL',
        '邮件',
        'Email',
        'chan:email',
      ]);
      // FILTER 与 SMS 在原生侧是两种回传、同一语义 ⇒ 同一个规范键
      expectAllSpellings('blocked', [
        'filter',
        'FILTER',
        'sms',
        'SMS',
        '过滤拦截',
        'Blocked',
        'chan:blocked',
      ]);
      expectAllSpellings('merge', [
        'merge',
        'MERGE',
        '合并推送',
        'Merged',
        'chan:merge',
      ]);
    });

    test('未知/空值兜底 generic', () {
      expect(channelKey('unknown_type'), 'generic');
      expect(channelKey(''), 'generic');
      expect(channelKey('   '), 'generic');
    });
  });

  group('channelDeliveryKey – 存储键', () {
    test('形如 chan:<slug>，且对已归一的键幂等', () {
      expect(channelDeliveryKey('DINGTALK'), 'chan:dingtalk');
      expect(channelDeliveryKey('chan:dingtalk'), 'chan:dingtalk');
      // 幂等是 DB v11 迁移可重复执行的前提
      expect(
        channelDeliveryKey(channelDeliveryKey('webhook:企业微信')),
        'chan:wechat_work',
      );
    });

    test('不同语言的显示名得到同一个键；应用通道与邮件互不混淆', () {
      expect(
        channelDeliveryKey('webhook:钉钉'),
        channelDeliveryKey('webhook:DingTalk'),
      );
      expect(
        channelDeliveryKey('wecom_app'),
        isNot(channelDeliveryKey('email')),
      );
    });
  });

  group('channelTypeDisplayName – 显示名不掺存储前缀', () {
    tearDown(() => GetIt.instance.reset());

    test('中文环境：无前缀（前缀是"显示名充当存储键"时代的产物）', () {
      expect(channelTypeDisplayName('wechat_work'), '企业微信');
      expect(channelTypeDisplayName('dingtalk'), '钉钉');
      expect(channelTypeDisplayName('feishu'), '飞书');
      expect(channelTypeDisplayName('server_chan'), 'Server酱');
      expect(channelTypeDisplayName('wecom_app'), '企业微信应用');
      expect(channelTypeDisplayName('email'), '邮件');
      expect(channelTypeDisplayName('sms'), '过滤拦截');
      expect(channelTypeDisplayName('merge'), '合并推送');
      expect(channelTypeDisplayName('unknown'), '通用 Webhook');
      for (final name in [
        '企业微信',
        '钉钉',
        '飞书',
        '企业微信应用',
        '邮件',
        '过滤拦截',
        '通用 Webhook',
      ]) {
        expect(
          name,
          isNot(
            anyOf(
              startsWith('webhook:'),
              startsWith('应用:'),
              startsWith('chan:'),
            ),
          ),
          reason: '显示名带前缀会直接漏到界面文案上',
        );
      }
    });

    test('输入可以是送达键（读取侧不必先换算）', () {
      expect(channelTypeDisplayName('chan:dingtalk'), '钉钉');
      expect(channelTypeDisplayName('webhook:钉钉'), '钉钉');
    });

    test('英文环境：只换显示名，存储键不变', () async {
      SharedPreferences.setMockInitialValues({});
      final localeService = LocaleService();
      GetIt.instance.registerSingleton<LocaleService>(localeService);
      await localeService.setLanguage(AppLanguage.en);

      expect(channelTypeDisplayName('wechat_work'), 'WeCom');
      expect(channelTypeDisplayName('dingtalk'), 'DingTalk');
      expect(channelTypeDisplayName('wecom_app'), 'WeCom App');
      expect(channelTypeDisplayName('email'), 'Email');
      expect(channelTypeDisplayName('unknown'), 'Generic Webhook');
      expect(channelDeliveryKey('DINGTALK'), 'chan:dingtalk');
    });
  });

  group('normalizeDeliveryKeys – 旧记录读取归一', () {
    test('旧本地化键 → chan: 键，状态原样保留', () {
      final out = normalizeDeliveryKeys({
        'webhook:企业微信': {'status': 'success', 'message': 'ok'},
        '邮件': {'status': 'pending', 'message': ''},
        '过滤拦截': {'status': 'intercepted', 'message': '黑名单'},
      });
      expect(out.keys.toSet(), {
        'chan:wechat_work',
        'chan:email',
        'chan:blocked',
      });
      expect(out['chan:wechat_work'], {'status': 'success', 'message': 'ok'});
    });

    test('同通道的中英双键合并为一项（旧缺陷留下的分裂数据）', () {
      final out = normalizeDeliveryKeys({
        'webhook:钉钉': {'status': 'pending'},
        'webhook:DingTalk': {'status': 'success', 'message': 'ok'},
      });
      expect(out.length, 1);
      expect(out['chan:dingtalk'], {'status': 'success', 'message': 'ok'});
    });

    test('已归一时原样返回（幂等，不重新分配 Map）', () {
      final input = {
        'chan:feishu': {'status': 'success'},
      };
      expect(identical(normalizeDeliveryKeys(input), input), isTrue);
    });
  });
}
