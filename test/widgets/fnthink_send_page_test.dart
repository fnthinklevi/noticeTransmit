import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/pages/fnthink_consent_gate.dart';
import 'package:notice_transmit/pages/fnthink_send_page.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';
import 'package:notice_transmit/services/fnthink_webhook_targets.dart';
import 'package:notice_transmit/services/fnthink_settings.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/fnthink_card.dart';
import 'package:notice_transmit/widgets/primary_action_button.dart';

/// 那张共用发送页（T98 片④）。
///
/// 这一族原来有两副形状：名单行与收件详情走一枚只有标题＋正文的弹层，远程执行那一格走
/// 一张独立的指令页。收成一张页之后，这一组用例钉的是**页自己的形状**，不是两档各自的功能：
///  ① 两档并排给（不是藏在两个入口里），进来停在谁那档由入口决定；
///  ② 指令档没有契约就**灰着留着**并说原因（藏起来＝用户以为这一页压根没这功能）；
///  ③ 名单"读不出来"与"真的没有"是两句（这一路要人挑收件人，挑错对象比不挑更坏）；
///  ④ "为什么发不出去"那句在页面最上面（提交键常在视口外 ⇒ 点了没反应）；
///  ⑤ 预填那两格由调用方给（回复＝只给标题 ⇒ 主操作是灰的）。
///
/// 两档"发出去那一发"各自的证据不在这里：纯文本那一档在 `fnthink_settings_page_test.dart`
/// （名单行那一路打的是真链路），指令那一档在 `remote_execution_pages_test.dart`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // T118 同意门读 prefs 那枚同意版本；这一组测的是这张页自己的形状，不是门
    // （门自己那几条单列在 fnthink_consent_gate_test.dart）。不记同意的话，
    // 两档的提交都停在弹窗上，红在一个与用例无关的地方。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'fnthink.consent_version': 1,
    });
    // T118：门那一道在 widget 测试里必须走这份同步读出来的契约 —— 真 IO 在假时钟下不会完成。
    debugFnthinkConsentSettingsOverride = FnthinkSettings(
      contract: FnthinkContract.readFile(),
    );
    addTearDown(() => debugFnthinkConsentSettingsOverride = null);
  });

  final contract = FnthinkContract.readFile();
  const peerAddress = '8K3FJ6QPTM9WZ4VHNS';
  const peer = FnthinkPeer(
    peerAddress: peerAddress,
    publicKey: 'pk-AAAA',
    level: 'L2',
    grantedAt: 1700000000000,
  );

  Future<AppLocalizations> pump(
    WidgetTester tester, {
    Future<List<FnthinkPeer>> Function()? loadPeers,
    Future<FnthinkContract> Function()? contractOf,
    String? preselectedPeer,
    String prefillTitle = '',
    String prefillBody = '',
    FnthinkSendTier initialTier = FnthinkSendTier.notice,
    void Function(String peer, String title, String text)? onSend,
    // T122：Webhook 那一组的两个注入口（不传 ⇒ 默认空名单，页面画"还没有启用的通道"）。
    Future<List<FnthinkWebhookTarget>?> Function()? loadWebhooks,
    void Function(FnthinkWebhookTarget target, String title, String body)?
    onSendWebhook,
  }) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: FnthinkSendPage(
          preselectedPeer: preselectedPeer,
          prefillTitle: prefillTitle,
          prefillBody: prefillBody,
          initialTier: initialTier,
          deps: FnthinkSendDeps(
            loadPeers: loadPeers ?? () async => const [peer],
            send:
                ({
                  required String peer,
                  required String title,
                  required String text,
                }) async {
                  onSend?.call(peer, title, text);
                  return const FnthinkSendResult(
                    status: FnthinkSendStatus.accepted,
                    messageId: 'm_send_1',
                  );
                },
            contractOf: contractOf ?? () async => contract,
            loadWebhooks: loadWebhooks ?? () async => const [],
            sendToWebhook:
                ({
                  required FnthinkWebhookTarget target,
                  required String title,
                  required String body,
                }) async {
                  onSendWebhook?.call(target, title, body);
                  return const FnthinkSendResult(
                    status: FnthinkSendStatus.accepted,
                    messageId: 'm_hook_1',
                  );
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(FnthinkSendPage)));
  }

  group('两档并排给，进来停在哪一档由入口决定', () {
    testWidgets('默认停在纯文本那一档：档位／动作那几格不在树上', (tester) async {
      await pump(tester);
      expect(
        find.byKey(const ValueKey('fnthink-send-tier-notice')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('fnthink-send-tier-command')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('fnthink-send-title')), findsOneWidget);
      // 指令档的那些格没被画出来 —— 不是"藏在小屏后面"，是这一档根本用不上它们。
      expect(find.byKey(const ValueKey('remote-send-level-L1')), findsNothing);
      expect(
        find.byKey(const ValueKey('remote-send-action-listener:start')),
        findsNothing,
      );
    });

    testWidgets('点另一枚就换档：档位那一排与动作那一格出现', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('fnthink-send-tier-command')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('remote-send-level-L1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('remote-send-action-listener:start')),
        findsOneWidget,
      );
      // 换档之后纯文本那两格撤掉：留着它们，用户会以为发出去的一条同时带着正文。
      expect(find.byKey(const ValueKey('fnthink-send-body')), findsNothing);
    });

    testWidgets('远程执行那一格进来时停在指令档', (tester) async {
      await pump(tester, initialTier: FnthinkSendTier.command);
      expect(
        find.byKey(const ValueKey('remote-send-level-L1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('fnthink-send-body')), findsNothing);
    });
  });

  testWidgets('契约读不到 ⇒ 指令档**灰着留着**并说原因，纯文本档照常能发', (tester) async {
    await pump(
      tester,
      contractOf: () async => throw const FnthinkContractUnavailable('missing'),
    );
    final command = find.byKey(const ValueKey('fnthink-send-tier-command'));
    expect(command, findsOneWidget, reason: '藏起来＝用户以为这一页没有指令这一档');
    expect(
      tester.widget<CupertinoButton>(command).onPressed,
      isNull,
      reason: '契约不在而这一枚还能点 ⇒ 点下去是一张填不动的表单',
    );
    expect(
      find.byKey(const ValueKey('remote-send-contract-error')),
      findsOneWidget,
    );
    // 纯文本那一档不依赖契约，不能因为它读不到就一并停掉。
    expect(find.byKey(const ValueKey('fnthink-send-submit')), findsOneWidget);
  });

  testWidgets('指令档进不去时从远程那一格进来 ⇒ 退回纯文本档，而不是空着一屏', (tester) async {
    await pump(
      tester,
      initialTier: FnthinkSendTier.command,
      contractOf: () async => throw const FnthinkContractUnavailable('missing'),
    );
    expect(find.byKey(const ValueKey('fnthink-send-body')), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-send-level-L1')), findsNothing);
  });

  group('名单那三种"没有"分开说', () {
    testWidgets('读失败 ⇒ 说的是读不出来，不是"还没有配对过任何设备"', (tester) async {
      await pump(tester, loadPeers: () async => throw StateError('db'));
      final l10n = AppLocalizations.of(
        tester.element(find.byType(FnthinkSendPage)),
      );
      expect(find.text(l10n.remotePeersReadFailed), findsOneWidget);
      // T123：断言按 key（断形状不断措辞）—— 「读不出来」与「真的没有」是两句，
      // 画哪一句由这一格是哪一个 key 说清，不靠读文案去猜。
      expect(
        find.byKey(const ValueKey('remote-send-peers-unknown')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('remote-send-peers-empty')),
        findsNothing,
      );
      // 「去配对」那枚是**空态**的出路：读不出来时不知道有没有设备，
      // 更不该把人支去配对（那是把"读失败"说成"你没设备"的同一个错，换了个形式）。
      expect(find.byKey(const ValueKey('fnthink-send-go-pair')), findsNothing);
      // 空名单那句**不再是**「还没有任何远程执行记录」（那是执行历史那格的话，串台）
      expect(find.text(l10n.fnthinkSendTargetNoPeer), findsNothing);
    });

    testWidgets('真的空着 ⇒ 是那句"还没有配对过任何设备"，不是读不出来', (tester) async {
      await pump(tester, loadPeers: () async => const <FnthinkPeer>[]);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(FnthinkSendPage)),
      );
      // T123 的正解，三件都按 key 断：① 空名单那一格说的是"还没配对过设备"
      // （并给出处），不是"没有执行历史"、也不是"读不出来"。
      final emptyNote = find.byKey(const ValueKey('remote-send-peers-empty'));
      expect(emptyNote, findsOneWidget);
      expect(tester.widget<Text>(emptyNote).data, l10n.fnthinkSendTargetNoPeer);
      expect(
        find.byKey(const ValueKey('remote-send-peers-unknown')),
        findsNothing,
      );
      expect(find.text(l10n.remoteHistoryEmpty), findsNothing);
      expect(find.text(l10n.remotePeersReadFailed), findsNothing);
      // ② 空态要给**可点的一枚**去处（只说"没有"而不给出路 = 让用户自己猜）；
      // 置灰的那一枚等于没给 —— 所以连"它按得动"一起断。
      final goPair = find.byKey(const ValueKey('fnthink-send-go-pair'));
      expect(goPair, findsOneWidget);
      expect(
        tester.widget<FnthinkInlineAction>(goPair).onPressed,
        isNotNull,
        reason: '枚在那儿但按不动 ⇒ 空态那条出路仍然只是文案',
      );
    });
  });

  testWidgets('预填：回复那一条标题带着走，正文空着 ⇒ 主操作是灰的', (tester) async {
    final l10n = await pump(
      tester,
      preselectedPeer: peerAddress,
      prefillTitle: '回复：机箱温度',
    );
    final title = tester.widget<CupertinoTextField>(
      find.byKey(const ValueKey('fnthink-send-title')),
    );
    expect(title.controller!.text, '回复：机箱温度');
    expect(
      tester
          .widget<PrimaryActionButton>(
            find.byKey(const ValueKey('fnthink-send-submit')),
          )
          .onPressed,
      isNull,
      reason: '空正文发出去那边只收到一句空话，而回执照样算"送达"',
    );
    // 为什么是灰的写在键上（这一族的规矩：不藏、不换名、只置灰并说清楚）。
    expect(find.text(l10n.fnthinkSendEmptyBody), findsWidgets);
  });

  testWidgets('带着对端进来 ⇒ 那一台已经选中，卡片标题说的是它', (tester) async {
    final l10n = await pump(tester, preselectedPeer: peerAddress);
    expect(
      find.text(l10n.fnthinkSendSheetTitle(peerAddress)),
      findsOneWidget,
      reason: '从哪一行进来就该已经站在这一台上；还要人再挑一次＝那一行白点',
    );
  });

  testWidgets('纯文本那一档：点发送 ⇒ 打的是注入的那一发，收件人是选中的那一台', (tester) async {
    final asked = <({String peer, String title, String text})>[];
    await pump(
      tester,
      preselectedPeer: peerAddress,
      onSend: (p, t, x) => asked.add((peer: p, title: t, text: x)),
    );
    await tester.enterText(
      find.byKey(const ValueKey('fnthink-send-body')),
      '门已开',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fnthink-send-submit')));
    await tester.pumpAndSettle();

    expect(asked.single.peer, peerAddress);
    expect(asked.single.text, '门已开');
    expect(
      find.byKey(const ValueKey('fnthink-send-note')),
      findsOneWidget,
      reason: '结论留在这一页上：用户回头还能看见自己那一发是什么结果',
    );
  });

  testWidgets('指令档没选中对端 ⇒ 那句"为什么发不出去"在页面最上面，不在提交那格底下', (tester) async {
    await pump(
      tester,
      initialTier: FnthinkSendTier.command,
      loadPeers: () async => const [],
    );
    await tester.tap(find.byKey(const ValueKey('remote-send-level-L1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('remote-send-action-listener:start')),
    );
    await tester.pumpAndSettle();
    // ⚠ 动作一多（T124 片B 陆续加了三个）这张卡就越长：提交键可能**还没被 build**
    //   （ListView 懒布局）—— `ensureVisible` 对"不在树上"的键抛 No element，
    //   这里要用会自己滚到"建出来为止"的那一枚。
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('remote-send-submit')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remote-send-submit')));
    await tester.pumpAndSettle();

    final blocked = find.byKey(const ValueKey('fnthink-send-blocked'));
    // ⚠ 按完提交之后人停在页面**底部**（上面 scrollUntilVisible 是为了够得着提交键）——
    //   那句解释画在页面**最上面**（清单还在视口之外），懒布局下它此刻根本没被 build。
    //   所以先滚回去把"它真的在树上"这一步做成这枚 key 的存在性（向上滚到建出来为止）。
    await tester.scrollUntilVisible(
      blocked,
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(blocked, findsOneWidget);
    // 位置那一半：与它同屏可比的锚是「发给谁」那张卡的第一枚 note ——
    // 解释必须在**那张卡之上**（"按了没反应而解释在屏幕外"是这一路最不能出现的形状；
    // 拿提交键做锚要两枚同时在树上，而它们一个在头一个在尾，永远凑不到同一屏）。
    expect(
      tester.getTopLeft(blocked).dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('fnthink-send-target-devices')),
            )
            .dy,
      ),
    );
  });

  // T122：目标二选一 —— Webhook 那一类
  const hook = FnthinkWebhookTarget(
    channelId: 'fc_hook_1',
    name: 'NAS 的端点',
    target: 'https://push.example.com/api/fnthink/p/ep_1/SECRET000000000000000',
  );

  testWidgets('通知档选一条 Webhook 通道 ⇒ 那一发把标题与正文交给 sendToWebhook（不再走设备那一发）', (
    tester,
  ) async {
    FnthinkWebhookTarget? gotTarget;
    String? gotTitle;
    String? gotBody;
    var deviceSent = 0;
    await pump(
      tester,
      loadWebhooks: () async => const [hook],
      onSend: (p, t, x) => deviceSent++,
      onSendWebhook: (target, title, body) {
        gotTarget = target;
        gotTitle = title;
        gotBody = body;
      },
    );
    await tester.enterText(
      find.byKey(const ValueKey('fnthink-send-body')),
      '门已开',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('fnthink-send-target-webhook-fc_hook_1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fnthink-send-submit')));
    await tester.pumpAndSettle();

    expect(gotTarget?.channelId, 'fc_hook_1');
    expect(gotTitle, '');
    expect(gotBody, '门已开');
    expect(deviceSent, 0, reason: '选了 Webhook 还往设备那一发打 ⇒ 目标选择器形同虚设');
  });

  testWidgets('指令档里 Webhook 那一组**不出现**，只有一句原因', (tester) async {
    await pump(
      tester,
      initialTier: FnthinkSendTier.command,
      loadWebhooks: () async => const [hook],
    );
    expect(
      find.byKey(const ValueKey('fnthink-send-target-webhook-fc_hook_1')),
      findsNothing,
      reason: '指令档列出一个发不出去的目标（Webhook 没有配对关系与档位授权）',
    );
    expect(
      find.byKey(const ValueKey('fnthink-send-target-webhook-only-notice')),
      findsOneWidget,
      reason: '不列它就要说清为什么 —— 一句不写的"少了一组"看起来像页面坏了',
    );
  });
}
