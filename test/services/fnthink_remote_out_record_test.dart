import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/fnthink_remote_execution_record.dart';
import 'package:notice_transmit/services/fnthink_remote_execution.dart';
import 'package:notice_transmit/services/fnthink_remote_out_record.dart';

/// T143 片1（维护者 2026-10-12 裁定 2）：发起端一发送就写一行 out 方向的执行记录。
///
/// 这一层钉的是**这一行能说什么、不能说什么**，不是它排版怎么好看：
/// ① 方向与主语 —— 这一行是"这台设备让别人做事"，与 in 那四行不是一回事；
/// ② 词表 —— `source` 必须是契约那两枚之一（本仓反复砸过的"自己造一个词"）；
/// ③ **覆盖同一行**：一次按下两写（按下 + send 结论），主键不许变，
///    否则历史里会出现"同一发既 pending 又 failed"两行，而那是两次按下；
/// ④ 不许提前说做完了：send accepted 只等于"交出去了"，对面执没执行是**回执**的事，
///    而回执什么时候到、到不到都改不了这一层写下的那一格（片2 之后它会被
///    `remoteOutRowForReceipt` 认领更新，那是另一格作者）。
void main() {
  final contract = FnthinkContract.readFile();
  final at = DateTime.utc(2026, 10, 12, 9, 7, 30);

  FnthinkRemoteExecutionRecord opened() => remoteOutRow(
    execId: 'x-seed-1',
    peer: '8K3FJ6QPTM9WZ4VHNS',
    level: 'L2',
    item: 'listener:start',
    argument: '',
    at: at,
  );

  group('按下那一行', () {
    test('方向是 out、状态是 pending、时间是按下那一刻', () {
      final row = opened();
      expect(row.direction, kFnthinkRemoteDirectionOut);
      expect(row.outgoing, isTrue);
      expect(row.state, RemoteExecutionStates.pending);
      expect(row.unsettled, isTrue, reason: '按下之后还没到终态 —— 界面上"这条还欠一个结论"要读得出来');
      expect(row.createdAt, at.millisecondsSinceEpoch);
      expect(row.peerAddress, '8K3FJ6QPTM9WZ4VHNS');
      expect(row.level, 'L2');
      expect(row.item, 'listener:start');
    });

    test('source 来自契约那两枚，不是这里新造的词', () {
      final row = opened();
      expect(
        contract.remoteExecutionSourcesFor(row.level).contains(row.source),
        isTrue,
        reason:
            '来源是一维封闭词表。写一个不在表里的名字，对面的判定与'
            '本机历史读的是同一张表 ⇒ 两边各判一次，而这一行会变成"谁都不认得"',
      );
      expect(row.source, kFnthinkRemoteOutSource);
    });
  });

  group('send 那一发回来之后', () {
    test('交出去了 ⇒ 还是 pending，且主键与按下时刻都不变', () {
      final row = remoteOutRowAfterSend(opened(), accepted: true);
      expect(
        row.state,
        RemoteExecutionStates.pending,
        reason:
            'send 只证明"交出去了"。把它写成 done 就是替对面编一个终态 —— '
            '而回执那条链目前没有关联键（片2），这一行根本不知道自己被谁确认了',
      );
      expect(row.execId, 'x-seed-1');
      expect(row.createdAt, at.millisecondsSinceEpoch);
      expect(row.reason, '');
    });

    test('没交出去 ⇒ failed + 那枚机器词，仍是同一行', () {
      final row = remoteOutRowAfterSend(
        opened(),
        accepted: false,
        reason: 'network',
      );
      expect(row.state, RemoteExecutionStates.failed);
      expect(row.unsettled, isFalse, reason: '失败是终态：不许留一条永远待办的行');
      expect(row.reason, 'network');
      expect(row.execId, 'x-seed-1');
      expect(row.direction, kFnthinkRemoteDirectionOut);
    });

    test('两写落进**同一行**（toRow 的主键一致，历史里不会长出两条）', () {
      final open = opened();
      final settled = remoteOutRowAfterSend(
        open,
        accepted: false,
        reason: 'locked',
      );
      expect(settled.toRow()['exec_id'], open.toRow()['exec_id']);
      expect(
        settled.toRow().keys.toList(),
        open.toRow().keys.toList(),
        reason: '行的列集合不许变：写的是同一张表的同一条记录',
      );
    });
  });

  group('这一层不认识的东西（不许长回来）', () {
    test('不带凭据：种子／口令／哈希一个键都不进这一行', () {
      final keys = opened().toRow().keys.toList();
      for (final forbidden in const ['key', 'totp', 'secret', 'seed', 'hash']) {
        expect(
          keys.where((k) => k.contains(forbidden)),
          isEmpty,
          reason:
              '契约 `execution.forbiddenFields` 同一份黑名单：'
              '这些对"这条指令后来怎么了"毫无用处，进来就等于给每个能读本机库的人发钥匙',
        );
      }
    });
  });

  group('回执认领发起端那一行（T143 片2，唯一作者 remoteOutRowForReceipt）', () {
    FnthinkRemoteExecutionRecord outRow(String state) =>
        FnthinkRemoteExecutionRecord(
          execId: 'RX-1',
          direction: kFnthinkRemoteDirectionOut,
          peerAddress: 'peer-a',
          level: 'L2',
          item: 'listener:start',
          argument: 'webhook_acme',
          state: state,
          source: 'fnthink',
          createdAt: 1700000000000,
          reason: 'network',
        );
    FnthinkRemoteExecutionRecord inRow() => const FnthinkRemoteExecutionRecord(
      execId: 'RX-1',
      direction: kFnthinkRemoteDirectionIn,
      peerAddress: 'peer-a',
      level: 'L2',
      item: 'listener:start',
      argument: '',
      state: RemoteExecutionStates.executing,
      source: 'fnthink',
      createdAt: 1700000000000,
    );
    RemoteReceipt receipt(String? state, {String exec = 'RX-1'}) =>
        RemoteReceipt(
          result: state == null
              ? remoteExecutionStartedReceipt(contract)
              : remoteExecutionFinishedReceipt(contract),
          level: 'L2',
          item: 'listener:start',
          argument: 'webhook_acme',
          state: state,
          exec: exec,
        );

    test('pending 直接收到终态 ⇒ 合成那两步合法迁移（不让那一行停在"待执行"）', () {
      final moved = remoteOutRowForReceipt(
        contract: contract,
        receipt: receipt(RemoteExecutionStates.done),
        row: outRow(RemoteExecutionStates.pending),
      );
      expect(moved!.state, RemoteExecutionStates.done);
      expect(
        moved.result,
        remoteExecutionFinishedReceipt(contract),
        reason: '界面读的是 result 那一格',
      );
    });

    test('没带关联键 ⇒ null（不猜：按 level/item/argument 配最老那条未终结行是歧义版）', () {
      expect(
        remoteOutRowForReceipt(
          contract: contract,
          receipt: receipt(RemoteExecutionStates.done, exec: ''),
          row: outRow(RemoteExecutionStates.pending),
        ),
        isNull,
      );
    });

    test('没有那一行 / 那一行是 in 方向 ⇒ null（外部回执不许插手本机执行链）', () {
      expect(
        remoteOutRowForReceipt(
          contract: contract,
          receipt: receipt(RemoteExecutionStates.done),
        ),
        isNull,
      );
      expect(
        remoteOutRowForReceipt(
          contract: contract,
          receipt: receipt(RemoteExecutionStates.done),
          row: inRow(),
        ),
        isNull,
      );
    });

    test('第一段 ⇒ 只走一步到 executing；重复的第一段 ⇒ null（不再改）', () {
      expect(
        remoteOutRowForReceipt(
          contract: contract,
          receipt: receipt(null),
          row: outRow(RemoteExecutionStates.pending),
        )!.state,
        RemoteExecutionStates.executing,
      );
      expect(
        remoteOutRowForReceipt(
          contract: contract,
          receipt: receipt(null),
          row: outRow(RemoteExecutionStates.executing),
        ),
        isNull,
      );
    });

    test('已经到终态的那一行收到迟到的回执 ⇒ null（终态不可逆，状态机两次都不认）', () {
      for (final state in const [
        RemoteExecutionStates.done,
        RemoteExecutionStates.failed,
        RemoteExecutionStates.cancelled,
      ]) {
        expect(
          remoteOutRowForReceipt(
            contract: contract,
            receipt: receipt(RemoteExecutionStates.failed),
            row: outRow(state),
          ),
          isNull,
          reason: '$state 是终态：一条迟到的 failed 不该把它改写',
        );
      }
    });

    test('回执里那枚 state 不在词表 ⇒ null（不落回第一段编一个状态）', () {
      expect(
        remoteOutRowForReceipt(
          contract: contract,
          receipt: receipt('whatever'),
          row: outRow(RemoteExecutionStates.pending),
        ),
        isNull,
      );
    });

    test('只动 state 与 result，其余逐字留原样（那一行是"我按下的那一发"）', () {
      final at = outRow(RemoteExecutionStates.pending);
      final moved = remoteOutRowForReceipt(
        contract: contract,
        receipt: receipt(RemoteExecutionStates.cancelled),
        row: at,
      )!;
      expect(moved.execId, at.execId);
      expect(moved.direction, at.direction);
      expect(moved.peerAddress, at.peerAddress);
      expect(moved.level, at.level);
      expect(moved.item, at.item);
      expect(moved.argument, at.argument);
      expect(moved.source, at.source);
      expect(moved.createdAt, at.createdAt);
      // send 没交出去时那枚理由（`network`）要留着：回执说的是对面那一段，
      // 而"我这一发在路上停过"是另一件事，抹掉它等于把账改轻。
      expect(moved.reason, at.reason);
    });
  });
}
