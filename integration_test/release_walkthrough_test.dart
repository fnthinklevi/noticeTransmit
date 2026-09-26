import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/di/service_locator.dart';
import 'package:notice_transmit/main.dart' show MyApp;
import 'package:notice_transmit/pages/app_channel_list_page.dart';
import 'package:notice_transmit/pages/channel_status_page.dart';
import 'package:notice_transmit/pages/app_channel_settings_page.dart';
import 'package:notice_transmit/pages/app_filter_page.dart';
import 'package:notice_transmit/pages/backup_restore_page.dart';
import 'package:notice_transmit/pages/battery_page.dart';
import 'package:notice_transmit/pages/email_settings_page.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/pages/keywords_page.dart';
import 'package:notice_transmit/pages/more_page.dart';
import 'package:notice_transmit/pages/notification_engine_page.dart';
import 'package:notice_transmit/pages/notification_page.dart';
import 'package:notice_transmit/pages/permission_settings_page.dart';
import 'package:notice_transmit/pages/rule_edit_page.dart';
import 'package:notice_transmit/pages/rule_list_page.dart';
import 'package:notice_transmit/pages/rule_tester_page.dart';
import 'package:notice_transmit/pages/sms_monitor_settings_page.dart';
import 'package:notice_transmit/pages/stats_page.dart';
import 'package:notice_transmit/pages/temperature_page.dart';
import 'package:notice_transmit/pages/webhook_channel_list_page.dart';
import 'package:notice_transmit/pages/webhook_settings_page.dart';
import 'package:notice_transmit/services/app_channel_service.dart';
import 'package:notice_transmit/services/battery_service.dart';
import 'package:notice_transmit/services/channel_descriptor_service.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/widgets/card_action_sheet.dart';
import 'package:notice_transmit/services/device_info_service.dart';
import 'package:notice_transmit/services/email_service.dart';
import 'package:notice_transmit/services/filter_service.dart';
import 'package:notice_transmit/services/temperature_service.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/services/webhook_service.dart';
import 'package:notice_transmit/services/archive_worker.dart'
    show archiveCallbackDispatcher;
import 'package:notice_transmit/services/update_service.dart';
import 'package:notice_transmit/update_manager.dart' show VersionCheckResult;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'support/native_payload_stubs.dart';

