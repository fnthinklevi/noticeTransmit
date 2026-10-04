import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_execution_log.dart';
import 'package:notice_transmit/services/fnthink_remote_execution.dart';

/// T-远程执行 片2：设备侧执行内核（状态机 + 延时窗口 + 凭据校验 + 两段回执 + 留痕映射）。
///
/// 这一组钉的是**内核形状**（纯函数、可注入时钟、不碰界面/通道/DB）：
/// ① 五态与契约逐项一致（不写死项数）；
/// ② 允许的迁移恰好那五条、非法迁移**拒**（不是静默保持）；
/// ③ 延时窗口：0 立刻走、未到点等、到点走、窗口内取消不执行、executing 不再看窗口；
/// ④ 凭据：L2 可选 / L3 必填 / 带错的一律拒 / 契约不认的那种带法拒；
/// ⑤ 两段回执取自契约（缺键抛）；
/// ⑥ 留痕映射：done→ok、failed→failed、cancelled→skipped+理由、未执行完不写。
class _StubProbe implements RemoteExecutionCredentialProbe {
  _StubProbe({this.goodKey = '', this.goodTotp = ''});

  final String goodKey;
  final String goodTotp;

  @override
  Future<bool> keyMatches(String presentedKey) async => presentedKey == goodKey;

  @override
  Future<bool> totpValid(String code) async => code == goodTotp;
}

/// 构造一个删掉了 `remoteExecution.receipts.finished` 的契约副本
/// （用于测「缺键抛」这一支：回一个看起来像成功的词出去，比抛更坏）。
FnthinkContract _withoutFinishedReceipt(FnthinkContract c) {
  final copy = Map<String, Object?>.from(c.raw);
  final caps = copy['capabilities']! as Map<String, Object?>;
  final remote = caps['remoteExecution']! as Map<String, Object?>;
  (remote['receipts']! as Map<String, Object?>).remove('finished');
  return FnthinkContract(copy);
}

