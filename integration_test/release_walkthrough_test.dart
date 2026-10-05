import 'dart:async';
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
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/di/service_locator.dart';
import 'package:notice_transmit/main.dart' show MyApp;
import 'package:notice_transmit/pages/app_channel_list_page.dart';
import 'package:notice_transmit/pages/channel_status_page.dart';
import 'package:notice_transmit/pages/app_channel_settings_page.dart';
import 'package:notice_transmit/pages/app_filter_page.dart';
import 'package:notice_transmit/pages/backup_restore_page.dart';
import 'package:notice_transmit/pages/battery_page.dart';
import 'package:notice_transmit/pages/device_state_page.dart';
import 'package:notice_transmit/pages/device_snapshot_page.dart';
import 'package:notice_transmit/pages/email_settings_page.dart';
import 'package:notice_transmit/pages/fnthink_push_page.dart';
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
import 'package:notice_transmit/services/device_state_service.dart';
import 'package:notice_transmit/services/engine_rule_diff.dart';
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
///   只跑其中一条（排障时省时间）：`--plain-name "闸门 3/4"`
///
/// 结构：24 个分节按"要看见的现场"分成**四条独立用例**（1/4 只读页、2/4 三族通道 CRUD、
/// 3/4 规则与更多页、4/4 备份往返）；拆的理由与代价都写在 `_assemble` 的注释里。
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
      // T18：设备状态页的数据源。**故意留一个读不到的维度**（电池温度），
      // 让"这台设备读不到"那条分支在设备上真走一遍 —— 缺桩=整页显示"没读到"，
      // 那一节就退化成只检查了失败分支。
      'getDeviceSnapshot': {
        'model': 'GateModel',
        'brand': 'GateBrand',
        'manufacturer': 'Google',
        'osVersion': '14',
        'sdkInt': 34,
        'network': 'wifi',
        'batteryLevel': 77,
        'batteryCharging': false,
        'storageTotalMb': 120000.0,
        'storageFreeMb': 40000.0,
        'memoryTotalMb': 8192.0,
        'memoryAvailableMb': 3072.0,
        'brightnessPercent': 45,
        'brightnessMode': 'auto',
        'uptimeSeconds': 90000,
        'capturedAtMs': 1767223200000,
        'unavailable': ['batteryTemperatureC'],
      },
      'getDownloadDirectory': '/data/local/tmp',
      // 测试类动作：全部返回成功，覆盖 UI 的成功分支（不联网、不真发）
      'testWebhook': {'success': true, 'message': '闸门通过', 'signed': false},
      'testAppChannel': {'success': true, 'message': '闸门通过'},
      'testEmail': {'success': true, 'message': '闸门通过'},
      'probeChannelHealth': {'reachable': true, 'latencyMs': 12},
      // 6e 非侵入探测：应用族只换 token、邮件族只握手，都不投递。给"通"的桩，
      // 让设备侧真走完「进页 → 探测 → 落健康单点 → 徽标刷新」那一段（缺桩=静默跳过）。
      'probeAppChannelToken': {
        'reachable': true,
        'latencyMs': 31,
        'reason': '',
      },
      'verifySmtp': {'reachable': true, 'latencyMs': 24, 'reason': ''},
      'requestPinAppWidget': true,
      'drainOfflineCache': {
        'records': <Map<String, dynamic>>[
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
        'dropped': 0,
      },
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

  testWidgets('闸门 1/4 只读页：服务启停 / 权限三态 / 短信监听 / 历史页导出', (tester) async {
    final gateFailures = <String, String>{};
    await _assemble(tester);
    await _step(tester, gateFailures, '1 通知页：服务启停', () async {
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
    });
    await _step(tester, gateFailures, '2 权限设置页：进页读三态', () async {
      // ── 2. 权限设置页：进入即读三态权限，页面必须渲染且不抛 ──────────────
      await _tap(tester, find.text('权限设置'), '通知页→权限设置');
      await _onPage(tester, PermissionSettingsPage, '权限设置页');
      await _backToHome(tester);
    });
    await _step(tester, gateFailures, '3 短信监听页：两个开关 + SIM 选择', () async {
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
    });
    await _step(tester, gateFailures, '4 推送历史页：进页 + 导出 JSON（真落盘）', () async {
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
    });
    await _step(
      tester,
      gateFailures,
      '4.1 推送历史页的方向切换：切到「收件（幻念）」再切回来',
      () async {
        // 为什么单开一步：T48 第一片把方向做成**数据源切换**（两张表分页口径不同，拼进同一条时间线
        // 的表现是翻页时同一条出现两次或整条不出现），而闸门此前只进过这一页的"转发"那一侧 ——
        // 收件那一档在设备上从没被点开过，与"幻念推送页整页是闸门盲区"是同一类洞。
        await _tap(tester, find.text('推送历史'), '通知页→推送历史（方向切换）');
        await _settle(tester, seconds: 2);
        await _tap(tester, _in(HistoryPage, find.text('收件（幻念）')), '历史页→收件（幻念）');
        await _settle(tester, seconds: 2);
        // 这台模拟器上没有幻念收件 ⇒ 只允许说"还没有收到过消息"那一句。
        // 出现转发那一侧的行 = 两份数据源串了；一句都不说 = 读不到与没有货同一张脸。
        expect(
          find.text('还没有收到过消息'),
          findsOneWidget,
          reason: '收件档没有自己的空态 ⇒ "没读过"与"没有货"在屏幕上分不出来',
        );
        expect(
          find.text('闸门通知一'),
          findsNothing,
          reason: '切到收件档还看得见转发的行 ⇒ 方向只是换了个高亮，没换数据源',
        );
        expect(
          find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey &&
                '${(w.key as ValueKey).value}'.startsWith('fnthink-inbox-row-'),
          ),
          findsNothing,
          reason: '空态下不该有收件行',
        );
        await _tap(tester, _in(HistoryPage, find.text('转发')), '历史页→切回转发');
        await _settle(tester, seconds: 2);
        expect(
          find.text('闸门通知一'),
          findsWidgets,
          reason: '切回来列表空了 ⇒ 两个方向共用一份 state（切回去时没重读自己的那一份）',
        );
        await _backToHome(tester);
      },
    );
    await _step(
      tester,
      gateFailures,
      '4.2 收件档"有货"的那一半：列表行 → 详情 → 点开即已读',
      () async {
        // 4.1 只能证"空态说人话"。这一格证的是**有货的时候**：这台模拟器没有服务端可连，
        // 而闸门用的是真实加密库（不是替身），所以直接往 `fnthink_messages` 塞一行，
        // 让"列表里那一行 / 未读点 / 详情里的标题与正文 / 点开即已读"这四件事在设备上各留一次证据。
        // ⚠ 首页那张未读卡**不在这里断言**：它的数只在服务启动与 resumed 时重取
        //    （`main_page.dart:184/283`），而注入发生在页面装配之后 —— 在这儿断"卡该出现"
        //    要么是假红、要么得写成软断言（更糟）。那一格由 widget 用例证。
        const gateId = 'gate_inbox_1';
        final helper = DatabaseHelper();
        final db = await helper.database;
        Future<void> drop() async {
          await db.delete(
            FnthinkInboxMessage.table,
            where: 'message_id = ?',
            whereArgs: [gateId],
          );
        }

        // 先清一次：上一轮没收干净的话，幂等插入会返回 false，那条断言就说不清是谁的错
        await drop();
        final inserted = await helper.insertFnthinkInbox(
          const FnthinkInboxMessage(
            messageId: gateId,
            sender: '8KMNPQRSTVWX999777',
            type: 'notice',
            item: '',
            title: '闸门收件一',
            body: '闸门注入的收件正文',
            receivedAt: 1767223200000,
          ),
        );
        expect(inserted, isTrue, reason: '注入没落库 ⇒ 后面每一条断言都是在演一场空');

        await _tap(tester, find.text('推送历史'), '通知页→推送历史（注入之后）');
        await _settle(tester, seconds: 2);
        await _tap(
          tester,
          _in(HistoryPage, find.text('收件（幻念）')),
          '历史页→收件（幻念）（有货）',
        );
        await _settle(tester, seconds: 2);
        final row = find.byKey(const ValueKey('fnthink-inbox-row-$gateId'));
        expect(
          row,
          findsOneWidget,
          reason: '表里有一条而列表不列 ⇒ 这一档读的不是那张表（或被 read 那一列滤掉）',
        );
        expect(
          find.byKey(const ValueKey('fnthink-inbox-unread-$gateId')),
          findsOneWidget,
          reason: '未读点不在 ⇒ 用户没法区分"看过没有"（它只该跟着 read 那一列走）',
        );
        expect(
          find.text('还没有收到过消息'),
          findsNothing,
          reason: '有货还报空态 ⇒ 4.1 那条空态断言此刻是反的',
        );

        await _tap(tester, row, '收件行→详情');
        await _settle(tester, seconds: 1);
        final sheet = find.byType(BottomSheet);
        expect(
          find.descendant(of: sheet, matching: find.text('闸门收件一')),
          findsOneWidget,
          reason: '详情弹层没起来，或起来了而没有标题',
        );
        expect(
          find.descendant(of: sheet, matching: find.text('闸门注入的收件正文')),
          findsOneWidget,
          reason: '详情里没有正文 ⇒ 只给标题的那一格不算"看过"',
        );
        // "点开即已读"写在 `await showModalBottomSheet(...)` **之后** ⇒ 必须先把弹层关掉，
        // 才轮到那一次 markRead + 重读表（点遮罩关，与第 4 步收长按弹层同一个动作）。
        await tester.tapAt(const Offset(10, 10));
        await _settle(tester, seconds: 2);
        expect(
          find.byKey(const ValueKey('fnthink-inbox-unread-$gateId')),
          findsNothing,
          reason: '关掉详情还在标未读 ⇒ 点开即已读那一刀没接上（或页面自己留了份状态没重读表）',
        );
        expect(row, findsOneWidget, reason: '已读不该把那一行从历史里抹掉（它只是变成"看过的"）');
        expect(
          await helper.countFnthinkInboxUnread(),
          0,
          reason: '库里那一行的 read 没翻过去',
        );
        await drop(); // 闸门要可重复跑：留着它，下一轮的 4.1 就不再是空态
        await _backToHome(tester);
      },
    );
    await _verdict(tester, gateFailures, '闸门 1/4');
  }, timeout: const Timeout(_caseABudget));

  testWidgets(
    '闸门 2/4 三族通道 CRUD：webhook 两页形状 / 邮件 / 自建应用',
    (tester) async {
      final gateFailures = <String, String>{};
      await _assemble(tester, () async {
        // 4.3 要看的是首页那张未读卡，而它的数只在 `_postInit`（主界面起来那一次）与
        // `resumed` 时取 ⇒ 必须在 `pumpWidget` **之前**灌好，`_assemble` 的 seed 就是这个位置。
        final helper = DatabaseHelper();
        for (final (id, wasRead) in const [
          ('gate_home_1', false),
          ('gate_home_2', true),
          ('gate_home_3', true),
        ]) {
          await helper.insertFnthinkInbox(
            FnthinkInboxMessage(
              messageId: id,
              sender: '8KMNPQRSTVWX999777',
              type: 'notice',
              item: '',
              title: '闸门首页卡 $id',
              body: '闸门注入：证首页未读数的来源',
              receivedAt: 1767223200000,
              read: wasRead,
            ),
          );
        }
      });
      await _step(
        tester,
        gateFailures,
        '4.3 首页「幻念收件」入口卡：数只数未读，点进去就是那一档',
        () async {
          // 三条注入里只有一条未读 ⇒ 这一格钉的不是"卡有没有"，而是**那个数是从表里算的**：
          // 写死、或把已读也数进去，都会在这里红（"未读 3 条"与"未读 1 条"在用户眼里是两件事）。
          const entry = '幻念收件';
          final card = find.text(entry);
          // ⚠ 先滚到那一格再收文字：首页是 ListView，视口外的卡根本没 build
          //（5.15 第一轮就是这么红的，本仓记过几次的同一类假红）。
          await _scrollUntil(tester, card);
          await _settle(tester, seconds: 1);
          expect(
            card,
            findsOneWidget,
            reason: '有未读而首页没有入口卡 ⇒ 收件只能靠用户自己想起去历史页找',
          );
          expect(
            find.text('未读 1 条'),
            findsOneWidget,
            reason: '入口卡的数不对：三条里两条已读，只该说 1（这一格是"数从表里算"的唯一现场证据）',
          );
          await _tap(tester, card, '首页→幻念收件入口卡');
          await _settle(tester, seconds: 2);
          for (final id in ['gate_home_1', 'gate_home_2', 'gate_home_3']) {
            expect(
              find.byKey(ValueKey('fnthink-inbox-row-$id')),
              findsOneWidget,
              reason: '入口卡点进来少了一行（$id）⇒ 两处读的不是同一张表',
            );
          }
          expect(
            find.byKey(const ValueKey('fnthink-inbox-unread-gate_home_1')),
            findsOneWidget,
            reason: '未读那条没点 ⇒ 用户找不到"哪条没看"',
          );
          expect(
            find.byKey(const ValueKey('fnthink-inbox-unread-gate_home_2')),
            findsNothing,
            reason: '已读那条还画着未读点 ⇒ 点在骗人（它只该跟着 read 那一列）',
          );
          final db = await DatabaseHelper().database;
          await db.delete(
            FnthinkInboxMessage.table,
            where: 'message_id LIKE ?',
            whereArgs: ['gate_home_%'],
          );
          await _backToHome(tester);
        },
      );
      await _step(
        tester,
        gateFailures,
        '4.4 历史页「全部」档：三段并排、每行有来源标识、返回不炸',
        () async {
          // T84 的形状是"三段各自翻页"，不是拼成一条时间线。闸门要证的恰恰是
          // **第三段没有安静地消失**：收件与发出这两段此前从没在设备上同过屏（4.1/4.2 只看单档）。
          // 用真库注入（这台模拟器没有服务端可连），事后清干净 —— 闸门不留余温。
          const inId = 'gate_all_in';
          const outId = 'gate_all_out';
          final helper = DatabaseHelper();
          final db = await helper.database;
          await db.delete(
            FnthinkInboxMessage.table,
            where: 'message_id LIKE ?',
            whereArgs: ['gate_all_%'],
          );
          for (final (id, title, dir) in const [
            (inId, '闸门全部档收件一', kFnthinkDirectionIn),
            (outId, '闸门全部档发出一', kFnthinkDirectionOut),
          ]) {
            final inserted = await helper.insertFnthinkInbox(
              FnthinkInboxMessage(
                messageId: id,
                sender: '8KMNPQRSTVWX999777',
                type: 'notice',
                item: '',
                title: title,
                body: '闸门注入：全部档里属于它的那一段',
                receivedAt: 1767223200000,
                direction: dir,
              ),
            );
            expect(inserted, isTrue, reason: '注入没落库（$id）⇒ 后面每一条断言都是在演一场空');
          }
          await _tap(tester, find.text('推送历史'), '首页→推送历史（要看全部档的那一次）');
          await _settle(tester, seconds: 2);
          await _tap(
            tester,
            _in(HistoryPage, find.byKey(const ValueKey('direction-chip-all'))),
            '历史页→全部档',
          );
          await _settle(tester, seconds: 2);
          // ⚠ 先滚到那一段再断言：ListView 懒建，视口外的标题根本没 build，
          //    那时"找不到"是闸门自己的红（5.15 与冒烟 2 各这样红过一次，本仓记过几次）。
          for (final kind in const ['forwarded', 'inbox', 'sent']) {
            final header = find.byKey(ValueKey('history-all-header-$kind'));
            await _scrollUntil(tester, header);
            expect(
              header,
              findsOneWidget,
              reason:
                  '全部档少了「$kind」那一段的标题 ⇒ 三段里有一段被安静地吞掉了。'
                  '少一段与三段都在，用户看到的是同一句"这就是全部"',
            );
            // 判据③：段标题**不带数字**（第四种计数会让人以为全部档另有一本账）。
            // ⚠ 那一枚 key 挂在 Padding 上而不是 Text 上（与 T84 的 widget 用例同一处坑），
            //    所以这里必须往下找一个 Text 读文字，直接 `widget<Text>(header)` 会当场 cast 炸。
            final title = tester
                .widgetList<Text>(
                  find.descendant(of: header, matching: find.byType(Text)),
                )
                .map((t) => t.data ?? '')
                .join();
            expect(
              RegExp(r'\d').hasMatch(title),
              isFalse,
              reason: '段标题里冒出数字 ⇒ 这一档开始自己计数，而它没有那份数据源',
            );
          }
          for (final id in const [inId, outId]) {
            final row = find.byKey(ValueKey('fnthink-inbox-row-$id'));
            await _scrollUntil(tester, row);
            expect(
              row,
              findsOneWidget,
              reason: '切到全部档看不到注入的那一行（$id）⇒ 它读的不是同一张表的那份账',
            );
          }
          for (final tag in const ['收', '发']) {
            final badge = find.byKey(ValueKey('history-all-tag-$tag'));
            expect(badge, findsWidgets, reason: '行首没有来源标识 ⇒ 三段并排变成一屏看不出归属的流水账');
          }
          await db.delete(
            FnthinkInboxMessage.table,
            where: 'message_id LIKE ?',
            whereArgs: ['gate_all_%'],
          );
          // 「返回不炸」不是废话：这一档是三段叠在一个可滚容器里，返回时若还有在途的一轮读，
          // 页面销毁之后 setState 就会红在这一发上。
          await _backToHome(tester);
        },
      );
      await _step(
        tester,
        gateFailures,
        '5.1 更多 tab 入口 + webhook 列表/详情两页形状',
        () async {
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
          const dingUrl =
              'https://oapi.dingtalk.com/robot/send?access_token=gate';
          const wecomUrl = _gateWecomUrl;

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
          _mark('5.1 建第二条（一次只改一件事）');
          await _tap(
            tester,
            find.byType(FloatingActionButton),
            'Webhook→新增第二条',
          );
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
                  w is TextField &&
                  (w.decoration?.hintText ?? '').startsWith('通道名称'),
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
          _mark('5.1 列表页整族动作：长按复制 / 长按删除');
          final row = find.byKey(
            ValueKey('webhook-channel-row-$webhookFirstId'),
          );
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
          expect(
            tripled,
            hasLength(3),
            reason: '复制没立刻落库 = 列表页还在用"整表快照 + 保存时才写"的旧形状',
          );
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
          _mark('5.1 删两条：企微那条留给后面的备份与状态页');
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
          _mark('5.1 删第二条：先退出列表页再重进（弹层删完本页手势失灵那条遗留）');
          _nav(tester).pop();
          await _settle(tester, seconds: 2);
          await _openMoreRow(tester, 'Webhook 推送通道');
          await _onPage(tester, WebhookChannelListPage, 'Webhook 列表页(重进删第二条)');
          final dingRow = find.byKey(
            ValueKey('webhook-channel-row-$webhookFirstId'),
          );
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
          expect(
            kept.single['url'],
            wecomUrl,
            reason: '删错条 = 行与通道错位（备份与恢复都会跟着错）',
          );
          expect(
            kept.single['channelType'],
            'wechat_work',
            reason: '按 URL 识别出来的类型没落库（也是后面备份往返的基准）',
          );
          // 本节自己 push 过页面（详情 / 重进的列表页），收尾必须回主界面：
          // 5.2 的 _openMoreRow 是直接点底部 tab 的，不还回去就在别人的页面上找按钮。
          await _backToHome(tester);
        },
      );
      await _step(tester, gateFailures, '5.2 邮件通道：新建→填表→保存→重进改一处', () async {
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
        await _waitUntil(
          tester,
          _appBarText('测试并保存'),
          '邮件编辑器（AppBar 的「测试并保存」）',
        );
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
      });
      await _step(
        tester,
        gateFailures,
        '5.3 自建应用：FAB→类型弹层→必填校验→填→保存→整族动作',
        () async {
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
          _mark('5.3 仅测试：不写库，但结论照样落单点');
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
                  GetIt.instance<AppChannelService>().channels.first['id']
                      .toString(),
                )
                ?.reachable,
            isTrue,
            reason: '自建应用通道的测试结论没落单点 = 三族里只有它冒不到首页',
          );
          // T07：回到列表页做"整族级"的动作（复制 / 启停 / 删除）。详情页只管一条。
          _mark('5.3 回列表页做整族动作（复制/启停/删除）');
          // ⚠ 不用 `tester.pageBack()`：它找的是 Cupertino 返回键 / 本地化 tooltip，
          // 本应用的页头是自己搭的 Material AppBar ⇒ 当场 "One back button expected"（实测红）。
          _nav(tester).pop();
          await _settle(tester, seconds: 2);
          await _onPage(tester, AppChannelListPage, '返回列表页');
          final firstId = GetIt.instance<AppChannelService>()
              .channels
              .first['id']
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
          _mark('5.3 删除走二次确认咽喉');
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
        },
      );
      await _verdict(tester, gateFailures, '闸门 2/4');
    },
    timeout: const Timeout(_caseBBudget),
  );

  testWidgets(
    '闸门 3/4 规则与更多页：引擎告警 / 筛选 / 关键词 / 约束 / 模板库 / 状态页',
    (tester) async {
      final gateFailures = <String, String>{};
      // 这一条里的 5.9 通道状态页要看见一条已启用的 webhook（拆开之前是 2/4 留下的现场）
      await _assemble(tester, _seedWebhookChannel);
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
        // T90 片14：这枚阈值框换成了共享外壳 `IosFormDialog`（Cupertino 那件）⇒ 本步里
        // **等/点/断言的每一处引用一起换**（片12 只改了「点」漏了「等」，闸门当场红）。
        // ⚠ 下面温度**试跑**结果框那一处曾长期**不换**（它还是 Material 那件）；
        //   T90 片28 把它收进 `IosDialogActions.showExplainer` ⇒ **那一处现在也换成
        //   `CupertinoAlertDialog` 了**，本文件里已无 `_in(AlertDialog, …)`。
        //   ⚠ 这条注释留着：当初"照着一起改就会把闸门改红"是对的，改之前先确认那一枚真的迁了。
        await _tap(
          tester,
          _in(CupertinoAlertDialog, find.text('电池温度')),
          '温度规则类型 chip',
        );
        await _tap(
          tester,
          _in(CupertinoAlertDialog, find.text('添加')),
          '温度→添加(确认)',
        );
        await _settle(tester, seconds: 1);
        // 启停开关是**每条规则一行**的尾控件，规则没建成就是 0 个 ⇒ 直接查服务更准
        expect(
          GetIt.instance<TemperatureService>().rules,
          isNotEmpty,
          reason: '温度规则没建成（对话框确认链路或存储断链）',
        );
        // T25：页右上的「试一次」必须真出结果 —— 求值在原生（判据只有一份），
        // 模拟器上读不读得到温区都可能，但"点了什么都不知道"就是这一节的失败。
        await _tap(
          tester,
          _in(TemperaturePage, find.byIcon(Icons.science_outlined)),
          '温度→试一次',
        );
        await _settle(tester);
        final previewBody = find.byKey(const ValueKey('temp-preview-body'));
        await _waitUntil(tester, previewBody, '温度试跑结果弹层');
        expect(
          tester.widget<Text>(previewBody).data,
          isNotEmpty,
          reason: '弹层是空的 ⇒ 原生回了载荷而 Dart 没渲染出来（三种结局都会看不见）',
        );
        await _tap(
          tester,
          _in(CupertinoAlertDialog, find.text('关闭')),
          '温度试跑→关闭',
        );
        await _settle(tester);
        await _backToHome(tester);

        await _backToHomeQuietly(tester);
      });
      // 5.4a 设备状态告警（T24）：亮度与网络各加一条 → 关一条 → 删一条。
      // 这一节钉的是**新触发源那条链有没有真的接上**：页面 → DeviceStateService →
      // engine_rules 表（族 device_state）→ prefs 镜像 → refreshEngineRules。
      // 链上任一环断了，用户在界面上配好的规则永远不推，而界面上一切正常。
      await _step(
        tester,
        gateFailures,
        '5.4a 设备状态告警：加亮度+网络各一条 → 停 → 删',
        () async {
          Map<String, dynamic>? ruleByTitle(String title) {
            for (final r in GetIt.instance<DeviceStateService>().rules) {
              if (r['title'] == title) return r;
            }
            return null;
          }

          await _backToHomeQuietly(tester);
          await _openEngineRow(tester, '设备状态告警');
          await _onPage(tester, DeviceStatePage, '设备状态页');

          // 亮度型：默认选中的就是「亮度低于」，点它既验 chip 可打中，也验形状不靠运气
          await _tap(
            tester,
            _in(DeviceStatePage, find.byIcon(Icons.add)),
            '设备状态→添加(亮度)',
          );
          await _settle(tester);
          // T90 片14：设备状态的阈值框同样换成了 `IosFormDialog` ⇒ 这一节的每一处
          // `_in(AlertDialog, …)` 一起跟着换（同一个步骤里等、点、输入都指着同一枚弹层）。
          await _tap(
            tester,
            _in(CupertinoAlertDialog, find.text('亮度低于')),
            '亮度规则类型 chip',
          );
          await _type(
            tester,
            _in(CupertinoAlertDialog, find.byType(TextField)),
            '闸门亮度规则',
            '亮度规则标题输入框',
          );
          await _tap(
            tester,
            _in(CupertinoAlertDialog, find.text('确定')),
            '设备状态→确定(亮度)',
          );
          await _settle(tester, seconds: 1);

          // 网络型：没有阈值可填 ⇒ 这一条专测"没有滑杆也要能存下来"
          await _tap(
            tester,
            _in(DeviceStatePage, find.byIcon(Icons.add)),
            '设备状态→添加(网络)',
          );
          await _settle(tester);
          await _tap(
            tester,
            _in(CupertinoAlertDialog, find.text('断网时')),
            '网络规则类型 chip',
          );
          // 标题留空 → 列表按类型名显示，就找不回这一条了 ⇒ 给它一个可定位的标题
          await _type(
            tester,
            _in(CupertinoAlertDialog, find.byType(TextField)),
            '闸门断网规则',
            '断网规则标题输入框',
          );
          await _tap(
            tester,
            _in(CupertinoAlertDialog, find.text('确定')),
            '设备状态→确定(网络)',
          );
          await _settle(tester, seconds: 1);

          expect(
            GetIt.instance<DeviceStateService>().rules,
            hasLength(2),
            reason: '两条里有一条没建成（对话框确认链路或落库断链）',
          );
          final brightness = ruleByTitle('闸门亮度规则');
          expect(brightness, isNotNull, reason: '亮度那条没按标题存下来');
          _mark('5.4a.1 亮度那条已按标题找回，开始加网络那条');
          expect(
            (brightness!['value'] as num).toInt(),
            greaterThan(0),
            reason: '亮度阈值为 0 ⇒ 滑杆的值没进规则（这一条永远不触发）',
          );
          final network = ruleByTitle('闸门断网规则');
          expect(network, isNotNull, reason: '断网那条没按标题存下来');
          _mark('5.4a.2 两条都在，开始验族归属与 prefs 镜像');
          expect(
            network!['value'],
            0,
            reason: '网络型没有阈值概念，恒 0；存成别的值说明两型共用了一条取值路径',
          );
          // 落对族：三族同存 engine_rules 一张表、按 family 分列。写错族 = 界面上三条都在，
          // 而原生那一侧按族取列表，这条永远取不到。
          for (final other in [
            GetIt.instance<BatteryService>().rules,
            GetIt.instance<TemperatureService>().rules,
          ]) {
            expect(
              other.map((r) => r['title']),
              isNot(contains('闸门亮度规则')),
              reason: '设备状态规则出现在别的族里 = 族名写错，原生永远读不到它',
            );
          }
          _mark('5.4a.3 两条都留在 device_state 族里（族名对了）');
          final prefs = await SharedPreferences.getInstance();
          expect(
            prefs.getString('device_state_rules'),
            allOf(contains('闸门亮度规则'), contains('闸门断网规则')),
            reason: 'DB 写了而镜像没写 = 原生读的还是旧列表，新规则永远不推',
          );
          _mark('5.4a.4 prefs 镜像里两条都在 ⇒ 下面开始点启停开关');

          // 每条规则一行的启停开关：点下去要回写得见
          final brightnessSwitch = find.descendant(
            of: find.byKey(ValueKey('device-state-row-${brightness['id']}')),
            matching: find.byType(CupertinoSwitch),
          );
          await _tap(tester, brightnessSwitch, '设备状态→亮度规则开关');
          await _settle(tester);
          expect(
            ruleByTitle('闸门亮度规则')!['enabled'],
            isFalse,
            reason: '开关点了不回写 = 界面上停着，用户以为已经关了',
          );
          _mark('5.4a.5 开关回写生效 ⇒ 下面开始长按删除');

          await _longPress(
            tester,
            find.byKey(ValueKey('device-state-row-${brightness['id']}')),
            '设备状态规则行',
          );
          await _tap(
            tester,
            find.descendant(
              of: find.byType(CardActionSheet),
              matching: find.text('删除'),
            ),
            '设备状态→长按→删除',
          );
          await _confirmDelete(tester, '设备状态规则行');
          expect(
            GetIt.instance<DeviceStateService>().rules.map((r) => r['title']),
            ['闸门断网规则'],
            reason: '删一条顺带没了另一条 = 两条同 id，或删除没走单条咽喉',
          );

          await _backToHome(tester);
          await _backToHomeQuietly(tester);
        },
      );
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
          reason:
              '骨架页上没有那枚开关 ⇒ T23 的入口被挪走或改了形状（本步会静默跳过的话，'
              '闸门就再也管不到"设备态告警受不受约束"这件事）',
        );
        final before =
            GetIt.instance<BatteryService>().deviceAlertsRespectConstraints;
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
          // T90 片12：这枚表单弹层换成了共享外壳 `IosFormDialog`（Cupertino 那件）⇒ 等的那一层跟着换。
          // ⚠ 上一轮只改了下面那处 `_tap` 的定位、漏了这一处 `_waitUntil` ⇒ 闸门 3/4 当场红在 5.7
          //   （`Found 0 widgets with type "AlertDialog"`）。**同一枚弹层在一个步骤里被两处引用时，
          //   换件必须一次改全**，只改"点的那处"会让等待先超时，后面的断言根本没跑到。
          await _waitUntil(
            tester,
            find.byType(CupertinoAlertDialog),
            '条件类型对话框',
            seconds: 10,
          );
          // 条件类型是"点开再选"的 iOS 选择器，快照证实选完**连条件对话框也一起关了**
          // （dialog=false）⇒ 不再追这层嵌套弹层，改为断言对话框三要素齐备后取消；
          // 条件能否真落盘由桌面 widget 用例守（跑得快、可断言到控件级）。
          // T90 片12：这枚表单弹层换成了共享外壳 `IosFormDialog`（Cupertino 那件）⇒ 定位跟着换。
          // ⚠ 同文件里上面那处「温度规则对话框」的定位（T90 片12 起）早已换成 `CupertinoAlertDialog`；
          //   本句原写的是「那一处不换」，T90 片28 把温度页最后一枚也迁完之后**本文件再无
          //   Material `AlertDialog` 引用** —— 留着是为了让下一个人改定位前先确认那一枚真的迁了。
          await _tap(
            tester,
            _in(CupertinoAlertDialog, find.text('条件类型')),
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
          expect(
            _modalUp(tester),
            isFalse,
            reason: '条件相关弹层关不掉 ⇒ 后面每节都会在弹层底下找控件',
          );
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
      await _step(
        tester,
        gateFailures,
        '5.8 规则测试器：填一条模拟通知，断言实时链路结果出现',
        () async {
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
        },
      );
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
        // T90 片7：设备名那枚弹层换成了共享的输入弹层 ⇒ 输入框与外壳都改成 Cupertino 那一件。
        // 这里仍按"外壳 + 文案"定位而不是拿 key：闸门要验的就是"用户看得见『保存』那颗"。
        if (find.byType(CupertinoTextField).evaluate().isEmpty) {
          _diagnose(tester, '设备名称弹层未出现');
          fail('设备名称弹层里没有输入框（见上一条 GATE-DIAG 的 pages/texts）');
        }
        await _type(tester, find.byType(CupertinoTextField), '闸门改名', '设备名称输入框');
        // 确认按钮的文案是 l10n.save（"保存"），不是"确定" —— 出处是 `_showDeviceNameDialog`
        // 里那句 confirmText，别照旧行号找（改完文件行号就漂）。
        await _tap(
          tester,
          _in(CupertinoAlertDialog, find.text('保存')),
          '设备名称→保存',
        );
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
          // T90 片6：这两枚弹层换成了共享的选项弹层，行是带 key 的 `CupertinoButton`。
          // ⚠ 这里**不再按文本点**：主题行的文案与页面那一格的副标题（当前档位）是同一串字，
          // 按文本命中两只 ⇒ `.first` 点到底下那一格，弹层重开一次，选档静默丢失
          // （语言那一格第 19 轮就红在这，当时的修法是 scope 到 ListTile；ListTile 没了，
          // 现在直接用行的 key，把"点到同名件"这一整类一次堵掉）。
          await _tap(
            tester,
            find.byKey(const ValueKey('ios-picker-ThemeMode.light')),
            '深色模式→浅色',
          );
          await _settle(tester, seconds: 1);
          await _openMoreRow(tester, '深色模式');
          await _settle(tester);
          await _tap(
            tester,
            find.byKey(const ValueKey('ios-picker-ThemeMode.system')),
            '深色模式→跟随系统',
          );
          await _settle(tester, seconds: 1);
          await _openMoreRow(tester, '语言');
          await _settle(tester);
          // 语言与主题同款：只有选项列表，没有"取消"按钮（第 19 轮快照 dialog=true、无 取消）
          expect(
            find.text('中文'),
            findsWidgets,
            reason: '语言对话框没列出当前语言 = 这层弹层结构变了',
          );
          await _tap(
            tester,
            find.byKey(const ValueKey('ios-picker-AppLanguage.zh')),
            '语言弹窗→选当前语言（关闭）',
          );
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
      // ── 5.14 设备状态页（T18）：更多 → 点进 → 快照逐项 → 推一条设备信息
      // ⚠ 编号接在 5.13 后面：5.10/5.11 已被「设备名称」「深色模式」占用
      await _step(tester, gateFailures, '── 5.14 设备状态页：快照与「推送设备信息」', () async {
        await _backToHomeQuietly(tester);
        // ⚠ 这句标签与 `more_page` 的 `l10n.deviceStatusEntry` **同一处出处**
        //   （ARB 的 `deviceStatusEntry`，中文「设备状态快照」）。2026-10-03 的 `2befab9`
        //   把那个入口改了名而没同步这里 ⇒ 5.14 当场红在"找不到入口"，而**闸门自己
        //   把它归成了"页面改坏了"** —— 真相反过来：页面是好的，定位是旧的。
        //   `test/architecture/` 里有一条守卫钉住这两处同源，改名时它会先红。
        await _openMoreRow(tester, '设备状态快照');
        await _onPage(tester, DeviceSnapshotPage, '设备状态页');
        // 值本身按机器不同（模拟器多半读不到温区），所以这里钉的是**结构**：
        // 一项一行、标签都在。数值级断言会绿在一次写死的桩上，这里不给桩。
        final texts = tester
            .widgetList<Text>(_in(DeviceSnapshotPage, find.byType(Text)))
            .map((t) => t.data ?? '')
            .join(' | ');
        for (final label in [
          '型号',
          '品牌',
          '厂商',
          '系统版本',
          '网络',
          '电量',
          '电池温度',
          '存储',
          '内存',
          '屏幕亮度',
          '已运行',
        ]) {
          expect(
            texts,
            contains(label),
            reason: '设备状态页少了「$label」这一项 ⇒ 快照那页的形状变了，用户看不见这一族读数',
          );
        }
        // 至少有实值（电量/亮度带 %），或者明写读不到 —— 两者都没有就是整片空白
        final hasAnyValue =
            texts.contains('%') ||
            texts.contains('这台设备读不到') ||
            texts.contains('没读到设备快照');
        expect(
          hasAnyValue,
          isTrue,
          reason: '页面画了标签却一个值都没有 ⇒ 快照没读上来，而界面看起来是"正常的一页"',
        );

        await _tap(
          tester,
          find.byKey(const ValueKey('device-status-push')),
          '设备状态→推送设备信息',
        );
        await _settle(tester, seconds: 3);
        expect(
          GetIt.instance<NotificationService>().records.any(
            // ⚠ 与上面那句同源（同一个 ARB 键 `deviceStatusEntry`）：那枚通知的 title
            //   取的就是这个入口标题。第一轮只改了入口定位、跑到这里才红 ⇒ 顺手量到的，
            //   不是猜的（两处曾是一起漏的，只补一处就是"改一半"）。
            (r) => r.title == '设备状态快照',
          ),
          isTrue,
          reason: '点了没落历史记录 ⇒ 送达结果没有落点（原生回传按 id 更新）',
        );
        expect(find.text('已交给通道推送，结果见推送历史'), findsOneWidget);
        await _backToHome(tester);

        await _backToHomeQuietly(tester);
      });
      // ── 5.15 幻念推送页（T42）：那一格的四件事在设备上长什么样 ─────────────
      // 为什么这一节值得加：#157 那六片（建 / 读 / 关 / 换）每一片都改了这个页面，
      // 而闸门此前一次都没进去过 —— 别的设置页都被点了一遍，唯独这一格是盲区。
      // 断言只钉**结构**与**此刻该说什么话**，刻意不按那四把按钮：
      // 按下去就是真网络请求（打的是线上那台服务器），而这一节的价值恰在于
      // "什么都还没做过时，界面有没有替用户编一份列表"。
      await _step(tester, gateFailures, '── 5.15 幻念推送页：端点那一格的形状', () async {
        await _backToHomeQuietly(tester);
        await _openMoreRow(tester, '幻念推送');
        await _onPage(tester, FnthinkPushPage, '幻念推送页');

        final inPage = find.descendant(
          of: find.byType(FnthinkPushPage),
          matching: find.byType(Text),
        );
        // ⚠ 先滚到那一格再收文字：本页是 ListView（懒加载），端点格在视口外时**根本没被 build**，
        // 于是"页面里找不到那句话"既可能是文案改了，也可能是它还没出生 —— 第一次红就是这么来的。
        final endpointCard = find.descendant(
          of: find.byType(FnthinkPushPage),
          matching: find.text('接入端点（给 NAS / 脚本用）'),
        );
        await _scrollUntil(tester, endpointCard);
        await _settle(tester);
        final texts = tester
            .widgetList<Text>(inPage)
            .map((t) => t.data ?? '')
            .join(' | ');
        expect(
          texts,
          contains('接入端点（给 NAS / 脚本用）'),
          reason: '端点那一格没渲染 ⇒ 这一页最重要的入口又回到只能去管理面',
        );
        // 上限那句里的数是**从契约读的**：它在设备上出现，才证明契约 asset 真被加载了
        // （而不是"页面上写死一个 10" —— 那条在 widget 用例里已经被 X5 钉过，这里钉设备上能读到）。
        expect(
          texts,
          contains('这台设备最多建'),
          reason: '端点格没有"最多建几把"那句 ⇒ 契约在设备上没读起来，那一格的所有解释都在说谎',
        );

        final create = find.byKey(const ValueKey('fnthink-endpoint-create'));
        final read = find.byKey(const ValueKey('fnthink-endpoint-read'));
        await _scrollUntil(tester, read);
        for (final pair in [
          ['建一个端点', create],
          ['读一次我建过的入口', read],
        ]) {
          expect(
            pair[1],
            findsOneWidget,
            reason: '${pair[0]} 那一下不在 ⇒ 这一格又只剩"看不见"那一半',
          );
          final button = tester.widget<TextButton>(pair[1] as Finder);
          expect(
            button.onPressed,
            isNotNull,
            reason: '${pair[0]} 是灰的 ⇒ 首屏就被判成不可用（要么 _busy 卡住，要么前置判据写歪）',
          );
        }

        // 还没读过 ⇒ 只能出现"还没读过"那一句；出现"没有端点"就是替用户编了一份列表。
        expect(
          find.byKey(const ValueKey('fnthink-endpoint-list-pending')),
          findsOneWidget,
          reason: '没读过就该说"还没看过"（空白会被读成"你没有"，那是这一格最容易说的假话）',
        );
        expect(
          find.byKey(const ValueKey('fnthink-endpoint-list-none')),
          findsNothing,
          reason: '一次都没读过就说"没有端点"：用户会当着一次没发生的事去重建入口',
        );
        // 没有列表行 ⇒ 没有"关掉这把 / 换一把口令"那两下（此刻连 id 都还不知道）。
        for (final prefix in [
          'fnthink-endpoint-revoke-',
          'fnthink-endpoint-rotate-',
        ]) {
          final rowButtons = find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey &&
                '${(w.key as ValueKey).value}'.startsWith(prefix),
          );
          expect(
            rowButtons,
            findsNothing,
            reason: '$prefix 那一下在没有列表的情况下出现了 ⇒ 按钮指向的是一个还不存在的对象',
          );
        }
        await _backToHome(tester);
        await _backToHomeQuietly(tester);
      });
      // ── 5.16 幻念推送页：名单行上的「发一条」（§4-10 片2b）───────────────
      // 这一格此前只有 widget 用例里的证据，而它有一个**只有设备上才看得见**的形状：
      // "名单是空的 ⇒ 连入口都不该有"。这一节钉三件形状，一个字节都不发出去：
      //   ① 名单里有一行 ⇒ 「发一条」在且可点；② 弹层里正文空着 ⇒ 「发送」是灰的；
      //   ③ 点「取消」⇒ 弹层关掉、结论行不出现（取消了还发出去，说的与做的就不一致）。
      // ⚠ 真发一条**不进闸门**：它打的是线上那台服务器，而且"发出去并被对方收到"要有对端
      //    （#108）—— 闸门只证形状，不证投递。
      await _step(
        tester,
        gateFailures,
        '── 5.16 幻念推送页：名单行上的「发一条」（只验形状）',
        () async {
          // 地址码形状：18 位、Crockford Base32（不含 I/L/O/U），一眼能看出是闸门塞的。
          const gatePeer = 'GATE000000PEER0001';
          final helper = DatabaseHelper();
          // 先清一次：上一轮没收干净的话"名单里有几行"就说不清是谁的错（与 4.2 同一条纪律）。
          await helper.removeFnthinkPeer(gatePeer);
          await helper.upsertFnthinkPeer(
            const FnthinkPeer(
              peerAddress: gatePeer,
              publicKey: 'AAAAgatePeerPublicKeyBytes',
              level: 'L1',
              grantedAt: 1767223200000,
              requestId: 'gate_peer_1',
            ),
          );
          try {
            await _backToHomeQuietly(tester);
            await _openMoreRow(tester, '幻念推送');
            await _onPage(tester, FnthinkPushPage, '幻念推送页');

            final sendEntry = find.byKey(
              const ValueKey('fnthink-peer-send-$gatePeer'),
            );
            // ⚠ 先滚到它再断言：本页是 ListView，名单那一格在视口外时根本没被 build
            // （5.15 第一次红就是这么来的）。
            await _scrollUntil(tester, sendEntry);
            await _settle(tester);
            expect(
              sendEntry,
              findsOneWidget,
              reason: '名单里已经有一行却没有「发一条」入口 ⇒ 那一行只是摆设，用户只能看着对端',
            );
            await _tap(tester, sendEntry, '名单行→发一条（开弹层）');
            await _settle(tester);

            final submit = find.byKey(const ValueKey('fnthink-send-submit'));
            expect(submit, findsOneWidget, reason: '发送弹层没起来 ⇒ 那一格点不动');
            // T90 片19：这枚表单弹层换成了共享外壳 `IosFormDialog`，提交那颗从 `TextButton`
            //  变成了 `CupertinoDialogAction` ⇒ 这里跟着换。⚠ 换的是**读哪个字段**，
            //  断的还是同一件事：正文空着而提交可点 ⇒ 发出去的是一句空话、而对面回执照样算"送达"。
            expect(
              tester.widget<CupertinoDialogAction>(submit).onPressed,
              isNull,
              reason: '正文空着而「发送」可点 ⇒ 点下去发出去的是一句空话，而对面回执照样算"送达"',
            );

            // 取消：弹层关掉 + 结论行不出现（后者是"一个字节都没发"在设备上的可观察形状）。
            final cancel = find.descendant(
              of: find.byType(CupertinoAlertDialog),
              matching: find.widgetWithText(CupertinoDialogAction, '取消'),
            );
            await _tap(tester, cancel, '发送弹层→取消');
            await _settle(tester);
            expect(
              find.byKey(const ValueKey('fnthink-send-body')),
              findsNothing,
              reason: '点了取消而弹层还开着 ⇒ 用户以为取消了',
            );
            expect(
              find.byKey(const ValueKey('fnthink-send-note')),
              findsNothing,
              reason: '取消之后出现结论行 ⇒ 那一发其实发出去了（"取消"说的与做的不一致）',
            );
          } finally {
            // 收尾：下一轮开跑之前名单必须回到"这台没配对过任何一台"（与擦库同一口径）。
            await helper.removeFnthinkPeer(gatePeer);
          }
          await _backToHome(tester);
          await _backToHomeQuietly(tester);
        },
      );
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
      await _verdict(tester, gateFailures, '闸门 3/4');
      // 3/4 是节数最多的一条（15 节），但每节都是"进一页、点两下"的量级；拆之前整轮
      // 实测 8:42（第 15 轮），各条用例占多少要等拆完的第一轮闸门日志才量得出来。
    },
    timeout: const Timeout(_caseCBudget),
  );

  testWidgets(
    '闸门 4/4 备份往返：导出一份 → 篡改本机 → 导回来 → 关键页再点一遍',
    (tester) async {
      final gateFailures = <String, String>{};
      // 7/8 断的是"备份里有没有这一条"，所以先把自己要的现场灌好（不依赖 2/4、3/4 跑没跑）
      await _assemble(tester, _seedBackupFixtures);
      // ── 7. 备份导出 → 篡改本机 → 导入恢复（真文件、真口令、真 DB）
      await _step(
        tester,
        gateFailures,
        '── 7. 备份导出 → 篡改本机 → 导入恢复（真文件、真口令、真 DB）',
        () async {
          await _openMoreRow(tester, '备份与恢复');
          await _onPage(tester, BackupRestorePage, '备份与恢复页');
          _mark('7.1 备份页已进：下面两次 PBKDF2 派生各按秒计（生成）');
          await _tap(tester, find.text('生成备份文件'), '备份→生成备份文件');
          await _settle(tester);
          // T90 片8：备份口令那枚弹层换成了共享的输入弹层 ⇒ 字段是 CupertinoTextField。
          await _type(
            tester,
            find.byType(CupertinoTextField).last,
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
          _mark('7.2 备份文件已落盘，开始验容器外层字段');
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

          // #95：把温度族与设备状态族在本机清空，模拟"换机后拿这份备份恢复"。
          // 不擦就测不出区别：备份里缺这一族时恢复是"缺键 ⇒ 不动本机"，规则条数照样对，
          // 于是这一节会绿着放行"备份根本不包含这两族"（上一版闸门的空转形状正是这样）。
          await GetIt.instance<TemperatureService>().restoreSettings(
            rules: const [],
          );
          await GetIt.instance<DeviceStateService>().restoreSettings(
            rules: const [],
          );
          expect(
            GetIt.instance<TemperatureService>().rules,
            isEmpty,
            reason: '没擦干净 = 下面的断言只是在测本机残留',
          );
          expect(
            GetIt.instance<DeviceStateService>().rules,
            isEmpty,
            reason: '没擦干净 = 下面的断言只是在测本机残留',
          );

          // 导入：FilePicker 返回刚才那个文件 ⇒ 页面真实 readAsString + 解密 + 恢复
          _mark('7.3 本机已篡改、两族已擦净：开始选文件恢复（第二次派生 + 冲突三选）');
          pickedPathForNextCall = backupPath;
          await _tap(tester, find.text('选择备份文件恢复'), '备份→选择备份文件恢复');
          await _settle(tester, seconds: 2);
          // T90 片8：恢复口令走的也是那枚共享输入弹层。
          await _type(
            tester,
            find.byType(CupertinoTextField).last,
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
          // #95：擦掉的两族必须从备份里回来（温度规则在 5.4 建、断网规则在 5.4a 建）
          expect(
            GetIt.instance<TemperatureService>().rules.map((r) => r['type']),
            contains('battery_temp_above'),
            reason: '温度族没进备份/恢复 ⇒ 换机后这条规则静默没了',
          );
          final restoredState = GetIt.instance<DeviceStateService>().rules;
          expect(
            restoredState.map((r) => r['title']),
            contains('闸门断网规则'),
            reason: '设备状态族（亮度/网络）没进备份/恢复',
          );
          expect(
            restoredState.any(
              (r) => (r['type'] ?? '').toString().contains('temp'),
            ),
            isFalse,
            reason: '恢复把温度规则落进设备状态族 = 族名写错，原生按族取列表时那一族永远空',
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
            find.text(_gateWecomUrl),
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
      // ── 影子差异出口（T72 的第一步）——**必须在最后一条用例里**：
      // `release_emulator.sh` 的"缺行判红"读的就是这一行。放在中间某条用例 ⇒ 那条被用例级
      // 超时掐掉时出口跟着一起消失，报告里只剩"闸门没有打印 GATE-DIFF-RING"这个误导结论。
      // 「差异清零才切主路径」是 T21 定的门槛，可今天没有任何地方回答得出"清零了没有"：
      // 那个环住在设备 prefs 里，只有它的单测与 T22 自检读它。所以这里**无条件**打一行 ——
      // `n=0` 是一种答复，**缺这一行**才说明出口自己坏了。环有上限 20，`n=20/20` 要看得见
      // "可能已经挤掉了更早的差异"；最新一条逐字段打，默认的 `EngineRuleDiff#3f2a1c`
      // 写在发版报告里等于没写。
      // 出口自己也要留一行：读了环却没打出来（`read()` 挂住、prefs 读不出来）时，
      // 日志里最后一条痕迹就是这一行，而不是上一节的 BEGIN。
      _mark('影子差异出口：读环并打一行（缺 GATE-DIFF-RING 就是这一段没走完）');
      final ring = await EngineRuleDiffLog().read();
      final byKind = <String, int>{};
      for (final d in ring) {
        byKind[d.kind] = (byKind[d.kind] ?? 0) + 1;
      }
      final newest = ring.isEmpty ? null : ring.last;
      debugPrint(
        'GATE-DIFF-RING ▸ n=${ring.length}/${EngineRuleDiffLog.maxEntries} '
        'kinds=$byKind families=${ring.map((d) => d.family).toSet().toList()} '
        'newest=${newest == null ? '-' : '${newest.family}/${newest.kind}#${newest.index} ${newest.detail}'}',
      );
      await _verdict(tester, gateFailures, '闸门 4/4');
      // 时间口径（拆开之后仍然是"谁先说话"的契约，钉在 release_gate_emulator_test.dart 里）：
      //   节内预算 ×2 ≤ 每条用例超时（一条用例里够两节各挂一次并各自点名）
      //   ≤ 单次调用回退上限 GATE_CASE_TIMEOUT（脚本按用例名分次调用 flutter test）
      //   ≤ 正常一轮 + 一条挂满 + 构建 ≤ CI job 60′
      // 拆之前的 18′ 是给"一条用例装完 24 节"用的：那时一次挂住吃满 18′ 且后面各节全废
      //（㊼ 当年从 18 放宽到 30 的理由是"超时红会被误读成功能回归"，节内预算出现后不再成立
      // —— 现在报出来的已经是"哪一节没跑完"）。
    },
    timeout: const Timeout(_caseDBudget),
  );
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
    // ⚠ 两类输入框都要列进来：T90 之后弹层里是 `CupertinoTextField`，
    //   只列 Material 那一件的话，"看不见输入框"这种红会把人往错的方向带。
    final fields = <String>[
      for (final w in t.widgetList<TextField>(find.byType(TextField)))
        '${w.decoration?.hintText ?? "-"}=${w.controller?.text ?? ""}'
            '${w.obscureText == true ? "(口令)" : ""}',
      for (final w in t.widgetList<CupertinoTextField>(
        find.byType(CupertinoTextField),
      ))
        '${w.placeholder ?? "-"}=${w.controller?.text ?? ""}'
            '${w.obscureText == true ? "(口令)" : ""}',
    ].join(' | ');
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
    // #184 片3：删除类确认框换成了 `CupertinoAlertDialog` —— 它走 `DialogRoute`，
    // **不是 `Dialog` 的子类**，`byType` 又是精确匹配 ⇒ 不加这一条，"有没有模态盖着"
    // 会在弹层还开着的时候答"没有"，下一节就在弹层底下找控件（第 16、17 轮那种红）。
    find.byType(CupertinoAlertDialog).evaluate().isNotEmpty ||
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
  await _withMissNet(t, '$why（长按第一下）', () => t.longPress(f.first));
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
  // 两类都要认：`askConfirm` 自 T90 片3 起是 `CupertinoDialogAction`，而台账里那些历史
  // Material 对话框（`IosDialogActions.confirm` 搭的 `AlertDialog`）仍是 `TextButton`。
  // 只认一种的话，另一种形状的删除确认框就"找不到"—— 而这条 helper 的意义恰恰是
  // "没有确认框当场红"，判据不能跟着本体换一半。（这个 SDK 版本的 `CommonFinders` 没有 anyOf，
  // 所以按"先认 Cupertino、没有再认 Material"的顺序取其一。）
  final cupertinoConfirm = find.widgetWithText(CupertinoDialogAction, '删除');
  final materialConfirm = find.widgetWithText(TextButton, '删除');
  final confirm = cupertinoConfirm.evaluate().isNotEmpty
      ? cupertinoConfirm
      : materialConfirm;
  await _must(t, confirm.evaluate().isNotEmpty, '删除确认框 $why', confirm);
  // 对话框永远在页面控件之后 ⇒ .last 是确认框里那颗，不是页面上的删除按钮
  await t.tap(confirm.last);
  await _settle(t);
  // ⚠ 再多 pump 一会儿：确认框的**下场动画**还没走完、咽喉里的 async 落库与清缓存也还没
  // 回来（两者都在同一个 setState 之前）。少这一段，紧跟其后的手势会打在"还挂在树上"的
  // 模态屏障上 —— 表现为"长按没弹出动作表"，实测就是闸门 T07-B 第一轮的红因。
  await _settle(t, seconds: 2);
}

/// 罩住一次手势，把**"打不中"从静默警告变成一行具名痕迹**。
///
/// `tester.tap()` / `longPress()` 未命中目标时只走 `debugPrint` 抛一条警告、**不抛异常**，
/// 于是那一下可能整个没发生而用例照报绿。2026-09-30 那次全量闸门报的是 8/8 rc=0，
/// 同一份日志里就躺着一条 "would not hit test on the specified widget"（5.11 语言弹层那一行）。
///
/// 这里**刻意先不判红**：先把清单数出来（`grep GATE-MISSED-TAP`），再决定逐条修还是升成闸门红线 ——
/// 一次性硬失败只会让整轮红而拿不到"到底几处"。⚠ 清单目前只覆盖**经过这三个 helper 的手势**
/// （`_tap` / `_type` 聚焦那一下 / `_longPress` 第一下），不是"全闸门只有 1 条"。
///
/// 那一段警告本身含 hit test 明细 + 栈（几十 KB），吞掉，只留第一行结论。
Future<void> _withMissNet(
  WidgetTester t,
  String why,
  Future<void> Function() gesture,
) async {
  final previousPrint = debugPrint;
  final missed = <String>[];
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null &&
        message.contains('would not hit test on the specified widget')) {
      missed.add(message);
      return;
    }
    previousPrint(message, wrapWidth: wrapWidth);
  };
  try {
    await gesture();
  } finally {
    debugPrint = previousPrint;
  }
  for (final m in missed) {
    final one = m.split('\n').first;
    debugPrint(
      'GATE-MISSED-TAP ▸ $why :: ${one.length > 220 ? "${one.substring(0, 220)}..." : one}',
    );
  }
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
  await _withMissNet(t, why, () => t.tap(f.first));
  await _settle(t);
}

Future<void> _type(WidgetTester t, Finder f, String text, String why) async {
  await _scrollUntil(t, f);
  await _must(t, f.evaluate().isNotEmpty, '输入框 $why', f);
  try {
    await t.ensureVisible(f.first);
  } catch (_) {}
  await t.pump(const Duration(milliseconds: 120));
  // ⚠ 这里不能 `as TextField`：T90 片7 起，闸门要往 Cupertino 的输入弹层里也打字
  //   （设备名那一格），那一位是 `CupertinoTextField` —— 直接 cast 会在 5.10 当场炸
  //   （本机模拟器实跑红过一次：`type 'CupertinoTextField' is not a subtype of type 'TextField'`）。
  //   两件外壳底下都是同一个 `EditableText`，读密文开关就读它，别读外壳。
  final obscured = t
      .widget<EditableText>(
        find.descendant(of: f.first, matching: find.byType(EditableText)).first,
      )
      .obscureText;
  await _withMissNet(t, '$why（聚焦那一下）', () => t.tap(f.first));
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

/// 一节最多给这么长时间。**挂住的某一节不该吃掉整轮**：此前每一轮 GATE_RC=124 都是
/// 一整轮 28 分钟什么结论都没有换回来，日志里连"卡在哪"都指不出来。
/// 超时按"该节失败"记账并继续往下走，于是报告里留下的是"某一节 3 分钟没动"，而不是一片空白。
///
/// ⚠ 本预算**只保证点名挂住的那一节**：被打断的 body 取消不掉（用 1ms 预算实测逼出来的，
/// 记录见 base.md（87）），它之后会带着 pending 的 await 与**同一条用例内**后面的每一节抢
/// 同一套测试操作 ⇒ 那条用例里其余各节全部变成 `Guarded function conflict.`。
/// 这正是把 24 节拆成四条独立用例的理由：跨用例不共用手势队列，一次挂住只作废它自己那条。
/// 3 分钟按最重的 5.1（webhook 建两条改一条删两条）实测约 40 秒的十倍给。
const _stepBudget = Duration(minutes: 3);

/// 用例级超时。口径（"谁先说话"是契约而不是巧合，钉在
/// `test/architecture/release_gate_emulator_test.dart` 里）：
///   `_stepBudget` ×2 ≤ 每条用例超时（一条用例里够两节各挂一次并各自点名）
///   ≤ 单次调用回退上限 `GATE_CASE_TIMEOUT`（脚本按用例名分次调用 `flutter test`）
///   ≤ 正常一轮 + 一条挂满 + 构建 ≤ CI job 60′
/// 为什么要**分次调用**而不是一个进程跑完四条：挂住的 body 取消不掉，它占着 binding 的
/// test zone，同一 isolate 里后面的用例会全部死在 `!inTest` 断言上（第 16 轮实测）。
/// 拆之前那一条用例装 24 节，用的是 18′：一次挂住吃满 18′ 且后面各节全废。
const _caseABudget = Duration(minutes: 6);
const _caseBBudget = Duration(minutes: 6);
const _caseCBudget = Duration(minutes: 7); // 节数最多的一条（15 节），但每节都是"进一页点两下"
const _caseDBudget = Duration(minutes: 6); // PBKDF2 两次派生各按秒计，余量给在这里

/// 5.1 建的第二条、2/4 与 4/4 的种子、8 断言"恢复后详情页回显的那条 URL"—— 拆开之后
/// 这三处都要用同一个字面量，所以它只能有一份：**各条用例面对的是同一个初值**，
/// 单跑任意一条与四条连着跑，看到的都是同一条通道。
const _gateWecomUrl =
    'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=gate';

/// 给**没被 `_step` 包住的裸段**留一行里程碑：5.1 webhook / 5.2 邮件 / 5.3 自建应用各自
/// 两百行左右，都是"整轮挂住"最可能发生的地方，而挂住的运行永远走不到 FAIL 那条打印。
/// 没有这些痕迹，日志里留下的只有启动那几行 —— 三轮 GATE_RC=124 就是这么白烧的。
/// 覆盖判据（连续裸代码不许超过 60 行）见 `test/architecture/release_gate_emulator_test.dart`。
void _mark(String name) => debugPrint('GATE-MARK ▸ $name');

/// 每条用例各自装配一遍（㊼ 对 smoke 做过的那种形状，见 `smoke_test.dart` 的 launchApp）。
///
/// 为什么拆：拆之前是**一个** testWidgets 串 24 节 ⇒ 一次挂住要吃满用例级超时，
/// 而且挂住那一节之后每一节都变成 `Guarded function conflict.`（用 1ms 预算实测逼出来的，
/// 记录见 base.md（87））—— 于是 28 分钟只换回"某一节没跑完"这一条信息。
/// 拆成四条之后，一次挂住只带走它自己那条用例，其余三条照常出结论，影子差异出口也照常打印。
///
/// 代价与对策：用例之间不再共享"上一步留下的现场"，所以需要通道的用例自己把它灌进数据层
/// （`_seedWebhookChannel` / `_seedBackupFixtures`）—— 否则单跑某一条必然假红。
/// 起点仍与拆前一致：`release_emulator.sh` 起跑前 `pm clear` 过一次，这里再擦三族通道与
/// 历史记录，因此每条用例面对的是同一个初值。
Future<void> _assemble(
  WidgetTester tester, [
  Future<void> Function()? seed,
]) async {
  // ⚠ 三行顺序要紧：`GetIt.reset()` 是 async 的（不 await ⇒ 上一条用例的 Service 实例
  // 漏进这一条），allowReassignment 必须在下面那两次注册**之前**打开（同一类型第二次
  // register 直接抛），setupLocator 注册的是 lazySingleton，pumpWidget 之前完成即可。
  await GetIt.instance.reset();
  GetIt.instance.allowReassignment = true;
  // ── 装配 ────────────────────────────────────────────────────────────
  setupLocator();
  GetIt.instance.registerSingleton<UpdateService>(_StubUpdateService());

  // 起点必须是干净的：闸门要能重复跑，且"备份里有没有这一条"这类断言依赖初值
  final db = DatabaseHelper();
  await db.saveWebhookChannels([]);
  await db.saveAppChannels([]);
  await db.saveEmailChannels([]);
  await GetIt.instance<NotificationService>().clearRecords();
  // 收件表也要擦，否则上面那句"起点数据已擦干净"对幻念收件是虚的：4.1 的"空态"会变成
  // "恰好是空的"，而上一轮如果中途红过、注入行留在库里，下一轮就是莫名其妙地红。
  await (await db.database).delete(FnthinkInboxMessage.table);

  // 现场灌在 pump **之前**：应用一来就带着这份配置启动，走的是"读已有配置"那条真实路径；灌在 pump 之后则等于在装配中途改配置 —— 会触发页面重建与通道探测。
  // 第 17 轮两处挂住（3/4 的 5.4a、4/4 的第 7 节）都紧跟在"装配完 + 种子写完"之后，这条顺序改动同时是一次否证实验。
  if (seed != null) await seed();

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
  _mark('装配完成：主界面起来、描述符拉通、起点数据已擦干净');
}

/// 用例 3 与用例 4 需要"本机至少有一条已启用的 webhook"：3/4 的 5.9 通道状态页断三族分组，
/// 4/4 的备份往返以它为零点（篡改 +1 条 → 恢复后必须回到 1 条）。
/// 拆开之前这份现场由 5.1 一手建出来，拆开之后每条用例自己灌，灌的是**同一个常量**
/// （`_gateWecomUrl`）与 5.1 留下的形状 ⇒ 单跑一条不假红，两条跑到的也不是两份数据。
Future<void> _seedWebhookChannel() async {
  await GetIt.instance<WebhookService>().saveChannels([
    {
      'id': 'gate_seed_wecom',
      'url': _gateWecomUrl,
      'name': '',
      'channelType': 'wechat_work',
      'enabled': true,
      'secret': '',
    },
  ]);
  _mark('种子现场：一条已启用的企微 webhook');
}

/// 用例 4（备份往返）的完整初值。拆开之前这些现场分别由 5.4 / 5.4a / 5.6 建出来，
/// 现在本节自己灌，且灌的族、类型、标题都和被点掉的那几条一致 —— 因为 7/8 的断言
/// 读的就是这三样（恢复后 `channelType` 仍是 wechat_work、白名单仍是「闸门白名单」、
/// 温度规则仍是 battery_temp_above、设备状态规则标题仍是「闸门断网规则」）。
Future<void> _seedBackupFixtures() async {
  await _seedWebhookChannel();
  final filter = GetIt.instance<FilterService>();
  await filter.saveWhitelistKeywords(['闸门白名单']);
  await filter.saveBlacklistKeywords(<String>[]);
  await GetIt.instance<TemperatureService>().restoreSettings(
    rules: [
      {
        'id': 'gate_seed_temp',
        'type': 'battery_temp_above',
        'title': '闸门温度规则',
        'value': 45,
        'enabled': true,
      },
    ],
  );
  await GetIt.instance<DeviceStateService>().restoreSettings(
    rules: [
      {
        'id': 'gate_seed_net',
        'type': 'network_disconnected',
        'title': '闸门断网规则',
        'value': 0,
        'enabled': true,
      },
    ],
  );
  _mark('种子现场：白名单 + 温度/设备状态各一条规则（4/4 的备份零点）');
}

/// 一条用例收尾：本条被 `_step` 收下的失败在这里统一判红，不吞任何一个。
/// 拆开之前全过程只有一次判红；现在每条用例自己那本账 ⇒ 用例名直接就是"红在哪一类"，
/// 而挂住/超时掐掉的那条用例，它的 `_verdict` 不会执行 —— 那时说话的是用例级超时。
Future<void> _verdict(
  WidgetTester t,
  Map<String, String> failures,
  String caseName,
) async {
  expect(
    t.takeException(),
    isNull,
    reason: '$caseName 过程中出现了未捕获异常（该用例各节已定位到页面）',
  );
  expect(
    failures,
    isEmpty,
    reason:
        '以下闸门步骤失败：\n'
        '${failures.entries.map((e) => "  ▸ ${e.key} → ${e.value}").join("\n")}',
  );
}

/// 一节红掉不影响后面的节继续跑：模拟器一轮要 4 分钟，一节一轮试不起。
/// 失败**照样让闸门红**（末尾统一 expect），只是把"这一轮能看见多少问题"放大。
Future<void> _step(
  WidgetTester t,
  Map<String, String> failures,
  String name,
  Future<void> Function() body,
) async {
  // 每一节开头也留一行：整轮挂住时（无超时 await、死循环），日志里最后一条 BEGIN
  // 就是嫌疑节。只有 FAIL 一条打印的话，挂住的运行留下的只有启动日志，什么都指不出来
  // —— T25 与 T18 各烧掉一轮 28 分钟才知道这件事。
  // 前面已经有一节挂住 ⇒ 这一节不再跑：跑它只会拿到 `Guarded function conflict.`
  //（挂住的 body 没死，还在抢同一套测试操作），而每节收尾的 `_backToHomeQuietly` 还要花时间。
  // 第 21 轮实测：3/4 一节挂住之后其余 14 节把用例级 7 分钟吃满，**连"挂住才重试一次"的
  // 资格都被用例超时挤掉了**。跳过仍记进同一本账 ⇒ 该条用例照样红，不吞任何一个：
  // "没有可信结论"与"通过"不许长得一样。
  if (failures.values.any((m) => m.contains('TimeoutException'))) {
    failures[name] = '已跳过：本条用例前面有一节挂住 ⇒ 这一节没有可信结论（不是通过）';
    debugPrint('GATE-STEP-SKIP ▸ $name');
    return;
  }
  debugPrint('GATE-STEP-BEGIN ▸ $name');
  try {
    await body().timeout(
      _stepBudget,
      onTimeout: () =>
          throw TimeoutException('本节在 $_stepBudget 内没跑完 ⇒ 挂住，不是断言失败'),
    );
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
