import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/services/fnthink_endpoint_probe.dart';
import 'package:notice_transmit/services/fnthink_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T76 ⓑ 首启选路：**只在"从没选过"时**按实测时延就近选一次，选完落盘；
/// 之后无论探测结果怎么变、用户按没按过，都不再自动改（T76 §6 ⑤）。
///
/// 这里钉三件，缺一件都会静默失效：
///  ① **判据是"测到的那些里最快的"**，不是"第一个能连上的"、也不是"表里的第一个"；
///  ② **有偏好就一个字节都不许自动改**（哪怕探测说另一台快得多）——这是 ⑤ 那条；
///  ③ **探测失败要落一个确定的默认**，不是"这次不选、下次再说"——
///     后者会让同一台设备两次冷启动连到不同的服务器，而用户什么都没按。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final contract = FnthinkContract.readFile();
  final settings = FnthinkSettings(contract: contract);
  final intl = (contract.raw['transport'] as Map<String, Object?>)['endpoints']
      as Map<String, Object?>;
  final top = intl['international'] as String;
  final com = intl['mainland'] as String;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('就近裁决（纯函数）', () {
    test('测到的里面挑最快的', () {
      expect(
        nearestHost(
          {top: const Duration(milliseconds: 180), com: const Duration(milliseconds: 40)},
          preferredOrder: [top, com],
        ),
        com,
      );
      expect(
        nearestHost(
          {top: const Duration(milliseconds: 40), com: const Duration(milliseconds: 180)},
          preferredOrder: [top, com],
        ),
        top,
      );
    });

    test('只有一台测到 ⇒ 就是它（不因为"另一台更快"而选一个连不上的）', () {
      expect(
        nearestHost({com: const Duration(milliseconds: 900)}, preferredOrder: [top, com]),
        com,
      );
    });

    test('两边一模一样快 ⇒ 归契约声明顺序里靠前的那台（结果必须确定）', () {
      final tie = {top: const Duration(milliseconds: 50), com: const Duration(milliseconds: 50)};
      expect(nearestHost(tie, preferredOrder: [top, com]), top);
      expect(nearestHost(tie, preferredOrder: [com, top]), com);
    });

    test('一台都测不到 ⇒ null（由调用方落契约 default，不在这里编一个）', () {
      expect(nearestHost(const {}, preferredOrder: [top, com]), isNull);
    });
  });

  group('首启选路（写盘 + 只动一次）', () {
    test('从没选过 ⇒ 按实测选，并把结果写进偏好（之后不再选）', () async {
      var probes = 0;
      final picked = await settings.ensureFirstRunHost(
        latencyProbe: (hosts) async {
          probes++;
          expect(hosts, [top, com], reason: '探的就是契约声明的那两台，顺序也是声明顺序');
          return {top: const Duration(milliseconds: 200), com: const Duration(milliseconds: 30)};
        },
      );
      expect(picked, com);
      expect(await settings.host, com, reason: '选完必须落盘，否则每次冷启动都重猜一次');

      // 第二次：即便探测说另一台快得多，也不许改（§6 ⑤）
      final again = await settings.ensureFirstRunHost(
        latencyProbe: (_) async => {top: const Duration(milliseconds: 5), com: const Duration(seconds: 9)},
      );
      expect(again, com);
      expect(probes, 1, reason: '有偏好之后连探都不该探 —— 探了就是"随时准备改"的形状');
    });

    test('用户手动选过 ⇒ 自动选路连探都不探（T76 ⑤）', () async {
      await settings.setHost(top);
      var probes = 0;
      final kept = await settings.ensureFirstRunHost(
        latencyProbe: (_) async {
          probes++;
          return {com: const Duration(milliseconds: 1)};
        },
      );
      expect(kept, top);
      expect(probes, 0, reason: '用户按过的那一下就是偏好；再探就是准备偷偷改它');
    });

    test('两台都测不到 ⇒ 落契约 default 且同样写进偏好（确定 > 每次重猜）', () async {
      final picked = await settings.ensureFirstRunHost(
        latencyProbe: (_) async => const {},
      );
      expect(picked, settings.defaultHost);
      expect(await settings.host, settings.defaultHost);
    });

    test('坏值已在盘上（备份恢复灌回来的）⇒ 读它并判非法，而不是拿探测覆盖掉', () async {
      // 这一条是"读的时候也校验"那条纪律在选路上的形状：不校验的话，
      // 坏值会被自动选路悄悄换成"探测结果"，用户看到的是"我设的地址自己变了"。
      SharedPreferences.setMockInitialValues({FnthinkSettings.keyHost: 'not a host'});
      var probed = false;
      await expectLater(
        settings.ensureFirstRunHost(
          latencyProbe: (_) async {
            probed = true;
            return const {};
          },
        ),
        throwsA(isA<FnthinkSettingsInvalid>()),
      );
      expect(probed, isFalse, reason: '坏值要先被读出来判非法，不许先探再覆盖');
    });
  });
}
