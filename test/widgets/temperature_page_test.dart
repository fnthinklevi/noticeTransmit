import 'package:notice_transmit/services/device_info_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:notice_transmit/widgets/engine_page_sections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/widgets/card_action_sheet.dart';
import 'package:notice_transmit/pages/temperature_page.dart';
import 'package:notice_transmit/services/engine_rule_codec.dart';
import 'package:notice_transmit/services/temperature_service.dart';
import 'package:notice_transmit/widgets/pull_to_refresh_list.dart';
import 'package:notice_transmit/widgets/app_root.dart';

import '../support/engine_rule_store_fake.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T16：温度规则页「保存后不刷新 / 开关点完弹回」。
///
/// 根因不是漏 `setState`：本页是 `_pushPage` 推进去的路由，父页 `setState` 重建不到它；
/// 而它过去只读构造时传进来的 `List` 快照，`TemperatureService` 的每个写操作又是
/// `_rules = [..._rules, rule]` **整体换新** —— 快照与被换掉的列表就此分家，
/// 界面上永远停在进页那一刻的内容。回调里的 `setState(() {})` 刷的是父页，等于没刷。
///
/// 现在页面订阅服务。因此这些用例的共同判据是：
/// **只改服务、不重新 pumpWidget（不重建父树），界面必须自己跟上。**
/// 一旦有人把订阅改回"传快照"，这四条会立刻全红。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TemperatureService service;
  late MemoryRuleStore store;

  Widget buildApp() {
    return const AppRoot(
      locale: Locale('zh'),
      dark: false,
      home: TemperaturePage(),
    );
  }

  Map<String, dynamic> rule({String id = 'r1', bool enabled = true}) => {
    'id': id,
    'type': 'battery_temp_above',
    'value': 45,
    'enabled': enabled,
    'title': '电池过热',
    'content': '',
  };

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    // 服务每次写都会落库 + 刷镜像 + invokeMethod('refreshEngineRules')。**在 testWidgets
    // 里不给通道装 mock handler，那个 await 就永远不返回**（实测：四条用例全部 did not
    // complete；同一个调用放在普通 test() 里则会立刻 MissingPluginException 返回）。
    // 存储注伪：T20 起规则落 engine_rules 表，真库要走 sqflite ffi，页测试不该依赖它。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.fnthink.notice/notification'),
          (call) async => null,
        );
    store = MemoryRuleStore();
    service = TemperatureService(store: store);
    GetIt.instance.registerSingleton<TemperatureService>(service);
    // 顶部实时读数要读 T17 的快照：注册真的 DeviceInfoService 就够 —— 通道 mock 回 null，
    // 页面必须显示「这台设备读不到」，而不是 0℃ / 0%（那一格本来就有的判据）。
    GetIt.instance.registerSingleton<DeviceInfoService>(DeviceInfoService());
    await service.loadSettings();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.fnthink.notice/notification'),
          null,
        );
    await GetIt.instance.reset();
  });

  testWidgets('服务侧新增规则 → 界面立刻出现（不重建父树）', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('暂无温度规则'), findsOneWidget);

    await service.addRule(rule());
    await tester.pumpAndSettle();

    expect(find.text('电池过热'), findsOneWidget);
    expect(find.textContaining('暂无温度规则'), findsNothing);
  });

  testWidgets('弹窗保存一条规则 → 列表出现该条（用户看到的"保存不刷新"）', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    // T90 片14：这颗「添加」从此是共享外壳 `IosFormDialog` 里的 `CupertinoDialogAction`。
    // ⚠ 换件打断 finder —— 与片8 那四条红同一次课：**页面级用例正是这一类的检出点**
    //   （外壳自己的用例只测形状，测不到"按下去之后服务里真的多了一条"）。
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(CupertinoAlertDialog),
        matching: find.widgetWithText(CupertinoDialogAction, '添加'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsOneWidget);
    expect(service.rules, hasLength(1), reason: '服务侧确实写了，问题只可能出在刷新链路');
  });

  testWidgets('点规则开关 → 开关停在新位置（此前"点完弹回"）', (tester) async {
    await service.restoreSettings(rules: [rule(enabled: false)]);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // 页里现在有两个开关：分组的"温度推送通知"总开关 + 每条规则自己的开关。
    // 这条测的是**规则**开关弹不弹回 ⇒ 必须限定在规则行（Slidable）里找，
    // 用位置（.last）会在分区顺序调整时悄悄测到总开关。
    final sw = find.descendant(
      of: find.byType(Slidable),
      matching: find.byType(CupertinoSwitch),
    );
    expect(tester.widget<CupertinoSwitch>(sw).value, isFalse);

    await tester.tap(sw);
    await tester.pumpAndSettle();

    expect(
      tester.widget<CupertinoSwitch>(sw).value,
      isTrue,
      reason: '开关回弹 = 界面读的还是进页那一刻的旧列表',
    );
    expect(service.rules.single['enabled'], isTrue);
  });

  testWidgets('删除规则 → 条目消失；备份恢复同理（两条都是换新列表的操作）', (tester) async {
    await service.restoreSettings(
      rules: [
        rule(),
        rule(id: 'r2'),
      ],
    );
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(2));

    await service.deleteRule('r1');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);

    await service.restoreSettings(rules: [rule(id: 'r9')]);
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
    expect(service.rules.single['id'], 'r9');
  });

  // T05：规则卡的滑出动作（删除/暂停）原本要先横向拖一下才看得见，
  // 长按菜单把同一批动作 + 修改/复制收进一个不需要发现的入口。
  testWidgets('长按规则行 ⇒ 修改/复制/暂停/删除；复制换新 id', (tester) async {
    await service.addRule(rule());
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('电池过热'));
    await tester.pumpAndSettle();
    Finder inSheet(String label) => find.descendant(
      of: find.byType(CardActionSheet),
      matching: find.text(label),
    );
    expect(inSheet('编辑'), findsOneWidget);
    expect(inSheet('复制'), findsOneWidget);
    expect(inSheet('停用'), findsOneWidget, reason: '规则当前是启用态 ⇒ 给"停用"');
    expect(inSheet('删除'), findsOneWidget);

    await tester.tap(inSheet('复制'));
    await tester.pumpAndSettle();

    final rules = service.rules;
    expect(rules, hasLength(2));
    expect(
      rules.map((r) => r['id']).toSet(),
      hasLength(2),
      reason: 'updateRule/deleteRule 都按 id 找，两条同 id 会一次改中两条',
    );
    expect(rules[1]['value'], rules[0]['value'], reason: '复制要带走阈值，否则用户得再拖一次滑块');
  });

  // T06：这一族以前"点一下就没了"，而且滑出与长按两条路都没有确认。
  testWidgets('长按删除先弹确认；取消不留痕，确认才真删', (tester) async {
    await service.addRule(rule());
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    Finder inSheet(String label) => find.descendant(
      of: find.byType(CardActionSheet),
      matching: find.text(label),
    );
    await tester.longPress(find.text('电池过热'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet('删除'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(CupertinoDialogAction, '删除'),
      findsWidgets,
      reason: '菜单里点删除就直接删 ⇒ 确认被绕开',
    );
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '取消').last);
    await tester.pumpAndSettle();
    expect(service.rules, hasLength(1), reason: '取消不许改数据');

    await tester.longPress(find.text('电池过热'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '删除').last);
    await tester.pumpAndSettle();
    expect(service.rules, isEmpty, reason: '确认之后必须真的删掉（并落盘）');
    expect(
      store.rows[EngineRuleCodec.familyTemperature],
      isEmpty,
      reason: '内存空了而存储还有行 = 重启后规则复活',
    );
  });

  testWidgets('换一个服务实例重读（= 重启进程）：规则原样回来', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await service.addRule(rule());
    await tester.pumpAndSettle();

    final reopened = TemperatureService(store: store);
    await reopened.loadSettings();
    expect(reopened.rules.map((r) => r['id']).toList(), [
      'r1',
    ], reason: '写操作只改内存列表的话，这条必红');
  });

  group('T25：温度试跑入口', () {
    const channel = MethodChannel('com.fnthink.notice/notification');

    /// 装一个只回这份载荷的通道桩（原生那侧的求值结果，这里不重跑判据）。
    Future<void> stubPreview(
      WidgetTester tester,
      Map<Object?, Object?>? payload,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'previewTemperatureRule') return payload;
            return null;
          });
    }

    testWidgets('命中：弹层给出原生渲染的标题，并列出三步走查', (tester) async {
      await stubPreview(tester, {
        'ok': true,
        'fired': true,
        'temps': {'battery_temp_above': 52.0},
        'steps': [
          {'phase': 'baseline', 'outcome': 'BASELINE'},
          {'phase': 'below', 'outcome': 'NOT_TRIGGERED'},
          {'phase': 'current', 'outcome': 'FIRE'},
        ],
        'ruleCount': 1,
        'ruleId': 'r1',
        'type': 'battery_temp_above',
        'threshold': 45,
        'temperatureC': 52.0,
        'title': '电池过热',
        'content': '电池温度 52.0℃',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.science_outlined));
      await tester.pumpAndSettle();

      expect(find.text('温度告警试跑'), findsOneWidget);
      // 标题/正文来自原生那条渲染抄本，Dart 不参与拼判据。
      expect(find.textContaining('会触发：电池过热'), findsOneWidget);
      expect(find.textContaining('首轮只记录基准，不触发'), findsOneWidget);
      expect(find.textContaining('52.0℃'), findsOneWidget);
    });

    testWidgets('读不到温区 ≠ 没到阈值：两种说法必须分开', (tester) async {
      await stubPreview(tester, {
        'ok': true,
        'fired': false,
        'temps': <String, double>{},
        'steps': [
          {'phase': 'current', 'outcome': 'NO_READING'},
        ],
        'ruleCount': 1,
        'silence': 'NO_READING',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.science_outlined));
      await tester.pumpAndSettle();

      expect(find.textContaining('该维度本机读不到'), findsOneWidget);
      expect(
        find.textContaining('未达到阈值'),
        findsNothing,
        reason: '把"读不到"说成"没到阈值"会把用户支使去调阈值，而问题在传感器',
      );
    });

    testWidgets('通道没通 = 没测成，不许显示成"不会触发"', (tester) async {
      await stubPreview(tester, null);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.science_outlined));
      await tester.pumpAndSettle();

      expect(find.textContaining('试跑失败'), findsOneWidget);
      expect(find.textContaining('不会触发：'), findsNothing);
    });

    testWidgets('长按菜单里也有单条试跑', (tester) async {
      await service.addRule(rule());
      await stubPreview(tester, {
        'ok': true,
        'fired': false,
        'silence': 'NO_RULES',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('电池过热'));
      await tester.pumpAndSettle();
      expect(find.text('试一次'), findsOneWidget);
    });
  });

  // 版式对齐电量页之后新增的三格（顶部读数 + 总开关行）此前无人测：
  // 读不到时画 0℃ 与"添加按钮没变灰"都是会静默骗人的形状。
  group('顶部读数与总开关（与电量页同构）', () {
    void stubSnapshot(Map<String, Object?>? snap) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.fnthink.notice/notification'),
            (call) async => call.method == 'getDeviceSnapshot' ? snap : null,
          );
    }

    Finder masterSwitch() => find.descendant(
      of: find.byType(EngineSwitchRow),
      matching: find.byType(CupertinoSwitch),
    );

    testWidgets('快照读不到 ⇒ 明写"这台设备读不到"，不许画 0℃', (tester) async {
      stubSnapshot(null);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('这台设备读不到'), findsOneWidget);
      expect(find.text('电池温度'), findsOneWidget, reason: '要说清这个"读不到"是谁的读数');
      expect(find.textContaining('0.0℃'), findsNothing);
    });

    testWidgets('快照给得出 ⇒ 显示实际读数，不再显示读不到', (tester) async {
      stubSnapshot({'batteryTemperatureC': 41.3});
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('41.3℃'), findsOneWidget);
      expect(find.text('这台设备读不到'), findsNothing);
    });

    testWidgets('下拉壳接的是本页真的重读，不是空函数（换壳之后手势的作者要在）', (tester) async {
      // #184：这一页的下拉壳刚从 Material 的 RefreshIndicator 换成 Cupertino 的 sliver 壳。
      // 手势本身由 `pull_to_refresh_list_test.dart` 那份（用真 AppRoot 的）用例验；
      // 这里验的是**分工的另一半** —— 本页交给壳的那一发，真的会再去读一次快照。
      // 坏法有两种：onRefresh 接成空函数（壳在、拉了什么都不做），或接成别的页的函数。
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.fnthink.notice/notification'),
            (call) async {
              if (call.method == 'getDeviceSnapshot') calls++;
              return null;
            },
          );

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      final atStart = calls;
      expect(
        atStart,
        greaterThanOrEqualTo(1),
        reason: '进页本身就是一次读数尝试，否则这一格永远停在"读不到"',
      );

      final shell = tester.widget<PullToRefreshList>(
        find.byType(PullToRefreshList),
      );
      await shell.onRefresh();

      expect(calls, greaterThan(atStart), reason: '下拉的作者不是本页的重读 ⇒ 拉一下什么都不发生');
      await tester.pumpAndSettle();
    });

    testWidgets('总开关那一行真的落到服务，且关掉后加号变灰', (tester) async {
      stubSnapshot({'batteryTemperatureC': 30.0});
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      expect(service.notifyEnabled, isTrue);

      await tester.tap(masterSwitch());
      await tester.pumpAndSettle();

      expect(service.notifyEnabled, isFalse, reason: '只改界面不落服务 = 重启就弹回');
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
            .onPressed,
        isNull,
        reason: '总开关关了还不让加规则，才是这行开关存在的意义',
      );
    });
  });

  // 反馈"三页统一版式"的可验部分：手机竖屏下顶部那块不能挤到换行/溢出。
  // RenderFlex 溢出会抛异常 ⇒ testWidgets 自动红；再加一条"确实渲染出来了"的断言，
  // 防空页冒充通过。
  group('手机竖屏（360×780 逻辑像素）', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.fnthink.notice/notification'),
            (call) async => call.method == 'getDeviceSnapshot'
                ? {'batteryTemperatureC': 41.3}
                : null,
          );
    });

    testWidgets('温度页顶部读数与总开关都在，且没有溢出', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '溢出/换行挤破布局都会从这里冒出来');
      expect(find.text('41.3℃'), findsOneWidget);
      expect(find.text('温度推送通知'), findsOneWidget);
      final header = tester.getRect(find.text('41.3℃'));
      expect(header.right, lessThanOrEqualTo(360), reason: '读数被推到屏幕外就是溢出');
    });
  });

  // T90 片28：温度「试一次」的结果框 —— 换壳之前**这一枚在 test/ 与 integration_test/ 里
  // 零页面级覆盖**（只有闸门 5.4 那一步点过，而闸门只断"正文非空"）。
  // 换壳那三个最容易丢的东西各钉一条：动作文案（「关闭」不是「好的」）、正文那个 key
  // （闸门与这两条用例都按它找）、以及点「关闭」真收得掉。
  group('试跑结果框（T90 片28 收进 showExplainer）', () {
    Future<void> openPreview(WidgetTester tester) async {
      await service.addRule(rule());
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tester.longPress(find.text('电池过热'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CardActionSheet),
          matching: find.text('试一次'),
        ),
      );
      // 原生那一次往返要走平台通道：`.timeout(8s)` 之外还要把帧推完，
      // 否则弹层还没进树（实测：只 pump 一次会停在 await 里）。
      await tester.pumpAndSettle();
    }

    testWidgets('原生没回话 ⇒ 弹层仍弹出、正文说"没测成"、动作是「关闭」', (tester) async {
      await openPreview(tester);

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'Material 那件已经出账（台账清零）⇒ 这一条同时是"账真的空了"的页面级证据',
      );
      final body = find.byKey(const ValueKey('temp-preview-body'));
      expect(body, findsOneWidget, reason: '闸门与这两条用例都按这个 key 找正文');
      expect(
        tester.widget<Text>(body).data,
        contains('不代表不会触发'),
        reason: '把"没测成"显示成"不会触发"会诱导用户去改阈值，而问题在传感器',
      );
      expect(
        find.widgetWithText(CupertinoDialogAction, '关闭'),
        findsOneWidget,
        reason: '这一枚原来的动作就是「关闭」；showExplainer 默认是「好的」，不显式传就换了文案',
      );
      expect(
        find.widgetWithText(CupertinoDialogAction, '好的'),
        findsNothing,
        reason: '「好的」是 showExplainer 给别的调用点的默认文案，不是这一枚的',
      );

      await tester.tap(find.widgetWithText(CupertinoDialogAction, '关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });

    testWidgets('原生回三维度 + 走查 ⇒ 正文逐段渲染，且长正文不溢出', (tester) async {
      // 复刻 setUp 里那个"什么都回 null"的桩，只把这一条方法换成有载荷的答复。
      // ⚠ `stubNativeChannels` 给同一通道也装桩且后者覆盖前者 ⇒ 自己的桩必须重装。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.fnthink.notice/notification'),
            (call) async {
              if (call.method != 'previewTemperatureRule') return null;
              return <Object?, Object?>{
                'ok': true,
                'ruleCount': 1,
                'temps': <Object?, Object?>{
                  'battery_temp_above': 46.53,
                  'device_temp_above': 38.24,
                  'screen_temp_above': 30.11,
                },
                'steps': <Object?>[
                  <Object?, Object?>{'phase': 'read', 'outcome': 'FIRE'},
                  <Object?, Object?>{
                    'phase': 'rule',
                    'outcome': 'NOT_TRIGGERED',
                  },
                  <Object?, Object?>{
                    'phase': 'cooldown',
                    'outcome': 'BASELINE',
                  },
                ],
                'fired': false,
                'silence': 'NOT_TRIGGERED',
              };
            },
          );
      await openPreview(tester);

      final text = tester
          .widget<Text>(find.byKey(const ValueKey('temp-preview-body')))
          .data!;
      expect(text, contains('当前读数：'), reason: '读数那一段没渲染 ⇒ 原生回了载荷而 Dart 没画');
      expect(text, contains('46.5℃'), reason: '保留一位小数（照抄原生会变成 46.53）');
      expect(text, contains('38.2℃'));
      expect(text, contains('30.1℃'));
      expect(
        text,
        contains('走查：触发 → 未达到阈值 → 首轮只记录基准，不触发'),
        reason: '走查三段要在同一行里按顺序出现（用户靠它判断卡在哪一步）',
      );
      expect(text, contains('不会触发：未达到阈值'));
      expect(
        find.text('试跑失败（没测成，不代表不会触发）'),
        findsNothing,
        reason: '原生明明回了一份成功载荷 ⇒ 这一句出现就是解析或判据出了问题',
      );
      // 这一枚的正文是全应用最长的一段（读数 + 走查 + 结论），屏高放不下。
      // 旧形状 content 里那层 `SingleChildScrollView` 已随换壳删掉（外层自带）⇒
      // 这条断言是"删掉那层仍然不溢出"的证据，不是装饰。
      expect(tester.takeException(), isNull, reason: '长正文溢出/滚动嵌套都会从这里冒出来');
    });
  });
}
