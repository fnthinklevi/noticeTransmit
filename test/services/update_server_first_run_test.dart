import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/services/update_server_probe.dart';
import 'package:notice_transmit/services/update_server_regions.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T95 片4：第一次进入按网络实测选一台（`ensureFirstRunRegion`）。
///
/// 这里钉的是**什么时候允许动偏好**：
/// ① 从没选过、也从没测出来过 ⇒ 动一次；
/// ② 用户钉过 ⇒ 一次都不许多探（更不许改）；
/// ③ 已经有过结论 ⇒ 也不再动（首启只动一次，之后由「更新服务器」那一页的实测更新）；
/// ④ 两台都没探通 ⇒ **不落结论**，下次进入还会再试。把失败落成"就用默认这台"，
///    界面上就再也没人知道曾经失败过 —— 那正是本仓最反对的那种绿。
void main() {
  late ChannelHealthStore health;
  late List<UpdateServerRegion> asked;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    health = ChannelHealthStore();
    asked = <UpdateServerRegion>[];
  });

  Future<void> run(Map<UpdateServerRegion, UpdateServerProbe> answers) =>
      ensureFirstRunRegion(
        health: health,
        probe: (region) async {
          asked.add(region);
          return answers[region]!;
        },
      );

  UpdateServerProbe reached(UpdateServerRegion r, int ms) => UpdateServerProbe(
    region: r,
    reachable: true,
    latencyMs: ms,
    httpCode: 200,
  );

  const down = UpdateServerProbe(
    region: UpdateServerRegion.mainland,
    reachable: false,
    latencyMs: 0,
  );

  test('从没选过：两台各探一次，更快那台落进偏好', () async {
    await run({
      UpdateServerRegion.mainland: reached(UpdateServerRegion.mainland, 900),
      UpdateServerRegion.international: reached(
        UpdateServerRegion.international,
        110,
      ),
    });
    expect(asked, UpdateServerRegion.ordered);
    final p = await SharedPreferences.getInstance();
    expect(p.getString(UpdateServerSettings.keyAutoRegion), 'international');
    expect(
      p.getString(UpdateServerSettings.keyMode),
      isNull,
      reason: '自动档不落 mode 键：没选过就是没选过',
    );
    expect(health.of(kUpdateHealthFamily, 'international'), isNotNull);
  });

  // ── T96 片2：先按国家码（服务端地理回读），拿不到才走上面那套时延实测 ──

  test('读到了国家码 ⇒ 直接按它落档，**时延那一发根本不发**', () async {
    await ensureFirstRunRegion(
      health: health,
      countryOf: () async => 'CN',
      probe: (region) async {
        asked.add(region);
        return reached(region, 1);
      },
    );
    final p = await SharedPreferences.getInstance();
    expect(p.getString(UpdateServerSettings.keyAutoRegion), 'mainland');
    expect(asked, isEmpty, reason: '读到了事实还去测时延 ⇒ 慢的那一档可能把国家码顶掉，而它是更弱的判据');
  });

  test('拿不到国家码（没声明信任 / 不通）⇒ 回落时延实测，且**不猜档**', () async {
    await ensureFirstRunRegion(
      health: health,
      countryOf: () async => null,
      probe: (region) async {
        asked.add(region);
        return reached(
          region,
          region == UpdateServerRegion.mainland ? 90 : 800,
        );
      },
    );
    expect(asked, UpdateServerRegion.ordered, reason: '拿不到就该走第二步');
    final p = await SharedPreferences.getInstance();
    expect(p.getString(UpdateServerSettings.keyAutoRegion), 'mainland');
  });

  test('国家码认得出才落档；空 / 短码都回 null', () {
    expect(regionForCountryCode('CN'), UpdateServerRegion.mainland);
    expect(regionForCountryCode('cn'), UpdateServerRegion.mainland);
    expect(regionForCountryCode('US'), UpdateServerRegion.international);
    expect(regionForCountryCode(null), isNull);
    expect(regionForCountryCode(''), isNull);
    expect(regionForCountryCode('C'), isNull, reason: '长度不对就是没读到');
  });

  test('用户钉过那一台：一次都不许探，更不许改偏好', () async {
    final p = await SharedPreferences.getInstance();
    await p.setString(UpdateServerSettings.keyMode, 'manual');
    await p.setString(
      UpdateServerSettings.keyManualRegion,
      UpdateServerRegion.international.name,
    );

    await run({
      UpdateServerRegion.mainland: reached(UpdateServerRegion.mainland, 1),
      UpdateServerRegion.international: reached(
        UpdateServerRegion.international,
        9999,
      ),
    });
    expect(asked, isEmpty, reason: '已有偏好 ⇒ 这一发根本不该发出去');
    expect(p.getString(UpdateServerSettings.keyManualRegion), 'international');
    expect(p.getString(UpdateServerSettings.keyAutoRegion), isNull);
  });

  test('已经有过结论：首启不重复选（之后由服务器选择页那一发更新）', () async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      UpdateServerSettings.keyAutoRegion,
      UpdateServerRegion.mainland.name,
    );

    await run({
      UpdateServerRegion.mainland: reached(UpdateServerRegion.mainland, 900),
      UpdateServerRegion.international: reached(
        UpdateServerRegion.international,
        10,
      ),
    });
    expect(asked, isEmpty);
    expect(p.getString(UpdateServerSettings.keyAutoRegion), 'mainland');
  });

  test('两台都没探通：不落结论，下次进入还会再试', () async {
    await run({
      UpdateServerRegion.mainland: down,
      UpdateServerRegion.international: const UpdateServerProbe(
        region: UpdateServerRegion.international,
        reachable: false,
        latencyMs: 0,
      ),
    });
    final p = await SharedPreferences.getInstance();
    expect(
      p.getString(UpdateServerSettings.keyAutoRegion),
      isNull,
      reason: '"没测出来"不许被落成一条看起来像结论的偏好',
    );
    final settings = await UpdateServerSettings.load();
    expect(settings.autoUnprobed, isTrue);
    // 但两台各自"没通"这件事要记进健康度单点 —— 徽标说的是最近一次试过。
    expect(health.of(kUpdateHealthFamily, 'mainland')!.reachable, isFalse);
    expect(health.of(kUpdateHealthFamily, 'international')!.reachable, isFalse);
  });
}
