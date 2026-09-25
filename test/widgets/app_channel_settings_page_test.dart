import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/app_channel_settings_page.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/services/app_channel_service.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/channel_descriptor_fixtures.dart';

/// 自建应用通道设置页 widget 冒烟测试。
///
/// AppChannelService 通过 GetIt 注册（fake store 注入），
/// MethodChannel mock 拦截 testAppChannel / probeChannelHealth / getChannelDescriptors。
///
/// ⚠ 描述符 fixture 来自原生导出快照（见 support/channel_descriptor_fixtures），
/// 「扩展参数有几个输入框」这类断言因此是**跟着原生表变的**，不是测试自己抄一份。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAppChannelStoreForPage store;
  late AppChannelService service;
  const channelName = 'com.fnthink.notice/notification';

  /// false = 原生描述符拉不到（老 App 配新原生、或装配失败）：
  /// 页面必须仍能保存且不把已存 config 写空。
  var serveDescriptors = true;

  /// T07：详情页是**单通道**形态 ⇒ 打开哪一条由 `channelId` 决定。
  /// [which] = 已加载列表里的第几条（默认第一条）；给 [newAppType] 则走"新增一条"形态。
  Widget buildApp({int which = 0, String? newAppType}) {
    final id = newAppType == null && service.channels.length > which
        ? service.channels[which]['id']?.toString()
        : null;
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      // key 挂在 id 上：测试里连续 pumpWidget 两个不同 channelId 时，没有 key 的话
      // Flutter 会**复用同一个 State**（initState 不再跑），断言就会看到上一条的内容。
      home: AppChannelSettingsPage(
        key: ValueKey('detail-${id ?? newAppType}'),
        channelId: id,
        newAppType: newAppType,
      ),
    );
  }

  setUp(() {
    serveDescriptors = true;
    SharedPreferences.setMockInitialValues({});
    store = FakeAppChannelStoreForPage();
    service = AppChannelService(store: store);
    // 替换 GetIt 中的 AppChannelService（主测试可能已注册）
    GetIt.instance.allowReassignment = true;
    if (GetIt.instance.isRegistered<AppChannelService>()) {
      GetIt.instance.unregister<AppChannelService>();
    }
    GetIt.instance.registerLazySingleton<AppChannelService>(() => service);
    registerChannelPageServices();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), (
          call,
        ) async {
          if (call.method == 'probeChannelHealth') {
            return {'reachable': true, 'latencyMs': 50, 'httpCode': 200};
          }
          if (call.method == 'testAppChannel') {
            return {'success': true, 'message': 'ok'};
          }
          if (call.method == 'getChannelDescriptors') {
            return serveDescriptors ? descriptorCallResponse(call) : null;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), null);
  });

  group('AppChannelSettingsPage – widget 冒烟', () {
    testWidgets('空通道渲染：页面标题 + 说明文案 + 无崩溃', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      expect(find.byType(AppChannelSettingsPage), findsOneWidget);
      expect(find.byType(TextField), findsWidgets); // 首条默认通道的输入框
    });

    testWidgets('已有通道渲染：通道卡片 + 输入框', (tester) async {
      store.rows = [
        {
          'id': 'app-1',
          'name': '测试企微应用',
          'app_type': 'wecom_app',
          'base_url': 'https://qyapi.weixin.qq.com',
          'secret': null,
          'config': '{"corpid":"corp-x","agentid":1,"touser":"@all"}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      // 页面数据源是 AppChannelService.channels —— 必须先加载
      await service.loadChannels();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      // 通道名称输入框有值
      final nameField = find.byType(TextField).first;
      final editor = tester.widget<TextField>(nameField);
      expect(editor.controller?.text, '测试企微应用');
    });

    testWidgets('T07：两条通道时详情页只渲染选中的那条（不再是整表平铺）', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      store.rows = [
        {
          'id': 'app-1',
          'name': 'A',
          'app_type': 'wecom_app',
          'base_url': 'https://a.com',
          'secret': null,
          'config': '{}',
          'message_format': 'default',
          'enabled': 1,
        },
        {
          'id': 'app-2',
          'name': 'B',
          'app_type': 'feishu_app',
          'base_url': 'https://open.feishu.cn',
          'secret': null,
          'config': '{}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      // 每条通道：名称 + API 地址 + 密钥 + 扩展参数（企微 3 / 飞书 3）= 6 个输入框，
      // 两条通道共 12 个。⚠ ListView 懒加载：默认 600px 视口只构建首张卡，
      // 需放大视口才能断言两张卡同时渲染（否则会误判为"字段缺失"）。
      // 单通道：名称 + API 地址 + 密钥 + 扩展参数 3 = 6 个输入框
      // （旧版整表平铺时这里是 12 —— 两条通道挤在一页里互相盖写，正是 T07 要拆掉的形状）
      expect(find.byType(TextField), findsNWidgets(6));
      expect(find.text('A'), findsWidgets);
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((f) => f.controller?.text ?? ''),
        isNot(contains('https://open.feishu.cn')),
        reason: '打开第 1 条却把第 2 条的地址也铺出来 = 又回到整表编辑页',
      );

      await tester.pumpWidget(buildApp(which: 1));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((f) => f.controller?.text ?? ''),
        contains('https://open.feishu.cn'),
        reason: '换 channelId 必须换内容，否则"点第 2 条打开的还是第 1 条"',
      );
    });

    // ===== 回归守卫：字段回填 + 保存不丢字段 =====
    // 背景：_bindControllers 曾只绑定 config 字段控制器，未创建
    // name/baseUrl/secret 控制器 —— 表现为①打开已有通道时三个输入框空白；
    // ②保存时 _channelPayload 读到 null，把 baseUrl 清空、secret 置 null（凭据丢失）。
    testWidgets('字段回填：名称 / API 地址 / 密钥来自已保存通道', (tester) async {
      store.rows = [
        {
          'id': 'app-1',
          'name': '企微应用A',
          'app_type': 'wecom_app',
          'base_url': 'https://custom.example.com',
          'secret': 'corpsecret-demo',
          'config': '{"corpid":"corp-x","agentid":1000002,"touser":"@all"}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final texts = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller?.text ?? '')
          .toList();
      expect(texts, contains('企微应用A'), reason: '名称未回填');
      expect(
        texts,
        contains('https://custom.example.com'),
        reason: 'API 地址未回填（私有化部署地址会丢失）',
      );
      expect(texts, contains('corpsecret-demo'), reason: '密钥未回填');
    });

    testWidgets('保存不丢字段：baseUrl / secret / name 原值保留', (tester) async {
      store.rows = [
        {
          'id': 'app-1',
          'name': '企微应用A',
          'app_type': 'wecom_app',
          'base_url': 'https://qyapi.weixin.qq.com',
          'secret': 'corpsecret-demo',
          'config': '{"corpid":"corp-x","agentid":1000002,"touser":"@all"}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '测试并保存'));
      await tester.pumpAndSettle();

      // service.saveChannels 归一化后的行是 UI 格式（baseUrl/appType/...）；
      // DB 列名映射（camelCase → snake_case）由 DatabaseHelper 负责，
      // 已由 test/database/app_channel_schema_test.dart 守卫。
      final saved = store.rows.firstWhere((r) => r['id'] == 'app-1');
      expect(
        saved['baseUrl'],
        'https://qyapi.weixin.qq.com',
        reason: '保存后 API 地址被清空（控制器缺失导致空值覆盖）',
      );
      expect(
        saved['secret'],
        'corpsecret-demo',
        reason: '保存后密钥被置 null —— 凭据丢失，推送将全部失败',
      );
      expect(saved['name'], '企微应用A', reason: '保存后名称丢失');
    });

    // ===== 回归守卫 T02：通道名必须跟着保存走 =====
    // 背景（roadmap T02）：`_channelPayload` 曾**不含 name**，控制器里的名字只在
    // `_saveAll` 的非空校验里读一次、从不回填进载荷 ⇒ `{...旧行, ...payload}` 合并后
    // 用的仍是旧行的 name：新建通道存成 `''`（列表页/首页标签空白），改名则**静默失效**
    // （看起来"保存成功"，重进页面还是老名字）。
    // 上面那条「保存不丢字段」用例**守不住这个**：它只验原值保留，不验值被改过。
    testWidgets('T02 改名后保存：新名字真的落库（此前只校验、从不回填）', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      store.rows = [
        {
          'id': 'app-1',
          'name': '企微应用A',
          'app_type': 'wecom_app',
          'base_url': 'https://qyapi.weixin.qq.com',
          'secret': 's',
          'config': '{"corpid":"corp-x","agentid":1,"touser":"@all"}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.enterText(_fieldName(), '办公告警应用');
      await tester.tap(find.widgetWithText(TextButton, '测试并保存'));
      await tester.pumpAndSettle();

      final saved = store.rows.firstWhere((r) => r['id'] == 'app-1');
      expect(saved['name'], '办公告警应用', reason: '改名没落库：载荷缺 name 键（T02 病灶）');
    });

    testWidgets('T02 新建→填名→保存→重进页面名字仍在（此前存成空串）', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      store.rows = [];
      await service.loadChannels();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      // 空列表时 initState 会自动补一张企微空卡（`_channels.isEmpty → _addChannel`）
      expect(find.byType(TextField), findsNWidgets(6));

      await tester.enterText(_fieldName(), 'NAS 告警应用');
      await tester.enterText(_fieldWithLabel('企业 ID（corpid）'), 'corp-new');
      await tester.tap(find.widgetWithText(TextButton, '测试并保存'));
      await tester.pumpAndSettle();

      expect(store.rows, hasLength(1));
      expect(store.rows.first['name'], 'NAS 告警应用');
      expect(store.rows.first['id'], isNotEmpty, reason: '新增行要带得住 id');

      // 「重载」才是这条用例的重点：换掉页面实例，让名字从 service 走一遍回来
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_fieldName()).controller?.text,
        'NAS 告警应用',
        reason: '保存后重进页面名字空白 ⇒ 落库的就是空串（T02）',
      );
    });

    // ===== 接入引导（v1.59）=====
    testWidgets('卡片「?」打开企微接入引导（含步骤与注意事项）', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      store.rows = [
        {
          'id': 'app-1',
          'name': '企微应用A',
          'app_type': 'wecom_app',
          'base_url': '',
          'secret': null,
          'config': '{}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // 页面顶部入口 + 卡片入口 → 取卡片内的那个打开引导
      await tester.tap(find.byIcon(Icons.help_outline).last);
      await tester.pumpAndSettle();

      expect(find.text('企业微信自建应用 · 接入步骤'), findsOneWidget);
      expect(find.textContaining('获取企业 ID（corpid）'), findsOneWidget);
      expect(find.text('注意事项'), findsOneWidget);
      // 注意事项含 HTTPS/证书警示（自定义地址场景的高频坑）
      expect(find.textContaining('自定义 API 地址须使用 HTTPS'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);
    });

    testWidgets('飞书类型卡片「?」打开飞书接入引导', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      store.rows = [
        {
          'id': 'app-2',
          'name': '飞书应用B',
          'app_type': 'feishu_app',
          'base_url': '',
          'secret': null,
          'config': '{}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.help_outline).last);
      await tester.pumpAndSettle();

      expect(find.text('飞书自建应用 · 接入步骤'), findsOneWidget);
      expect(find.textContaining('开通消息权限'), findsOneWidget);
    });

    // ===== 健康徽标数据源 =====
    // 此前 channel_health_<id> 只有 webhook 侧会写，本页面只读不写 ⇒
    // 应用通道的徽标永远不出现（读一条恒为空的缓存）。
    testWidgets('点「测试」后写健康缓存并显示徽标（此前徽标恒空）', (tester) async {
      // 「测试」按钮在卡片底部，默认 800×600 视口里落在屏幕外，tap 会命中失败
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      store.rows = [
        {
          'id': 'app-h1',
          'name': '企微应用H',
          'app_type': 'wecom_app',
          'base_url': 'https://qyapi.weixin.qq.com',
          'secret': 's',
          'config': '{}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      expect(
        find.textContaining('连通 ·'),
        findsNothing,
        reason: '未测试过时不应凭空出现徽标',
      );

      await tester.tap(find.widgetWithText(FilledButton, '测试'));
      await tester.pumpAndSettle();

      expect(find.textContaining('连通 ·'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      // 第 6 步起键里带 family（`channel_health_app:<id>`）：不带 family 时三族各自的
      // id 序列一旦撞上，徽标就会串到别人身上。
      final cachedRaw = prefs.getString('channel_health_app:app-h1');
      expect(cachedRaw, isNotNull, reason: '徽标必须落缓存，否则重进页面又变回恒空');
      final cached = jsonDecode(cachedRaw!) as Map<String, dynamic>;
      expect(cached['reachable'], isTrue);
      expect(cached['probedAt'], isNotNull);
    });

    testWidgets('旧格式键（不带 family）仍读得穿：徽标不因第 6 步换键而消失', (tester) async {
      SharedPreferences.setMockInitialValues({
        'channel_health_app-h2':
            '{"reachable":false,"latencyMs":0,"httpCode":0,"probedAt":${DateTime.now().millisecondsSinceEpoch}}',
      });
      store.rows = [
        {
          'id': 'app-h2',
          'name': '飞书应用H2',
          'app_type': 'feishu_app',
          'base_url': 'https://open.feishu.cn',
          'secret': 's',
          'config': '{}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      expect(find.text('连接失败'), findsOneWidget);
    });

    // ===== 未知应用类型不得冒充企业微信 =====
    testWidgets('未知 app_type 不给接入引导入口（引导文案只有企微/飞书两套）', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      store.rows = [
        {
          'id': 'app-x',
          'name': '未来的通道',
          'app_type': 'whatever_app',
          'base_url': '',
          'secret': null,
          'config': '{}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // 只剩页面顶部那个企微入口；卡片内不得再多出一个（否则点开就是企微步骤）
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
    });
    // ===== 描述符驱动（第 5 步）=====

    testWidgets('字段清单来自描述符：企微 corpid/agentid/touser 都回填了', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      store.rows = [
        {
          'id': 'app-1',
          'name': '企微应用A',
          'app_type': 'wecom_app',
          'base_url': 'https://qyapi.weixin.qq.com',
          'secret': 's',
          'config': '{"corpid":"corp-x","agentid":1000002,"touser":"user1"}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final texts = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller?.text ?? '')
          .toList();
      expect(texts, containsAll(['corp-x', '1000002', 'user1']));
    });

    testWidgets('描述符拉不到时保存不写空 config（合并语义，不是重建）', (tester) async {
      serveDescriptors = false;
      store.rows = [
        {
          'id': 'app-1',
          'name': '企微应用A',
          'app_type': 'wecom_app',
          'base_url': 'https://qyapi.weixin.qq.com',
          'secret': 'corpsecret-demo',
          'config': '{"corpid":"corp-x","agentid":1000002,"touser":"@all"}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '测试并保存'));
      await tester.pumpAndSettle();

      final saved = store.rows.firstWhere((r) => r['id'] == 'app-1');
      final config = Map<String, dynamic>.from(saved['config'] as Map);
      expect(
        config['corpid'],
        'corp-x',
        reason: '描述符未就绪时重建 config 会抹掉已存凭据（推送从此静默失败）',
      );
    });

    testWidgets('必填项未填 → 保存被拦下并指名缺哪个字段（不再只报"保存失败"）', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      store.rows = [
        {
          'id': 'app-1',
          'name': '企微应用A',
          'app_type': 'wecom_app',
          'base_url': 'https://qyapi.weixin.qq.com',
          'secret': 's',
          'config': '{}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '测试并保存'));
      await tester.pumpAndSettle();

      final toast = find.descendant(
        of: find.byType(SnackBar),
        matching: find.byType(Text),
      );
      final message = tester.widget<Text>(toast.first).data ?? '';
      expect(message, contains('必填项未填写'));
      // agentid 有默认值 0、touser 非必填：都不该出现在报错里，只有 corpid 缺
      expect(
        message,
        contains('企业 ID（corpid）'),
        reason: '报错要点名缺的字段（用 ARB 显示名，不是 corpid 这种存储键）',
      );
      expect(message, isNot(contains('应用 agentid（纯数字）')));
      expect(message, isNot(contains('appChannelCorpidLabel')));
      // 输入框标签本身也要渲染得出来（描述符发的是 ARB 资源名）
      expect(find.text('企业 ID（corpid）'), findsOneWidget);
    });

    testWidgets('切换类型重置扩展参数：corpid 不会带进飞书通道', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      store.rows = [
        {
          'id': 'app-1',
          'name': '企微应用A',
          'app_type': 'wecom_app',
          'base_url': 'https://qyapi.weixin.qq.com',
          'secret': 's',
          'config': '{"corpid":"corp-x","agentid":1,"touser":"@all"}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      expect(find.text('corp-x'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_right).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('飞书自建应用'));
      await tester.pumpAndSettle();

      expect(find.text('corp-x'), findsNothing, reason: '旧类型的凭据残留会让用户以为配过了');
      expect(find.text('企业 ID（corpid）'), findsNothing);
      expect(find.text('应用 app_id'), findsOneWidget, reason: '飞书字段应换上来');
      // 一条通道：3 基础字段 + 3 描述符字段
      expect(find.byType(TextField), findsNWidgets(6));
    });

    testWidgets('飞书三字段逐个回填 + 编辑后原样落库（漏绑控制器就会写空）', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      store.rows = [
        {
          'id': 'app-f',
          'name': '飞书应用F',
          'app_type': 'feishu_app',
          'base_url': 'https://open.feishu.cn',
          'secret': 'app-secret',
          'config':
              '{"app_id":"cli_x","receive_id_type":"chat_id",'
              '"receive_id":"oc_y"}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final texts = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller?.text ?? '')
          .toList();
      expect(
        texts,
        containsAll(['cli_x', 'chat_id', 'oc_y']),
        reason: '三个字段都各自绑到了控制器；少绑一个就是"输入框空白 + 保存写空"',
      );

      await tester.tap(find.widgetWithText(TextButton, '测试并保存'));
      await tester.pumpAndSettle();
      final saved = store.rows.firstWhere((r) => r['id'] == 'app-f');
      final config = Map<String, dynamic>.from(saved['config'] as Map);
      expect(config['app_id'], 'cli_x');
      expect(config['receive_id_type'], 'chat_id');
      expect(config['receive_id'], 'oc_y');
    });
  });

  // T04：「仅测试」与「测试并保存」是两个动作，且测试结论必须落到健康单点
  // （首页/通道状态页只认那一份）。此前只有"保存后自动测试"一条路，而且测出的
  // 失败只活在弹条里 ⇒ 配置异常的通道在首页永远是 unknown。
  group('AppChannelSettingsPage – 仅测试 / 测试并保存（T04）', () {
    void stubTest({required bool success, required List<String> calls}) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName), (
            call,
          ) async {
            calls.add(call.method);
            if (call.method == 'testAppChannel') {
              return {'success': success, 'message': success ? 'ok' : '凭据无效'};
            }
            if (call.method == 'getChannelDescriptors') {
              return descriptorCallResponse(call);
            }
            return null;
          });
    }

    Future<void> seedOneChannel() async {
      store.rows = [
        {
          'id': 'app-1',
          'name': '企微应用A',
          'app_type': 'wecom_app',
          'base_url': 'https://qyapi.weixin.qq.com',
          'secret': 's',
          'config': '{"corpid":"corp-x","agentid":1,"touser":"@all"}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
    }

    testWidgets('仅测试：跑一次测试并记健康度，但绝不落库', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final calls = <String>[];
      stubTest(success: true, calls: calls);
      await seedOneChannel();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.enterText(_fieldName(), '改了名但只想试一下');
      // 只判"点击之后"的调用：进页面时的 loadChannels/描述符拉取会先写进库里一条
      // setAppChannels（初始化同步），不清掉就成了「谁先跑」的假阳性。
      calls.clear();
      await tester.tap(find.widgetWithText(TextButton, '仅测试'));
      await tester.pumpAndSettle();

      expect(calls, contains('testAppChannel'));
      expect(
        calls,
        isNot(contains('setAppChannels')),
        reason: '「仅测试」按定义不落库：写了库就等于偷偷替用户保存了半成品',
      );
      expect(store.rows.first['name'], '企微应用A');
      expect(
        GetIt.instance<ChannelHealthStore>().of('app', 'app-1')?.reachable,
        isTrue,
        reason: '测试结论没记进单点 ⇒ 首页说不出这条通道的状态',
      );
    });

    testWidgets('测试失败照样保存，并把异常落进健康单点（冒到首页）', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final calls = <String>[];
      stubTest(success: false, calls: calls);
      await seedOneChannel();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.enterText(_fieldName(), '改好的名字');
      await tester.tap(find.widgetWithText(TextButton, '测试并保存'));
      await tester.pumpAndSettle();

      expect(
        store.rows.first['name'],
        '改好的名字',
        reason:
            '测试失败不该回滚保存：配置是对的、只是这一刻连不上，'
            '回滚会把用户的有效编辑一起吞掉（roadmap T04 的决策）',
      );
      expect(
        GetIt.instance<ChannelHealthStore>().of('app', 'app-1')?.reachable,
        isFalse,
        reason: '失败必须留痕，否则首页的三态永远是 unknown',
      );
    });
  });

  // T05：长按卡片标题行的动作表。
  group('AppChannelSettingsPage – 长按菜单（T05）', () {});
}

/// 卡片内输入框的 build 顺序是 name → （类型选择器）→ baseUrl → secret → 扩展参数，
/// 所以"第一个 TextField"就是通道名。单卡通例用它是为了不把 l10n 标签文本抄进测试
/// （标签由描述符的 ARB 资源名驱动，抄一次就会随原生表漂移）。
Finder _fieldName() => find.byType(TextField).first;

/// 按标签文本定位扩展参数输入框。Material 把 hintText 当浮动标签留着，
/// 空值时 `find.text(标签)` 仍在树里（既有断言 :461 依赖同一条行为）。
Finder _fieldWithLabel(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextField));

/// 测试用 fake store（与 app_channel_service_test 相同模式）
class FakeAppChannelStoreForPage implements AppChannelStore {
  List<Map<String, dynamic>> rows = [];

  @override
  Future<List<Map<String, dynamic>>> getAppChannels() async => rows;

  @override
  Future<void> saveAppChannels(List<Map<String, dynamic>> channels) async {
    rows = List.of(channels);
  }
}
