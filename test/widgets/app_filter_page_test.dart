import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/app_filter_page.dart';

const _channel = MethodChannel('com.fnthink.notice/notification');

Widget _buildApp(Widget home) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh'), Locale('en')],
    locale: const Locale('zh'),
    home: home,
  );
}

final _installedApps = [
  {'packageName': 'com.alpha.app', 'appName': 'Alpha', 'isSystemApp': false},
  {'packageName': 'com.beta.app', 'appName': 'Beta', 'isSystemApp': false},
  {'packageName': 'com.gamma.app', 'appName': 'Gamma', 'isSystemApp': false},
];

/// Mock 原生通道：有权限 + 返回固定应用列表
void _mockChannel() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        switch (call.method) {
          case 'canQueryAllPackages':
            return true;
          case 'getCachedInstalledApps':
          case 'getInstalledApps':
            return _installedApps;
          default:
            return null;
        }
      });
}

void main() {
  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('AppFilterPage – 已选/未选分组', () {
    testWidgets('未做选择时不显示已选/未选分组，列表平铺', (tester) async {
      _mockChannel();
      await tester.pumpWidget(
        _buildApp(const AppFilterPage(installedApps: [], enabledPackages: [])),
      );
      await tester.pumpAndSettle();

      // 三个应用全部平铺展示
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Gamma'), findsOneWidget);
      // 无任何分组头（注意：模式提示横幅文案里含"未选"，必须用精确匹配）
      expect(find.text('未选 0'), findsNothing);
      expect(find.text('未选 3'), findsNothing);
      expect(find.text('已选 3'), findsNothing);
    });

    testWidgets('有选择时已选应用置顶，显示已选/未选分组头', (tester) async {
      _mockChannel();
      await tester.pumpWidget(
        _buildApp(
          const AppFilterPage(
            installedApps: [],
            enabledPackages: ['com.alpha.app', 'com.gamma.app'],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 分组头：已选 2 / 未选 1（工具栏计数也是"已选 2"，共 2 处）
      expect(find.text('已选 2'), findsNWidgets(2));
      expect(find.text('未选 1'), findsOneWidget);

      // 三个应用都在列表中
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Gamma'), findsOneWidget);

      // 已选应用置顶：Alpha/Gamma 排在未选的 Beta 之上
      final alphaTop = tester.getTopLeft(find.text('Alpha')).dy;
      final gammaTop = tester.getTopLeft(find.text('Gamma')).dy;
      final betaTop = tester.getTopLeft(find.text('Beta')).dy;
      expect(alphaTop, lessThan(betaTop));
      expect(gammaTop, lessThan(betaTop));
    });

    testWidgets('取消全部选择后恢复平铺（分组头消失）', (tester) async {
      _mockChannel();
      await tester.pumpWidget(
        _buildApp(
          const AppFilterPage(
            installedApps: [],
            enabledPackages: ['com.alpha.app'],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已选 1'), findsWidgets);

      // 点击已选中的 Alpha 取消选择
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(find.text('未选 3'), findsNothing); // 无分组头
      expect(find.text('已选 1'), findsNothing);
      expect(find.text('已选 0'), findsOneWidget); // 工具栏计数归零
    });

    testWidgets('无权限：进入弹窗提醒，拒绝后显示提示文案，点击文案发起申请', (tester) async {
      var requestCalls = 0;
      TestWidgetsFlutterBinding.ensureInitialized();
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            switch (call.method) {
              case 'canQueryAllPackages':
                return false;
              case 'requestQueryAllPackagesPermission':
                requestCalls++;
                return true;
              default:
                return null;
            }
          });

      await tester.pumpWidget(
        _buildApp(const AppFilterPage(installedApps: [], enabledPackages: [])),
      );
      await tester.pumpAndSettle();

      // 进入页面先弹权限提醒弹窗
      expect(find.text('需要应用列表权限'), findsOneWidget);

      // 选择"拒绝"：不申请权限，列表区域显示提示文案
      await tester.tap(find.text('拒绝'));
      await tester.pumpAndSettle();
      expect(requestCalls, 0);
      final promptFinder = find.textContaining('当前无应用列表读取权限');
      expect(promptFinder, findsOneWidget);

      // 点击提示文案：直接发起权限申请
      await tester.tap(promptFinder);
      await tester.pumpAndSettle();
      expect(requestCalls, 1);
    });
  });
}
