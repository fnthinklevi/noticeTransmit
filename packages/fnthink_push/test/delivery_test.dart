import 'dart:convert';
import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:test/test.dart';

/// 投递状态机（T34）的 **Dart 侧**向量断言。Node 那一半在
/// server/test/fnthink-delivery.test.js，两边吃同一份
/// protocol/fnthink-vectors-v1.json 的 delivery 段。
///
/// 为什么这一组特别值得共享：这条链**一半在服务端**（排队、到期、挤位）**一半在设备上**
/// （ack、重发）。两边判得不一样时不会报错，只会变成"设备以为还能重试、服务端已经转
/// waiting_online"—— 而中间态意味着那条消息的正文一直留着删不掉，正是产品不变量里
/// "不静默丢、也不无谓留"的反面。
void main() {
  final contract = FnthinkContract.readFile();
  final cases =
      (jsonDecode(File(fnthinkVectorsFile()).readAsStringSync())
              as Map<String, Object?>)['delivery']
          as List<Object?>;
  final steps = cases.cast<Map<String, Object?>>();

  DeliveryStep _run(Map<String, Object?> given) => advanceDelivery(
    contract,
    state: given['state'] as String,
    event: given['event'] as String,
    attempts: (given['attempts'] as num).toInt(),
    hasBackupChannel: given['hasBackupChannel'] == true,
  );

  final states = contract.strings(const ['delivery', 'states']);
  final events = contract.strings(const ['delivery', 'events']);
  final receipts = (contract.raw['receipts'] as List<Object?>)
      .map((e) => '$e')
      .toList();

  group('投递状态机向量（Dart 侧，T34-A）', () {
    test('逐条：状态、尝试数、回执、正文释放、补发路向都要对上', () {
      expect(steps, isNotEmpty);
      for (final c in steps) {
        final given = c['given'] as Map<String, Object?>;
        final want = c['expect'] as Map<String, Object?>;
        final got = _run(given);
        final id = c['id'];
        expect(got.state, want['state'], reason: '$id state');
        expect(
          got.attempts,
          (want['attempts'] as num).toInt(),
          reason: '$id attempts',
        );
        expect(got.receipt, want['receipt'], reason: '$id receipt');
        expect(
          got.deleteBody,
          want['deleteBody'] == true,
          reason: '$id deleteBody',
        );
        expect(got.resend, want['resend'], reason: '$id resend');
        expect(got.ignored, want['ignored'], reason: '$id ignored');
      }
    });

    test('词表：向量里不许出现契约之外的状态、事件与回执', () {
      for (final c in steps) {
        final given = c['given'] as Map<String, Object?>;
        final want = c['expect'] as Map<String, Object?>;
        expect(
          states,
          contains(given['state']),
          reason: '${c['id']} given.state',
        );
        expect(
          events,
          contains(given['event']),
          reason: '${c['id']} given.event',
        );
        expect(
          states,
          contains(want['state']),
          reason: '${c['id']} expect.state',
        );
        final receipt = want['receipt'];
        if (receipt != null) {
          expect(
            receipts,
            contains(receipt),
            reason: '${c['id']} receipt 不在契约回执表里',
          );
        }
      }
    });

    test('覆盖：契约迁移表里每条边都至少被一例走到（少一条边就是没人测过那条状态）', () {
      final table = contract.map(const ['delivery', 'transitions']) ?? const {};
      final covered = <String>{};
      for (final c in steps) {
        final given = c['given'] as Map<String, Object?>;
        final want = c['expect'] as Map<String, Object?>;
        if (want['ignored'] != null) continue;
        covered.add('${given['state']}->${want['state']}');
      }
      final missing = <String>[
        for (final entry in table.entries)
          for (final to in (entry.value as List<Object?>? ?? const []).map(
            (e) => '$e',
          ))
            if (!covered.contains('${entry.key}->$to')) '${entry.key}->$to',
      ];
      expect(missing, isEmpty, reason: '这些迁移边没有任何向量覆盖：$missing');
    });

    test('乱序与迟到不抛错：ignored 的形状固定，且状态与尝试数都不动', () {
      for (final c in steps) {
        final given = c['given'] as Map<String, Object?>;
        final want = c['expect'] as Map<String, Object?>;
        if (want['ignored'] == null) continue;
        final got = _run(given);
        expect(got.state, given['state'], reason: '${c['id']} 被忽略却改了状态');
        expect(got.attempts, given['attempts'], reason: '${c['id']} 被忽略却动了尝试数');
        expect(got.receipt, isNull, reason: '${c['id']} 被忽略却发了回执');
        expect(
          got.ignored,
          'ignored:${given['state']}+${given['event']}',
          reason: '${c['id']} ignored 形状不对',
        );
      }
    });

    test('未知状态/未知事件直接抛：那是编程错误，不是网络噪声', () {
      expect(
        () => _run({
          'state': 'teleporting',
          'event': 'dispatch',
          'attempts': 0,
          'hasBackupChannel': false,
        }),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => _run({
          'state': 'queued',
          'event': 'reboot',
          'attempts': 0,
          'hasBackupChannel': false,
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('正文释放与保留上限（T34-A）', () {
    test('每一个终态都释放正文（契约 validate 也钉同一条，这里是双侧各查一遍）', () {
      final terminals = contract.strings(const ['delivery', 'terminalStates']);
      expect(terminals, isNotEmpty);
      for (final t in terminals) {
        expect(
          releasesDeliveryBody(contract, t),
          isTrue,
          reason: '终态 $t 不在 retention.deleteBodyOn 里 ⇒ 它的正文会合法地留到 7 天',
        );
      }
      // 反过来：非终态不许释放（否则消息还在飞，正文先没了）
      for (final s in states.where((e) => !terminals.contains(e))) {
        expect(
          releasesDeliveryBody(contract, s),
          isFalse,
          reason: '非终态 $s 被列进了 deleteBodyOn',
        );
      }
    });

    test('重试预算：1 次首投 + 契约的 deliveryRetryTotal', () {
      expect(
        deliveryMaxAttempts(contract),
        (contract.intOf(const ['limits', 'deliveryRetryTotal']) ?? 0) + 1,
      );
      expect(deliveryMaxAttempts(contract), 3);
    });

    test('补发路向二选一：配了备用渠道走备用，没配才由服务端排队补发', () {
      final waiting = contract.map(const ['waitingOnline']) ?? const {};
      final withBackup = advanceDelivery(
        contract,
        state: 'delivering',
        event: 'no_ack',
        attempts: deliveryMaxAttempts(contract),
        hasBackupChannel: true,
      );
      final withoutBackup = advanceDelivery(
        contract,
        state: 'delivering',
        event: 'no_ack',
        attempts: deliveryMaxAttempts(contract),
      );
      expect(withBackup.resend, waiting['withBackupChannel']);
      expect(withoutBackup.resend, waiting['withoutBackupChannel']);
      expect(
        withBackup.resend,
        isNot(withoutBackup.resend),
        reason: '两条路同名就等于并存 —— 同一条消息提醒两次',
      );
    });

    test('挤位：算出要丢几条最旧的，且每条都带 dropped 回执（不许静默丢）', () {
      final max =
          contract.intOf(const ['retention', 'pendingPerDeviceMax']) ?? 0;
      expect(max, 200);
      expect(deliveryEvictCount(contract, pendingNow: max - 1), 0);
      expect(deliveryEvictCount(contract, pendingNow: max), 1);
      expect(deliveryEvictCount(contract, pendingNow: max + 4, incoming: 3), 7);
      expect(deliveryEvictionReceipts(contract), ['dropped']);
      expect(receipts, contains('dropped'));
    });

    test('到期判定按契约的 maxRetentionDays，边界是"到点即过期"', () {
      final days = contract.intOf(const ['retention', 'maxRetentionDays']) ?? 0;
      final dayMs = 24 * 60 * 60 * 1000;
      expect(
        isDeliveryExpired(contract, queuedAtMs: 0, nowMs: days * dayMs - 1),
        isFalse,
      );
      expect(
        isDeliveryExpired(contract, queuedAtMs: 0, nowMs: days * dayMs),
        isTrue,
      );
    });

    test('初态与终态都取自契约表，不写死', () {
      expect(
        deliveryInitialState(contract),
        contract.str(const ['delivery', 'initialState']),
      );
      expect(isDeliveryTerminal(contract, 'queued'), isFalse);
      for (final t in contract.strings(const ['delivery', 'terminalStates'])) {
        expect(isDeliveryTerminal(contract, t), isTrue, reason: t);
        expect(
          canTransitionDelivery(contract, t, 'queued'),
          isFalse,
          reason: '终态 $t 不该还有出边',
        );
      }
    });
  });
}
