import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/app_channel_list_page.dart';
import 'package:notice_transmit/services/app_channel_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 自建应用通道列表页的类型标签。
///
/// 曾经的写法是 `appType == 'feishu_app' ? 飞书应用 : 企业微信应用`——
/// **把否定分支当默认值用**。于是任何未识别的 app_type（原生新增通道、
/// DB 被外部改过、脏数据）都会被标成「企业微信应用」，用户照着企微的引导去填
/// 另一家的凭据，界面上没有任何线索指向真相。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAppChannelStore store;
  late AppChannelService service;

  Map<String, dynamic> row(String id, String appType, String name) => {
    'id': id,
    'name': name,
    'app_type': appType,
    'base_url': 'https://example.com',
    'secret': null,
    'config': '{}',
    'message_format': 'default',
    'enabled': 1,
  };

  Future<void> open(WidgetTester tester) async {
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // loadChannels() 末尾会 setAppChannels 同步原生：widget 测试里若不给该通道装
    // mock handler，invokeMethod 永不返回，pumpAndSettle 会一直挂到 10 分钟超时。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.fnthink.notice/notification'),
          (call) async => null,
        );
    store = _FakeAppChannelStore();
    service = AppChannelService(store: store);
    GetIt.instance.allowReassignment = true;
    if (GetIt.instance.isRegistered<AppChannelService>()) {
      GetIt.instance.unregister<AppChannelService>();
    }
    GetIt.instance.registerLazySingleton<AppChannelService>(() => service);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.fnthink.notice/notification'),
          null,
        );
    GetIt.instance.reset();
  });

  testWidgets('已知类型显示各自名称', (tester) async {
    store.rows = [row('a', 'wecom_app', '企微A'), row('b', 'feishu_app', '飞书B')];
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
