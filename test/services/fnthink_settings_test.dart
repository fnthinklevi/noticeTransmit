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

  group('服务地址', () {
    test('默认那台来自契约（代码里没有兜底域名）', () async {
      expect(await settings.host, defaultHost['default']);
      expect(settings.defaultHost, defaultHost['default']);
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
        File(
          '${projectRoot()}/lib/services/fnthink_settings.dart',
        ).readAsStringSync(),
      );
      for (final needle in ['fnthink.top', 'fnthink.com', 'push.fnthink']) {
        expect(src, isNot(contains(needle)), reason: '设置层里出现了真实域名：$needle');
      }
    });
  });
}
