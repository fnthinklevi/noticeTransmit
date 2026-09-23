import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/app_channel_settings_page.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/services/app_channel_service.dart';
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

  Widget buildApp() {
    return const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('zh'),
      home: AppChannelSettingsPage(),
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

    testWidgets('两条通道渲染：卡片数与输入框数量正确', (tester) async {
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
      expect(find.byType(TextField), findsNWidgets(12));
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

      await tester.tap(find.widgetWithText(TextButton, '保存'));
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

      await tester.tap(find.widgetWithText(TextButton, '保存'));
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

      await tester.tap(find.widgetWithText(TextButton, '保存'));
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

      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pumpAndSettle();
      final saved = store.rows.firstWhere((r) => r['id'] == 'app-f');
      final config = Map<String, dynamic>.from(saved['config'] as Map);
      expect(config['app_id'], 'cli_x');
      expect(config['receive_id_type'], 'chat_id');
      expect(config['receive_id'], 'oc_y');
    });

    testWidgets('新增按钮的类型列表来自描述符（不再硬编码两个类型）', (tester) async {
      store.rows = [
        {
          'id': 'app-1',
          'name': 'A',
          'app_type': 'wecom_app',
          'base_url': 'https://qyapi.weixin.qq.com',
          'secret': null,
          'config': '{}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, '企业微信自建应用'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '飞书自建应用'), findsOneWidget);
    });
  });
}

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
