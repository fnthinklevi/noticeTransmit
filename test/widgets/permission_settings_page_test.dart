import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/permission_settings_page.dart';
import 'package:notice_transmit/services/platform_channel.dart';
import 'package:notice_transmit/services/permission_service.dart';

/// 权限设置页此前**没有任何**自动化契约 —— "点这一行到底发生了什么"全靠读代码。
/// 维护者 1.5.76 反馈 #3 改的就是这一行的行为，所以先把行为钉住：
/// 一次点击 = 一次申请动作，中间那层应用内说明框不再挡路。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = AppChannels.notification;
  late int appListTaps;

  Future<void> pumpPage(
    WidgetTester tester, {
    required String appListState,
  }) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getAppListPermissionState') return appListState;
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
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        locale: const Locale('zh'),
        home: PermissionSettingsPage(
          notificationListenerGranted: false,
          postNotificationGranted: false,
          batteryOptimizationIgnored: false,
          smsPermissionGranted: false,
          phonePermissionGranted: false,
          appListPermissionGranted: appListState == 'granted',
          manufacturer: 'meizu',
          onRefresh: () async {},
          onRequestNotificationListenerPermission: () {},
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

  group('应用列表权限那一行（1.5.76 反馈 #3）', () {
    testWidgets('点一下就直接发起申请，不再先弹应用内说明框', (tester) async {
      await pumpPage(tester, appListState: 'unknown');

      await tester.tap(find.text('应用列表权限'));
      await tester.pumpAndSettle();

      expect(appListTaps, 1, reason: '这一行的语义就是"去申请"，点一次就该走一次');
      expect(
        find.text('需要应用列表权限'),
        findsNothing,
        reason: '那层说明框是用户要拿掉的中间步骤（它的文案还写着"将跳转到系统设置页"）',
      );
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
}
