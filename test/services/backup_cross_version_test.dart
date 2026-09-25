import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/notification_rule.dart';
import 'package:notice_transmit/models/webhook_channel.dart';
import 'package:notice_transmit/services/app_channel_service.dart';
import 'package:notice_transmit/services/backup_service.dart';
import 'package:notice_transmit/services/battery_service.dart';
import 'package:notice_transmit/services/channel_config_codec.dart';
import 'package:notice_transmit/services/device_info_service.dart';
import 'package:notice_transmit/services/email_service.dart';
import 'package:notice_transmit/services/filter_service.dart';
import 'package:notice_transmit/services/locale_service.dart';
import 'package:notice_transmit/services/platform_channel.dart';
import 'package:notice_transmit/services/sms_service.dart';
import 'package:notice_transmit/services/theme_service.dart';
import 'package:notice_transmit/services/engine_rule_codec.dart';
import 'package:notice_transmit/services/webhook_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/engine_rule_store_fake.dart';
import '../support/source_guards.dart';

/// 跨版本备份兼容回归（roadmap E10 的收尾项）。
///
/// 为什么单独成文：备份文件是恢复链路上唯一**不受我们控制**的输入 —— 容器可能是 v1
/// （没有 appChannels/battery/deviceName/preferences 四类），每一类的键名与值类型
/// 也随版本变过（`enabled` 真 bool ↔ SQLite 的 0/1、`secret` null ↔ 字符串 "null"、
/// 通道类型写在 `channelType` 还是 `channel_type`）。此前没有任何测试吃过一份
/// 真实历史文件，所以"恢复一次备份就丢一次类型/凭据"这类缺陷只能靠线上报回来。
///
/// [legacyV1Payload] 的形状取自维护者的真实备份：容器 version=1、
/// createdAt=2026-09-10（1.5.73 或更早导出）。**键名、值类型、哪些键为 null 照抄**，
/// 只把 URL/密钥/邮箱/中文名换成占位值 —— 凭据不进仓库。
Map<String, dynamic> legacyV1Payload() => {
  'webhookChannels': [
    {
      // 旧版把通道类型同时写在两个键上；送达回传与通知服务读 `type`
      'channelType': 'wechat_work',
      'type': 'wechat_work',
      'enabled': true,
      'id': 'wh_1786704137269_0',
      'message_format': 'default',
      'message_template': null,
      'name': '',
      'secret': null,
      'url': 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=PLACE-KEY',
    },
  ],
  'emailChannels': [
    {
      'enabled': false,
      'fromEmail': 'placeholder@qq.com',
      'id': '1785147068431',
      'name': '占位',
      'password': 'placeholder-auth-code',
      'smtpHost': 'smtp.qq.com',
      'smtpPort': 465,
      'toEmail': 'placeholder@qq.com',
      'useSSL': true,
      'username': 'placeholder@qq.com',
    },
  ],
  'notificationRules': [
    {
      'actions': [
        {'id': 'a1', 'type': 'silent', 'params': <String, dynamic>{}},
      ],
      'conditions': [
        {
          'id': 'c1',
          'type': 'time_range',
          'value': '22:00-07:00',
          'logic': 'and',
        },
      ],
      'description': '夜间免打扰说明',
      'enabled': false,
      'id': 'night_dnd',
      'name': '夜间免打扰',
      'priority': 200,
    },
    {
      'actions': [
        {
          'id': 'a1',
          'type': 'merge',
          'params': {'windowSeconds': 60},
        },
      ],
      'conditions': [
        {'id': 'c1', 'type': 'package_name', 'value': '*', 'logic': 'and'},
      ],
      'description': '聚合说明',
      'enabled': true,
      'id': 'merge_burst',
      'name': '应用通知聚合',
      'priority': 50,
    },
  ],
  'smsSettings': {
    'sms_monitor_enabled': true,
    'sms_code_monitor_enabled': true,
    'sms_sim_filter': 'all',
  },
  'appFilter': {'mode': 'allow', 'packages': <String>[]},
  'blacklistKeywords': ['广告', '优惠', '抢购'],
  'whitelistKeywords': ['验证码', '快递'],
  // v1 容器里确实没有 appChannels / battery / deviceName / preferences 四类
};

class _FakeWebhookStore implements WebhookChannelStore {
  List<Map<String, dynamic>> rows = [];
  Object? failWith;

