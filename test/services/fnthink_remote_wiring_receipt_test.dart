import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/models/fnthink_remote_execution_record.dart';
import 'package:notice_transmit/services/fnthink_l2_actions.dart';
import 'package:notice_transmit/services/fnthink_l3_settings.dart';
import 'package:notice_transmit/services/fnthink_remote_command_handler.dart';
import 'package:notice_transmit/services/fnthink_remote_execution.dart';
import 'package:notice_transmit/services/fnthink_remote_runner.dart';
import 'package:notice_transmit/services/fnthink_remote_settings.dart';
import 'package:notice_transmit/services/fnthink_remote_wiring.dart';
import 'package:notice_transmit/services/remote_credential_store.dart';
import 'package:notice_transmit/services/remote_execution_notifier.dart';
import 'package:notice_transmit/services/secure_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 发起端认领回执那一格（T143 片2）：**接线**层，不是判定层。
///
/// 这一组只钉三件事，而它们都不是 `remoteOutRowForReceipt` 那条纯函数能表达的：
///  ① 一条回执**不会按通知弹出来**（回 true）—— 少了这一格，用户看到的是
///     "对面回了我一句话"，而那句话其实是"你那条我办完了"；
///  ② 认领动的是**发起端那一行**（out 方向），且只动 state/result 两格；
///  ③ 回执那一格**不吞指令**：`FRX1:` 那条照旧走判定（这里用"开关关着 ⇒ 留痕一行
///     `switch-off`"来证明判定确实被走到了）。
///
/// ⚠ 为什么这里敢用真 `RemoteCredentialStore` / 真 `FnthinkRemoteSettings`：
///   回执那一路在 `recognizer.parse` **之前**就返回了，那些协作者一次都不会被调到。
///   反过来这也是这一组的牙 —— 哪一天回执被误路由进判定，那一路会去碰
///   没有平台通道的真存储，用例当场抛红，而不是绿着把"回执弹成通知"放过去。
class _NoopL2 implements FnthinkL2Executor {
  final List<String> calls = [];

  @override
  Future<FnthinkL2Result> setListener({required bool enabled}) async {
    calls.add('setListener($enabled)');
    return const FnthinkL2Result.ok();
  }

  @override
  Future<FnthinkL2Result> toggleChannel(RemoteChannelTarget target) async =>
      const FnthinkL2Result.ok();

  @override
  Future<FnthinkL2Result> pushDeviceState() async => const FnthinkL2Result.ok();

  @override
  Future<String?> reportNotifications(int count) async => null;

  @override
  Future<FnthinkL2Result> ringAlert() async => const FnthinkL2Result.ok();

  @override
  Future<({String? payload, String? reason})> searchSms(String keyword) async =>
      (payload: null, reason: 'unused');

  @override
  Future<({String? payload, String? reason})> searchCalls(
    String keyword,
  ) async => (payload: null, reason: 'unused');

  @override
  Future<({String? payload, String? reason})> searchContacts(
    String keyword,
  ) async => (payload: null, reason: 'unused');

  @override
  Future<({String? payload, String? reason})> getLocation() async =>
      (payload: null, reason: 'unused');

  @override
  Future<({String? payload, String? reason})> snapPhoto() async =>
      (payload: null, reason: 'unused');

  @override
  Future<({bool ok, String? reason})> launchApp(String name) async =>
      (ok: false, reason: 'unused');
}

class _NoopL3 implements FnthinkL3Executor {
  @override
  Future<bool> grant(FnthinkL3Setting setting) async => true;

  @override
  Future<bool> toggle(FnthinkL3Setting setting) async => true;
}

FnthinkInboxMessage _message(String body) => FnthinkInboxMessage(
  messageId: 'm-1',
  sender: 'peer-a',
  type: 'notice',
  item: '',
  title: '',
  body: body,
  receivedAt: 1760000000000,
);

