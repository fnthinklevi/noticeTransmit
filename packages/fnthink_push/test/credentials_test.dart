import 'dart:convert';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:test/test.dart';

/// 凭证两件套与签名规范化字节（T26 的第一片：纯 Dart，不碰原生）。
void main() {
  final contract = FnthinkContract.readFile();

  Map<String, Object?> mutate(void Function(Map<String, Object?> raw) change) {
    final copy = jsonDecode(jsonEncode(contract.raw)) as Map<String, Object?>;
    change(copy);
    return copy;
  }

  group('长度与字母表都来自契约', () {
    test('地址码 18 位、配对口令 20 位，都是读契约读出来的', () {
      expect(contract.identityLength('addressCode'), 18);
      expect(contract.identityLength('pairingCode'), 20);
      expect(
        FnthinkAddressCode.generate(contract).value.length,
        contract.identityLength('addressCode'),
      );
      expect(
        FnthinkPairingCode.generate(contract).value.length,
        contract.identityLength('pairingCode'),
      );
    });

    test('契约改位数 ⇒ 生成跟着改（证明代码里没有第二份 18）', () {
      final twelve = FnthinkContract(
        mutate((raw) {
          ((raw['identity'] as Map)['addressCode'] as Map)['length'] = 12;
        }),
      );
      expect(FnthinkAddressCode.generate(twelve).value.length, 12);
    });

    test('契约缺位数就抛，不补一个"默认 18"', () {
      final broken = FnthinkContract(
        mutate((raw) {
          ((raw['identity'] as Map)['addressCode'] as Map).remove('length');
        }),
      );
      expect(
        () => FnthinkAddressCode.generate(broken),
        throwsA(isA<StateError>()),
        reason: '补默认位数会静默生成对端不认的凭证',
      );
    });

    test('2000 次生成只出 Crockford 字母表，永不含 I L O U', () {
      for (var i = 0; i < 2000; i++) {
        for (final char in FnthinkAddressCode.generate(
          contract,
        ).value.split('')) {
          expect(
            CrockfordBase32.standardAlphabet.contains(char),
            isTrue,
            reason: '生成了字母表外的字符 $char',
          );
          expect(
            CrockfordBase32.standardExcluded.contains(char),
            isFalse,
            reason: '$char 属于易混排除集',
          );
        }
      }
    });

    test('排除集或字母表与实现不符 ⇒ 拒绝工作，不照自己的表继续生成', () {
      final wrongExcluded = FnthinkContract(
        mutate((raw) {
          ((raw['identity'] as Map)['addressCode'] as Map)['excludedChars'] =
              'ABC';
        }),
      );
      expect(
        () => FnthinkAddressCode.generate(wrongExcluded),
        throwsA(isA<ArgumentError>()),
      );
      final wrongAlphabet = FnthinkContract(
        mutate((raw) {
          ((raw['identity'] as Map)['addressCode'] as Map)['alphabet'] =
              'base64url';
        }),
      );
      expect(
        () => FnthinkAddressCode.generate(wrongAlphabet),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('解析与显示', () {
    test('大小写、空格、连字符都归一化成同一个值', () {
      final code = FnthinkAddressCode.generate(contract);
      expect(
        FnthinkAddressCode.parse(contract, code.value.toLowerCase()),
        code,
      );
      expect(
        FnthinkAddressCode.parse(contract, code.value.split('').join(' ')),
        code,
      );
      final dashed = '${code.value.substring(0, 6)}-${code.value.substring(6)}';
      expect(FnthinkAddressCode.parse(contract, dashed), code);
    });

    test('长度不对或含表外字符 ⇒ null（不抛，也不"尽力解释"）', () {
      expect(FnthinkAddressCode.parse(contract, 'ABC'), isNull);
      final code = FnthinkAddressCode.generate(contract);
      final withU = '${code.value.substring(0, code.value.length - 1)}U';
      expect(
        FnthinkAddressCode.parse(contract, withU),
        isNull,
        reason: 'U 被 Crockford 排除：把它当合法字符会把打错的输入当成一枚新码',
      );
    });

    test('显示分组：地址码 6 位一段、口令 5 位一段，去分隔符后回到原值', () {
      final code = FnthinkAddressCode.generate(contract);
      expect(code.formatted.replaceAll('-', ''), code.value);
      expect(code.formatted.split('-').map((p) => p.length), everyElement(6));
      final pairing = FnthinkPairingCode.generate(contract);
      expect(pairing.formatted.replaceAll('-', ''), pairing.value);
      expect(
        pairing.formatted.split('-').map((p) => p.length),
        everyElement(5),
      );
    });

    test('两次生成不相同（CSPRNG；碰撞概率低到不需要处理）', () {
      final a = FnthinkAddressCode.generate(contract);
      final b = FnthinkAddressCode.generate(contract);
      expect(a, isNot(b));
    });

    test('配对口令的有效期与一次性从契约带出来', () {
      final pairing = FnthinkPairingCode.generate(contract);
      expect(pairing.ttlSeconds, 300);
      expect(pairing.singleUse, isTrue);
    });
  });

  group('签名规范化字节（顺序与分隔符本身就是协议）', () {
    Map<String, Object?> fields() => const {
      'version': '1',
      'type': 'message',
      'target': '0A1B2C3D4E5F6G7H8J',
      'ts': 1770000000,
      'nonce': '7Q9M3K',
      'body': '服务器磁盘剩余 8%',
    };

    test('按契约顺序拼接、用契约分隔符分隔、utf8 编码', () {
      // 断言方式：把字节解回来按分隔符切开，逐段对照契约顺序。
      // 不在测试里重抄一遍 join(顺序, 分隔符) —— 那等于把规则抄成第二份，
      // 两边一起改错时测试还会绿。
      final decoded = utf8.decode(CanonicalMessage.bytes(contract, fields()));
      final parts = decoded.split(contract.signatureSeparator);
      expect(parts.length, contract.canonicalOrder.length);
      expect(
        parts,
        contract.canonicalOrder.map((k) => '${fields()[k]}').toList(),
      );
      expect(utf8.decode(utf8.encode('服务器磁盘剩余 8%')), '服务器磁盘剩余 8%');
    });

    test('换顺序就是换签名：契约改序 ⇒ 字节必变', () {
      final swapped = FnthinkContract(
        mutate((raw) {
          final order = List<String>.from(
            (raw['signature'] as Map)['canonicalOrder'] as List,
          );
          order.setAll(0, [order[1], order[0], ...order.skip(2)]);
          (raw['signature'] as Map)['canonicalOrder'] = order;
        }),
      );
      expect(
        CanonicalMessage.bytes(swapped, fields()),
        isNot(CanonicalMessage.bytes(contract, fields())),
      );
    });

    test('缺字段抛并点名，不静默补空串', () {
      final missing = Map<String, Object?>.from(fields())..remove('nonce');
      expect(
        () => CanonicalMessage.bytes(contract, missing),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('nonce'),
          ),
        ),
        reason: '"没填" 与 "填了空值" 不许签出同一个字节串',
      );
    });

    test('字段值里含分隔符 ⇒ 拒绝（拼接边界歧义是伪造入口）', () {
      final nul = String.fromCharCode(0);
      final evil = Map<String, Object?>.from(fields())
        ..['body'] = 'abc${nul}def';
      expect(
        () => CanonicalMessage.bytes(contract, evil),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('body'), contains('分隔符')),
          ),
        ),
        reason: '不拒绝的话，一个字段就能拼出另一个字段的字节串',
      );
    });

    test('signedFields 就是契约那份顺序（调用方据此判断哪些字段进签名）', () {
      expect(CanonicalMessage.signedFields(contract), contract.canonicalOrder);
    });
  });
}
