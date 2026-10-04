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
    // stage 没有默认值：两段判的不完全是同一件事，逼调用方说清自己是哪一段
    stage: given['stage'] == 'intake'
        ? CapabilityStage.intake
        : CapabilityStage.apply,
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
        expect(
          got.requiresApplyConfirm,
          want['requiresApplyConfirm'] == true,
          reason: '${c['id']} requiresApplyConfirm',
        );
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

    test('两段各覆盖到，且 apply 段必须显式传 stage（编译期就拦）', () {
      final stages = caps
          .map((c) => (c['given'] as Map)['stage'] as String)
          .toSet();
      expect(stages, {'intake', 'apply'});
      // 收单段永远不判确认：自称已确认与没确认，两次的结果必须一模一样
      final selfClaim = caps.firstWhere(
        (c) => c['id'] == 'c-intake-ignores-self-claim',
      );
      final asIfNotConfirmed = decideCapability(
        contract,
        stage: CapabilityStage.intake,
        grant: FnthinkGrant.fromNode(
          contract,
          (selfClaim['given'] as Map)['grant'],
        ),
        type: 'setting',
        item: 'setting:battery_saver',
        confirmedThisTime: false,
      );
      expect(
        asIfNotConfirmed.allowed,
        (selfClaim['expect'] as Map)['allowed'] == true,
        reason: '请求里那个自称的 confirmed 在收单段根本不参与判决',
      );
    });

    test('缺省档就是最窄那一档，且授权变更必须重新确认（两条红线）', () {
      expect(contract.grantDefaultMaxLevel, contract.capabilityLevels.first);
      expect(contract.rejectsUnknownMessageTypes, isTrue);
      expect(contract.grantChangeRequiresConfirmation, isTrue);
      // 吊销与生命周期（T31）：白名单只有 active，且吊销不删历史
      expect(contract.deliveryAllowedStatuses, ['active']);
      expect(
        contract.deviceStatuses.keys,
        containsAll(['active', 'frozen', 'revoked', 'awaitingRepair']),
      );
      expect(contract.revokeKeepsHistory, isTrue);
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

  group('L3 熔断：一分钟内连续失败降到 L1（T49）', () {
    late int clock;
    late L3CircuitBreaker breaker;
    final start = 1700000000000;

    setUp(() {
      clock = start;
      breaker = L3CircuitBreaker(contract: contract, nowMs: () => clock);
    });

    test('没到那条线不许降（少一次失败就还是现状）', () {
      for (var i = 0; i < breaker.threshold - 1; i++) {
        clock += 100;
        expect(breaker.recordFailure(), isNull, reason: '第 ${i + 1} 次就降了');
      }
      expect(breaker.failuresInWindow, breaker.threshold - 1);
      expect(breaker.tripped, isFalse);
    });

    test('一分钟内连续失败到那条线就降到契约写的那一档', () {
      for (var i = 0; i < breaker.threshold; i++) {
        clock += 100;
        final drop = breaker.recordFailure();
        if (i < breaker.threshold - 1) {
          expect(drop, isNull, reason: '第 ${i + 1} 次就降了');
        } else {
          expect(drop, 'L1', reason: '到线那一次没降');
        }
      }
      expect(breaker.tripped, isTrue);
    });

    test('失败之间插一次成功就重新计数（连续的意思）', () {
      for (var i = 0; i < breaker.threshold - 1; i++) {
        clock += 100;
        breaker.recordFailure();
      }
      breaker.recordSuccess();
      expect(breaker.failuresInWindow, 0);
      clock += 100;
      expect(breaker.recordFailure(), isNull, reason: '成功后还在拿旧账降级');
    });

    test('超过一分钟的旧失败不算（否则每分钟失败一次也会攒到阈值）', () {
      for (var i = 0; i < breaker.threshold; i++) {
        clock += 1000;
        breaker.recordFailure();
      }
      clock += L3CircuitBreaker.windowMs;
      expect(breaker.failuresInWindow, 0, reason: '窗口没被裁掉');
      expect(breaker.tripped, isFalse);
    });

    test('降级有方向：降到契约那一档就停，不会一路掉到最低档', () {
      String? seen;
      for (var i = 0; i < breaker.threshold * 3; i++) {
        clock += 10;
        seen = breaker.recordFailure() ?? seen;
      }
      expect(seen, breaker.downgradeTo);
      expect(
        contract.levelRank(seen!),
        lessThan(contract.levelRank(contract.capabilityLevels.last)),
      );
    });

    test('阈值与降档都取自契约（代码里没有第二个数字）', () {
      expect(breaker.threshold, 5);
      expect(breaker.downgradeTo, 'L1');
    });
  });
}
