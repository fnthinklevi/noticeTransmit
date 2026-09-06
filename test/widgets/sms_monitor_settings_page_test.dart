import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations_delegate.dart';
import 'package:notice_transmit/pages/sms_monitor_settings_page.dart';
import 'package:notice_transmit/services/sms_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('com.fnthink.notice/notification');

Widget _buildApp(Widget home) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh'), Locale('en')],
    locale: const Locale('zh'),
    home: home,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'setSmsSetting') return true;
          return null;
        });
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('SmsMonitorSettingsPage – widget 测试', () {
    testWidgets('渲染三个设置区块', (tester) async {
      await tester.pumpWidget(
        _buildApp(SmsMonitorSettingsPage(smsService: SmsService())),
      );
      await tester.pumpAndSettle();

      expect(find.text('短信监听'), findsOneWidget);
      expect(find.text('监听卡'), findsOneWidget);
      expect(find.text('监听验证码'), findsOneWidget);
    });

    testWidgets('切换总开关后状态生效并持久化', (tester) async {
      final service = SmsService();
      await tester.pumpWidget(
        _buildApp(SmsMonitorSettingsPage(smsService: service)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(service.smsMonitorEnabled, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sms_monitor_enabled'), isFalse);
    });

    testWidgets('选择仅卡1时弹出系统限制提醒弹窗', (tester) async {
      final service = SmsService();
      await tester.pumpWidget(
        _buildApp(SmsMonitorSettingsPage(smsService: service)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('仅卡1'));
      await tester.pumpAndSettle();

      expect(find.text('部分短信可能无法识别所属卡'), findsOneWidget);
      expect(service.simFilter, '1');

      // 关闭弹窗后选择回到"全部"不再弹窗
      await tester.tap(find.text('好的'));
      await tester.pumpAndSettle();
      expect(find.text('部分短信可能无法识别所属卡'), findsNothing);
    });

    testWidgets('选择全部卡不弹提醒弹窗', (tester) async {
      final service = SmsService();
      await service.saveSimFilter('1');
      await tester.pumpWidget(
        _buildApp(SmsMonitorSettingsPage(smsService: service)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();

      expect(find.text('部分短信可能无法识别所属卡'), findsNothing);
      expect(service.simFilter, 'all');
    });

    testWidgets('单卡设备：监听卡选项置灰不可选', (tester) async {
      // 覆盖 setUp 的通用 mock：单卡设备返回 1
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            switch (call.method) {
              case 'setSmsSetting':
                return true;
              case 'getSimCardCount':
                return 1;
              default:
                return null;
            }
          });

      final service = SmsService();
      await service.loadSettings();
      expect(service.simCardCount, 1);

      await tester.pumpWidget(
        _buildApp(SmsMonitorSettingsPage(smsService: service)),
      );
      await tester.pumpAndSettle();

      // 副标题切换为单卡提示
      expect(find.text('当前设备仅检测到一张SIM卡，无需选择'), findsOneWidget);

      // 点击"仅卡1"不生效（置灰禁用）：无提醒弹窗、配置不变
      await tester.tap(find.text('仅卡1'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('部分短信可能无法识别所属卡'), findsNothing);
      expect(service.simFilter, 'all');
    });
  });
}