void main() {
  final contract = FnthinkContract.readFile();
  final startedAt = DateTime.utc(2026, 10, 3, 12);

  group('状态机', () {
    test('五态与契约逐项一致（两边差集都空，不写死项数）', () {
      final declared = contract.remoteExecutionStates.toSet();
      const constants = {
        RemoteExecutionStates.pending,
        RemoteExecutionStates.executing,
        RemoteExecutionStates.done,
        RemoteExecutionStates.failed,
        RemoteExecutionStates.cancelled,
      };
      expect(constants.difference(declared), isEmpty);
      expect(declared.difference(constants), isEmpty);
    });

    test('允许的迁移恰好那五条，每一条都迁得成', () {
      expect(kRemoteExecutionMoves, {
        RemoteExecutionStates.pending: {
          RemoteExecutionStates.executing,
          RemoteExecutionStates.cancelled,
        },
        RemoteExecutionStates.executing: {
          RemoteExecutionStates.done,
          RemoteExecutionStates.failed,
          RemoteExecutionStates.cancelled,
        },
      });
      for (final entry in kRemoteExecutionMoves.entries) {
        for (final to in entry.value) {
          expect(
            advanceRemoteExecution(contract, entry.key, to),
            isA<RemoteExecutionMoved>(),
            reason: '契约允许的迁移 ${entry.key} → $to 竟然被拒',
          );
        }
      }
    });

    test('终态（done/failed）再迁一律拒，理由是终态', () {
      for (final from in [
        RemoteExecutionStates.done,
        RemoteExecutionStates.failed,
      ]) {
        for (final to in [
          RemoteExecutionStates.executing,
          RemoteExecutionStates.done,
        ]) {
          final t = advanceRemoteExecution(contract, from, to);
          expect(t, isA<RemoteExecutionRefused>());
          expect((t as RemoteExecutionRefused).reason, 'terminal-state');
        }
      }
    });

    test('不在允许表里的迁移拒（例如 pending → done：跳过 executing）', () {
      final t = advanceRemoteExecution(
        contract,
        RemoteExecutionStates.pending,
        RemoteExecutionStates.done,
      );
      expect(t, isA<RemoteExecutionRefused>());
      expect((t as RemoteExecutionRefused).reason, 'illegal-move');
    });

    test('from 不在契约词表里 ⇒ unknown-state（别拿一个没命名的状态往下迁）', () {
      final t = advanceRemoteExecution(
        contract,
        'running',
        RemoteExecutionStates.done,
      );
      expect(t, isA<RemoteExecutionRefused>());
      expect((t as RemoteExecutionRefused).reason, 'unknown-state');
    });
  });

  group('延时窗口（时钟注入，不睡真表）', () {
    test('窗口 0 秒 ⇒ 立刻执行（等于关掉延时）', () {
      // ⚠ 8.179 的反证 S3 实测：内核里原有一行 `windowSeconds <= 0 ⇒ Go`，
      // 但窗口为 0 时 deadline==startedAt、`remaining` 必 ≤ 0 ⇒ 那一行与「到点」判据
      // **语义重合、任何夹具都走不到**，摘掉它零失败（假绿）。已删；本条现在断的是**行为**
      // （0 秒窗口必须立刻执行），`now` 晚于 startedAt 以免它落在「等」那一支上。
      final gate = resolveRemoteExecutionWindow(
        contract: contract,
        state: RemoteExecutionStates.pending,
        windowSeconds: 0,
        startedAt: startedAt,
        now: startedAt.add(const Duration(seconds: 5)),
        cancelled: false,
      );
      expect(gate, isA<RemoteExecutionGateGo>());
    });

    test('未到点 ⇒ 等，且剩下的毫秒算得对（默认 10s，走了 3s）', () {
      final gate = resolveRemoteExecutionWindow(
        contract: contract,
        state: RemoteExecutionStates.pending,
        windowSeconds: contract.remoteExecutionDelayDefaultSeconds,
        startedAt: startedAt,
        now: startedAt.add(const Duration(seconds: 3)),
        cancelled: false,
      );
      expect(gate, isA<RemoteExecutionGateWait>());
      expect(
        (gate as RemoteExecutionGateWait).remaining,
        const Duration(seconds: 7).inMilliseconds,
      );
    });

    test('到点 ⇒ 执行（用户不在设备前也一样：计时只看 startedAt 与 now）', () {
      final gate = resolveRemoteExecutionWindow(
        contract: contract,
        state: RemoteExecutionStates.pending,
        windowSeconds: contract.remoteExecutionDelayDefaultSeconds,
        startedAt: startedAt,
        now: startedAt.add(const Duration(seconds: 30)),
        cancelled: false,
      );
      expect(gate, isA<RemoteExecutionGateGo>());
    });

    test('窗口内用户撤销 ⇒ 不执行（pending 与 executing 都一样）', () {
      for (final state in [
        RemoteExecutionStates.pending,
        RemoteExecutionStates.executing,
      ]) {
        final gate = resolveRemoteExecutionWindow(
          contract: contract,
          state: state,
          windowSeconds: contract.remoteExecutionDelayDefaultSeconds,
          startedAt: startedAt,
          now: startedAt.add(const Duration(seconds: 1)),
          cancelled: true,
        );
        expect(
          gate,
          isA<RemoteExecutionGateCancelled>(),
          reason: '$state 下撤销没生效',
        );
      }
    });

    test('已经在 executing 里就不再看窗口（否则一条执行会被反复判成「等」）', () {
      final gate = resolveRemoteExecutionWindow(
        contract: contract,
        state: RemoteExecutionStates.executing,
        windowSeconds: contract.remoteExecutionDelayDefaultSeconds,
        startedAt: startedAt,
        now: startedAt.add(const Duration(seconds: 1)),
        cancelled: false,
      );
      expect(gate, isA<RemoteExecutionGateGo>());
    });
  });

  group('凭据校验', () {
    test('L3 不带凭据 ⇒ 拒（missing-required）', () async {
      final r = await checkRemoteExecutionAuth(
        contract,
        level: 'L3',
        key: null,
        totpCode: null,
        probe: _StubProbe(),
      );
      expect(r, isA<RemoteExecutionAuthRejected>());
      expect((r as RemoteExecutionAuthRejected).reason, 'missing-required');
    });

    test('L2 不带凭据 ⇒ 放行（维护者定：L2 可选）', () async {
      final r = await checkRemoteExecutionAuth(
        contract,
        level: 'L2',
        key: null,
        totpCode: null,
        probe: _StubProbe(),
      );
      expect(r, isA<RemoteExecutionAuthOk>());
      expect((r as RemoteExecutionAuthOk).presented, '');
    });

    test('L3 带对的 key 或 totp 都放行（任一即可）', () async {
      final probe = _StubProbe(goodKey: 'sekret', goodTotp: '123456');
      final byKey = await checkRemoteExecutionAuth(
        contract,
        level: 'L3',
        key: 'sekret',
        totpCode: null,
        probe: probe,
      );
      final byTotp = await checkRemoteExecutionAuth(
        contract,
        level: 'L3',
        key: null,
        totpCode: '123456',
        probe: probe,
      );
      expect((byKey as RemoteExecutionAuthOk).presented, 'key');
      expect((byTotp as RemoteExecutionAuthOk).presented, 'totp');
    });

    test('带了但不对 ⇒ 拒（带了就必须验，不能「带了但不校验」）', () async {
      final r = await checkRemoteExecutionAuth(
        contract,
        level: 'L3',
        key: 'wrong',
        totpCode: '000000',
        probe: _StubProbe(goodKey: 'sekret', goodTotp: '123456'),
      );
      expect(r, isA<RemoteExecutionAuthRejected>());
      expect((r as RemoteExecutionAuthRejected).reason, 'wrong');
    });

    test('带了契约不认的那一种凭据 ⇒ 拒（unsupported-mode）', () async {
      final narrow = FnthinkContract(
        // 只认 key ⇒ 带 totp 不该被放过
        _withAuthModes(contract, const ['key']),
      );
      final r = await checkRemoteExecutionAuth(
        narrow,
        level: 'L3',
        key: null,
        totpCode: '123456',
        probe: _StubProbe(goodTotp: '123456'),
      );
      expect(r, isA<RemoteExecutionAuthRejected>());
      expect((r as RemoteExecutionAuthRejected).reason, 'unsupported-mode');
    });
  });

  group('两段回执', () {
    test('两个词都取自契约（不是本文件写死的）', () {
      expect(
        remoteExecutionStartedReceipt(contract),
        contract.remoteExecutionReceipts['started'],
      );
      expect(
        remoteExecutionFinishedReceipt(contract),
        contract.remoteExecutionReceipts['finished'],
      );
    });

    test('缺 finished 那个键 ⇒ 抛（不许默认回一个看起来像成功的词）', () {
      final broken = _withoutFinishedReceipt(contract);
      expect(
        () => remoteExecutionFinishedReceipt(broken),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('留痕映射', () {
    FnthinkExecutionLog? row(String state) => remoteExecutionAuditRow(
      kind: 'l2_action',
      item: 'listener:start',
      argument: '',
      from: 'peer-a',
      state: state,
      atMs: 1,
    );

    test('done ⇒ ok；failed ⇒ failed；cancelled ⇒ skipped 且理由是用户撤销', () {
      expect(row(RemoteExecutionStates.done)!.result, 'ok');
      expect(row(RemoteExecutionStates.failed)!.result, 'failed');
      final cancelled = row(RemoteExecutionStates.cancelled)!;
      expect(cancelled.result, 'skipped');
      expect(cancelled.reason, 'cancelled-by-user');
    });

    test('还没执行完不写留痕（pending / executing ⇒ 无行）', () {
      expect(row(RemoteExecutionStates.pending), isNull);
      expect(row(RemoteExecutionStates.executing), isNull);
    });

    test('收出来的键全在契约白名单里（顺带过一次黑名单）', () {
      final out = row(RemoteExecutionStates.done)!.toRow(contract);
      for (final key in out.keys) {
        expect(
          contract.executionFields.contains(key),
          isTrue,
          reason: '$key 不在 execution.fields 白名单里',
        );
        expect(contract.executionForbiddenFields.contains(key), isFalse);
      }
      expect(out['body'], isNull, reason: '留痕里不许有正文键');
    });
  });
}

/// 把契约副本里的 auth.modes 改成只认一种（用于 unsupported-mode 那条）。
Map<String, Object?> _withAuthModes(FnthinkContract c, List<String> modes) {
  final copy = Map<String, Object?>.from(c.raw);
  final caps = copy['capabilities']! as Map<String, Object?>;
  final remote = caps['remoteExecution']! as Map<String, Object?>;
  (remote['auth']! as Map<String, Object?>)['modes'] = modes;
  return copy;
}
