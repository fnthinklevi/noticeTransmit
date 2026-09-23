import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/webhook_settings_page.dart';
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
    registerChannelDescriptorService();
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
      await tester.pumpAndSettle();
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
          await t.pumpAndSettle();
        },
      );
      expect(saved, hasLength(1));
      expect(saved!.single['id'], 'b', reason: '按下标取 id 会拿到被删掉的 a');
      expect(saved.single['url'], 'https://b.example.com/hook');
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
}
