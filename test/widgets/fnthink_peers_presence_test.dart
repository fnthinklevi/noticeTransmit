import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/pages/fnthink_peers_page.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';
import 'package:notice_transmit/services/fnthink_receive_coordinator.dart';
import 'package:notice_transmit/services/fnthink_receiver_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_setup.dart';

/// T156 片2：设备名单那一行上的对端状态。
///
/// 这一格的四档必须各自可见：在线、离线、unknown（还没上过线）、notShared（对方没共享）；
/// 读取失败是**整张名单**的一档，不许把每一台画成离线。
const _peer = 'PEER00000000000001';

FnthinkPeerPresenceResult _ok(List<FnthinkPeerPresence> rows) =>
    FnthinkPeerPresenceResult(
      status: FnthinkPollStatus.ok,
      peers: rows,
      signedWhileUncalibrated: false,
    );

FnthinkPeersDeps _deps(
  Future<FnthinkPeerPresenceResult> Function() loadPresence,
) {
  final loader = FnthinkContractLoader(
    readAsset: (_) async => File('protocol/fnthink-v1.json').readAsStringSync(),
  );
  final coordinator = FnthinkReceiveCoordinator(
    contracts: loader,
    signer: _NoSigner(),
    persist: (_) async => true,
    serviceFactory: (_) => throw StateError('本用例不走收货'),
  );
  return FnthinkPeersDeps(
    contracts: loader,
    coordinator: coordinator,
    loadPeers: () async => const [
      FnthinkPeer(
        peerAddress: _peer,
        publicKey: 'key',
        level: 'L1',
        grantedAt: 0,
      ),
    ],
    loadPresence: loadPresence,
  );
}

Future<void> _pump(
  WidgetTester tester,
  Future<FnthinkPeerPresenceResult> Function() loadPresence,
) async {
  await tester.pumpWidget(
    AppRoot(
      locale: const Locale('zh'),
      dark: false,
      home: FnthinkPeersPage(deps: _deps(loadPresence)),
    ),
  );
  await tester.pumpAndSettle();
}

String? _presenceText(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('fnthink-peer-presence-$_peer'));
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Text>(finder).data;
}

class _NoSigner implements FnthinkIdentitySigner {
  @override
  Future<String> call(List<int> canonicalBytes) async => 'AAAAc2ln';

  @override
  Future<bool> probe() async => false;

  @override
  Future<String?> publicKey() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    stubNativeChannels();
  });

  testWidgets('在线：那一行写「上次收取 12 秒前」', (tester) async {
    await _pump(
      tester,
      () async => _ok(const [
        FnthinkPeerPresence(
          addressCode: _peer,
          presence: 'online',
          lastSeenAt: 1,
          ageSeconds: 12,
        ),
      ]),
    );
    expect(_presenceText(tester), '在线 · 上次收取 12 秒前');
  });

  testWidgets('离线：同一把尺说「上次收取 1 分钟前」', (tester) async {
    await _pump(
      tester,
      () async => _ok(const [
        FnthinkPeerPresence(
          addressCode: _peer,
          presence: 'offline',
          lastSeenAt: 1,
          ageSeconds: 90,
        ),
      ]),
    );
    expect(_presenceText(tester), '离线 · 上次收取 1 分钟前');
  });

  testWidgets('unknown：说「还没上过线」，不画成离线', (tester) async {
    await _pump(
      tester,
      () async => _ok(const [
        FnthinkPeerPresence(addressCode: _peer, presence: 'unknown'),
      ]),
    );
    final text = _presenceText(tester);
    expect(text, '未知 · 还没上过线');
    expect(text, isNot(contains('离线')));
  });

  testWidgets('notShared：读到了但对方没共享，不画成离线', (tester) async {
    await _pump(tester, () async => _ok(const []));
    final text = _presenceText(tester);
    expect(text, '对方没有共享在线状态');
    expect(text, isNot(contains('离线')));
  });

  testWidgets('读取失败：只画卡片级一句，不给每一行编状态', (tester) async {
    await _pump(
      tester,
      () async => const FnthinkPeerPresenceResult(
        status: FnthinkPollStatus.failed,
        reason: 'peer-presence-http:404',
        signedWhileUncalibrated: false,
      ),
    );
    expect(
      find.byKey(const ValueKey('fnthink-peer-presence-failed')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('fnthink-peer-presence-$_peer')),
      findsNothing,
    );
    final note = tester
        .widget<Text>(
          find.byKey(const ValueKey('fnthink-peer-presence-failed')),
        )
        .data;
    expect(note, contains('404'));
  });
}
