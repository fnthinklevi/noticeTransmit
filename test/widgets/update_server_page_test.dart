import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/update_server_page.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/services/update_server_regions.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/channel_health_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「更新服务器」选择页（T95 片3）。
///
/// 钉的四件事，都不是"画出来了"而是"点了会生效 / 说不出就别说"：
/// ① 进这一页 = 两台**各**探一次（候选恒两台，探不通也不从列表里拿掉 —— T76 的口径）；
/// ② 自动档只有两台都被测过才比较，结论落盘；手动钉住之后另一台再快也不许自动改；
/// ③ 每一行的"最新版 / 安装包来自哪儿"绑的是**那一台**的回答，不是把一台的数字抄两遍；
/// ④ 徽标来自健康度单点：注入替身换掉探测，换不掉记账。
void main() {
  late ChannelHealthStore health;
  late List<UpdateServerRegion> asked;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    health = ChannelHealthStore();
    asked = <UpdateServerRegion>[];
  });

  UpdateServerProbe reached(
    UpdateServerRegion region, {
    required int ms,
    required String version,
    required String cdn,
  }) => UpdateServerProbe(
    region: region,
    reachable: true,
    latencyMs: ms,
    httpCode: 200,
    latestVersion: version,
    latestBuild: 999,
    downloadHost: cdn,
  );

  UpdateServerProbe down(UpdateServerRegion region, {int? code}) =>
      UpdateServerProbe(
        region: region,
        reachable: false,
        latencyMs: 0,
        httpCode: code,
      );

  /// 开页。[answers] 决定这一台被探到时的回答；缺的那一档按"没回话"回答。
  Future<AppLocalizations> open(
    WidgetTester tester, {
    Map<UpdateServerRegion, UpdateServerProbe>? answers,
  }) async {
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: UpdateServerPage(
          health: health,
          probe: (region) async {
            asked.add(region);
            return answers?.containsKey(region) == true
                ? answers![region]!
                : down(region);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(UpdateServerPage)));
  }

  Finder row(UpdateServerRegion region) =>
      find.byKey(ValueKey('update-server-row-${region.name}'));

  Finder status(UpdateServerRegion region) =>
      find.byKey(ValueKey('update-server-status-${region.name}'));

  Future<void> prefs(
    WidgetTester tester, {
    UpdateServerMode? mode,
    UpdateServerRegion? manual,
    UpdateServerRegion? auto,
  }) async {
    final p = await SharedPreferences.getInstance();
    if (mode != null) {
      await p.setString(UpdateServerSettings.keyMode, mode.name);
    }
    if (manual != null) {
      await p.setString(UpdateServerSettings.keyManualRegion, manual.name);
    }
    if (auto != null) {
      await p.setString(UpdateServerSettings.keyAutoRegion, auto.name);
    }
  }

  testWidgets('打开这一页 = 两台各探一次，两档都摆出来', (tester) async {
    await open(tester);
    expect(asked, UpdateServerRegion.ordered);
    for (final region in UpdateServerRegion.ordered) {
      expect(find.text(region.apiHost), findsOneWidget);
    }
  });

  testWidgets('两台都没探通：说"两台都没探通"，也仍然列出两台（不藏那一台）', (tester) async {
    await open(tester);
    expect(
      find.byKey(const ValueKey('update-server-both-down')),
      findsOneWidget,
    );
    // 自动档一次都没测出来 —— 这句必须与"测出来用的是默认那台"分开。
    expect(
      find.byKey(const ValueKey('update-server-auto-unprobed')),
      findsOneWidget,
    );
    final p = await SharedPreferences.getInstance();
    expect(p.getString(UpdateServerSettings.keyAutoRegion), isNull);
    expect(find.text(UpdateServerRegion.mainland.apiHost), findsOneWidget);
    expect(find.text(UpdateServerRegion.international.apiHost), findsOneWidget);
  });

  testWidgets('自动档取更快那台：结论落盘，行上标"当前用这一台"', (tester) async {
    final l10n = await open(
      tester,
      answers: {
        UpdateServerRegion.mainland: reached(
          UpdateServerRegion.mainland,
          ms: 800,
          version: '1.9.9',
          cdn: 'cdn.fnthink.com',
        ),
        UpdateServerRegion.international: reached(
          UpdateServerRegion.international,
          ms: 120,
          version: '1.9.9',
          cdn: 'cdn2.fnthink.top',
        ),
      },
    );
    final p = await SharedPreferences.getInstance();
    expect(p.getString(UpdateServerSettings.keyAutoRegion), 'international');
    expect(
      find.text(l10n.updateServerInUse),
      findsOneWidget,
      reason: '只有一行能标"当前用这一台"，两行都标就等于没说',
    );
    expect(
      find.descendant(
        of: row(UpdateServerRegion.international),
        matching: find.byKey(
          const ValueKey('update-server-inuse-international'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('update-server-auto-unprobed')),
      findsNothing,
    );
  });

  testWidgets('手动钉住海外之后：大陆即使 1 毫秒也不自动改', (tester) async {
    await prefs(
      tester,
      mode: UpdateServerMode.manual,
      manual: UpdateServerRegion.international,
    );
    await open(
      tester,
      answers: {
        UpdateServerRegion.mainland: reached(
          UpdateServerRegion.mainland,
          ms: 1,
          version: '1.9.9',
          cdn: 'cdn.fnthink.com',
        ),
        UpdateServerRegion.international: reached(
          UpdateServerRegion.international,
          ms: 900,
          version: '1.9.9',
          cdn: 'cdn2.fnthink.top',
        ),
      },
    );
    final p = await SharedPreferences.getInstance();
    expect(p.getString(UpdateServerSettings.keyMode), 'manual');
    expect(
      find.byKey(const ValueKey('update-server-inuse-international')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('update-server-inuse-mainland')),
      findsNothing,
    );
  });

  testWidgets('点一行 = 钉住那一台（切手动）', (tester) async {
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: UpdateServerPage(
          health: health,
          probe: (region) async =>
              reached(region, ms: 100, version: '1.9.9', cdn: region.cdnHost),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(row(UpdateServerRegion.mainland));
    await tester.pumpAndSettle();

    final p = await SharedPreferences.getInstance();
    expect(p.getString(UpdateServerSettings.keyMode), 'manual');
    expect(p.getString(UpdateServerSettings.keyManualRegion), 'mainland');
    expect(
      find.byKey(const ValueKey('update-server-inuse-mainland')),
      findsOneWidget,
    );
  });

  testWidgets('每行绑的是那一台的回答（两台的数字会漂，这里要看得见）', (tester) async {
    await open(
      tester,
      answers: {
        UpdateServerRegion.mainland: reached(
          UpdateServerRegion.mainland,
          ms: 50,
          version: '1.9.9',
          cdn: 'cdn.fnthink.com',
        ),
        UpdateServerRegion.international: reached(
          UpdateServerRegion.international,
          ms: 400,
          version: '1.8.0',
          cdn: 'cdn2.fnthink.top',
        ),
      },
    );
    expect(
      find.descendant(
        of: row(UpdateServerRegion.mainland),
        matching: status(UpdateServerRegion.mainland),
      ),
      findsOneWidget,
    );
    final mainlandText = tester
        .widget<Text>(
          find.descendant(
            of: row(UpdateServerRegion.mainland),
            matching: status(UpdateServerRegion.mainland),
          ),
        )
        .data!;
    final intlText = tester
        .widget<Text>(
          find.descendant(
            of: row(UpdateServerRegion.international),
            matching: status(UpdateServerRegion.international),
          ),
        )
        .data!;
    expect(mainlandText, contains('1.9.9'));
    expect(mainlandText, contains('cdn.fnthink.com'));
    expect(intlText, contains('1.8.0'));
    expect(intlText, contains('cdn2.fnthink.top'));
    expect(mainlandText, isNot(intlText));
  });

  testWidgets('探测结果进了健康度单点，两行都画得出徽标（注入替身换不掉记账）', (tester) async {
    await open(
      tester,
      answers: {
        UpdateServerRegion.mainland: reached(
          UpdateServerRegion.mainland,
          ms: 50,
          version: '1.9.9',
          cdn: 'cdn.fnthink.com',
        ),
        UpdateServerRegion.international: down(
          UpdateServerRegion.international,
          code: 403,
        ),
      },
    );
    for (final region in UpdateServerRegion.ordered) {
      expect(
        health.of(kUpdateHealthFamily, region.name),
        isNotNull,
        reason: '${region.name} 那一档探完没写进单点，徽标就永远"没测过"',
      );
    }
    final p = await SharedPreferences.getInstance();
    expect(
      p.getString('channel_health_$kUpdateHealthFamily:mainland'),
      isNotNull,
      reason: '只在内存里记 = 重开这一页又回到"没测过"',
    );
    expect(find.byType(ChannelHealthBadge), findsNWidgets(2));
    // 没通那一档把状态码说出来：被 CDN 拦与这台宕机是两个下一步。
    expect(
      tester.widget<Text>(status(UpdateServerRegion.international)).data,
      contains('403'),
    );
  });

  testWidgets('成段说明只在问号弹层里（页面摆短说，全文点出来）', (tester) async {
    final l10n = await open(tester);
    expect(find.text(l10n.updateServerShort), findsOneWidget);
    expect(find.text(l10n.updateServerHelpBody), findsNothing);

    await tester.tap(find.byKey(const ValueKey('update-server-desc-help')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.updateServerHelpBody), findsOneWidget);
    expect(find.text(l10n.updateServerHelpTitle), findsOneWidget);
  });
}