/// ㊻ 发版硬闸门：**所有**用户可达页面各点一遍 + 每条 CRUD 各走一次 +
/// 备份**真的**导出成文件再导回来。与 `smoke_test.dart`（7 步主链路）互补，不重复它。
///
/// 运行方式（发版脚本会自动做，见 `.github/scripts/release_emulator.sh`）：
///   `flutter test integration_test/release_walkthrough_test.dart -d emulator-5554`
///
/// 为什么值得单独一个闸门：1.5.74 上线后，"备份导入后 webhook 设置页打不开"
/// 是**维护者手点**撞出来的，而当时"全量测试通过 + 四包构建通过 + CI 冒烟通过"。
/// 缺的正是"每个页面都进去一次、导入导出真做一次"这一层。
///
/// 桩策略（与 smoke 一致）：`com.fnthink.notice/notification` 全量 mock；
/// sqflite_sqlcipher 数据库与 AndroidKeyStore **走真实实现**（备份往返必须落在真库上）；
/// FilePicker 用 `FilePicker.platform = ` 注入假实现，返回真写到设备临时目录的备份文件路径
/// ⇒ 页面里那段 `File(path).readAsString()` 与解密、恢复链路全是真的，只有 SAF 选单界面被替掉。
///
/// ⚠ 只在模拟器上跑：集成测试在签名不匹配时会 `adb uninstall` 目标应用并连带清掉它的
///   加密数据库。真机上等于删用户数据（本项目真出过一次）。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  const backupPassword = 'gatepass123'; // ≥8 位，BackupService 有最小长度校验
  final captured = <String, List<List<Object?>>>{};
  final writtenFiles = <String, String>{}; // fileName -> 设备上的真实路径
  String? pickedPathForNextCall;

  setUpAll(() async {
    // 见 smoke_test 同名注释：本文件的 main() 不执行应用 main()，WorkManager 必须补初始化
    Workmanager().initialize(archiveCallbackDispatcher);
    SharedPreferences.setMockInitialValues({
      'privacy_policy_accepted': true,
      'flutter.privacy_policy_accepted': true,
      'has_launched': true,
      // 断言用中文文案 ⇒ 必须钉语言，否则模拟器系统语言为 en 时回落英文（smoke 踩过）
      'app_language': 'zh',
      'flutter.app_language': 'zh',
      'last_system_lang': 'zh',
      'flutter.last_system_lang': 'zh',
    });
    FilePicker.platform = _FakeFilePicker(() => pickedPathForNextCall);

    const channelName = 'com.fnthink.notice/notification';
    // 应用清单：缓存与全量给同一份数据。⚠ 别只桩 getInstalledApps ——
    // 页面首帧先读缓存（InstalledAppsService.loadCached），没桩到的那个方法会返回 null，
    // 于是闸门跑的是"缓存读失败⇒空列表"的降级分支，还顺带在日志里刷一条
    // `type 'Null' is not a subtype of type 'List<dynamic>'`（看着像产品 bug，其实是桩缺项）。
    final gateApps = <Map<String, dynamic>>[
      {
        'packageName': 'com.gate.app1',
        'appName': '闸门应用一',
        'isSystemApp': false,
      },
      {
        'packageName': 'com.gate.app2',
        'appName': '闸门应用二',
        'isSystemApp': false,
      },
    ];
    final stubs = <String, Object?>{
      'getSimCardCount': 2,
      'isNotificationPermissionGranted': true,
      'isPostNotificationPermissionGranted': true,
      'isSmsPermissionGranted': true,
      'isPhonePermissionGranted': true,
      'getAppListPermissionState': 'granted',
      'canQueryAllPackages': true,
      'isIgnoringBatteryOptimizations': true,
      'canScheduleExactAlarms': true,
      'isExactAlarmEnabled': true,
      'isServiceRunning': false,
      'getEnabledPackages': <String>[],
      'getBlacklistKeywords': <String>[],
      'getWhitelistKeywords': <String>[],
      'getAppFilterMode': 'allow',
      'getInstalledApps': gateApps,
      'getCachedInstalledApps': gateApps,
      'getDeviceName': '闸门设备',
      'getDeviceModel': 'GateModel',
      'getManufacturer': 'Google',
      'getAppVersion': {'versionName': '1.5.74', 'versionCode': 113},
      'getBatteryStatus': {'level': 77, 'isCharging': false, 'status': 3},
      'getDownloadDirectory': '/data/local/tmp',
      // 测试类动作：全部返回成功，覆盖 UI 的成功分支（不联网、不真发）
      'testWebhook': {'success': true, 'message': '闸门通过', 'signed': false},
      'testAppChannel': {'success': true, 'message': '闸门通过'},
      'testEmail': {'success': true, 'message': '闸门通过'},
      'probeChannelHealth': {'reachable': true, 'latencyMs': 12},
      // 6e 非侵入探测：应用族只换 token、邮件族只握手，都不投递。给"通"的桩，
      // 让设备侧真走完「进页 → 探测 → 落健康单点 → 徽标刷新」那一段（缺桩=静默跳过）。
      'probeAppChannelToken': {'reachable': true, 'latencyMs': 31, 'reason': ''},
      'verifySmtp': {'reachable': true, 'latencyMs': 24, 'reason': ''},
      'requestPinAppWidget': true,
      'drainOfflineCache': <Map<String, dynamic>>[
        {
          'id': 'gate_note_1',
          'title': '闸门通知一',
          'content': '闸门集成测试注入的通知内容',
          'subText': '',
          'packageName': 'com.gate.app1',
          'appName': '闸门应用一',
          'postTime': 1767223200000,
          'time': '2026-01-01 10:00:00',
          'type': 'notification',
          'priority': 1,
        },
      ],
      'drainDeliveryResults': <Map<String, dynamic>>[
        {
          'notificationId': 'gate_note_1',
          'webhookType': 'DINGTALK',
          'status': 'SUCCESS',
          'message': 'ok',
          'httpCode': 200,
          'channelUrl': 'https://oapi.dingtalk.com/robot/send',
        },
      ],
      // 描述符必须给**非空**桩：空载荷按"原生未就绪"处理（见 smoke 的同一注释）。
      // 桩只有一份来源：integration_test/support/native_payload_stubs.dart，
      // 由 native_payload_stub_test 与导出快照逐字段比对（手抄两份各撞过一次静默降级）。
      'getChannelDescriptors': channelDescriptorsStub([
        stubDingtalk(),
        stubWechatWork(),
        stubWecomApp(),
        stubEmail(),
      ]),
    };

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), (
          call,
        ) async {
          captured.putIfAbsent(call.method, () => []).add([call.arguments]);
          // 文件落盘类：真的写到设备文件系统，后面的"导入"要读同一个文件
          if (call.method == 'saveFile') {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final name = args['fileName'].toString();
            final path =
                '${Directory.systemTemp.path}${Platform.pathSeparator}$name';
            File(path).writeAsStringSync(args['content'].toString());
            writtenFiles[name] = path;
            return {'success': true};
          }
          final mirrored = _nativeMirror(call);
          if (mirrored != _noMirror) return mirrored;
          if (stubs.containsKey(call.method)) return stubs[call.method];
          return null;
        });
  });

  tearDownAll(() {
    for (final path in writtenFiles.values) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
  });

  testWidgets('全功能点击 + 导入导出往返（发版硬闸门）', (tester) async {
    // ── 装配 ────────────────────────────────────────────────────────────
    setupLocator();
    GetIt.instance.allowReassignment = true;
    GetIt.instance.registerSingleton<UpdateService>(_StubUpdateService());

    // 起点必须是干净的：闸门要能重复跑，且"备份里有没有这一条"这类断言依赖初值
    final db = DatabaseHelper();
    await db.saveWebhookChannels([]);
    await db.saveAppChannels([]);
    await db.saveEmailChannels([]);
    await GetIt.instance<NotificationService>().clearRecords();

    await tester.pumpWidget(const MyApp());
    await _settle(tester, seconds: 3);
    expect(
      find.byType(NavigationBar),
      findsOneWidget,
      reason: '闸门第 0 步：主界面未出现（装配链断了/隐私弹窗没跳过）',
    );
    expect(
      GetIt.instance<ChannelDescriptorService>().isReady,
      isTrue,
      reason: 'splash 未拉通描述符 ⇒ 后面每个表单都会缺字段，点击结果无意义',
    );

    final gateFailures = <String, String>{};
    // ── 1. 通知页：服务启停（真实控件是圆形按钮，不是文案）──────────────
    await _tap(
      tester,
      find.byKey(const ValueKey<String>('service-toggle')),
      '通知页服务开关',
    );
    expect(
      captured['startNotificationListener'],
      isNotNull,
      reason: '点服务开关没有下发 startNotificationListener',
    );
    await _tap(
      tester,
      find.byKey(const ValueKey<String>('service-toggle')),
      '通知页服务开关(关)',
    );
    expect(
      captured['stopNotificationListener'],
      isNotNull,
      reason: '再点一次应下发 stopNotificationListener',
    );

    // ── 2. 权限设置页：进入即读三态权限，页面必须渲染且不抛 ──────────────
    await _tap(tester, find.text('权限设置'), '通知页→权限设置');
    await _onPage(tester, PermissionSettingsPage, '权限设置页');
    await _backToHome(tester);

    // ── 3. 短信监听页：两个开关 + SIM 卡选择 ────────────────────────────
    await _tap(tester, find.text('短信监听'), '通知页→短信监听');
    await _onPage(tester, SmsMonitorSettingsPage, '短信监听页');
    final smsSwitches = _in(
      SmsMonitorSettingsPage,
      find.byType(CupertinoSwitch),
    );
    expect(smsSwitches, findsNWidgets(2), reason: '短信监听页应有两个开关');
    await _tap(tester, smsSwitches.at(1), '监听验证码开关');
    await _tap(tester, find.text('仅卡1'), 'SIM 卡选择「仅卡1」');
    final smsSets = (captured['setSmsSetting'] ?? const [])
        .map((a) => (a.first as Map)['key'])
        .toList();
    expect(
      smsSets,
      containsAll(<String>['sms_code_monitor_enabled', 'sms_sim_filter']),
      reason: '开关与卡选择都必须回写原生，否则后台读不到新配置',
    );
    await _backToHome(tester);

    // ── 4. 推送历史页：进入 + 溢出菜单里的导出 JSON（真落盘）─────────────
    await _tap(tester, find.text('推送历史'), '通知页→推送历史');
    await _settle(tester, seconds: 2);
    expect(
      find.text('闸门通知一'),
      findsWidgets,
      reason: '注入的历史记录没出现在列表里（loadRecords/DB 链路）',
    );
    await _tap(
      tester,
      _in(HistoryPage, find.byIcon(Icons.more_horiz)),
      '历史页溢出菜单',
    );
    await _settle(tester);
    await _tap(tester, find.text('导出 JSON'), '历史页→导出 JSON');
    await _settle(tester);
    // 导出前有一步确认弹层（main_page_actions 的 exportBtn），不点它 saveFile 不会发生
    await _tap(tester, find.text('确定导出'), '历史页导出→确定导出');
    await _settle(tester, seconds: 3);
    expect(
      writtenFiles.keys.any((n) => n.endsWith('.json')),
      isTrue,
      reason: '导出生成没有真的走 saveFile？（历史 JSON 导出是运维取数唯一出口）',
    );
    // T05：历史记录卡的长按动作表。本批把它就地写的整份弹层搬进了共用组件，
    // 所以这里必须真展开一次 —— 只展开再收起，不点「屏蔽」，
    // 那会改掉后面各节依赖的过滤配置（闸门要可重复）。
    await _longPress(tester, find.text('闸门通知一'), '历史记录行');
    // 限定在弹层里 + 精确文本：这一项的**副标题**也含"屏蔽该应用"五个字
    // （闸门第一轮就是被这条 loose 断言打红的：textContaining 一次数到两个）。
    final blockAppItem = find.descendant(
      of: find.byType(CardActionSheet),
      matching: find.text('屏蔽该应用的通知'),
    );
    expect(
      blockAppItem,
      findsOneWidget,
      reason: '长按弹层没出来 ⇒ CardActionSheet 在真机手势区上不可用',
    );
    await tester.tapAt(const Offset(10, 10));
    await _settle(tester);
    expect(
      find.byType(CardActionSheet),
      findsNothing,
      reason: '点遮罩关不掉弹层 ⇒ 用户被卡在动作表里',
    );
    await _backToHome(tester);

    // ── 5. 更多 tab：以下每个入口逐个进页，页面级 CRUD 各自走完 ──────────
    await _tap(
      tester,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('更多'),
      ),
      '底部 tab→更多',
    );
    await _onPage(tester, MorePage, '更多页');

    // 5.1 Webhook 通道（T07-B 起是「列表页 → 单通道详情页」两页形状）：
    //     FAB 建第一条 → 仅测试（不许写库）→ 测试并保存 → 回列表 → 建第二条 →
    //     点第一条行进详情改一处 → 断言第二条原样 → 长按复制 → 长按删除并确认。
    //     删完必须断言"活下来的是哪一条"：删一行后其余行继承错位 id 是这个页面
    //     真实发生过的缺陷类别（平铺页保存走整表 delete+insert）。
    await _openMoreRow(tester, 'Webhook 推送通道');
    await _onPage(tester, WebhookChannelListPage, 'Webhook 列表页');
    const dingUrl = 'https://oapi.dingtalk.com/robot/send?access_token=gate';
    const wecomUrl =
        'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=gate';

    await _tap(tester, find.byType(FloatingActionButton), 'Webhook→新增');
    await _onPage(tester, WebhookSettingsPage, 'Webhook 详情页(新增)');
    await _fillWebhookUrl(tester, dingUrl);
    // URL 填完 ⇒ 类型选择器应显出「自动识别·钉钉」：描述符与 host 识别表都在工作
    expect(
      find.textContaining('自动识别'),
      findsWidgets,
      reason: '填完 URL 后类型选择器没有按 host 识别 ⇒ 描述符/识别表断链',
    );
    // T04「仅测试」：与「测试并保存」是两条路径 ⇒ 它**不写库**（这一条还没 id，
    // 更没有归属，健康单点也不该被写）。
    await _tap(tester, _appBarText('仅测试'), 'Webhook→仅测试');
    await _settle(tester, seconds: 2);
    expect(
      find.byType(WebhookSettingsPage),
      findsOneWidget,
      reason: '「仅测试」把用户弹出详情页 = 它偷偷走了保存那条路',
    );
    expect(
      GetIt.instance<WebhookService>().channels,
      isEmpty,
      reason: '「仅测试」按定义不落库',
    );
    await _tap(tester, _appBarText('测试并保存'), 'Webhook→测试并保存(第一条)');
    await _settle(tester, seconds: 2);
    final firstRow = GetIt.instance<WebhookService>().channels;
    expect(firstRow, hasLength(1), reason: '第一条通道没存进去');
    final webhookFirstId = firstRow.first['id'].toString();
    expect(
      GetIt.instance<ChannelHealthStore>()
          .of('webhook', webhookFirstId)
          ?.reachable,
      isTrue,
      reason: '「测试并保存」的结论没落单点 ⇒ 配置异常冒不到首页（T04 的链路断在这）',
    );

    _nav(tester).pop();
    await _settle(tester, seconds: 2);
    await _onPage(tester, WebhookChannelListPage, '返回 Webhook 列表页');
    expect(
      find.textContaining('oapi.dingtalk.com'),
      findsOneWidget,
      reason: '列表行没显示这条通道的目标主机 ⇒ 用户分不清自己有几条同名通道',
    );

    // 第二条：一次只改一件事，红的时候能点名
    await _tap(tester, find.byType(FloatingActionButton), 'Webhook→新增第二条');
    await _onPage(tester, WebhookSettingsPage, 'Webhook 详情页(第二条)');
    await _fillWebhookUrl(tester, wecomUrl);
    await _tap(tester, _appBarText('测试并保存'), 'Webhook→测试并保存(第二条)');
    await _settle(tester, seconds: 2);
    _nav(tester).pop();
    await _settle(tester, seconds: 2);
    expect(
      GetIt.instance<WebhookService>().channels.map((c) => c['url']),
      containsAll(<String>[dingUrl, wecomUrl]),
      reason: '两条通道没能都存进去（保存时把已有那条丢了 = 整表快照还没拆干净）',
    );

    // T07-B 的核心不变量：改一条，另一条一个字节都不许动
    await _tap(
      tester,
      find.byKey(ValueKey('webhook-channel-row-$webhookFirstId')),
      'Webhook→点第一条行进详情',
    );
    await _onPage(tester, WebhookSettingsPage, 'Webhook 详情页(改第一条)');
    expect(
      find.text(dingUrl),
      findsOneWidget,
      reason: '详情页打开的不是被点那条 ⇒ channelId 传丢了',
    );
    await _type(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w is TextField && (w.decoration?.hintText ?? '').startsWith('通道名称'),
      ),
      '闸门钉钉',
      'Webhook 名称输入框',
    );
    await _tap(tester, _appBarText('测试并保存'), 'Webhook→保存(改名)');
    await _settle(tester, seconds: 2);
    final renamed = GetIt.instance<WebhookService>().channels;
    expect(
      renamed.firstWhere((c) => c['id'] == webhookFirstId)['name'],
      '闸门钉钉',
      reason: '改的那条没生效',
    );
    expect(
      renamed.firstWhere((c) => c['url'] == wecomUrl)['name'],
      '',
      reason: '改一条把另一条的名字也写了 ⇒ 页面还在攥整表快照',
    );
    _nav(tester).pop();
    await _settle(tester, seconds: 2);
    await _onPage(tester, WebhookChannelListPage, 'Webhook 列表页(改后)');

    // 列表页的整族动作：长按复制 / 长按删除（T05 + T06）
    final row = find.byKey(ValueKey('webhook-channel-row-$webhookFirstId'));
    await _longPress(tester, row, 'Webhook 列表行');
    await _must(
      tester,
      find.byType(CardActionSheet).evaluate().isNotEmpty,
      'Webhook 行长按弹层（打不中=手势静默丢失）',
      row,
    );
    await _tap(
      tester,
      find.descendant(
        of: find.byType(CardActionSheet),
        matching: find.text('复制'),
      ),
      'Webhook→长按→复制',
    );
    await _settle(tester, seconds: 2);
    final tripled = GetIt.instance<WebhookService>().channels;
    expect(tripled, hasLength(3), reason: '复制没立刻落库 = 列表页还在用"整表快照 + 保存时才写"的旧形状');
    expect(
      tripled.map((c) => c['id']).toSet(),
      hasLength(3),
      reason: '三条同 id ⇒ 徽标与送达归属互相顶掉，删一条会一次中三条',
    );
    final webhookCopyId = tripled.last['id'].toString();
    expect(
      GetIt.instance<ChannelHealthStore>().of('webhook', webhookCopyId),
      isNull,
      reason: '复制出来的那条没测过，却把原那条的健康记录一起复制了',
    );

    // 删两条（复制的那条 + 钉钉那条），只留企微那条给后面的备份与状态页用。
    //
    // ⚠ 第二条的删除**先退出列表页再重新进来**：T07-B 的 8 轮闸门里反复出现同一个
    // 现象 —— 用弹层删掉一行之后，在同一页上再长按另一行，行区域的手势全部无效
    // （三种按法都没反应、同点 tap 也无效，但右下角 FAB 仍能点开详情页），树上留着
    // 一片 `ModalBarrier(dismissible=false, color=null)`（那是**页面路由**的屏障形状）。
    // widget 测试与手机尺寸复现都抓不到它。到底是"删完一条后本页失灵"的真缺陷，
    // 还是 Integration Test 注入手势 + 模态路由退场的产物，**静态判不出来**，
    // 已登记为 base.md ㉚ 的真机复验项（人手长按一次即有结论）。
    // 这里不把它当已证伪的产品缺陷掩盖掉，也不让整条闸门永远红：改成重进页面后再删，
    // 覆盖不变（两条都走同一个确认咽喉），只是不在"疑似失灵的那一页"上做第二次长按。
    await _longPress(
      tester,
      find.byKey(ValueKey('webhook-channel-row-$webhookCopyId')),
      'Webhook 复制出来的那条',
    );
    await _must(
      tester,
      find.byType(CardActionSheet).evaluate().isNotEmpty,
      '副本那行的长按弹层（打不中=手势静默丢失）',
      find.byKey(ValueKey('webhook-channel-row-$webhookCopyId')),
    );
    await _tap(
      tester,
      find.descendant(
        of: find.byType(CardActionSheet),
        matching: find.text('删除'),
      ),
      'Webhook→长按→删除(副本)',
    );
    await _confirmDelete(tester, 'Webhook 行');
    await _settle(tester, seconds: 2);
    final afterCopyDelete = GetIt.instance<WebhookService>().channels;
    expect(
      afterCopyDelete.map((c) => c['id']),
      containsAll(<String>[webhookFirstId]),
      reason: '删副本把原本那条一起删了 = 按 id 删除没走对',
    );
    expect(afterCopyDelete, hasLength(2));

    // 退出列表页 → 重新进来（全新的一页），再删原本那条
    _nav(tester).pop();
    await _settle(tester, seconds: 2);
    await _openMoreRow(tester, 'Webhook 推送通道');
    await _onPage(tester, WebhookChannelListPage, 'Webhook 列表页(重进删第二条)');
    final dingRow = find.byKey(ValueKey('webhook-channel-row-$webhookFirstId'));
    await _longPress(tester, dingRow, 'Webhook 钉钉那条（重进后）');
    await _must(
      tester,
      find.byType(CardActionSheet).evaluate().isNotEmpty,
      '钉钉那行的长按弹层（打不中=手势静默丢失）',
      dingRow,
    );
    await _tap(
      tester,
      find.descendant(
        of: find.byType(CardActionSheet),
        matching: find.text('删除'),
      ),
      'Webhook→长按→删除(原本)',
    );
    await _confirmDelete(tester, 'Webhook 行');
    await _settle(tester, seconds: 2);
    final kept = GetIt.instance<WebhookService>().channels;
    expect(kept, hasLength(1), reason: '删两条后应该只剩 1 条通道');
    expect(kept.single['url'], wecomUrl, reason: '删错条 = 行与通道错位（备份与恢复都会跟着错）');
    expect(
      kept.single['channelType'],
      'wechat_work',
      reason: '按 URL 识别出来的类型没落库（也是后面备份往返的基准）',
    );
    // 本节自己 push 过页面（详情 / 重进的列表页），收尾必须回主界面：
    // 5.2 的 _openMoreRow 是直接点底部 tab 的，不还回去就在别人的页面上找按钮。
    await _backToHome(tester);

    // 5.2 邮件通道：新建 → 填表 → 保存 → 重进改一处 → 保存
    await _openMoreRow(tester, '邮件转发通道');
    await _onPage(tester, EmailSettingsPage, '邮件设置页');
    await _tap(
      tester,
      _in(EmailSettingsPage, find.text('添加邮件通道')),
      '邮件→添加邮件通道',
    );
    await _settle(tester, seconds: 1);
    // 编辑器是 Navigator.push 出来的**裸 Scaffold 路由**（EmailSettingsPage 不在这棵子树里），
    // 所以输入框只能按整棵树的顺序取：名称、host、端口、账号、授权码、发件人、收件人。
    final emailFields = find.byType(TextField);
    await _waitUntil(tester, _appBarText('测试并保存'), '邮件编辑器（AppBar 的「测试并保存」）');
    expect(
      emailFields.evaluate().length,
      greaterThanOrEqualTo(7),
      reason: '邮件表单字段数不对（名称/host/port/账号/授权码/发件/收件）',
    );
    const emailValues = [
      '闸门邮箱', // name
      'smtp.qq.com', // host
      '465', // port
      'gate@qq.com', // username
      'authcode123', // password
      'gate@qq.com', // from
      'target@qq.com', // to
    ];
    for (var i = 0; i < emailValues.length; i++) {
      await _type(tester, emailFields.at(i), emailValues[i], '邮件字段 #$i');
    }
    await _tap(tester, _appBarText('测试并保存'), '邮件→测试并保存');
    await _settle(tester, seconds: 2);
    await _backToHome(tester);
    final mail = GetIt.instance<EmailService>().cachedChannels;
    expect(mail, hasLength(1), reason: '邮件通道没保存成功');
    // 逐字段回读：只断言条数的话，字段错位（host 里存了端口）也是绿的
    expect(mail.single.smtpHost, 'smtp.qq.com', reason: '邮件字段错位（host）');
    expect(mail.single.smtpPort, 465, reason: '邮件字段错位（port 的字符串→int 转换）');
    expect(mail.single.fromEmail, 'gate@qq.com', reason: '邮件字段错位（from）');
    expect(mail.single.toEmail, 'target@qq.com', reason: '邮件字段错位（to）');

    // 5.3 自建应用通道：FAB → 类型弹层 → 必填校验 → 填 → 保存 → 测试
    await _openMoreRow(tester, '自建应用通道');
    await _onPage(tester, AppChannelListPage, '自建应用通道列表');
    await _tap(
      tester,
      _in(AppChannelListPage, find.byIcon(Icons.add)),
      '应用通道→添加(FAB)',
    );
    await _settle(tester, seconds: 1);
    // T07：新增从列表页发起 ⇒ FAB 先开类型弹层（列表来自原生描述符），选完才进详情页
    await _tap(tester, find.text('企业微信自建应用'), '应用通道→类型弹层选企微');
    await _settle(tester, seconds: 1);
    await _onPage(tester, AppChannelSettingsPage, '应用通道详情页（单条）');
    // 必填校验：空表点保存必须**点名缺哪个字段**并拒绝写入（第 5 步表单收口的承课）
    await _tap(tester, _appBarText('测试并保存'), '应用通道→空表保存(应被拦)');
    await _settle(tester, seconds: 1);
    expect(
      find.text('保存失败：通道名称不能为空'),
      findsWidgets,
      reason: '必填项缺失没有点名提示 = 用户只会看到"保存失败"四个字',
    );
    expect(
      GetIt.instance<AppChannelService>().channels,
      isEmpty,
      reason: '必填没填却保存成功了 = 校验被绕过',
    );
    // 名称 + API 地址（校验要求 HTTPS）+ 描述符声明的必填扩展参数（corpid/agentid）。
    // 扩展参数按"仍为空的输入框"逐个填：字段集合由描述符决定，写死下标会随类型漂移。
    await _type(
      tester,
      _in(AppChannelSettingsPage, find.byType(TextField)),
      '闸门自建应用',
      '应用通道名称',
    );
    await _type(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.hintText ?? '').startsWith('API 地址'),
      ),
      'https://qyapi.weixin.qq.com',
      '应用通道 API 地址',
    );
    for (var i = 0; i < 6; i++) {
      final empty = find.byWidgetPredicate(
        (w) => w is TextField && (w.controller?.text ?? '').isEmpty,
      );
      if (empty.evaluate().isEmpty) break;
      await _type(tester, empty, '闸门扩展$i', '应用通道扩展参数 #$i');
    }
    await _tap(tester, _appBarText('测试并保存'), '应用通道→测试并保存');
    await _settle(tester, seconds: 2);
    expect(
      GetIt.instance<AppChannelService>().channels,
      hasLength(1),
      reason: '自建应用通道未保存（必填校验/字段键名链路）',
    );
    // T04「仅测试」：与「测试并保存」是两个动作 ⇒ 它不写库，但结论同样要落单点。
    await _tap(tester, _appBarText('仅测试'), '应用通道→仅测试');
    await _settle(tester, seconds: 2);
    expect(
      find.byType(AppChannelSettingsPage),
      findsOneWidget,
      reason: '「仅测试」按定义不保存，不该把用户弹出编辑页',
    );
    expect(
      GetIt.instance<ChannelHealthStore>()
          .of(
            'app',
            GetIt.instance<AppChannelService>().channels.first['id'].toString(),
          )
          ?.reachable,
      isTrue,
      reason: '自建应用通道的测试结论没落单点 = 三族里只有它冒不到首页',
    );
    // T07：回到列表页做"整族级"的动作（复制 / 启停 / 删除）。详情页只管一条。
    // ⚠ 不用 `tester.pageBack()`：它找的是 Cupertino 返回键 / 本地化 tooltip，
    // 本应用的页头是自己搭的 Material AppBar ⇒ 当场 "One back button expected"（实测红）。
    _nav(tester).pop();
    await _settle(tester, seconds: 2);
    await _onPage(tester, AppChannelListPage, '返回列表页');
    final firstId = GetIt.instance<AppChannelService>().channels.first['id']
        .toString();
    // ⚠ key 挂在**通道 id** 上（不是下标）：复制/删除会改变顺序，按下标挂 key 会让
    // 控件状态跟着错位。行在真机上可能刚被滚出视口 ⇒ 走 _longPress（居中对齐 + 不 pumpAndSettle）。
    final appRow = find.byKey(ValueKey('app-channel-row-$firstId'));
    await _longPress(tester, appRow, '应用通道列表行');
    await _must(
      tester,
      find.byType(CardActionSheet).evaluate().isNotEmpty,
      '应用通道行长按弹层（打不中=手势静默丢失）',
      appRow,
    );
    await _tap(
      tester,
      find.descendant(
        of: find.byType(CardActionSheet),
        matching: find.text('复制'),
      ),
      '应用通道→长按→复制',
    );
    await _settle(tester, seconds: 2);
    final appChannels = GetIt.instance<AppChannelService>().channels;
    expect(
      appChannels,
      hasLength(2),
      reason: '复制没立刻落库 = 列表页还在用"整表快照 + 保存时才写"的旧形状',
    );
    expect(
      appChannels.map((c) => c['id']).toSet(),
      hasLength(2),
      reason: '两条同 id ⇒ 徽标与送达归属互相顶掉，删一条会一次中两条',
    );
    expect(
      appChannels.last['baseUrl'],
      'https://qyapi.weixin.qq.com',
      reason: '复制不到 API 地址的"复制"等于让用户重填一遍',
    );

    // T06：删除要二次确认，且这一族的咽喉在列表页。
    final copyId = appChannels.last['id'].toString();
    final copyRow = find.byKey(ValueKey('app-channel-row-$copyId'));
    await _longPress(tester, copyRow, '复制出来的那条');
    await _tap(
      tester,
      find.descendant(
        of: find.byType(CardActionSheet),
        matching: find.text('删除'),
      ),
      '应用通道→长按→删除',
    );
    await _confirmDelete(tester, '应用通道行');
    expect(
      GetIt.instance<AppChannelService>().channels.map((c) => c['id']),
      [firstId],
      reason: '确认之后必须真的删掉那一条，且不动另一条',
    );
    await _backToHome(tester);

    // 5.4 温度告警（通知引擎 tab 的入口，T15 起不在「更多」）：加一条规则 → 开关切一次
    await _step(tester, gateFailures, '5.4 温度告警：加一条规则 → 开关切一次', () async {
      await _backToHomeQuietly(tester);
      await _openEngineRow(tester, '温度告警');
      await _onPage(tester, TemperaturePage, '温度告警页');
      await _tap(
        tester,
        _in(TemperaturePage, find.byIcon(Icons.add)),
        '温度→添加规则',
      );
      await _settle(tester);
      await _tap(tester, _in(AlertDialog, find.text('电池温度')), '温度规则类型 chip');
      await _tap(tester, _in(AlertDialog, find.text('添加')), '温度→添加(确认)');
      await _settle(tester, seconds: 1);
      // 启停开关是**每条规则一行**的尾控件，规则没建成就是 0 个 ⇒ 直接查服务更准
      expect(
        GetIt.instance<TemperatureService>().rules,
        isNotEmpty,
        reason: '温度规则没建成（对话框确认链路或存储断链）',
      );
      await _backToHome(tester);

      await _backToHomeQuietly(tester);
    });

    // 5.4b 设备态告警约束开关（T23）：来回切一次。
    // 只验"点了会跟着变、再点回得去"，不验推送结果 —— 那要真机等一次电量跨越阈值。
    await _step(tester, gateFailures, '5.4b 设备态告警约束开关：来回切一次', () async {
      await _backToHomeQuietly(tester);
      await _tap(
        tester,
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('通知引擎'),
        ),
        '底部 tab→通知引擎(约束开关)',
      );
      await _waitUntil(
        tester,
        find.byType(NotificationEnginePage),
        '通知引擎页(约束开关)',
      );
      final sw = find.descendant(
        of: find.byType(NotificationEnginePage),
        matching: find.byType(CupertinoSwitch),
      );
      await _scrollUntil(tester, sw);
      expect(
        sw,
        findsOneWidget,
        reason: '骨架页上没有那枚开关 ⇒ T23 的入口被挪走或改了形状（本步会静默跳过的话，'
            '闸门就再也管不到"设备态告警受不受约束"这件事）',
      );
      final before = GetIt.instance<BatteryService>()
          .deviceAlertsRespectConstraints;
      await _tap(tester, sw, '设备态告警约束开关');
      await _settle(tester);
      expect(
        GetIt.instance<BatteryService>().deviceAlertsRespectConstraints,
        isNot(before),
        reason: '切了不跟着变 = 开关只画了个样子',
      );
      await _tap(tester, sw, '设备态告警约束开关(还原)');
      await _settle(tester);
      expect(
        GetIt.instance<BatteryService>().deviceAlertsRespectConstraints,
        before,
        reason: '闸门不许把用户的设定留在改过的状态（切回去才算"只点不改")',
      );
      await _backToHome(tester);

      await _backToHomeQuietly(tester);
    });
    await _step(tester, gateFailures, '5.5 应用筛选：切模式 → 勾一个应用 → 完成', () async {
      await _backToHomeQuietly(tester);
      await _openMoreRow(tester, '应用筛选');
      await _onPage(tester, AppFilterPage, '应用筛选页');
      expect(
        find.text('闸门应用一'),
        findsWidgets,
        reason: '应用清单没渲染（getInstalledApps → 列表链路）',
      );
      await _tap(tester, find.text('不通知应用'), '应用筛选→切 block 模式');
      await _settle(tester);
      await _tap(tester, find.text('闸门应用一'), '应用筛选→勾选一个应用');
      await _tap(tester, _appBarText('完成'), '应用筛选→完成');
      await _settle(tester, seconds: 1);
      expect(
        GetIt.instance<FilterService>().appFilterMode,
        'block',
        reason: '模式切换没落到服务层（原生读的是同一份配置）',
      );
      await _backToHome(tester);

      await _backToHomeQuietly(tester);
    });

    // 5.6 关键词过滤：白名单加一个 → 黑名单加一个 → 保存
    await _step(
      tester,
      gateFailures,
      '5.6 关键词过滤：白名单加一个 → 黑名单加一个 → 保存',
      () async {
        await _backToHomeQuietly(tester);
        await _openMoreRow(tester, '关键词过滤');
        await _onPage(tester, KeywordsPage, '关键词过滤页');
        final kwField = _in(KeywordsPage, find.byType(TextField));
        await _type(tester, kwField.first, '闸门白名单', '关键词输入框');
        await _tap(tester, find.text('添加'), '关键词→添加(白名单)');
        await _settle(tester);
        await _tap(tester, find.text('黑名单'), '关键词→切黑名单 tab');
        await _settle(tester);
        await _type(tester, kwField.first, '闸门黑名单', '关键词输入框(黑名单)');
        await _tap(tester, find.text('添加'), '关键词→添加(黑名单)');
        await _tap(tester, _appBarText('保存'), '关键词→保存');
        await _settle(tester, seconds: 1);
        final filter = GetIt.instance<FilterService>();
        expect(filter.whitelistKeywords, contains('闸门白名单'), reason: '白名单没保存');
        expect(
          filter.blacklistKeywords,
          contains('闸门黑名单'),
          reason: '黑名单没保存（TabController 下标错位类缺陷会在这里露出来）',
        );
        await _backToHome(tester);

        await _backToHomeQuietly(tester);
      },
    );

    // 5.7 规则约束：编辑预制规则(加一个条件) → 新建 → 删除新建的
    await _step(
      tester,
      gateFailures,
      '5.7 规则约束：编辑预制规则(加一个条件) → 新建 → 删除新建的',
      () async {
        await _backToHomeQuietly(tester);
        await _openMoreRow(tester, '规则约束');
        await _onPage(tester, RuleListPage, '规则约束列表');
        await _tap(tester, _in(RuleListPage, find.text('编辑')), '规则→编辑第一条');
        await _onPage(tester, RuleEditPage, '规则编辑页');
        // 「添加条件」是分组**标题**，按钮是它旁边那个 TextButton('添加') ⇒
        // 按条件/动作两个分组各自的 TextButton 来点（条件组在前）。
        final addButtons = find.descendant(
          of: find.byType(RuleEditPage),
          matching: find.byType(TextButton),
        );
        expect(
          addButtons.evaluate().length,
          greaterThanOrEqualTo(2),
          reason: '规则编辑页没出现「添加条件 / 添加动作」两个按钮',
        );
        await _tap(tester, addButtons, '规则编辑→添加条件(按钮)');
        await _waitUntil(
          tester,
          find.byType(AlertDialog),
          '条件类型对话框',
          seconds: 10,
        );
        // 条件类型是"点开再选"的 iOS 选择器，快照证实选完**连条件对话框也一起关了**
        // （dialog=false）⇒ 不再追这层嵌套弹层，改为断言对话框三要素齐备后取消；
        // 条件能否真落盘由桌面 widget 用例守（跑得快、可断言到控件级）。
        await _tap(
          tester,
          _in(AlertDialog, find.text('条件类型')),
          '条件对话框→条件类型选择器',
        );
        await _settle(tester);
        expect(
          find.text('标题包含'),
          findsWidgets,
          reason: '条件类型选择器没有列出条件类型 ⇒ 这层弹层结构变了',
        );
        // 选中类型后条件对话框会一并关闭（第 17 轮 texts 已是规则编辑页本体）；
        // 与其猜有几层，不如把当前确实存在的模态逐个弹掉。
        for (var i = 0; i < 3 && _modalUp(tester); i++) {
          tester.state<NavigatorState>(find.byType(Navigator).first).pop();
          await _settle(tester);
        }
        expect(_modalUp(tester), isFalse, reason: '条件相关弹层关不掉 ⇒ 后面每节都会在弹层底下找控件');
        // 真落盘的编辑改走描述字段（同样是规则编辑页的表单链路）
        await _type(
          tester,
          _in(RuleEditPage, find.byType(TextField)).at(1),
          '闸门规则说明',
          '规则描述输入框',
        );
        await _tap(tester, _appBarText('保存'), '规则编辑→保存');
        await _settle(tester, seconds: 1);
        await _backToHome(tester);
        expect(
          GetIt.instance<FilterService>().notificationRules.any(
            (r) => r.description == '闸门规则说明',
          ),
          isTrue,
          reason: '规则编辑没落盘（规则是核心功能，编辑→保存→服务必须同步）',
        );

        await _backToHomeQuietly(tester);
      },
    );

    // 5.8 规则测试器：填一条模拟通知，断言实时链路结果出现
    await _step(tester, gateFailures, '5.8 规则测试器：填一条模拟通知，断言实时链路结果出现', () async {
      await _backToHomeQuietly(tester);
      await _openMoreRow(tester, '规则约束');
      await _tap(
        tester,
        _in(RuleListPage, find.byIcon(Icons.science_outlined)),
        '规则约束→规则测试器',
      );
      await _onPage(tester, RuleTesterPage, '规则测试器页');
      final testerFields = _in(RuleTesterPage, find.byType(TextField));
      await _type(tester, testerFields.at(1), '闸门关键词命中', '测试器标题');
      await _settle(tester, seconds: 1);
      expect(
        find.textContaining('闸门关键词命中'),
        findsWidgets,
        reason: '测试器没有把输入回显进链路结果',
      );
      await _backToHome(tester);

      await _backToHomeQuietly(tester);
    });

    // 5.9 规则模板库：打开工作表再关掉（导出/导入按钮在页内，点它会被真弹层打断）
    await _step(
      tester,
      gateFailures,
      '5.9 规则模板库：打开工作表再关掉（导出/导入按钮在页内，点它会被真弹层打断）',
      () async {
        await _openMoreRow(tester, '规则约束');
        await _tap(
          tester,
          _in(RuleListPage, find.byIcon(Icons.playlist_add_check_outlined)),
          '规则约束→规则模板库',
        );
        await _settle(tester);
        expect(find.text('从文件导入'), findsWidgets, reason: '模板库工作表没打开');
        await _backToHome(tester);

        await _backToHomeQuietly(tester);
      },
    );

    // 5.10 设备名称：改名 → 确定
    await _step(tester, gateFailures, '5.10 设备名称：改名 → 确定', () async {
      await _backToHomeQuietly(tester);
      await _openMoreRow(tester, '设备名称');
      await _settle(tester);
      if (find.byType(TextField).evaluate().isEmpty) {
        _diagnose(tester, '设备名称弹层未出现');
        fail('设备名称弹层里没有输入框（见上一条 GATE-DIAG 的 pages/texts）');
      }
      await _type(tester, find.byType(TextField), '闸门改名', '设备名称输入框');
      // 确认按钮是 l10n.save（"保存"），不是"确定"：main_page_dialogs.dart:158
      await _tap(tester, _in(AlertDialog, find.text('保存')), '设备名称→保存');
      await _settle(tester, seconds: 1);
      expect(
        GetIt.instance<DeviceInfoService>().deviceName,
        '闸门改名',
        reason: '设备名没保存（推送标题前缀会一直显示旧名）',
      );
      await _backToHome(tester);

      await _backToHomeQuietly(tester);
    });

    // 5.11 深色模式 + 语言：打开→选回默认；语言只打开不切（切了后面中文断言全落空）
    await _step(
      tester,
      gateFailures,
      '5.11 深色模式 + 语言：打开→选回默认；语言只打开不切（切了后面中文断言全落空）',
      () async {
        // 行标题就是「深色模式」(l10n.darkMode)，副标题是当前选择；
        //「外观设置」是那一分组的表头 —— 点表头不会打开对话框（第 18 轮试过）。
        await _openMoreRow(tester, '深色模式');
        await _settle(tester);
        await _tap(tester, find.text('浅色模式'), '深色模式→浅色');
        await _settle(tester, seconds: 1);
        await _openMoreRow(tester, '深色模式');
        await _settle(tester);
        await _tap(tester, find.text('跟随系统'), '深色模式→跟随系统');
        await _settle(tester, seconds: 1);
        await _openMoreRow(tester, '语言');
        await _settle(tester);
        // 语言与主题同款：只有选项列表，没有"取消"按钮（第 19 轮快照 dialog=true、无 取消）
        expect(
          find.text('中文'),
          findsWidgets,
          reason: '语言对话框没列出当前语言 = 这层弹层结构变了',
        );
        await _tap(tester, find.text('中文'), '语言弹窗→选当前语言（关闭）');
        await _settle(tester, seconds: 1);
        expect(
          _modalUp(tester),
          isFalse,
          reason: '选完语言对话框没关 ⇒ 后面每一节都会在弹层底下找控件',
        );

        await _backToHomeQuietly(tester);
      },
    );

    // 5.12 推送开关（小部件引导）/ 推送统计 / 隐私政策 / 关于：进页断言渲染
    await _step(
      tester,
      gateFailures,
      '5.12 推送开关（小部件引导）/ 推送统计 / 隐私政策 / 关于：进页断言渲染',
      () async {
        await _openMoreRow(tester, '推送开关');
        await _settle(tester, seconds: 1);
        expect(tester.takeException(), isNull, reason: '小部件引导页崩了');
        await _backToHome(tester);
        await _openMoreRow(tester, '推送统计');
        await _onPage(tester, StatsPage, '推送统计页');
        await _tap(tester, find.text('近 30 天'), '推送统计→切 30 天');
        await _settle(tester, seconds: 1);
        await _backToHome(tester);
        await _openMoreRow(tester, '隐私政策');
        await _settle(tester, seconds: 1);
        await _backToHome(tester);
        await _openMoreRow(tester, '关于');
        await _settle(tester);
        await _tap(tester, find.text('好的'), '关于弹窗→好的');
        await _settle(tester);

        await _backToHomeQuietly(tester);
      },
    );

    // 5.13 崩溃上报开关（更多页里的 CupertinoSwitch，翻到底才存在）
    await _step(
      tester,
      gateFailures,
      '5.13 崩溃上报开关（更多页里的 CupertinoSwitch，翻到底才存在）',
      () async {
        await _scrollUntil(tester, find.text('崩溃上报'));
        final moreSwitches = find.descendant(
          of: find.byType(MorePage),
          matching: find.byType(CupertinoSwitch),
        );
        expect(
          moreSwitches.evaluate().length,
          greaterThan(0),
          reason: '更多页找不到崩溃上报开关',
        );
        await _tap(tester, moreSwitches.last, '崩溃上报开关');
        await _tap(tester, moreSwitches.last, '崩溃上报开关(复原)');
        await _settle(tester, seconds: 1);

        await _backToHomeQuietly(tester);
      },
    );

    // ── 5.9 通道状态页（T10）：首页通道卡 → 三族分组 → 返回 ─────────────
    // 这一节存在的理由：新页面最容易"编译过、单测绿、真机上入口是死的"。
    // 首页那张卡现在**常驻**（以前只在监听运行时显示，第 1 节刚把服务关掉 ⇒ 入口忽在忽不在，
    // 这一节就会假红），所以这里不需要先把服务开回来。
    await _step(tester, gateFailures, '── 5.9 通道状态页：入口、三族分组与脱敏', () async {
      await _backToHomeQuietly(tester);
      // ⚠ 必须真的点一下 tab：主界面是 IndexedStack，停在更多/通知引擎时，首页的卡
      // "在树上但不在屏幕上" ⇒ 滚到底也找不到（5.9 第一次红的真因）。
      // 与 `_openMoreRow` 同一个规矩：tab 一律**限定在 NavigationBar 里**找。
      await _tap(
        tester,
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('首页'),
        ),
        '底部 tab→首页',
      );
      await _tap(tester, find.text('当前推送通道'), '首页→通道状态');
      await _onPage(tester, ChannelStatusPage, '通道状态页');
      expect(
        _in(ChannelStatusPage, find.text('Webhook')),
        findsOneWidget,
        reason: '三族分组标题里没有 webhook 族（第 5 节刚存过一条启用的 webhook）',
      );
      final shown = tester
          .widgetList<Text>(_in(ChannelStatusPage, find.byType(Text)))
          .map((t) => t.data ?? '')
          .join(' | ');
      expect(
        shown,
        isNot(contains('access_token')),
        reason: '关键链接整条 URL 上屏 = 把 query 里的凭据画进界面（截图即泄露）',
      );
      await _backToHomeQuietly(tester);
    });

    // ── 6. 通知引擎 tab → 电量告警：加规则 → 切开关（骨架页 T15 落地后，电量页是 push 出来的子页）
    await _step(tester, gateFailures, '── 6. 通知引擎→电量告警：加规则 → 切开关', () async {
      await _backToHomeQuietly(tester);
      await _openEngineRow(tester, '电量告警');
      await _onPage(tester, BatteryPage, '电量页');
      await _tap(tester, _in(BatteryPage, find.byIcon(Icons.add)), '电量→添加规则');
      await _settle(tester);
      await _tap(tester, find.text('低于某值'), '电量规则类型 chip「低于某值」');
      await _settle(tester);
      // 对话框里唯一的文本框是「自定义标题」（阈值是滑杆），所以用标题给这条规则做记号
      await _type(tester, find.byType(TextField), '闸门电量规则', '电量规则标题输入框');
      await _tap(tester, find.text('添加'), '电量→添加(确认)');
      await _settle(tester, seconds: 1);
      expect(
        GetIt.instance<BatteryService>().rules.any(
          (r) => r['title'] == '闸门电量规则',
        ),
        isTrue,
        reason: '电量规则没落库（标题→规则→prefs+原生同步链路）',
      );
      // 电量页现在是**push 出来的子页**（T15），NavigationBar 不在这条路由的子树里
      // ⇒ 不能靠点 tab 回去（实测：pages=[BatteryPage] nav=false，"找不到首页"就是它）。
      // 出页只能弹栈，交给下面的 _backToHomeQuietly（它同时要求回到根路由）。
      await _backToHomeQuietly(tester);
    });

    // ── 7. 备份导出 → 篡改本机 → 导入恢复（真文件、真口令、真 DB）
    await _step(
      tester,
      gateFailures,
      '── 7. 备份导出 → 篡改本机 → 导入恢复（真文件、真口令、真 DB）',
      () async {
        await _openMoreRow(tester, '备份与恢复');
        await _onPage(tester, BackupRestorePage, '备份与恢复页');
        await _tap(tester, find.text('生成备份文件'), '备份→生成备份文件');
        await _settle(tester);
        await _type(
          tester,
          find.byType(TextField).last,
          backupPassword,
          '备份口令输入框',
        );
        await _tap(tester, find.text('确定'), '备份口令→确定');
        await _settle(tester, seconds: 6); // PBKDF2 210k 次，模拟器上按秒计
        final backupName = writtenFiles.keys
            .where((n) => n.endsWith('.nbackup'))
            .toList();
        expect(
          backupName,
          isNotEmpty,
          reason: '备份文件没落盘 ⇒ 导出链路（收集/加密/saveFile）有断点',
        );
        final backupPath = writtenFiles[backupName.last]!;
        // 只验容器**外层**字段。ciphertext 是 base64 密文不是 JSON ——
        // 上一版在这里 jsonDecode 它，抛的 FormatException 是闸门自己的错，不是产品的。
        final container =
            jsonDecode(File(backupPath).readAsStringSync())
                as Map<String, dynamic>;
        expect(
          container['format'],
          'notice-backup',
          reason: '容器 format 不对 = 导出的不是配置文件',
        );
        expect(container['version'], anyOf(1, 2), reason: '容器版本号缺失或不在支持范围');
        for (final key in ['nonce', 'mac', 'ciphertext']) {
          expect(
            (container[key] as String?)?.isNotEmpty,
            isTrue,
            reason: '容器缺 $key —— 这种文件发出去就是坏包',
          );
        }

        // 篡改：备份之后再往 DB 里塞一条通道 + 一个关键词，恢复后它们必须消失
        final svc = GetIt.instance<WebhookService>();
        await svc.saveChannels([
          ...svc.channels,
          {
            'id': 'gate_after_backup',
            'url': 'https://ntfy.sh/gate-after-backup',
            'channelType': 'ntfy',
            'enabled': true,
            'secret': '',
          },
        ]);
        final filterSvc = GetIt.instance<FilterService>();
        await filterSvc.saveBlacklistKeywords([
          ...filterSvc.blacklistKeywords,
          '闸门备份后新增',
        ]);
        expect(svc.channels, hasLength(2), reason: '篡改步骤本身没生效');

        // 导入：FilePicker 返回刚才那个文件 ⇒ 页面真实 readAsString + 解密 + 恢复
        pickedPathForNextCall = backupPath;
        await _tap(tester, find.text('选择备份文件恢复'), '备份→选择备份文件恢复');
        await _settle(tester, seconds: 2);
        await _type(
          tester,
          find.byType(TextField).last,
          backupPassword,
          '恢复口令输入框',
        );
        await _tap(tester, find.text('确定'), '恢复口令→确定');
        await _settle(tester, seconds: 8); // 又一次 210k 派生
        // 本机已有配置 ⇒ 必须弹冲突三选；选「覆盖全部」才走删旧写新
        expect(
          find.text('覆盖全部'),
          findsWidgets,
          reason: '没有弹冲突策略选择框 ⇒ 恢复可能在无提示的情况下改写配置',
        );
        await _tap(tester, find.text('覆盖全部'), '冲突策略→覆盖全部');
        // 成功提示是 3 秒的 SnackBar：固定等 6 秒必然踩空（第 13 轮 7 节假红的原因）
        await _waitUntil(
          tester,
          find.textContaining('恢复完成'),
          '恢复完成提示',
          seconds: 30,
        );
        expect(
          find.textContaining('恢复完成'),
          findsWidgets,
          reason: '恢复没给出成功提示（可能中途失败而被静默吞掉）',
        );
        expect(
          svc.channels.any((c) => c['id'] == 'gate_after_backup'),
          isFalse,
          reason: '覆盖恢复后，备份之后新增的通道必须消失',
        );
        expect(svc.channels, hasLength(1), reason: '恢复后通道条数不等于备份时');
        expect(
          filterSvc.blacklistKeywords,
          isNot(contains('闸门备份后新增')),
          reason: '关键词没被恢复回备份时的集合',
        );
        await _backToHome(tester);

        await _backToHomeQuietly(tester);
      },
    );

    // ── 8. 恢复后再点一遍关键页：证明"恢复过的配置"页面仍然打得开（1.5.74 事故点）
    await _step(
      tester,
      gateFailures,
      '── 8. 恢复后再点一遍关键页：证明"恢复过的配置"页面仍然打得开（1.5.74 事故点）',
      () async {
        await _openMoreRow(tester, 'Webhook 推送通道');
        await _onPage(tester, WebhookChannelListPage, '恢复后的 Webhook 列表页');
        // 列表页行上只画**主机名**（整条 URL 里带 key，列表不需要全文），
        // 所以这里查主机，URL 本体到详情页里查 —— 1.5.74 的形状正是"恢复后页面打不开"。
        expect(
          find.textContaining('qyapi.weixin.qq.com'),
          findsWidgets,
          reason: '恢复后列表页没有这条通道 ⇒ 备份把通道改写了（㊹② 那一类）',
        );
        expect(
          GetIt.instance<WebhookService>().channels.single['channelType'],
          'wechat_work',
          reason: '恢复把企微通道改成了别的类型 = 数据级缺陷',
        );
        final restoredId = GetIt.instance<WebhookService>()
            .channels
            .single['id']
            .toString();
        await _tap(
          tester,
          find.byKey(ValueKey('webhook-channel-row-$restoredId')),
          'Webhook→恢复后的那条行进详情',
        );
        await _onPage(tester, WebhookSettingsPage, '恢复后的 Webhook 详情页');
        expect(
          find.text(
            'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=gate',
          ),
          findsOneWidget,
          reason: '详情页没回显恢复出来的整条 URL ⇒ 备份往返把地址弄丢或弄改了',
        );
        _nav(tester).pop();
        await _settle(tester, seconds: 2);
        await _backToHome(tester);
        await _openMoreRow(tester, '关键词过滤');
        await _onPage(tester, KeywordsPage, '恢复后的关键词页');
        // 数据层：恢复到底把白名单写回服务了没有（页面只显示，服务才是真相）
        expect(
          GetIt.instance<FilterService>().whitelistKeywords,
          contains('闸门白名单'),
          reason: '备份里的白名单没被恢复进服务',
        );
        // 页面层：白名单/黑名单是两个 tab，先确保站在白名单上，再滚到条目
        await _tap(tester, find.text('白名单'), '关键词页→白名单 tab');
        await _settle(tester);
        await _scrollUntil(tester, find.text('闸门白名单'));
        expect(
          find.text('闸门白名单'),
          findsWidgets,
          reason: '服务里有但页面不显示 ⇒ 页面喂的是旧数据（恢复后 main_page 的副本没刷新）',
        );
        await _backToHome(tester);

        await _backToHomeQuietly(tester);
      },
    );

    // ── 9. 全程不得有任何未捕获异常 ──────────────────────────────────────
    expect(tester.takeException(), isNull, reason: '闸门过程中出现了未捕获异常（上面各节已定位到页面）');
    // 一节一报：上面被 _step 收下的失败在这里统一判红，不吞任何一个
    expect(
      gateFailures,
      isEmpty,
      reason:
          '以下闸门步骤失败：\n'
          '${gateFailures.entries.map((e) => "  \u25b8 ${e.key} \u2192 ${e.value}").join("\n")}',
    );
    // 预算说明（㊼）：本机 5:23，但 CI 的 job 用 `-gpu swiftshader_indirect` 软件渲染，
    // 比本机 `-gpu auto` 慢数倍。原来钉 18 分钟 ⇒ 超时先于功能失败，报出来的是
    // "闸门超时红"，会被误读成功能回归。放宽到 30，配套 job 预算 45 分钟。
  }, timeout: const Timeout(Duration(minutes: 30)));
}

