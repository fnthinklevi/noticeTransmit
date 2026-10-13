import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/services/fnthink_settings.dart';
import 'package:notice_transmit/pages/fnthink_consent_gate.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/models/fnthink_remote_execution_record.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';
import 'package:notice_transmit/services/fnthink_remote_action_labels.dart';
import 'package:notice_transmit/services/fnthink_remote_execution.dart';
import 'package:notice_transmit/services/fnthink_remote_out_record.dart';
import 'package:notice_transmit/pages/fnthink_send_page.dart';
import 'package:notice_transmit/pages/remote_history_page.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/fnthink_card.dart';

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
  final zhL10n = lookupAppLocalizations(const Locale('zh'));
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
    void Function(FnthinkRemoteExecutionRecord record)? onSaved,
    List<String>? trace,
  }) async {
    final events = trace ?? <String>[];
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
            // T143 片1：发起端那一发的留痕。要看的是**顺序**（按下先写一行 pending，
            // send 回来再覆盖同一行），所以这里记两样：写了什么、按什么次序写。
            saveRemoteExecution: (record) async {
              events.add('save:${record.state}');
              onSaved?.call(record);
            },
            loadPeers: () async => peers ?? const <FnthinkPeer>[],
            send:
                ({
                  required String peer,
                  required String title,
                  required String text,
                }) async {
                  events.add('send');
                  if (send != null) {
                    return send(peer: peer, title: title, text: text);
                  }
                  return const FnthinkSendResult(
                    status: FnthinkSendStatus.accepted,
                  );
                },
            contractOf: contractOf ?? () async => contract,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 提交键在页面最下面，而这张页是 `ListView`（懒布局）：T146 把 18 枚动作分栏之后它更靠后，
  /// 可能**根本没被 build** —— `ensureVisible` 对不在树上的键抛 `No element`，
  /// 只能一格一格滚到建出来为止（与 `fnthink_send_page_test.dart` 同一手法）。
  Future<void> revealSubmit(WidgetTester tester) => tester.scrollUntilVisible(
    find.byKey(const ValueKey('remote-send-submit')),
    200,
    scrollable: find.byType(Scrollable).first,
  );

  Future<void> pumpHistory(
    WidgetTester tester, {
    required Future<List<FnthinkRemoteExecutionRecord>?> Function(String?)
    loadRecords,
    Future<bool> Function(String)? remove,
    Future<FnthinkContract> Function()? contractOf,
    Listenable? Function()? events,
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
            executionEvents: events,
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
    String result = '',
    String reason = '',
    String level = 'L2',
    String item = 'listener:start',
    String argument = '',
  }) => FnthinkRemoteExecutionRecord(
    execId: id,
    direction: direction,
    peerAddress: peerAddress,
    level: level,
    item: item,
    argument: argument,
    state: state,
    source: source,
    createdAt: 1700000000000,
    result: result,
    reason: reason,
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
      await revealSubmit(tester);
      await tester.pumpAndSettle();
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
      await revealSubmit(tester);
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
      await revealSubmit(tester);
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
      await revealSubmit(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      // 二次确认那一层：先过掉它
      await _confirmIfPresent(tester);
      expect(find.byKey(const ValueKey('remote-send-note')), findsOneWidget);
      // T126 片3：同一句还**当场弹一次** ⇒ 屏幕上两处，且必须是**逐字相同**的那一句
      // （弹层里再拼一遍就会在两处说不一样，而没人能判哪句是原话）。
      expect(find.textContaining('已发出'), findsNWidgets(2));
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
      await revealSubmit(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      await _confirmIfPresent(tester);
      expect(find.textContaining('已发出'), findsNothing);
      expect(find.textContaining('没发出去'), findsWidgets);
    });
  });

  group('发送页（T124 A 片）：参数由界面生成，不让人手敲冒号串', () {
    testWidgets('channel:toggle ⇒ 族与目标档是选出来的，用户只填对面那台的通道号', (tester) async {
      String? sent;
      await pumpSend(
        tester,
        send:
            ({
              required String peer,
              required String title,
              required String text,
            }) async {
              sent = text;
              return const FnthinkSendResult(
                status: FnthinkSendStatus.accepted,
              );
            },
      );
      await tester.tap(
        find.byKey(const ValueKey('remote-send-peer-8K3FJ6QPTM9WZ4VHNS')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-level-L2')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('remote-send-action-channel:toggle')),
      );
      await tester.pumpAndSettle();
      // 三段的头与尾是**选**出来的（族／目标档），中间那段才是填的。
      await tester.tap(find.byKey(const ValueKey('remote-send-family-app')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('remote-send-argument')),
        'chan-42',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('remote-send-want-off')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-want-off')));
      await tester.pumpAndSettle();
      // ⚠ L2 **不要**凭据（契约 `auth.l2Requires: false`）⇒ 凭据两格在这里本来就不该出现。
      expect(find.byKey(const ValueKey('remote-send-key')), findsNothing);
      await revealSubmit(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      await _confirmIfPresent(tester);

      final env = RemoteCommandEnvelope.decode(sent ?? '');
      expect(env, isNotNull, reason: '发出去的必须是一条指令载荷，否则对面按通知处置');
      expect(env!.level, 'L2');
      // ⚠⚠ **参数写在 item 的斜杠段**：对面判形状与派发都只读那一段，
      //   只写进信封那个 `argument` 字段的话每一条都会被拒成 missing-argument
      //   （`fnthink_remote_command_handler_test.dart` 把两处的区别钉死）。
      expect(env.item, 'channel:toggle/app:chan-42:off');
      expect(
        env.argument,
        'app:chan-42:off',
        reason: '信封那一份仍带着（进对面留痕与回执），但动作参数只认 item 的斜杠段',
      );
    });

    testWidgets('L3 的 toggle ⇒ 没选目标值不许发；选了就写在 item 上（重投才幂等）', (tester) async {
      final sent = <String>[];
      await pumpSend(
        tester,
        send:
            ({
              required String peer,
              required String title,
              required String text,
            }) async {
              sent.add(text);
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
        find.byKey(const ValueKey('remote-send-action-monitoring')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('remote-send-key')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('remote-send-key')),
        'K-1',
      );
      await tester.pumpAndSettle();
      await revealSubmit(tester);
      await tester.pumpAndSettle();
      // 先不选目标档：不带目标值 = 对面"读当前再翻"，重投一次就翻回原状。
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      expect(
        find.byKey(const ValueKey('fnthink-send-blocked')),
        findsOneWidget,
        reason: '挡住的那句必须在页面最上面（这一族的老形状：点了没反应）',
      );
      // 选了才发，且目标值要落在那一段 item 上。
      await tester.ensureVisible(
        find.byKey(const ValueKey('remote-send-l3-want-on')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-l3-want-on')));
      await tester.pumpAndSettle();
      await revealSubmit(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      await _confirmIfPresent(tester);
      expect(sent, hasLength(1));
      expect(RemoteCommandEnvelope.decode(sent.single)?.item, 'monitoring/on');
    });

    testWidgets('回传那一条 ⇒ 只填一个数：空／越界被挡，填对了发 notifications:report/10', (
      tester,
    ) async {
      String? sent;
      await pumpSend(
        tester,
        send:
            ({
              required String peer,
              required String title,
              required String text,
            }) async {
              sent = text;
              return const FnthinkSendResult(
                status: FnthinkSendStatus.accepted,
              );
            },
      );
      await tester.tap(
        find.byKey(const ValueKey('remote-send-peer-8K3FJ6QPTM9WZ4VHNS')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('remote-send-action-notifications:report')),
      );
      await tester.pumpAndSettle();
      // 它只要一枚数 —— 通道那三格（族／号／目标档）一个都不该出现。
      expect(
        find.byKey(const ValueKey('remote-send-report-count')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('remote-send-family-webhook')),
        findsNothing,
      );

      Future<void> submit() async {
        await revealSubmit(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
        await tester.pumpAndSettle();
      }

      // 空着 ⇒ 被挡（区间写在挡住那句里）。
      await submit();
      expect(sent, isNull);
      expect(
        find.byKey(const ValueKey('fnthink-send-blocked')),
        findsOneWidget,
      );

      // 越界 ⇒ 还是被挡。
      await tester.ensureVisible(
        find.byKey(const ValueKey('remote-send-report-count')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('remote-send-report-count')),
        '99',
      );
      await tester.pumpAndSettle();
      await submit();
      expect(sent, isNull);

      // 填对了才发，且拼出来的是那个数（不是用户敲的整串别的什么）。
      await tester.enterText(
        find.byKey(const ValueKey('remote-send-report-count')),
        '10',
      );
      await tester.pumpAndSettle();
      await submit();
      await _confirmIfPresent(tester);
      expect(
        RemoteCommandEnvelope.decode(sent ?? '')?.item,
        'notifications:report/10',
      );
    });

    testWidgets('搜短信那一条 ⇒ 只填一枚关键词：空被挡，填了发 sms:search/<词>', (tester) async {
      String? sent;
      await pumpSend(
        tester,
        send:
            ({
              required String peer,
              required String title,
              required String text,
            }) async {
              sent = text;
              return const FnthinkSendResult(
                status: FnthinkSendStatus.accepted,
              );
            },
      );
      await tester.tap(
        find.byKey(const ValueKey('remote-send-peer-8K3FJ6QPTM9WZ4VHNS')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('remote-send-action-sms:search')),
      );
      await tester.pumpAndSettle();
      // 它只要一枚词 —— 回传那张数格与通道那三格都不该出现。
      expect(find.byKey(const ValueKey('remote-send-keyword')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('remote-send-report-count')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('remote-send-family-webhook')),
        findsNothing,
      );

      Future<void> submit() async {
        await revealSubmit(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
        await tester.pumpAndSettle();
      }

      await submit();
      expect(sent, isNull);
      expect(
        find.byKey(const ValueKey('fnthink-send-blocked')),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('remote-send-keyword')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('remote-send-keyword')),
        '验证码',
      );
      await tester.pumpAndSettle();
      await submit();
      await _confirmIfPresent(tester);
      expect(RemoteCommandEnvelope.decode(sent ?? '')?.item, 'sms:search/验证码');
    });

    testWidgets('打开入口那一条 ⇒ 那两格的字是"打开哪一条"，发 app:launch/<名字>', (tester) async {
      String? sent;
      await pumpSend(
        tester,
        send:
            ({
              required String peer,
              required String title,
              required String text,
            }) async {
              sent = text;
              return const FnthinkSendResult(
                status: FnthinkSendStatus.accepted,
              );
            },
      );
      await tester.tap(
        find.byKey(const ValueKey('remote-send-peer-8K3FJ6QPTM9WZ4VHNS')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('remote-send-action-app:launch')),
      );
      await tester.pumpAndSettle();
      // 同一个 keyword 形态，但文案必须是"打开哪一条"（不是"搜什么词"）。
      final l10n = AppLocalizations.of(
        tester.element(find.byType(FnthinkSendPage)),
      );
      expect(find.text(l10n.remoteSendShortcutNameLabel), findsOneWidget);
      expect(find.text(l10n.remoteSendSmsKeywordLabel), findsNothing);

      await revealSubmit(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      expect(sent, isNull, reason: '名字空着不许发');

      await tester.ensureVisible(
        find.byKey(const ValueKey('remote-send-keyword')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('remote-send-keyword')),
        '开门',
      );
      await tester.pumpAndSettle();
      await revealSubmit(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      await _confirmIfPresent(tester);
      expect(RemoteCommandEnvelope.decode(sent ?? '')?.item, 'app:launch/开门');
    });

    testWidgets('搜通话记录那一条 ⇒ 文案是"搜什么词或号码"，发 calls:search/<词>', (tester) async {
      String? sent;
      await pumpSend(
        tester,
        send:
            ({
              required String peer,
              required String title,
              required String text,
            }) async {
              sent = text;
              return const FnthinkSendResult(
                status: FnthinkSendStatus.accepted,
              );
            },
      );
      await tester.tap(
        find.byKey(const ValueKey('remote-send-peer-8K3FJ6QPTM9WZ4VHNS')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('remote-send-action-calls:search')),
      );
      await tester.pumpAndSettle();
      // 同一个 keyword 形态，第三个动作：文案按动作分（不与短信那一条并成一句）。
      final l10n = AppLocalizations.of(
        tester.element(find.byType(FnthinkSendPage)),
      );
      expect(find.text(l10n.remoteSendCallsKeywordLabel), findsOneWidget);
      expect(find.text(l10n.remoteSendSmsKeywordLabel), findsNothing);
      expect(find.byKey(const ValueKey('remote-send-keyword')), findsOneWidget);

      await revealSubmit(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      expect(sent, isNull, reason: '关键词空着不许发');

      await tester.ensureVisible(
        find.byKey(const ValueKey('remote-send-keyword')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('remote-send-keyword')),
        '10086',
      );
      await tester.pumpAndSettle();
      await revealSubmit(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      await _confirmIfPresent(tester);
      expect(
        RemoteCommandEnvelope.decode(sent ?? '')?.item,
        'calls:search/10086',
      );
    });

    testWidgets('搜通讯录那一条 ⇒ 文案是"搜什么名字或号码"，发 contacts:search/<词>', (
      tester,
    ) async {
      String? sent;
      await pumpSend(
        tester,
        send:
            ({
              required String peer,
              required String title,
              required String text,
            }) async {
              sent = text;
              return const FnthinkSendResult(
                status: FnthinkSendStatus.accepted,
              );
            },
      );
      await tester.tap(
        find.byKey(const ValueKey('remote-send-peer-8K3FJ6QPTM9WZ4VHNS')),
      );
      await tester.pumpAndSettle();
      // 动作多到换行之后这一枚可能在屏外：先滚到它再点。
      await tester.ensureVisible(
        find.byKey(const ValueKey('remote-send-action-contacts:search')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('remote-send-action-contacts:search')),
      );
      await tester.pumpAndSettle();
      // 同一个 keyword 形态，第四个动作：文案按动作分（不与短信/通话并成一句）。
      final l10n = AppLocalizations.of(
        tester.element(find.byType(FnthinkSendPage)),
      );
      expect(find.text(l10n.remoteSendContactsKeywordLabel), findsOneWidget);
      expect(find.text(l10n.remoteSendCallsKeywordLabel), findsNothing);
      expect(find.text(l10n.remoteSendSmsKeywordLabel), findsNothing);
      expect(find.byKey(const ValueKey('remote-send-keyword')), findsOneWidget);

      await revealSubmit(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      expect(sent, isNull, reason: '关键词空着不许发');

      await tester.ensureVisible(
        find.byKey(const ValueKey('remote-send-keyword')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('remote-send-keyword')),
        '张三',
      );
      await tester.pumpAndSettle();
      await revealSubmit(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      await _confirmIfPresent(tester);
      expect(
        RemoteCommandEnvelope.decode(sent ?? '')?.item,
        'contacts:search/张三',
      );
    });

    testWidgets('回定位那一条 ⇒ 没有参数可填，直接发 location:get', (tester) async {
      String? sent;
      await pumpSend(
        tester,
        send:
            ({
              required String peer,
              required String title,
              required String text,
            }) async {
              sent = text;
              return const FnthinkSendResult(
                status: FnthinkSendStatus.accepted,
              );
            },
      );
      await tester.tap(
        find.byKey(const ValueKey('remote-send-peer-8K3FJ6QPTM9WZ4VHNS')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('remote-send-action-location:get')),
      );
      await tester.pumpAndSettle();
      // 无参数形态：关键词/条数/通道那三组参数格都不该出现。
      expect(find.byKey(const ValueKey('remote-send-keyword')), findsNothing);
      expect(
        find.byKey(const ValueKey('remote-send-report-count')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('remote-send-family-webhook')),
        findsNothing,
      );

      await revealSubmit(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      await _confirmIfPresent(tester);
      expect(RemoteCommandEnvelope.decode(sent ?? '')?.item, 'location:get');
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

    testWidgets('那一格小字是公共件画的（T100 片5：页面不再自搭壳）', (tester) async {
      await pumpHistory(tester, loadRecords: (_) async => const []);
      // key 逐字没动（`remote-history-empty` 还是那枚 Text 的 key）⇒ 上面那两条定位一条都不欠；
      // 这一条钉的是**画法**：把壳换回页面自搭的 Text，key 还在、字号与行距就开始各漂各的。
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('remote-history-empty')),
          matching: find.byType(FnthinkNote),
        ),
        findsOneWidget,
        reason: '那格小字不再由 `FnthinkNote` 画 ⇒ 这一族在这张页上又长出第二个作者',
      );
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

  group('发起端那一发送就写一行 out（T143 片1）', () {
    Future<void> submit(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey('remote-send-peer-8K3FJ6QPTM9WZ4VHNS')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('remote-send-action-listener:start')),
      );
      await tester.pumpAndSettle();
      await revealSubmit(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
      await tester.pumpAndSettle();
      await _confirmIfPresent(tester);
    }

    testWidgets('第一写在 send **之前**（按下那一刻账上就有这一条，不是发完才记）', (tester) async {
      final events = <String>[];
      final saved = <FnthinkRemoteExecutionRecord>[];
      await pumpSend(tester, trace: events, onSaved: saved.add);
      await submit(tester);

      expect(
        events.first,
        'save:pending',
        reason:
            '写在 send 之后 ⇒ 那一发卡在路上（或这台被杀掉）时，「发」那一档什么都没有，'
            '而用户确实按下过。第一写要回答的是"我按过"，第二写才是"结果如何"',
      );
      expect(events, contains('send'));
      expect(saved.first.direction, kFnthinkRemoteDirectionOut);
      expect(saved.first.peerAddress, '8K3FJ6QPTM9WZ4VHNS');
      expect(saved.first.item, 'listener:start');
      expect(saved.first.source, kFnthinkRemoteOutSource);
      expect(
        events.where((e) => e.startsWith('save:')),
        hasLength(2),
        reason: '两写落**同一行**（一次按下 = 一条记录，不是两条）',
      );
      expect(saved[1].execId, saved.first.execId);
    });

    testWidgets('被拒那一发 ⇒ 同一行改写成 failed + 那枚理由', (tester) async {
      final events = <String>[];
      final saved = <FnthinkRemoteExecutionRecord>[];
      await pumpSend(
        tester,
        trace: events,
        onSaved: saved.add,
        send:
            ({
              required String peer,
              required String title,
              required String text,
            }) async => const FnthinkSendResult(
              status: FnthinkSendStatus.transportError,
            ),
      );
      await submit(tester);

      expect(saved.last.state, RemoteExecutionStates.failed);
      expect(
        saved.last.reason,
        'transportError',
        reason: '没给那枚机器词时，退到 status.name —— 这一格不许空着说"失败了但不知道为什么"',
      );
      expect(saved.last.execId, saved.first.execId);
      expect(
        saved.last.unsettled,
        isFalse,
        reason: '没发出去就是终态：留一条永远 pending 的行，界面会一直等一个不会来的回执',
      );
    });

    testWidgets('发出去那一发**不替对面编终态**：第二写仍是 pending', (tester) async {
      final saved = <FnthinkRemoteExecutionRecord>[];
      await pumpSend(tester, onSaved: saved.add);
      await submit(tester);

      expect(saved, isNotEmpty);
      expect(
        saved.last.state,
        RemoteExecutionStates.pending,
        reason:
            'send 只证明交出去了。写成 done 就是本机替对面说话 —— 而回执载荷里'
            '目前没有关联键（片2），这一行根本不知道自己被谁确认了',
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

    testWidgets('「撤销」那一枚由行内动作件画出（片11：钉的是件不是 key）', (tester) async {
      // key 字符串逐字没动，所以"找不到"不是这一条要防的事 —— 这一条防的是
      // **key 还在、画的却不是公共件**：那样字号与语义色又回到页面自己挑，
      // 而这一族的形状统一（T148 差异⑧）就只在台账上成立、在屏上不成立。
      await pumpHistory(
        tester,
        loadRecords: (_) async => [record('x0000001', state: 'pending')],
      );
      final cancel = find.byKey(
        const ValueKey('remote-history-cancel-x0000001'),
      );
      // ⚠ `matchRoot: true` 不是随手加的：`FnthinkInlineAction` 收的是 `super.key`
      //   （键**就是**那枚件），而 `find.ancestor` 默认把根排除 ⇒ 不加就是恒空的 0。
      //   同页另一枚 `FnthinkNote` 恰好相反（键挂在那枚 `Text` 上）—— 一件两种定位法，
      //   判据要跟着件住哪儿走，别拿同一写法断两枚（片7 记过同族那次红）。
      expect(
        find.ancestor(
          of: cancel,
          matching: find.byType(FnthinkInlineAction),
          matchRoot: true,
        ),
        findsOneWidget,
        reason: '那一格还在、画的却不是 `FnthinkInlineAction` ⇒ 行内动作这一族又长出第二个作者',
      );
      // 件里那枚 `Text` 必须还是词条本身（换件不许顺手换词；断在词条上而不是某串措辞）
      expect(
        find.descendant(
          of: cancel,
          matching: find.text(zhL10n.remoteHistoryCancel),
        ),
        findsOneWidget,
      );
    });

    testWidgets('方向条那三枚由 `FnthinkChoiceChip` 画出（片12：行内 chip 那笔账）', (
      tester,
    ) async {
      // 这一页原来私有搭了一枚 `_DirectionChip`，选中态**只有字重与字色差** —— 那种形状的病不是
      // "两处不统一"，而是**用户在屏上读不出自己选上了没有**（T108 片② 在发送页三排上实测过）。
      // 这里钉的是件不是 key：key 逐字没动，换成自搭壳它照样找得到。
      await pumpHistory(tester, loadRecords: (_) async => const []);
      for (final key in const [
        'remote-history-dir-in',
        'remote-history-dir-out',
        'remote-history-dir-all',
      ]) {
        expect(
          find.ancestor(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(FnthinkChoiceChip),
          ),
          findsOneWidget,
          reason: '$key 还在、画的却不是公共件 ⇒ 「一排可选项里的一枚」又长出第二个作者',
        );
      }
      // 三档互斥：恰好一枚选中（零枚＝屏幕不说现在在哪一档；两枚＝互斥被破）
      expect(
        tester
            .widgetList<FnthinkChoiceChip>(find.byType(FnthinkChoiceChip))
            .where((w) => w.selected)
            .length,
        1,
        reason: '方向条的选中态必须恰好一枚',
      );
    });

    testWidgets('发起端那一行（out + pending）也不给取消：本机手里没有可撤的窗口', (tester) async {
      // T143 片1 带出来的新形状：out 的 `pending` 说的是"已交出去、等对面回执"，
      // 给这一下等于把一条已经上路的东西标成"我收回了" —— 而对面照不照做没人知道。
      await pumpHistory(
        tester,
        loadRecords: (_) async => [
          record(
            'x0000009',
            state: 'pending',
            direction: kFnthinkRemoteDirectionOut,
          ),
        ],
      );
      expect(
        find.byKey(const ValueKey('remote-history-cancel-x0000009')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('remote-history-row-x0000009')),
        findsOneWidget,
        reason: '不给出口的同时，那一行本身要看得见（"发"那一档不再恒空就是本片的目的）',
      );
    });

    testWidgets('状态词在词表外 ⇒ 说"不认得"，不当它等于某个已知状态', (tester) async {
      await pumpHistory(
        tester,
        loadRecords: (_) async => [record('x0000001', state: 'weird-state')],
      );
      expect(find.textContaining('不认得'), findsWidgets);
    });

    // 裁定 3（2026-10-12）：历史那一行**除了状态还要有结果与理由**。这两条钉的是同一枚形状的两面：
    // 有就说出、没有就不说 —— 后者防的是把"没有"渲染成一句空话（"理由："），那是界面替本机编的。
    testWidgets('被拒那一行要把理由说出来（switch-off 这类读数看得见才算"有执行结果"）', (tester) async {
      await pumpHistory(
        tester,
        loadRecords: (_) async => [
          record('x0000001', state: 'failed', reason: 'switch-off'),
        ],
      );
      expect(
        find.byKey(const ValueKey('remote-history-reason-x0000001')),
        findsOneWidget,
        reason: '理由不显示 ⇒ 用户只看到"没做成"，而"没做成"与"为什么没做成"是两件事',
      );
      expect(find.textContaining('switch-off'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('remote-history-result-x0000001')),
        findsNothing,
        reason: 'result 是空串：那一条真没有结果，不许画一句"结果："冒充',
      );
    });

    testWidgets('结果与理由各自有空就有：两个都有就两行都在', (tester) async {
      await pumpHistory(
        tester,
        loadRecords: (_) async => [
          record('x0000002', state: 'done', result: '已开启', reason: ''),
        ],
      );
      expect(
        find.byKey(const ValueKey('remote-history-result-x0000002')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('remote-history-reason-x0000002')),
        findsNothing,
      );
      expect(find.textContaining('已开启'), findsOneWidget);
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

  group('历史页那一行：名走那张人话表，参数自己一格（T146 片2）', () {
    // 裁定 5 的第②条：「名与参数挤一串」。量出来时它比记的更坏 —— 参数那一列**根本没上屏**：
    // 一行写着 `L3 · monitoring`，用户看不出这台把对面的总开关开了还是关了。
    testWidgets('L3 那一条 ⇒ 标题用人话，档位落在参数那一格里', (tester) async {
      await pumpHistory(
        tester,
        loadRecords: (_) async => [
          record('e_l3', level: 'L3', item: 'monitoring', argument: 'on'),
        ],
      );

      final title = tester
          .widget<Text>(find.byKey(const ValueKey('remote-history-title-e_l3')))
          .data!;
      expect(
        title,
        contains(fnthinkRemoteActionLabel(zhL10n, 'monitoring')),
        reason: '标题不吃那张人话表 ⇒ 画给用户的是契约那个裸名',
      );
      expect(
        title,
        isNot(contains('monitoring')),
        reason: '同一格里再出现契约名 = 这一格有两个作者（页面与那张表各翻一半）',
      );
      expect(
        find.text('参数：on'),
        findsOneWidget,
        reason: '档位不显示 ⇒ "这台把总开关开了还是关了"在界面上读不出来',
      );
    });

    testWidgets('参数为空那一类（`location:get`）⇒ 不画空的那一格', (tester) async {
      await pumpHistory(
        tester,
        loadRecords: (_) async => [
          record('e_noarg', level: 'L2', item: 'location:get'),
        ],
      );

      expect(
        find.byKey(const ValueKey('remote-history-subtitle-e_noarg')),
        findsNothing,
        reason: '空参数画成「参数：」是一句界面替本机编的话（有就说、没有就不说）',
      );
    });

    testWidgets('L1 那一条没有 item ⇒ 标题只剩级别，不带那枚悬空的分隔符', (tester) async {
      await pumpHistory(
        tester,
        loadRecords: (_) async => [record('e_l1', level: 'L1', item: '')],
      );

      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('remote-history-title-e_l1')),
            )
            .data,
        'L1',
        reason: '`L1 · ` 那种尾巴是拼串漏了判空，读起来像"级别后面还有个名字没显示出来"',
      );
    });

    testWidgets('没配人话的那一项 ⇒ 原样回契约名（看得见的缺，不编一句）', (tester) async {
      await pumpHistory(
        tester,
        loadRecords: (_) async => [
          record('e_new', level: 'L2', item: 'brand-new:thing'),
        ],
      );

      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('remote-history-title-e_new')),
            )
            .data,
        'L2 · brand-new:thing',
        reason:
            '回退形状变了 ⇒ "没配就看得见"这条一起失效；'
            '这里要的是**裸名**，不是把未知项说成某个已知的动作',
      );
    });
  });

  group('历史页：结果那一格是人话（T144 片2 格①）', () {
    testWidgets('done 那一行读得到"本机做成了哪一步"', (tester) async {
      await pumpHistory(
        tester,
        loadRecords: (_) async => [
          record('e_done', state: 'done', result: 'performed'),
        ],
      );

      expect(
        find.text(zhL10n.remoteHistoryResult(zhL10n.remoteOutcomePerformed)),
        findsOneWidget,
        reason: '把列里的机器词原样念出来 = 那一格没有作者',
      );
    });

    testWidgets('词表外的读数**原样显示**，不翻成"已完成"', (tester) async {
      await pumpHistory(
        tester,
        loadRecords: (_) async => [
          record('e_odd', state: 'done', result: 'some-new-code'),
        ],
      );

      expect(
        find.text(zhL10n.remoteHistoryResult('some-new-code')),
        findsOneWidget,
        reason: '读不出来的东西被界面替本机说成"做完了"，比裸词更坏',
      );
    });

    testWidgets('failed 那一行只有理由那一格（同一个码不再抄两遍）', (tester) async {
      await pumpHistory(
        tester,
        loadRecords: (_) async => [
          record('e_failed', state: 'failed', reason: 'switch-off'),
        ],
      );

      expect(
        find.byKey(const ValueKey('remote-history-result-e_failed')),
        findsNothing,
        reason: '两格写同一串时，"结果"与"为什么没成"在界面上塌成同一句话',
      );
      expect(
        find.text(zhL10n.remoteHistoryReason('switch-off')),
        findsOneWidget,
      );
    });
  });

  group('历史页：边界那句在场（T149 片1 后只留一行短说）', () {
    testWidgets('页尾是那一行短说，长边界不再摊在页面上', (tester) async {
      await pumpHistory(tester, loadRecords: (_) async => [record('x0000001')]);

      expect(
        find.byKey(const ValueKey('remote-history-boundary')),
        findsOneWidget,
        reason: '那一行还在 ⇒ 只是把位置换了；换成"整句消失"就是把事实删了',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('remote-history-boundary')))
            .data,
        zhL10n.remoteHistoryBoundaryShort,
      );
      expect(
        find.text(zhL10n.remoteHistoryBoundary),
        findsNothing,
        reason: '维护者 2026-10-12 第 4 条：页面里不许再摊成段说明',
      );
    });

    testWidgets('点那枚问号 ⇒ 弹层起得来（定位串没漂）', (tester) async {
      await pumpHistory(tester, loadRecords: (_) async => [record('x0000001')]);

      await tester.tap(
        find.byKey(const ValueKey('remote-history-boundary-help')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('remote-history-boundary-help')),
        findsOneWidget,
        reason: '问号按 key 点得中：helpKey 被改形就是这一条先红，而不是"点了没反应"',
      );
    });

    testWidgets('弹层里那句长边界在（只挪位置，不许删正文）', (tester) async {
      await pumpHistory(tester, loadRecords: (_) async => [record('x0000001')]);

      await tester.tap(
        find.byKey(const ValueKey('remote-history-boundary-help')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(zhL10n.remoteHistoryBoundary),
        findsOneWidget,
        reason:
            '搬进弹层时把整句搬丢了 = "凭据与指令正文不进这一层"这条披露消失，'
            '而界面上看着一切正常（这一族"只挪位置不删正文"的正反两面）',
      );
    });

    testWidgets('空表那一屏的边界句同样只剩短说（两处装配点不许只改一处）', (tester) async {
      await pumpHistory(tester, loadRecords: (_) async => []);

      expect(
        find.byKey(const ValueKey('remote-history-boundary')),
        findsOneWidget,
        reason: '空表与有货是两条 return，长句在两处各写一遍时就会有一处漏改',
      );
      expect(find.text(zhL10n.remoteHistoryBoundary), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('remote-history-boundary-help')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(zhL10n.remoteHistoryBoundary),
        findsOneWidget,
        reason: '空表那一屏的问号是**另一个装配点**：只给有货那屏装上，空屏就没人说这句话',
      );
    });
  });

  // ── T147 ①（维护者 2026-10-12 第 1 条：成功执行过却在历史里看不见）──────────
  // 那一行**是写进去了**，看不见的是"页面只在 initState 读一次"。延时窗口到点、执行完、
  // 被拒、撤销 —— 每一步都发生在用户已经开着这一页之后，而屏幕上还是进页那一刻的读数。
  group('历史页要跟着执行链重取（T147 ①）', () {
    testWidgets('执行链报一次事件 ⇒ 不用退出重进就能看到新落的那一行', (tester) async {
      final events = ChangeNotifier();
      var reads = 0;
      Future<List<FnthinkRemoteExecutionRecord>?> load(
        String? direction,
      ) async {
        reads++;
        // 第一次读：只有那条「待执行」；执行链点火后：终态那一行覆盖了同一行。
        return reads == 1
            ? [record('e_one')]
            : [record('e_one', state: 'done')];
      }

      await pumpHistory(tester, loadRecords: load, events: () => events);
      expect(reads, 1, reason: '进页读一次是原有的形状，不许偷偷变成两次');
      expect(
        find.byKey(const ValueKey('remote-history-row-e_one')),
        findsOneWidget,
      );

      events.notifyListeners();
      await tester.pumpAndSettle();
      expect(reads, 2, reason: '执行链已经 notify 而页面不重取 = 用户得退出这一页再进来才看见结果');
    });

    testWidgets('回前台 ⇒ 重取一次（去系统里改完授权回来的那条路）', (tester) async {
      var reads = 0;
      await pumpHistory(
        tester,
        loadRecords: (_) async {
          reads++;
          return [record('e_one')];
        },
      );
      expect(reads, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(reads, 2, reason: '同一族缺陷在权限页（T140 片2）已经踩过一次：读数停在离开那一刻');
    });

    testWidgets('没有事件源（deps 没给）⇒ 页面照常，不许因为 null 崩', (tester) async {
      await pumpHistory(tester, loadRecords: (_) async => [record('e_one')]);
      expect(
        find.byKey(const ValueKey('remote-history-row-e_one')),
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
