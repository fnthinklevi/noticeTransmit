import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:notice_transmit/di/service_locator.dart';
import 'package:notice_transmit/main.dart' show MyApp;
import 'package:notice_transmit/update_manager.dart' show VersionCheckResult;
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/services/update_service.dart';
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
    // 真实 SharedPreferences 与 KeyStore 均可用，仅预置首启/隐私状态跳过弹窗
    SharedPreferences.setMockInitialValues({
      'flutter.privacy_policy_accepted': true,
      'privacy_policy_accepted': true,
      'has_launched': true,
    });

    // 原生通道 mock：按方法名分发；未知方法返回 null（走 Flutter 默认值兜底）
    const channelName = 'com.fnthink.notice/notification';
    final stubs = <String, Object?>{
      'getSimCardCount': 2,
      'isNotificationPermissionGranted': true,
      'isPostNotificationPermissionGranted': true,
      'isSmsPermissionGranted': true,
      'isPhonePermissionGranted': true,
      'isAppListPermissionGranted': true,
      'isIgnoringBatteryOptimizations': true,
      'canScheduleExactAlarms': true,
      'isExactAlarmEnabled': false,
      'isServiceRunning': false,
      'getEnabledPackages': <String>[],
      'getBlacklistKeywords': <String>[],
      'getWhitelistKeywords': <String>[],
      'getAppFilterMode': 'allow',
      'getWebhookChannels': <Map<String, dynamic>>[],
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
    expect(find.text('通知'), findsWidgets); // tabNotification

    // ── 步骤 2：数据注入（drainOfflineCache/drainDeliveryResults 已在 mock 中）
    // loadRecords 于 _postInit 执行；此处等待记录进入 service 内存与真实 DB
    final notificationService = GetIt.instance<NotificationService>();
    await waitUntil(
      tester,
      find.text('冒烟离线通知'),
      timeout: const Duration(seconds: 25),
    );

    // ── 步骤 3：通知页渲染（通知标题可见，ActiveChannels 非崩溃）──
    expect(find.text('冒烟离线通知'), findsWidgets);

    // ── 步骤 4：送达状态 success（drainDeliveryResults → updateDelivery 幂等补更新）
    await pumpFor(tester, const Duration(seconds: 1));
    final record = notificationService.records.firstWhere(
      (r) => r.id == 'smoke_offline_1',
    );
    expect(record.deliveryStatus['webhook:钉钉']['status'], 'success');

    // ── 步骤 5：历史页呈现记录与送达徽标（推送成功）
    await tester.tap(find.text('推送历史'));
    await pumpFor(tester, const Duration(seconds: 2));
    await waitUntil(tester, find.text('冒烟离线通知'));
    expect(find.text('推送成功'), findsWidgets); // deliverySuccess
    // 返回通知页
    await tester.pageBack();
    await pumpFor(tester, const Duration(milliseconds: 800));

    // ── 步骤 6：服务启停（通知页圆形按钮 → mock 捕获 start/stop）
    await tester.tap(find.text('通知监听服务未启动，点击可启动'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(
      capturedCalls['startNotificationListener'],
      isNotNull,
      reason: '应调用原生 startNotificationListener',
    );
    expect(notificationService.serviceRunning, isTrue);
    await tester.tap(find.text('通知监听服务正在运行，点击可停止'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(
      capturedCalls['stopNotificationListener'],
      isNotNull,
      reason: '应调用原生 stopNotificationListener',
    );

    // ── 步骤 6.5：更多页 → 短信监听设置 → 验证码开关切换（mock 捕获 setSmsSetting）
    await tester.tap(find.text('更多'));
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.text('短信监听设置'));
    await pumpFor(tester, const Duration(seconds: 1));
    await waitUntil(tester, find.text('监听验证码'));
    final switches = find.byType(Switch);
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