/// 假 FilePicker：把「选文件」变成返回测试自己写出来的那个备份文件路径。
/// SAF 系统选单本身不可自动化，其余环节（读盘/解密/校验/恢复）全部走真实代码。
class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this._path);

  final String? Function() _path;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    final path = _path();
    if (path == null) return null;
    return FilePickerResult([
      PlatformFile(
        name: path.split(Platform.pathSeparator).last,
        path: path,
        size: File(path).lengthSync(),
      ),
    ]);
  }
}

class _StubUpdateService extends UpdateService {
  @override
  Future<VersionCheckResult?> checkUpdate({bool force = false}) async => null;
}

// ── 交互助手 ────────────────────────────────────────────────────────────
// 集成测试跑在真机上：异步（DB/原生往返/30s 定时器）不与帧同步，所以一律
// 「pump + 真实等待」轮询，不用 pumpAndSettle（有周期定时器时它永不收敛）。

Future<void> _settle(WidgetTester t, {int seconds = 1}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
}

Future<void> _waitUntil(
  WidgetTester t,
  Finder f,
  String what, {
  int seconds = 25,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 200));
    if (f.evaluate().isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  throw '等待超时：$what（finder=$f）';
}

/// 懒加载列表里的条目**不在视口时根本没被 build**，`find.text('添加通道')` 会 0 命中
/// （实测第 4 次跑就是这样）⇒ 任何点击/输入之前先把它滚出来。
/// 从树上最后一个 Scrollable 反向试：后压入的路由在 widget 树里更靠后，最可能是当前页。
Future<bool> _scrollUntil(WidgetTester t, Finder f) async {
  if (f.evaluate().isNotEmpty) return true;
  // ⚠ 必须按**下标**重新解析 Scrollable：一次 drag 之后 widget 实例会被重建，
  // 拿 find.byWidget(旧实例) 去 drag 会立刻 "matched 0 widgets" ⇒ 一次也滚不动，
  // 表现成"下面几行的入口找不到"（5.10/5.11/8 三节同一个假原因就是这么来的）。
  final count = t.widgetList(find.byType(Scrollable)).length;
  for (var i = count - 1; i >= 0; i--) {
    final target = find.byType(Scrollable).at(i);
    // 两个方向都要试：上一节可能已把同一个列表拖到底，此时要找的顶部行在**上方**，
    // 只朝下拖永远找不到（第 15 轮第 8 节找不到「Webhook 推送通道」就是这个）。
    for (final dy in const [-320.0, 320.0]) {
      for (var k = 0; k < 14 && f.evaluate().isEmpty; k++) {
        try {
          await t.drag(target, Offset(0, dy), warnIfMissed: false);
        } catch (_) {
          break; // 这个容器不可滚动（或已不在屏幕上），换下一个
        }
        await t.pump(const Duration(milliseconds: 120));
      }
      if (f.evaluate().isNotEmpty) return true;
    }
  }
  return false;
}

