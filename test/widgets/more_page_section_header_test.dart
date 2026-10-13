import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/email_channel.dart';
import 'package:notice_transmit/models/fnthink_channel.dart';
import 'package:notice_transmit/pages/more_page.dart';
import 'package:notice_transmit/services/battery_service.dart';
import 'package:notice_transmit/services/device_info_service.dart';
import 'package:notice_transmit/services/locale_service.dart';
import 'package:notice_transmit/services/update_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/fnthink_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T146 片4 的页面级证据：「更多」页那五张组标题由公共件画出来。
///
/// 这一页以前自己搭了一枚 13px/**w500** 的组标题壳（与权限设置页那枚逐字相同），
/// 而幻念那三张清单页走的是 13px/w600 的公共件 `FnthinkRowLabel` ——
/// 同一个角色两把尺，谁都不会发现自己漂了（T146 片3 结尾登记的那笔欠账）。
///
/// ⚠ 整页是 `ListView`（懒布局）：默认 800×600 视口下第五张组标题压根没被建出来，
///   finder 会报"找不到"而让人误以为行为没了 ⇒ 给一个足够高的视口，让五段都在场。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await GetIt.instance.reset();
    // 这一页的语言格与设备格直接 `GetIt<LocaleService>()`／`DeviceInfoService()`／`BatteryService()`，
    // 没装配就是整页构建期抛异常 —— 表现是"那一格找不到"，真原因是装配缺件。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GetIt.instance.registerSingleton<LocaleService>(LocaleService());
    GetIt.instance.registerSingleton<UpdateService>(UpdateService());
    GetIt.instance.registerSingleton<DeviceInfoService>(DeviceInfoService());
    GetIt.instance.registerSingleton<BatteryService>(BatteryService());
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Future<void> pumpMore(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 7200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: MorePage(
          webhookChannels: const [],
          appChannels: const [],
          emailChannels: const <EmailChannel>[],
          fnthinkChannels: const <FnthinkChannel>[],
          deviceName: '测试机',
          enabledPackagesCount: 0,
          blacklistCount: 0,
          whitelistCount: 0,
          ruleCount: 0,
          isCheckingUpdate: false,
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          onOpenWebhookSettings: () {},
          onOpenEmailSettings: () {},
          onOpenAppChannels: () {},
          onOpenFnthinkChannels: () {},
          onShowDeviceNameDialog: () {},
          onShowAboutDialog: () {},
          onOpenAppFilter: () {},
          onOpenKeywords: () {},
          onOpenRules: () {},
          onCheckUpdate: () {},
          onOpenUpdateServer: () {},
          onOpenPrivacyPolicy: () {},
          onChangeLanguage: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('五张组标题都在，且每一枚都由 `FnthinkRowLabel` 画出来', (tester) async {
    await pumpMore(tester);
    for (final key in [
      'more-section-appearance',
      'more-section-push-channels',
      'more-section-filter-rules',
      'more-section-device',
      'more-section-about-update',
    ]) {
      final cell = find.byKey(ValueKey(key));
      expect(
        cell,
        findsOneWidget,
        reason: '组标题那一格的 key 读不到 ⇒ 页面又自己搭了一份壳，key 会跟着措辞漂',
      );
      expect(
        find.ancestor(of: cell, matching: find.byType(FnthinkRowLabel)),
        findsOneWidget,
        reason:
            'key 还在、画的却不是 `FnthinkRowLabel` ⇒ 这一族又长出第二个作者，'
            '字号与字重会各漂各的（w500 对 w600 就是这么活下来的）',
      );
    }
  });

  testWidgets('组标题的文字仍是那五句（换件不许改口径）', (tester) async {
    await pumpMore(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(MorePage)));
    for (final title in [
      l10n.appearance,
      l10n.pushChannels,
      l10n.filterRules,
      l10n.device,
      l10n.aboutUpdate,
    ]) {
      expect(
        find.text(title),
        findsWidgets,
        reason: '那张组标题的文字不见了 ⇒ 换件时把内容也换掉了（这一片只许动画法）',
      );
    }
  });
}
