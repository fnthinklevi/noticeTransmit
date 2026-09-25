import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/webhook_channel_list_page.dart';
import 'package:notice_transmit/pages/webhook_settings_page.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/services/webhook_service.dart';
import 'package:notice_transmit/widgets/card_action_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/channel_descriptor_fixtures.dart';
import '../test_setup.dart';

/// Webhook 通道**列表页**（T07-B：这一族原先是一张全量平铺编辑页）。
///
/// 这一页要钉住的四件事，每一件都是平铺形态下真实存在过的缺陷类别：
/// 1. 行的内容跟着**自己的通道**走（以前九条并行列表按下标寻址，删一行漏一处就串台）；
/// 2. 点第 N 行进的是第 N 条的详情页（以前点谁都是同一个平铺页）；
/// 3. 启停 / 复制 / 删除都只动一条，且即时落库（以前要等右上角保存整表重写）；
/// 4. 进页后台探测读的是**实时列表**而不是构造期快照（以前探测结论会写到已删除的通道上）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'com.fnthink.notice/notification';
  final now = DateTime.now().millisecondsSinceEpoch;

  late _FakeWebhookStore store;
  late WebhookService service;
  late ChannelHealthStore health;

  /// DB 行形状（服务层负责归一化成 UI 形状）。
  Map<String, dynamic> row(
    String id,
    String name,
    String url,
    String type, {
    bool enabled = true,
    String? secret,
  }) => {
    'id': id,
    'name': name,
    'url': url,
    'channel_type': type,
    'enabled': enabled ? 1 : 0,
    'secret': secret,
    'message_format': 'default',
    'message_template': null,
  };

  List<Map<String, dynamic>> twoRows() => [
    row('a', '通道A', 'https://a.example.com/hook', 'wechat_work'),
    row('b', '通道B', 'https://b.example.com/hook', 'generic'),
  ];

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await service.loadChannels();
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh'),
        home: WebhookChannelListPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 长按某一行的动作表（key 挂在通道 id 上，不是下标）。
  Future<void> openMenu(WidgetTester tester, String id) async {
    await tester.longPress(find.byKey(ValueKey('webhook-channel-row-$id')));
    await tester.pumpAndSettle();
  }

  Finder inSheet(String label) => find.descendant(
    of: find.byType(CardActionSheet),
    matching: find.text(label),
  );

  /// 删除的确认框（T06 的咽喉在本页的 `_confirmDeleteChannel`）。
  /// 这条 helper 本身就是守卫：没有确认框 ⇒ 它当场红。
  Future<void> confirmDelete(WidgetTester t) async {
    // 动作表的下场动画与确认框的上场动画之间必须让它 settle，否则这里找到的
    // 是"还没出现的对话框"（本仓库的 widget 测试反复踩过：点完菜单项立刻断言）。
    await t.pumpAndSettle();
    final dialog = find.widgetWithText(TextButton, '删除');
    expect(
      dialog,
      findsWidgets,
      reason: '点删除就直接删 ⇒ T06 的二次确认被绕开（凭据重填一次的成本远高于确认一下）',
    );
    await t.tap(dialog.last);
    await t.pumpAndSettle();
  }

  List<String> savedIds() =>
      service.channels.map((c) => c['id']?.toString() ?? '').toList();

  Map<String, dynamic> savedOf(String id) =>
      service.channels.firstWhere((c) => c['id'] == id);

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      // a 不可达 / b 可达 7ms，probedAt = 刚刚 ⇒ 进页不会触发后台探测
      // （探测会覆盖缓存，让断言的前提失效）。
      'channel_health_webhook:a': jsonEncode({
        'reachable': false,
        'latencyMs': 0,
        'httpCode': 0,
        'probedAt': now,
      }),
      'channel_health_webhook:b': jsonEncode({
        'reachable': true,
        'latencyMs': 7,
        'httpCode': 200,
        'probedAt': now,
      }),
    });
    // ⚠ 服务层写路径会 await **两个**原生通道（notification + flutter_secure_storage），
    // 少桩一个就是整批用例 did not complete（base.md（53）（54）两次踩过，helper 已收口）。
    stubNativeChannels(
      onCall: (call) async {
        if (call.method == 'getChannelDescriptors') {
          return descriptorCallResponse(call);
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

  group('WebhookChannelListPage – 行跟着自己的通道走', () {
    testWidgets('零通道进入不崩，给空态与添加提示', (tester) async {
      store.rows = [];
      await open(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('暂无 Webhook 通道'), findsOneWidget);
      expect(find.text('点击下方按钮添加'), findsOneWidget);
    });

    testWidgets('每行显示类型名 + 主机 + 自己的健康徽标（不是上一条的）', (tester) async {
      store.rows = twoRows();
      await open(tester);

      expect(find.text('通道A'), findsOneWidget);
      expect(find.text('通道B'), findsOneWidget);
      // a 不可达 / b 可达 7ms：两枚徽标各归各
      expect(find.text('连接失败'), findsOneWidget);
      expect(find.text('连通 · 7 ms'), findsOneWidget);
      expect(find.textContaining('a.example.com'), findsOneWidget);
      expect(find.textContaining('b.example.com'), findsOneWidget);
    });

    testWidgets('未知类型不被兜底成某个平台（否则用户照着错的引导去填凭据）', (tester) async {
      store.rows = [
        row('z', 'Z', 'https://z.example.com/hook', 'totally_new_platform'),
      ];
      await open(tester);
      // 描述符里没有这个 slug ⇒ 名称退回 slug 原样显示，不冒充企微
      expect(find.text('企业微信'), findsNothing);
      expect(find.textContaining('totally_new_platform'), findsOneWidget);
    });
  });

  group('WebhookChannelListPage – 点行进详情页', () {
    testWidgets('点第 2 行打开的是第 2 条（以前点谁都是同一个平铺页）', (tester) async {
      store.rows = twoRows();
      await open(tester);

      await tester.tap(find.text('通道B'));
      await tester.pumpAndSettle();

      expect(find.byType(WebhookSettingsPage), findsOneWidget);
      expect(
        find.text('https://b.example.com/hook'),
        findsOneWidget,
        reason: '详情页打开的必须是被点那条',
      );
    });

    testWidgets('FAB 进新增形态：标题是「新增 Webhook 通道」且不带着任何已有通道', (tester) async {
      store.rows = twoRows();
      await open(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.byType(WebhookSettingsPage), findsOneWidget);
      expect(find.text('新增 Webhook 通道'), findsOneWidget);
      expect(find.text('https://a.example.com/hook'), findsNothing);
    });
  });

  group('WebhookChannelListPage – 单条操作即时落库', () {
    testWidgets('启停只翻那一条，另一条例外不动', (tester) async {
      store.rows = twoRows();
      await open(tester);
      store.savedBatches.clear();

      await tester.tap(find.byType(CupertinoSwitch).first);
      await tester.pumpAndSettle();

      expect(savedIds(), ['a', 'b']);
      expect(savedOf('a')['enabled'], isFalse);
      expect(savedOf('b')['enabled'], isTrue);
      expect(store.savedBatches, isNotEmpty, reason: '开关必须即时落库');
      // 原生启用 URL 列表跟着重算：后台只推启用通道
      expect(
        store.savedBatches.last.map((r) => r['url']).toList(),
        ['https://a.example.com/hook', 'https://b.example.com/hook'],
        reason: '整表写库本身没变（DB 只有全量替换路径），变的是"谁决定这一条"',
      );
    });

    testWidgets('复制出的新行换 id、名字带「副本」、不继承徽标', (tester) async {
      store.rows = [
        row(
          'dt',
          '钉钉A',
          'https://oapi.dingtalk.com/robot/send?access_token=a',
          'dingtalk',
          secret: 'sec-a',
        ),
      ];
      await open(tester);

      await openMenu(tester, 'dt');
      await tester.tap(inSheet('复制'));
      await tester.pumpAndSettle();

      expect(savedIds(), hasLength(2));
      final copyId = savedIds().last;
      expect(copyId, isNot('dt'), reason: '两条同 id ⇒ 徽标与送达归属整体串台');
      expect(savedOf(copyId)['name'], '钉钉A 副本');
      expect(
        savedOf(copyId)['url'],
        'https://oapi.dingtalk.com/robot/send?access_token=a',
        reason: '复制的意义就是不用再粘一遍地址（含凭据 query）',
      );
      expect(
        health.of('webhook', copyId),
        isNull,
        reason: '刚复制出来的那条没测过，顶着一枚绿勾比顶着空白更糟',
      );
    });

    testWidgets('删除：点「取消」不改数据，也不清健康记录', (tester) async {
      store.rows = twoRows();
      await open(tester);

      await openMenu(tester, 'a');
      await tester.tap(inSheet('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消').last);
      await tester.pumpAndSettle();

      expect(savedIds(), ['a', 'b']);
      expect(
        health.of('webhook', 'a'),
        isNotNull,
        reason: '取消却清了缓存 ⇒ 用户反悔了，首页的异常标记却回不来',
      );
    });

    testWidgets('删除：确认后只删那条，并连带清掉它的健康记录', (tester) async {
      store.rows = twoRows();
      await open(tester);

      await openMenu(tester, 'a');
      await tester.tap(inSheet('删除'));
      await confirmDelete(tester);

      expect(savedIds(), ['b']);
      expect(
        health.of('webhook', 'a'),
        isNull,
        reason: '记录留着，日后 id 复用（从旧备份恢复）时徽标会复活成上一条通道的状态',
      );
      expect(health.of('webhook', 'b'), isNotNull, reason: '只能清被删那条');
    });
  });

  group('WebhookChannelListPage – 手机宽度下的行布局', () {
    testWidgets('两行 + 徽标不得撑破行（RenderFlex overflow）', (tester) async {
      // T07-B 的模拟器闸门红过一轮：徽标里"连通 · N ms"与"N 分钟前探测"都是自然宽度，
      // 手机宽度下列表行副标题只剩 ~170dp ⇒ 撑破行（widget 测试的视口比手机宽得多，看不见）。
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      store.rows = twoRows();
      await service.loadChannels();
      final health = GetIt.instance<ChannelHealthStore>();
      await health.record('webhook', 'a', reachable: false, latencyMs: 0);
      await health.record('webhook', 'b', reachable: true, latencyMs: 1234);
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: WebhookChannelListPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: '行内任何一段文字不许把行撑破：溢出会把副标题截断，也会让手势落在意外的位置',
      );
      // 状态本身必须还在（放不下时缩的是文字尾部，不是把整枚徽标挤没）
      expect(find.textContaining('连通'), findsOneWidget);
    });
  });

  group('WebhookChannelListPage – 进页后台探测读实时列表', () {
    testWidgets('探测请求带的是列表里那条通道**当前**的 URL', (tester) async {
      store.rows = [
        row('s', '旧的', 'https://stale.example.com/hook', 'generic'),
      ];
      // probedAt = 0 ⇒ 超过 6 小时时效，进页必须重探
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'channel_health_webhook:s',
        jsonEncode({
          'reachable': true,
          'latencyMs': 1,
          'httpCode': 200,
          'probedAt': 0,
        }),
      );
      await health.load();

      final probed = <String, Object?>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName), (
            call,
          ) async {
            if (call.method == 'getChannelDescriptors') {
              return descriptorCallResponse(call);
            }
            if (call.method == 'probeChannelHealth') {
              probed.addAll(Map<String, Object?>.from(call.arguments as Map));
              return {'reachable': false, 'latencyMs': 9, 'httpCode': 500};
            }
            return null;
          });

      await open(tester);
      await tester.pumpAndSettle();

      expect(probed['url'], 'https://stale.example.com/hook');
      expect(
        health.of('webhook', 's')?.reachable,
        isFalse,
        reason: '探测结论要写回单点，否则首页永远显示旧的绿',
      );
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
