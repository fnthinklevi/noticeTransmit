import 'dart:convert';
import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:test/test.dart';

/// 配对载荷与裁决（T28-A）· **Dart 侧**。Node 那一半在 server/test/fnthink-pairing.test.js，
/// 两边吃同一份 protocol/fnthink-vectors-v1.json 的 payloads 段。
///
/// 为什么值得钉：配对是整条协议里唯一"把秘密印在屏幕上给另一台设备看"的环节。
/// 两端对载荷的理解差一个字段，表现不是报错而是"扫了码说无效"，而用户只会认为是相机坏了。

Map<String, Object?> _loadVectors() =>
    jsonDecode(File(fnthinkVectorsFile()).readAsStringSync())
        as Map<String, Object?>;

FnthinkContract _with(void Function(Map<String, Object?> raw) change) {
  final copy =
      jsonDecode(jsonEncode(FnthinkContract.readFile().raw))
          as Map<String, Object?>;
  change(copy);
  return FnthinkContract(copy);
}

void main() {
  final contract = FnthinkContract.readFile();
  final payloads = (_loadVectors()['payloads'] as List<Object?>)
      .cast<Map<String, Object?>>();

  group('配对载荷（与 Node 共吃一份向量）', () {
    test('逐条：ok / reason / 归一化后的请求三项都要对上（点名到 id）', () {
      final bad = <String>[];
      for (final c in payloads) {
        final id = '${c['id']}';
        final text = '${c['payload']}';
        final want = c['expect'] as Map<String, Object?>;
        final got = FnthinkPairingRequest.parse(contract, text);
        if (got.ok != want['ok']) {
          bad.add(
            '$id 判成 ${got.ok}，期望 ${want['ok']}（reason=${got.internalReason}）',
          );
          continue;
        }
        if (got.internalReason != want['reason']) {
          bad.add('$id reason=${got.internalReason}，期望 ${want['reason']}');
          continue;
        }
        if (!got.ok) continue;
        final wantReq = want['request'] as Map<String, Object?>;
        final req = got.request!;
        if (req.contractVersion != wantReq['v'] ||
            req.addressCode != wantReq['to'] ||
            req.pairingCode != wantReq['code'] ||
            req.level != wantReq['level']) {
          bad.add(
            '$id 解析出 ${req.addressCode}/${req.pairingCode}/${req.level}/${req.contractVersion}，'
            '期望 ${wantReq['to']}/${wantReq['code']}/${wantReq['level']}/${wantReq['v']}',
          );
        }
      }
      expect(bad, isEmpty);
    });

    test('拼出来的文本再解一次必须回到同一个请求；产出文本恒为规范形态（大写、契约字段序）', () {
      for (final c in payloads) {
        final want = c['expect'] as Map<String, Object?>;
        if (want['ok'] != true) continue;
        final req = want['request'] as Map<String, Object?>;
        final built = FnthinkPairingRequest(
          addressCode: req['to'] as String,
          pairingCode: req['code'] as String,
          level: req['level'] as String,
          contractVersion: req['v'] as int,
        ).qrText(contract);
        // 向量里的文本可能是小写（p-lower 就是来测这个的），所以比的是"再解一次"而不是字面。
        final again = FnthinkPairingRequest.parse(contract, built).request!;
        expect(
          [
            again.contractVersion,
            again.addressCode,
            again.pairingCode,
            again.level,
          ],
          [req['v'], req['to'], req['code'], req['level']],
          reason: '${c['id']} 拼出去再解回来变了',
        );
        expect(
          built,
          '${contract.pairingQrPrefix}?v=${req['v']}&to=${req['to']}'
          '&code=${req['code']}&level=${req['level']}',
          reason: '${c['id']}：两端各自印的码必须逐字符相同',
        );
      }
    });

    test('字段顺序与上限都只在契约里：改契约，产出跟着变', () {
      final reordered = _with((raw) {
        ((raw['pairing'] as Map)['payloadFields'] as List).setAll(0, [
          'level',
          'code',
          'to',
          'v',
        ]);
      });
      final request = FnthinkPairingRequest(
        addressCode: '8K3FJ6QPTM9WZ4VHNS',
        pairingCode: '7YD4RKQPBM8XZ3VHNT6J',
        level: 'L1',
        contractVersion: 1,
      );
      expect(
        request.qrText(reordered),
        startsWith('${reordered.pairingQrPrefix}?level=L1&code='),
      );
      // 顺序只在契约里：换序后自己拼的文本自己照样能解（解不出来才是真出事了）
      expect(
        FnthinkPairingRequest.parse(reordered, request.qrText(reordered)).ok,
        isTrue,
      );
    });

    test('契约缺 qrPrefix / rejectUnknownFields ⇒ 抛，不补默认值', () {
      final noPrefix = _with((raw) {
        (raw['pairing'] as Map).remove('qrPrefix');
      });
      expect(() => noPrefix.pairingQrPrefix, throwsStateError);
      final noReject = _with((raw) {
        (raw['pairing'] as Map).remove('rejectUnknownFields');
      });
      expect(() => noReject.pairingRejectUnknownFields, throwsStateError);
    });

    test('载荷只判"是不是契约定义的级别"，上限留给裁决（一条规则只写一处）', () {
      expect(
        FnthinkPairingRequest.parse(
          contract,
          FnthinkPairingRequest(
            addressCode: '8K3FJ6QPTM9WZ4VHNS',
            pairingCode: '7YD4RKQPBM8XZ3VHNT6J',
            level: 'L3',
            contractVersion: 1,
          ).qrText(contract),
        ).ok,
        isTrue,
      );
    });
  });

  group('裁决（decidePairing）', () {
    FnthinkPairingResult good({String level = 'L1'}) {
      final request = FnthinkPairingRequest(
        addressCode: '8K3FJ6QPTM9WZ4VHNS',
        pairingCode: '7YD4RKQPBM8XZ3VHNT6J',
        level: level,
        contractVersion: 1,
      );
      return FnthinkPairingRequest.parse(contract, request.qrText(contract));
    }

    test('口令没验对时，人点了确认也不批准', () {
      expect(
        decidePairing(
          contract,
          payload: good(),
          pairingCodeVerified: false,
          hasSenderSignature: true,
          signatureValid: true,
          userConfirmed: true,
        ),
        PairingVerdict.rejectCredential,
      );
    });

    test('一切合法但没人确认 ⇒ 停在 awaitingConfirmation，绝不自动批准', () {
      expect(
        decidePairing(
          contract,
          payload: good(),
          pairingCodeVerified: true,
          hasSenderSignature: true,
          signatureValid: true,
        ),
        PairingVerdict.awaitingConfirmation,
      );
    });

    test('全部满足 + 人确认 ⇒ 才 approve', () {
      expect(
        decidePairing(
          contract,
          payload: good(),
          pairingCodeVerified: true,
          hasSenderSignature: true,
          signatureValid: true,
          userConfirmed: true,
        ),
        PairingVerdict.approve,
      );
    });

    test('L2 可请求，L3 在配对这条路上必拒（免本地确认的上限来自契约）', () {
      expect(contract.pairingMaxRequestableLevel, 'L2');
      for (final level in ['L1', 'L2']) {
        expect(
          decidePairing(
            contract,
            payload: good(level: level),
            pairingCodeVerified: true,
            hasSenderSignature: true,
            signatureValid: true,
            userConfirmed: true,
          ),
          PairingVerdict.approve,
          reason: '$level 应在免本地确认的上限内',
        );
      }
      expect(
        decidePairing(
          contract,
          payload: good(level: 'L3'),
          pairingCodeVerified: true,
          hasSenderSignature: true,
          signatureValid: true,
          userConfirmed: true,
        ),
        PairingVerdict.rejectLevelTooHigh,
      );
    });

    test('缺签名与签名不对都拒（载荷里没有签名的位置，签验在 T29）', () {
      for (final args in [
        {'hasSenderSignature': false, 'signatureValid': false},
        {'hasSenderSignature': true, 'signatureValid': false},
      ]) {
        expect(
          decidePairing(
            contract,
            payload: good(),
            pairingCodeVerified: true,
            hasSenderSignature: args['hasSenderSignature']!,
            signatureValid: args['signatureValid']!,
            userConfirmed: true,
          ),
          PairingVerdict.rejectSignature,
        );
      }
    });

    test('载荷不成形 / 为 null ⇒ rejectPayload，且不消耗口令', () {
      expect(
        decidePairing(
          contract,
          payload: null,
          pairingCodeVerified: true,
          userConfirmed: true,
        ),
        PairingVerdict.rejectPayload,
      );
      expect(
        decidePairing(
          contract,
          payload: FnthinkPairingRequest.parse(contract, 'other://pair?v=1'),
          pairingCodeVerified: true,
          userConfirmed: true,
        ),
        PairingVerdict.rejectPayload,
      );
    });

    test('契约被翻成"可自动批准"时宁可拒绝，也不擅自入白名单', () {
      final flipped = _with((raw) {
        (raw['pairing'] as Map)['autoApprove'] = true;
      });
      expect(flipped.validate().any((p) => p.contains('不自动批准')), isTrue);
      expect(
        decidePairing(
          flipped,
          payload: FnthinkPairingRequest.parse(
            flipped,
            FnthinkPairingRequest(
              addressCode: '8K3FJ6QPTM9WZ4VHNS',
              pairingCode: '7YD4RKQPBM8XZ3VHNT6J',
              level: 'L1',
              contractVersion: 1,
            ).qrText(flipped),
          ),
          pairingCodeVerified: true,
          hasSenderSignature: true,
          signatureValid: true,
          userConfirmed: true,
        ),
        isNot(PairingVerdict.approve),
      );
    });
  });

  group('失败文案（同形那条）', () {
    test('预授权阶段的四种原因，用户看到的都是同一句', () {
      const reasons = [
        'address-code',
        'pairing-code',
        'version:2',
        'carries-secret:signature',
        null,
      ];
      final texts = reasons.map(fnthinkPairingFailureTextKey).toSet();
      expect(texts, hasLength(1));
      expect(texts.single, isNotEmpty);
    });

    test('口令没验对之前，任何原因都不许解释', () {
      for (final reason in ['level:L3', 'pairing-code', 'unknown:foo']) {
        expect(
          fnthinkPairingMayExplain(reason, codeVerified: false),
          isFalse,
          reason: '$reason 在口令验对前被解释 = 给枚举器递话',
        );
      }
    });

    test('口令验对之后，策略性拒绝可以说明（否则用户只能瞎重试）', () {
      expect(fnthinkPairingMayExplain('level:L3', codeVerified: true), isTrue);
      expect(
        fnthinkPairingMayExplain('pairing-code', codeVerified: true),
        isFalse,
      );
    });
  });
}
