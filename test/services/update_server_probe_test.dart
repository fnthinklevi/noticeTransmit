import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notice_transmit/services/update_server_regions.dart';
import 'package:notice_transmit/update_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T95 片2：更新流按档位取 apiBase，并把「检查更新」那一发同时记成一次探测。
///
/// 每一件都用**行为**验（在假 http 服务器上真跑一次），不去 grep 源码里那行
/// `${_region.apiBase}`：读源码的守卫验不出"改动没接上、链路还在走 .top"这一种坏法，
/// 也只有真跑一次才能同时看到请求打去哪、回调里报了什么、prefs 落了什么。
void main() {
  const okPayload = {
    'code': 0,
    'message': 'success',
    'data': {
      'hasUpdate': true,
      'latestVersion': '1.9.9',
      'latestBuild': 999,
      'forceUpdate': false,
      'changelog': 'x',
      'changelogEn': 'x',
      'downloadUrl':
          'https://cdn.fnthink.com/app/notice/update/1.9.9/notice_all_1.9.9.apk',
      'fileSize': 1,
      'minSupportedVersion': '1.0.0',
      'downloads': {
        'all':
            'https://cdn.fnthink.com/app/notice/update/1.9.9/notice_all_1.9.9.apk',
      },
      'fileSizes': {'all': 1},
      'sha256': {'all': 'aa'},
    },
  };

  http.Response json200() => http.Response(
    jsonEncode(okPayload),
    200,
    headers: {'content-type': 'application/json'},
  );

  /// 真跑一次检查更新：带回"这一发打去了哪台"与"报出来的探测结论"。
  Future<({List<String> hosts, List<UpdateServerProbe> probes})> runCheck(
    Future<http.Response> Function(http.Request request) handler,
  ) async {
    final hosts = <String>[];
    final probes = <UpdateServerProbe>[];
    await AppUpdateManager.instance.checkUpdate(
      force: true,
      onProbe: ({required probe}) async => probes.add(probe),
      client: MockClient((request) async {
        hosts.add(request.url.host);
        return handler(request);
      }),
    );
    return (hosts: hosts, probes: probes);
  }

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('检查更新走哪一台', () {
    test('没选过 = 走默认那一台（.top，也就是本改动之前的行为）', () async {
      final r = await runCheck((_) async => json200());
      expect(r.hosts, ['notice.fnthink.top']);
    });

    test('钉住大陆 ⇒ 那一发问的是 notice.fnthink.com（不是只改了徽标）', () async {
      final s = await UpdateServerSettings.load();
      await s.setManual(UpdateServerRegion.mainland);

      final r = await runCheck((_) async => json200());
      expect(r.hosts, ['notice.fnthink.com']);
      expect(AppUpdateManager.instance.region, UpdateServerRegion.mainland);
    });

    test('自动档跟着最近一次实测走：recordAutoProbe 之后检查更新就换台', () async {
      final s = await UpdateServerSettings.load();
      await s.recordAutoProbe(UpdateServerRegion.mainland);

      final r = await runCheck((_) async => json200());
      expect(r.hosts, ['notice.fnthink.com']);
    });

    test('先钉大陆再切回自动（没测过）⇒ 回到默认那一台，不把钉过的档演成结论', () async {
      final s = await UpdateServerSettings.load();
      await s.setManual(UpdateServerRegion.mainland);
      await s.setAuto();

      final r = await runCheck((_) async => json200());
      expect(r.hosts, ['notice.fnthink.top']);
    });
  });

  group('检查更新那一发同时报出探测结论', () {
    test('200 ⇒ reachable、档位、这一台报的最新版与它实际下发的 CDN 主机名都带上', () async {
      final r = await runCheck((_) async => json200());
      expect(r.hosts, hasLength(1), reason: '这一发本身就是探测，不该再多发一发');
      expect(r.probes, hasLength(1));
      final probe = r.probes.single;
      expect(probe.reachable, isTrue);
      expect(probe.httpCode, 200);
      expect(probe.region, UpdateServerRegion.international);
      expect(probe.latestVersion, '1.9.9');
      expect(probe.latestBuild, 999);
      expect(probe.downloadHost, 'cdn.fnthink.com');
    });

    test('500 ⇒ 报不可达并带状态码；一次检查只报一次', () async {
      final r = await runCheck((_) async => http.Response('boom', 500));
      expect(r.probes.map((p) => p.reachable), [false]);
      expect(r.probes.single.httpCode, 500);
    });

    // 静态回退（`/api/version.json`）已删：服务端两台都没有那个路由，维护者 2026-10-07 确认
    // "故意没做"。留着它的唯一效果是让用户白等第二个 15 秒超时后仍然报同一个码 ——
    // 所以"只发一发"与"错误里带状态码"这两条现在是**行为契约**，钉在这里。
    test('404 ⇒ 只发一发（不再补第二发去拉不存在的静态端点），错误里带状态码', () async {
      final r = await runCheck((_) async => http.Response('Cannot GET', 404));
      expect(r.hosts, hasLength(1), reason: '第二发就是那条走不通的静态回退');
      expect(r.probes, hasLength(1));
      expect(r.probes.single.reachable, isFalse);
      expect(r.probes.single.httpCode, 404);
      expect(
        AppUpdateManager.instance.lastError,
        contains('404'),
        reason: '原来的措辞原样保留（用户看到的没变），只是不再白等第二发',
      );
    });

    test('两发都抛异常 ⇒ httpCode 为 null（"没回话"与"回了 500"不是一件事）', () async {
      final r = await runCheck(
        (_) async => throw http.ClientException('dns down'),
      );
      expect(r.probes, hasLength(1));
      expect(r.probes.single.reachable, isFalse);
      expect(r.probes.single.httpCode, isNull);
      expect(r.probes.single.latestVersion, isNull, reason: '没读到就不许编一个');
    });
  });

  group('主动探测（打开服务器选择页那一次）', () {
    test('用极低版本号问这一台，并读出它报的最新版与下发的 CDN 主机名', () async {
      final asked = <String, String>{};
      final probe = await AppUpdateManager.instance.probeUpdateServer(
        UpdateServerRegion.mainland,
        client: MockClient((request) async {
          asked['host'] = request.url.host;
          asked['version'] = request.url.queryParameters['version'] ?? '';
          asked['build'] = request.url.queryParameters['build'] ?? '';
          return json200();
        }),
      );
      expect(asked['host'], 'notice.fnthink.com');
      // 极低版本号 ⇒ 这台必然答"有更新"，于是同一发里能读到它报告的最新版与 CDN。
      expect(asked['version'], '0.0.0');
      expect(asked['build'], '0');
      expect(probe.reachable, isTrue);
      expect(probe.region, UpdateServerRegion.mainland);
      expect(probe.latestVersion, '1.9.9');
      expect(probe.downloadHost, 'cdn.fnthink.com');
    });

    test('403（CDN 拦）⇒ 不可达，状态码留着给用户看', () async {
      final probe = await AppUpdateManager.instance.probeUpdateServer(
        UpdateServerRegion.international,
        client: MockClient(
          (_) async =>
              http.Response('blocked', 403, headers: {'server': 'cloudflare'}),
        ),
      );
      expect(probe.reachable, isFalse);
      expect(probe.httpCode, 403);
    });

    test('探测不拨 24 小时那一档的时钟（不然真正的自动检查会被它挤掉一次）', () async {
      await AppUpdateManager.instance.probeUpdateServer(
        UpdateServerRegion.mainland,
        client: MockClient((_) async => json200()),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('last_update_check_time'), isNull);
    });
  });
}
