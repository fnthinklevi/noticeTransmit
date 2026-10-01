import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';
import 'package:notice_transmit/services/fnthink_pair_link.dart';

import '../test_setup.dart';

/// #176 片4：点开的那条配对链接，Dart 侧读点判的是什么。
///
/// 这一层看着只是"把原生那串取回来交给包层解析"，但它压着三条会静默失真的判据：
///  ① **null 与"判不过"是两件事** —— 前者是"没人点过链接"（每次打开 App 都会跑这一发，
///     于是导航一次都不该做），后者是"点了但这台用不上"（必须说一句）。把它们合成都说谎；
///  ② **判据只有包层那一份** —— 这里不自己拆 query、不自己比版本；写一份出来就是第二个作者，
///     而两份判据可以朝同一个方向写错（那时两侧编译与测试仍然全绿）；
///  ③ **take 只有一个出口** —— 读一次就清，所以同一条链接不可能被两个读者各弹一次输入层，
///     而那枚口令按契约是 `singleUse` 的。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final contract = FnthinkContract.readFile();
  late List<String> taken;

  /// 假原生：`takeFnthinkPairLink` 每次回 `queue` 里的下一项（取走即清的形状）。
  /// 队列空了回 null —— 那就是"没有待处理的链接"。
  FnthinkPairLinkReader readerWith({
    List<String?> queue = const [],
    bool contractOk = true,
  }) {
    var index = 0;
    stubNativeChannels(
      onCall: (call) async {
        if (call.method != 'takeFnthinkPairLink') return null;
        taken.add(call.method);
        final value = index < queue.length ? queue[index] : null;
        index++;
        return value;
      },
    );
    return FnthinkPairLinkReader(
      contracts: FnthinkContractLoader(
        readAsset: (_) async {
          if (!contractOk) return '{ 这不是合法 JSON';
          return File('protocol/fnthink-v1.json').readAsStringSync();
        },
      ),
    );
  }

  /// 对端那台：地址码与口令都由包层按契约生成（长度/字母表都是契约说了算）。
  /// 手打一串 20 个 A 会被 `FnthinkAddressCode.parse` 拒掉（今日长度是 18），
  /// 那种红看着像"解析写错了"，其实是测试自己写的载荷不成形。
  final otherDevice = FnthinkAddressCode.generate(contract).value;
  final armedCode = FnthinkPairingCode.generate(contract).value;

  String link({
    String? address,
    String? code,
    String level = 'L1',
    int? version,
  }) {
    return FnthinkPairingRequest(
      addressCode: address ?? otherDevice,
      pairingCode: code ?? armedCode,
      level: level,
      contractVersion: version ?? contract.contractVersion,
    ).qrText(contract);
  }

  setUp(() => taken = <String>[]);
  tearDown(clearNativeChannelStubs);

  group('读那条配对链接（#176 片4）', () {
    test('原生回 null ⇒ 回 null（"没人点过链接"，与"点了但用不上"是两件事）', () async {
      final reader = readerWith();
      expect(await reader.take(), isNull);
    });

    test('空串同样按"没有链接"处理', () async {
      final reader = readerWith(queue: ['']);
      expect(await reader.take(), isNull);
    });

    test('合法的那一条 ⇒ 判过，三项都带上（地址码 / 口令 / 档位）', () async {
      final reader = readerWith(queue: [link()]);
      final outcome = await reader.take();
      expect(outcome, isNotNull);
      expect(outcome!.accepted, isTrue);
      expect(outcome.request!.addressCode, otherDevice);
      expect(outcome.request!.pairingCode, armedCode);
      expect(outcome.request!.level, 'L1');
      expect(outcome.reason, isNull);
    });

    test('只读一次：第二次 take 拿到的是"没有链接"', () async {
      final reader = readerWith(queue: [link(), null]);
      expect((await reader.take())!.accepted, isTrue);
      expect(
        await reader.take(),
        isNull,
        reason: '原生那本账是"取走即清"的：同一个链接被读第二次就是弹两次输入层',
      );
      expect(taken, hasLength(2), reason: '两次都真的走了一次通道（不是本地缓存了那一份）');
    });

    test('通道没接（MissingPluginException）⇒ null，不往上抛', () async {
      stubNativeChannels(
        onCall: (call) async => throw MissingPluginException('没接'),
      );
      final reader = FnthinkPairLinkReader(
        contracts: FnthinkContractLoader(
          readAsset: (_) async =>
              File('protocol/fnthink-v1.json').readAsStringSync(),
        ),
      );
      expect(
        await reader.take(),
        isNull,
        reason: '取链接不是必须发生的动作；抛上去会让首页启动那一串跟着失败',
      );
    });

    test('载荷少一项 ⇒ 判不过（不是"能读多少算多少"）', () async {
      final reader = readerWith(
        queue: ['${contract.pairingQrPrefix}?v=1&to=$otherDevice'],
      );
      final outcome = await reader.take();
      expect(outcome, isNotNull, reason: '点了链接但判不过 ⇒ 有 outcome（要界面说一句）');
      expect(outcome!.accepted, isFalse);
      expect(outcome.request, isNull);
    });

    test('多带一个未知字段 ⇒ 判不过（配对载荷上的"容错"就是往身份交换里塞料的口子）', () async {
      final reader = readerWith(queue: ['${link()}&extra=1']);
      expect((await reader.take())!.accepted, isFalse);
    });

    test('版本对不上 ⇒ 判不过（拒，不是降到能读的那一半）', () async {
      final reader = readerWith(
        queue: [link(version: contract.contractVersion + 1)],
      );
      expect((await reader.take())!.accepted, isFalse);
    });

    test('契约读不到 ⇒ 判不过而不是"没有链接"', () async {
      final reader = readerWith(queue: [link()], contractOk: false);
      final outcome = await reader.take();
      expect(outcome, isNotNull, reason: '"这台现在没法判这条链接"与"没人点过链接"必须分得开');
      expect(outcome!.accepted, isFalse);
      expect(outcome.reason, contains('contract-unavailable'));
    });

    test('原因只带在 outcome 里，不进任何用户可见文案', () async {
      final reader = readerWith(
        queue: ['${contract.pairingQrPrefix}?v=99&to=X'],
      );
      final outcome = await reader.take();
      // 这一条钉的是**这一层的职责边界**：把 `unknown:` / `version:` 这类词原样贴到界面上，
      // 就等于让一台设备的屏幕开始教人哪种写法能被接受 —— 那是枚举器的形状。
      expect(outcome!.accepted, isFalse);
      expect(outcome.request, isNull);
    });
  });
}
