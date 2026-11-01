import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/pages/fnthink_peers_page.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';
import 'package:notice_transmit/services/fnthink_credential_store.dart';
import 'package:notice_transmit/services/fnthink_pairing_lifecycle.dart';
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
final _contract = FnthinkContract.readFile();

/// `flutter_secure_storage` 与 `getFnthinkIdentity` 共用一枚桩（与设置页 harness 同一形状）。
void _stubSecureDisk(Map<String, String?> disk) {
  stubNativeChannels(
    onCall: (call) async {
      switch (call.method) {
        case 'read':
          return disk[call.arguments['key'] as String];
        case 'write':
          disk[call.arguments['key'] as String] =
              call.arguments['value'] as String?;
          return null;
        case 'delete':
          disk.remove(call.arguments['key'] as String);
          return null;
        case 'getFnthinkIdentity':
          return <String, Object?>{
            'publicKey': 'AAAApublicKeyBytesForTests',
            'plan': 'androidKeyStoreEd25519',
            'keystoreBacked': true,
          };
        default:
          return null;
      }
    },
  );
}

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
    // T177：404 翻成「服务器没有对端状态读口」，不再把裸状态码摊给用户。
    expect(note, contains('服务器没有对端状态读口'));
    expect(note, isNot(contains('404')));
  });

  group('本机身份卡（T214）', () {
    /// 名单那一格与身份卡都在 ListView 里；卡在名单之后，不滚到它就没被 build。
    /// ⚠ 不用 `scrollUntilVisible`：它默认取 `find.byType(Scrollable)`，而页里不止一个
    /// （SelectableText 自己也是）⇒ "Too many elements"。
    Future<void> scrollTo(WidgetTester tester, Finder target) async {
      if (target.evaluate().isEmpty) {
        await tester.dragUntilVisible(
          target,
          find.byType(ListView),
          const Offset(0, -240),
          maxIteration: 40,
        );
      }
      await tester.pumpAndSettle();
    }

    Map<String, String?> fullDisk() => {
      FnthinkCredentialStore.addressCodeKey: FnthinkAddressCode.generate(
        _contract,
      ).value,
      FnthinkCredentialStore.pairingCodeKey: FnthinkPairingCode.generate(
        _contract,
      ).value,
      FnthinkCredentialStore.pairingArmedAtKey:
          '${DateTime.now().millisecondsSinceEpoch}',
    };

    testWidgets('配对页读得到本机地址码与口令；两枚 destructive 留设置页', (tester) async {
      final disk = fullDisk();
      _stubSecureDisk(disk);
      await _pump(tester, () async => _ok(const []));
      final card = find.byKey(const ValueKey('fnthink-address-code'));
      await scrollTo(tester, card);

      expect(card, findsOneWidget);
      expect(
        find.text(disk[FnthinkCredentialStore.addressCodeKey]!),
        findsOneWidget,
      );
      expect(
        find.text(disk[FnthinkCredentialStore.pairingCodeKey]!),
        findsOneWidget,
      );
      // 撤销口令与重置地址码是管理动作，配对现场只挂出/重新生成。
      expect(find.byKey(const ValueKey('fnthink-reset-code')), findsNothing);
      expect(
        find.byKey(const ValueKey('fnthink-revoke-pairing')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('fnthink-pairing-peers-hint')),
        findsOneWidget,
        reason: '配对页要说清"对面要的就是这两样"，否则用户不知道该抄哪一串',
      );
    });

    testWidgets('已被对面用过那一档在配对页照样显示', (tester) async {
      SharedPreferences.setMockInitialValues({kFnthinkPairingConsumedKey: 1});
      _stubSecureDisk(fullDisk());
      await _pump(tester, () async => _ok(const []));
      final row = find.byKey(const ValueKey('fnthink-pairing-lifecycle'));
      await scrollTo(tester, row);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(FnthinkPeersPage)),
      );
      expect(
        tester.widget<Text>(row).data,
        l10n.fnthinkPairingLifecycleConsumed,
        reason: '配对现场最容易撞上的就是"这枚已经用过了"，配对页不能把这一档藏起来',
      );
    });

    testWidgets('已过期那一档在配对页照样显示', (tester) async {
      final disk = fullDisk();
      disk[FnthinkCredentialStore.pairingArmedAtKey] = '1';
      _stubSecureDisk(disk);
      await _pump(tester, () async => _ok(const []));
      final row = find.byKey(const ValueKey('fnthink-pairing-lifecycle'));
      await scrollTo(tester, row);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(FnthinkPeersPage)),
      );
      expect(
        tester.widget<Text>(row).data,
        l10n.fnthinkPairingLifecycleExpired,
      );
    });

    testWidgets('配对页也能挂出一枚口令（挂出后当场读到新码）', (tester) async {
      // 挂出那一枚在卡的最下方：默认 800×600 的视口里拖到它也只是"被 build 了"，
      // 中心点仍在屏外 ⇒ tap 会打空。把这一发的视口调高，让那一枚真的可见。
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final disk = <String, String?>{};
      _stubSecureDisk(disk);
      await _pump(tester, () async => _ok(const []));
      final arm = find.byKey(const ValueKey('fnthink-arm-pairing'));
      await scrollTo(tester, arm);

      await tester.tap(arm);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('fnthink-pairing-code-value')),
        findsOneWidget,
        reason: '挂出之后本机那一枚必须当场显示（页面不缓存，动作后重取一次）',
      );
      expect(
        disk.containsKey(FnthinkCredentialStore.pairingCodeKey),
        isTrue,
        reason: '口令只该在本机加密盘里挂出，不是画在屏幕上的临时值',
      );
    });
  });
}
