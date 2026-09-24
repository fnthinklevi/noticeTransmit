import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/email_channel.dart';
import 'package:notice_transmit/services/active_channels.dart';
import 'package:notice_transmit/services/app_channel_service.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/services/email_service.dart';
import 'package:notice_transmit/services/webhook_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_setup.dart';

/// T01：首页「当前推送通道」的状态必须真的来自健康单点。
///
/// 病灶（改之前）：`ActiveChannel.statusLabel` 是 `tested == false ? 'error' : 'ok'`，
/// 而 `tested` **只有 email 族会赋值** ⇒ 所有 webhook 与自建应用通道恒显"状态正常"，
/// 哪怕从没探测过、哪怕上一次探测是失败的。首页因此是一个恒绿的灯。
///
/// 这里锁三件事：
/// 1. 三族的状态**同一条判据**（都读 `ChannelHealthStore`）；
/// 2. 「没有新鲜结果」是**未知**，不是正常也不是异常（正常是谎，异常是假警报）；
/// 3. 显示格式统一成 `类型：（子类型/）通道名`（邮件族无子类型）。
///
/// 断言用中文文案：这些用例不注册 LocaleService，`channel_*_name` 会退回中文
/// （见 channel_display 的 `_isEnglishLocale` 兜底），因此不依赖宿主语言环境。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  late AppChannelService appService;
  late WebhookService webhookService;
  late EmailService emailService;

  Map<String, dynamic> appRow({String name = '办公', bool enabled = true}) => {
    'id': 'app-1',
    'name': name,
    'appType': 'wecom_app',
    'baseUrl': 'https://qyapi.weixin.qq.com',
    'enabled': enabled,
  };

  Map<String, dynamic> hookRow({String name = '告警群', bool enabled = true}) => {
    'id': 'wh-1',
    'name': name,
    'type': 'dingtalk',
    'url': 'https://oapi.dingtalk.com/robot/send?access_token=t',
    'enabled': enabled,
  };

  Future<void> seedChannels({
    List<Map<String, dynamic>>? apps,
    List<Map<String, dynamic>>? hooks,
    List<EmailChannel> emails = const [],
  }) async {
    await appService.saveChannels([if (apps == null) appRow() else ...apps]);
    if (hooks != null && hooks.isNotEmpty) {
      await webhookService.saveChannels(hooks);
    }
    emailService.cachedChannels = emails;
  }

  EmailChannel enabledEmail({String id = 'e1', String name = '主邮箱'}) =>
      EmailChannel(
        id: id,
        name: name,
        enabled: true,
        smtpHost: 'smtp.example.com',
        smtpPort: 465,
        username: 'u@example.com',
        fromEmail: 'u@example.com',
        toEmail: 'to@example.com',
      );

  ActiveChannel? entry(String family) {
    for (final c in collectActiveChannels()) {
      if (c.family == family) return c;
    }
    return null;
  }

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    appService = AppChannelService(store: _FakeAppStore());
    webhookService = WebhookService(store: _FakeWebhookStore());
    emailService = EmailService();
    GetIt.instance.registerSingleton<AppChannelService>(appService);
    GetIt.instance.registerSingleton<WebhookService>(webhookService);
    GetIt.instance.registerSingleton<EmailService>(emailService);
    GetIt.instance.registerSingleton<ChannelHealthStore>(ChannelHealthStore());
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  group('T01 状态来源：三族一律读健康单点', () {
    test('从没探测过的通道判"未知"，不再恒显正常（病灶）', () async {
      await seedChannels(hooks: [hookRow()], emails: [enabledEmail()]);
      for (final family in const ['app', 'webhook', 'email']) {
        expect(
          entry(family)!.statusLabel,
          'unknown',
          reason:
              '$family 族没有探测记录却判出了结论 —— '
              '病灶就是 webhook/应用通道恒 '
              "'ok'，email 恒按 tested 判",
        );
      }
    });

    test('成功=正常、失败=异常，三族同判据（不按族特例）', () async {
      final health = GetIt.instance<ChannelHealthStore>();
      await seedChannels(hooks: [hookRow()], emails: [enabledEmail()]);
      // id 取自服务侧（保存链路会归一化形状），不硬抄 'wh-1'：抄错了这条用例
      // 只是"没记录 → unknown"，测不到判据本身
      final appId = appService.channels.first['id'] as String;
      final hookId = webhookService.channels.first['id'] as String;
      await health.record('app', appId, reachable: true, latencyMs: 30);
      await health.record('webhook', hookId, reachable: false, latencyMs: 9000);
      await health.record('email', 'e1', reachable: true, latencyMs: 120);

      expect(entry('app')!.statusLabel, 'ok');
      expect(
        entry('webhook')!.statusLabel,
        'error',
        reason: '上次探测失败必须冒到首页（此前恒绿）',
      );
      expect(entry('email')!.statusLabel, 'ok');
    });

    test('成功但记录已过时效（>6h）→ 未知：旧的成功不能证明现在通', () async {
      final staleAt = DateTime.now()
          .subtract(const Duration(hours: 7))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'channel_health_app:app-1': jsonEncode({
          'reachable': true,
          'latencyMs': 20,
          'httpCode': null,
          'probedAt': staleAt,
        }),
      });
      await GetIt.instance.unregister<ChannelHealthStore>();
      final health = ChannelHealthStore();
      await health.load();
      GetIt.instance.registerSingleton<ChannelHealthStore>(health);
      await seedChannels();

      // 「没记录」与「记录过期」都判 unknown —— 所以必须先证明记录真读到了，
      // 否则这条用例其实什么都没测
      expect(entry('app')!.health, isNotNull, reason: '预置键没命中：id 或键格式变了');
      expect(entry('app')!.statusLabel, 'unknown');
    });

    test('失败不因时效而降级成未知：失败是确凿证据，直到下次探测推翻它', () async {
      final failedAt = DateTime.now()
          .subtract(const Duration(days: 3))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'channel_health_app:app-1': jsonEncode({
          'reachable': false,
          'latencyMs': 5000,
          'httpCode': null,
          'probedAt': failedAt,
        }),
      });
      await GetIt.instance.unregister<ChannelHealthStore>();
      final health = ChannelHealthStore();
      await health.load();
      GetIt.instance.registerSingleton<ChannelHealthStore>(health);
      await seedChannels();

      expect(
        entry('app')!.statusLabel,
        'error',
        reason: '把陈旧失败判成未知 = 首页不再提醒用户这条通道是坏的',
      );
    });

    test('健康单点没注册：不崩，且 email 族不得被连带丢掉', () async {
      // 两个 GetIt 解析分开兜底是第 6 步留下的规矩：合成一个 try 时"健康单点没注册"
      // 会连带把 email 整族丢掉，表现为送达快照里再也不出现 chan:email。
      await GetIt.instance.unregister<ChannelHealthStore>();
      await seedChannels(emails: [enabledEmail()]);

      expect(entry('email'), isNotNull, reason: 'email 族被连带吞掉（回归）');
      expect(entry('email')!.statusLabel, 'unknown');
    });

    test('未启用的通道不进清单（既有语义不变）', () async {
      await seedChannels(apps: [appRow(enabled: false)]);
      expect(collectActiveChannels(), isEmpty);
    });
  });

  group('T01 显示格式：类型：（子类型/）通道名', () {
    test('webhook 带子类型、邮件族无子类型、名为空不留分隔符', () async {
      await seedChannels(hooks: [hookRow()], emails: [enabledEmail()]);
      expect(entry('webhook')!.displayLine, 'Webhook：钉钉/告警群');
      expect(entry('app')!.displayLine, '自建应用：企业微信应用/办公');
      expect(
        entry('email')!.displayLine,
        '邮件：主邮箱',
        reason: 'SMTP 没有子类型，不能写成"邮件：邮件/主邮箱"',
      );
    });

    test('通道名为空时只显示到子类型（T02 之前新建通道就是空名）', () async {
      await seedChannels(apps: [appRow(name: '')]);
      expect(entry('app')!.displayLine, '自建应用：企业微信应用');
    });
  });
}

class _FakeAppStore implements AppChannelStore {
  List<Map<String, dynamic>> rows = [];

  @override
  Future<List<Map<String, dynamic>>> getAppChannels() async => rows;

  @override
  Future<void> saveAppChannels(List<Map<String, dynamic>> channels) async {
    rows = List.of(channels);
  }
}

class _FakeWebhookStore implements WebhookChannelStore {
  List<Map<String, dynamic>> rows = [];

  @override
  Future<List<Map<String, dynamic>>> getWebhookChannels() async => rows;

  @override
  Future<void> saveWebhookChannels(List<Map<String, dynamic>> channels) async {
    rows = channels.map(Map<String, dynamic>.from).toList();
  }
}
