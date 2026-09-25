import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/email_settings_page.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/services/email_service.dart';
import 'package:notice_transmit/widgets/card_action_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T04：邮件页的测试结论必须落到**健康单点**，且「仅测试」不许顺手写库。
///
/// 邮件族此前的状态是"失败只弹一条提示"：提示消失后什么都没留下，首页与通道状态页
/// 于是永远说这条通道 unknown/正常。三族通道同一口径靠的就是这一条链路。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannelName = 'com.fnthink.notice/notification';
  late _FakeEmailStore store;
  late ChannelHealthStore health;

  List<Map<String, dynamic>> oneChannel() => [
    {
      'id': 'em-1',
      'name': '值班邮箱',
      'enabled': true,
      'smtpHost': 'smtp.example.com',
      'smtpPort': 465,
      'username': 'alert@example.com',
      'password': 'auth-code',
      'fromEmail': 'alert@example.com',
      'toEmail': 'oncall@example.com',
      'useSSL': true,
    },
  ];

  void stubTest({required bool success, required List<String> calls}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(methodChannelName), (
          call,
        ) async {
          calls.add(call.method);
          if (call.method == 'testEmail') {
            return {
              'success': success,
              'message': success ? '已送达' : '535 认证失败',
            };
          }
          return null;
        });
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: EmailSettingsPage(emailChannels: oneChannel()),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    store = _FakeEmailStore();
    health = ChannelHealthStore();
    GetIt.instance.registerSingleton<ChannelHealthStore>(health);
    GetIt.instance.registerSingleton<EmailService>(EmailService(store: store));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(methodChannelName), null);
  });

  group('EmailSettingsPage – 测试结论落单点（T04）', () {
    testWidgets('卡片「测试」：失败记进单点并在列表留痕，但一个字节的库都不写', (tester) async {
      final calls = <String>[];
      stubTest(success: false, calls: calls);
      await open(tester);

      await tester.tap(find.widgetWithText(InkWell, '测试').first);
      await tester.pumpAndSettle();

      expect(calls, contains('testEmail'));
      expect(store.rows, isEmpty, reason: '「测试」按定义不落库：写了库就等于偷偷保存了用户没确认的半成品');
      expect(
        health.of('email', 'em-1')?.reachable,
        isFalse,
        reason: '失败没落单点 ⇒ 首页说不出这条通道的状态（T04 的冒泡链路断了）',
      );
      expect(
        find.text('❌ 验证失败'),
        findsOneWidget,
        reason: '结论得在列表里留痕，不能只活一条会自己消失的弹条',
      );
    });

    testWidgets('弹窗「仅测试」：测的是没保存的表单值，但结论照样落单点', (tester) async {
      final calls = <String>[];
      stubTest(success: false, calls: calls);
      await open(tester);

      await tester.tap(find.widgetWithText(InkWell, '编辑').first);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, '仅测试'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '测试并保存'), findsOneWidget);

      calls.clear();
      await tester.tap(find.widgetWithText(TextButton, '仅测试'));
      await tester.pumpAndSettle();

      expect(calls, contains('testEmail'));
      expect(store.rows, isEmpty, reason: '「仅测试」不保存：弹窗里改到一半的授权码不该被写进加密库');
      expect(
        health.of('email', 'em-1')?.reachable,
        isFalse,
        reason: '此前这条路径只弹提示 ⇒ 退出弹窗后异常就查无实据了',
      );
    });

    testWidgets('删除通道要连着清掉它的健康记录（id 复用不能让徽标复活）', (tester) async {
      final calls = <String>[];
      stubTest(success: true, calls: calls);
      await health.record('email', 'em-1', reachable: true, latencyMs: 9);
      await open(tester);
      expect(health.of('email', 'em-1'), isNotNull, reason: '前提：有一条待删的记录');

      await tester.tap(find.widgetWithText(InkWell, '删除').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '删除').last);
      await tester.pumpAndSettle();

      expect(
        health.of('email', 'em-1'),
        isNull,
        reason: '记录留着，日后 id 复用（从旧备份恢复）时徽标会复活成上一条通道的状态',
      );
    });
  });

  // T05：邮件列表卡是只读的，所以长按菜单里的三个动作在这一页都必须是真动作。
  group('EmailSettingsPage – 长按菜单（T05）', () {
    testWidgets('长按出「编辑 / 复制 / 删除」；复制换新 id 并立刻落库', (tester) async {
      final calls = <String>[];
      stubTest(success: true, calls: calls);
      await open(tester);

      await tester.longPress(find.text('值班邮箱'));
      await tester.pumpAndSettle();
      // 三项都必须**在弹层里**：卡片自己就挂着「编辑/删除」两个动作芯片，
      // 不限定的 finder 会把它们数进来（第一次写就踩到了）。
      Finder inSheet(String label) => find.descendant(
        of: find.byType(CardActionSheet),
        matching: find.text(label),
      );
      expect(inSheet('编辑'), findsOneWidget);
      expect(inSheet('复制'), findsOneWidget);
      expect(inSheet('删除'), findsOneWidget);

      calls.clear();
      await tester.tap(inSheet('复制'));
      await tester.pumpAndSettle();

      expect(find.text('值班邮箱 副本'), findsOneWidget);
      expect(
        store.rows,
        hasLength(2),
        reason: '这一页没有"未保存"状态：复制完就得落库，否则退出页面那条就没了',
      );
      expect(
        store.rows.map((r) => r['id']).toSet(),
        hasLength(2),
        reason: '两条同 id ⇒ 健康徽标与送达归属互相顶掉，编辑/删除也会一次中两条',
      );
      expect(
        store.rows[1]['password'],
        store.rows[0]['password'],
        reason: '复制的意义就是不用再填一遍授权码',
      );
    });
  });
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
