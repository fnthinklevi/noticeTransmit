import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/pages/webhook_settings_page.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/services/webhook_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/channel_descriptor_fixtures.dart';
import '../test_setup.dart';

/// Webhook **单通道详情页**（T07-B 之前这里是全量平铺编辑器）。
///
/// 钉住的三件事各有其历史原因：
/// 1. **显隐按原生能力位**（`usesSecretField` / `supportsCustomTemplate`）：以前页面
///    自带一份「排除 6 个平台」黑名单，原生加了签名方案这边不会跟着变，
///    表现就是"能签名却没地方填密钥"。
/// 2. **必填缺失点名到字段并阻止保存**（T03）：空 URL 的通道原本会在保存时被静默丢掉，
///    用户敲过的名字与密钥跟着没了。
/// 3. **保存只写这一条**（T07-B 的存在理由）：以前整表由页面攥着快照重写，
///    "只想改一条"会把别的通道一起覆盖。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeWebhookStore store;
  late WebhookService service;
  late ChannelHealthStore health;

  /// 原生描述符拉不到（装配失败 / 旧 App 配新原生）
  var serveDescriptors = true;
  final calls = <String>[];

  /// 最近一次 `testWebhook` 的参数（页面交给原生的字面量就在这里）。
  Map<dynamic, dynamic>? lastTestArgs;

  /// testWebhook 的答复，逐条用例可改
  var testSucceeds = true;

  /// 改写原生载荷里的档位名单（null = 用导出快照原样）。T08-B 用它证明名单真的来自载荷。
  List<String>? formatsOverride;

  Map<String, Object?> descriptorsPayload(List<String> formats) => {
    ...descriptorCallResponse(const MethodCall('getChannelDescriptors'))
        as Map<String, Object?>,
    'messageFormats': formats,
  };

  Map<String, dynamic> uiRow(
    String id,
    String name,
    String url,
    String type, {
    bool enabled = true,
    String? secret,
    String format = 'default',
    String? template,
  }) => {
    'id': id,
    'name': name,
    'url': url,
    'channelType': type,
    'type': type,
    'enabled': enabled,
    'secret': secret,
    'message_format': format,
    'message_template': template,
  };

  /// 打开某条通道的详情页（服务里得先有那条 —— 页面按 id 从 `service.channels` 取）。
  Future<void> openDetail(
    WidgetTester tester,
    List<Map<String, dynamic>> rows, {
    String? channelId,
  }) async {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await service.saveChannels(rows);
    store.savedBatches.clear();
    calls.clear();
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: WebhookSettingsPage(channelId: channelId),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 卡片里的输入框按出现顺序：0 名称、1 URL、2 密钥（显示时）、3 模板（格式≠默认时）。
  Finder fieldAt(int i) => find.byType(TextField).at(i);

  Map<String, dynamic> saved(String id) =>
      service.channels.firstWhere((c) => c['id'] == id);

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('测试并保存'));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    serveDescriptors = true;
    testSucceeds = true;
    formatsOverride = null;
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    // ⚠ 桩**两个**原生通道：`WebhookService._syncToNative` 先走 flutter_secure_storage，
    // 只桩 notification 会让 widget 测试里的 await 永远不返回。
    stubNativeChannels(
      onCall: (call) async {
        calls.add(call.method);
        if (call.method == 'testWebhook') lastTestArgs = call.arguments;
        if (call.method == 'getChannelDescriptors') {
          if (!serveDescriptors) return null;
          final override = formatsOverride;
          return override == null
              ? descriptorCallResponse(call)
              : descriptorsPayload(override);
        }
        if (call.method == 'testWebhook') {
          return {
            'success': testSucceeds,
            'message': testSucceeds ? 'ok' : 'HTTP 401 未授权',
            'signed': false,
          };
        }
        if (call.method == 'probeChannelHealth') {
          return {'reachable': true, 'latencyMs': 42, 'httpCode': 200};
        }
        return null;
      },
    );
    store = _FakeWebhookStore();
    service = WebhookService(store: store);
    GetIt.instance.allowReassignment = true;
    if (GetIt.instance.isRegistered<WebhookService>()) {
      GetIt.instance.unregister<WebhookService>();
    }
    GetIt.instance.registerLazySingleton<WebhookService>(() => service);
    registerChannelPageServices();
    health = GetIt.instance<ChannelHealthStore>();
    await health.load();
  });

  tearDown(() {
    clearNativeChannelStubs();
    GetIt.instance.reset();
  });

  group('详情页 – 显隐按原生能力位', () {
    testWidgets('Telegram 无凭据形态 ⇒ 不渲染 secret 输入框（此前是页面黑名单）', (tester) async {
      await openDetail(tester, [
        uiRow(
          'tg',
          'TG',
          'https://api.telegram.org/bot12345:secret-abc/sendMessage',
          'auto',
        ),
      ], channelId: 'tg');

      expect(find.text('签名密钥（可选）'), findsNothing);
      // 只剩 URL + 名称两个输入框
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('自动识别（Telegram）'), findsOneWidget);
    });

    testWidgets('Gotify 的实发正文不吃自定义格式 ⇒ 格式与模板入口一起收掉', (tester) async {
      await openDetail(tester, [
        uiRow(
          'g',
          'G',
          'https://gotify.example.com/message',
          'gotify',
          secret: 'app-token',
        ),
      ], channelId: 'g');

      expect(find.text('消息格式'), findsNothing);
      expect(find.text('推送模板（可选）'), findsNothing);
      // Gotify 的 secret 是必填应用 Token ⇒ 密钥区要在
      expect(find.text('签名密钥（可选）'), findsOneWidget);
    });

    testWidgets('企微 webhook 有签名 ⇒ 密钥区在、格式选择器也在', (tester) async {
      await openDetail(tester, [
        uiRow(
          'w',
          'W',
          'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=abc',
          'wechat_work',
        ),
      ], channelId: 'w');

      expect(find.text('签名密钥（可选）'), findsOneWidget);
      expect(find.text('消息格式'), findsOneWidget);
    });

    testWidgets('钉钉的 URL 识别说明用自己的文案（roadmap E8 的行为锁）', (tester) async {
      await openDetail(tester, [
        uiRow(
          'dt',
          'DT',
          'https://oapi.dingtalk.com/robot/send?access_token=x',
          'dingtalk',
        ),
      ], channelId: 'dt');
      expect(find.text('URL 加签（timestamp+sign），正文可发 Markdown'), findsOneWidget);
      expect(
        find.text('文本格式推送'),
        findsNothing,
        reason: '这句是企微的；钉钉借用它 = E8 那个文案缺陷',
      );
    });

    testWidgets('飞书的说明体现"恒发纯文本、markdown 会降级"', (tester) async {
      await openDetail(tester, [
        uiRow(
          'fs',
          'FS',
          'https://open.feishu.cn/open-apis/bot/v2/hook/x',
          'feishu',
        ),
      ], channelId: 'fs');
      expect(
        find.textContaining('正文按纯文本发送，Markdown 会降级'),
        findsOneWidget,
        reason: '飞书恒发 msg_type=text，说明里必须体现（页面另有降级提示条）',
      );
      expect(
        find.text('文本格式推送'),
        findsNothing,
        reason: '这句是企微的；飞书借用它 = E8 那个文案缺陷',
      );
    });

    testWidgets('描述符拉不到时不收入口（宁可多给，不能让凭据没地方填）', (tester) async {
      serveDescriptors = false;
      await openDetail(tester, [
        uiRow(
          'tg',
          'TG',
          'https://api.telegram.org/bot12345:secret-abc/sendMessage',
          'auto',
        ),
      ], channelId: 'tg');

      expect(find.text('签名密钥（可选）'), findsOneWidget);
      expect(find.text('消息格式'), findsOneWidget);
    });
  });

  group('详情页 – 选择通道类型（T90 片23）', () {
    Map<String, dynamic> tele(String id, String type) =>
        uiRow(id, id.toUpperCase(), 'https://example.com/hook', type);

    /// 开那一枚选择器。那一格是一个**无标签**的 （只有展示文案 + 一颗尖角），
    /// 文案还会跟着 URL 探测结果变（「自动识别」 / 「自动识别（某某）」）
    /// ⇒ 按文案点不稳，按尖角那颗图标才是稳的（全页只有那一枚尖角）。
    Future<void> openPicker(WidgetTester tester) async {
      final chevron = find.byIcon(Icons.chevron_right);
      expect(chevron, findsOneWidget, reason: '页面上的尖角不是唯一 ⇒ 这个找法已经不成立');
      await tester.ensureVisible(chevron);
      await tester.tap(chevron);
      await tester.pumpAndSettle();
    }

    testWidgets('弹层是现成的选项弹层，不是 Material AlertDialog', (tester) async {
      await openDetail(tester, [tele('t', 'auto')], channelId: 't');
      await openPicker(tester);

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('选择推送渠道'), findsOneWidget);
      // 「自动」与每个已知档位都在；都带  这个 key（下一条用它点）。
      expect(find.byKey(const ValueKey('ios-picker-auto')), findsOneWidget);
    });

    testWidgets('选中那一档 ⇒ 值回到页面，且下次开层时那一档打勾', (tester) async {
      await openDetail(tester, [tele('t', 'auto')], channelId: 't');
      await openPicker(tester);

      final telegram = find.byKey(const ValueKey('ios-picker-telegram'));
      await tester.ensureVisible(telegram);
      await tester.tap(telegram);
      await tester.pumpAndSettle();

      expect(
        find.byType(CupertinoAlertDialog),
        findsNothing,
        reason: '选完必须自己关掉',
      );
      // ⚠ 必须**scope 到页面那一格**：选完弹层已关，但弹层里列下的档位名也在树上（未会自动移除），
      // 直接 `find.text('Telegram')` 会匹到多个 ⇒ 把「页面格子变了」这个判据误读成三个。
      final row = find.ancestor(
        of: find.text('Telegram'),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString().contains('Container'),
        ),
      );
      expect(row, findsWidgets);
      expect(
        find.text('Telegram'),
        findsWidgets,
        reason: '选中的值没回到页面 ⇒ 页面那一格仍是「自动识别」',
      );

      // 重开一次：现地那一档打勾——下面那个打勾才是「你选了哪一档」
      await openPicker(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ios-picker-telegram')),
          matching: find.byIcon(CupertinoIcons.check_mark),
        ),
        findsOneWidget,
      );
    });

    testWidgets('选「自动」 ⇒ 存的字面量与旧形状一致（auto，不是空字符串）', (tester) async {
      await openDetail(tester, [tele('t', 'telegram')], channelId: 't');
      await openPicker(tester);
      await tester.tap(find.byKey(const ValueKey('ios-picker-auto')));
      await tester.pumpAndSettle();

      // 断的是**页面端**交给原生的那个字面量：选「自动」就等于
      // 把类型交回「自动识别」——旧形状序的字面量就是 auto（不是空字符串），
      // 换件时一律「规范化成空」就是改了数据（存进 DB 的字面量不同）。
      // 不断存进去的那个值： 会把 auto 归一化成 generic，
      // 那是 codec 的职责（与旧形状一致），断它会把「页面交错值」也隐去。
      await tester.tap(find.text('仅测试'));
      await tester.pumpAndSettle();
      expect(
        lastTestArgs?['channelType'],
        'auto',
        reason:
            '选「自动」交给原生的类型必须还是 auto：'
            '旧形状存的就是这个字面量，换件时一律「规范化成空」就是改了数据'
            '（存进 DB 的字面量也会变）。'
            '（不断存进去的值：webhook_service 会把 auto 归一化成 generic，那是 codec 的职责。）',
      );
    });

    testWidgets('点外面关掉 ⇒ 一个字节都不改', (tester) async {
      await openDetail(tester, [tele('t', 'telegram')], channelId: 't');
      await openPicker(tester);

      // 断弹层确实可点穿（旧的 Material showDialog 默认可点穿，
      //  默认 false —— 这一句不能省）。
      // ⚠ 坐标不可写死： 高度不封顶，屏幕上可能根本没有「外面」
      // （片 21 已经在同一个坑上记录过）。
      final barriers = tester
          .widgetList<ModalBarrier>(find.byType(ModalBarrier))
          .where((b) => b.dismissible)
          .toList();
      expect(barriers, isNotEmpty, reason: '这一枚不可点穿 ⇒ 看了想收回去的路没了');
    });
  });

  group('详情页 – 消息格式档位来自原生（T08-B）', () {
    Map<String, dynamic> generic(String id, {String format = 'default'}) =>
        uiRow(
          id,
          '通道$id',
          'https://$id.example.com/hook',
          'generic',
          format: format,
        );

    testWidgets('导出的档位逐个成 chip（Dart 不再另存一份名单）', (tester) async {
      await openDetail(tester, [generic('a')], channelId: 'a');

      expect(find.text('默认格式'), findsOneWidget);
      expect(find.text('纯文本'), findsOneWidget);
      expect(find.text('Markdown'), findsOneWidget);
      expect(find.text('JSON'), findsOneWidget);
      expect(find.text('XML'), findsOneWidget);
    });

    testWidgets('原生加一档 ⇒ 界面就多一档，选了也能存下来', (tester) async {
      // 这条是"单一来源"的正证：以前要在 Dart 枚举里也加一项，否则界面看不见。
      formatsOverride = const [
        'default',
        'text',
        'markdown',
        'json',
        'xml',
        'html',
      ];
      await openDetail(tester, [generic('a')], channelId: 'a');

      expect(find.text('HTML'), findsNothing);
      await tester.tap(find.text('html'));
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(
        saved('a')['message_format'],
        'html',
        reason: '未知 token 被回退成 default = 用户选了档位却没生效',
      );
    });

    testWidgets('存量档位不认识也原样留着（旧枚举 fromValue 会静默改设置）', (tester) async {
      await openDetail(tester, [
        generic('a', format: 'card_v2'),
      ], channelId: 'a');

      expect(
        find.text('card_v2'),
        findsOneWidget,
        reason: '看不见自己存的档位 = 用户以为它不存在，下次保存顺手换成别的',
      );
      await tapSave(tester);
      expect(saved('a')['message_format'], 'card_v2');
    });

    testWidgets('描述符拉不到 ⇒ 不凭空造档位，也不把已存的洗掉', (tester) async {
      serveDescriptors = false;
      await openDetail(tester, [
        generic('a', format: 'markdown'),
      ], channelId: 'a');

      expect(find.text('Markdown'), findsOneWidget);
      expect(find.text('XML'), findsNothing);
      await tapSave(tester);
      expect(
        saved('a')['message_format'],
        'markdown',
        reason: '原生没答复时宁可只显示当前值，也不给出点了就丢真值的假档位',
      );
    });
  });

  group('详情页 – 备份/DB 形状不得打死页面（㊹）', () {
    testWidgets('enabled 是 0/1、类型只有 snake_case、secret 是 "null" 也能正常读出', (
      tester,
    ) async {
      // 维护者实测：备份后重新导入，webhook 设置页打不开 —— 页面 initState 原先
      // 对这些值做 `as bool?` 硬转型，而文件里的形状不受我们控制。
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      store.rows = [
        {
          'id': 'a',
          'name': '钉钉',
          'url': 'https://oapi.dingtalk.com/robot/send?access_token=x',
          'channel_type': 'dingtalk',
          'enabled': 1,
          'secret': 'null',
          'message_format': null,
          'message_template': 'null',
        },
      ];
      await service.loadChannels();
      await tester.pumpWidget(
        const AppRoot(
          locale: Locale('zh'),
          dark: false,
          home: WebhookSettingsPage(channelId: 'a'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '备份形状的行把页面打死了');
      // 标题用通道名（同一个字符串也出现在名称输入框里 ⇒ 只断言 AppBar 那一处）
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('钉钉')),
        findsOneWidget,
      );
      final texts = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((t) => t.controller?.text ?? '')
          .toList();
      expect(
        texts,
        isNot(contains('null')),
        reason: '"null" 脏数据必须被洗成未配置，否则被当成已配置密钥/模板',
      );
    });

    testWidgets('id 是数字也不崩（toString 兜住）', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      store.rows = [
        {
          'id': 7,
          'url': 'https://ntfy.sh/topic',
          'channel_type': 'ntfy',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
      await tester.pumpWidget(
        const AppRoot(
          locale: Locale('zh'),
          dark: false,
          home: WebhookSettingsPage(channelId: '7'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsWidgets);
    });
  });

  group('详情页 – 保存只写这一条（T07-B 的存在理由）', () {
    List<Map<String, dynamic>> twoRows() => [
      uiRow(
        'a',
        '通道A',
        'https://a.example.com/hook',
        'generic',
        secret: 'sec-a',
      ),
      uiRow(
        'b',
        '通道B',
        'https://b.example.com/hook',
        'generic',
        secret: 'sec-b',
      ),
    ];

    testWidgets('改第二条的名称 ⇒ 第一条在库里一个字节都不许变', (tester) async {
      await openDetail(tester, twoRows(), channelId: 'b');

      await tester.enterText(fieldAt(0), 'B 改名');
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(saved('b')['name'], 'B 改名');
      expect(saved('a')['name'], '通道A');
      expect(
        saved('a')['secret'],
        'sec-a',
        reason: '平铺页时代：详情页攥着整表快照，"只改一条"会覆盖别条（数据丢失级）',
      );
      expect(saved('a')['url'], 'https://a.example.com/hook');
    });

    testWidgets('没动过的字段保留原值（载荷不重发能力位收掉的东西）', (tester) async {
      await openDetail(tester, [
        uiRow(
          'dt',
          '钉钉A',
          'https://oapi.dingtalk.com/robot/send?access_token=a',
          'dingtalk',
          secret: 'sec-a',
          format: 'markdown',
          template: '## %title%',
        ),
      ], channelId: 'dt');
      await tester.enterText(fieldAt(0), '钉钉值班群');
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(saved('dt')['name'], '钉钉值班群');
      expect(saved('dt')['secret'], 'sec-a');
      expect(saved('dt')['message_format'], 'markdown');
      expect(saved('dt')['message_template'], '## %title%');
    });

    testWidgets('清空密钥是真的写空（看得见的字段显式发 null，合并不能把它顶回来）', (tester) async {
      await openDetail(tester, [
        uiRow(
          'dt',
          '钉钉A',
          'https://oapi.dingtalk.com/robot/send?access_token=a',
          'dingtalk',
          secret: 'sec-a',
        ),
      ], channelId: 'dt');
      await tester.enterText(fieldAt(2), '');
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(
        saved('dt')['secret'],
        anyOf(isNull, isEmpty),
        reason:
            '"载荷没这个键 = 保留原值"只对**看不见**的字段成立；密钥框就在眼前，'
            '用户清空白就是清空白',
      );
    });

    testWidgets('新增形态：保存后库里多出一条，已有那条原样', (tester) async {
      await openDetail(tester, [
        uiRow(
          'dt',
          '钉钉A',
          'https://oapi.dingtalk.com/robot/send?access_token=a',
          'dingtalk',
        ),
      ]);
      // 模拟器闸门（6.7）曾在"第二条"这一步发现结果里只剩新加的那条 —— 老那条不见了。
      expect(find.text('新增 Webhook 通道'), findsOneWidget);
      await tester.enterText(fieldAt(1), 'https://b.example.com/hook');
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(service.channels, hasLength(2));
      expect(
        saved('dt')['url'],
        'https://oapi.dingtalk.com/robot/send?access_token=a',
      );
      final newId = service.channels
          .map((c) => c['id']?.toString() ?? '')
          .firstWhere((id) => id != 'dt');
      expect(newId, startsWith('wh_'), reason: '新通道由本页发号，服务层按追加处理');
    });

    testWidgets('保存后标题跟着名字走（不重绘就还写着"新增"）', (tester) async {
      await openDetail(tester, const []);
      await tester.enterText(fieldAt(0), '告警群');
      await tester.pumpAndSettle();
      await tester.enterText(fieldAt(1), 'https://ntfy.sh/topic');
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(find.text('告警群'), findsWidgets);
      expect(find.text('新增 Webhook 通道'), findsNothing);
    });
  });

  group('详情页 – 必填缺失要点名（T03）', () {
    testWidgets('没填 URL ⇒ 点名地址缺失，且不写库', (tester) async {
      await openDetail(tester, const []);
      await tester.enterText(fieldAt(0), '告警群');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('保存失败：Webhook 地址不能为空'),
        findsOneWidget,
        reason: '只说"保存失败"等于让用户自己找缺什么',
      );
      expect(
        store.savedBatches,
        isEmpty,
        reason: '校验没过就不许写库（写了就是"我明明没配完，怎么开始收不到"）',
      );
    });

    testWidgets('URL 缺 scheme 时保存被拦下（不再静默存进 DB）', (tester) async {
      await openDetail(tester, const []);
      await tester.enterText(fieldAt(1), 'ntfy.sh/topic');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('保存失败：Webhook 地址必须以 http(s):// 开头'),
        findsOneWidget,
      );
      expect(store.savedBatches, isEmpty);

      // 局域网 http 自建端点必须能存：原生两处规则都接受 http
      await tester.enterText(fieldAt(1), 'http://ntfy.lan:8080/topic');
      await tester.pumpAndSettle();
      await tapSave(tester);
      expect(store.savedBatches, isNotEmpty);
    });

    testWidgets('Gotify 缺应用 Token ⇒ 阻止并点名；补上后放行', (tester) async {
      await openDetail(tester, [
        uiRow('gt', '本机 Gotify', 'http://push.example.com/message', 'gotify'),
      ], channelId: 'gt');
      await tapSave(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('该平台必需的凭据（签名密钥或 Token）不能为空'), findsOneWidget);
      expect(store.savedBatches, isEmpty);

      await tester.enterText(fieldAt(2), 'A1B2C3D4E5');
      await tester.pumpAndSettle();
      await tapSave(tester);
      expect(store.savedBatches, isNotEmpty);
    });

    testWidgets('描述符拉不到时不得凭猜测拦保存（没有元数据就放行）', (tester) async {
      serveDescriptors = false;
      await openDetail(tester, [
        uiRow('gt', '本机 Gotify', 'http://push.example.com/message', 'gotify'),
      ], channelId: 'gt');
      await tapSave(tester);

      expect(
        store.savedBatches,
        isNotEmpty,
        reason: 'URL 合法、只是读不到描述符 ⇒ 这时拦人保存是无据可依的猜测',
      );
    });
  });

  group('详情页 – 仅测试与测试并保存（T04/T07-B）', () {
    testWidgets('「仅测试」落单点但一个字节都不写库', (tester) async {
      await openDetail(tester, [
        uiRow(
          'dt',
          '钉钉A',
          'https://oapi.dingtalk.com/robot/send?access_token=a',
          'dingtalk',
          secret: 'sec-a',
        ),
      ], channelId: 'dt');
      testSucceeds = false;
      await health.record('webhook', 'dt', reachable: true, latencyMs: 5);
      calls.clear();
      store.savedBatches.clear();

      await tester.tap(find.widgetWithText(TextButton, '仅测试'));
      await tester.pumpAndSettle();

      expect(calls, contains('testWebhook'));
      expect(store.savedBatches, isEmpty, reason: '「仅测试」按定义不落库');
      expect(
        health.of('webhook', 'dt')?.reachable,
        isFalse,
        reason: '手动测试盖不掉旧的绿 ⇒ 首页与通道状态页还在说"正常"，异常冒不上去',
      );
    });

    testWidgets('新增未保存（还没有 id）⇒ 测了但不记账', (tester) async {
      await openDetail(tester, const []);
      await tester.enterText(fieldAt(1), 'https://ntfy.sh/topic');
      await tester.pumpAndSettle();
      calls.clear();
      final prefs = await SharedPreferences.getInstance();

      await tester.tap(find.widgetWithText(TextButton, '仅测试'));
      await tester.pumpAndSettle();

      expect(
        calls,
        contains('testWebhook'),
        reason: '这一条确实要被测到，否则「仅测试」对新增就是空按钮',
      );
      expect(
        prefs.getKeys().where((k) => k.startsWith('channel_health_')).toList(),
        isEmpty,
        reason: '没有归属的记账比不记更糟：空 id 写进去，下一条复用该位置的通道会继承这枚徽标',
      );
    });

    testWidgets('URL 还没填就点「仅测试」⇒ 不假装测过，直接说要填什么', (tester) async {
      await openDetail(tester, const []);
      calls.clear();

      await tester.tap(find.widgetWithText(TextButton, '仅测试'));
      await tester.pumpAndSettle();

      expect(calls, isNot(contains('testWebhook')));
      expect(find.textContaining('请先输入 Webhook URL'), findsOneWidget);
    });

    testWidgets('「测试并保存」= 先落库再测这一条', (tester) async {
      await openDetail(tester, [
        uiRow(
          'dt',
          '钉钉A',
          'https://oapi.dingtalk.com/robot/send?access_token=a',
          'dingtalk',
          secret: 'sec-a',
        ),
      ], channelId: 'dt');
      calls.clear();
      store.savedBatches.clear();

      await tapSave(tester);

      expect(store.savedBatches, isNotEmpty, reason: '这颗按钮的定义就是"存下来"');
      expect(calls, contains('testWebhook'));
    });

    testWidgets('停用的通道保存后不自动测：它本来就不在推送路由里', (tester) async {
      await openDetail(tester, [
        uiRow(
          'dt',
          '钉钉A',
          'https://oapi.dingtalk.com/robot/send?access_token=a',
          'dingtalk',
          secret: 'sec-a',
          enabled: false,
        ),
      ], channelId: 'dt');
      calls.clear();
      store.savedBatches.clear();

      await tapSave(tester);

      expect(store.savedBatches, isNotEmpty);
      expect(calls, isNot(contains('testWebhook')));
    });
  });
}

/// 内存版 webhook 存储：只记录"最后一次整表写了什么"，够钉住单条写入语义。
class _FakeWebhookStore implements WebhookChannelStore {
  List<Map<String, dynamic>> rows = [];
  final List<List<Map<String, dynamic>>> savedBatches = [];

  @override
  Future<List<Map<String, dynamic>>> getWebhookChannels() async => rows;

  @override
  Future<void> saveWebhookChannels(List<Map<String, dynamic>> channels) async {
    savedBatches.add(List.of(channels));
    rows = List.of(channels);
  }
}
