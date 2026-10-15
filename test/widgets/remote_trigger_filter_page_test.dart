import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/remote_trigger_filter_page.dart';
import 'package:notice_transmit/services/installed_apps_service.dart';
import 'package:notice_transmit/theme/app_colors.dart';
import 'package:notice_transmit/widgets/app_root.dart';

/// T153 片1：远程触发专用筛选页的**语义判据**。
///
/// 这一页从 `AppFilterPage` 派生而来（维护者 2026-10-15 拍板 Q1=b：派生、两处同步维护），
/// 派生要钉的不是"能不能渲染"，而是**它说的必须是触发、不能是通知**：
/// 那一页的五处文案（标题 / 两枚模式 chip / 模式说明 / 已选摘要 / 底部 info）
/// 全部在说「通知要被推送」，照抄过来就等于维护者反馈的病灶原样存在。
///
/// 三组判据：
///  ① 五处文案都在说触发（允许触发 / 禁止触发），一句"通知应用"都不在场；
///  ② 模式说明跟着档位换（不是切了档还在说上一档的话）；
///  ③ 「完成」走公共件（不继承原页那枚裸 TextButton 的形状）。
///
/// ⚠ 返回契约（`mode` + `packages`）由 `remote_credential_settings_page` 的调用方测
///   （pop 的返回值只有调用方读得到），本文件不断它。
///
/// harness 照 `app_filter_page_test.dart`：原生通道必须打桩 —— 不打桩时
/// `canQueryAllPackages` 抛异常 ⇒ 走"无权限"分支弹引导框 ⇒ `pumpAndSettle`
/// 等那个弹层的动画等到超时（症状是"页面挂住"，很容易被误读成页面自己写坏了）。
const _channel = MethodChannel('com.fnthink.notice/notification');

final _installedApps = [
  {'packageName': 'com.alpha.app', 'appName': 'Alpha', 'isSystemApp': false},
  {'packageName': 'com.beta.app', 'appName': 'Beta', 'isSystemApp': false},
];

void _mockChannel() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!GetIt.instance.isRegistered<InstalledAppsService>()) {
    GetIt.instance.registerLazySingleton<InstalledAppsService>(
      () => InstalledAppsService(),
    );
  }
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

Widget _buildApp(Widget home) =>
    AppRoot(locale: const Locale('zh'), dark: false, home: home);

void main() {
  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  testWidgets('标题是「可触发的应用」，不是「应用筛选」', (tester) async {
    _mockChannel();
    await tester.pumpWidget(_buildApp(const RemoteTriggerFilterPage()));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(RemoteTriggerFilterPage)),
    );

    expect(find.text(l10n.remoteTriggerFilterTitle), findsOneWidget);
    // 通知筛选那一页的标题**不许**出现在这一页上
    expect(find.text(l10n.appFilter), findsNothing);
  });

  testWidgets('两枚模式 chip 是「允许触发 / 禁止触发」，通知那两个词一个都不在场', (tester) async {
    _mockChannel();
    await tester.pumpWidget(_buildApp(const RemoteTriggerFilterPage()));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(RemoteTriggerFilterPage)),
    );

    expect(find.text(l10n.remoteTriggerAllow), findsOneWidget);
    expect(find.text(l10n.remoteTriggerBlock), findsOneWidget);
    // 这一组是本病灶的正面判据：照抄 `AppFilterPage` 文案时它们立刻红
    expect(find.text(l10n.filterNotifyApps), findsNothing);
    expect(find.text(l10n.filterBlockApps), findsNothing);
    // 模式说明整句也不许是通知语义（未选择时的默认那句）
    expect(find.text(l10n.appFilterAllowModeInfo), findsNothing);
    expect(find.text(l10n.appFilterBlockModeInfo), findsNothing);
    // 已选摘要那两句同理（切到 block 档 + 勾一个才出现，这里先断"默认态不出现"）
    expect(find.text(l10n.appFilterAllowModeSelected(1)), findsNothing);
    expect(find.text(l10n.appFilterBlockModeSelected(1)), findsNothing);
  });

  testWidgets('模式说明说的是「触发」，且切档后整句跟着换', (tester) async {
    _mockChannel();
    await tester.pumpWidget(_buildApp(const RemoteTriggerFilterPage()));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(RemoteTriggerFilterPage)),
    );

    // 默认 allow 空清单 ⇒「当前模式：允许触发 — 只有选中的应用，其通知正文才能触发本机远程指令」
    expect(find.text(l10n.remoteTriggerAllowModeInfo), findsOneWidget);
    // 切到 block 档 ⇒ 说明跟着换成 block 那句（不是还在说 allow）
    await tester.tap(find.text(l10n.remoteTriggerBlock));
    await tester.pumpAndSettle();
    expect(find.text(l10n.remoteTriggerBlockModeInfo), findsOneWidget);
    expect(find.text(l10n.remoteTriggerAllowModeInfo), findsNothing);
  });

  testWidgets('「完成」走公共件，不是裸 TextButton', (tester) async {
    _mockChannel();
    await tester.pumpWidget(_buildApp(const RemoteTriggerFilterPage()));
    await tester.pumpAndSettle();
    // 派生页不继承原页那枚裸 TextButton 的形状（T153 片6 要清的那一族）
    expect(find.byKey(const ValueKey('remote-trigger-done')), findsOneWidget);
  });

  testWidgets('派生页确实独立实现（不是转发回 AppFilterPage）', (tester) async {
    _mockChannel();
    await tester.pumpWidget(_buildApp(const RemoteTriggerFilterPage()));
    await tester.pumpAndSettle();
    // 行为侧能看出来的那一半：这一页自己画出了应用清单
    // （转发回去的话，清单会带着通知文案一起出现，上面那几条已经红过）
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    // 真正的源码断言在 test/architecture/remote_trigger_page_derivation_test.dart
  });

  testWidgets('卡片底色与主题一致（派生页不是裸 Scaffold）', (tester) async {
    _mockChannel();
    await tester.pumpWidget(_buildApp(const RemoteTriggerFilterPage()));
    await tester.pumpAndSettle();
    final element = tester.element(find.byType(RemoteTriggerFilterPage));
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, AppColors.bgColor(element));
  });
}
