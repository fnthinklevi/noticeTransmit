import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/app_channel_list_page.dart';
import 'package:notice_transmit/pages/app_channel_settings_page.dart';
import 'package:notice_transmit/services/app_channel_service.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/widgets/card_action_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/channel_descriptor_fixtures.dart';

/// 自建应用通道**列表页**（T07 之后它是"有哪些通道"的唯一所有者）。
///
/// 三件事各有其历史原因：
/// 1. **类型标签**：曾经写成 `appType == 'feishu_app' ? 飞书 : 企微`——把否定分支当
///    默认值用，于是任何未识别的 app_type（原生新增通道、脏数据）都被标成企微，
///    用户照着企微的引导去填另一家的凭据。
/// 2. **单条操作即时落库**：详情页只编辑一条，列表页的启停/复制/删除必须各自直达
///    服务层（不再有"整表快照 + 保存时才写"的中间态）。
/// 3. **删除要确认**（T06 的咽喉在本页的 `_confirmDeleteChannel`）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAppChannelStore store;
  late AppChannelService service;
  late ChannelHealthStore health;

  Map<String, dynamic> row(String id, String appType, String name) => {
    'id': id,
    'name': name,
    'app_type': appType,
    'base_url': 'https://example.com',
    'secret': 'sec-$id',
    'config': jsonEncode({'corpid': 'corp-$id'}),
    'message_format': 'default',
    'enabled': 1,
  };

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
        home: AppChannelListPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 长按某一行的动作表（key 挂在通道 id 上，不是下标）。
  Future<void> openMenu(WidgetTester tester, String id) async {
    await tester.longPress(find.byKey(ValueKey('app-channel-row-$id')));
    await tester.pumpAndSettle();
  }

  Finder inSheet(String label) => find.descendant(
    of: find.byType(CardActionSheet),
    matching: find.text(label),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // loadChannels() 末尾会 setAppChannels 同步原生：widget 测试里若不给该通道装
    // mock handler，invokeMethod 永不返回，pumpAndSettle 会一直挂到 10 分钟超时。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.fnthink.notice/notification'),
          (call) async {
            // FAB 的类型弹层内容来自原生描述符表；给 null 就等于"原生没返回"，
            // 弹层会是空的 ⇒ 用例会在自己的假前提下判红。
            if (call.method == 'getChannelDescriptors') {
              return descriptorCallResponse(call);
            }
            return null;
          },
        );
    store = _FakeAppChannelStore();
    service = AppChannelService(store: store);
    GetIt.instance.allowReassignment = true;
    if (GetIt.instance.isRegistered<AppChannelService>()) {
      GetIt.instance.unregister<AppChannelService>();
    }
    GetIt.instance.registerLazySingleton<AppChannelService>(() => service);
    registerChannelPageServices();
    health = GetIt.instance<ChannelHealthStore>();
    await health.load();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.fnthink.notice/notification'),
          null,
        );
    GetIt.instance.reset();
  });

  group('AppChannelListPage – 类型标签', () {
    testWidgets('已知类型显示各自名称', (tester) async {
      store.rows = [
        row('a', 'wecom_app', '企微A'),
        row('b', 'feishu_app', '飞书B'),
      ];
      await open(tester);
      expect(find.text('企业微信自建应用'), findsOneWidget);
      expect(find.text('飞书自建应用'), findsOneWidget);
    });

    testWidgets('未知类型显示「未知」，不冒充企业微信自建应用', (tester) async {
      store.rows = [row('c', 'lark_app', '未来通道C')];
      await open(tester);
      expect(find.text('企业微信自建应用'), findsNothing);
      expect(find.text('飞书自建应用'), findsNothing);
      expect(find.text('未知'), findsWidgets);
    });

    testWidgets('app_type 为空同样不冒充', (tester) async {
      store.rows = [row('d', '', '空类型D')];
      await open(tester);
      expect(find.text('企业微信自建应用'), findsNothing);
    });
  });

  group('AppChannelListPage – 单条操作直达服务（T07）', () {
    testWidgets('启停开关即时落库，且只改那一条', (tester) async {
      store.rows = [row('a', 'wecom_app', 'A'), row('b', 'wecom_app', 'B')];
      await open(tester);

      await tester.tap(find.byType(CupertinoSwitch).first);
      await tester.pumpAndSettle();

      expect(service.channels, hasLength(2));
      expect(
        service.channels.firstWhere((c) => c['id'] == 'a')['enabled'],
        isFalse,
      );
      expect(
        service.channels.firstWhere((c) => c['id'] == 'b')['enabled'],
        isTrue,
        reason: '整表重写时把另一条的旧快照一起写回去 = 覆盖掉别人的改动',
      );
      expect(store.rows, hasLength(2), reason: '落库的必须是服务归一化后的整表');
    });

    testWidgets('点某一行打开的是**那一条**的详情页', (tester) async {
      store.rows = [row('a', 'wecom_app', 'A'), row('b', 'feishu_app', 'B')];
      await open(tester);

      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();

      expect(find.byType(AppChannelSettingsPage), findsOneWidget);
      final texts = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller?.text ?? '')
          .toList();
      expect(texts, contains('B'));
      expect(
        texts,
        isNot(contains('A')),
        reason: '点第 2 条打开的却是整表/第 1 条 = T07 要修的旧形状',
      );
    });

    testWidgets('FAB 的类型列表来自描述符（不再硬编码两个类型）', (tester) async {
      await open(tester);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, '企业微信自建应用'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '飞书自建应用'), findsOneWidget);
    });

    testWidgets('长按 ⇒ 修改/复制/启停/删除；复制另发新 id 并带上凭据', (tester) async {
      store.rows = [row('a', 'wecom_app', '企微A')];
      await open(tester);

      await openMenu(tester, 'a');
      expect(
        inSheet('编辑'),
        findsOneWidget,
        reason: '标签用既有的 l10n.edit（编辑），不另立一词',
      );
      expect(inSheet('复制'), findsOneWidget);
      expect(inSheet('停用'), findsOneWidget);
      expect(inSheet('删除'), findsOneWidget);

      await tester.tap(inSheet('复制'));
      await tester.pumpAndSettle();

      expect(service.channels, hasLength(2));
      final copy = service.channels.last;
      expect(
        copy['id'],
        isNot('a'),
        reason: '两条同 id ⇒ 徽标与送达归属互相顶掉，编辑/删除也会一次中两条',
      );
      expect(copy['name'], '企微A 副本');
      expect(copy['secret'], 'sec-a', reason: '复制不到凭据的"复制"等于让用户重填一遍');
      expect((copy['config'] as Map)['corpid'], 'corp-a', reason: '扩展参数也要一起过来');
    });

    testWidgets('删除先确认；取消不动数据，确认才落库并清健康记录', (tester) async {
      store.rows = [row('a', 'wecom_app', '企微A'), row('b', 'wecom_app', '企微B')];
      await open(tester);
      await health.record('app', 'a', reachable: false, latencyMs: 4);
      expect(health.of('app', 'a'), isNotNull, reason: '前提：有一条待删的记录');

      await openMenu(tester, 'a');
      await tester.tap(inSheet('删除'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '取消').last);
      await tester.pumpAndSettle();
      expect(service.channels, hasLength(2), reason: '取消不许改数据');
      expect(health.of('app', 'a'), isNotNull, reason: '取消也不许清缓存');

      await openMenu(tester, 'a');
      await tester.tap(inSheet('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '删除').last);
      await tester.pumpAndSettle();

      expect(service.channels.map((c) => c['id']), ['b']);
      expect(
        health.of('app', 'a'),
        isNull,
        reason: '记录留着，日后 id 复用（从旧备份恢复）时徽标会复活成上一条通道的状态',
      );
      expect(health.of('app', 'b'), isNull, reason: '只清被删那条');
    });
  });
}

/// 纯 Dart 测试环境没有平台通道，注入内存 store。
class _FakeAppChannelStore implements AppChannelStore {
  List<Map<String, dynamic>> rows = [];

  @override
  Future<List<Map<String, dynamic>>> getAppChannels() async => rows;

  @override
  Future<void> saveAppChannels(List<Map<String, dynamic>> channels) async {
    rows = List.of(channels);
  }
}
