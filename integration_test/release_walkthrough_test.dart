import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/di/service_locator.dart';
import 'package:notice_transmit/main.dart' show MyApp;
import 'package:notice_transmit/pages/app_channel_list_page.dart';
import 'package:notice_transmit/pages/app_channel_settings_page.dart';
import 'package:notice_transmit/pages/app_filter_page.dart';
import 'package:notice_transmit/pages/backup_restore_page.dart';
import 'package:notice_transmit/pages/battery_page.dart';
import 'package:notice_transmit/pages/email_settings_page.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/pages/keywords_page.dart';
import 'package:notice_transmit/pages/more_page.dart';
import 'package:notice_transmit/pages/notification_page.dart';
import 'package:notice_transmit/pages/permission_settings_page.dart';
import 'package:notice_transmit/pages/rule_edit_page.dart';
import 'package:notice_transmit/pages/rule_list_page.dart';
import 'package:notice_transmit/pages/rule_tester_page.dart';
import 'package:notice_transmit/pages/sms_monitor_settings_page.dart';
import 'package:notice_transmit/pages/stats_page.dart';
import 'package:notice_transmit/pages/temperature_page.dart';
import 'package:notice_transmit/pages/webhook_settings_page.dart';
import 'package:notice_transmit/services/app_channel_service.dart';
import 'package:notice_transmit/services/battery_service.dart';
import 'package:notice_transmit/services/channel_descriptor_service.dart';
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
      'getInstalledApps': <Map<String, dynamic>>[
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
      ],
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
      // 描述符必须给**非空**桩：空列表按"原生未就绪"处理（见 smoke 的同一注释）
      'getChannelDescriptors': <Map<String, Object?>>[
        _descriptor(
          'webhook',
          'dingtalk',
          'DINGTALK',
          '钉钉',
          ['oapi.dingtalk.com'],
          ['secretUsed', 'jsonContract', 'customTemplate'],
        ),
        _descriptor(
          'webhook',
          'wechat_work',
          'WECHAT_WORK',
          '企业微信',
          ['qyapi.weixin.qq.com'],
          ['markdown', 'customTemplate'],
        ),
        _descriptor(
          'app',
          'wecom_app',
          'wecom_app',
          '企业微信应用',
          ['qyapi.weixin.qq.com'],
          ['secretUsed', 'markdown'],
          extra: {
            'officialBase': 'https://qyapi.weixin.qq.com',
            'fields': <Map<String, Object?>>[
              <String, Object?>{
                'key': 'corpid',
                'labelKey': 'appChannelCorpidLabel',
                'kind': 'text',
                'required': true,
              },
              <String, Object?>{
                'key': 'agentid',
                'labelKey': 'appChannelAgentIdLabel',
                'kind': 'text',
                'required': true,
              },
            ],
          },
        ),
      ],
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
    await _backToHome(tester);

    // ── 5. 更多 tab：以下每个入口逐个进页，页面级 CRUD 各自走完 ──────────
    await _tap(tester, find.text('更多'), '底部 tab→更多');
    await _onPage(tester, MorePage, '更多页');

    // 5.1 Webhook 通道：建两条 → 保存 → 重进 → 删掉第一行 → 保存
    //     删完必须断言"活下来的是哪一条"：删一行后其余行继承错位 id 是这个页面
    //     真实发生过的缺陷类别（保存走 delete+insert，见 webhook_settings_page 注释）。
    await _openMoreRow(tester, 'Webhook 推送通道');
    await _onPage(tester, WebhookSettingsPage, 'Webhook 设置页');
    const dingUrl = 'https://oapi.dingtalk.com/robot/send?access_token=gate';
    const wecomUrl =
        'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=gate';
    await _fillWebhookUrl(tester, dingUrl);
    // URL 填完 ⇒ 类型选择器应显出「自动识别·钉钉」：描述符与 host 识别表都在工作
    expect(
      find.textContaining('自动识别'),
      findsWidgets,
      reason: '填完 URL 后类型选择器没有按 host 识别 ⇒ 描述符/识别表断链',
    );
    await _tap(tester, _appBarText('保存'), 'Webhook→保存(第一条)');
    await _settle(tester, seconds: 2);
    await _backToHome(tester);
    expect(
      GetIt.instance<WebhookService>().channels,
      hasLength(1),
      reason: '第一条通道没存进去',
    );
    // 第二次改：重进 → 加一行 → 填企微地址 → 保存（一次只改一件事，红的时候能点名）
    await _openMoreRow(tester, 'Webhook 推送通道');
    await _onPage(tester, WebhookSettingsPage, 'Webhook 设置页(加第二条)');
    await _tap(tester, find.text('添加通道'), 'Webhook→添加第二条');
    await _fillWebhookUrl(tester, wecomUrl);
    await _tap(tester, _appBarText('保存'), 'Webhook→保存(两条)');
    await _settle(tester, seconds: 2);
    await _backToHome(tester);
    expect(
      GetIt.instance<WebhookService>().channels.map((c) => c['url']),
      containsAll(<String>[dingUrl, wecomUrl]),
      reason: '两条通道没能都存进去（或保存时把已有那条丢了）',
    );
    await _openMoreRow(tester, 'Webhook 推送通道');
    await _onPage(tester, WebhookSettingsPage, 'Webhook 设置页(重进)');
    await _tap(
      tester,
      _in(WebhookSettingsPage, find.byIcon(Icons.delete_outline)),
      'Webhook→删除第一行',
    );
    await _settle(tester);
    await _tap(tester, _appBarText('保存'), 'Webhook→保存(删后)');
    await _settle(tester, seconds: 2);
    await _backToHome(tester);
    final kept = GetIt.instance<WebhookService>().channels;
    expect(kept, hasLength(1), reason: '删掉一行后应该只剩 1 条通道');
    expect(
      kept.single['url'],
      'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=gate',
      reason: '删第一行后活下来的不是预期那条 = 下标/id 错位（备份与恢复都会跟着错）',
    );
    expect(
      kept.single['channelType'],
      'wechat_work',
      reason: '按 URL 识别出来的类型没落库（也是后面备份往返的基准）',
    );

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
    await _onPage(tester, AppChannelSettingsPage, '应用通道编辑页');
    // 必填校验：空表点保存必须**点名缺哪个字段**并拒绝写入（第 5 步表单收口的承课）
    await _tap(tester, _appBarText('保存'), '应用通道→空表保存(应被拦)');
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
    await _tap(tester, _appBarText('保存'), '应用通道→保存');
    await _settle(tester, seconds: 2);
    expect(
      GetIt.instance<AppChannelService>().channels,
      hasLength(1),
      reason: '自建应用通道未保存（必填校验/字段键名链路）',
    );
    await _backToHome(tester);

    // 5.4 温度推送：加一条规则 → 开关切一次
    await _step(tester, gateFailures, '5.4 温度推送：加一条规则 → 开关切一次', () async {
      await _backToHomeQuietly(tester);
      await _openMoreRow(tester, '温度推送');
      await _onPage(tester, TemperaturePage, '温度推送页');
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

    // 5.5 应用筛选：切模式 → 勾一个应用 → 完成
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

    // 5.7 规则引擎：编辑预制规则(加一个条件) → 新建 → 删除新建的
    await _step(
      tester,
      gateFailures,
      '5.7 规则引擎：编辑预制规则(加一个条件) → 新建 → 删除新建的',
      () async {
        await _backToHomeQuietly(tester);
        await _openMoreRow(tester, '规则引擎');
        await _onPage(tester, RuleListPage, '规则引擎列表');
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
      await _openMoreRow(tester, '规则引擎');
      await _tap(
        tester,
        _in(RuleListPage, find.byIcon(Icons.science_outlined)),
        '规则引擎→规则测试器',
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
        await _openMoreRow(tester, '规则引擎');
        await _tap(
          tester,
          _in(RuleListPage, find.byIcon(Icons.playlist_add_check_outlined)),
          '规则引擎→规则模板库',
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

    // ── 6. 电量 tab：加规则 → 切开关
    await _step(tester, gateFailures, '── 6. 电量 tab：加规则 → 切开关', () async {
      await _backToHomeQuietly(tester);
      await _tap(tester, find.text('电量'), '底部 tab→电量');
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
      await _tap(tester, find.text('通知'), '底部 tab→回通知页');
      await _settle(tester, seconds: 1);

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
        await _onPage(tester, WebhookSettingsPage, '恢复后的 Webhook 设置页');
        expect(
          find.text(
            'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=gate',
          ),
          findsWidgets,
          reason: '恢复后通道类型/URL 不匹配 ⇒ 备份把通道改写了（㊹② 那一类）',
        );
        expect(
          GetIt.instance<WebhookService>().channels.single['channelType'],
          'wechat_work',
          reason: '恢复把企微通道改成了别的类型 = 数据级缺陷',
        );
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
  }, timeout: const Timeout(Duration(minutes: 18)));
}

/// 描述符桩：形状与 `getChannelDescriptors` 的导出契约一致
/// （family/key/nativeType/labelKey/iconKey/hosts/capabilities/fields）。
Map<String, Object?> _descriptor(
  String family,
  String key,
  String nativeType,
  String label,
  List<String> hosts,
  List<String> capabilities, {
  Map<String, Object?> extra = const {},
}) {
  return <String, Object?>{
    'family': family,
    'key': key,
    'nativeType': nativeType,
    'labelKey': 'gateLabel$key',
    'iconKey': key,
    'hosts': hosts,
    'capabilities': capabilities,
    'fields': <Map<String, Object?>>[],
    ...extra,
  };
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

/// Webhook 行里输入框的顺序是「名称 → URL →（密钥/模板，随类型能力变化）」，
/// 按下标取会随通道类型漂移；URL 输入框在**为空时**必定显示占位文案，
/// 于是"还带占位文案的那个 TextField"就是下一个待填的 URL 框。
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
  expect(
    f.evaluate().isNotEmpty,
    isTrue,
    reason: '找不到待填的 Webhook URL 输入框（占位文案未渲染或行没建出来）',
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
    final nav = t.state<NavigatorState>(find.byType(Navigator).first);
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

/// 更多页里某个入口是否已经可见/可点，统一交给 `_scrollUntil`（在 `_tap`/`_type` 里自动调用）。