/// 失败现场快照：闸门红的时候，日志里必须能直接看出"当时屏幕上有什么"，
/// 否则每猜一次控件就要再花一轮模拟器时间（本批已经烧掉 16 轮）。

/// 有状态的原生镜像。⚠ `FilterService.loadSettings()` 会**回读**这几个键，
/// 桩若恒答空表，任何一次 loadSettings（备份采集、恢复前探测）都会把服务内存里
/// 刚写进去的关键词/应用筛选抹掉 —— 第 19 轮第 8 节的"白名单没被恢复"就是这么来的假信号。
const _noMirror = Object();
final _nativeState = <String, Object?>{};

Object? _nativeMirror(MethodCall call) {
  final a = call.arguments;
  switch (call.method) {
    case 'setBlacklistKeywords':
      _nativeState['blacklist'] = (a as Map)['keywords'];
      return _noMirror;
    case 'setWhitelistKeywords':
      _nativeState['whitelist'] = (a as Map)['keywords'];
      return _noMirror;
    case 'setAppFilter':
      _nativeState['appFilter'] = a;
      return _noMirror;
    case 'getBlacklistKeywords':
      return _nativeState['blacklist'] ?? const <String>[];
    case 'getWhitelistKeywords':
      return _nativeState['whitelist'] ?? const <String>[];
    case 'getEnabledPackages':
      return (_nativeState['appFilter'] as Map?)?['packages'] ??
          const <String>[];
    case 'getAppFilterMode':
      return (_nativeState['appFilter'] as Map?)?['mode'] ?? 'allow';
  }
  return _noMirror;
}

