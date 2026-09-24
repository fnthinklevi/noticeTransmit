import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/email_channel.dart';
import 'package:notice_transmit/pages/channel_status_page.dart';
import 'package:notice_transmit/services/app_channel_service.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/services/email_service.dart';
import 'package:notice_transmit/services/webhook_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_setup.dart';

/// T10：通道状态页（首页「当前推送通道」点进来的那一页）。
///
/// 锁四件事：
/// 1. **按三族分组**，每行给通道名 / 类型 / 关键链接 / 最近一次探测；
/// 2. 关键链接**只有 host[:port]** —— webhook 的凭据常在 path 与 query 里
///    （Server酱 `/<SENDKEY>.send`、钉钉 `?access_token=`），整条 URL 上屏就是泄露；
/// 3. 点某一行按**族**回调（配置页的"先加载再进页、退出回存"逻辑留在 MainPage，不复制）；
/// 4. 首次进入弹一条 tip，且落 prefs 后不再弹。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  late AppChannelService appService;
  late WebhookService webhookService;
  late EmailService emailService;

  /// 保存链路可能自己生成/改写 id，所以 id 一律从服务侧回读，不在断言里硬抄
  String app1Id = 'app-1';
  String wh1Id = 'wh-1';
  final opened = <String>[];

  Widget buildApp() {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: ChannelStatusPage(
        onOpenChannel: (family) async => opened.add(family),
      ),
    );
  }

  Future<void> seedAll() async {
    await appService.saveChannels([
      {
        'id': 'app-1',
        'name': '办公',
        'appType': 'wecom_app',
        'baseUrl': 'https://qyapi.weixin.qq.com',
        'secret': 'app-secret-should-not-show',
        'config': <String, dynamic>{},
        'enabled': true,
      },
    ]);
    await webhookService.saveChannels([
      {
        'id': 'wh-1',
        'name': '告警群',
        'type': 'dingtalk',
        'url': 'https://oapi.dingtalk.com/robot/send?access_token=SECRET123',
        'enabled': true,
      },
    ]);
    app1Id = appService.channels.first['id'] as String;
    wh1Id = webhookService.channels.first['id'] as String;
    emailService.cachedChannels = [
      const EmailChannel(
        id: 'e1',
        name: '主邮箱',
        enabled: true,
        smtpHost: 'smtp.example.com',
        smtpPort: 465,
        username: 'u@example.com',
        fromEmail: 'u@example.com',
        toEmail: 'to@example.com',
      ),
    ];
  }

  setUp(() async {
    opened.clear();
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    // 见 base.md（53）（54）：testWidgets 里不接住原生通道，服务侧那一句
    // `await invokeMethod(...)` 永远不返回 ⇒ 整批用例 did not complete。
    stubNativeChannels();
    appService = AppChannelService(store: _FakeAppStore());
    webhookService = WebhookService(store: _FakeWebhookStore());
    emailService = EmailService(store: _FakeEmailStore());
    GetIt.instance.registerSingleton<AppChannelService>(appService);
    GetIt.instance.registerSingleton<WebhookService>(webhookService);
    GetIt.instance.registerSingleton<EmailService>(emailService);
    GetIt.instance.registerSingleton<ChannelHealthStore>(ChannelHealthStore());
  });

  tearDown(() async {
    clearNativeChannelStubs();
    await GetIt.instance.reset();
  });

  testWidgets('三族分组：族标题 + 每行的名字、类型、关键链接', (tester) async {
    tester.view.physicalSize = const Size(1200, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await seedAll();

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    for (final header in const ['Webhook', '邮件', '自建应用']) {
      expect(find.text(header), findsOneWidget, reason: '缺少族分组标题「$header」');
    }
    // 顺序也是契约：webhook → 邮件 → 自建应用
    double topOf(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(
      [topOf('Webhook'), topOf('邮件'), topOf('自建应用')],
      orderedEquals(<double>[topOf('Webhook'), topOf('邮件'), topOf('自建应用')]),
      reason: '族分组顺序变了就是页面结构变了',
    );
    expect(topOf('Webhook'), lessThan(topOf('邮件')));
    expect(topOf('邮件'), lessThan(topOf('自建应用')));

    expect(find.text('告警群'), findsOneWidget);
    expect(find.text('主邮箱'), findsOneWidget);
    expect(find.text('办公'), findsOneWidget);
    // 关键链接（脱敏后）与探测时间同行显示
    expect(find.textContaining('oapi.dingtalk.com'), findsOneWidget);
    expect(find.textContaining('smtp.example.com:465'), findsOneWidget);
    expect(find.textContaining('从未探测'), findsWidgets);
  });

  testWidgets('凭据不得上屏：URL 的 path 与 query、密钥都不出现', (tester) async {
    tester.view.physicalSize = const Size(1200, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await seedAll();

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    final onScreen = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' | ');
    expect(onScreen, isNot(contains('SECRET123')));
    expect(onScreen, isNot(contains('access_token')));
    expect(onScreen, isNot(contains('/robot/send')));
    expect(onScreen, isNot(contains('app-secret-should-not-show')));
  });

  testWidgets('点某行按族回调', (tester) async {
    tester.view.physicalSize = const Size(1200, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await seedAll();

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('channel-status-webhook-$wh1Id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('channel-status-email-e1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('channel-status-app-$app1Id')));
    await tester.pumpAndSettle();

    expect(opened, ['webhook', 'email', 'app']);
  });

  testWidgets('首次进入弹 tip，第二次不再弹（prefs 记账）', (tester) async {
    tester.view.physicalSize = const Size(1200, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await seedAll();

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('点任意一条可直接进入它的配置页'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('channel_status_guide_seen'), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(
      find.textContaining('点任意一条可直接进入它的配置页'),
      findsNothing,
      reason: '每次都弹就成了打扰，"只提示一次"靠的就是那个 prefs 键',
    );
  });

  testWidgets('探测过的通道显示时效与状态；没启用的不出现', (tester) async {
    tester.view.physicalSize = const Size(1200, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await seedAll();
    await GetIt.instance<ChannelHealthStore>().record(
      'webhook',
      'wh-1',
      reachable: false,
      latencyMs: 1200,
    );

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('状态异常'), findsOneWidget);
    expect(find.textContaining('分钟前探测'), findsOneWidget);
    expect(find.text('状态正常'), findsNothing);

    // 关掉一条 → 不再列它（与首页同一判据：enabled != true 就出局）
    // 关掉一条 → 再走一次"进配置页再回来"的回路，它就该消失。
    // ⚠ 必须是**回调返回之后**才重取：本页在 build 时现取 collectActiveChannels，
    // 没有订阅服务，所以只在返回点刷新 —— 这正是 _open() 里 setState 的职责。
    await appService.saveChannels([
      {
        'id': 'app-1',
        'name': '办公',
        'appType': 'wecom_app',
        'baseUrl': 'https://qyapi.weixin.qq.com',
        'config': <String, dynamic>{},
        'enabled': false,
      },
    ]);
    await tester.tap(find.byKey(const ValueKey('channel-status-email-e1')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('channel-status-app-$app1Id')),
      findsNothing,
      reason: '从配置页回来没有重取数据（禁用后仍显示）',
    );
  });
  group('T11 主备角色', () {
    testWidgets('弹层里改成备用 → 服务落库、页面徽标跟着变', (tester) async {
      tester.view.physicalSize = const Size(1200, 2800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await seedAll();

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      // 新库没写过 role → 一律"主"（老语义：全量推）
      expect(find.text('主'), findsNWidgets(3));
      final whId = webhookService.channels.first['id'] as String;

      await tester.tap(find.byKey(const ValueKey('channel-status-open-roles')));
      await tester.pumpAndSettle();
      expect(find.textContaining('仅当所有主通道都不可用时'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('role-picker-webhook-$whId')),
          matching: find.text('备'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        webhookService.channels.first['role'],
        'backup',
        reason: '改了没落库 = 重启设置就丢',
      );
      // 点遮罩关掉弹层（BottomSheet 默认可点外关闭），再看页面徽标
      await tester.tapAt(const Offset(6, 6));
      await tester.pumpAndSettle();

      expect(find.text('备'), findsOneWidget);
      expect(find.text('主'), findsNWidgets(2));
    });

    testWidgets('主通道超过 5 条只提示、不阻止保存', (tester) async {
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await appService.saveChannels([
        for (var i = 0; i < 6; i++)
          {
            'id': 'app-$i',
            'name': '应用$i',
            'appType': 'wecom_app',
            'baseUrl': 'https://qyapi.weixin.qq.com',
            'config': <String, dynamic>{},
            'enabled': true,
          },
      ]);

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      expect(find.text('主'), findsNWidgets(6), reason: '全部默认主通道');

      await tester.tap(find.byKey(const ValueKey('channel-status-open-roles')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('建议不超过 5 条'),
        findsOneWidget,
        reason: '超过推荐值要给提示（但不设硬上限）',
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

class _FakeEmailStore implements EmailChannelStore {
  List<Map<String, dynamic>> rows = [];

  @override
  Future<List<Map<String, dynamic>>> getEmailChannels() async => rows;

  @override
  Future<void> saveEmailChannels(List<Map<String, dynamic>> channels) async {
    rows = channels.map(Map<String, dynamic>.from).toList();
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
