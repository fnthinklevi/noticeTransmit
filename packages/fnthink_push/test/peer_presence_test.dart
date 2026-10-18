import 'dart:convert';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:test/test.dart';

/// T156 片2：设备侧读「对端上次收取」这一发。
///
/// 这里不判"谁在线"——三态与年龄的唯一作者是服务端。这个文件钉的是**设备侧怎么读**：
///  ① 载荷为空、`type`/`target` 从契约来（不接受点名）；
///  ② 三态与两个时间字段原样落进结果；
///  ③ 空列表是成功（"没有一台共享"），缺 `peers` 键才是失败（"没读到"）—— 两者不许塌成一句；
///  ④ 形状不认识就整读失败：词表外的状态、unknown 带年龄、online 缺年龄、重复地址码都不收。
class _Harness {
  _Harness(this.contract);

  final FnthinkContract contract;
  final List<Map<String, Object?>> sent = [];
  FnthinkReply reply = const FnthinkReply(status: 200, body: {});
  Object? throws;

  Future<FnthinkReply> transport(Map<String, Object?> envelope) async {
    sent.add(envelope);
    if (throws != null) throw throws!;
    return reply;
  }

  FnthinkReceiveKernel kernel() => FnthinkReceiveKernel(
    contract: contract,
    addressCode: _self,
    signer: (_) async => 'sig',
    transport: transport,
    nonceFactory: () => 'n${sent.length + 1}',
  );
}

const _self = '8K3FJ6QPTM9WZ4VHNS';
const _peer = '8KMNPQRSTVWX999777';
const _peer2 = '8KAAAABBBBCCCCDDDD';
const _peer3 = '8KEEEFFFFGGGGHHHH';

void main() {
  late FnthinkContract contract;

  setUp(() => contract = FnthinkContract.readFile());

  Map<String, Object?> entry({
    required String address,
    required String presence,
    int? lastSeenAt,
    int? ageSeconds,
  }) {
    final readout = contract.peerReadout;
    return {
      readout.addressCodeField: address,
      readout.presenceField: presence,
      readout.lastSeenField: lastSeenAt,
      readout.ageField: ageSeconds,
    };
  }

  Map<String, Object?> body(List<Object?> peers) => {
    contract.peerReadout.peersField: peers,
    'serverTime': 1780000000000,
  };

  test('载荷为空、类型与目标都从契约来（不接受点名）', () {
    final h = _Harness(contract);
    final fields = h.kernel().peerPresenceFields(nonce: 'n1');
    expect(fields['body'], '{}');
    expect(
      fields['type'],
      contract.str(const ['clientEvents', 'peerPresence', 'messageType']),
    );
    expect(fields['target'], _self);
    expect(fields['nonce'], 'n1');
  });

  test('三态与两个时间字段原样落到结果', () async {
    final h = _Harness(contract);
    h.reply = FnthinkReply(
      status: 200,
      body: body([
        entry(
          address: _peer,
          presence: contract.presenceOnlineState,
          lastSeenAt: 1780000000000,
          ageSeconds: 12,
        ),
        entry(
          address: _peer2,
          presence: contract.presenceOfflineState,
          lastSeenAt: 1779999999000,
          ageSeconds: 90,
        ),
        entry(address: _peer3, presence: contract.presenceUnknownState),
      ]),
    );
    final result = await h.kernel().peerPresence();
    expect(result.ok, isTrue);
    expect(result.peers, hasLength(3));
    expect(result.peerOf(_peer)!.ageSeconds, 12);
    expect(result.peerOf(_peer2)!.presence, contract.presenceOfflineState);
    expect(result.peerOf(_peer3)!.ageSeconds, isNull);
    expect(result.peerOf(_peer3)!.lastSeenAt, isNull);
    expect(result.peerOf('8KZZZZZZZZZZZZZZZZ'), isNull);
  });

  test('空列表是成功：读到了，只是没有一台共享', () async {
    final h = _Harness(contract);
    h.reply = FnthinkReply(status: 200, body: body(const []));
    final result = await h.kernel().peerPresence();
    expect(result.ok, isTrue);
    expect(result.peers, isEmpty);
  });

  test('缺 peers 键是失败，不是空清单', () async {
    final h = _Harness(contract);
    h.reply = const FnthinkReply(
      status: 200,
      body: {'serverTime': 1780000000000},
    );
    final result = await h.kernel().peerPresence();
    expect(result.ok, isFalse);
    expect(result.peers, isNull);
    expect(result.reason, contains('peer-presence-unparsable'));
  });

  test('词表外的状态整读失败', () async {
    final h = _Harness(contract);
    h.reply = FnthinkReply(
      status: 200,
      body: body([entry(address: _peer, presence: 'idle')]),
    );
    final result = await h.kernel().peerPresence();
    expect(result.ok, isFalse);
    expect(result.reason, contains('peer-presence-unparsable'));
  });

  test('unknown 带年龄整读失败', () async {
    final h = _Harness(contract);
    h.reply = FnthinkReply(
      status: 200,
      body: body([
        entry(
          address: _peer,
          presence: contract.presenceUnknownState,
          lastSeenAt: 1780000000000,
          ageSeconds: 0,
        ),
      ]),
    );
    final result = await h.kernel().peerPresence();
    expect(result.ok, isFalse);
    expect(result.reason, contains('peer-presence-shape'));
  });

  test('online 缺年龄整读失败', () async {
    final h = _Harness(contract);
    h.reply = FnthinkReply(
      status: 200,
      body: body([
        entry(
          address: _peer,
          presence: contract.presenceOnlineState,
          lastSeenAt: 1780000000000,
        ),
      ]),
    );
    final result = await h.kernel().peerPresence();
    expect(result.ok, isFalse);
    expect(result.reason, contains('peer-presence-shape'));
  });

  test('同一地址码出现两次整读失败', () async {
    final h = _Harness(contract);
    h.reply = FnthinkReply(
      status: 200,
      body: body([
        entry(
          address: _peer,
          presence: contract.presenceOnlineState,
          lastSeenAt: 1780000000000,
          ageSeconds: 1,
        ),
        entry(
          address: _peer,
          presence: contract.presenceOfflineState,
          lastSeenAt: 1779999999000,
          ageSeconds: 90,
        ),
      ]),
    );
    final result = await h.kernel().peerPresence();
    expect(result.ok, isFalse);
    expect(result.reason, contains('peer-presence-unparsable'));
  });

  test('传输异常是 transportError，不是"没有共享"', () async {
    final h = _Harness(contract);
    h.throws = StateError('boom');
    final result = await h.kernel().peerPresence();
    expect(result.status, FnthinkPollStatus.transportError);
    expect(result.ok, isFalse);
    expect(result.peers, isNull);
  });

  test('签名信封里的 body 是空对象，并且真的发出去了', () async {
    final h = _Harness(contract);
    h.reply = FnthinkReply(status: 200, body: body(const []));
    await h.kernel().peerPresence();
    expect(h.sent, hasLength(1));
    final fields = h.sent.single['fields']! as Map<String, Object?>;
    expect(fields['body'], '{}');
    expect(jsonDecode(fields['body']! as String), isEmpty);
  });
}