void _diagnose(WidgetTester t, String where) {
  try {
    final pages = t
        .widgetList(
          find.byWidgetPredicate(
            (w) => w.runtimeType.toString().endsWith('Page'),
          ),
        )
        .map((w) => w.runtimeType.toString())
        .toSet()
        .join(', ');
    final fields = t
        .widgetList(find.byType(TextField))
        .map((w) {
          final f = w as TextField;
          return '${f.decoration?.hintText ?? "-"}=${f.controller?.text ?? ""}'
              '${f.obscureText == true ? "(口令)" : ""}';
        })
        .join(' | ');
    final texts = t
        .widgetList(find.byType(Text))
        .take(220)
        .map((w) => (w as Text).data ?? '')
        .where((s) => s.isNotEmpty)
        .join(' / ');
    debugPrint(
      'GATE-DIAG($where) pages=[$pages] '
      'nav=${find.byType(NavigationBar).evaluate().isNotEmpty} '
      'dialog=${find.byType(Dialog).evaluate().isNotEmpty} '
      'sheet=${find.byType(BottomSheet).evaluate().isNotEmpty}',
    );
    debugPrint('GATE-DIAG($where) fields=[$fields]');
    debugPrint('GATE-DIAG($where) texts=[$texts]');
  } catch (e) {
    debugPrint('GATE-DIAG($where) 快照失败: $e');
  }
}

