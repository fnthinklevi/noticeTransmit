import 'dart:convert';
import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:test/test.dart';

/// 补推与补发二选一（T46）的 **Dart 侧**断言。Node 那一半在
/// server/test/fnthink-backup-replay.test.js，两边吃同一份
/// protocol/fnthink-vectors-v1.json 的 backupReplay 段。
///
/// 这一组要防的分叉是**互斥**：备用补推与排队补发并存 = 同一条消息提醒两次，
/// 而两边的实现分叉时不会报错，只会在用户手机上响两声。
void main() {
  final contract = FnthinkContract.readFile();

  FnthinkContract mutate(void Function(Map<String, Object?> raw) change) {
    final copy = jsonDecode(jsonEncode(contract.raw)) as Map<String, Object?>;
    change(copy);
    return FnthinkContract(copy);
  }

  final vectors =
      (jsonDecode(File(fnthinkVectorsFile()).readAsStringSync())
              as Map<String, Object?>)['backupReplay']
          as List<Object?>;
  final cases = vectors.cast<Map<String, Object?>>();

  BackupReplayDecision _run(Map<String, Object?> given) => decideBackupReplay(
    contract,
    route: given['route'] as String,
    alreadyReplayed: given['alreadyReplayed'] == true,
    replayCount: (given['replayCount'] as num).toInt(),
    messageId: given['messageId'] as String?,
  );

  group('补推/补发二选一向量（Dart 侧，T46）', () {
    test('逐条：动作、标签、去重键、上限、没做的原因都要对上', () {
      expect(cases, isNotEmpty);
      for (final c in cases) {
        final given = c['given'] as Map<String, Object?>;
        final want = c['expect'] as Map<String, Object?>;
        final got = _run(given);
        final id = c['id'];
        // 比的是**契约路线词**（got.route），不是枚举名：枚举名与契约词各写一份时，
        // 改名的那一天两边悄悄对不上，而对不上的表现是"这一档从来没被走到过"。
        expect(got.route ?? 'none', want['action'], reason: '$id route');
        if (want.containsKey('label')) {
          expect(got.label, want['label'], reason: '$id label');
        }
        if (want.containsKey('dedupeKey')) {
          expect(got.dedupeKey, want['dedupeKey'], reason: '$id dedupeKey');
        }
        if (want.containsKey('max')) {
          expect(got.max, (want['max'] as num).toInt(), reason: '$id max');
        }
        if (want.containsKey('limitReason')) {
          expect(
            got.limitReason,
            want['limitReason'],
            reason: '$id limitReason',
          );
        }
      }
    });

    test('互斥：一条消息的结论里同时只可能出现一条路', () {
      final withBackup = contract.str(const [
        'waitingOnline',
        'withBackupChannel',
      ]);
      final withoutBackup = contract.str(const [
        'waitingOnline',
        'withoutBackupChannel',
      ]);
      expect(withBackup, isNot(withoutBackup));
      for (var count = 0; count <= 3; count++) {
        for (final replayed in [true, false]) {
          for (final route in [withBackup, withoutBackup]) {
            final got = decideBackupReplay(
              contract,
              route: route!,
              alreadyReplayed: replayed,
              replayCount: count,
              messageId: 'msg-x',
            );
            final picksReplay = got.action == BackupReplayAction.backupReplay;
            final picksQueue = got.action == BackupReplayAction.queueResend;
            expect(
              picksReplay && picksQueue,
              isFalse,
              reason: 'route=$route replayed=$replayed count=$count 同时走了两条路',
            );
            // 走了补推那一档时去重键与标签必须都在（缺一个就是"补推了但记不住"）。
            if (picksReplay) {
              expect(got.dedupeKey, isNotNull, reason: '补推却没有去重键');
              expect(got.label, isNotNull, reason: '补推却没标签');
            }
          }
        }
      }
    });

    test('词表与读数全部取自契约：实现里不许写死路线词、标签与上限', () {
      expect(
        backupReplayMax(contract),
        contract.intOf(const ['limits', 'backupReplayMax']),
      );
      expect(
        backupReplayIdempotencyKeyName(contract),
        contract.str(const ['waitingOnline', 'backupReplayIdempotencyKey']),
      );
      final first = decideBackupReplay(
        contract,
        route: contract.str(const ['waitingOnline', 'withBackupChannel'])!,
        alreadyReplayed: false,
        replayCount: 0,
        messageId: 'msg-y',
      );
      expect(
        first.label,
        contract.str(const ['waitingOnline', 'backupReplayLabel']),
      );
    });
  });

  group('读不出契约时照抛，不退回默认值', () {
    test('limits.backupReplayMax 缺了 ⇒ 抛（退回 0 等于把这条路径悄悄关掉）', () {
      final broken = mutate((raw) {
        (raw['limits'] as Map<String, Object?>).remove('backupReplayMax');
      });
      expect(() => backupReplayMax(broken), throwsA(isA<StateError>()));
      expect(
        () => decideBackupReplay(
          broken,
          route: 'backup_replay',
          alreadyReplayed: false,
          replayCount: 0,
          messageId: 'msg-z',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('backupReplayIdempotencyKey 指名别的键 ⇒ 抛（不拿 message_id 顶替）', () {
      final broken = mutate((raw) {
        (raw['waitingOnline']
                as Map<String, Object?>)['backupReplayIdempotencyKey'] =
            'dedupe_id';
      });
      expect(
        () => backupReplayIdempotencyKeyName(broken),
        throwsA(isA<StateError>()),
      );
    });

    test('backupReplayLabel 缺了 ⇒ 抛（补推那一发在记录上必须有个名字）', () {
      final broken = mutate((raw) {
        (raw['waitingOnline'] as Map<String, Object?>).remove(
          'backupReplayLabel',
        );
      });
      expect(
        () => decideBackupReplay(
          broken,
          route: 'backup_replay',
          alreadyReplayed: false,
          replayCount: 0,
          messageId: 'msg-z',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('路线词不属于那两条之一 ⇒ 抛（猜错的方向是提醒两次，或用户什么都收不到）', () {
      expect(
        () => decideBackupReplay(
          contract,
          route: 'invented_route',
          alreadyReplayed: false,
          replayCount: 0,
          messageId: 'msg-z',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('真要补推却没给 messageId ⇒ 抛（拿空键去重等于没去重）', () {
      expect(
        () => decideBackupReplay(
          contract,
          route: 'backup_replay',
          alreadyReplayed: false,
          replayCount: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('契约层的三道判据（validate 必须报出那一条）', () {
    void expectProblem(FnthinkContract broken, String needle, String why) {
      final problems = broken.validate();
      expect(
        problems.any((p) => p.contains(needle)),
        isTrue,
        reason: '$why ⇒ 期望报出「$needle」，实际 $problems',
      );
    }

    test('backupReplayMax 缺了 / 为 0 ⇒ 报', () {
      expectProblem(
        mutate((raw) {
          (raw['limits'] as Map<String, Object?>).remove('backupReplayMax');
        }),
        'limits.backupReplayMax',
        '上限缺了',
      );
      expectProblem(
        mutate((raw) {
          (raw['limits'] as Map<String, Object?>)['backupReplayMax'] = 0;
        }),
        'limits.backupReplayMax',
        '上限为 0 = 这条路径被静默关掉',
      );
    });

    test('幂等键为空 ⇒ 报', () {
      expectProblem(
        mutate((raw) {
          (raw['waitingOnline']
                  as Map<String, Object?>)['backupReplayIdempotencyKey'] =
              '';
        }),
        'backupReplayIdempotencyKey',
        '没有幂等键，同一条消息会被补推两次',
      );
    });

    test('标签为空 ⇒ 报', () {
      expectProblem(
        mutate((raw) {
          (raw['waitingOnline'] as Map<String, Object?>).remove(
            'backupReplayLabel',
          );
        }),
        'backupReplayLabel',
        '补推那一发在记录上要有个名字',
      );
    });
  });
}
