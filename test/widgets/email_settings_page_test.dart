import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/email_settings_page.dart';
import 'package:notice_transmit/services/channel_descriptor_service.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/services/email_service.dart';
import 'package:notice_transmit/widgets/card_action_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/channel_descriptor_fixtures.dart';
import '../test_setup.dart';

/// 邮件页（列表 + 单条编辑弹层）。
///
/// 钉两类事情：
/// 1. **T04 的结论链路**：「测试」与「仅测试」都要落健康单点，但都不许写库；
///    删除要连带清掉那条记录（id 复用不能让旧徽标复活）。
/// 2. **T08-C2 的表单事实来源**：控件、必填、提示、预置档位都来自 email 描述符。
///    台架给的是**导出快照**（`channel_descriptors.json`，由原生表生成），
///    所以"原生改了表而页面还按旧清单渲染"会立刻红。
///
/// ⚠ `_FakeEmailStore` 刻意照 `DatabaseHelper.saveEmailChannels` 做 camelCase→snake_case
/// 翻译：不做翻译的话，"写进去的形状"与"读回来的形状"在测试里永远一致，
/// 而真实世界这两处正是键名漂移最容易出事的地方（㊹ 的备份恢复缺陷就是这么来的）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeEmailStore store;
  late ChannelHealthStore health;
  late EmailService service;

  /// 原生描述符是否给得到（T08-C2：拉不到时**不许**开一张空表单）
  var serveDescriptors = true;

  /// 数据库形状（snake_case）的一条邮件通道
  List<Map<String, dynamic>> seedRows({int count = 1}) => [
    for (var i = 0; i < count; i++)
      {
        // 种子必须给**不同**的 id：两条同 id 会让"另一条不许变"这类断言自欺欺人
        'id': 'em-${i + 1}',
        'name': i == 0 ? '值班邮箱' : '备用邮箱',
        'enabled': 1,
        'role': 'primary',
        'smtp_host': 'smtp.example.com',
        'smtp_port': 465,
        'username': 'alert@example.com',
        'password': 'auth-code',
        'from_email': 'alert@example.com',
        'to_email': 'oncall@example.com',
        'use_ssl': 1,
        'subject_template': null,
        'body_template': null,
      },
  ];

  /// 页面构造参数用的是 UI 形状（camelCase），与 `EmailService.loadChannels()` 不同。
  /// ⚠ 必须**从同一批 DB 行解码出来**：另写一份字面量的话，"页面看到的"与
  /// "库里的"就不是同一条数据，改一条不许动另一条这类断言会自欺欺人（实测先红在此）。
  List<Map<String, dynamic>> uiFromDb(List<Map<String, dynamic>> rows) => [
    for (final r in rows)
      {
        'id': r['id'],
        'name': r['name'],
        'enabled': r['enabled'] == 1,
        'role': r['role'],
        'smtpHost': r['smtp_host'],
        'smtpPort': r['smtp_port'],
        'username': r['username'],
        'password': r['password'],
        'fromEmail': r['from_email'],
        'toEmail': r['to_email'],
        'useSSL': r['use_ssl'] == 1,
      },
  ];

  List<Map<String, dynamic>> uiChannels({int count = 1}) =>
      uiFromDb(seedRows(count: count));

  final calls = <String>[];
  var testSucceeds = true;

  Future<void> open(WidgetTester tester, {int count = 1}) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: EmailSettingsPage(emailChannels: uiChannels(count: count)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester, {int count = 1}) async {
    await open(tester, count: count);
    await tester.tap(find.widgetWithText(InkWell, '编辑').first);
    await tester.pumpAndSettle();
  }

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    serveDescriptors = true;
    testSucceeds = true;
    calls.clear();
    // ⚠ 两个原生通道都要桩（secure storage 缺桩会让 await 永远不返回）
    stubNativeChannels(
      onCall: (call) async {
        calls.add(call.method);
        if (call.method == 'getChannelDescriptors') {
          return serveDescriptors ? descriptorCallResponse(call) : null;
        }
        if (call.method == 'testEmail') {
          return {
            'success': testSucceeds,
            'message': testSucceeds ? '已送达' : '535 认证失败',
          };
        }
        return null;
      },
    );
    GetIt.instance.allowReassignment = true;
    // ⚠ 顺序要紧：`registerChannelPageServices()` 会**覆盖注册**描述符服务与健康单点，
    // 放在后面就会把测试手里那个 health 换成另一个实例 ⇒ 断言永远读到 null（假红）。
    registerChannelPageServices();
    store = _FakeEmailStore();
    service = EmailService(store: store);
    health = ChannelHealthStore();
    GetIt.instance.registerSingleton<ChannelHealthStore>(health);
    GetIt.instance.registerSingleton<EmailService>(service);
    await health.load();
    // 页面读的是**已装载**的描述符（真机上由 splash 的装配链 await 过）。
    // 不 load 就等于让页面永远走"元数据未就绪"分支，测的其实是降级路径。
    await GetIt.instance<ChannelDescriptorService>().load();
  });

  tearDown(() {
    clearNativeChannelStubs();
    GetIt.instance.reset();
  });

  group('测试结论落单点（T04）', () {
    testWidgets('卡片「测试」：失败记进单点并在列表留痕，但一个字节的库都不写', (tester) async {
      testSucceeds = false;
      store.rows = seedRows();
      await open(tester);
      final before = store.snapshot();

      await tester.tap(find.widgetWithText(InkWell, '测试').first);
      await tester.pumpAndSettle();

      expect(calls, contains('testEmail'));
      expect(
        store.snapshot(),
        before,
        reason: '「测试」按定义不落库：写了库就等于偷偷保存了用户没确认的半成品',
      );
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
      testSucceeds = false;
      store.rows = seedRows();
      await openEditor(tester);
      expect(find.widgetWithText(TextButton, '仅测试'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '测试并保存'), findsOneWidget);

      calls.clear();
      final before = store.snapshot();
      await tester.tap(find.widgetWithText(TextButton, '仅测试'));
      await tester.pumpAndSettle();

      expect(calls, contains('testEmail'));
      expect(store.snapshot(), before, reason: '弹窗里改到一半的授权码不该被写进加密库');
      expect(health.of('email', 'em-1')?.reachable, isFalse);
    });

    testWidgets('删除通道要连着清掉它的健康记录（id 复用不能让徽标复活）', (tester) async {
      store.rows = seedRows();
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
      expect(store.rows, isEmpty, reason: '确认之后必须真的删掉');
    });
  });

  group('单条写入咽喉（T08-C2）', () {
    testWidgets('改一条的名称 ⇒ 另一条在库里一个字节都不许变', (tester) async {
      store.rows = seedRows(count: 2);
      await open(tester, count: 2);

      await tester.tap(find.widgetWithText(InkWell, '编辑').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '通道名称'),
        '改过名字的值班邮箱',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '测试并保存'));
      await tester.pumpAndSettle();

      expect(store.rows, hasLength(2));
      expect(
        store.rows.firstWhere((r) => r['id'] == 'em-1')['name'],
        '改过名字的值班邮箱',
      );
      expect(
        store.rows.firstWhere((r) => r['id'] == 'em-2')['name'],
        '备用邮箱',
        reason: '页面攥着整表快照重写时，"只改一条"会覆盖别的通道（数据丢失级）',
      );
    });

    testWidgets('启停只翻这一条，其余字段原样', (tester) async {
      store.rows = seedRows(count: 2);
      await open(tester, count: 2);

      await tester.tap(find.byType(CupertinoSwitch).first);
      await tester.pumpAndSettle();

      final off = store.rows.firstWhere((r) => r['id'] == 'em-1');
      final other = store.rows.firstWhere((r) => r['id'] == 'em-2');
      expect(off['enabled'], 0);
      expect(other['enabled'], 1, reason: '启停整表 = 把用户的开关状态连带改掉');
      expect(off['smtp_host'], 'smtp.example.com');
      expect(off['password'], 'auth-code');
    });

    testWidgets('编辑保存不得重置启停与主备角色（P7 的老教训）', (tester) async {
      final rows = [
        seedRows()[0],
        {
          ...seedRows()[0],
          'id': 'em-2',
          'name': '备用邮箱',
          'enabled': 0,
          'role': 'backup',
        },
      ];
      store.rows = rows;
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: EmailSettingsPage(emailChannels: uiFromDb(rows)),
        ),
      );
      await tester.pumpAndSettle();

      // 编辑第二条（停用的那条），只改名字
      await tester.tap(find.widgetWithText(InkWell, '编辑').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '通道名称'), '备用邮箱改名');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '测试并保存'));
      await tester.pumpAndSettle();

      final row = store.rows.firstWhere((r) => r['id'] == 'em-2');
      expect(row['name'], '备用邮箱改名');
      expect(
        row['enabled'],
        0,
        reason: '旧实现每次保存都重建 EmailChannel 且没带 enabled ⇒ 已关闭的通道被偷偷打开，开始收推送',
      );
      expect(row['role'], 'backup', reason: '同理：主备角色不能被编辑保存抹回 primary');
      expect(
        store.rows.firstWhere((r) => r['id'] == 'em-1')['enabled'],
        1,
        reason: '只改第二条，第一条的启停状态不许被顺手改掉',
      );
    });

    testWidgets('库里没有这条 ⇒ setEnabled 不写任何数据', (tester) async {
      store.rows = seedRows();
      await open(tester);
      final before = store.snapshot();

      expect(await service.setEnabled('no-such-id', false), isFalse);
      expect(store.snapshot(), before, reason: '找不到却把表重写一遍 = 无谓的写放大与风险');
    });
  });

  group('表单来自描述符（T08-C2）', () {
    testWidgets('必填缺失按描述符清单点名，且叫得出名字（不露裸键名）', (tester) async {
      store.rows = seedRows();
      await openEditor(tester);

      await tester.enterText(find.widgetWithText(TextField, 'SMTP 服务器'), '');
      await tester.enterText(find.widgetWithText(TextField, '收件人'), '  ');
      await tester.pumpAndSettle();
      final before = store.snapshot();
      await tester.tap(find.widgetWithText(TextButton, '测试并保存'));
      await tester.pumpAndSettle();

      final snack = find.textContaining('保存失败：请填写');
      expect(snack, findsOneWidget, reason: '校验没过必须点名，且不能保存');
      final text = tester.widget<Text>(snack.first).data ?? '';
      expect(text, contains('SMTP 服务器'));
      expect(text, contains('收件人'), reason: '点不出名字就等于让用户在 10 个框里自己找');
      expect(text, isNot(contains('smtpHost')), reason: '露出裸键名 = 标签映射漏了');
      expect(store.snapshot(), before, reason: '校验没过不得写库');
    });

    testWidgets('开关字段画成 CupertinoSwitch、授权码字段带遮罩', (tester) async {
      store.rows = seedRows();
      await openEditor(tester);

      // 列表页自己有一条开关，弹层里应有 useSSL 这一条
      expect(find.byType(CupertinoSwitch), findsWidgets);
      final obscured = tester
          .widgetList<TextField>(find.byType(TextField))
          .where((t) => t.obscureText);
      expect(obscured, isNotEmpty, reason: 'SMTP 授权码是凭据：明文显示等于把口令摊在屏幕上');
    });

    testWidgets('预置档位来自 ARB：点「标准」填进的是当前语言的正文', (tester) async {
      store.rows = seedRows();
      await openEditor(tester);

      final chip = find.widgetWithText(ActionChip, '标准');
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      final body = find.widgetWithText(TextField, '正文模板（可选）');
      expect(body, findsOneWidget);
      final controller = tester.widget<TextField>(body.first).controller!;
      expect(controller.text, contains('应用：'));
      expect(
        controller.text,
        isNot(contains('%title%\n%content%\n%time%\n%deviceName%')),
        reason: '档位正文没走 ARB（英文界面会拿到中文，反之拿到变量原文）',
      );
    });

    testWidgets('描述符拉不到 ⇒ 不开空表单、不写库，并把话说清楚', (tester) async {
      store.rows = seedRows();
      serveDescriptors = false;
      final before = store.snapshot();
      // setUp 已经把描述符装载好了；这条用例要的是"从来没装到"，所以换一个空实例
      GetIt.instance.unregister<ChannelDescriptorService>();
      GetIt.instance.registerLazySingleton<ChannelDescriptorService>(
        ChannelDescriptorService.new,
      );
      await open(tester);

      await tester.tap(find.widgetWithText(InkWell, '编辑').first);
      await tester.pumpAndSettle();

      expect(find.text('添加邮件通道'), findsNothing);
      expect(find.text('编辑邮件通道'), findsNothing);
      expect(
        find.textContaining('通道元数据未就绪'),
        findsOneWidget,
        reason: '静默开一张空表单 = 用户点保存就把已存配置写空',
      );
      expect(store.snapshot(), before);
    });
  });

  // T05：邮件列表卡是只读的，所以长按菜单里的三个动作在这一页都必须是真动作。
  group('长按菜单（T05）', () {
    testWidgets('长按出「编辑 / 复制 / 删除」；复制换新 id 并立刻落库', (tester) async {
      store.rows = seedRows();
      await open(tester);

      await tester.longPress(find.text('值班邮箱'));
      await tester.pumpAndSettle();
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

/// 照 `DatabaseHelper.saveEmailChannels` 的键名映射写死的伪存储。
class _FakeEmailStore implements EmailChannelStore {
  List<Map<String, dynamic>> rows = [];

  String snapshot() => rows.toString();

  static Map<String, dynamic> encode(Map<String, dynamic> c) => {
    'id': c['id'],
    'name': c['name'],
    'enabled': (c['enabled'] == true || c['enabled'] == 1) ? 1 : 0,
    'role': c['role'] ?? 'primary',
    'smtp_host': c['smtpHost'] ?? '',
    'smtp_port': c['smtpPort'] ?? 465,
    'username': c['username'] ?? '',
    'password': c['password'] ?? '',
    'from_email': c['fromEmail'] ?? '',
    'to_email': c['toEmail'] ?? '',
    'use_ssl': (c['useSSL'] != false) ? 1 : 0,
    'subject_template': c['subjectTemplate'],
    'body_template': c['bodyTemplate'],
  };

  @override
  Future<List<Map<String, dynamic>>> getEmailChannels() async => rows;

  @override
  Future<void> saveEmailChannels(List<Map<String, dynamic>> channels) async {
    var i = 0;
    rows = channels.map((c) {
      final row = encode(c);
      final id = row['id']?.toString() ?? '';
      // 与真实实现同一条兜底：空主键会让两条通道以同一 id 落库并互相覆盖
      if (id.isEmpty) row['id'] = 'em_fake_$i';
      i++;
      return row;
    }).toList();
  }
}