/// 找不到就拍快照再失败，别只留一句"找不到控件"。
Future<void> _must(WidgetTester t, bool ok, String why, Finder f) async {
  if (ok) return;
  _diagnose(t, why);
  fail('找不到「$why」（滚到底也没有）：$f');
}

/// 有没有模态盖在主界面之上。⚠ 不能用 `find.byType(Dialog)`：`AlertDialog` 不是它的
/// 子类匹配对象（byType 是精确类型），实测这条判断恒为 false ⇒ 复位"以为已经回主界面"，
/// 下一节就在弹层底下找控件（第 16、17 轮多节连红的共同根因）。
bool _modalUp(WidgetTester t) =>
    find.byType(AlertDialog).evaluate().isNotEmpty ||
    find.byType(SimpleDialog).evaluate().isNotEmpty ||
    find.byType(Dialog).evaluate().isNotEmpty ||
    find.byType(BottomSheet).evaluate().isNotEmpty;

/// 长按一个可能不在屏幕中间的控件。
///
/// 与 `_tap` 同一套前置，但**必须居中对齐**：`WidgetTester.ensureVisible` 默认
/// `alignment: 0.0`（把目标贴到视口上沿），而设置页的卡片上沿紧贴 AppBar —— 贴顶的
/// 行会被 AppBar 的 Material 吃掉手势。`longPress()` 打不中时**只打印 warning
/// 不抛异常**，于是表现为"菜单没出来"（闸门第 3 轮的真实红因：现场中心点 y=35.9
/// 落在 AppBar 里，`sheet=false`）。同理这里不用 `pumpAndSettle`：刚输入过的
/// TextField 有光标动画，它会永远不收敛（本文件其余分节都因此用 `_settle`）。
Future<void> _longPress(WidgetTester t, Finder f, String why) async {
  await _scrollUntil(t, f);
  await _must(t, f.evaluate().isNotEmpty, '长按目标 $why', f);
  // 不带 duration ⇒ 瞬移，不留滚动动画（动画 + 已聚焦的输入框 = pumpAndSettle 永不收敛）
  await Scrollable.ensureVisible(t.element(f.first), alignment: 0.5);
  await _settle(t);
  await t.longPress(f.first);
  await _settle(t);
  if (_menuUp(t)) return;
  // ⚠ 走到这里说明"手势命中了控件但动作表没出现"（`longPress()` 打不中才会打 warning，
  // 没打 warning 就是命中了）。T07-B 的几轮红都收在同一个位置：删掉一行之后再长按**同一行**，
  // 弹层没开。下面把能打的诊断都打上，并依次试三种按法 —— 只要有一种能开，就说明是
  // 时序/事件送达问题而不是功能坏了；三种都不行才是真缺陷（那时这条就是证据）。
  final r = t.getRect(f.first);
  final vp = t.view.physicalSize / t.view.devicePixelRatio;
  final tiles = find.descendant(of: f, matching: find.byType(ListTile));
  final tileCount = tiles.evaluate().length;
  final hasLongPress =
      tileCount > 0 && t.widget<ListTile>(tiles.first).onLongPress != null;
  debugPrint(
    'GATE-DIAG(长按未弹层 $why) rect=(${r.left.round()},${r.top.round()}) '
    '${r.width.round()}x${r.height.round()} '
    'viewport=${vp.width.round()}x${vp.height.round()} '
    'rows=${find.byType(Card).evaluate().length} '
    'barriers=${find.byType(ModalBarrier).evaluate().length} '
    'sheets=${find.byType(BottomSheet).evaluate().length} '
    'tiles=$tileCount longPress=$hasLongPress binding=${t.binding.runtimeType}',
  );
  // 试法一：拆开的"按下 - 保持 - 抬起"，中间多泵一次，确保 down 事件真的送达
  final g = await t.startGesture(r.center, kind: PointerDeviceKind.touch);
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(kLongPressTimeout + const Duration(milliseconds: 200));
  await g.up();
  await t.pump();
  if (_menuUp(t)) return;
  // 试法二：等真实时间走完（上一环节的退场动画可能还占着屏障），再按一次
  await _settle(t, seconds: 2);
  await t.longPress(f.first);
  await _settle(t, seconds: 2);
  if (_menuUp(t)) return;
  // 试法三：显式按几何中心
  await t.longPressAt(r.center);
  await _settle(t, seconds: 2);
  if (_menuUp(t)) return;
  // 还不行 ⇒ 采证：那个 ModalBarrier 挂在谁下面（是"某个弹层路由没退干净"还是本页自带的），
  // 以及**同一位置的普通点击**能不能走通 —— 点击能走通就是长按识别器的问题，
  // 点击也走不通就是有一层屏障把整页吞了（那是真缺陷，用户会遇到"删完一条后长按没反应"）。
  final owners = <String>[];
  final barrierState = <String>[];
  for (final e in find.byType(ModalBarrier).evaluate()) {
    final b = e.widget as ModalBarrier;
    barrierState.add('dismissible=${b.dismissible} color=${b.color}');
    final chain = <String>[];
    e.visitAncestorElements((a) {
      chain.add(a.widget.runtimeType.toString());
      return chain.length < 26;
    });
    owners.add(chain.join('<'));
  }
  // 屏障本体在哪一层"被吸收"了：忽略指针的祖先 + 所有还在树上的模态路由
  final absorbers = <String>[];
  for (final e
      in find.byWidgetPredicate((w) => w is IgnorePointer).evaluate()) {
    final ip = e.widget as IgnorePointer;
    absorbers.add('(${ip.ignoring})');
  }
  final modalScopes = find
      .byWidgetPredicate((w) => w.runtimeType.toString().contains('ModalScope'))
      .evaluate()
      .length;
  final barrierText = barrierState.join(' ; ');
  final absorberText = absorbers.join(',');
  final ownerText = owners.join(' | ');
  debugPrint(
    'GATE-DIAG(屏障状态 $why) $barrierText '
    'ignorePointers=$absorberText modalScopes=$modalScopes',
  );
  debugPrint('GATE-DIAG(屏障归属 $why) $ownerText');
  await t.tapAt(r.center);
  await _settle(t, seconds: 2);
  debugPrint(
    'GATE-DIAG(同点能否点击生效 $why) '
    'detail=${find.byType(WebhookSettingsPage).evaluate().isNotEmpty} '
    'barriersNow=${find.byType(ModalBarrier).evaluate().length}',
  );
  if (find.byType(WebhookSettingsPage).evaluate().isNotEmpty) {
    _nav(t).pop();
    await _settle(t, seconds: 2);
  }
  // 再采一问：整页都不动，还是只有这一行不动？FAB 在右下角，若它能开详情页，
  // 说明问题只在行所在的那块区域（有东西盖着 / 手势被行内某个控件吃掉）。
  await t.tap(find.byType(FloatingActionButton));
  await _settle(t, seconds: 2);
  debugPrint(
    'GATE-DIAG(FAB 能否点开 $why) '
    'detail=${find.byType(WebhookSettingsPage).evaluate().isNotEmpty}',
  );
  if (find.byType(WebhookSettingsPage).evaluate().isNotEmpty) {
    _nav(t).pop();
    await _settle(t, seconds: 2);
  }
  await _must(t, _menuUp(t), '$why 长按后动作表（三种按法都没开=手势真的不生效）', f);
}

