import 'dart:convert';
import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:test/test.dart';

/// 跨端一致性向量的 **Dart 侧**（T26）。Node 那一半在 server/test/fnthink-credentials.test.js，
/// 两边吃同一份 protocol/fnthink-vectors-v1.json。
///
/// 为什么值得单独一份文件：归一化和摘要这类"看起来不可能不一致"的东西，恰恰是两端各写一遍
/// 最容易悄悄分叉的 —— 差一个字符的归一化规则，表现是"设备显示的口令服务端永远不认"，
/// 而两边各自跑测试都是绿的。

Map<String, Object?> _loadVectors() =>
    jsonDecode(File(fnthinkVectorsFile()).readAsStringSync())
        as Map<String, Object?>;

void main() {
  final contract = FnthinkContract.readFile();
  final vectors = _loadVectors();
  final cases = (vectors['cases'] as List<Object?>)
      .cast<Map<String, Object?>>();

  group('凭证向量（Dart 侧）', () {
    test('向量文件与契约同目录，且不是包里的副本', () {
      final path = fnthinkVectorsFile().replaceAll(r'\', '/');
      expect(path.endsWith('protocol/fnthink-vectors-v1.json'), isTrue);
      expect(path.contains('packages/fnthink_push/protocol'), isFalse);
      expect(cases, isNotEmpty);
    });

    test('逐条：地址码走 parse、口令走 parse，归一化与摘要都要对上（报错点名到 id）', () {
      final bad = <String>[];
      for (final c in cases) {
        final id = '${c['id']}';
        final kind = '${c['kind']}';
        final input = '${c['input']}';
        final expect_ = c['expect'] as Map<String, Object?>;
        final wantValid = expect_['valid'] as bool;
        final wantNormalized = expect_['normalized'] as String?;
        final wantDigest = expect_['digest'] as String?;

        // 归一化与校验是两件事：normalize 只管大小写与分隔符，位数由 parse 判。
        final norm = CrockfordBase32.fromContract(
          alphabet: contract.str(const ['identity', 'addressCode', 'alphabet']),
          excludedChars: contract.str(const [
            'identity',
            'addressCode',
            'excludedChars',
          ]),
        ).normalize(input);
        if (norm != wantNormalized) {
          bad.add('$id 归一化成 $norm ≠ 向量 $wantNormalized');
          continue;
        }
        final parsed = kind == 'addressCode'
            ? FnthinkAddressCode.parse(contract, input)
            : FnthinkPairingCode.parse(contract, input);
        if ((parsed != null) != wantValid) {
          bad.add(
            '$id($kind) "$input" → ${parsed == null ? '判非法' : '判合法'}，'
            '契约要求 ${wantValid ? '合法' : '非法'}',
          );
          continue;
        }
        if (!wantValid) continue;
        try {
          final digest = fnthinkCredentialDigest(contract, kind, input);
          if (digest != wantDigest) {
            bad.add('$id 摘要 $digest ≠ 向量 $wantDigest');
          }
        } on ArgumentError catch (e) {
          bad.add('$id 合法却拒绝计算摘要：$e');
        }
      }
      expect(bad, isEmpty);
    });

    test('向量覆盖到位：两种凭证各有正例，四个排除字符各挡一次', () {
      final kinds = cases.map((c) => '${c['kind']}').toSet();
      expect(kinds, equals({'addressCode', 'pairingCode'}));
      final alphabet = CrockfordBase32.fromContract(
        alphabet: contract.str(const ['identity', 'addressCode', 'alphabet']),
        excludedChars: contract.str(const [
          'identity',
          'addressCode',
          'excludedChars',
        ]),
      );
      for (final kind in kinds) {
        expect(
          cases.any(
            (c) =>
                c['kind'] == kind &&
                ((c['expect'] as Map)['valid'] as bool) == true,
          ),
          isTrue,
          reason: '$kind 没有正例，等于没测',
        );
        expect(
          cases.any(
            (c) =>
                c['kind'] == kind &&
                ((c['expect'] as Map)['valid'] as bool) == false,
          ),
          isTrue,
        );
      }
      for (final char in alphabet.excluded.split('')) {
        expect(
          cases.any(
            (c) =>
                ((c['expect'] as Map)['valid'] as bool) == false &&
                '${c['input']}'.toUpperCase().contains(char),
          ),
          isTrue,
          reason: '排除字符 $char 没有对应用例',
        );
      }
    });

    test('不合法就拒绝算摘要：空串会算出稳定摘要，那正是"没填=填了空"的越权入口', () {
      expect(
        () => fnthinkCredentialDigest(contract, 'addressCode', ''),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('18'),
          ),
        ),
      );
      expect(
        () => fnthinkCredentialDigest(contract, 'pairingCode', 'ILOU' * 5),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('摘要只认归一化后的字节：换写法不换值，差一位就换值', () {
      final one = fnthinkCredentialDigest(
        contract,
        'addressCode',
        '8K3FJ6QPTM9WZ4VHNS',
      );
      expect(
        fnthinkCredentialDigest(
          contract,
          'addressCode',
          '8k3f-j6qp tm9w-z4vhns',
        ),
        one,
      );
      expect(one.length, 64);
      expect(one, one.toLowerCase());
      expect(
        fnthinkCredentialDigest(contract, 'addressCode', '8K3FJ6QPTM9WZ4VHNR'),
        isNot(one),
      );
    });

    test('契约改位数 ⇒ 判定跟着改（代码里没有第二份 18）', () {
      final shrunk = FnthinkContract(_deepMap(contract.raw));
      // 把地址码改成 17 位：17 位的串必须立刻变合法，18 位变非法。
      ((shrunk.raw['identity'] as Map<String, Object?>)['addressCode']
              as Map<String, Object?>)['length'] =
          17;
      expect(FnthinkAddressCode.parse(shrunk, '8K3FJ6QPTM9WZ4VHN'), isNotNull);
      expect(FnthinkAddressCode.parse(shrunk, '8K3FJ6QPTM9WZ4VHNS'), isNull);
    });
  });
}

Map<String, Object?> _deepMap(Map<String, Object?> source) {
  final out = <String, Object?>{};
  source.forEach((key, value) {
    if (value is Map<String, Object?>) {
      out[key] = _deepMap(value);
    } else if (value is List<Object?>) {
      out[key] = List<Object?>.from(value);
    } else {
      out[key] = value;
    }
  });
  return out;
}
