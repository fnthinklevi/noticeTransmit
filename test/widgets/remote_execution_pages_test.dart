import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notice_transmit/services/fnthink_settings.dart';
import 'package:notice_transmit/pages/fnthink_consent_gate.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/models/fnthink_remote_execution_record.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';
import 'package:notice_transmit/pages/fnthink_send_page.dart';
import 'package:notice_transmit/pages/remote_history_page.dart';
import 'package:notice_transmit/widgets/app_root.dart';

/// 远程执行 片3b-2 的**页面**契约（发送页 + 历史页）。
///
/// 这一组钉的是四件：
///  ① 契约读不到 ⇒ 整页只显示那一句话，不给填（凭据/档位全从契约来）；
///  ② 名单空着 / 没选中 / 没选动作 / L3 没带凭据 ⇒ **不许发**，且每一句都不是
///     "发不出去"这一种（合成一句就是那个点了没反应的按钮）；
///  ③ 已终态的那一行**不给**取消按钮（点了没反应正是要防的形状）；
///  ④ 三种"没有记录"分开说（还没读 / 读失败 / 真的一个都没有）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // T118：这一页那两档都过同意门 ⇒ 种上同意，并给门一份同步读出来的契约
    //（widget 测试里真 IO 的 future 不会完成）。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'fnthink.consent_version': 1,
    });
    debugFnthinkConsentSettingsOverride = FnthinkSettings(
      contract: FnthinkContract.readFile(),
    );
  });
  tearDown(() => debugFnthinkConsentSettingsOverride = null);

  final contract = FnthinkContract.readFile();
  const peer = FnthinkPeer(
    peerAddress: '8K3FJ6QPTM9WZ4VHNS',
    publicKey: 'pk-AAAA',
    level: 'L2',
    grantedAt: 1700000000000,
  );

  Future<void> pumpSend(
    WidgetTester tester, {
    List<FnthinkPeer>? peers = const [peer],
    Future<FnthinkContract> Function()? contractOf,
    Future<FnthinkSendResult> Function({
      required String peer,
      required String title,
      required String text,
    })?
    send,
  }) async {
    tester.view.physicalSize = const Size(1080, 5400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: FnthinkSendPage(
          // 这一组用例走的是**指令档**（T98 片④ 之后它不再是一张独立的页，而是那张共用
          // 发送页停在哪一档）。纯文本那一档的证据在 `fnthink_settings_page_test.dart`。
          initialTier: FnthinkSendTier.command,
          deps: FnthinkSendDeps(
            loadPeers: () async => peers ?? const <FnthinkPeer>[],
            send:
                send ??
                ({
                  required String peer,
                  required String title,
                  required String text,
                }) async =>
                    const FnthinkSendResult(status: FnthinkSendStatus.accepted),
            contractOf: contractOf ?? () async => contract,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpHistory(
    WidgetTester tester, {
    required Future<List<FnthinkRemoteExecutionRecord>?> Function(String?)
    loadRecords,
    Future<bool> Function(String)? remove,
    Future<FnthinkContract> Function()? contractOf,
  }) async {
    tester.view.physicalSize = const Size(1080, 5400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: RemoteHistoryPage(
          deps: RemoteHistoryDeps(
            loadRecords: loadRecords,
            removeRecord: remove ?? (id) async => true,
            contractOf: contractOf ?? () async => contract,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FnthinkRemoteExecutionRecord record(
    String id, {
    String state = 'pending',
    String direction = kFnthinkRemoteDirectionIn,
    String peerAddress = '8K3FJ6QPTM9WZ4VHNS',
    String source = 'fnthink',
  }) => FnthinkRemoteExecutionRecord(
    execId: id,
    direction: direction,
    peerAddress: peerAddress,
    level: 'L2',
    item: 'listener:start',
    argument: '',
    state: state,
    source: source,
    createdAt: 1700000000000,
  );

  group('发送页：契约读不到就整页只显示那一句', () {
    testWidgets('契约抛错 ⇒ 显示那句，不给填', (tester) async {
      await pumpSend(
        tester,
        contractOf: () async =>
            throw const FnthinkContractUnavailable('missing'),
      );
      expect(
        find.byKey(const ValueKey('remote-send-contract-error')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('remote-send-submit')), findsNothing);
    });
  });

  group('发送页：没填齐就不许发，且每条挡住的理由不是同一句', () {
    testWidgets('没选中对端 ⇒ 不发', (tester) async {
      var called = false;
      await pumpSend(
        tester,
        send:
            ({
              required String peer,
              required String title,
              required String text,
            }) async {
              called = true;
              return const FnthinkSendResult(
                status: FnthinkSendStatus.accepted,
              );
            },
      );
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      expect(called, isFalse);
      expect(
        find.byKey(const ValueKey('fnthink-send-blocked')),
        findsOneWidget,
        reason: '挡住的那句必须在页面最上面（ListView 懒布局，提交键常常在视口之外）',
      );
    });

    testWidgets('没选动作 ⇒ 不发', (tester) async {
      var called = false;
      await pumpSend(
        tester,
        send:
            ({
              required String peer,
              required String title,
              required String text,
            }) async {
              called = true;
              return const FnthinkSendResult(
                status: FnthinkSendStatus.accepted,
              );
            },
      );
      await tester.tap(
        find.byKey(const ValueKey('remote-send-peer-8K3FJ6QPTM9WZ4VHNS')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      expect(called, isFalse);
    });

    testWidgets('L3 且两个凭据都空着 ⇒ 不发', (tester) async {
      var called = false;
      await pumpSend(
        tester,
        send:
            ({
              required String peer,
              required String title,
              required String text,
            }) async {
              called = true;
              return const FnthinkSendResult(
                status: FnthinkSendStatus.accepted,
              );
            },
      );
      await tester.tap(
        find.byKey(const ValueKey('remote-send-peer-8K3FJ6QPTM9WZ4VHNS')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-level-L3')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('remote-send-action-notification')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      expect(called, isFalse, reason: 'L3 必须带其一，两个都空着不许发');
    });

    testWidgets('L1 时凭据两格**一格都不给**（它永远不需要凭据）', (tester) async {
      await pumpSend(tester);
      expect(find.byKey(const ValueKey('remote-send-key')), findsNothing);
      expect(find.byKey(const ValueKey('remote-send-totp')), findsNothing);
    });

    testWidgets('名单空着 ⇒ 那句"还没有配对过任何设备"，不给随便填地址', (tester) async {
      await pumpSend(tester, peers: const []);
      expect(
        find.byKey(const ValueKey('remote-send-peers-empty')),
        findsOneWidget,
      );
    });
  });

  group('发送页：发成与没发成是两句不同的话', () {
    testWidgets('accepted ⇒ 说"已发出，等两条回执"', (tester) async {
      await pumpSend(
        tester,
        send:
            ({
              required String peer,
              required String title,
              required String text,
            }) async =>
                const FnthinkSendResult(status: FnthinkSendStatus.accepted),
      );
      await tester.tap(
        find.byKey(const ValueKey('remote-send-peer-8K3FJ6QPTM9WZ4VHNS')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('remote-send-action-listener:start')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      // 二次确认那一层：先过掉它
      await _confirmIfPresent(tester);
      expect(find.textContaining('已发出'), findsOneWidget);
    });

    testWidgets('被拒 ⇒ 贴那句"没发出去"，不是"已发出"', (tester) async {
      await pumpSend(
        tester,
        send:
            ({
              required String peer,
              required String title,
              required String text,
            }) async => const FnthinkSendResult(
              status: FnthinkSendStatus.rejectedCapability,
              reason: 'rejected_capability',
            ),
      );
      await tester.tap(
        find.byKey(const ValueKey('remote-send-peer-8K3FJ6QPTM9WZ4VHNS')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('remote-send-action-listener:start')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      await _confirmIfPresent(tester);
      expect(find.textContaining('已发出'), findsNothing);
      expect(find.textContaining('没发出去'), findsWidgets);
    });
  });

  group('历史页：三种"没有记录"分开说', () {
    testWidgets('空表 ⇒ "还没有任何远程执行记录"', (tester) async {
      await pumpHistory(tester, loadRecords: (_) async => const []);
      expect(
        find.byKey(const ValueKey('remote-history-empty')),
        findsOneWidget,
      );
    });

    testWidgets('读失败 ⇒ 贴原话，不说成"一个都没有"', (tester) async {
      await pumpHistory(
        tester,
        loadRecords: (_) async => throw StateError('db is locked'),
      );
      expect(
        find.byKey(const ValueKey('remote-history-error')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('remote-history-empty')), findsNothing);
    });

    testWidgets('三档方向：收/发/全部各读各的', (tester) async {
      final asked = <String?>[];
      await pumpHistory(
        tester,
        loadRecords: (direction) async {
          asked.add(direction);
          return [record('x0000001')];
        },
      );
      await tester.tap(find.byKey(const ValueKey('remote-history-dir-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-history-dir-all')));
      await tester.pumpAndSettle();
      expect(
        asked,
        containsAllInOrder([
          kFnthinkRemoteDirectionIn,
          kFnthinkRemoteDirectionOut,
          null,
        ]),
      );
    });
  });

  group('历史页：已终态的那一行不给取消按钮', () {
    testWidgets('pending 给取消；done 不给', (tester) async {
      await pumpHistory(
        tester,
        loadRecords: (_) async => [
          record('x0000001', state: 'pending'),
          record('x0000002', state: 'done'),
        ],
      );
      expect(
        find.byKey(const ValueKey('remote-history-cancel-x0000001')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('remote-history-cancel-x0000002')),
        findsNothing,
        reason: '已终态的那一行给这一下 = 一个点了没反应的按钮',
      );
    });

    testWidgets('状态词在词表外 ⇒ 说"不认得"，不当它等于某个已知状态', (tester) async {
      await pumpHistory(
        tester,
        loadRecords: (_) async => [record('x0000001', state: 'weird-state')],
      );
      expect(find.textContaining('不认得'), findsWidgets);
    });

    testWidgets('本机触发的���一行没有对端 ⇒ 说清"没有远端发送方"', (tester) async {
      await pumpHistory(
        tester,
        loadRecords: (_) async => [
          record(
            'x0000001',
            state: 'done',
            peerAddress: '',
            source: 'localNotificationWhitelist',
          ),
        ],
      );
      expect(find.textContaining('没有远端发送方'), findsWidgets);
    });
  });

  group('历史页：边界那句在场', () {
    testWidgets('凭据与指令正文不进这一层（那句边界必须在）', (tester) async {
      await pumpHistory(tester, loadRecords: (_) async => [record('x0000001')]);
      expect(
        find.byKey(const ValueKey('remote-history-boundary')),
        findsOneWidget,
      );
    });
  });
}

/// 二次确认弹层（`IosDialogActions.askConfirm`）：本组两处都要过它。
/// ⚠ `askConfirm` **没有键名**（只有 `showInfo` / `IosFormDialog` 那些有），
/// 所以这里按**文案**点 —— 而那一格那句是本组自己定的 ARB 词条，
/// 改了文案这一处会找不到（届时改成按 `CupertinoDialogAction` 的序号点）。
Future<void> _confirmIfPresent(WidgetTester tester) async {
  final confirm = find.text('发出去');
  if (confirm.evaluate().isNotEmpty) {
    await tester.tap(confirm.last);
  }
  await tester.pumpAndSettle();
}
