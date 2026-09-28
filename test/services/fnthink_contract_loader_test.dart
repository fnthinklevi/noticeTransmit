import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';

import '../support/source_guards.dart';

/// 设备上那份协议契约怎么来（随包资源）。
///
/// 这一层最容易犯的错不是"读错了"，而是**读不到却继续跑**：契约里全是数字与词表
/// （间隔、额度、状态码、正文删留时机），一旦拿不到就"先用默认值顶着"，表现是
/// 两端各算一份事实 —— 而这类分歧从来不报错，只表现为"设备以为排队 7 天、服务端第 3 天就删了"。
/// 所以这个文件钉的是：① 只有 asset 那一个来源；② 四类失败（读不到 / 不是 JSON /
/// 顶层形状不对 / 这一包解释不了或表不自洽）**一律抛同一种异常**；③ 不自洽时
/// 只点名条数与第一条，不把整张表抄进日志（日志会离开这台机）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final realContractText = File(fnthinkContractFile()).readAsStringSync();

  /// 改坏一份契约的文本（用真契约当底，这样"改一处"是唯一的变量）。
  String mutate(void Function(Map<String, Object?> raw) change) {
    final copy = jsonDecode(realContractText) as Map<String, Object?>;
    change(copy);
    return jsonEncode(copy);
  }

  group('正向：读得到就用它', () {
    test('仓库那份契约经 asset 通道读得出来，取数与 validate 都可用', () async {
      final shim = _BundleShim(realContractText);
      final contract = await FnthinkContractLoader(readAsset: shim.load).load();
      expect(shim.keys, [fnthinkContractAssetKey]);
      expect(contract.validate(), isEmpty, reason: '真契约必须自洽，否则本文件其余用例都在测空气');
      expect(contract.apiPath('poll'), '/api/fnthink/poll');
      expect(contract.pollIntervalSeconds, greaterThan(0));
    });

    test('读过一次就不再读第二次；refresh 才重读', () async {
      final shim = _BundleShim(realContractText);
      final loader = FnthinkContractLoader(readAsset: shim.load);
      final first = await loader.load();
      final second = await loader.load();
      expect(identical(first, second), isTrue);
      expect(shim.calls, 1);
      await loader.load(refresh: true);
      expect(shim.calls, 2);
      expect(loader.cached, isNotNull);
      loader.clear();
      expect(loader.cached, isNull);
    });
  });

  group('四类失败一律同一种异常', () {
    test('asset 读不到 ⇒ 抛，且点名那个键（少了 pubspec 那行就是这一类）', () async {
      final loader = FnthinkContractLoader(
        readAsset: _BundleShim(null, throws: true).load,
      );
      await expectLater(
        loader.load(),
        throwsA(
          isA<FnthinkContractUnavailable>().having(
            (e) => e.reason,
            'reason',
            contains(fnthinkContractAssetKey),
          ),
        ),
      );
    });

    test('不是合法 JSON ⇒ 抛', () async {
      final loader = FnthinkContractLoader(
        readAsset: _BundleShim('{ "protocol": ').load,
      );
      await expectLater(
        loader.load(),
        throwsA(
          isA<FnthinkContractUnavailable>().having(
            (e) => e.reason,
            'reason',
            contains('JSON'),
          ),
        ),
      );
    });

    test('合法 JSON 但顶层不是对象 ⇒ 同一种异常（不是让 TypeError 冒出去）', () async {
      final loader = FnthinkContractLoader(readAsset: _BundleShim('[]').load);
      await expectLater(
        loader.load(),
        throwsA(
          isA<FnthinkContractUnavailable>().having(
            (e) => e.reason,
            'reason',
            contains('顶层形状'),
          ),
        ),
      );
    });

    test('契约是 v99 而这一包只实现到 v1 ⇒ 抛（不"按已知的键凑合读"）', () async {
      final loader = FnthinkContractLoader(
        readAsset: _BundleShim(
          mutate((raw) {
            // 协议名与 contractVersion 要**一起**升上去：那样它是一份自洽的 v99 契约，
            // 被拦下的原因才是"这一包只实现到 v1"。只改一个数会先撞上"名与数不一致"，
            // 那条虽然也该抛，测的却不是版本闸门。
            raw['protocol'] = 'fnthink-v99';
            raw['contractVersion'] = 99;
          }),
        ).load,
      );
      await expectLater(
        loader.load(),
        throwsA(
          isA<FnthinkContractUnavailable>().having(
            (e) => e.reason,
            'reason',
            // 两条一起断才抓得住"版本闸门被摘掉"：摘掉之后 validate 那条重叠的守卫仍然抛，
            // 但报的是笼统的"契约表不自洽"。可操作的句子（本包只实现到 v1）才是这一闸的产物。
            allOf(contains('只实现到 v1'), isNot(contains('不自洽'))),
          ),
        ),
      );
    });

    test('表不自洽 ⇒ 抛，并报出条数', () async {
      final loader = FnthinkContractLoader(
        readAsset: _BundleShim(
          mutate(
            (raw) =>
                (raw['capabilities']
                        as Map<String, Object?>)['endpointMaxLevel'] =
                    'L3',
          ),
        ).load,
      );
      await expectLater(
        loader.load(),
        throwsA(
          isA<FnthinkContractUnavailable>().having(
            (e) => e.reason,
            'reason',
            allOf(contains('不自洽'), contains('endpointMaxLevel')),
          ),
        ),
      );
    });

    test('不自洽不止一条时只点名第一条（日志会离开这台机）', () async {
      final broken = mutate((raw) {
        (raw['capabilities'] as Map<String, Object?>)['endpointMaxLevel'] =
            'L3';
        (raw['retention'] as Map<String, Object?>)['bodyAtRest'] = {
          'algorithm': 'none',
        };
      });
      // 条数从 validate 自己数出来：改坏两处**触发**几条判据是那张表的事，不是这里拍的。
      final expected = FnthinkContract.parse(broken).validate().length;
      expect(expected, greaterThan(1), reason: '锚点：得真的不止一条，否则这条用例在测空气');
      final loader = FnthinkContractLoader(readAsset: _BundleShim(broken).load);
      try {
        await loader.load();
        fail('本该抛');
      } on FnthinkContractUnavailable catch (e) {
        expect(e.reason, contains('$expected 条'));
        expect(e.reason, contains('第一条：'));
        // 只许贴一条：整张表进日志就是把协议数字与状态码全部抄写一份出去。
        expect(e.reason.length, lessThan(400), reason: e.reason);
      }
    });
  });

  group('来源只有一个（跨文件守卫）', () {
    test('pubspec 的 assets 里真的有这个键', () {
      final pubspec = stripComments(
        File('${projectRoot()}/pubspec.yaml').readAsStringSync(),
      );
      expect(
        pubspec,
        contains('- $fnthinkContractAssetKey'),
        reason: '少这一行 = 桌面测试全绿、设备上 Unable to load asset',
      );
    });

    test('App 侧只有这一处契约读法（不许再出现 readFile / 手拼路径）', () {
      final src = stripComments(
        File(
          '${projectRoot()}/lib/services/fnthink_contract_loader.dart',
        ).readAsStringSync(),
      );
      expect(
        RegExp(r"protocol/fnthink-v1\.json").allMatches(src).length,
        1,
        reason: '那个路径字面量只许出现在常量定义处一次',
      );
      expect(src, isNot(contains('FnthinkContract.readFile')));
    });

    test('lib/ 里除了这个文件没人自己读契约', () {
      final hits = Directory('${projectRoot()}/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('.dart') &&
                // 必须剥注释：那个 loader 文件里的注释正是在解释"为什么不许用 readFile"，
                // 不剥就会把说明读成调用（这条纪律在别的源码守卫上已经咬过几次）。
                stripComments(
                  f.readAsStringSync(),
                ).contains('FnthinkContract.readFile'),
          )
          .toList();
      expect(
        hits.map((f) => f.path.replaceAll(r'\', '/')),
        isEmpty,
        reason: 'readFile 按"向上找仓库根"定位，设备沙箱里没有仓库根 —— 那条路只能到测试里用',
      );
    });
  });
}

/// 记次数的假 asset bundle（`readAsset` 的替身）。
class _BundleShim {
  _BundleShim(this.text, {this.throws = false});
  final String? text;
  final bool throws;
  int calls = 0;
  final List<String> keys = [];

  Future<String> load(String key) async {
    calls++;
    keys.add(key);
    if (throws) throw Error.safeToString('asset not found: $key');
    return text!;
  }
}
