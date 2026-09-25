import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/widgets/card_action_sheet.dart';
import 'package:notice_transmit/pages/webhook_settings_page.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/channel_descriptor_fixtures.dart';

/// Webhook 通道设置页「行下标 ↔ 通道」对应关系的回归测试。
///
/// 页面的表单状态是**一堆并行列表**（controllers / enabled / types / ids），
/// 行增删只对它们同步 `add`/`removeAt`；而 `widget.webhookChannels` 是构造期输入，
/// **不会随行增删收缩**。任何按下标读它的地方都会长歪：
/// - 新增一行 → 下标越界，`widget.webhookChannels[index]` 直接抛 RangeError；
/// - 删掉一行 → 其余行读到上一条通道的数据（徽标串台、保存继承错 id）。
/// 曾经的健康徽标就是这样（零通道进入页面即崩，因为 initState 会补一个空行）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannelName = 'com.fnthink.notice/notification';
  final now = DateTime.now().millisecondsSinceEpoch;

  /// false = 原生描述符拉不到（装配失败 / 旧 App 配新原生）
  var serveDescriptors = true;

  /// Telegram：URL 里带 chat_id，类型走**自动识别**，用来证明按 host 探测出的类型
  /// 也走描述符（secretUsed=false ⇒ 密钥输入框不出现）。
  List<Map<String, dynamic>> oneTelegram() => [
    {
      'id': 'tg',
      'name': 'TG',
      'url': 'https://api.telegram.org/bot12345:secret-abc/sendMessage',
      'type': 'telegram',
      'channelType': 'auto',
      'enabled': true,
      'message_format': 'default',
    },
  ];

  Map<String, Object> healthPrefs() => {
    // a 不可达 / b 可达 7ms。probedAt 取"刚刚"，避免进入页面就触发
    // 6 小时过期后台探测（探测会覆盖缓存，让断言前提失效）。
    'channel_health_a': jsonEncode({
      'reachable': false,
      'latencyMs': 0,
      'httpCode': 0,
      'probedAt': now,
    }),
    'channel_health_b': jsonEncode({
      'reachable': true,
      'latencyMs': 7,
      'httpCode': 200,
      'probedAt': now,
    }),
  };

  /// 一条已保存的钉钉通道（形状 = 服务归一化后交给页面的样子）。
  List<Map<String, dynamic>> oneDingTalk() => [
    {
      'id': 'dt',
      'name': '钉钉A',
      'url': 'https://oapi.dingtalk.com/robot/send?access_token=a',
      'channelType': 'dingtalk',
      'type': 'dingtalk',
      'enabled': true,
      'secret': 'sec-a',
      'message_format': 'default',
      'message_template': null,
    },
  ];

  List<Map<String, dynamic>> twoChannels() => [
    {
      'id': 'a',
      'name': '通道A',
      'url': 'https://a.example.com/hook',
      'type': 'wechat_work',
      'channelType': 'wechat_work',
      'enabled': true,
      'message_format': 'default',
    },
    {
      'id': 'b',
      'name': '通道B',
      'url': 'https://b.example.com/hook',
      'type': 'generic',
      'channelType': 'generic',
      'enabled': true,
      'message_format': 'default',
    },
  ];

  /// 直接把页面当 home：`_saveAndBack` 的返回值要用 [pushAndSave] 才拿得到。
  Future<void> openDirectly(
    WidgetTester tester,
    List<Map<String, dynamic>> channels,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: WebhookSettingsPage(webhookChannels: channels),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// push 页面 → 执行 [interact] → 点保存 → 返回 pop 出来的通道列表。
  Future<List<Map<String, dynamic>>?> pushAndSave(
    WidgetTester tester,
    List<Map<String, dynamic>> channels, {
    Future<void> Function(WidgetTester tester)? interact,
  }) async {
    List<Map<String, dynamic>>? popped;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await Navigator.push<List<Map<String, dynamic>>>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      WebhookSettingsPage(webhookChannels: channels),
                ),
              );
            },
            child: const Text('go-settings'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go-settings'));
    await tester.pumpAndSettle();
    if (interact != null) await interact(tester);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    return popped;
  }

  setUp(() {
    serveDescriptors = true;
    SharedPreferences.setMockInitialValues(healthPrefs());
    registerChannelPageServices();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(methodChannelName), (
          call,
        ) async {
          if (call.method == 'probeChannelHealth') {
            return {'reachable': true, 'latencyMs': 42, 'httpCode': 200};
          }
          if (call.method == 'getChannelDescriptors') {
            return serveDescriptors ? descriptorCallResponse(call) : null;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(methodChannelName), null);
  });

  /// 删除一律先二次确认（T06 的单一咽喉在执行删除的那个函数里）。
  /// 这条 helper 本身就是守卫：没有确认框 ⇒ 它当场红。
  Future<void> confirmDelete(WidgetTester t) async {
    await t.pumpAndSettle();
    final dialog = find.widgetWithText(TextButton, '删除');
    expect(
      dialog,
      findsWidgets,
      reason: '点红叉就直接删 ⇒ T06 的二次确认被绕开（凭据重填一次的成本远高于确认一下）',
    );
    await t.tap(dialog.last);
    await t.pumpAndSettle();
  }

  group('WebhookSettingsPage – 行与通道的对应', () {
    testWidgets('零通道进入不崩溃（补出来的空行没有可对应的输入通道）', (tester) async {
      await openDirectly(tester, const []);
      expect(tester.takeException(), isNull);
      // initState 会补一行空表单，页面照常可编辑
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('新增一行后仍可渲染，且新行不继承别人的健康徽标', (tester) async {
      // 两条通道的表单已经高出默认视口，「+ 添加通道」在折叠区下方，
      // 直接 tap 会命中屏幕外的中心点（Flutter 警告 hit test 落空）。
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await openDirectly(tester, twoChannels());
      expect(find.text('连接失败'), findsOneWidget);
      expect(find.text('连通 · 7 ms'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: '越界读 widget.webhookChannels',
      );
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(3));
      // 新增行没有 id ⇒ 没有健康记录，徽标数量不变
      expect(find.text('连接失败'), findsOneWidget);
      expect(find.text('连通 · 7 ms'), findsOneWidget);
    });

    testWidgets('删掉首行后，徽标跟着自己的通道走（不继承被删通道的状态）', (tester) async {
      await openDirectly(tester, twoChannels());
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await confirmDelete(tester);
      expect(tester.takeException(), isNull);

      // 剩下的这一行是通道 B：可达 7ms；A 的"连接失败"不得出现在它头上
      expect(find.text('连通 · 7 ms'), findsOneWidget);
      expect(find.text('连接失败'), findsNothing);
      final nameField = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller?.text ?? '')
          .toList();
      expect(nameField, contains('通道B'));
    });

    testWidgets('保存：行保留自己的 id，删过的行不复活', (tester) async {
      final saved = await pushAndSave(tester, twoChannels());
      expect(saved, hasLength(2));
      expect(saved!.map((c) => c['id']), ['a', 'b']);
      expect(saved.map((c) => c['url']), [
        'https://a.example.com/hook',
        'https://b.example.com/hook',
      ]);
    });

    testWidgets('删首行后保存：剩下那条拿的是自己的 id', (tester) async {
      final saved = await pushAndSave(
        tester,
        twoChannels(),
        interact: (t) async {
          await t.tap(find.byIcon(Icons.delete_outline).first);
          await confirmDelete(t);
        },
      );
      expect(saved, hasLength(1));
      expect(saved!.single['id'], 'b', reason: '按下标取 id 会拿到被删掉的 a');
      expect(saved.single['url'], 'https://b.example.com/hook');
    });

    testWidgets('已有 1 条时新增一行并保存，两条都必须在结果里', (tester) async {
      // 模拟器闸门（6.7）在"第二条"这一步发现结果里只剩新加的那条，
      // 老那条不见了 ⇒ 这是数据级丢失，必须有用例钉住（快、可离线跑）。
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final saved = await pushAndSave(
        tester,
        oneDingTalk(),
        interact: (t) async {
          await t.tap(find.byIcon(Icons.add_circle_outline));
          await t.pumpAndSettle();
          // 新行的 URL 框 = 唯一"占位是 URL 且内容为空"的那个。
          // ⚠ 不能按占位文案是否可见来找：Material 会把 hintText 留成浮动标签，
          // 已填过的那一行同样命中 ⇒ 会覆盖掉已有通道。
          final urlField = find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                w.decoration?.hintText == 'https://example.com/webhook' &&
                (w.controller?.text ?? '').isEmpty,
          );
          expect(urlField, findsOneWidget, reason: '新行没建出来');
          await t.enterText(urlField, 'https://b.example.com/hook');
          await t.pumpAndSettle();
        },
      );
      expect(saved, hasLength(2), reason: '新增一行后保存，原有那条被吞了（数据丢失）');
      // 原有那条必须带着自己的 id 与地址活着；新行没有 id（保存时由 DB 侧生成）
      expect(saved!.map((c) => c['url']).toList(), [
        'https://oapi.dingtalk.com/robot/send?access_token=a',
        'https://b.example.com/hook',
      ]);
      expect(saved.first['id'], 'dt');
    });

    testWidgets('保存的通道不再携带恒为 null 的 extra_config 假字段', (tester) async {
      final saved = await pushAndSave(tester, twoChannels());
      for (final row in saved!) {
        // 此前页面声明了 `Map? extraConfig;` 却从不赋值，只是把 null 传下去；
        // webhook 的扩展配置没有任何输入框（企微自建应用已迁到 app_channels 表），
        // 假字段留着，下一个改这里的人会以为"这里有扩展配置"。
        expect(row.containsKey('extra_config'), isFalse);
      }
    });
  });

  // ===== 描述符驱动显隐（第 5 步）=====
  group('WebhookSettingsPage – 显隐按原生能力位', () {
    testWidgets('Telegram 无凭据形态 ⇒ 不渲染 secret 输入框（此前是页面黑名单）', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await openDirectly(tester, oneTelegram());

      expect(find.text('签名密钥（可选）'), findsNothing);
      // 只剩 URL + 名称两个输入框
      expect(find.byType(TextField), findsNWidgets(2));
      // 且识别提示确实按 telegram 显示（不是 generic）
      expect(find.text('自动识别（Telegram）'), findsOneWidget);
    });

    testWidgets('Gotify 的实发正文不吃自定义格式 ⇒ 格式与模板入口一起收掉', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await openDirectly(tester, [
        {
          'id': 'g',
          'name': 'G',
          'url': 'https://gotify.example.com/message',
          'type': 'gotify',
          'channelType': 'gotify',
          'enabled': true,
          'message_format': 'default',
        },
      ]);

      expect(find.text('消息格式'), findsNothing);
      expect(find.text('推送模板（可选）'), findsNothing);
      // Gotify 的 secret 是必填应用 Token ⇒ 密钥区要在
      expect(find.text('签名密钥（可选）'), findsOneWidget);
    });

    testWidgets('企微 webhook 有签名 ⇒ 密钥区在、格式选择器也在', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await openDirectly(tester, [
        {
          'id': 'w',
          'name': 'W',
          'url': 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=abc',
          'type': 'wechat_work',
          'channelType': 'wechat_work',
          'enabled': true,
          'message_format': 'default',
        },
      ]);

      expect(find.text('签名密钥（可选）'), findsOneWidget);
      expect(find.text('消息格式'), findsOneWidget);
    });

    testWidgets('每家的「URL 识别」说明用自己的文案（roadmap E8 的行为锁）', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await openDirectly(tester, [
        {
          'id': 'dt',
          'name': 'DT',
          'url': 'https://oapi.dingtalk.com/robot/send?access_token=x',
          'type': 'dingtalk',
          'channelType': 'dingtalk',
          'enabled': true,
          'message_format': 'default',
        },
        {
          'id': 'fs',
          'name': 'FS',
          'url': 'https://open.feishu.cn/open-apis/bot/v2/hook/x',
          'type': 'feishu',
          'channelType': 'feishu',
          'enabled': true,
          'message_format': 'default',
        },
      ]);

      expect(find.text('URL 加签（timestamp+sign），正文可发 Markdown'), findsOneWidget);
      expect(
        find.textContaining('正文按纯文本发送，Markdown 会降级'),
        findsOneWidget,
        reason: '飞书恒发 msg_type=text，说明里必须体现（页面另有降级提示条）',
      );
      expect(
        find.text('文本格式推送'),
        findsNothing,
        reason: '这句是企微的；钉钉/飞书借用它 = E8 那个文案缺陷',
      );
    });

    testWidgets('URL 缺 scheme 时保存被拦下并点名行号（不再静默存进 DB）', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await openDirectly(tester, const []);

      // 卡片里第一个输入框是「通道名称」，第二个才是 URL（不是直觉上第一个）
      final urlField = find.byType(TextField).at(1);
      await tester.enterText(urlField, 'ntfy.sh/topic');
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      // ⚠ 用 pump 而不是 pumpAndSettle：SnackBar 有 2s 自动收起计时，
      //   pumpAndSettle 会把计时器跑完 → 断言时条已经消失（不是没弹）。
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('第 1 行的 URL 必须是 http(s):// 开头'),
        findsOneWidget,
      );
      expect(
        find.byType(WebhookSettingsPage),
        findsOneWidget,
        reason: '校验没过就不该 pop（保存会连带写库，非法 URL 就此静默落地）',
      );

      // 局域网 http 自建端点必须能存：原生两处规则都接受 http
      await tester.enterText(urlField, 'http://ntfy.lan:8080/topic');
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(WebhookSettingsPage), findsNothing);
    });

    testWidgets('描述符拉不到时不收入口（宁可多给，不能让凭据没地方填）', (tester) async {
      serveDescriptors = false;
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await openDirectly(tester, oneTelegram());

      expect(find.text('签名密钥（可选）'), findsOneWidget);
      expect(find.text('消息格式'), findsOneWidget);
    });
  });

  group('备份/DB 形状的行不得打死页面（㊹）', () {
    testWidgets(
      'enabled 是 0/1、类型只有 snake_case、secret 是 "null"、还带旧 extra_config',
      (tester) async {
        // 维护者实测：备份后重新导入，webhook 设置页打不开。
        // 页面 initState 原先对这些值做 `as bool?` / `as String?` 硬转型 —— 备份文件里的形状
        // 不受我们控制（旧版本、DB 行漏进 UI、手改过的文件），一个 int 就足以让整个页面抛异常。
        tester.view.physicalSize = const Size(1200, 3600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await openDirectly(tester, [
          {
            'id': 'a',
            'name': '钉钉',
            'url': 'https://oapi.dingtalk.com/robot/send?access_token=x',
            'channel_type': 'dingtalk',
            'enabled': 1,
            'secret': 'null',
            'message_format': null,
            'message_template': 'null',
            'extra_config': {'corpid': 'legacy'},
          },
        ]);

        expect(tester.takeException(), isNull, reason: '备份形状的行把页面打死了');
        expect(find.text('钉钉'), findsOneWidget);
        // 值被按语义读出来：1 ⇒ 启用、"null" ⇒ 视为未配置密钥
        final switchFinder = find.byType(CupertinoSwitch);
        expect(switchFinder, findsWidgets);
        expect(
          tester.widget<CupertinoSwitch>(switchFinder.first).value,
          isTrue,
          reason: 'enabled:1 必须读成启用，而不是静默变关',
        );
        // 钉钉本来就要签名字段（secretUsed），所以字段在；关键是字符串 "null" 没漏进任何输入框
        final texts = tester
            .widgetList<TextField>(find.byType(TextField))
            .map((t) => t.controller?.text ?? '')
            .toList();
        expect(
          texts,
          isNot(contains('null')),
          reason: '"null" 脏数据必须被洗成未配置，否则被当成已配置密钥/模板',
        );
      },
    );

    testWidgets('值缺键/为数字 id 也不崩（id 用 toString 兜住）', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await openDirectly(tester, [
        {'url': 'https://ntfy.sh/topic', 'id': 7},
      ]);
      expect(tester.takeException(), isNull);
      // 没有 channelType/type ⇒ 按 host 自动识别，页面仍可编辑
      expect(find.byType(TextField), findsWidgets);
    });
  });

  // T03：必填缺失一律"点名 + 阻止保存"。判据不在本页另立：
  // 空 URL 的行原本会在保存时被静默丢弃（原生也 filter 掉它），用户敲过的名字与
  // 密钥跟着没了；`secretRequired` 平台缺凭据则要到发送时才被服务端拒收。
  // T06：删除一律二次确认，且确认之后要把健康记录一起清掉。
  group('WebhookSettingsPage – 删除要确认（T06）', () {
    testWidgets('点「取消」⇒ 行与徽标都还在（确认框不许顺手改数据）', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await openDirectly(tester, twoChannels());
      expect(find.text('连通 · 7 ms'), findsOneWidget, reason: '前提：通道 B 有徽标');

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消').last);
      await tester.pumpAndSettle();

      expect(
        GetIt.instance<ChannelHealthStore>().of('webhook', 'a'),
        isNotNull,
        reason: '取消却清了缓存 ⇒ 用户反悔了，首页的异常标记却回不来',
      );
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
    });

    testWidgets('确认后除了收起这一行，还要清掉它的健康记录', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await openDirectly(tester, twoChannels());
      final health = GetIt.instance<ChannelHealthStore>();
      expect(health.of('webhook', 'a'), isNotNull, reason: '前提：a 有"连接失败"记录');

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await confirmDelete(tester);

      expect(
        health.of('webhook', 'a'),
        isNull,
        reason: '记录留着，日后 id 复用（从旧备份恢复）时徽标会复活成上一条通道的状态',
      );
      expect(health.of('webhook', 'b'), isNotNull, reason: '只能清被删那条');
    });
  });

  group('WebhookSettingsPage – 必填缺失要点名（T03）', () {
    Future<void> openWith(
      WidgetTester tester,
      List<Map<String, dynamic>> rows,
    ) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await openDirectly(tester, rows);
    }

    testWidgets('填了名字却没填 URL ⇒ 点名这一行，且不许 pop（否则用户的编辑会被丢掉）', (tester) async {
      await openWith(tester, const []);
      // 卡片里第一个输入框是「通道名称」，第二个才是 URL
      await tester.enterText(find.byType(TextField).at(0), '告警群');
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('第 1 行没填 Webhook 地址'),
        findsOneWidget,
        reason: '只说"保存失败"等于让用户自己找是哪一行、缺什么',
      );
      expect(find.byType(WebhookSettingsPage), findsOneWidget);
    });

    testWidgets('整行确实空白 ⇒ 仍按原行为放弃这行，不算错误', (tester) async {
      await openWith(tester, const []);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.byType(WebhookSettingsPage), findsNothing);
    });

    testWidgets('Gotify 缺应用 Token ⇒ 阻止并点名；补上后放行', (tester) async {
      await openWith(tester, [
        {
          'id': 'gt',
          'name': '本机 Gotify',
          'url': 'http://push.example.com/message',
          'channelType': 'gotify',
          'type': 'gotify',
          'enabled': true,
          'message_format': 'default',
        },
      ]);
      await tester.tap(find.text('保存'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('第 1 行缺这个平台必需的凭据'), findsOneWidget);
      expect(find.byType(WebhookSettingsPage), findsOneWidget);

      // 第三个输入框是签名密钥/Token（前两个是名称与 URL）
      await tester.enterText(find.byType(TextField).at(2), 'A1B2C3D4E5');
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(WebhookSettingsPage), findsNothing);
    });

    testWidgets('描述符拉不到时不得凭猜测拦保存（没有元数据就放行）', (tester) async {
      serveDescriptors = false;
      await openWith(tester, [
        {
          'id': 'gt',
          'name': '本机 Gotify',
          'url': 'http://push.example.com/message',
          'channelType': 'gotify',
          'type': 'gotify',
          'enabled': true,
          'message_format': 'default',
        },
      ]);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(
        find.byType(WebhookSettingsPage),
        findsNothing,
        reason: 'URL 合法、只是读不到描述符 ⇒ 这时拦人保存是无据可依的猜测',
      );
    });
  });

  // T04：「仅测试」与保存是两个动作，且测试结论必须落到健康单点 ——
  // 否则测出来的失败只活在这一屏，首页与通道状态页永远说不出这条通道的状态。
  group('WebhookSettingsPage – 仅测试（T04）', () {
    void stubTest({required bool success, required List<String> calls}) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(methodChannelName), (
            call,
          ) async {
            calls.add(call.method);
            if (call.method == 'testWebhook') {
              return {
                'success': success,
                'message': success ? 'ok' : 'HTTP 401 未授权',
              };
            }
            if (call.method == 'getChannelDescriptors') {
              return serveDescriptors ? descriptorCallResponse(call) : null;
            }
            if (call.method == 'probeChannelHealth') {
              return {'reachable': true, 'latencyMs': 42, 'httpCode': 200};
            }
            return null;
          });
    }

    Future<void> openBig(
      WidgetTester tester,
      List<Map<String, dynamic>> rows,
    ) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await openDirectly(tester, rows);
    }

    testWidgets('测出失败也要记进单点，但绝不 pop（pop 才是保存）', (tester) async {
      final calls = <String>[];
      stubTest(success: false, calls: calls);
      final health = GetIt.instance<ChannelHealthStore>();
      // 前提写成一条"刚刚探测过、且是绿的"记录：stale 才会触发进页后台探测，
      // 不压掉它，本用例会和异步探测抢同一条记录（断言变成看时序）。
      await health.record('webhook', 'dt', reachable: true, latencyMs: 5);
      await openBig(tester, oneDingTalk());
      expect(health.of('webhook', 'dt')?.reachable, isTrue);

      calls.clear();
      await tester.tap(find.widgetWithText(TextButton, '仅测试'));
      await tester.pumpAndSettle();

      expect(calls, contains('testWebhook'));
      expect(
        find.byType(WebhookSettingsPage),
        findsOneWidget,
        reason: '「仅测试」按定义不落库：本页的保存动作就是 pop 把通道交回上层写库',
      );
      expect(
        health.of('webhook', 'dt')?.reachable,
        isFalse,
        reason: '手动测试盖不掉旧的绿 ⇒ 首页与通道状态页还在说"正常"，异常冒不上去',
      );
    });

    testWidgets('新增行（保存前没有 id）测了但不记账', (tester) async {
      final calls = <String>[];
      stubTest(success: true, calls: calls);
      await openBig(tester, const []);
      final prefs = await SharedPreferences.getInstance();
      List<String> healthKeys() =>
          prefs.getKeys().where((k) => k.startsWith('channel_health_')).toList()
            ..sort();
      final before = healthKeys();

      await tester.enterText(
        find.byType(TextField).at(1),
        'https://ntfy.sh/topic',
      );
      await tester.pumpAndSettle();
      calls.clear();
      await tester.tap(find.widgetWithText(TextButton, '仅测试'));
      await tester.pumpAndSettle();

      expect(
        calls,
        contains('testWebhook'),
        reason: '这一行确实要被测到，否则「仅测试」对新行就是空按钮',
      );
      expect(
        healthKeys(),
        before,
        reason: '没有归属的记账比不记更糟：空 id 写进去，下一条复用该位置的通道会继承这枚徽标',
      );
    });

    testWidgets('整页一行 URL 都没填 ⇒ 不假装测过，直接说要填什么', (tester) async {
      final calls = <String>[];
      stubTest(success: true, calls: calls);
      await openBig(tester, const []);
      calls.clear();

      await tester.tap(find.widgetWithText(TextButton, '仅测试'));
      await tester.pumpAndSettle();

      expect(calls, isNot(contains('testWebhook')));
      expect(find.textContaining('请先输入 Webhook URL'), findsOneWidget);
      expect(find.byType(WebhookSettingsPage), findsOneWidget);
    });
  });

  // T05：长按标题行的动作表。
  group('WebhookSettingsPage – 长按菜单（T05）', () {
    Finder inSheet(String label) => find.descendant(
      of: find.byType(CardActionSheet),
      matching: find.text(label),
    );

    testWidgets('复制出的新行**不带被复制那条的 id**（徽标归属不能跟着复制）', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final popped = await pushAndSave(
        tester,
        oneDingTalk(),
        interact: (t) async {
          await t.longPress(find.byKey(const ValueKey('webhook-row-menu-0')));
          await t.pumpAndSettle();
          expect(inSheet('复制'), findsOneWidget);
          await t.tap(inSheet('复制'));
          await t.pumpAndSettle();
        },
      );
      expect(popped, hasLength(2));
      expect(popped![0]['id'], 'dt');
      expect(
        popped[1]['id'],
        isNot('dt'),
        reason: '两条同 id ⇒ 保存走 delete+insert 时徽标与送达归属整体串台（本页面犯过）',
      );
      expect(
        popped[1]['url'],
        popped[0]['url'],
        reason: '复制的意义就是不用再粘一遍地址（含凭据 query）',
      );
    });

    testWidgets('只剩一行时「删除」置灰，而不是把入口藏掉', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await openDirectly(tester, oneDingTalk());
      await tester.longPress(find.byKey(const ValueKey('webhook-row-menu-0')));
      await tester.pumpAndSettle();

      final tile = tester.widget<ListTile>(
        find.ancestor(of: inSheet('删除'), matching: find.byType(ListTile)),
      );
      expect(
        tile.enabled,
        isFalse,
        reason: '与卡片上删除按钮的显隐条件同一口径：最后一行不许删；置灰才看得出"有这条路但当前不通"',
      );
    });
  });
}
