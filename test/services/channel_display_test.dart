import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/services/channel_display.dart';
import 'package:notice_transmit/services/locale_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/source_guards.dart';

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
      expect(channelDeliveryKey('DINGTALK'), 'chan:dingtalk');
    });

    // ── 认不出就说得出来，不许编一个族名（T154 片4）─────────────────────────
    //
    // ⚠ 这组**改掉了本文件两条旧断言**（原来 `unknown` → 「通用 Webhook」）。
    //   那是 `channelKey` 的存储兜底被顺手带进了显示层：一条早就下架的通道，
    //   用户看到的是"我明明配的是邮件，它说通用 Webhook"。
    //   判据与同文件 `channelFamilyName`「未登记的族原样返回，不猜成 webhook」同源 ——
    //   这一族自己不该有两种口径。
    // ⚠ 两件事必须分开：**存储键仍然兜底**（认不出的老数据也得有稳定落点），
    //   **显示名不兜底**。下面 `channelKey` 那两条就是这个分岔。
    group('认不出的键：显示名不猜，存储键照旧兜底', () {
      tearDown(() => GetIt.instance.reset());

      test('显示名原样给出那一段 token（剥掉存储前缀）', () {
        expect(channelTypeDisplayName('chan:retired_family'), 'retired_family');
        expect(channelTypeDisplayName('retired_family'), 'retired_family');
        expect(
          channelTypeDisplayName('chan:Old_Weird_Slug'),
          'Old_Weird_Slug',
          reason:
              '**原样**给出，不做大小写归一 —— 那是存储层的事。'
              '这里 lowercase 一遍等于又造了第二种拼写：'
              '同一条老记录按大小写不同会显示成两个名字，而它本来只有一个',
        );
        expect(
          channelTypeDisplayName('chan:sms'),
          '过滤拦截',
          reason:
              '反向自证：`sms` **认得出**（别名表里 `sms` → `blocked`），'
              '所以它必须仍显示「过滤拦截」而不是 token —— '
              '否则下面那几条就是在"什么都认不出"的前提下假绿',
        );
      });

      test('英文环境同样不猜（不因换语言就换成一个编出来的族名）', () async {
        SharedPreferences.setMockInitialValues({});
        final localeService = LocaleService();
        GetIt.instance.registerSingleton<LocaleService>(localeService);
        await localeService.setLanguage(AppLanguage.en);

        expect(channelTypeDisplayName('chan:retired_family'), 'retired_family');
      });

      test('空串回空串：那不是"通用"，那是什么都没有', () {
        expect(channelTypeDisplayName(''), '');
        expect(
          channelTypeDisplayName('chan:'),
          '',
          reason: '只有前缀没有内容 ⇒ 剥完是空的，不该回一个编出来的名字',
        );
      });

      test('存储键那一侧分毫不动：认不出仍落 generic（老数据要读得进来）', () {
        expect(channelKey('chan:retired_family'), 'generic');
        expect(channelKey(''), 'generic');
        expect(channelDeliveryKey('chan:retired_family'), 'chan:generic');
        expect(
          channelKey('sms'),
          'blocked',
          reason: '认得出的照旧认得出 —— 这一条钉的是"兜底只发生在认不出时"',
        );
      });

      // ⚠ 这一条是本片**真实要护住的后果**：显示名那一改，`normalizeDeliveryKeys`
      //   读旧数据的归一也走同一层。认不出的老键落 `generic` 之后，
      //   历史页那一格会显示成「通用 Webhook」—— 这正是本片改掉的那种撒谎，
      //   所以它必须在**归一之后**仍然看得见，而不是在归一时被抹平。
      //   钉的是"键归一了、但显示名那一侧仍不猜"两件事同时成立。
      test('归一之后仍不撒谎：老键落进存储，显示名那一格仍说得出它认不出', () {
        final out = normalizeDeliveryKeys({
          'retired_family': {'status': 'failed', 'message': '超时'},
        });
        expect(
          out.keys.single,
          'chan:generic',
          reason: '存储键那侧照旧兜底 —— 老数据要读得进来',
        );
        expect(
          channelTypeDisplayName(out.keys.single),
          '通用 Webhook',
          reason:
              '⚠ 这是本片**认下的残余代价**，不是漏网：键一旦归一成 `chan:generic`，'
              '显示层就再也分不出"它本来就是通用"与"它本来是别的一族、只是认不出了"。'
              '归一那一步是有意的（老数据要能读），所以这一格只能显示成通用。'
              '换句话说：**本片治的是"还没归一、还看得到原键"的那条路**'
              '（`record.channels` 与送达日志 tag 直接给原键），'
              '而这一条属于"已经归一、线索没了"的那条 —— 要治它得让归一保留原键，'
              '那是动存储形状，不在本片范围内。写在这里免得后人读成"漏了一个"。',
        );
      });

      test('反向自证：兜底那一句删掉就会红（尺不是恒真）', () {
        final src = librarySource(
          projectRoot(),
          'lib/services/channel_display.dart',
        );
        expect(
          stripComments(src)
              .contains("_resolveSlugOrNull(rawType) ?? 'generic'"),
          isTrue,
          reason:
              '存储兜底没了 ⇒ 认不出的键在写侧就会返回 null，'
              '而 `channelDeliveryKey` 会拼出 "chan:null" —— 那是比撒谎更坏的一种。'
              '⚠ 必须剥注释再找：那串字面量就写在「不许顺手带进显示层」那段注释里，'
              '不剥就会靠注释让这条恒绿。',
        );
      });
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
