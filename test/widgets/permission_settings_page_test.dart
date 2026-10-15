import 'dart:async';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/pages/permission_settings_page.dart';
import 'package:notice_transmit/services/fnthink_l3_grants.dart';
import 'package:notice_transmit/services/platform_channel.dart';
import 'package:notice_transmit/services/permission_service.dart';
import 'package:notice_transmit/theme/app_colors.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/fnthink_card.dart';

/// 权限设置页此前**没有任何**自动化契约 —— "点这一行到底发生了什么"全靠读代码。
/// 维护者 1.5.76 反馈 #3 改的就是这一行的行为，所以先把行为钉住：
/// 一次点击 = 一次申请动作，中间那层应用内说明框不再挡路。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = AppChannels.notification;
  final contract = FnthinkContract.readFile();
  late int appListTaps;
  late int notifListenerTaps;

  /// 页面（含它背后的 `PermissionService`）实际打到原生的那一发发方法名。
  /// 精确闹钟那一族撤掉 App 内开关之后，"点这一行绝不写偏好"这一句只能靠它来观察。
  late List<String> channelCalls;

  Future<void> pumpPage(
    WidgetTester tester, {
    required String appListState,
    Map<String, bool?>? l3Readers,
    Map<String, String>? l3Notes,
    // 「回前台要重算」那两条要自己控制取数节奏（改一份可变的 readers、数被取了几次），
    // 所以取数这件事留一个口子；不传就用下面那份默认读法（与真机同源：都走 collectL3GrantRows）。
    Future<List<FnthinkL3GrantRow>> Function()? l3Loader,
    // 系统对精确闹钟的授权读数（T140 走 (c) 之后这一族唯一的真值）。
    bool exactAlarmGranted = false,
  }) async {
    channelCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          channelCalls.add(call.method);
          if (call.method == 'getAppListPermissionState') return appListState;
          if (call.method == 'canScheduleExactAlarms') return exactAlarmGranted;
          // 其余都是布尔读数：回 false 即可（回 String 会让服务的 try/catch 吞掉整批赋值）
          return false;
        });
    final service = PermissionService(appListEnumerator: () async {});
    await service.checkAllPermissions();
    GetIt.instance.allowReassignment = true;
    GetIt.instance.registerSingleton<PermissionService>(service);

    // 整页是 ListView（懒布局），默认 800×600 视口下「可选权限」那一段压根没被建出来，
    // finder 会报"找不到"而让人误以为行为没了。给一个足够高的视口，让所有行都在场。
    tester.view.physicalSize = const Size(1080, 7200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    appListTaps = 0;
    notifListenerTaps = 0;
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: PermissionSettingsPage(
          notificationListenerGranted: false,
          postNotificationGranted: false,
          batteryOptimizationIgnored: false,
          smsPermissionGranted: false,
          phonePermissionGranted: false,
          appListPermissionGranted: appListState == 'granted',
          // 与真机同源：这一格的数据仍由调用方按契约词表算好（读法只有一处 `collectL3GrantRows`），
          // 但交出去的是**「去取一次」这件事** —— 默认"全部读到 false"，各用例按需改某一项。
          loadL3GrantRows:
              l3Loader ??
              () async => collectL3GrantRows(
                contract,
                readers:
                    l3Readers ??
                    {for (final k in contract.l3Settings.keys) k: false},
                notes: l3Notes ?? const {},
              ),
          manufacturer: 'meizu',
          onRefresh: () async {},
          onRequestNotificationListenerPermission: () => notifListenerTaps++,
          onRequestPostNotificationPermission: () {},
          onRequestBatteryOptimization: () {},
          onRequestXiaomiAutoStart: () {},
          onRequestMeizuBackground: () {},
          onRequestHuaweiLaunch: () {},
          onRequestOppoBackground: () {},
          onRequestVivoBackground: () {},
          onRequestSmsPermission: () {},
          onRequestPhonePermission: () {},
          onRequestAppListPermission: () => appListTaps++,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    GetIt.instance.reset();
  });

  testWidgets('五张组标题都由公共件画出来（key 逐字在册，T146 片4）', (tester) async {
    // 这一页以前自己搭了一枚 13px/w500 的组标题壳（与「更多」页那枚逐字相同），
    // 而幻念那三张清单页走的是 13px/w600 的公共件 —— 同一个角色两把尺，谁也不会发现自己漂了。
    await pumpPage(tester, appListState: 'granted');
    for (final key in [
      'permission-section-essential-perms',
      'permission-section-keep-alive-guide',
      'permission-section-vendor-bg-settings',
      'permission-section-optional-perms',
      'permission-section-l3-settings',
    ]) {
      final cell = find.byKey(ValueKey(key));
      expect(
        cell,
        findsOneWidget,
        reason: '组标题那一格的 key 读不到 ⇒ 页面又自己搭了一份壳，key 跟着措辞漂',
      );
      expect(
        find.ancestor(of: cell, matching: find.byType(FnthinkRowLabel)),
        findsOneWidget,
        reason: 'key 还在、画的却不是 `FnthinkRowLabel` ⇒ 这一族又长出第二个作者',
      );
    }
  });

  group('应用列表权限那一行（T153 片4：先引导后跳）', () {
    // ⚠ **这一组在 2026-10-16 被维护者的新要求改写过**，原判据是：
    //   「点一下就直接发起申请，不再先弹应用内说明框」（1.5.76 反馈 #3，
    //    理由是"申请动作本身就是这一行的语义"）。
    //   T153 片4 维护者 2026-10-15 拍板 Q2=a：「得先弹窗提醒用户把话说清楚并引导
    //   用户进行操作」—— 因为他遇到的实际问题是**跳过去之后不知道该开哪一项**
    //   （原话"不要只是跳转到应用设置页"）。
    //
    // 两次要求都关于"这一行点下去要不要弹"，但**目的不同**：1.5.76 去掉的是
    // "再问你一次要不要申请"（确认），2026-10-15 加回的是"告诉你去哪找那一项"（指路）。
    // 本组按最新指令钉"指路那一层在、且它**不拦路**（不点它就不跳）"。
    // ⚠ 若维护者确认 1.5.76 #3 的意思是"这一行任何时候都别弹任何东西"，
    //   回退只需删掉 `_guideThenJump` 的两处调用（`permission_settings_page.dart`）。
    testWidgets('点一下**先弹引导**（说清系统里叫什么），确认后才跳', (tester) async {
      await pumpPage(tester, appListState: 'unknown');

      await tester.tap(find.text('应用列表权限'));
      await tester.pumpAndSettle();

      // ① 引导框在场，且它说的是"这一项在系统里叫什么"
      expect(
        find.text('应用列表权限要让系统放行'),
        findsOneWidget,
        reason: '没有这一层 ⇒ 用户跳过去站在一页权限列表前不知道开哪一项',
      );
      expect(
        find.textContaining('读取已安装的应用列表'),
        findsOneWidget,
        reason: '引导必须点出系统里那一项的名字，否则等于只是"跳过去"',
      );
      // ② 此刻**还没跳**（拦在引导这一层）
      expect(appListTaps, 0, reason: '引导还没确认就跳了 ⇒ 那一层是装饰');

      // ③ 点「去开启」才走那一发
      //    ⚠ 必须限定在弹层内：那一格自己的副标题也写着「点击前往设置」
      //      （`clickToSettings`，用于厂商那几行），不限定会 ambiguous。
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text('点击前往设置'),
        ),
      );
      await tester.pumpAndSettle();
      expect(appListTaps, 1, reason: '确认之后必须真的走那一发');
    });

    testWidgets('引导里点「取消」⇒ 那一发不走（不许"取消也跳"）', (tester) async {
      await pumpPage(tester, appListState: 'unknown');

      await tester.tap(find.text('应用列表权限'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text('取消'),
        ),
      );
      await tester.pumpAndSettle();

      expect(appListTaps, 0, reason: '取消 = "现在别跳"；取消之后还跳走，用户就失去了"我改主意了"这条出口');
    });

    testWidgets('已读到明确授予 ⇒ 该行不再可点（不给"重复申请"留口子）', (tester) async {
      await pumpPage(tester, appListState: 'granted');

      expect(find.text('已开启'), findsWidgets, reason: '授予态要有明确读数');
      await tester.tap(find.text('应用列表权限'));
      await tester.pumpAndSettle();

      expect(appListTaps, 0);
    });

    testWidgets('读不到明确状态时显示的是"不提供明确状态"，不是"已开启"', (tester) async {
      await pumpPage(tester, appListState: 'unknown');

      expect(find.text('应用列表权限'), findsOneWidget);
      expect(find.textContaining('该系统版本不提供明确状态'), findsOneWidget);
    });
  });

  group('L3 那一格（T52：置灰而不是隐藏，四态不说成同一句）', () {
    testWidgets('一项都没给 ⇒ 契约里有几项就渲染几行，一行都不折', (tester) async {
      await pumpPage(tester, appListState: 'unknown');

      expect(find.text('对端可以请求的系统设置'), findsOneWidget);
      // ⚠ 这一条钉的是"隐藏"：未授权项被折叠掉的话，用户看到的是一个少了几行的列表，
      // 而"幻念推送要改哪些系统设置"本该在点之前就说完。行数**取自契约**，不在这里写死。
      expect(find.text('还没给这台设备授权'), findsNWidgets(contract.l3Settings.length));
    });

    testWidgets('契约新增一项而这一页还没配词条 ⇒ 那一行照画，标题就是那枚裸 key', (tester) async {
      await pumpPage(
        tester,
        appListState: 'unknown',
        l3Loader: () async => const [
          FnthinkL3GrantRow(
            key: 'brand_new_setting',
            mode: 'grant',
            native: 'getBrandNewSetting',
            state: FnthinkL3GrantState.missing,
          ),
        ],
      );

      // 这一条钉的是**回退形状**，不是"这页配齐了"：少一行是静默的（用户以为这台没这项要管），
      // 退成裸 key 才是"这一项还没配人话"的可见缺。配套的架构守卫同时把这件事报成红
      // （`test/architecture/fnthink_l3_item_words_scope_test.dart` ①），两处一起改才收得住。
      expect(
        find.text('brand_new_setting'),
        findsOneWidget,
        reason: '回退形状变了（编一句、或者干脆不画那一行）⇒ 上面那条守卫红得没道理，两处一起失效',
      );
      expect(
        find.text('通知转发监听'),
        findsNothing,
        reason: '只剩这一行时别把已配项的名字串进来（"少画一行"会被读成"这页在说另一项"）',
      );
    });

    testWidgets('读不到的一项说的是"读不到"，不是"已开启"也不是"还没给"', (tester) async {
      await pumpPage(
        tester,
        appListState: 'unknown',
        l3Readers: {
          for (final k in contract.l3Settings.keys) k: false,
          'autostart': null,
        },
      );

      expect(find.text('读不到这台设备的状态'), findsOneWidget);
      expect(find.text('自启动（按厂商）'), findsOneWidget);
      // 少了的那一条：unreadable 不再冒充 missing ⇒ missing 那一堆少一项
      expect(
        find.text('还没给这台设备授权'),
        findsNWidgets(contract.l3Settings.length - 1),
      );
    });

    testWidgets('已给的那一项显示"已开启"，且不再给"重复申请"的箭头', (tester) async {
      await pumpPage(
        tester,
        appListState: 'unknown',
        l3Readers: {
          for (final k in contract.l3Settings.keys) k: false,
          'notification': true,
        },
      );

      final row = find.text('通知访问权限').last;
      expect(find.text('已开启'), findsWidgets);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(notifListenerTaps, 0, reason: '已经给了还让点，就是在催用户重复申请');

      // ⚠ "置灰"是这一格的全部承诺之一：给了的与没给的必须看得出区别。
      // 断言落在**具体颜色**上（不是"两个不一样"），否则把 dimmed 写成恒 false 也过得去。
      final ctx = tester.element(find.byType(Scaffold).last);
      Color titleColor(Finder title) =>
          tester.widget<Text>(title).style!.color!;
      expect(
        titleColor(find.text('幻念收件开关')),
        AppColors.tertiaryLabel(ctx),
        reason: '没给的这一行要灰下去',
      );
      expect(
        titleColor(find.text('通知访问权限').last),
        isNot(AppColors.tertiaryLabel(ctx)),
        reason: '已给的不要灰 —— 灰的是"还差这一格"，不是"这一格无所谓"',
      );
    });

    testWidgets('没给的那一项点一下就走申请（这一行的语义就是"去申请"）', (tester) async {
      await pumpPage(tester, appListState: 'unknown');

      await tester.tap(find.text('通知访问权限').last);
      await tester.pumpAndSettle();

      expect(notifListenerTaps, 1);
    });

    testWidgets('开关住在别处的那两行：给一句说明，不放点了没反应的按钮', (tester) async {
      await pumpPage(
        tester,
        appListState: 'unknown',
        l3Readers: {
          for (final k in contract.l3Settings.keys) k: true,
          'monitoring': null,
          'collect_inbox': false,
          'battery_optimization': false,
        },
        l3Notes: const {
          'monitoring': '这一格的开关在「幻念推送」页',
          'collect_inbox': '这一格的开关在「幻念推送」页',
        },
      );

      // 说明这一句是**跟着状态走的**（状态 · 说明），所以按包含查。
      expect(find.text('通知转发监听'), findsOneWidget);
      expect(
        find.textContaining('这一格的开关在「幻念推送」页'),
        findsNWidgets(2),
        reason: '读不到的那一项也要说一句去哪开，否则用户只能自己翻页面',
      );
      // ⚠ 点了不会有任何事发生的那一行（开关在别的页），**整行不可点** ——
      // "点了没反应"正是这片要防的形状，说明句替代了按钮。
      expect(
        tester
            .widget<InkWell>(
              find.ancestor(
                of: find.text('通知转发监听'),
                matching: find.byType(InkWell),
              ),
            )
            .onTap,
        isNull,
      );
      // 反过来：没给、而这一格确实能跳的那一行，可点（最后一枚是 L3 那一格里的）。
      expect(
        tester
            .widget<InkWell>(
              find.ancestor(
                of: find.text('忽略电池优化').last,
                matching: find.byType(InkWell),
              ),
            )
            .onTap,
        isNotNull,
      );
    });
  });

  group('L3 那一格读的是此刻，不是进页那一刻（T140 层4 引）', () {
    testWidgets('去系统里改完回来 ⇒ 那一行跟着改口（回前台必须再取一次）', (tester) async {
      // 这一条钉的是"什么时候再问一遍"，不是"问出来的话好不好听"：
      // 旧写法把**打开页面那一刻算好的那份 List** 当构造参数注入，页面画的是那份快照 ——
      // 用户就在这一页点「通知访问权限」跳系统、给完回来，那一行还说"还没给"，
      // 而同一页上 B1 精确闹钟那一格（页面自己读的那一份）已经改口了。
      // 一屏两句话、互相矛盾，而用户只能靠退出重进来确认自己到底给了没有。
      var granted = false;
      var loads = 0;
      await pumpPage(
        tester,
        appListState: 'unknown',
        l3Loader: () async {
          loads++;
          return collectL3GrantRows(
            contract,
            readers: {
              for (final k in contract.l3Settings.keys)
                k: k == 'notification' && granted,
            },
            notes: const {},
          );
        },
      );
      expect(loads, 1, reason: '进页面取一次');
      expect(find.text('还没给这台设备授权'), findsNWidgets(contract.l3Settings.length));

      granted = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(loads, 2, reason: '回前台必须**再取一次**：只重画不重取，画出来的还是进页那一刻那份快照');
      expect(
        find.text('还没给这台设备授权'),
        findsNWidgets(contract.l3Settings.length - 1),
        reason: '给了的那一项不能再挂着"还没给" —— 那是把用户刚做完的事抹掉',
      );
      expect(find.text('已开启'), findsWidgets);
    });

    testWidgets('还没取到 ⇒ 那一格一行都不画（不拿一张空卡冒充"这台没项要管"）', (tester) async {
      // 「还没问过」与「问过了，这项这台没有」在 T52 的四态里是刻意分开的两档；
      // 旧形状不会有第三种（构造参数当场就有值），换成异步取数之后必须给它一句真话 ——
      // 最诚实的是**先不画那一格**：分区标题是结构性事实（这一页有这一格），照画。
      final pending = Completer<List<FnthinkL3GrantRow>>();
      await pumpPage(
        tester,
        appListState: 'unknown',
        l3Loader: () => pending.future,
      );

      expect(find.text('对端可以请求的系统设置'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('perm-l3-group-card')),
        findsNothing,
        reason: '画一张空的分组卡会被读成"这台没什么要管的"，而真相是我们还没问过',
      );
      expect(
        find.text('自启动（按厂商）'),
        findsNothing,
        reason: '取数还在路上就先把行画出来，等于替这台设备回答了一次"没有"',
      );

      pending.complete(
        collectL3GrantRows(
          contract,
          readers: {for (final k in contract.l3Settings.keys) k: false},
          notes: const {},
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('perm-l3-group-card')),
        findsOneWidget,
        reason: '读到之后那一格必须自己长出来，不需要用户退出重进',
      );
      expect(find.text('自启动（按厂商）'), findsOneWidget);
    });
  });

  group('精确闹钟那一行（T140 走 (c)：只剩系统授权一枚真值）', () {
    // 这一族以前右侧是一枚写 Flutter 偏好的开关（默认关），副标题报的却是系统授权。
    // 后果不是崩，是**同一行上两句假话的合取**：写着「已授权」，而排闹钟的代码看的是那枚关着的开关
    // ⇒ 到点晚几分钟（契约对常态收取承诺 5–60 秒）。维护者裁定删开关，所以这里钉的是新形状。
    final tile = find
        .ancestor(
          of: find.text('精确闹钟（准时推送）').first,
          matching: find.byType(InkWell),
        )
        .first;

    testWidgets('未授权：那一行说「点击授权」，点一下就去系统里给', (tester) async {
      await pumpPage(tester, appListState: 'granted');

      expect(
        find.textContaining('点击授权'),
        findsOneWidget,
        reason: '没给的时候要说"点这下去给"，而不是含糊的"未开启"',
      );
      expect(
        tester.widget<InkWell>(tile).onTap,
        isNotNull,
        reason: '还没给 ⇒ 这一行的全部意义就是把人送到系统那一屏，它必须可点',
      );

      channelCalls.clear();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(
        channelCalls,
        contains('requestExactAlarmPermission'),
        reason: '这一行的语义就是"去系统里给"，点一次就该走一次',
      );
      expect(
        channelCalls.any((m) => m.contains('ExactAlarmEnabled')),
        isFalse,
        reason: '点一下绝不写偏好 —— 写了就是那一枚开关换了个入口长回来',
      );
    });

    testWidgets('整页一枚 CupertinoSwitch 都没有（开关那一族不许在这一页复活）', (tester) async {
      await pumpPage(tester, appListState: 'granted');

      // 这一页历史上只有精确闹钟那一枚开关；换成"状态 + 一键跳"之后整页应当一枚都不剩。
      // 断整页而不是断那一行：下次有人往别的行塞开关，这一条会一起报出来。
      expect(
        find.byType(CupertinoSwitch),
        findsNothing,
        reason: '权限引导页只报授权、只跳系统，不持有第二份配置',
      );
    });

    testWidgets('已授权：说的是"已授权"，且不给"重复申请"留口子', (tester) async {
      // ⚠ 这一发只把**通道侧那枚授权**改成 true，L3 那几行仍走注入的 readers（默认全 false）：
      //   生产上两行同源（都读 `canScheduleExactAlarms`），这里分开注入是为了只动一个旋钮。
      await pumpPage(tester, appListState: 'granted', exactAlarmGranted: true);

      expect(
        find.textContaining('已授权 · '),
        findsOneWidget,
        reason: '这一行画的那一枚，与原生排闹钟读的那一枚同源 ⇒ 「已授权」这句第一次等于「到点真的准」',
      );
      expect(
        tester.widget<InkWell>(tile).onTap,
        isNull,
        reason: '已经给了还让点，就是在催用户重复申请（与 L3 那几行同一条规矩）',
      );

      channelCalls.clear();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(channelCalls, isEmpty, reason: '已授权状态下这一行不该打任何原生');
    });
  });
}