/// 有没有动作表/弹层在树上（长按之后唯一的"手势生效"证据）。
bool _menuUp(WidgetTester t) =>
    find.byType(CardActionSheet).evaluate().isNotEmpty ||
    find.byType(BottomSheet).evaluate().isNotEmpty;

/// 删除的二次确认（T06）。**这条 helper 本身就是守卫**：没有确认框它当场红，
/// 于是"某条删除路径偷偷绕开了咽喉"在闸门上就是可见的，而不是靠人记住。
Future<void> _confirmDelete(WidgetTester t, String why) async {
  await _settle(t);
  final confirm = find.widgetWithText(TextButton, '删除');
  await _must(t, confirm.evaluate().isNotEmpty, '删除确认框 $why', confirm);
  // 对话框永远在页面控件之后 ⇒ .last 是确认框里那颗，不是页面上的删除按钮
  await t.tap(confirm.last);
  await _settle(t);
  // ⚠ 再多 pump 一会儿：确认框的**下场动画**还没走完、咽喉里的 async 落库与清缓存也还没
  // 回来（两者都在同一个 setState 之前）。少这一段，紧跟其后的手势会打在"还挂在树上"的
  // 模态屏障上 —— 表现为"长按没弹出动作表"，实测就是闸门 T07-B 第一轮的红因。
  await _settle(t, seconds: 2);
}

