import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/services/fnthink_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/source_guards.dart';

/// 幻念推送的设备侧设置（T44 的数据层）。
///
/// 这一层最容易被写歪的两件事：**默认方向**与**校验的位置**。
///  ① 默认关：这台设备从没同意过"通知内容经服务器中转"。默认开着 = 替用户点了那个同意，
///     而"新功能不许悄悄做让用户意外的事"是路线图顶部四条不变量之一。
///  ② 读的时候也要校验：写入校验过不代表值一定合法 —— 备份恢复会把 prefs 里的值原样灌回来，
///     那时候不校验，后果是拼出一个怪 authority 然后一路 400，而没人会怀疑到设置上。
/// 服务地址的默认值来自契约，代码里不许出现任何真实域名（`feedback-public-docs-no-real-domains` 同理适用于源码）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final contract = FnthinkContract.readFile();
  final settings = FnthinkSettings(contract: contract);
  final defaultHost =
      (contract.raw['transport'] as Map<String, Object?>)['endpoints']
          as Map<String, Object?>;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('总开关', () {
    test('没写过 ⇒ 默认关（默认开等于替用户同意了"内容经服务器中转"）', () async {
      expect(await settings.receiveEnabled, isFalse);
    });

    test('开与关都存得住，且读回来是同一个值', () async {
      await settings.setReceiveEnabled(true);
      expect(await settings.receiveEnabled, isTrue);
      await settings.setReceiveEnabled(false);
      expect(await settings.receiveEnabled, isFalse);
    });
  });

  group('T197 片2：锁屏持续接收', () {
    test('没写过 ⇒ 默认开（维护者 2026-10-25 拍板）', () async {
      expect(await settings.screenKeepalive, isTrue);
    });

    test('关掉后读回来是关，且写的键名与原生读的是同一把', () async {
      await settings.setScreenKeepalive(false);
      expect(await settings.screenKeepalive, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(FnthinkSettings.keyScreenKeepalive),
        isFalse,
        reason: 'Dart 写的是裸键，SharedPreferences 自己加 flutter. 前缀',
      );
    });
  });

  group('服务地址', () {
    test('默认那台来自契约（代码里没有兜底域名）', () async {
      expect(await settings.host, defaultHost['default']);
      expect(settings.defaultHost, defaultHost['default']);
    });

    // ── T76 双地域：候选恒为契约声明的那两台 ──
    group('declaredHosts（T76 选哪台）', () {
      test('两台都在，且逐字等于契约里的值（代码里不许再抄一份域名）', () {
        final hosts = settings.declaredHosts;
        expect(hosts.map((h) => h.key).toList(), [
          'international',
          'mainland',
        ], reason: '顺序也钉住：界面按这个顺序摆两档');
        expect(hosts.map((h) => h.host).toList(), [
          defaultHost['international'],
          defaultHost['mainland'],
        ]);
      });

      test('两台不同：相同的话"切换"这一下就什么也没换', () {
        final hosts = settings.declaredHosts.map((h) => h.host).toSet();
        expect(hosts.length, 2, reason: '契约侧已经钉过这一条，这里是第二道（客户端视角）');
      });

      test('默认那台必须是两台之一（选档与默认值不许指向第三台）', () {
        expect(
          settings.declaredHosts.map((h) => h.host),
          contains(settings.defaultHost),
          reason: '默认值落在候选之外 ⇒ 界面摆两档而实际连的是第三台，用户改不动它',
        );
      });

      // ⚠ §6 定的口径：**候选恒是这两台，`.com` 没部署好也照样列出来**。
      //   这条是它的反面自检 —— 一旦有人加"探测通了才进候选"的过滤，下面那条会红。
      test('不按"能不能连上"过滤：这一层只看契约，不发任何请求', () async {
        // prefs 是空的、也没有任何网络桩：这一层若偷偷去探测，这里就会挂住或抛。
        final hosts = settings.declaredHosts;
        expect(hosts, hasLength(2));
        expect(await settings.host, defaultHost['default']);
      });
    });

    test('存进去归一成小写：同一台主机不许有两个写法被认成两台服务', () async {
      await settings.setHost('Push.Example.COM');
      expect(await settings.host, 'push.example.com');
    });

    test('端口允许（自部署常见 https://host:8443）', () async {
      await settings.setHost('push.example.com:8443');
      expect((await settings.baseUrl).port, 8443);
      expect((await settings.baseUrl).scheme, 'https');
    });

    test('四类坏值一律拒，并说清是哪一种（不是笼统"格式不对"）', () async {
      await expectLater(
        settings.setHost(''),
        throwsA(
          isA<FnthinkSettingsInvalid>().having(
            (e) => e.reason,
            'reason',
            contains('空的'),
          ),
        ),
      );
      await expectLater(
        settings.setHost('https://push.example.com'),
        throwsA(
          isA<FnthinkSettingsInvalid>().having(
            (e) => e.reason,
            'reason',
            contains('scheme'),
          ),
        ),
      );
      await expectLater(
        settings.setHost('push.example.com/api/fnthink'),
        throwsA(
          isA<FnthinkSettingsInvalid>().having(
            (e) => e.reason,
            'reason',
            contains('裸主机名'),
          ),
        ),
      );
      await expectLater(
        settings.setHost('push.example.com:abc'),
        throwsA(
          isA<FnthinkSettingsInvalid>().having(
            (e) => e.reason,
            'reason',
            contains('端口'),
          ),
        ),
      );
    });

    test('② 盘上已经是坏值时，读的时候也要抛（备份恢复灌回来的那条路）', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyHost}': 'not a host at all/',
      });
      await expectLater(settings.host, throwsA(isA<FnthinkSettingsInvalid>()));
      await expectLater(
        settings.baseUrl,
        throwsA(isA<FnthinkSettingsInvalid>()),
      );
    });

    test('baseUrl 只给 scheme + 主机：路径一个字符都不许写在这里', () async {
      final uri = await settings.baseUrl;
      expect(uri.scheme, 'https');
      expect(uri.path, '');
      expect(
        uri.toString(),
        isNot(contains('/api/')),
        reason: '路径的唯一出处是契约 transport.apiPaths',
      );
    });

    test('契约里没有 default ⇒ 抛（不拍一个域名当默认值）', () async {
      final copy = jsonDecode(jsonEncode(contract.raw)) as Map<String, Object?>;
      ((copy['transport'] as Map<String, Object?>)['endpoints']
              as Map<String, Object?>)
          .remove('default');
      final bare = FnthinkSettings(contract: FnthinkContract(copy));
      // 缺键与"值是空串"收成同一种失败：调用方（coordinator）只需要一种 catch，
      // 而"契约缺 default"这条会在 reason 里以"服务地址是空的"露出来 —— 那是可操作的。
      await expectLater(
        () => bare.defaultHost,
        throwsA(
          isA<FnthinkSettingsInvalid>().having(
            (e) => e.reason,
            'reason',
            contains('空的'),
          ),
        ),
      );
    });
  });

  group('源码守卫', () {
    test('本文件不出现任何真实域名（真值只在契约与内部手册里）', () {
      final src = stripComments(
        File('${projectRoot()}/lib/services/fnthink_settings.dart')
            .readAsStringSync(),
      );
      for (final needle in ['fnthink.top', 'fnthink.com', 'push.fnthink']) {
        expect(src, isNot(contains(needle)), reason: '设置层里出现了真实域名：$needle');
      }
    });
  });

  group('T47：收件保留档位', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('没选过 ⇒ 缺省 30 天（不把 default 写进盘）', () async {
      final settings = FnthinkSettings(contract: contract);
      expect(await settings.retentionDays(), 30);
      expect(
        (await SharedPreferences.getInstance()).getInt(
          FnthinkSettings.keyRetentionDays,
        ),
        isNull,
        reason: '缺省写进盘 = 哪天缺省调了，这台跟不上',
      );
    });

    test('选过 ⇒ 原样读回；盘上坏值 ⇒ 按缺省读（不当 0 执行）', () async {
      final settings = FnthinkSettings(contract: contract);
      await settings.setRetentionDays(90);
      expect(await settings.retentionDays(), 90);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(FnthinkSettings.keyRetentionDays, 13);
      expect(
        await settings.retentionDays(),
        30,
        reason: '坏值当 0 执行 = 清空收件表；按缺省读才是 fail-safe 的方向',
      );
    });

    test('档位表外的写入当场抛（不静默夹到邻档）', () async {
      final settings = FnthinkSettings(contract: contract);
      expect(
        () => settings.setRetentionDays(13),
        throwsA(isA<FnthinkSettingsInvalid>()),
      );
    });
  });
}
