import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:notice_transmit/di/service_locator.dart';
import 'package:notice_transmit/main.dart' show MyApp;
import 'package:notice_transmit/update_manager.dart' show VersionCheckResult;
import 'package:notice_transmit/services/channel_descriptor_service.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/services/archive_worker.dart'
    show archiveCallbackDispatcher;
import 'package:notice_transmit/services/update_service.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Q1 真机/模拟器集成冒烟测试：7 步主链路。
///
/// 运行方式（需真机或模拟器）：
///   flutter test integration_test/smoke_test.dart -d `<device>`
///
/// 原生通道策略：com.fnthink.notice/notification 统一 mock（按方法名分发，
/// 未知方法返回 null）；数据库 sqflite_sqlcipher 与 AndroidKeyStore 走真实实现。
/// CI 接入见 .github/workflows/integration_test.yml。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final capturedCalls = <String, List<List<Object?>>>{};

  setUpAll(() async {
    // WorkManager 必须在这里补初始化：本文件的 main() 直接 pumpWidget(MyApp())，
    // **不会执行应用的 main()**（`lib/main.dart` 里那句 Workmanager().initialize 因此被跳过），
    // 而 ArchiveWorker 在页面装配阶段就调用 registerPeriodicTask →
    // 平台侧抛 "You have not properly initialized the Flutter WorkManager Package"。
    // 这里镜像应用真实启动路径（而不是 mock 掉该通道），让冒烟测试仍覆盖真机 WorkManager。
    Workmanager().initialize(archiveCallbackDispatcher);

    // 真实 SharedPreferences 与 KeyStore 均可用，仅预置首启/隐私状态跳过弹窗
    SharedPreferences.setMockInitialValues({
      'flutter.privacy_policy_accepted': true,
      'privacy_policy_accepted': true,
      'has_launched': true,
      // 语言必须显式钉成中文：本测试的断言用的是中文 UI 文案，而
      // LocaleService 在 system 模式下回落到**设备语言**——模拟器默认 en，
      // 于是所有中文 find.text 落空（首个症状是 tabNotification 找不到）。
      // 键名与值都按 LocaleService 的实现写（'app_language' = AppLanguage.name）。
      'app_language': 'zh',
      'flutter.app_language': 'zh',
      'last_system_lang': 'zh',
      'flutter.last_system_lang': 'zh',
    });

    // 原生通道 mock：按方法名分发；未知方法返回 null（走 Flutter 默认值兜底）
    const channelName = 'com.fnthink.notice/notification';
    final stubs = <String, Object?>{
      'getSimCardCount': 2,
      'isNotificationPermissionGranted': true,
      'isPostNotificationPermissionGranted': true,
      'isSmsPermissionGranted': true,
      'isPhonePermissionGranted': true,
      // 三态契约（㊸）：权限页读的是状态字符串，不再是布尔
      'getAppListPermissionState': 'granted',
      'isIgnoringBatteryOptimizations': true,
      'canScheduleExactAlarms': true,
      'isExactAlarmEnabled': false,
      'isServiceRunning': false,
      'getEnabledPackages': <String>[],
      'getBlacklistKeywords': <String>[],
      'getWhitelistKeywords': <String>[],
      'getAppFilterMode': 'allow',
      'getWebhookChannels': <Map<String, dynamic>>[],
      // 第 5 步：splash 的装配链会 await 这个调用。桩必须给出**非空**列表 ——
      // 服务对空列表按"原生未就绪"处理（不覆盖缓存），那样冒烟跑的就只是降级分支。
      // ⚠️ 这里只是形状正确的最小桩：真实导出内容 + 能否过 MethodChannel 编码，
      //    由设备侧 ChannelDescriptorsInstrumentedTest 与 JVM 侧
      //    ChannelDescriptorExportTest 锁（Dart 测试一律走 mock，碰不到原生分支）。
      'getChannelDescriptors': <Map<String, Object?>>[
        <String, Object?>{
          'family': 'webhook',
          'key': 'dingtalk',
          'nativeType': 'DINGTALK',
          'labelKey': 'channelTypeDingtalk',
          'iconKey': 'dingtalk',
          'hosts': <String>['oapi.dingtalk.com'],
          'capabilities': <String>[
            'secretUsed',
            'jsonContract',
            'customTemplate',
          ],
          'fields': <Map<String, Object?>>[],
        },
        <String, Object?>{
          'family': 'app',
          'key': 'wecom_app',
          'nativeType': 'wecom_app',
          'labelKey': 'channelTypeWecomApp',
          'iconKey': 'wecom_app',
          'hosts': <String>['qyapi.weixin.qq.com'],
          'officialBase': 'https://qyapi.weixin.qq.com',
          'capabilities': <String>['secretUsed', 'markdown'],
          'fields': <Map<String, Object?>>[
            <String, Object?>{
              'key': 'corpid',
              'labelKey': 'appChannelCorpidLabel',
              'kind': 'text',
              'required': true,
            },
          ],
        },
      ],
      'getEmailChannels': <Map<String, dynamic>>[],
      'getDeviceName': '冒烟设备',
      'getAppVersion': {'versionName': '1.5.63', 'versionCode': 98},
      'getBatteryStatus': {'level': 80, 'isCharging': false, 'status': 3},
      'getDownloadDirectory': '/tmp/smoke',
      // 步骤 4/5：注入离线通知与送达结果（loadRecords 时入库）
      'drainOfflineCache': <Map<String, dynamic>>[
        {
          'id': 'smoke_offline_1',
          'title': '冒烟离线通知',
          'content': '集成冒烟测试注入的离线通知内容',
          'subText': '',
          'packageName': 'com.smoke.app',
          'appName': '冒烟应用',
          'postTime': 1767223200000,
          'time': '2026-01-01 10:00:00',
          'type': 'notification',
          'priority': 1,
        },
      ],
      'drainDeliveryResults': <Map<String, dynamic>>[
        {
          'notificationId': 'smoke_offline_1',
          'webhookType': 'DINGTALK',
          'status': 'SUCCESS',
          'message': 'ok',
          'httpCode': 200,
          'channelUrl': 'https://oapi.dingtalk.com/robot/send',
        },
      ],
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), (
          call,
        ) async {
          capturedCalls
              .putIfAbsent(call.method, () => [])
              .add(
                call.arguments is List
                    ? [call.arguments as Object?]
                    : [call.arguments],
              );
          if (stubs.containsKey(call.method)) return stubs[call.method];
          return null;
        });
  });

  Future<void> pumpFor(WidgetTester t, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  /// 轮询等待 finder 命中（真实异步：DB/KeyStore/通道往返不与帧同步）
  Future<void> waitUntil(
    WidgetTester t,
    Finder finder, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 200));
      if (finder.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    expect(finder.evaluate().isNotEmpty, isTrue, reason: '等待超时: $finder');
  }

  testWidgets('7 步主链路冒烟：启动→注入→通知页→送达状态→历史→服务启停→导出', (tester) async {
    // ── 环境装配 ────────────────────────────────────────────────
    setupLocator();
    // 屏蔽真实 CDN 检查更新（避免网络与弹窗干扰主链路）
    GetIt.instance.allowReassignment = true;
    GetIt.instance.registerSingleton<UpdateService>(_StubUpdateService());

    // ── 步骤 1：启动装配（隐私/首启弹窗已跳过，MainPage 出现）──
    await tester.pumpWidget(const MyApp());
    await waitUntil(tester, find.byType(NavigationBar));
    // 后续 11 处断言全部依赖中文文案，这里先验证语言预置真的生效：
    // 失败时报"语言回落"而不是"0 widgets with text 通知"，避免排查方向被带偏。
    expect(
      find.text('通知'),
      findsWidgets,
      reason:
          'tabNotification 未渲染中文 —— 语言钉定未生效，'
          '检查 setUpAll 的 app_language 预置与 LocaleService 回落逻辑',
    );

    // ── 步骤 1.5：通道描述符已随装配链就绪（第 5 步）──────────────
    // 设置页的字段清单与显隐全按它渲染；这里若为 false，说明 splash 漏了 await
    // 或 GetIt 未注册 —— 表现是"打开设置页时表单缺字段"，静态测试查不出来。
    expect(
      GetIt.instance<ChannelDescriptorService>().isReady,
      isTrue,
      reason: 'splash 未拉取通道描述符（装配链缺 await / 注册缺失 / 原生无该分支）',
    );

    // ── 步骤 2：数据注入（drainOfflineCache/drainDeliveryResults 已在 mock 中）
    // ⚠ 通知 tab 是「服务仪表盘」（圆形开关 + 条数 + 通道），**不渲染记录列表**——
    //   记录只在历史页出现。所以这里等的是 service 内存态；等 find.text(标题) 是步骤 5 的事。
    //   （原实现在此等标题文本，25s 必超时。）
    final notificationService = GetIt.instance<NotificationService>();
    final injectDeadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(injectDeadline) &&
        notificationService.records.every((r) => r.id != 'smoke_offline_1')) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(
      notificationService.records.any((r) => r.id == 'smoke_offline_1'),
      isTrue,
      reason: 'drainOfflineCache 的记录未合并进内存列表（loadRecords 链路断）',
    );

    // ── 步骤 3：仪表盘把条数反映到界面（recordCount = 共 N 条记录）──
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('共 1 条记录'),
      findsWidgets,
      reason: '仪表盘未反映注入后的记录条数（notificationCount 链路断）',
    );

    // ── 步骤 4：送达状态 success（drainDeliveryResults → updateDelivery 幂等补更新）
    await pumpFor(tester, const Duration(seconds: 1));
    final record = notificationService.records.firstWhere(
      (r) => r.id == 'smoke_offline_1',
    );
    // 送达键与语言无关（DB v11 起为 chan:<slug>）。历史上键就是显示名，曾因
    // LocaleService 尚未 init 而按系统语言写成 'webhook:DingTalk'，实时回传再写
    // 中文键 → 同一记录中英双键。此处锁「存储键必须是 chan: 键」；装配期语言
    // 竞态本身由 bootstrap_order_test 在源码层守（显示名仍依赖 init 顺序）。
    expect(record.deliveryStatus['chan:dingtalk']['status'], 'success');
    expect(
      record.deliveryStatus.keys.every((k) => k.startsWith('chan:')),
      isTrue,
      reason: '出现非 chan: 前缀的送达键 = 键又长回了本地化显示名',
    );

    // ── 步骤 5：历史页呈现记录与送达徽标（推送成功）
    await tester.tap(find.text('推送历史'));
    await pumpFor(tester, const Duration(seconds: 2));
    await waitUntil(tester, find.text('冒烟离线通知'));
    expect(find.text('推送成功'), findsWidgets); // deliverySuccess
    // 返回通知页：pageBack() 只找 CupertinoNavigationBarBackButton（本页是 Material 路由，
    // 且中文 locale 下背键 tooltip 不是它预期的 'Back'）→ 直接从 Navigator 弹出，
    // 不依赖任何本地化文案。
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await pumpFor(tester, const Duration(milliseconds: 800));

    // ── 步骤 6：服务启停（通知页圆形按钮 → mock 捕获 start/stop）
    // ⚠ 「通知监听服务未启动，点击可启动」那行是**纯 Text**（notification_page.dart:97），
    //   没有手势；真正可点的是上面的圆形按钮（onTap: onStartService/onStopService）。
    //   点文案不会报错（tap 只是打在坐标上），但方法不会被调用——曾在此静默失败。
    final serviceToggle = find.byKey(const ValueKey<String>('service-toggle'));
    await tester.tap(serviceToggle);
    await pumpFor(tester, const Duration(seconds: 1));
    expect(
      capturedCalls['startNotificationListener'],
      isNotNull,
      reason: '应调用原生 startNotificationListener',
    );
    expect(notificationService.serviceRunning, isTrue);
    await tester.tap(serviceToggle);
    await pumpFor(tester, const Duration(seconds: 1));
    expect(
      capturedCalls['stopNotificationListener'],
      isNotNull,
      reason: '应调用原生 stopNotificationListener',
    );

    // ── 步骤 6.5：tab 切换 → 通知页「短信监听」卡片 → 验证码开关（mock 捕获 setSmsSetting）
    //   ⚠ 入口是**通知仪表盘上的卡片**（标题 l10n.smsMonitor = 短信监听），不在更多页：
    //     原实现先点「更多」再找「短信监听设置」（那是点进去之后的页面标题），必然 0 命中。
    await tester.tap(find.text('更多'));
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.text('通知'));
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.text('短信监听'));
    await pumpFor(tester, const Duration(seconds: 1));
    await waitUntil(tester, find.text('监听验证码'));
    // 应用内开关已统一为 CupertinoSwitch（Material Switch 已全量替换）
    final switches = find.byType(CupertinoSwitch);
    expect(switches.evaluate().length, greaterThanOrEqualTo(2));
    await tester.tap(switches.at(1)); // 第二个开关 = 监听验证码
    await pumpFor(tester, const Duration(seconds: 1));
    final smsCalls = capturedCalls['setSmsSetting'] ?? const [];
    expect(
      smsCalls.any(
        (a) =>
            a.isNotEmpty &&
            a.first is Map &&
            (a.first as Map)['key'] == 'sms_code_monitor_enabled',
      ),
      isTrue,
      reason: '切换验证码开关应回写 setSmsSetting',
    );

    // ── 步骤 7：导出 JSON 契约（真实 DB 全量读取）
    final json = await notificationService.buildExportJson(
      '冒烟设备',
      'Pixel',
      'Google',
    );
    expect(json.contains('recordCount'), isTrue);
    expect(json.contains('smoke_offline_1'), isTrue);
    expect(json.contains('_warning'), isTrue);
  });
}

/// 检查更新桩：返回 null = 无更新，避免真实 CDN 网络与弹窗干扰主链路。
class _StubUpdateService extends UpdateService {
  @override
  Future<VersionCheckResult?> checkUpdate({bool force = false}) async => null;
}