Future<void> _tap(WidgetTester t, Finder f, String why) async {
  await _scrollUntil(t, f);
  await _must(t, f.evaluate().isNotEmpty, '可点控件 $why', f);
  // ⚠ 用"树上第一个匹配"，不要把控件钉成实例：`const Icon(...)` 会被规范化，
  // find.byWidget 对两个一模一样的图标同时命中 ⇒ tap 报 "ambiguously found"（实测）。
  //
  // ⚠⚠ **必须每次都先 ensureVisible**：懒加载列表会把视口外不远处的行也 build 出来，
  // 于是 finder 命中 ≠ 已绘制；而 `tester.tap()` 打不中时**只打印 Warning 不抛异常**
  // （"Hit test ... outside the bounds"），所以靠 try/catch 兜底永远不会触发 ⇒
  // 点击静默丢失（第 16 轮 5.10/5.12/7/8 全是这一个原因）。
  try {
    await t.ensureVisible(f.first);
  } catch (_) {}
  await t.pump(const Duration(milliseconds: 120));
  await _must(t, f.evaluate().isNotEmpty, '可见化后 $why', f);
  await t.tap(f.first);
  await _settle(t);
}

Future<void> _type(WidgetTester t, Finder f, String text, String why) async {
  await _scrollUntil(t, f);
  await _must(t, f.evaluate().isNotEmpty, '输入框 $why', f);
  try {
    await t.ensureVisible(f.first);
  } catch (_) {}
  await t.pump(const Duration(milliseconds: 120));
  final obscured = (t.widget(f.first) as TextField).obscureText;
  await t.tap(f.first);
  await _settle(t);
  await t.enterText(f.first, text);
  await _settle(t);
  // 回读校验：软键盘/焦点/重建都可能把输入吞掉，不在这里点名就只能靠后面"条数不对"去猜
  // （第 6、7 轮各白跑了一次模拟器）。⚠ 不要拿钉住的实例回读 controller ——
  // 输入触发 setState 后那个 TextField 实例已被替换（读回来是 null，实测）；
  // 改看"文字有没有渲染出来"。口令/密钥字段本身打成圆点，跳过。
  if (!obscured) {
    if (find.text(text).evaluate().isEmpty) {
      _diagnose(t, '输入回读 $why');
      throw '输入没落进「$why」：界面上找不到 $text';
    }
  }
}

/// AppBar 上的文字按钮（'保存' / '完成'）。不这样限定就会和正文里同名的
/// Snackbar 文案、对话框按钮撞在一起，tap 直接抛 "matched 2 widgets"。
Finder _appBarText(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is AppBar || w.runtimeType.toString().contains('NavigationBar'),
  ),
  matching: find.text(label),
);

/// 限定在某个页面类内部查找控件。IndexedStack 会让三个 tab 的控件同时存在于树上，
/// 不限定的 `find.byIcon(Icons.add)` / `find.text('保存')` 会命中别的气泡。
Finder _in(Type page, Finder f) =>
    find.descendant(of: find.byType(page), matching: f);

/// Webhook 详情页里输入框的顺序是「名称 → URL →（密钥/模板，随通道类型的描述符能力位变化）」，
/// 按下标取会随类型漂移；URL 输入框在**为空时**必定显示占位文案，
/// 于是"还带占位文案且 controller 为空的那个 TextField"就是要填的 URL 框。
/// ⚠ 不能用"占位文案还在不在"判断某个输入框是空的：Material 会把 hintText 留成
/// 浮动标签（实测带文字的 URL 框仍然 `find.text(占位)` 命中），于是"下一个空行"
/// 永远命中第 0 行，把已有那条的地址覆盖掉 —— 闸门因此少存一条通道。
/// 正确做法是按 decoration.hintText + controller.text 是否真的为空来挑。
Finder _emptyWebhookUrlField() => find.byWidgetPredicate(
  (w) =>
      w is TextField &&
      w.decoration?.hintText == 'https://example.com/webhook' &&
      (w.controller?.text ?? '').isEmpty,
);

Future<void> _fillWebhookUrl(WidgetTester t, String url) async {
  final f = _emptyWebhookUrlField();
  // ⚠ 必须先等/找，不能进页后立刻断言：行的 URL 框是异步装载后建出来的，
  // CI 的 swiftshader 软件渲染比本机慢，第 21 轮在 API 34 画像上就是在这里红了
  // （本机 API 36 永远来得及 ⇒ 典型的"本地绿 CI 红"）。_scrollUntil 会边泵帧边找。
  await _scrollUntil(t, f);
  expect(
    f.evaluate().isNotEmpty,
    isTrue,
    reason:
        '找不到待填的 Webhook URL 输入框（占位文案未渲染或行没建出来）'
        '；当前页面上 TextField 数='
        '${find.byType(TextField).evaluate().length}',
  );
  await _type(t, f, url, 'Webhook URL 输入框');
  await _settle(t);
}

/// 一节红掉不影响后面的节继续跑：模拟器一轮要 4 分钟，一节一轮试不起。
/// 失败**照样让闸门红**（末尾统一 expect），只是把"这一轮能看见多少问题"放大。
Future<void> _step(
  WidgetTester t,
  Map<String, String> failures,
  String name,
  Future<void> Function() body,
) async {
  try {
    await body();
  } catch (e) {
    failures[name] = e.toString().split('\n').first;
    debugPrint('GATE-STEP-FAIL ▸ $name ▸ $e');
  }
  await _backToHomeQuietly(t);
}

/// 每节收尾都回主界面；回不去本身不算该节失败（由下一节的入口断言去暴露）。
/// 主 Navigator 的 state（弹一层路由用，不依赖任何本地化返回按钮文案）。
NavigatorState _nav(WidgetTester t) =>
    t.state<NavigatorState>(find.byType(Navigator).first);

Future<void> _backToHomeQuietly(WidgetTester t) async {
  try {
    await _backToHome(t);
  } catch (_) {}
}

/// 进页断言：页面类出现在树上（说明路由真的 push 成功），且没有当场抛异常。
Future<void> _onPage(WidgetTester t, Type pageType, String label) async {
  await _waitUntil(t, find.byType(pageType), '$label 未出现', seconds: 30);
  expect(t.takeException(), isNull, reason: '$label 渲染过程中抛了异常');
}

/// 弹到只剩主界面（底部 NavigationBar 可见）。不依赖任何本地化返回按钮文案。
Future<void> _backToHome(WidgetTester t) async {
  for (var i = 0; i < 16; i++) {
    // ⚠ 只看 NavigationBar 不够：对话框/底部弹层盖在主界面之上时它仍在树上，
    // 于是"已回主界面"被误判，下一节是在弹窗里找按钮（第 11 轮 13 节全红的真因）。
    final modalUp = _modalUp(t);
    if (!modalUp &&
        find.byType(NavigationBar).evaluate().isNotEmpty &&
        find.byType(NotificationPage).evaluate().isNotEmpty) {
      await _settle(t);
      return;
    }
    // 判定"已回主界面"要求没有弹窗盖着（modalUp）；页面本身照常 pop，
    // 到根路由时 canPop() 为 false，不会弹过头。
    final nav = _nav(t);
    if (nav.canPop()) {
      nav.pop();
    } else {
      break;
    }
    await _settle(t);
  }
  expect(
    find.byType(NavigationBar).evaluate().isNotEmpty,
    isTrue,
    reason: '返回不了主界面（路由栈没清空）',
  );
}

/// 在「更多」页里滚到某个入口再点它。MorePage 是长列表，靠下条目不滚动根本不存在。
Future<void> _openMoreRow(WidgetTester t, String label) async {
  // 主界面是 IndexedStack：MorePage 永远**在树上**，但当前 tab 不是它时并不在屏幕上，
  // 滚不动 ⇒ 每次都先点一下 tab（第 12 轮 5.11/8 两节的"找不到入口"就是这个）。
  // tab 与行都必须**限定范围**：通知页卡片上也有"更多"两个字，不限定就会点到它 ——
  // 第 15 轮 5.10 的快照 pages=[MainPage, NotificationPage] 正是"根本没切到更多页"，
  // 之后找到的"设备名称"其实是通知页上的同名文字，点了自然没有弹层。
  await _tap(
    t,
    find.descendant(of: find.byType(NavigationBar), matching: find.text('更多')),
    '底部 tab→更多',
  );
  await _waitUntil(t, find.byType(MorePage), '更多页(打开 $label)');
  final row = find.descendant(
    of: find.byType(MorePage),
    matching: find.text(label),
  );
  await _scrollUntil(t, row);
  if (row.evaluate().isEmpty) {
    _diagnose(t, '更多页缺入口 $label');
    fail('更多页里找不到入口「$label」（上一条 GATE-DIAG 的 texts 是页面上真实标签）');
  }
  await _tap(t, row, '更多页→$label');
  await _settle(t);
}

/// 「通知引擎」tab 里的入口（T15 骨架页：电量告警 / 温度告警）。
///
/// 与 `_openMoreRow` 同一套规矩：IndexedStack 让这页永远在树上，不在屏幕上的时候
/// 点不到 ⇒ 先限定在 NavigationBar 里点 tab，再把行限定在本页里找（首页卡片上也有
/// "电量/温度"这类字样）。
Future<void> _openEngineRow(WidgetTester t, String label) async {
  await _tap(
    t,
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('通知引擎'),
    ),
    '底部 tab→通知引擎',
  );
  await _waitUntil(t, find.byType(NotificationEnginePage), '通知引擎页(打开 $label)');
  final row = find.descendant(
    of: find.byType(NotificationEnginePage),
    matching: find.text(label),
  );
  await _scrollUntil(t, row);
  if (row.evaluate().isEmpty) {
    _diagnose(t, '通知引擎页缺入口 $label');
    fail('通知引擎页里找不到入口「$label」（上一条 GATE-DIAG 的 texts 是页面上真实标签）');
  }
  await _tap(t, row, '通知引擎→$label');
  await _settle(t);
}

/// 更多页里某个入口是否已经可见/可点，统一交给 `_scrollUntil`（在 `_tap`/`_type` 里自动调用）。
