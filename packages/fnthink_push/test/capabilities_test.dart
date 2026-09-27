import 'dart:convert';
import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:test/test.dart';

/// 能力清单（T30）的 **Dart 侧**向量断言。Node 那一半在
/// server/test/fnthink-capabilities.test.js，两边吃同一份
/// protocol/fnthink-vectors-v1.json 的 capabilities 段。
///
/// 这一组为什么必须共享：两份实现（Dart 与 Node）都对"这台设备准不准发这一条"
/// 各判一次，而它们不一致时的表现不是报错 —— 是设备以为只给了 L1、服务端却按 L2 收，
/// 或者反过来把一条合法消息丢掉。

Map<String, Object?> _loadVectors() =>
    jsonDecode(File(fnthinkVectorsFile()).readAsStringSync())
        as Map<String, Object?>;

/// reason 的全部形状（与向量文件里 `_capabilityReasonVocabulary` 那一段一一对应）。
const _reasonForms = <String>[
  'unknown-type:',
  'level:L',
  'item:',
  'missing-item',
  'confirm-required',
];

void main() {
  final contract = FnthinkContract.readFile();
  final caps = (_loadVectors()['capabilities'] as List<Object?>)
      .cast<Map<String, Object?>>();

  CapabilityDecision _decide(Map<String, Object?> given) => decideCapability(
    contract,
    grant: FnthinkGrant.fromNode(contract, given['grant']),
    type: given['type'] as String,
    item: given['item'] as String?,
    confirmedThisTime: given['confirmedThisTime'] == true,
  );

  group('能力清单向量（Dart 侧，T30-A）', () {
    test('逐条：allowed 与 reason 都要对上（失败点名到 id）', () {
      expect(caps, isNotEmpty);
      for (final c in caps) {
        final got = _decide(c['given'] as Map<String, Object?>);
        final want = c['expect'] as Map<String, Object?>;
        expect(
          got.allowed,
          want['allowed'] == true,
          reason: '${c['id']} allowed',
        );
        expect(got.reason, want['reason'], reason: '${c['id']} reason');
      }
    });

    test('实现产出的每个 reason 都在词表里（冒出第六种形状就是没对齐契约）', () {
      for (final c in caps) {
        final reason = _decide(c['given'] as Map<String, Object?>).reason;
        if (reason == null) continue;
        expect(
          CapabilityDecision.reasonPattern.hasMatch(reason),
          isTrue,
          reason: '${c['id']} 的 reason「$reason」不在词表里',
        );
      }
    });

    test('词表里每一形都有用例覆盖（删了用例会让那一形再也拦不住）', () {
      final covered = <String>{
        for (final c in caps)
          for (final form in _reasonForms)
            if ((c['expect'] as Map)['reason']?.toString().startsWith(form) ??
                false)
              form,
      };
      expect(covered, _reasonForms.toSet());
    });

    test('契约的 type 词表 = 向量里用到的 type（新增一档却不补向量 ⇒ 红）', () {
      final used = caps
          .map((c) => (c['given'] as Map)['type'] as String)
          .toSet();
      final declared = contract.messageTypeLevels.keys.toSet();
      expect(
        used.intersection(declared),
        declared,
        reason: '这些 type 没有向量：$declared',
      );
      // 向量里那几个"故意不存在"的 type 也必须真的不存在（否则测的是别的东西）
      for (final ghost in ['teleport', 'Notice']) {
        expect(declared.contains(ghost), isFalse);
      }
    });

    test('缺省档就是最窄那一档，且授权变更必须重新确认（两条红线）', () {
      expect(contract.grantDefaultMaxLevel, contract.capabilityLevels.first);
      expect(contract.rejectsUnknownMessageTypes, isTrue);
      expect(contract.grantChangeRequiresConfirmation, isTrue);
      expect(contract.validate(), isEmpty);
    });

    test('grant 节点形状不认识的都往窄的那一侧靠', () {
      expect(
        FnthinkGrant.fromNode(contract, null).maxLevel,
        contract.grantDefaultMaxLevel,
      );
      expect(
        FnthinkGrant.fromNode(contract, {'maxLevel': 'L3'}).items,
        isEmpty,
      );
      // items 写成字符串/对象都不算"全给"，按空清单处理
      expect(
        FnthinkGrant.fromNode(contract, {
          'maxLevel': 'L3',
          'items': 'app:a/b',
        }).items,
        isEmpty,
      );
    });
  });
}
