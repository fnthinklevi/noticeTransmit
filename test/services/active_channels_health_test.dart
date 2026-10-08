import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/email_channel.dart';
import 'package:notice_transmit/models/fnthink_channel.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/services/active_channels.dart';
import 'package:notice_transmit/services/app_channel_service.dart';
import 'package:notice_transmit/services/channel_display.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/services/channel_probe_service.dart';
import 'package:notice_transmit/services/email_service.dart';
import 'package:notice_transmit/services/fnthink_channel_service.dart';
import 'package:notice_transmit/services/platform_channel.dart';
import 'package:notice_transmit/services/webhook_service.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  // ===== T104 第四族：幻念通道进这份清单 =====
  //
  // 病灶不是"少写一个 for"：这一族的通道此前在 Dart 侧**没有一个同步读口**（页面各自 await 开库），
  // 而这份清单是同步的（首页每帧、回前台那一轮、入库快照都读它）。片② 给的是 `cachedChannels`，
  // 片③ 把它接进来。这里钉的四件事按"错了不报错、只是慢慢说假话"排：
  // ① 启用中的那条**在**（不在就是 T104 没做完）；② 三列同口径（target／角色／显示名）；
  // ③ 服务器那一份结论不许冒充通道那一份（片① 拆的两种主语）；④ 自动重探**永不**碰它。
  group('T104 第四族进清单：显示口径 + 自动重探（T106 片③ 起会探设备档）', () {
    final helper = DatabaseHelper();
    late FnthinkChannelService channelService;

    const peerAddress = '8KMNPQRSTVWX999777';

    /// 一台已配对**且已勾选为转发目标**的设备 —— 设备目标的通道只认这种目标（服务那侧的判据）。
    Future<void> seedForwardPeer() async {
      await helper.upsertFnthinkPeer(
        const FnthinkPeer(
          peerAddress: peerAddress,
          publicKey: 'AAAA',
          level: 'L1',
          grantedAt: 1780000111000,
        ),
      );
      await channelService.setForward(peerAddress, true);
    }

    ActiveChannel? byId(String id) {
      for (final c in collectActiveChannels()) {
        if (c.family == 'fnthink' && c.id == id) return c;
      }
      return null;
    }

    setUp(() async {
      final dbPath = join(
        await getDatabasesPath(),
        'active_channels_fnthink_test.db',
      );
      if (await databaseFactory.databaseExists(dbPath)) {
        await databaseFactory.deleteDatabase(dbPath);
      }
      final db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(version: DatabaseHelper.dbVersion),
      );
      await helper.createSchemaForTest(db);
      helper.debugDatabase = db;
      channelService = FnthinkChannelService(db: helper);
      // 生产里这是 `setupLocator()` 里那**一个**实例（T104 片②）：装载与读缓存必须落在同一个对象上。
      GetIt.instance.registerSingleton<FnthinkChannelService>(channelService);
      addTearDown(() async {
        helper.debugDatabase = null;
        await db.close();
      });
    });

    test('启用中的幻念通道出现在清单里（此前一个字都不出现）', () async {
      await seedForwardPeer();
      await channelService.create(
        id: 'fc_dev',
        name: '机房那台',
        target: peerAddress,
        targetKind: FnthinkChannelTarget.device,
      );

      final e = byId('fc_dev');
      expect(e, isNotNull, reason: '一条启用中的幻念通道没进清单 = T104 没做完');
      expect(e!.family, 'fnthink');
      expect(e.slug, kFnthinkChannelSlug);
      expect(e.deliveryKey, 'chan:fnthink');
      // 设备目标的"关键链接"就是那台地址码：它不含凭据，且是用户用来认设备的那串。
      expect(e.target, peerAddress);
      expect(e.role, 'primary');
      expect(
        e.displayLine,
        '幻念推送：机房那台',
        reason: '族名没登记进 `_familyNames` 时这里会画成英文 token「fnthink：…」',
      );
      expect(
        e.statusLabel,
        'unknown',
        reason: '从没测过的通道在首页不许显示"正常" —— 这一族的探针只有"真发一条"那一种',
      );
    });

    test('webhook 目标那条只留 host：path 里常常就是凭据', () async {
      await channelService.create(
        id: 'fc_hook',
        name: '自建端点',
        target: 'https://push.example.com/hook/secretpath',
        targetKind: FnthinkChannelTarget.webhook,
      );
      expect(byId('fc_hook')!.target, 'push.example.com');
    });

    test('停用 ⇒ 从清单与送达快照一起退掉（与另三族同一判据）', () async {
      await seedForwardPeer();
      await channelService.create(
        id: 'fc_off',
        name: '停掉的那条',
        target: peerAddress,
        targetKind: FnthinkChannelTarget.device,
      );
      expect(deliveryKeysOfActiveChannels(), contains('chan:fnthink'));

      final created = (await channelService.list()).firstWhere(
        (c) => c.id == 'fc_off',
      );
      await channelService.save(created.copyWith(enabled: false));

      expect(byId('fc_off'), isNull);
      expect(
        deliveryKeysOfActiveChannels(),
        isNot(contains('chan:fnthink')),
        reason: '界面上退掉了而入库快照还按它算 ⇒ 历史记录里那条永远"发送中"',
      );
    });

    test('服务器通不通 ≠ 这条通道通不通（片① 拆开的两种主语）', () async {
      final health = GetIt.instance<ChannelHealthStore>();
      await seedForwardPeer();
      await channelService.create(
        id: 'fc_dev',
        name: '机房那台',
        target: peerAddress,
        targetKind: FnthinkChannelTarget.device,
      );
      // 那台中转机判"不可达"，而这条通道从没测过。
      await health.record(
        kFnthinkServerFamily,
        'push.example.com',
        reachable: false,
        latencyMs: 9000,
      );

      expect(
        byId('fc_dev')!.statusLabel,
        'unknown',
        reason:
            '服务器那一份结论串到通道行上 = 首页当着用户说"这条通道坏了"，'
            '而这两件事的下一步动作完全不同（换档 vs 进详情点「仅探测」）',
      );
      expect(
        health.of(kFnthinkChannelSlug, 'push.example.com'),
        isNull,
        reason: '通道那一族的主语是**通道 id**：拿 host 去查它说明两处又共用族名了',
      );

      // 反向：通道自己测过之后结论只归通道，不许漏到服务器那一格。
      await health.record(
        kFnthinkChannelSlug,
        'fc_dev',
        reachable: true,
        latencyMs: 20,
      );
      expect(byId('fc_dev')!.statusLabel, 'ok');
      expect(
        health.of(kFnthinkServerFamily, 'push.example.com')!.reachable,
        isFalse,
      );
    });

    test('自动重探（含 force 那一发）现在会探这一族：设备档写进健康单点，webhook 档不探', () async {
      // ⚠ 这一格的**方向被 T106 片③ 改过**：T104 时这里断的是"一条记录都不写"，
      //   因为那一族当时没有非侵入探针（"顺手重探"＝替用户往对面发一条真通知）。
      //   现在探针有了（`/probe`，一条都不投），断的变成"它真的被探、而且只探设备档"。
      final health = GetIt.instance<ChannelHealthStore>();
      await seedChannels(
        hooks: [hookRow()],
        apps: [appRow()],
        emails: [enabledEmail()],
      );
      await seedForwardPeer();
      await channelService.create(
        id: 'fc_dev',
        name: '机房那台',
        target: peerAddress,
        targetKind: FnthinkChannelTarget.device,
      );
      await channelService.create(
        id: 'fc_hook',
        name: '自建端点',
        target: 'https://push.example.com/hook/secretpath',
        targetKind: FnthinkChannelTarget.webhook,
      );

      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppChannels.notification, (call) async {
            calls.add(call);
            return <String, Object?>{'reachable': true, 'latencyMs': 5};
          });
      GetIt.instance.registerSingleton<ChannelProbeService>(
        ChannelProbeService(health: health, channel: AppChannels.notification),
      );

      final probed = <String>[];
      Future<FnthinkProbeResult> stubProbe({required String peer}) async {
        probed.add(peer);
        return const FnthinkProbeResult(
          status: FnthinkPollStatus.ok,
          ready: false,
        );
      }

      // force：通道状态页下拉刷新那一路。
      await probeChannelsAcrossFamilies(force: true, fnthinkProbe: stubProbe);

      expect(
        probed,
        [peerAddress],
        reason:
            '设备档那条要真的被探（探的是那台地址码）；webhook 档那条今天探不了 —— '
            '它的干跑要另立一条出示长期口令的路（T106 片①b），这里跳过它而不是假装探过',
      );
      expect(
        health.of(kFnthinkChannelSlug, 'fc_dev')!.reachable,
        isFalse,
        reason: '服务端说"这条链立不住"（ready:false）就是一次失败，照实写',
      );
      expect(
        health.of(kFnthinkChannelSlug, 'fc_hook'),
        isNull,
        reason: '没探过就不许有记录 —— 写一条假的绿比不写更糟',
      );
      // 另三族的行为一字节不许因为"加了一族"而变。
      expect(
        calls.map((c) => c.method),
        containsAll(<String>['probeChannelHealth', 'probeAppChannelToken']),
        reason: '加第四族时把另两族一起弄丢了 ⇒ 过时效的灯又没人管',
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppChannels.notification, null);
    });

    test('进页/回前台那一路只探过期的：刚探过的那条不再发（force 才属于下拉）', () async {
      final health = GetIt.instance<ChannelHealthStore>();
      await seedForwardPeer();
      await channelService.create(
        id: 'fc_dev',
        name: '机房那台',
        target: peerAddress,
        targetKind: FnthinkChannelTarget.device,
      );

      final probed = <String>[];
      Future<FnthinkProbeResult> stubProbe({required String peer}) async {
        probed.add(peer);
        return const FnthinkProbeResult(
          status: FnthinkPollStatus.ok,
          ready: true,
        );
      }

      // 第一发（进页那一发就是 stale-only）：从没探过 ⇒ 探。
      await probeChannelsAcrossFamilies(fnthinkProbe: stubProbe);
      expect(probed, [peerAddress], reason: '从没测过的通道挂着「从未探测」，进页那次必须探它');
      expect(health.of(kFnthinkChannelSlug, 'fc_dev')!.reachable, isTrue);

      // 第二发：刚探过（在时效内）⇒ 一个字节都不发。
      await probeChannelsAcrossFamilies(fnthinkProbe: stubProbe);
      expect(probed, [
        peerAddress,
      ], reason: '进页/回前台是"顺手检查"，不是"每次露脸都发一轮请求"（另三族同一条不变量）');
    });
  });

  group('#174 过期之后有人重探：目标构造 + 全族扫一遍', () {
    // 能探的邮件通道：凭据要**齐**（探测目标的门槛里含密码）—— `enabledEmail()` 不带密码，
    // 拿它来断言会把"门槛生效"错读成"这条链路没接上"。
    EmailChannel probeableEmail() => const EmailChannel(
      id: 'e1',
      name: '主邮箱',
      enabled: true,
      smtpHost: 'smtp.example.com',
      smtpPort: 465,
      username: 'u@example.com',
      password: 'pw',
      fromEmail: 'u@example.com',
      toEmail: 'to@example.com',
    );

    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppChannels.notification, (call) async {
            calls.add(call);
            return <String, Object?>{'reachable': true, 'latencyMs': 5};
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppChannels.notification, null);
    });

    test('目标构造：能探才给（url 空的不给、凭据没填完的不给）', () async {
      await seedChannels(
        hooks: [
          hookRow(),
          {...hookRow(name: '没填 url'), 'id': 'wh-empty', 'url': ''},
        ],
        apps: [appRow()],
        emails: [
          probeableEmail(),
          const EmailChannel(
            id: 'e-incomplete',
            name: '凭据没填完',
            enabled: true,
            smtpHost: '',
            smtpPort: 465,
            username: '',
            fromEmail: '',
            toEmail: '',
          ),
        ],
      );

      expect(
        webhookService.probeTargets.length,
        1,
        reason: 'url 为空的通道不给目标：探它只会把徽标钉成"不可达"，而那其实是"配置没填完"',
      );
      expect(appService.probeTargets.single.method, 'probeAppChannelToken');
      expect(
        emailService.probeTargets.map((t) => t.id),
        ['e1'],
        reason: '凭据不完整的通道不给目标（T04 的缺失字段标记负责说那件事）',
      );
    });

    test('全族扫一遍：只探过期的那条，刚探过的一个字节都不发', () async {
      final health = GetIt.instance<ChannelHealthStore>();
      await seedChannels(
        hooks: [
          hookRow(),
          {
            ...hookRow(name: '第二条'),
            'id': 'wh-2',
            // 两条的 url 必须不同：断言「探的是哪一条」靠它 —— 同 url 时这条判据分不出对象
            'url': 'https://oapi.dingtalk.com/robot/send?access_token=second',
          },
        ],
        apps: [appRow()],
        emails: [probeableEmail()],
      );
      // id 取自服务侧（保存链路会归一化），不硬抄：抄错了这条用例只是"没记录 ⇒ unknown"。
      final rows = webhookService.channels;
      final freshId = rows.first['id'] as String;
      final freshUrl = rows.first['url'] as String;
      await health.record('webhook', freshId, reachable: true, latencyMs: 3);

      final prober = ChannelProbeService(
        health: health,
        channel: AppChannels.notification,
      );
      GetIt.instance.registerSingleton<ChannelProbeService>(prober);

      await probeChannelsAcrossFamilies();

      final probedHooks = calls
          .where((c) => c.method == 'probeChannelHealth')
          .toList();
      expect(
        probedHooks.length,
        1,
        reason: '刚探过的那一条（6h 内）不该被重探 —— 进页/回前台不是"必发一轮请求"的借口',
      );
      final probedArgs = probedHooks.single.arguments as Map;
      expect(
        probedArgs['url'],
        isNot(freshUrl),
        reason: '探错对象：重探应当落在**过期**的那一条上',
      );
      expect(
        calls.map((c) => c.method),
        containsAll(['probeAppChannelToken', 'verifySmtp']),
        reason: '三族都要扫到：只探 webhook 一族，应用/邮件那两族的"未知"就永远没人管',
      );
    });

    test('全族扫一遍（force）：刚探过的那一条也重探（下拉刷新那一路）', () async {
      final health = GetIt.instance<ChannelHealthStore>();
      await seedChannels(
        hooks: [
          hookRow(),
          {
            ...hookRow(name: '第二条'),
            'id': 'wh-2',
            'url': 'https://oapi.dingtalk.com/robot/send?access_token=second',
          },
        ],
        apps: [appRow()],
        emails: [probeableEmail()],
      );
      final freshId = webhookService.channels.first['id'] as String;
      await health.record('webhook', freshId, reachable: true, latencyMs: 3);
      GetIt.instance.registerSingleton<ChannelProbeService>(
        ChannelProbeService(health: health, channel: AppChannels.notification),
      );

      await probeChannelsAcrossFamilies(force: true);

      final probedHooks = calls
          .where((c) => c.method == 'probeChannelHealth')
          .toList();
      expect(
        probedHooks.length,
        2,
        reason: 'force 那一发若仍被 staleness 挡住 ⇒ 用户拉了圈、转完屏幕上什么都没变（手势成装饰品）',
      );
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