  @override
  Future<List<Map<String, dynamic>>> getWebhookChannels() async => rows;

  @override
  Future<void> saveWebhookChannels(List<Map<String, dynamic>> channels) async {
    if (failWith != null) throw failWith!;
    rows = channels.map(Map<String, dynamic>.from).toList();
  }
}

class _FakeAppChannelStore implements AppChannelStore {
  List<Map<String, dynamic>> rows = [];

  @override
  Future<List<Map<String, dynamic>>> getAppChannels() async => rows;

  @override
  Future<void> saveAppChannels(List<Map<String, dynamic>> channels) async {
    rows = channels.map(Map<String, dynamic>.from).toList();
  }
}

class _FakeEmailStore implements EmailChannelStore {
  List<Map<String, dynamic>> rows = [];

  @override
  Future<List<Map<String, dynamic>>> getEmailChannels() async => rows;

  @override
  Future<void> saveEmailChannels(List<Map<String, dynamic>> channels) async {
    rows = channels.map(Map<String, dynamic>.from).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeWebhookStore webhookStore;
  late _FakeAppChannelStore appChannelStore;
  late _FakeEmailStore emailStore;
  late BackupService backup;
  late List<MethodCall> nativeCalls;

  /// 电量规则的内存存储（T20 起住 engine_rules 表）：备份的 battery 类别要钉的是
  /// "**库里**那一族真的被换了"，而不是内存列表换了个引用。
  late MemoryRuleStore batteryStore;

  /// 伪原生：写方法记账，读方法回读同一份 —— 否则 loadSettings 永远读到空，
  /// 「本机已有配置」这类判定就测不出来。
  late Map<String, Object?> nativeState;

  Object? handleNative(MethodCall call) {
    nativeCalls.add(call);
    if (call.method.startsWith('set')) {
      nativeState[call.method] = call.arguments;
      return true;
    }
    return switch (call.method) {
      'getEnabledPackages' =>
        (nativeState['setAppFilter'] as Map?)?['packages'] ?? <String>[],
      'getAppFilterMode' =>
        (nativeState['setAppFilter'] as Map?)?['mode'] ?? 'allow',
      'getBlacklistKeywords' =>
        (nativeState['setBlacklistKeywords'] as Map?)?['keywords'] ??
            <String>[],
      'getWhitelistKeywords' =>
        (nativeState['setWhitelistKeywords'] as Map?)?['keywords'] ??
            <String>[],
      'getSimCardCount' => 1,
      _ => null,
    };
  }

  setUp(() async {
    batteryStore = MemoryRuleStore();
    webhookStore = _FakeWebhookStore();
    appChannelStore = _FakeAppChannelStore();
    emailStore = _FakeEmailStore();
    nativeCalls = [];
    nativeState = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, (call) async {
          return handleNative(call);
        });
    SharedPreferences.setMockInitialValues({});
    backup = BackupService();
    GetIt.instance
      ..registerSingleton<WebhookService>(WebhookService(store: webhookStore))
      ..registerSingleton<AppChannelService>(
        AppChannelService(store: appChannelStore),
      )
      ..registerSingleton<EmailService>(EmailService(store: emailStore))
      ..registerSingleton<FilterService>(FilterService())
      ..registerSingleton<SmsService>(SmsService())
      ..registerSingleton<BatteryService>(BatteryService(store: batteryStore))
      ..registerSingleton<DeviceInfoService>(DeviceInfoService())
      ..registerSingleton<ThemeService>(ThemeService())
      ..registerSingleton<LocaleService>(LocaleService());
    await GetIt.instance<FilterService>().loadSettings();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, null);
    await GetIt.instance.reset();
  });

  /// 与页面同一条链路：validatePayload → restorePayload
  Future<RestoreReport> restore(
    Map<String, dynamic> payload, {
    bool overwrite = true,
  }) async {
    final (valid, _) = backup.validatePayload(payload);
    return backup.restorePayload(valid, overwriteExisting: overwrite);
  }

  Map<String, dynamic> webhookUiRow() =>
      GetIt.instance<WebhookService>().channels.single;

  group('真实 v1 备份 → 恢复链路', () {
    test('Webhook：通道类型/URL/格式不丢，内存形状页面可读', () async {
      final report = await restore(legacyV1Payload());
      expect(report.failedCategories, isEmpty, reason: '整次恢复不该有类别失败');

      final stored = webhookStore.rows.single;
      expect(stored['channel_type'], 'wechat_work');
      expect(
        stored['url'],
        'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=PLACE-KEY',
      );
      expect(stored['message_format'], 'default');
      // 文件里 secret 是 null：恢复要写成空串，不能落成字符串 "null"
      expect(stored['secret'], '');

      final ui = webhookUiRow();
      expect(ui['channelType'], 'wechat_work');
      expect(ui['type'], 'wechat_work', reason: '送达回传与通知服务按 type 取');
      // 页面 initState 按可空读法取值，但值本身必须是它期望的类型
      expect(ui['url'], isA<String>());
      expect(ui['enabled'], isA<bool>());
      expect(ui['id'], isA<String>());
      expect(ChannelConfigCodec.nullableText(ui['message_template']), isNull);
      expect(
        WebhookChannel.fromMap(ui).type,
        WebhookChannelType.wechatWork,
        reason: '模型读不出类型 = 恢复后按通用 webhook 发送',
      );
    });

    test('Webhook：恢复确实下发原生（完整通道 + 仅启用 URL）', () async {
      await restore(legacyV1Payload());
      // detectExisting 的 loadChannels 会先发一次"空表同步"，所以取最后一次
      // MethodChannel 会编解码参数：Map 回来是 `_Map<Object?,Object?>`，
      // 直接 cast 成 Map<String,dynamic> 会抛 —— 与生产代码同一套 from() 写法。
      final sent =
          (nativeCalls
                      .lastWhere((c) => c.method == 'setWebhookChannels')
                      .arguments!['channels']
                  as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
      expect(sent.single['type'], 'wechat_work');
      expect(sent.single['enabled'], isTrue);
      final urls =
          (nativeCalls
                      .lastWhere((c) => c.method == 'setWebhookUrls')
                      .arguments!['urls']
                  as List)
              .map((e) => e.toString())
              .toList();
      expect(
        urls.single,
        startsWith('https://qyapi.weixin.qq.com/'),
        reason: '启用的通道必须进后台推送名单',
      );
    });

    test('邮件通道：驼峰键 + int 端口 + 授权码不丢', () async {
      final report = await restore(legacyV1Payload());
      expect(report.failedCategories, isEmpty);
      final row = emailStore.rows.single;
      expect(row['smtpPort'], 465);
      expect(row['useSSL'], isTrue);
      expect(row['password'], 'placeholder-auth-code');
      expect(row['fromEmail'], 'placeholder@qq.com');
      // enabled:false 不能被"缺省即启用"读成开
      expect(row['enabled'], isFalse);
      final cached = GetIt.instance<EmailService>().cachedChannels.single;
      expect(cached.smtpPort, 465);
      expect(cached.useSSL, isTrue);
      expect(cached.enabled, isFalse);
    });

    test('通知规则：优先级、条件类型、action params 逐字段保真', () async {
      await restore(legacyV1Payload());
      final prefs = await SharedPreferences.getInstance();
      final rules = (jsonDecode(prefs.getString('notification_rules')!) as List)
          .cast<Map<String, dynamic>>();
      expect(rules.map((r) => r['id']), ['night_dnd', 'merge_burst']);
      // 备份里的 50，不是当前预制值的 10：恢复不得"顺手升级"用户数据
      expect(rules[0]['priority'], 200);
      expect(rules[1]['priority'], 50);
      expect(rules[0]['enabled'], isFalse);
      expect(rules[0]['description'], '夜间免打扰说明');
      final conditions = (rules[0]['conditions'] as List)
          .cast<Map<String, dynamic>>();
      expect(conditions.single['value'], '22:00-07:00');
      expect(conditions.single['type'], 'time_range');
      final params =
          ((rules[1]['actions'] as List)
                  .cast<Map<String, dynamic>>()
                  .single['params']
              as Map);
      expect(params['windowSeconds'], 60);
      // 落给原生的是同一份（RuleEngine 读 JSON 同名键）
      final native =
          nativeCalls
                  .lastWhere((c) => c.method == 'setNotificationRules')
                  .arguments!['rules']
              as List;
      expect(native, hasLength(2));
    });

    test('关键词 / 应用筛选 / 短信开关按类别落盘', () async {
      final filter = GetIt.instance<FilterService>();
      final sms = GetIt.instance<SmsService>();
      await restore(legacyV1Payload());
      expect(filter.blacklistKeywords, ['广告', '优惠', '抢购']);
      expect(filter.whitelistKeywords, ['验证码', '快递']);
      expect(filter.appFilterMode, 'allow');
      expect(filter.enabledPackages, isEmpty);
      expect(sms.smsMonitorEnabled, isTrue);
      expect(sms.codeMonitorEnabled, isTrue);
      expect(sms.simFilter, 'all');
    });

    test('v1 缺少的四类保持本机配置（不得当成"备份里是空的"）', () async {
      appChannelStore.rows = [
        {
          'id': 'app_keep',
          'name': '自建飞书',
          'app_type': 'feishu_app',
          'base_url': 'https://open.feishu.cn',
          'enabled': 1,
          'config': '{"app_id":"cli_x"}',
        },
      ];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'battery_rules',
        jsonEncode([
          {'id': 'low20', 'type': 'level_below', 'value': 20, 'enabled': true},
        ]),
      );
      await prefs.setString('device_name', '我的手机');
      await prefs.setString('theme_mode', 'dark');

      final report = await restore(legacyV1Payload());

      expect(appChannelStore.rows.single['id'], 'app_keep');
      expect(prefs.getString('device_name'), '我的手机');
      expect(prefs.getString('theme_mode'), 'dark');
      expect(
        jsonDecode(prefs.getString('battery_rules')!) as List,
        hasLength(1),
      );
      for (final absent in [
        'appChannels',
        'battery',
        'deviceName',
        'preferences',
      ]) {
        expect(report.restored.keys, isNot(contains(absent)));
      }
    });

    test('备份里根本没有 webhookChannels 键：不得清空本机通道', () async {
      // 缺键 ≠ 空表。validatePayload 若给缺键补一个 []，覆盖模式就会
      // 把"这份备份没导出该类"执行成"删掉用户全部通道"。
      webhookStore.rows = [
        {
          'id': 'wh_local',
          'url': 'https://example.com/hook',
          'channel_type': 'generic',
          'enabled': 1,
        },
      ];
      final payload = legacyV1Payload()..remove('webhookChannels');
      final report = await restore(payload);
      expect(report.restored.keys, isNot(contains('webhookChannels')));
      expect(webhookStore.rows.single['id'], 'wh_local');
    });

    test('仅导入空缺项：本机已有的类别不动', () async {
      final filter = GetIt.instance<FilterService>();
      await filter.saveBlacklistKeywords(['本机关键词']);
      webhookStore.rows = [
        {
          'id': 'wh_local',
          'url': 'https://example.com/hook',
          'channel_type': 'generic',
          'enabled': 1,
        },
      ];
      final report = await restore(legacyV1Payload(), overwrite: false);
      expect(filter.blacklistKeywords, ['本机关键词']);
      expect(webhookStore.rows.single['id'], 'wh_local');
      expect(report.skippedCategories, contains('blacklistKeywords'));
      expect(report.skippedCategories, contains('webhookChannels'));
    });
  });

  group('形状不受控的文件（手改 / 别的导出工具 / 旧 DB 行）', () {
    test('只有 snake_case 键的 webhook 行：类型不丢、0/1 读成布尔', () async {
      await restore({
        'webhookChannels': [
          {
            'id': 'wh_snake',
            'channel_type': 'feishu',
            'url': 'https://open.feishu.cn/open-apis/bot/v2/hook/x',
            'enabled': 1,
            'secret': 'null',
            'message_template': 'null',
            'extra_config': {'legacy': true},
          },
        ],
      });
      final stored = webhookStore.rows.single;
      expect(stored['channel_type'], 'feishu');
      // ㊷ 之后没有任何链路读写 extra_config，恢复不得把它带回 DB 行
      expect(stored.containsKey('extra_config'), isFalse);
      final ui = webhookUiRow();
      expect(ui['channelType'], 'feishu');
      expect(ui['enabled'], isTrue);
      expect(ui['secret'], isNull, reason: '"null" 必须洗成未配置');
    });

    test('规则里的字符串优先级、0/1 开关、垃圾子表：按语义读，不抛', () async {
      await restore({
        'notificationRules': [
          {
            'id': 'r_num',
            'name': '优先级是字符串',
            'priority': '150',
            'enabled': 0,
            'conditions': {'not': 'a list'},
            'actions': [
              {'id': 'a1', 'type': 'merge', 'params': '{"windowSeconds":30}'},
            ],
          },
        ],
      });
      final rule = GetIt.instance<FilterService>().notificationRules.single;
      expect(rule.priority, 150);
      expect(rule.enabled, isFalse);
      expect(rule.conditions, isEmpty, reason: '非列表子表按"没有条件"处理');
      expect(rule.actions.single.type, ActionType.merge);
    });

    test('notificationRules 整体不是列表：跳过该类，本机规则不被清空', () async {
      final filter = GetIt.instance<FilterService>();
      final before = filter.notificationRules.length;
      expect(before, greaterThan(0), reason: 'setUp 已落预制规则');

      await restore({
        'notificationRules': {'garbage': true},
      });
      expect(filter.notificationRules, hasLength(before));
    });

    test('battery.rules 不是列表：保持本机规则而不是写空', () async {
      final battery = GetIt.instance<BatteryService>();
      await battery.restoreSettings(
        rules: [
          {'id': 'low20', 'type': 'level_below', 'value': 20},
        ],
      );
      await restore({
        'battery': {
          'notify_enabled': false,
          'rules': {'garbage': true},
        },
      });
      expect(battery.rules, hasLength(1));
      expect(
        batteryStore.rows[EngineRuleCodec.familyBattery],
        hasLength(1),
        reason: '只改内存不写存储 = 备份恢复"看起来成功"，重启又回到旧规则',
      );
      expect(battery.notifyEnabled, isFalse);
    });

    test('字符串开关、字符串名单、混进数字的关键词：认出来，不抛', () async {
      await restore({
        'smsSettings': {
          'sms_monitor_enabled': 'false',
          'sms_code_monitor_enabled': 0,
          'sms_sim_filter': '1',
        },
        'appFilter': {'mode': 'block', 'packages': 'com.a,com.b'},
        'blacklistKeywords': ['ok', 7, null],
      });
      final sms = GetIt.instance<SmsService>();
      expect(sms.smsMonitorEnabled, isFalse);
      expect(sms.codeMonitorEnabled, isFalse);
      expect(sms.simFilter, '1');
      // packages 不是列表 ⇒ 没有名单（allow/block + 空名单在原生侧都不拦任何应用）
      final filter = GetIt.instance<FilterService>();
      expect(filter.enabledPackages, isEmpty);
      expect(filter.appFilterMode, 'block');
      expect(filter.blacklistKeywords, ['ok', '7']);
    });
  });

  group('单类失败不得带走整次恢复', () {
    test('某类写盘抛异常：其余类别仍然恢复，报告点名失败类', () async {
      webhookStore.failWith = StateError('SQLCipher 打不开');
      final report = await restore(legacyV1Payload());
      expect(report.failedCategories.keys, ['webhookChannels']);
      expect(
        GetIt.instance<FilterService>().blacklistKeywords,
        hasLength(3),
        reason: '后面的类别必须继续恢复',
      );
      expect(report.restored.keys, contains('notificationRules'));
    });
  });

  group('DB 写入层仍然认 codec 的归一化结果', () {
    // DatabaseHelper 依赖原生 SQLCipher，纯 Dart 测试打不开真库，
    // 所以这一环用结构守卫钉住「列名键优先」（㊹② 修了 codec，这一处是同一 bug 的下游）。
    test('saveWebhookChannels 的 channel_type 先取列名键', () {
      final root = projectRoot();
      final src = stripComments(
        File('$root/lib/database/database_helper.dart').readAsStringSync(),
      );
      // ⚠ 必须用实现体的签名：`Future<void> saveWebhookChannels` 在
      // WebhookChannelStore 抽象声明里也出现一次，而签名式取块会一路吞到类体。
      final body = blockAfter(
        src,
        '@override\n  Future<void> saveWebhookChannels',
      );
      expect(body, contains("insert(\n          'webhook_channels'"));
      expect(
        RegExp(
          r"'channel_type':\s*c\['channel_type'\]\?\.toString\(\)\s*\?\?",
        ).hasMatch(body),
        isTrue,
        reason:
            '列名键必须排在 camel 之前：否则只带 channel_type 的行（老备份、legacy 迁移）'
            '会被这里重算成 generic，恢复一次备份丢一次通道类型',
      );
    });
  });
}