/// 发起端那一行（out）。默认 `pending` —— send 交出去之后就是这个状态。
FnthinkRemoteExecutionRecord _outRow({
  String execId = 'RX-1',
  String state = RemoteExecutionStates.pending,
}) => FnthinkRemoteExecutionRecord(
  execId: execId,
  direction: kFnthinkRemoteDirectionOut,
  peerAddress: 'peer-a',
  level: 'L2',
  item: 'listener:start',
  argument: '',
  state: state,
  source: 'fnthink',
  createdAt: 1700000000000,
);

FnthinkRemoteExecutionRecord _inRow({String execId = 'IN-1'}) =>
    FnthinkRemoteExecutionRecord(
      execId: execId,
      direction: kFnthinkRemoteDirectionIn,
      peerAddress: 'peer-a',
      level: 'L2',
      item: 'listener:start',
      argument: '',
      state: RemoteExecutionStates.executing,
      source: 'fnthink',
      createdAt: 1700000000000,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final contract = FnthinkContract.readFile();
  late List<FnthinkRemoteExecutionRecord> saved;
  late List<(String, RemoteReceipt)> replies;
  late Map<String, FnthinkRemoteExecutionRecord> table;
  late RemoteCommandWiring wiring;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    saved = [];
    replies = [];
    table = {};
    final runner = RemoteCommandRunner(
      contract: contract,
      windowSeconds: () async => 0,
      l2: _NoopL2(),
      l3: _NoopL3(),
      saveRecord: (record) async => saved.add(record),
      sendReceipt: (peer, receipt) async {
        replies.add((peer, receipt));
        return true;
      },
      sendReport: (peer, action, payload) async => true,
      now: () => DateTime.utc(2026, 10, 14),
    );
    addTearDown(runner.dispose);
    wiring = RemoteCommandWiring(
      contract: contract,
      recognizer: RemoteCommandRecognizer(
        contract: contract,
        settings: FnthinkRemoteSettings(contract: contract),
        credentials: RemoteCredentialStore(
          contract: contract,
          storage: SecureStorageService(),
          clockMs: () => 1700000000000,
        ),
        grantForSender: (peer) async =>
            FnthinkGrant(maxLevel: 'L1', items: const []),
      ),
      runner: runner,
      notifier: const RemoteExecutionNotifier(),
      saveRecord: (record) async {
        saved.add(record);
        table[record.execId] = record;
      },
      loadRecord: (execId) async => table[execId],
    );
  });

  group('T141①：拒的那一档留痕带消息关联', () {
    test('onCommand 收到的指令被拒 ⇒ 记录带那条收件的消息号', () async {
      // grantForSender 交的是 L1 ⇒ 一条 L2 指令必在第四道被拒（理由不钉，那不是本条的事）。
      final wire = RemoteCommandEnvelope.encode(
        level: 'L2',
        item: 'listener:start',
      );
      expect(await wiring.onCommand(_message(wire)), isTrue);
      expect(saved, hasLength(1));
      expect(saved.single.state, RemoteExecutionStates.failed);
      expect(
        saved.single.messageId,
        'm-1',
        reason: '关联丢了 ⇒ 收件历史页那行永远画不出「被拒/原因」',
      );
    });
  });

  group('回执走认领那一格', () {
    test('第二段回执 ⇒ 本机那一行被更新，且**不按通知弹出来**', () async {
      table['RX-1'] = _outRow();
      final wire = RemoteReceiptEnvelope.encode(
        result: remoteExecutionFinishedReceipt(contract),
        level: 'L2',
        item: 'listener:start',
        state: RemoteExecutionStates.done,
        exec: 'RX-1',
      );

      expect(await wiring.onCommand(_message(wire)), isTrue);
      expect(saved, hasLength(1));
      expect(saved.single.execId, 'RX-1');
      expect(saved.single.state, RemoteExecutionStates.done);
      expect(saved.single.result, remoteExecutionFinishedReceipt(contract));
    });

    test('第一段回执 ⇒ pending 走一步到 executing（不越级写终态）', () async {
      table['RX-1'] = _outRow();
      final wire = RemoteReceiptEnvelope.encode(
        result: remoteExecutionStartedReceipt(contract),
        level: 'L2',
        item: 'listener:start',
        exec: 'RX-1',
      );

      await wiring.onCommand(_message(wire));
      expect(saved.single.state, RemoteExecutionStates.executing);
    });

    test('没带关联键（对面是旧版）⇒ 一行都不写，但仍然不弹', () async {
      table['RX-1'] = _outRow();
      final wire = RemoteReceiptEnvelope.encode(
        result: remoteExecutionFinishedReceipt(contract),
        level: 'L2',
        item: 'listener:start',
        state: RemoteExecutionStates.done,
      );

      expect(
        await wiring.onCommand(_message(wire)),
        isTrue,
        reason: '一段回执不是一条消息，认领不上也不该弹成通知',
      );
      expect(saved, isEmpty, reason: '猜不得：宁可停在 pending');
    });

    test('本机没有那一行 ⇒ 不写、不弹（这台可能只收不发）', () async {
      final wire = RemoteReceiptEnvelope.encode(
        result: remoteExecutionStartedReceipt(contract),
        level: 'L2',
        item: 'listener:start',
        exec: 'RX-unknown',
      );

      expect(await wiring.onCommand(_message(wire)), isTrue);
      expect(saved, isEmpty);
    });

    test('认领到的那一行是 in 方向 ⇒ 外部回执不许插手本机执行链', () async {
      table['RX-1'] = _inRow(execId: 'RX-1');
      final wire = RemoteReceiptEnvelope.encode(
        result: remoteExecutionFinishedReceipt(contract),
        level: 'L2',
        item: 'listener:start',
        state: RemoteExecutionStates.done,
        exec: 'RX-1',
      );

      expect(await wiring.onCommand(_message(wire)), isTrue);
      expect(saved, isEmpty);
    });

    test('重复的第二段回执 ⇒ 幂等，那一行不再改', () async {
      table['RX-1'] = _outRow(state: RemoteExecutionStates.done);
      final wire = RemoteReceiptEnvelope.encode(
        result: remoteExecutionFinishedReceipt(contract),
        level: 'L2',
        item: 'listener:start',
        state: RemoteExecutionStates.failed,
        exec: 'RX-1',
      );

      await wiring.onCommand(_message(wire));
      expect(saved, isEmpty, reason: '已经 done 的那一行不该被一条迟到的 failed 改写');
    });
  });

  group('回执那一格不吞别的路', () {
    test('一条普通消息照旧回 false（照常按通知显示）', () async {
      expect(await wiring.onCommand(_message('今天天气不错')), isFalse);
      expect(saved, isEmpty);
    });

    test('一条指令（FRX1:）照旧走判定 ⇒ 留痕那一行是 in 方向 + switch-off', () async {
      // 开关没开（`setUp` 里 mock 值是空的）⇒ 判定给「拒」，理由逐字落在留痕里。
      final wire = RemoteCommandEnvelope.encode(
        level: 'L2',
        item: 'listener:start',
        exec: 'RX-1',
      );

      expect(await wiring.onCommand(_message(wire)), isTrue);
      expect(saved, hasLength(1));
      expect(saved.single.direction, kFnthinkRemoteDirectionIn);
      expect(saved.single.reason, 'switch-off');
      expect(table.containsKey('RX-1'), isFalse, reason: '指令那一发不该被当成回执认领掉');
      // 被拒那一档的回执也要**带回那枚关联键**：对面那一行否则停在"待执行"，
      // 而它其实已经知道没成（发起端读的是回执里那一格，不是自己猜）。
      expect(replies, hasLength(1));
      expect(replies.single.$2.exec, 'RX-1');
    });
  });
}
