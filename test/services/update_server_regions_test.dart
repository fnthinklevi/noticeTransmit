import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/update_server_regions.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T95 片1：更新服务器两档地址表 + 选择偏好。
///
/// 三条判据分别对应三件不同的事，别混成"表对不对"：
/// ①两档之间只差后缀（维护者那句「除了后缀和cdn外其余链接完全一致」）；
/// ②同一个事实在两处代码里各有一份（App 的档位表 / 官网的双域名映射）⇒ 逐字交叉核对；
/// ③偏好的解析与落盘行为（含"认不出来不许猜"）。
void main() {
  /// 官网那份映射（`server/public/index.html`）里的三处字面串。
  ///
  /// ⚠ 抽不出来必须红：整份 index.html 被重写、或那两个三元换了写法，
  /// 都会让"交叉核对"退化成一条谁都不比的空断言 —— 而它绿着的样子和真有牙一模一样。
  ({String com, String top})? pairFromSite(RegExp pattern, String where) {
    final src = File('server/public/index.html').readAsStringSync();
    final m = pattern.firstMatch(src);
    if (m == null) {
      throw StateError(
        '官网那份双域名映射里认不出「$where」的形状：'
        'index.html 改了写法 ⇒ 本文件的交叉核对失效，必须同步（不是放宽）',
      );
    }
    return (com: m.group(1)!, top: m.group(2)!);
  }

  group('档位表自身的形状', () {
    test('两档的 API 主机名只差后缀，前三段里除 TLD 外逐字一致', () {
      final a = UpdateServerRegion.mainland.apiHost.split('.');
      final b = UpdateServerRegion.international.apiHost.split('.');
      expect(a.length, 3, reason: 'notice.fnthink.<TLD> 的形状变了：这条判据要重读，不是改数');
      expect(b.length, 3);
      expect(a.sublist(0, 2), b.sublist(0, 2), reason: '主机名前两段必须同一条链路上的同一个名字');
      expect(a.last, 'com');
      expect(b.last, 'top');
    });

    test('CDN 那一维：.com 配 cdn、.top 配 cdn2（维护者原话里的另一处差异）', () {
      final a = UpdateServerRegion.mainland.cdnHost.split('.');
      final b = UpdateServerRegion.international.cdnHost.split('.');
      expect(a.length, 3);
      expect(b.length, 3);
      expect(a[1], 'fnthink');
      expect(b[1], 'fnthink');
      expect(a[0], 'cdn', reason: '大陆那档的 CDN 标签必须是 cdn，不是 cdn2');
      expect(b[0], 'cdn2');
      expect(a.last, 'com');
      expect(b.last, 'top');
    });

    test('apiBase 只加 scheme、路径为空；scheme 只有一份', () {
      for (final region in UpdateServerRegion.ordered) {
        final uri = Uri.parse(region.apiBase);
        expect(uri.scheme, 'https');
        expect(uri.host, region.apiHost);
        expect(uri.path, isEmpty, reason: '版本 API 的路径由调用方拼，档位表里不许埋一段路径');
      }
      expect(UpdateServerRegion.ordered.toSet().length, 2);
    });

    test('兜底那一档 = 本改动之前代码里唯一的那台（.top）', () {
      // 这一条是"改动的影响面"：默认档一旦翻到 .com，两台里没部署好的那台
      // 就会在探测失败时接住所有用户。今天的行为是 .top，兜底必须是它。
      expect(
        UpdateServerRegion.defaultRegion,
        UpdateServerRegion.international,
      );
      expect(UpdateServerRegion.defaultRegion.apiHost, 'notice.fnthink.top');
    });
  });

  group('与官网那份双域名映射交叉核对', () {
    test('notice 那一对：站点按 _isCom 选的两个主机名 == 档位表的两个 apiHost', () {
      final pair = pairFromSite(
        RegExp(
          r"""\(_isCom\s*\?\s*'([A-Za-z0-9.\-]+)'\s*:\s*'([A-Za-z0-9.\-]+)'\)\s*\+\s*'/api/version""",
        ),
        'notice 站点域回退源',
      );
      expect(pair!.com, UpdateServerRegion.mainland.apiHost);
      expect(pair.top, UpdateServerRegion.international.apiHost);
    });

    test('CDN 那一对：站点的 _cdn 三元 == 档位表的两个 cdnHost', () {
      final pair = pairFromSite(
        RegExp(
          r"""_cdn\s*=\s*_isCom\s*\?\s*'([A-Za-z0-9.\-]+)'\s*:\s*'([A-Za-z0-9.\-]+)'""",
        ),
        'CDN 主机名映射',
      );
      expect(pair!.com, UpdateServerRegion.mainland.cdnHost);
      expect(pair.top, UpdateServerRegion.international.cdnHost);
    });

    test('_fixCdn 只认这两个 CDN 主机名 ⇒ 客户端换档时不会换出一个它不认的地址', () {
      final pair = pairFromSite(
        RegExp(
          r"""url\.hostname\s*===\s*'([A-Za-z0-9.\-]+)'\s*\|\|\s*url\.hostname\s*===\s*'([A-Za-z0-9.\-]+)'""",
        ),
        '_fixCdn 的白名单',
      );
      expect(
        {pair!.com, pair.top},
        {
          UpdateServerRegion.mainland.cdnHost,
          UpdateServerRegion.international.cdnHost,
        },
        reason:
            '站点只换它认得的那两个主机名；档位表若添第三档而站点没跟上，'
            '换档后的下载地址会带着另一档的 CDN 名出去',
      );
    });
  });

  group('偏好解析与落盘', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('空偏好 = 自动 + 没测过，用的是默认那一档', () async {
      final s = await UpdateServerSettings.load();
      expect(s.isAuto, isTrue);
      expect(s.autoUnprobed, isTrue, reason: '"没测过"必须能问出来：否则界面会把兜底演成结论');
      expect(s.region, UpdateServerRegion.defaultRegion);
    });

    test('钉住大陆 ⇒ 用大陆；切回自动 ⇒ 回到上一次实测那档，而不是退回默认', () async {
      var s = await UpdateServerSettings.load();
      await s.recordAutoProbe(UpdateServerRegion.mainland);
      s = await UpdateServerSettings.load();
      expect(s.region, UpdateServerRegion.mainland, reason: '自动档要跟最近一次实测走');

      await s.setManual(UpdateServerRegion.international);
      s = await UpdateServerSettings.load();
      expect(s.region, UpdateServerRegion.international);
      expect(s.isAuto, isFalse);

      await s.setAuto();
      s = await UpdateServerSettings.load();
      expect(s.region, UpdateServerRegion.mainland, reason: '钉过哪台不该把实测结果抹掉');
    });

    test('recordAutoProbe 不改方式：停在手动时它只是一份记录', () async {
      var s = await UpdateServerSettings.load();
      await s.setManual(UpdateServerRegion.international);
      await s.recordAutoProbe(UpdateServerRegion.mainland);
      s = await UpdateServerSettings.load();
      expect(s.mode, UpdateServerMode.manual);
      expect(s.region, UpdateServerRegion.international);
      expect(s.autoRegion, UpdateServerRegion.mainland);
    });

    test('存了认不出来的值 = 当成没这个键，不猜档', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        UpdateServerSettings.keyMode: 'both',
        UpdateServerSettings.keyManualRegion: 'mars',
        UpdateServerSettings.keyAutoRegion: 'MAINLAND',
      });
      final s = await UpdateServerSettings.load();
      expect(s.mode, UpdateServerMode.auto, reason: '认不出来的方式回自动（= 没选过）');
      expect(s.manualRegion, isNull);
      // 档位名大小写不敏感（与 fnthink host 归一小写同一条理由：DNS 不分大小写，
      // 而 'MAINLAND' 与 'mainland' 存成两份会被当成两档）。
      expect(s.autoRegion, UpdateServerRegion.mainland);
    });

    test('resolveUpdateRegion：手动但钉不住时回兜底，不回自动档', () {
      expect(
        resolveUpdateRegion(
          mode: UpdateServerMode.manual,
          manualRegion: null,
          autoRegion: UpdateServerRegion.mainland,
        ),
        UpdateServerRegion.defaultRegion,
        reason: '用户说过"我要这台"却没落成 ⇒ 这是配置坏了，不能拿另一台的实测结果顶上去了',
      );
    });
  });

  group('自动档的选法（两台都探过才比）', () {
    UpdateServerProbe probe(
      UpdateServerRegion region, {
      required bool ok,
      int ms = 0,
    }) => UpdateServerProbe(region: region, reachable: ok, latencyMs: ms);

    test('两台都可达 ⇒ 取更快那台，而不是列表里排前面那台', () {
      expect(
        pickAutoRegion({
          UpdateServerRegion.mainland: probe(
            UpdateServerRegion.mainland,
            ok: true,
            ms: 800,
          ),
          UpdateServerRegion.international: probe(
            UpdateServerRegion.international,
            ok: true,
            ms: 120,
          ),
        }),
        UpdateServerRegion.international,
      );
    });

    test('只有一台可达 ⇒ 就是它，哪怕它更慢（不可达那台的时延不参与比较）', () {
      expect(
        pickAutoRegion({
          UpdateServerRegion.mainland: probe(
            UpdateServerRegion.mainland,
            ok: true,
            ms: 1500,
          ),
          UpdateServerRegion.international: probe(
            UpdateServerRegion.international,
            ok: false,
            ms: 5,
          ),
        }),
        UpdateServerRegion.mainland,
      );
    });

    test('都没探通 ⇒ null（不是默认那一台："没测出来"必须能被问出来）', () {
      expect(
        pickAutoRegion({
          UpdateServerRegion.mainland: probe(
            UpdateServerRegion.mainland,
            ok: false,
          ),
          UpdateServerRegion.international: probe(
            UpdateServerRegion.international,
            ok: false,
          ),
        }),
        isNull,
      );
      expect(
        pickAutoRegion(const {}),
        isNull,
        reason: '一台都没探过 ⇒ 没有结论，不能替用户挑一台看起来像结论的',
      );
    });

    test('时延相同 ⇒ 按摆列顺序（大陆在前），不让同一台设备两次开机落到不同档', () {
      expect(
        pickAutoRegion({
          UpdateServerRegion.international: probe(
            UpdateServerRegion.international,
            ok: true,
            ms: 100,
          ),
          UpdateServerRegion.mainland: probe(
            UpdateServerRegion.mainland,
            ok: true,
            ms: 100,
          ),
        }),
        UpdateServerRegion.mainland,
      );
    });
  });
}
