import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/pages/fnthink_push_page.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';
import 'package:notice_transmit/services/fnthink_credential_store.dart';
import 'package:notice_transmit/services/fnthink_identity_service.dart';
import 'package:notice_transmit/services/fnthink_presence_scheduler.dart';
import 'package:notice_transmit/services/fnthink_receive_coordinator.dart';
import 'package:notice_transmit/services/fnthink_receive_loop.dart';
import 'package:notice_transmit/services/fnthink_receiver_service.dart';
import 'package:notice_transmit/services/fnthink_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_setup.dart';

/// 幻念推送页（T44 的②③ + T42 的入口那半）—— 整条收货链路唯一的用户入口。
///
/// 这里钉的全是"界面说的话是不是真话"，每条都有一个"写歪了用户会怎么被骗"：
///  ① 只是**看一眼**这一页，不该生成任何凭证、不该动 KeyStore、不该把循环起来；
///  ② 起不来的时候不许把开关回弹 —— prefs 里已经是"开"的那一份，回弹说的是"你没点上"这句假话；
///     真相要两格分开：开关=用户要的，状态行=实际的，中间贴服务端/本机给的原话；
///  ③ "上一轮还在途"、"开关没开"、"这一轮取到 0 条"是三件不同的事，不许都显示成第三句；
///  ④ 换地址码必须**重启**循环：循环握的是启动那一刻定型的码，继续跑等于拿旧码签新的请求；
///  ⑤ 那笔账上界面时不许带标题与正文。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final contract = FnthinkContract.readFile();
  late Map<String, String?> disk;

  setUp(() {
    disk = {};
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(clearNativeChannelStubs);

  /// `flutter_secure_storage` 与 `getFnthinkIdentity` 共用一枚桩：`disk` 就是那台机的加密盘。
  ///
  /// [presenceStatus] 喂的是「下一次自己醒」那一行读的那份原生状态（§4-9 片1d）：不传就是
  /// `null` ⇒ Dart 那侧映射成 `{0,0}` ⇒ 界面说「没在醒着」。要观察"开关一关那一行跟着变"，
  /// 传一个闭包进去，在测试里改它闭住的变量 —— 那一行的值必须**每次都从原生读**，
  /// 页面自己记一份的实现会在这条用例上露出来。
  void stubChannels({
    bool identityOk = true,
    Map<dynamic, dynamic>? Function()? presenceStatus,
  }) {
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
            if (!identityOk) return null;
            return <String, Object?>{
              'publicKey': 'AAAApublicKeyBytesForTests',
              'plan': 'androidKeyStoreEd25519',
              'keystoreBacked': true,
            };
          case 'fnthinkPresenceStatus':
            return presenceStatus?.call();
          default:
            return null;
        }
      },
    );
  }

  final validAddress = FnthinkAddressCode.generate(contract).value;
  final validPairing = FnthinkPairingCode.generate(contract).value;

  /// 一套装配：可控的签名能力 + 只记账不碰网络的循环 + 数得到"循环被建了几次"，
  /// 外加**配对那一发的假服务器**（`armBody` / `armStatus` / `confirmBody`）—— 页面现在会真发
  /// 那一发，不打个假服务器进去，测试就是在依赖"flutter test 把真实 HTTP 挡掉了"这件事。
  _Harness harness({
    bool canSign = true,
    List<String> messages = const [],
    int pending = 0,
    List<FnthinkPairRequest> pairRequests = const [],
    Future<void> Function()? gate,
    bool contractOk = true,
    String? contractText,
    int armStatus = 200,
    String armBody =
        '{"armed":true,"expiresAt":1800000300000,"ttlSeconds":300,'
        '"serverTime":1800000000000}',
    int confirmStatus = 200,
    String confirmBody =
        '{"requestId":"pr_9","status":"approved","grantedLevel":"L1",'
        '"serverTime":1800000000000}',
    int revokeStatus = 200,
    String revokeBody = '{"revoked":true,"serverTime":1800000000000}',
    int endpointStatus = 200,
    String endpointBody =
        '{"endpointId":"ep_7","secret":"ABCDEFGHIJKLMNOP2345678901",'
        '"postOnly":true,"serverTime":1800000000000}',
    int endpointListStatus = 200,
    // 默认"读到了，确实一把都没有"—— 这是最常见也最容易与"没读到"混为一谈的那一支。
    String endpointListBody = '{"endpoints":[],"serverTime":1800000000000}',
    int endpointRevokeStatus = 200,
    String endpointRevokeBody =
        '{"endpointId":"ep_new","revoked":true,"serverTime":1800000000000}',
    int endpointRotateStatus = 200,
    // 默认那把新口令是 Z 开头：断言"界面上出现的就是这一把"时不会与创建那一次的口令混。
    String endpointRotateBody =
        '{"endpointId":"ep_live","rotated":true,"secret":"ZZZ7RABQKPZ3STVWX234",'
        '"rotatingUntil":1800003600000,"serverTime":1800000000000}',
    int sendStatus = 202,
    String sendBody =
        '{"receipt":"queued","messageId":"m_send_1","action":"new","evicted":[]}',
    Future<FnthinkPeerWrite> Function(FnthinkPeer peer)? recordPeer,
    Future<bool> Function(String peerAddress)? removePeer,
    List<FnthinkPeer> peers = const [],
    bool peersFail = false,
  }) {
    final loader = FnthinkContractLoader(
      readAsset: (_) async {
        if (!contractOk) return '{ 这不是合法 JSON';
        // 少数用例要的是"契约里那个数改了，界面跟着改"——这时传一份改过的进来，
        // 而不是拿同一份契约去断言实现（那样写出来的断言永远绿：两边读的是同一个数）。
        if (contractText != null) return contractText;
        return File('protocol/fnthink-v1.json').readAsStringSync();
      },
    );
    final armAsked = <http.Request>[];
    final confirmAsked = <http.Request>[];
    final revokeAsked = <http.Request>[];
    final endpointAsked = <http.Request>[];
    final endpointListAsked = <http.Request>[];
    final endpointRevokeAsked = <http.Request>[];
    final endpointRotateAsked = <http.Request>[];
    final sendAsked = <http.Request>[];
    final removed = <String>[];
    final peerRows = <FnthinkPeer>[];
    final peersShown = <FnthinkPeer>[...peers];
    var peerReads = 0;
    var builds = 0;
    final coordinator = FnthinkReceiveCoordinator(
      contracts: loader,
      signer: _StubSigner(canSign),
      persist: (_) async => true,
      // 名单落库的替身：页面测试里不碰 sqflite，但要数得到"到底写没写、写的是哪一档"。
      // 写进去的那一行同时进 `peersShown`（= 下一次读名单就能读到它），这样"同意之后
      // 名单要重读一次"这条能被观察到，而不是只能靠数读取次数。
      recordPeer:
          recordPeer ??
          (peer) async {
            peerRows.add(peer);
            peersShown.add(peer);
            return FnthinkPeerWrite.created;
          },
      // 删行的替身：同样把 `peersShown` 改掉，于是"撤成之后那一行自己消失"是**读回来**的，
      // 不是页面自己把那一行从列表里剪掉的（那种实现当场看不出来，只会让守卫无处可钉）。
      removePeer:
          removePeer ??
          (addr) async {
            removed.add(addr);
            final before = peersShown.length;
            peersShown.removeWhere((p) => p.peerAddress == addr);
            return peersShown.length < before;
          },
      serviceFactory: (spec) => FnthinkReceiverService(
        contract: spec.contract,
        baseUri: spec.baseUri,
        signer: spec.signer,
        addressCode: spec.addressCode,
        client: MockClient((req) async {
          if (req.url.path == contract.apiPath('pairConfirm')) {
            confirmAsked.add(req);
            return http.Response(confirmBody, confirmStatus);
          }
          if (req.url.path == contract.apiPath('pairRevoke')) {
            revokeAsked.add(req);
            return http.Response(revokeBody, revokeStatus);
          }
          if (req.url.path == contract.apiPath('endpointCreate')) {
            endpointAsked.add(req);
            return http.Response(endpointBody, endpointStatus);
          }
          if (req.url.path == contract.apiPath('endpointList')) {
            endpointListAsked.add(req);
            // 带 content-type：那份载荷里可能有中文端点名（用户自己起的），而
            // `http.Response(body, code)` 在没有 content-type 时按 latin-1 编码，中文会在
            // 假服务器里就抛 ArgumentError —— 那是测试替身的形状问题，不是被测代码的问题。
            return http.Response(
              endpointListBody,
              endpointListStatus,
              headers: const {
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          if (req.url.path == contract.apiPath('endpointRevoke')) {
            endpointRevokeAsked.add(req);
            return http.Response(endpointRevokeBody, endpointRevokeStatus);
          }
          if (req.url.path == contract.apiPath('endpointRotate')) {
            endpointRotateAsked.add(req);
            return http.Response(
              endpointRotateBody,
              endpointRotateStatus,
              headers: const {
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          if (req.url.path == contract.apiPath('message')) {
            sendAsked.add(req);
            return http.Response(
              sendBody,
              sendStatus,
              headers: const {
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          armAsked.add(req);
          return http.Response(armBody, armStatus);
        }),
      ),
      loopFactory: (spec) {
        builds++;
        return FnthinkReceiveLoop(
          poll: () async {
            if (gate != null) await gate();
            return FnthinkReceiveOutcome(
              status: FnthinkPollStatus.ok,
              messages: [
                for (final id in messages)
                  FnthinkDelivered(
                    messageId: id,
                    type: 'notice',
                    item: '',
                    title: '机箱温度',
                    body: '温度 63 度（$id）',
                    sender: 'endpoint:ep_7',
                  ),
              ],
              pending: pending,
              pairRequests: pairRequests,
              nextDelay: const Duration(seconds: 20),
            );
          },
          ack: (id, result) async => const FnthinkAckResult(
            status: FnthinkPollStatus.ok,
            nextDelay: Duration(seconds: 20),
          ),
          persist: (_) async => true,
          // 协调者塞进 spec 的那一行必须在这里接上：不接，测试里的"后台那一轮"就永远不会
          // 把账交给协调者（生产那一条链路由 `buildFnthinkReceiveLoop` 的守卫钉，
          // 而替身这边漏接时，红的是"这一格自己出现"那条 —— 它确实该红）。
          onRound: spec.onRound,
          schedule: (delay, callback) => Timer(Duration.zero, () {}),
        );
      },
    );
    return _Harness(
      page: FnthinkPushPage(
        deps: FnthinkPushDeps(
          contracts: loader,
          coordinator: coordinator,
          identity: FnthinkIdentityService(),
          // 名单的读替身：页面只能经由这一个入口读到对端（守卫钉住它不许直连表）。
          // `peerReads` 数得到被读了几次 —— "点完同意之后那一格还是旧的"就是这么抓的。
          loadPeers: () async {
            peerReads++;
            if (peersFail) throw StateError('库打不开');
            return List<FnthinkPeer>.unmodifiable(peersShown);
          },
          // 「下一次自己醒」那一行（§4-9 片1d）：真的 scheduler + 被桩住的通道 ——
          // 页面拿到的就是生产那一份（`status()` 读 `fnthinkPresenceStatus`），
          // 而通道那头由各条用例自己决定回什么。
          presence: FnthinkPresenceScheduler(contracts: loader),
        ),
      ),
      coordinator: coordinator,
      builds: () => builds,
      armAsked: () => armAsked,
      confirmAsked: () => confirmAsked,
      peerRows: () => peerRows,
      peersShown: () => peersShown,
      peerReads: () => peerReads,
      revokeAsked: () => revokeAsked,
      endpointAsked: () => endpointAsked,
      endpointListAsked: () => endpointListAsked,
      endpointRevokeAsked: () => endpointRevokeAsked,
      endpointRotateAsked: () => endpointRotateAsked,
      sendAsked: () => sendAsked,
      removed: () => removed,
    );
  }

  Future<AppLocalizations> pump(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(FnthinkPushPage)));
  }

  group('看一眼不该发生的事', () {
    testWidgets('还没生成地址码 ⇒ 明说"还没生成"，并且盘上一个键都没写', (tester) async {
      stubChannels();
      final h = harness();
      final l10n = await pump(tester, h.page);
      expect(
        find.text(l10n.fnthinkAddressCodeNone),
        findsOneWidget,
        reason: '空白会被读成"坏了"，而事实是还没到过需要它的那一刻',
      );
      expect(disk, isEmpty, reason: '只是看了一眼，不该落一枚凭证');
      expect(h.coordinator.isRunning, isFalse, reason: '看页面不等于把循环起来起来');
    });

    testWidgets('契约读不到 ⇒ 只剩那一条原因，开关那一格根本不存在', (tester) async {
      stubChannels();
      final h = harness(contractOk: false);
      await pump(tester, h.page);
      expect(
        find.byKey(const ValueKey('fnthink-contract-error')),
        findsOneWidget,
      );
      expect(
        find.byType(CupertinoSwitch),
        findsNothing,
        reason: '契约不在还让人翻开关，等于把一个值写进没人能解释的地方',
      );
    });

    testWidgets('存量地址码坏掉 ⇒ 原话贴出来，且绝不被自动换掉', (tester) async {
      stubChannels();
      disk[FnthinkCredentialStore.addressCodeKey] = 'TOO_SHORT!';
      final h = harness();
      await pump(tester, h.page);
      expect(
        find.byKey(const ValueKey('fnthink-credential-error')),
        findsOneWidget,
        reason: '自动换一枚的表现不是报错，而是别人白名单里那条指向一台不再存在的设备',
      );
      expect(
        disk[FnthinkCredentialStore.addressCodeKey],
        'TOO_SHORT!',
        reason: '自愈式换码正是这条判据最坏的实现方式',
      );
    });

    testWidgets('身份取不到 ⇒ 说成身份问题，不伪装成网络或未配置', (tester) async {
      stubChannels(identityOk: false);
      final h = harness();
      final l10n = await pump(tester, h.page);
      expect(find.text(l10n.fnthinkKeystoreUnknown), findsOneWidget);
    });
  });

  group('开关那一格与状态那一格', () {
    testWidgets('默认关 ⇒ 开关关着、"立即收取"是灰的', (tester) async {
      stubChannels();
      final h = harness();
      final l10n = await pump(tester, h.page);
      expect(
        tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
        isFalse,
      );
      expect(find.text(l10n.fnthinkStatusIdle), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('fnthink-receive-now')),
            )
            .onPressed,
        isNull,
        reason: '关着时点它只会拿回 null，把按钮点亮是请用户来验证一条死路',
      );
    });

    testWidgets('翻开 ⇒ 写进 prefs、循环起来、状态行改口', (tester) async {
      stubChannels();
      final h = harness();
      final l10n = await pump(tester, h.page);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      // 注意读的是**不带前缀**的那个键：SharedPreferences 自己会加 `flutter.`，
      // 手抄前缀就变成找 `flutter.flutter.…`，那条断言会永远拿到 null（我第一版就是这么红的）。
      expect(prefs.getBool(FnthinkSettings.keyReceiveEnabled), isTrue);
      expect(h.builds(), 1);
      expect(h.coordinator.isRunning, isTrue);
      expect(find.text(l10n.fnthinkStatusRunning), findsOneWidget);
      expect(find.byKey(const ValueKey('fnthink-start-note')), findsNothing);
    });

    testWidgets('起不来 ⇒ 开关**留在开**、原话贴在下面（不回弹、不谎称在跑）', (tester) async {
      stubChannels();
      final h = harness(canSign: false);
      final l10n = await pump(tester, h.page);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
        isTrue,
        reason: 'prefs 已经是开的那一份；回弹说的是"你没点上"，而真实情况是"点上了但起不来"',
      );
      expect(find.text(l10n.fnthinkStatusIdle), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('fnthink-start-note')))
            .data,
        contains('signing-unavailable'),
        reason: '五种起不来各有各的用户动作，归并成"出错了"就没了可诊断性',
      );
      expect(h.builds(), 0, reason: '签名能力没探测过就不该建循环');
    });

    testWidgets('关掉 ⇒ 循环停、状态行改回来', (tester) async {
      stubChannels();
      final h = harness();
      final l10n = await pump(tester, h.page);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      expect(h.coordinator.isRunning, isFalse);
      expect(find.text(l10n.fnthinkStatusIdle), findsOneWidget);
    });
  });

  group('立即收取那一发', () {
    testWidgets('有货 ⇒ 上界面的是那笔账，而账里没有标题与正文', (tester) async {
      stubChannels();
      final h = harness(messages: const ['m_1'], pending: 2);
      await pump(tester, h.page);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fnthink-receive-now')));
      await tester.pumpAndSettle();
      final text = tester
          .widget<Text>(find.byKey(const ValueKey('fnthink-last-round')))
          .data!;
      expect(text, contains('取 1'));
      expect(text, contains('待取 2'));
      expect(text, isNot(contains('机箱温度')));
      expect(text, isNot(contains('温度 63 度')));
    });

    testWidgets('上一轮还在途 ⇒ 说"还在途"，不许说成"取 0 条"', (tester) async {
      stubChannels();
      final gate = Completer<void>();
      final h = harness(gate: () => gate.future, messages: const ['m_1']);
      final l10n = await pump(tester, h.page);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      // 起循环的那一轮此刻卡在 poll 上，这一发拿回的是"整轮跳过"那份账。
      await tester.tap(find.byKey(const ValueKey('fnthink-receive-now')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.fnthinkReceiveSkipped), findsOneWidget);
      expect(
        find.byKey(const ValueKey('fnthink-last-round')),
        findsNothing,
        reason: '把"跳过"显示成"取 0 条"，用户读到的是"服务器那边没有货"',
      );
      gate.complete();
      await tester.pumpAndSettle();
    });
  });

  group('三件套面板', () {
    testWidgets('挂出口令 ⇒ 口令显示出来，并顺手把地址码补上（口令没有落点的码等于没口令）', (tester) async {
      stubChannels();
      final h = harness();
      await pump(tester, h.page);
      await tester.tap(find.byKey(const ValueKey('fnthink-arm-pairing')));
      await tester.pumpAndSettle();
      expect(disk.containsKey(FnthinkCredentialStore.addressCodeKey), isTrue);
      expect(disk.containsKey(FnthinkCredentialStore.pairingCodeKey), isTrue);
      expect(
        find.text(disk[FnthinkCredentialStore.pairingCodeKey]!),
        findsOneWidget,
      );
    });

    testWidgets('口令挂了多久：时间戳缺失 ⇒ 显示"未知"，不许显示 0 秒', (tester) async {
      stubChannels();
      disk[FnthinkCredentialStore.pairingCodeKey] = validPairing;
      final h = harness();
      final l10n = await pump(tester, h.page);
      final text = tester
          .widget<Text>(find.byKey(const ValueKey('fnthink-pairing-age')))
          .data!;
      expect(text, l10n.fnthinkPairingHeld(l10n.unknown));
      expect(text, isNot(contains('0')));
    });

    // ── 挂口令那一发：界面必须分得清"本机记下了"与"服务器收下了" ──
    // 这三条各对一个"写歪了用户怎么被骗"：把两件事说成一件，对端扫码只会拿到"口令不存在"，
    // 而这一台上写着"已挂出 5 分钟"；反过来把"不知道"演成"没挂上"会清空一串仍然有效的码。

    testWidgets('服务器回了过期时间 ⇒ 明说"服务器已收到"，口令与倒计时同时在场', (tester) async {
      stubChannels();
      final h = harness();
      final l10n = await pump(tester, h.page);
      await tester.tap(find.byKey(const ValueKey('fnthink-arm-pairing')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('fnthink-pairing-acked')),
        findsOneWidget,
        reason: l10n.fnthinkPairingAcked,
      );
      expect(find.byKey(const ValueKey('fnthink-pairing-age')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('fnthink-pairing-local-only')),
        findsNothing,
      );
      expect(h.armAsked(), hasLength(1));
      expect(
        h.armAsked().single.url.path,
        contract.apiPath('pairArm'),
        reason: '那一发要打到契约声明的门上，而不是页面自己拼的某条路径',
      );
    });

    testWidgets('服务器没确认 ⇒ 说"只有这台记下了"，且**不清空那串仍然有效的码**', (tester) async {
      stubChannels();
      final h = harness(armBody: '{"serverTime":1800000000000}');
      await pump(tester, h.page);
      await tester.tap(find.byKey(const ValueKey('fnthink-arm-pairing')));
      await tester.pumpAndSettle();
      final code = disk[FnthinkCredentialStore.pairingCodeKey]!;
      expect(
        find.text(code),
        findsOneWidget,
        reason: '它在本机确实还有效（倒计时也在走）；抹掉它是替服务器撒第二次谎',
      );
      expect(find.byKey(const ValueKey('fnthink-pairing-acked')), findsNothing);
      final note = tester
          .widget<Text>(
            find.byKey(const ValueKey('fnthink-pairing-local-only')),
          )
          .data!;
      expect(
        note,
        isNot(contains('signing-unavailable')),
        reason: '这一条的原因是"服务器没给过期时间"，别套上身份问题的原话',
      );
      expect(note, isNotEmpty);
    });

    testWidgets('签不出来 ⇒ 一个字节都不发，但把原话贴在界面上', (tester) async {
      stubChannels();
      final h = harness(canSign: false);
      await pump(tester, h.page);
      await tester.tap(find.byKey(const ValueKey('fnthink-arm-pairing')));
      await tester.pumpAndSettle();
      expect(h.armAsked(), isEmpty);
      final note = tester
          .widget<Text>(
            find.byKey(const ValueKey('fnthink-pairing-local-only')),
          )
          .data!;
      expect(
        note,
        contains('signing-unavailable'),
        reason: '身份问题被折叠成"出错了"，用户就会去检查一直好好的网络',
      );
    });

    testWidgets('进页面读到本机存着一枚 ⇒ 说"没问过服务器"，且不替用户重发那一发', (tester) async {
      stubChannels();
      disk[FnthinkCredentialStore.pairingCodeKey] = validPairing;
      final h = harness();
      await pump(tester, h.page);
      expect(
        find.byKey(const ValueKey('fnthink-pairing-unknown')),
        findsOneWidget,
        reason: '这一台没发过那一发；显示成"已收到"或"没收到"都是在编',
      );
      expect(
        h.armAsked(),
        isEmpty,
        reason: '加载时顺手重发 = 页面自己造了一次用户没要求的网络请求（还会把口令消耗掉）',
      );
    });

    testWidgets('重置地址码：取消 ⇒ 码一个字都不动', (tester) async {
      stubChannels();
      disk[FnthinkCredentialStore.addressCodeKey] = validAddress;
      final h = harness();
      final l10n = await pump(tester, h.page);
      await tester.tap(find.byKey(const ValueKey('fnthink-reset-code')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(disk[FnthinkCredentialStore.addressCodeKey], validAddress);
      expect(h.builds(), 0);
    });

    testWidgets('重置地址码：确认 ⇒ 换新码，并且正在跑的循环被重启（旧码不许继续签）', (tester) async {
      stubChannels();
      disk[FnthinkCredentialStore.addressCodeKey] = validAddress;
      final h = harness();
      final l10n = await pump(tester, h.page);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      expect(h.builds(), 1);
      await tester.tap(find.byKey(const ValueKey('fnthink-reset-code')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      final fresh = disk[FnthinkCredentialStore.addressCodeKey];
      expect(fresh, isNot(validAddress));
      expect(find.text(fresh!), findsOneWidget);
      expect(h.builds(), 2, reason: '循环手里握的是启动那一刻定型的地址码，不重启就是拿旧码签新的请求');
    });
  });

  group('服务地址', () {
    testWidgets('多写了 scheme ⇒ 贴出校验原话，值一个字都不改', (tester) async {
      stubChannels();
      final h = harness();
      final l10n = await pump(tester, h.page);
      final before = contract.str(const ['transport', 'endpoints', 'default']);
      // 这一格在 ListView 的折叠线以下：不先滚进视口，tap 打在一个够不着的坐标上。
      // ⚠ 必须用 `revealTo`（滚到它被 build 出来）而不是 `ensureVisible`：名单那一格加进来之后
      //    服务地址卡已经落在 cacheExtent 之外，`ensureVisible` 拿到的是空 finder。
      final edit = find.widgetWithText(TextButton, l10n.edit);
      await revealTo(tester, edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('fnthink-host-input')),
        'https://Push.Example.COM',
      );
      await tester.tap(find.widgetWithText(TextButton, l10n.save));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('fnthink-host-error')))
            .data,
        contains('scheme'),
      );
      expect(find.text(before!), findsOneWidget, reason: '校验没过就不该改值');
    });

    testWidgets('合法值按归一后的那一份显示（大小写不是两台服务）', (tester) async {
      stubChannels();
      final h = harness();
      final l10n = await pump(tester, h.page);
      // 这一格在 ListView 的折叠线以下：不先滚进视口，tap 打在一个够不着的坐标上。
      // 同上一条：这一格已经在 cacheExtent 之外。
      final edit = find.widgetWithText(TextButton, l10n.edit);
      await revealTo(tester, edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('fnthink-host-input')),
        'PUSH.Example:8443',
      );
      await tester.tap(find.widgetWithText(TextButton, l10n.save));
      await tester.pumpAndSettle();
      expect(find.text('push.example:8443'), findsOneWidget);
      expect(find.byKey(const ValueKey('fnthink-host-error')), findsNothing);
      final resetDefault = find.byKey(const ValueKey('fnthink-host-default'));
      await revealTo(tester, resetDefault);
      await tester.pumpAndSettle();
      await tester.tap(resetDefault);
      await tester.pumpAndSettle();
      expect(
        find.text(contract.str(const ['transport', 'endpoints', 'default'])!),
        findsOneWidget,
      );
    });

    testWidgets('换地址与恢复默认都重启循环：屏幕上写的那个地址，就是正在取货的那个', (tester) async {
      // 理由与"重置地址码必须重启"是同一条：循环手里握的是**启动那一刻定型的 spec**
      // （baseUri 就在里面）。不重启的表现是"地址明明改了，货还是从旧地址取"，
      // 而用户下一个动作是把地址改回来 —— 那一改同样"没反应"，两下叠起来就是"这页坏了"。
      stubChannels();
      final h = harness();
      final l10n = await pump(tester, h.page);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      expect(h.builds(), 1, reason: '先把循环弄成"正在跑"，下面才有"该不该重启"可问');

      final edit = find.widgetWithText(TextButton, l10n.edit);
      await revealTo(tester, edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('fnthink-host-input')),
        'push.example:8443',
      );
      await tester.tap(find.widgetWithText(TextButton, l10n.save));
      await tester.pumpAndSettle();
      expect(find.text('push.example:8443'), findsOneWidget);
      expect(h.builds(), 2, reason: '改了地址而循环没重启 ⇒ 界面与在跑的那一份各说一段');

      final resetDefault = find.byKey(const ValueKey('fnthink-host-default'));
      await revealTo(tester, resetDefault);
      await tester.pumpAndSettle();
      await tester.tap(resetDefault);
      await tester.pumpAndSettle();
      expect(h.builds(), 3, reason: '恢复默认也是换地址，同一记重启');
    });

    testWidgets('校验没过（值没改）⇒ 不该白重启一次循环', (tester) async {
      stubChannels();
      final h = harness();
      final l10n = await pump(tester, h.page);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      expect(h.builds(), 1);

      final edit = find.widgetWithText(TextButton, l10n.edit);
      await revealTo(tester, edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('fnthink-host-input')),
        'https://push.example.com',
      );
      await tester.tap(find.widgetWithText(TextButton, l10n.save));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fnthink-host-error')), findsOneWidget);
      expect(h.builds(), 1, reason: '值都没落库就重启，等于把"改了没反应"做成"每改一次断一次线"');
    });
  });

  group('待确认的配对请求（T42 第五片）', () {
    FnthinkPairRequest request(String level) => FnthinkPairRequest(
      requestId: 'pr_9',
      requester: '8KMNPQRSTVWX999777',
      requesterPublicKey: 'AAAA',
      level: level,
    );

    /// 把"后台那一轮带回一条请求"这件事装好，再把页面盖上去。
    ///
    /// ⚠ 顺序是**先盖页面、后起循环**，然后靠 `tester.pump()` 推进那一轮：
    /// `testWidgets` 跑在 fake-async 时区里，`pumpEventQueue()` 那种"等真实事件队列"的写法
    /// 在这里不会自己走（`Future.delayed` 只有 pump 才推进），整个用例会挂死在
    /// `pumpAndSettle` 上 —— 第一版就在这里停了十分钟。
    /// 这个顺序恰好钉的是本片真正要的东西：页面开着的时候，后台那一轮带回来的请求**自己上界面**。
    Future<({AppLocalizations l10n, _Harness h})> openWith(
      WidgetTester tester, {
      required List<FnthinkPairRequest> requests,
      int confirmStatus = 200,
      String? confirmBody,
      Future<FnthinkPeerWrite> Function(FnthinkPeer peer)? recordPeer,
    }) async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final h = harness(
        pairRequests: requests,
        confirmStatus: confirmStatus,
        confirmBody:
            confirmBody ??
            '{"requestId":"pr_9","status":"approved","grantedLevel":"L1",'
                '"serverTime":1800000000000}',
        recordPeer: recordPeer,
      );
      final l10n = await pump(tester, h.page);
      await h.coordinator.startIfEnabled();
      await tester.pump();
      await tester.pumpAndSettle();
      return (l10n: l10n, h: h);
    }

    testWidgets('有人请求配对 ⇒ 这一格自己出现，两下都在', (tester) async {
      stubChannels();
      final ctx = await openWith(tester, requests: [request('L1')]);
      expect(
        find.byKey(const ValueKey('fnthink-pair-request-pr_9')),
        findsOneWidget,
        reason: '后台每轮带回来的东西要能自己上界面：用户挂出口令之后是盯着屏幕等的',
      );
      expect(
        find.text(ctx.l10n.fnthinkPairRequestLine('8KMNPQRSTVWX999777', 'L1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('fnthink-pair-approve-pr_9')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('fnthink-pair-deny-pr_9')),
        findsOneWidget,
      );
    });

    testWidgets('没有人请求 ⇒ 这一格根本不存在', (tester) async {
      stubChannels();
      final ctx = await openWith(tester, requests: const []);
      expect(
        find.text(ctx.l10n.fnthinkPairRequests),
        findsNothing,
        reason: '一张永远空的表等于让界面猜',
      );
      expect(find.byKey(const ValueKey('fnthink-pair-answer')), findsNothing);
    });

    testWidgets('同意之前要二次确认，弹层上写的是本机实际会给到的那一档', (tester) async {
      stubChannels();
      final ctx = await openWith(tester, requests: [request('L3')]);
      final approve = find.byKey(const ValueKey('fnthink-pair-approve-pr_9'));
      await tester.ensureVisible(approve);
      await tester.pumpAndSettle();
      await tester.tap(approve);
      await tester.pumpAndSettle();
      expect(
        find.text(ctx.l10n.fnthinkPairAskMsg('8KMNPQRSTVWX999777', 'L2')),
        findsOneWidget,
        reason: '让用户在他以为的档位上按下同意，而实际授出去的是另一档，那一下点得就没有意义',
      );
      expect(ctx.h.confirmAsked(), isEmpty, reason: '弹层还没点确认，那一发不该已经出去');
    });

    testWidgets('界面上那一句说的是服务端回的档位，不是用户点的那一档', (tester) async {
      stubChannels();
      final ctx = await openWith(
        tester,
        requests: [request('L2')],
        // 服务端那侧还有一道自己的封顶：本机发 L2，它记的是 L1。
        confirmBody:
            '{"requestId":"pr_9","status":"approved","grantedLevel":"L1",'
            '"serverTime":1800000000000}',
      );
      await _tapPair(tester, ctx.l10n, approve: true);
      expect(
        find.text(ctx.l10n.fnthinkPairApproved('8KMNPQRSTVWX999777', 'L1')),
        findsOneWidget,
      );
      expect(
        find.text(ctx.l10n.fnthinkPairApproved('8KMNPQRSTVWX999777', 'L2')),
        findsNothing,
        reason: '名单与界面要跟着服务端那一份走，否则显示 L2 而对面被限在 L1',
      );
      expect(ctx.h.peerRows().single.level, 'L1');
    });

    testWidgets('答复过的那一条不再出现（服务端一条只答一次）', (tester) async {
      stubChannels();
      final ctx = await openWith(tester, requests: [request('L1')]);
      await _tapPair(tester, ctx.l10n, approve: true);
      expect(
        find.byKey(const ValueKey('fnthink-pair-request-pr_9')),
        findsNothing,
        reason: '留着那一行等于请用户再点一下，而第二下只会换回一句同形的 403',
      );
      expect(
        find.byKey(const ValueKey('fnthink-pair-answer')),
        findsOneWidget,
        reason: '行消失了但结论要留得住：回头看不出自己同意还是被拒，等于没记账',
      );
    });

    testWidgets('服务端认了却没回档位 ⇒ 说"本机名单没写"，不说"已同意"', (tester) async {
      stubChannels();
      final ctx = await openWith(
        tester,
        requests: [request('L1')],
        confirmBody:
            '{"requestId":"pr_9","status":"approved","grantedLevel":null,'
            '"serverTime":1800000000000}',
      );
      await _tapPair(tester, ctx.l10n, approve: true);
      expect(find.text(ctx.l10n.fnthinkPairNoGrantedLevel), findsOneWidget);
      expect(
        find.text(ctx.l10n.fnthinkPairApproved('8KMNPQRSTVWX999777', 'L1')),
        findsNothing,
        reason: '不知道记到哪一档就不能写成"已同意"—— 那一格后面是给"取消配对"用的',
      );
      expect(ctx.h.peerRows(), isEmpty);
    });

    testWidgets('同一个地址码换了公钥 ⇒ 明说"一行都没改"', (tester) async {
      stubChannels();
      final ctx = await openWith(
        tester,
        requests: [request('L1')],
        recordPeer: (_) async => FnthinkPeerWrite.keySwapped,
      );
      await _tapPair(tester, ctx.l10n, approve: true);
      expect(
        find.text(ctx.l10n.fnthinkPairKeySwapped('8KMNPQRSTVWX999777')),
        findsOneWidget,
        reason: '报成"已同意"就是这台设备替用户点了"同意换钥"',
      );
    });

    testWidgets('档位读不懂的那一条 ⇒ 同意是灰的，拒绝还能点', (tester) async {
      stubChannels();
      final ctx = await openWith(tester, requests: [request('L9')]);
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('fnthink-pair-approve-pr_9')),
            )
            .onPressed,
        isNull,
        reason:
            '给一个没人请求过的档位，是替对方做决定；协调者那一发也不会发出去，'
            '把按钮点亮就是请用户来验证一条死路',
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('fnthink-pair-deny-pr_9')),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        find.byKey(const ValueKey('fnthink-pair-unknown-level-pr_9')),
        findsOneWidget,
      );
      expect(ctx.h.confirmAsked(), isEmpty);
    });

    testWidgets('看不懂的请求还能划掉：拒绝那一发照发，档位是封顶那一档', (tester) async {
      stubChannels();
      final ctx = await openWith(tester, requests: [request('L9')]);
      await _tapPair(tester, ctx.l10n, approve: false);
      final body = sentPayload(ctx.h.confirmAsked().single);
      expect(
        body['decision'],
        isNot(contract.pairConfirmApproveDecision),
        reason:
            '拒绝不写任何授权，服务端只要求这一键是个合法档位；'
            '连划掉都做不到，那条畸形请求就会一直挂在待确认栏里',
      );
      expect(body['level'], contract.pairConfirmLevelCeiling);
      expect(ctx.h.peerRows(), isEmpty);
    });

    testWidgets('服务端拒了 ⇒ 名单没写、那一行还留着、原话贴出来', (tester) async {
      stubChannels();
      final ctx = await openWith(
        tester,
        requests: [request('L1')],
        confirmStatus: 403,
        confirmBody: '{"receipt":"${contract.unsignedReceipt}"}',
      );
      await _tapPair(tester, ctx.l10n, approve: true);
      expect(ctx.h.peerRows(), isEmpty);
      expect(
        find.byKey(const ValueKey('fnthink-pair-request-pr_9')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('fnthink-pair-answer')),
        findsOneWidget,
        reason: '"没答应"这句要能被看见，而不是让那一行默默还在',
      );
    });
  });

  group('本机配对名单（T42「配对名单」那一格）', () {
    FnthinkPeer row(
      String address, {
      String level = 'L1',
      int at = 1780000111000,
    }) => FnthinkPeer(
      peerAddress: address,
      publicKey: 'AAAA',
      level: level,
      grantedAt: at,
      requestId: 'pr_9',
    );

    testWidgets('名单里有两台 ⇒ 两行都画出来，档位与时刻跟着名单走，边界那句在场', (tester) async {
      stubChannels();
      final h = harness(
        peers: [
          row('AAAAAAAAAAAAAAAAAAAA', level: 'L2', at: 1780000111000),
          row('BBBBBBBBBBBBBBBBBBBB'),
        ],
      );
      final l10n = await pump(tester, h.page);
      final first = find.byKey(
        const ValueKey('fnthink-peer-AAAAAAAAAAAAAAAAAAAA'),
      );
      await revealTo(tester, first);
      expect(first, findsOneWidget);
      final line = tester.widget<Text>(first).data!;
      expect(line, contains('AAAAAAAAAAAAAAAAAAAA'));
      expect(
        line,
        contains('L2'),
        reason: '档位显示的是名单里那一列（= 服务端当初回的那一档），不是页面上另算的一份',
      );
      expect(
        line,
        matches(RegExp(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}')),
        reason:
            '时刻按本机时区格式化。用例里**不许**写死一个绝对时刻字符串 —— '
            '那种断言换台机器就红，而红的不是任何一条判据',
      );
      expect(
        find.byKey(const ValueKey('fnthink-peer-BBBBBBBBBBBBBBBBBBBB')),
        findsOneWidget,
      );
      final boundary = find.byKey(const ValueKey('fnthink-peers-boundary'));
      await revealTo(tester, boundary);
      expect(
        tester.widget<Text>(boundary).data,
        l10n.fnthinkPeersBoundary,
        reason:
            '"撤销撤的是服务器那份授权、已收到的通知不删"必须与名单同屏，而且必须是**这一句**：'
            '少了它，那一行下面的按钮就会被读成"把这条记录删掉"，而屏幕上再没有别的出处',
      );
      expect(h.peerReads(), greaterThanOrEqualTo(1));
    });

    testWidgets('名单真的是空的 ⇒ 说"还没有配对过任何设备"', (tester) async {
      stubChannels();
      final h = harness();
      final l10n = await pump(tester, h.page);
      await revealTo(tester, find.byKey(const ValueKey('fnthink-peers-empty')));
      expect(
        find.text(l10n.fnthinkPeersEmpty),
        findsOneWidget,
        reason: '写入者已经有了（第五片），此时"没有"是一句真话 —— 前提是没有读失败',
      );
      expect(find.byKey(const ValueKey('fnthink-peers-error')), findsNothing);
    });

    testWidgets('名单读不出来 ⇒ 贴原话，不许显示成"还没有配对过任何设备"', (tester) async {
      stubChannels();
      final h = harness(peersFail: true);
      final l10n = await pump(tester, h.page);
      await revealTo(tester, find.byKey(const ValueKey('fnthink-peers-error')));
      expect(
        find.byKey(const ValueKey('fnthink-peers-error')),
        findsOneWidget,
        reason:
            '把"读不出来"显示成"一个都没有"，是这一格能做出的最坏的一件事：'
            '用户会以为自己没配过任何设备，然后重新挂口令',
      );
      expect(find.text(l10n.fnthinkPeersEmpty), findsNothing);
      expect(find.textContaining('库打不开'), findsOneWidget);
    });

    testWidgets('同意之后名单重读一次：新那一条不点别处就出现在格子里', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      final h = harness(
        pairRequests: const [
          FnthinkPairRequest(
            requestId: 'pr_9',
            requester: '8KMNPQRSTVWX999777',
            requesterPublicKey: 'AAAA',
            level: 'L1',
          ),
        ],
      );
      final l10n = await pump(tester, h.page);
      await h.coordinator.startIfEnabled();
      await tester.pump();
      await tester.pumpAndSettle();
      final before = h.peerReads();
      await _tapPair(tester, l10n, approve: true);
      await revealTo(
        tester,
        find.byKey(const ValueKey('fnthink-peer-8KMNPQRSTVWX999777')),
      );
      expect(
        h.peerReads(),
        greaterThan(before),
        reason: '名单是"同意"那一发的后果。不重读，用户点完同意，下面那格还是旧的',
      );
      expect(
        find.byKey(const ValueKey('fnthink-peer-8KMNPQRSTVWX999777')),
        findsOneWidget,
      );
    });

    testWidgets('grantedAt 是 0 ⇒ 那一行写"—"，不写成 1970 年', (tester) async {
      stubChannels();
      final h = harness(peers: [row('CCCCCCCCCCCCCCCCCCCC', at: 0)]);
      await pump(tester, h.page);
      final target = find.byKey(
        const ValueKey('fnthink-peer-CCCCCCCCCCCCCCCCCCCC'),
      );
      await revealTo(tester, target);
      final line = tester.widget<Text>(target).data!;
      expect(
        line,
        isNot(contains('1970')),
        reason: '1970-01-01 把"这一行没有时间"伪装成"很久以前同意过"—— 那是两个不同的结论',
      );
      expect(line, contains('—'));
    });
  });

  group('名单上那一下「撤销」（T31 B 片第二片）', () {
    FnthinkPeer peerRow(
      String address, {
      String level = 'L1',
      int at = 1780000111000,
    }) => FnthinkPeer(
      peerAddress: address,
      publicKey: 'AAAA',
      level: level,
      grantedAt: at,
      requestId: 'pr_9',
    );

    /// 走完「撤销 → 二次确认」。
    /// ⚠ 这里要 `revealTo`（滚到被 build 出来）**再** `ensureVisible`（把它滚进视口）：
    ///   `ListView` 懒建，`revealTo` 在"已经 build 但在屏幕外"时直接返回，此时 `tap` 会
    ///   打到一个 hit-test 打不中的坐标（点了等于没点，弹层永远不出现）。
    Future<void> tapRevoke(
      WidgetTester tester,
      AppLocalizations l10n,
      String address,
    ) async {
      final button = find.byKey(ValueKey('fnthink-peer-revoke-$address'));
      await revealTo(tester, button);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('点了不等于撤了：那一发要先过二次确认', (tester) async {
      stubChannels();
      final h = harness(peers: [peerRow('AAAAAAAAAAAAAAAAAAAA')]);
      final l10n = await pump(tester, h.page);
      await tapRevoke(tester, l10n, 'AAAAAAAAAAAAAAAAAAAA');
      expect(
        find.text(l10n.fnthinkRevokeAskTitle),
        findsOneWidget,
        reason:
            'T06：删除一律二次确认。撤销删的是"别人还能不能推给我"这件事，'
            '点错一下的代价是对方要重新扫码，而界面上一句都看不见',
      );
      expect(h.revokeAsked(), isEmpty);
      expect(h.removed(), isEmpty, reason: '弹层还在时本机一行都不该动');
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      expect(h.revokeAsked(), hasLength(1));
    });

    testWidgets('撤成 ⇒ 那一行从格子里消失，而结论说的是服务端的事实', (tester) async {
      stubChannels();
      final h = harness(peers: [peerRow('BBBBBBBBBBBBBBBBBBBB')]);
      final l10n = await pump(tester, h.page);
      final before = h.peerReads();
      await tapRevoke(tester, l10n, 'BBBBBBBBBBBBBBBBBBBB');
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      expect(h.removed(), [
        'BBBBBBBBBBBBBBBBBBBB',
      ], reason: '删行由协调者在服务端认了之后调，页面不自己动表');
      expect(h.peerReads(), greaterThan(before), reason: '名单是这一发的后果，不重读就是旧的');
      expect(
        find.byKey(const ValueKey('fnthink-peer-BBBBBBBBBBBBBBBBBBBB')),
        findsNothing,
      );
      final note = find.byKey(const ValueKey('fnthink-peer-revoke-note'));
      await revealTo(tester, note);
      expect(tester.widget<Text>(note).data, isNot(contains('撤销没成')));
    });

    testWidgets('那边本来没有这一条（revoked:false）⇒ 那一行也消失，而且不当成失败', (tester) async {
      stubChannels();
      final h = harness(
        peers: [peerRow('CCCCCCCCCCCCCCCCCCCC')],
        revokeBody: '{"revoked":false,"serverTime":1800000000000}',
      );
      final l10n = await pump(tester, h.page);
      await tapRevoke(tester, l10n, 'CCCCCCCCCCCCCCCCCCCC');
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      expect(h.removed(), hasLength(1), reason: '撤销是幂等的：目标状态已达成就是成功');
      final note = find.byKey(const ValueKey('fnthink-peer-revoke-note'));
      await revealTo(tester, note);
      expect(tester.widget<Text>(note).data, contains('幂等'));
      expect(find.text(l10n.fnthinkPeersEmpty), findsOneWidget);
    });

    testWidgets('服务端拒了 ⇒ 那一行必须还留着，而那句说的不是"已撤销"', (tester) async {
      stubChannels();
      final h = harness(
        peers: [peerRow('DDDDDDDDDDDDDDDDDD')],
        revokeStatus: 403,
        revokeBody: '{"receipt":"rejected_capability"}',
      );
      final l10n = await pump(tester, h.page);
      await tapRevoke(tester, l10n, 'DDDDDDDDDDDDDDDDDD');
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      expect(h.revokeAsked(), hasLength(1));
      expect(
        h.removed(),
        isEmpty,
        reason:
            '撤失败却删了行＝"授权还在而来源从屏幕上消失"：对面照样推得进来，'
            '而这一台再也看不见它是谁 —— 那是最难发现的一种静默',
      );
      expect(
        find.byKey(const ValueKey('fnthink-peer-DDDDDDDDDDDDDDDDDD')),
        findsOneWidget,
      );
      final note = find.byKey(const ValueKey('fnthink-peer-revoke-note'));
      await revealTo(tester, note);
      expect(tester.widget<Text>(note).data, contains('撤销没成'));
    });

    testWidgets('服务器撤了而本机删行抛 ⇒ 说得出"那一行还留着"，不说成撤销失败', (tester) async {
      stubChannels();
      final h = harness(
        peers: [peerRow('EEEEEEEEEEEEEEEEEEEE')],
        removePeer: (_) async => throw StateError('表被锁'),
      );
      final l10n = await pump(tester, h.page);
      await tapRevoke(tester, l10n, 'EEEEEEEEEEEEEEEEEEEE');
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      final note = find.byKey(const ValueKey('fnthink-peer-revoke-note'));
      await revealTo(tester, note);
      expect(
        tester.widget<Text>(note).data,
        l10n.fnthinkRevokeRowRemains,
        reason: '报成"撤销没成"会请用户再点一次，而那一次换来的是一句幂等的成功',
      );
      expect(
        find.byKey(const ValueKey('fnthink-peer-EEEEEEEEEEEEEEEEEEEE')),
        findsOneWidget,
      );
    });

    testWidgets('签不出来 ⇒ 那一发不发、那一行留着（与答复那一路同一道闸）', (tester) async {
      stubChannels();
      final h = harness(
        canSign: false,
        peers: [peerRow('FFFFFFFFFFFFFFFFFFFF')],
      );
      final l10n = await pump(tester, h.page);
      await tapRevoke(tester, l10n, 'FFFFFFFFFFFFFFFFFFFF');
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      expect(h.revokeAsked(), isEmpty);
      expect(h.removed(), isEmpty);
      expect(
        find.byKey(const ValueKey('fnthink-peer-FFFFFFFFFFFFFFFFFFFF')),
        findsOneWidget,
      );
    });
  });

  group('接入端点那一格（T42 第七片）', () {
    testWidgets('点一下 ⇒ 出现 id、那把口令，和"只出现这一次"那句', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness();
      final l10n = await pump(tester, h.page);
      final button = find.byKey(const ValueKey('fnthink-endpoint-create'));
      await revealTo(tester, button);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(h.endpointAsked(), hasLength(1));
      for (final key in [
        'fnthink-endpoint-id',
        'fnthink-endpoint-secret',
        'fnthink-endpoint-once',
      ]) {
        final target = find.byKey(ValueKey(key));
        await revealTo(tester, target);
        expect(target, findsOneWidget, reason: '$key 缺席：口令只显示这一次，少一行就等于没给');
      }
      expect(
        find.text(l10n.fnthinkEndpointSecret('ABCDEFGHIJKLMNOP2345678901')),
        findsOneWidget,
        reason: '那一行必须是**这一把**口令本身，不是"已生成"这种代词 —— 用户要抄的就是这串字符',
      );
    });

    testWidgets('口令不落盘：prefs 里没有它，键名里也没有它', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness();
      await pump(tester, h.page);
      final button = find.byKey(const ValueKey('fnthink-endpoint-create'));
      await revealTo(tester, button);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      const secret = 'ABCDEFGHIJKLMNOP2345678901';
      expect(
        prefs.getKeys().where((k) => '${prefs.get(k)}'.contains(secret)),
        isEmpty,
        reason: '服务端只存摘要，本机若存明文那一份，泄露的就是这台设备而不是那把口令的摘要',
      );
      expect(
        prefs.getKeys().where((k) => k.toLowerCase().contains('secret')),
        isEmpty,
        reason: '连"存了一个口令"这件事都不该出现在本机设置里',
      );
    });

    testWidgets('上限那句里的数来自契约（把契约那一位改掉，界面跟着改）', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final raw =
          jsonDecode(File('protocol/fnthink-v1.json').readAsStringSync())
              as Map<String, Object?>;
      final shrunk = {
        ...raw,
        'endpoint': {
          ...(raw['endpoint']! as Map<String, Object?>),
          'perDeviceMax': 3,
        },
      };
      final h = harness(contractText: jsonEncode(shrunk));
      final l10n = await pump(tester, h.page);
      final cap = find.byKey(const ValueKey('fnthink-endpoint-cap'));
      await revealTo(tester, cap);
      expect(
        tester.widget<Text>(cap).data,
        l10n.fnthinkEndpointCap(3),
        reason:
            '断言不能拿同一份契约去比实现（那样"写死 10"与"读契约"当场分不出来）；'
            '这里改的是契约那一位，界面要是跟着它走才算读过',
      );
    });

    testWidgets('没建成 ⇒ 贴原话，且不出现口令行', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(endpointStatus: 429, endpointBody: '{}');
      await pump(tester, h.page);
      final button = find.byKey(const ValueKey('fnthink-endpoint-create'));
      await revealTo(tester, button);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final note = find.byKey(const ValueKey('fnthink-endpoint-error'));
      await revealTo(tester, note);
      expect(note, findsOneWidget);
      expect(
        find.byKey(const ValueKey('fnthink-endpoint-secret')),
        findsNothing,
      );
    });

    testWidgets('服务端认了但读不出口令 ⇒ 走"没建成"那一句，不显示一把抄不到的入口', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(endpointBody: '{"endpointId":"ep_7","serverTime":1}');
      await pump(tester, h.page);
      final button = find.byKey(const ValueKey('fnthink-endpoint-create'));
      await revealTo(tester, button);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final note = find.byKey(const ValueKey('fnthink-endpoint-error'));
      await revealTo(tester, note);
      expect(
        tester.widget<Text>(note).data,
        contains('endpoint-create-unparsable-ack'),
        reason: '"建好了但抄不到"是最坏的一种显示：表里多了一行，而用户以为自己有',
      );
      expect(find.byKey(const ValueKey('fnthink-endpoint-id')), findsNothing);
    });
  });

  group('接入端点那一格的"读"（#157 第二片）', () {
    Future<void> tapRead(WidgetTester tester) async {
      final button = find.byKey(const ValueKey('fnthink-endpoint-read'));
      await revealTo(tester, button);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('只是翻开页面 ⇒ 那一发没发出去，而界面说的是"还没读过"', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness();
      final l10n = await pump(tester, h.page);
      expect(
        h.endpointListAsked(),
        isEmpty,
        reason: '进页面那一刻服务地址与身份还没就位，发出去读回的失败会被当成第一句话',
      );
      final note = find.byKey(const ValueKey('fnthink-endpoint-list-pending'));
      await revealTo(tester, note);
      expect(
        tester.widget<Text>(note).data,
        l10n.fnthinkEndpointListPending,
        reason: '"没有"与"还没看"必须是两句话 —— 空格子会被读成前者',
      );
      expect(
        find.byKey(const ValueKey('fnthink-endpoint-list-none')),
        findsNothing,
      );
    });

    testWidgets('点那一下 ⇒ 一行一条，已吊销那条也带出来并说它不收信了', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(
        // 这里不带 `owner` 字段：owner 那一刀（别人名下一行也不进结果）钉在包内用例
        // （receive_kernel_test 的「别人名下一行漏出来」），这一组测的是"读回来的怎么画"。
        endpointListBody:
            '{"endpoints":['
            '{"id":"ep_new","name":"自家 NAS","status":"active","postOnly":true,'
            '"createdAt":1700000000000},'
            '{"id":"ep_old","name":"","status":"revoked","createdAt":1600000000000}'
            '],"serverTime":1800000000000}',
      );
      final l10n = await pump(tester, h.page);
      await tapRead(tester);
      expect(h.endpointListAsked(), hasLength(1));

      final named = find.byKey(const ValueKey('fnthink-endpoint-row-ep_new'));
      await revealTo(tester, named);
      expect(
        tester.widget<Text>(named).data,
        '${l10n.fnthinkEndpointRowNamed('自家 NAS', 'ep_new')} · '
        '${l10n.fnthinkEndpointUsable}',
        reason: '那一行要的是**这一把**的 id 与名字，不是"你有几把"这种代词',
      );
      final revoked = find.byKey(const ValueKey('fnthink-endpoint-row-ep_old'));
      await revealTo(tester, revoked);
      expect(
        tester.widget<Text>(revoked).data,
        '${l10n.fnthinkEndpointRowUnnamed('ep_old')} · '
        '${l10n.fnthinkEndpointNotUsable('revoked')}',
        reason: '没起名要说"未命名"；已吊销的那行不能消失，否则"我明明建过"变成"界面说没有"',
      );
      expect(
        find.byKey(const ValueKey('fnthink-endpoint-list-none')),
        findsNothing,
      );
    });

    testWidgets('读到确实一把都没有 ⇒ 说"没有"，而不是"没读到"', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness();
      await pump(tester, h.page);
      await tapRead(tester);
      final none = find.byKey(const ValueKey('fnthink-endpoint-list-none'));
      await revealTo(tester, none);
      expect(none, findsOneWidget);
      expect(
        find.byKey(const ValueKey('fnthink-endpoint-list-failed')),
        findsNothing,
      );
    });

    testWidgets('读失败 ⇒ 说"这一次没读到"并贴原话，绝不冒出"你没有端点"那句', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(endpointListStatus: 403, endpointListBody: '{}');
      await pump(tester, h.page);
      await tapRead(tester);
      final failed = find.byKey(const ValueKey('fnthink-endpoint-list-failed'));
      await revealTo(tester, failed);
      expect(failed, findsOneWidget);
      expect(
        find.byKey(const ValueKey('fnthink-endpoint-list-none')),
        findsNothing,
        reason: '把失败画成"没有"，用户就会当着一次失败的面去配 NAS，或把还在收信的入口当成不存在',
      );
      expect(
        find.byKey(const ValueKey('fnthink-endpoint-list-pending')),
        findsNothing,
      );
    });

    testWidgets('已经读过再建一把 ⇒ 立刻重读，界面上不留在"2 把"', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness();
      await pump(tester, h.page);
      await tapRead(tester);
      expect(h.endpointListAsked(), hasLength(1));
      final button = find.byKey(const ValueKey('fnthink-endpoint-create'));
      await revealTo(tester, button);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        h.endpointListAsked(),
        hasLength(2),
        reason: '刚建完还写着"没有"，与写着"有 3 把"而实际 2 把是同一句假话，只是方向反了',
      );
    });

    testWidgets('还没读过就建一把 ⇒ 不凭空开始读（第一句还是口令那一行）', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness();
      await pump(tester, h.page);
      final button = find.byKey(const ValueKey('fnthink-endpoint-create'));
      await revealTo(tester, button);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        h.endpointListAsked(),
        isEmpty,
        reason: '用户没要求过这一次读；替他在界面上凭空生成一份列表，是把"还没看过"换成了"我造的"',
      );
      expect(
        find.byKey(const ValueKey('fnthink-endpoint-list-pending')),
        findsOneWidget,
      );
    });

    testWidgets('签不出来 ⇒ 那一发不发，说的是"这一次没读到"再加那一句原话', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(canSign: false);
      await pump(tester, h.page);
      await tapRead(tester);
      expect(h.endpointListAsked(), isEmpty);
      expect(
        find.byKey(const ValueKey('fnthink-endpoint-list-none')),
        findsNothing,
        reason: '签不出来与"名下没有"是两件事：冒成后者，用户会去新建一把而旧的那把还在收信',
      );
      final failed = find.byKey(const ValueKey('fnthink-endpoint-list-failed'));
      await revealTo(tester, failed);
      expect(
        tester.widget<Text>(failed).data,
        contains('signing-unavailable'),
        reason: '用户点了那一下，就要听到**这一次**为什么没成，而不是继续一句"还没读过"',
      );
    });
  });

  group('关掉一把入口（#157 第四片）', () {
    // 一把还在收信 + 一把已经停了：后者**不该**再有"关掉"那一下（点了只会拿到一句幂等成功，
    // 而界面上摆一个没有后果的按钮，就是教用户以为按钮都是这么回事）。
    const twoRows =
        '{"endpoints":['
        '{"id":"ep_live","name":"nas","status":"active","postOnly":true},'
        '{"id":"ep_dead","name":"","status":"revoked"}'
        '],"serverTime":1800000000000}';

    Future<void> readList(WidgetTester tester) async {
      final button = find.byKey(const ValueKey('fnthink-endpoint-read'));
      await revealTo(tester, button);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    Future<void> tapClose(WidgetTester tester, String id) async {
      final button = find.byKey(ValueKey('fnthink-endpoint-revoke-$id'));
      await revealTo(tester, button);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('列表里那一下先过二次确认；确认之前一发都不出去', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(endpointListBody: twoRows);
      final l10n = await pump(tester, h.page);
      await readList(tester);
      await tapClose(tester, 'ep_live');
      expect(
        h.endpointRevokeAsked(),
        isEmpty,
        reason: '关掉一把入口改的是"别人还能不能往这台设备推"，手滑的代价在另一台机器上',
      );
      expect(
        find.text(l10n.fnthinkEndpointRevokeAskMsg('ep_live')),
        findsOneWidget,
        reason: '弹层上写的必须是**这一把**的 id：一句"确定吗"关不掉任何问责',
      );
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      expect(h.endpointRevokeAsked(), hasLength(1));
      final note = find.byKey(const ValueKey('fnthink-endpoint-revoke-note'));
      await revealTo(tester, note);
      expect(
        tester.widget<Text>(note).data,
        l10n.fnthinkEndpointRevoked('ep_live'),
      );
    });

    testWidgets('弹层上点取消 ⇒ 那一发不发，也不留下任何结论行', (tester) async {
      // 这一条与上一条是**一对**：上一条只走"确定"那一支，摘掉 `if (!ok || !mounted) return;`
      // 在它身上完全看不出来（askConfirm 本身是 await 的，取消没被取消也不影响时序）。
      // 反证 SA6 第一次就是在这里 NO FAILURE 的 —— 补了这一条，那一道闸才真的可观察。
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(endpointListBody: twoRows);
      final l10n = await pump(tester, h.page);
      await readList(tester);
      await tapClose(tester, 'ep_live');
      expect(
        find.text(l10n.fnthinkEndpointRevokeAskMsg('ep_live')),
        findsOneWidget,
      );
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(h.endpointRevokeAsked(), isEmpty, reason: '取消就是取消：一个字节都不该离机');
      expect(
        find.byKey(const ValueKey('fnthink-endpoint-revoke-note')),
        findsNothing,
        reason: '没做过的事不在界面上留结论',
      );
    });

    testWidgets('关掉之后重读一次列表（屏幕跟上服务端，而不是自己把那行画灰）', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(endpointListBody: twoRows);
      final l10n = await pump(tester, h.page);
      await readList(tester);
      expect(h.endpointListAsked(), hasLength(1));
      await tapClose(tester, 'ep_live');
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      expect(
        h.endpointListAsked(),
        hasLength(2),
        reason:
            '那一行还在列表里（服务端不删行）；界面若自己把它涂成灰，'
            '下一次读之前那份灰就是唯一的真值',
      );
    });

    testWidgets('已经停了的那一把不再给"关掉"那一下', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(endpointListBody: twoRows);
      await pump(tester, h.page);
      await readList(tester);
      final live = find.byKey(
        const ValueKey('fnthink-endpoint-revoke-ep_live'),
      );
      await revealTo(tester, live);
      expect(live, findsOneWidget);
      expect(
        find.byKey(const ValueKey('fnthink-endpoint-revoke-ep_dead')),
        findsNothing,
        reason: '那一行没有可关的东西了；给它一个按下去只拿到幂等成功的按钮，是摆一个假动作',
      );
    });

    testWidgets('服务端拒了 ⇒ 说的是"这把没关掉"，而那一行还挂着', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(
        endpointListBody: twoRows,
        endpointRevokeStatus: 403,
        endpointRevokeBody: '{}',
      );
      final l10n = await pump(tester, h.page);
      await readList(tester);
      await tapClose(tester, 'ep_live');
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      final note = find.byKey(const ValueKey('fnthink-endpoint-revoke-note'));
      await revealTo(tester, note);
      expect(
        tester.widget<Text>(note).data,
        isNot(l10n.fnthinkEndpointRevoked('ep_live')),
        reason: '"已关闭"说错一次的代价是：用户不再去管那把，而 NAS 还在往它推',
      );
      expect(
        tester.widget<Text>(note).data,
        isNot(contains('ep_live')),
        reason: '那一句说的是"这次没关掉"，不去复述 id：复述会诱导出"按 id 找行"的假断言',
      );
      final row = find.byKey(const ValueKey('fnthink-endpoint-row-ep_live'));
      await revealTo(tester, row);
      expect(row, findsOneWidget, reason: '没关掉 ⇒ 服务端那一份还是原来的样子，列表按它显示（不自己删行）');
    });

    testWidgets('那边本来就不收了（revoked:false）⇒ 走成功那一路，不说失败', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(
        endpointListBody: twoRows,
        endpointRevokeBody:
            '{"endpointId":"ep_live","revoked":false,"serverTime":1800000000000}',
      );
      final l10n = await pump(tester, h.page);
      await readList(tester);
      await tapClose(tester, 'ep_live');
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      final note = find.byKey(const ValueKey('fnthink-endpoint-revoke-note'));
      await revealTo(tester, note);
      expect(
        tester.widget<Text>(note).data,
        l10n.fnthinkEndpointRevokeAlreadyGone('ep_live'),
        reason:
            '撤销的目标状态是"它不再收信"，本来就不收信就是已达成 —— '
            '报成失败会让人再点一次，而第二次换来的还是一句 200',
      );
    });

    testWidgets('签不出来 ⇒ 那一发不发，而**按不到那一下**（读不成功就没有列表行）', (tester) async {
      // 这一条今天只能断到"读不成功 ⇒ 页面没有任何可点的行"：那一发的守卫
      // （签不出来 ⇒ 不发 + 原话）在协调者用例里钉（`revokeEndpoint（#157 第四片）` 那一组）。
      // 与其在这里造一个页面根本不会出现的按钮，不如把"为什么这里断不了"写下来。
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(canSign: false, endpointListBody: twoRows);
      await pump(tester, h.page);
      await readList(tester);
      expect(
        h.endpointListAsked(),
        isEmpty,
        reason: '签不出来 ⇒ 一个字节都不离机（读那一发也不例外）：那一刻连"有几把"都无从知道',
      );
      expect(
        find.byKey(const ValueKey('fnthink-endpoint-revoke-ep_live')),
        findsNothing,
        reason: '读都没读到，就不该有"关掉某一行的具体哪一把"那一下 —— 那一刻连 id 都没有',
      );
      expect(h.endpointRevokeAsked(), isEmpty);
    });
  });

  group('换一把入口的口令（#157 第六片）', () {
    const oneLive =
        '{"endpoints":[{"id":"ep_live","name":"nas","status":"active"}],'
        '"serverTime":1800000000000}';
    const oneDead =
        '{"endpoints":[{"id":"ep_dead","name":"nas","status":"revoked"}],'
        '"serverTime":1800000000000}';

    Future<void> readList(WidgetTester tester) async {
      final button = find.byKey(const ValueKey('fnthink-endpoint-read'));
      await revealTo(tester, button);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    Future<void> tapRotate(WidgetTester tester, String id) async {
      final button = find.byKey(ValueKey('fnthink-endpoint-rotate-$id'));
      await revealTo(tester, button);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('换成功 ⇒ 新口令那一行就是这一把，宽限期那一行跟着服务端回的时刻', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(
        endpointListBody: oneLive,
        // rotatingUntil 给 0：这一支要断的是"时刻是服务端给的、不是本机算的"，
        // 而 `_formatTime(0)` 的那一个 '—' 是"这一刻不可用"的既有表示 —— 不用碰时钟就能断。
        endpointRotateBody:
            '{"endpointId":"ep_live","rotated":true,'
            '"secret":"ZZZ7RABQKPZ3STVWX234","rotatingUntil":0}',
      );
      final l10n = await pump(tester, h.page);
      await readList(tester);
      await tapRotate(tester, 'ep_live');
      expect(find.text(l10n.fnthinkEndpointRotateAskMsg), findsOneWidget);
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      expect(h.endpointRotateAsked(), hasLength(1));
      final secret = find.byKey(
        const ValueKey('fnthink-endpoint-rotated-secret'),
      );
      await revealTo(tester, secret);
      // `SelectableText.text` 在这个 Flutter 版本上没有 getter ⇒ 断"界面上有这一串字符"（与创建那一次同一写法）。
      expect(
        find.text(l10n.fnthinkEndpointSecret('ZZZ7RABQKPZ3STVWX234')),
        findsOneWidget,
        reason: '那一行必须是**这一把**新口令：换过一次而抄不到，等于旧那把在倒计时而没人有新口令',
      );
      final grace = find.byKey(const ValueKey('fnthink-endpoint-rotate-grace'));
      await revealTo(tester, grace);
      expect(tester.widget<Text>(grace).data, isNotNull);
    });

    testWidgets('服务端没回 rotatingUntil ⇒ 那一行根本不出现（不编一个截止时间）', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(
        endpointListBody: oneLive,
        endpointRotateBody:
            '{"endpointId":"ep_live","rotated":true,'
            '"secret":"ZZZ7RABQKPZ3STVWX234"}',
      );
      final l10n = await pump(tester, h.page);
      await readList(tester);
      await tapRotate(tester, 'ep_live');
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('fnthink-endpoint-rotate-grace')),
        findsNothing,
        reason: '说一句"还能用到 X"而 X 是猜的，比不说更糟：用户会按那个钟去改 NAS',
      );
      expect(
        find.byKey(const ValueKey('fnthink-endpoint-rotated-secret')),
        findsOneWidget,
      );
    });

    testWidgets('换完重读一次列表：旧那把的截止日期以服务端那一份为准', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(endpointListBody: oneLive);
      final l10n = await pump(tester, h.page);
      await readList(tester);
      expect(h.endpointListAsked(), hasLength(1));
      await tapRotate(tester, 'ep_live');
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      expect(
        h.endpointListAsked(),
        hasLength(2),
        reason: '本机不留一份"我换过了"的账：那份表在服务端，重读才是此刻的真话',
      );
    });

    testWidgets('弹层上点取消 ⇒ 那一发不发（旧口令不该开始倒计时）', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(endpointListBody: oneLive);
      final l10n = await pump(tester, h.page);
      await readList(tester);
      await tapRotate(tester, 'ep_live');
      expect(find.text(l10n.fnthinkEndpointRotateAskMsg), findsOneWidget);
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(
        h.endpointRotateAsked(),
        isEmpty,
        reason: '换一把会让正在用的那把开始倒计时 —— 没确认之前一个字节都不出去',
      );
      expect(
        find.byKey(const ValueKey('fnthink-endpoint-rotate-note')),
        findsNothing,
      );
    });

    testWidgets('那把本来就不收了（rotated:false）⇒ 说"没给它换"，不出现口令行', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(
        endpointListBody: oneLive,
        endpointRotateBody:
            '{"endpointId":"ep_live","rotated":false,"serverTime":1800000000000}',
      );
      final l10n = await pump(tester, h.page);
      await readList(tester);
      await tapRotate(tester, 'ep_live');
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      final note = find.byKey(const ValueKey('fnthink-endpoint-rotate-note'));
      await revealTo(tester, note);
      expect(
        tester.widget<Text>(note).data,
        l10n.fnthinkEndpointRotateNotRotated('ep_live'),
        reason: '这不是失败：报成失败会让人再点一次，而每次都是给一个不工作的端点换口令',
      );
      expect(
        find.byKey(const ValueKey('fnthink-endpoint-rotated-secret')),
        findsNothing,
      );
    });

    testWidgets('服务端说换了却没口令 ⇒ 走"没换成"，reason 单独那一句要看得见', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(
        endpointListBody: oneLive,
        endpointRotateBody: '{"endpointId":"ep_live","rotated":true}',
      );
      final l10n = await pump(tester, h.page);
      await readList(tester);
      await tapRotate(tester, 'ep_live');
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      final note = find.byKey(const ValueKey('fnthink-endpoint-rotate-note'));
      await revealTo(tester, note);
      expect(
        tester.widget<Text>(note).data,
        contains('endpoint-rotate-missing-new-secret'),
        reason: '这一档表里真换掉了：说成"没换成"会让人以为旧的还能用，而那正是 NAS 401 的那一刻',
      );
    });

    testWidgets('已经停了的那一把，"关掉"与"换一把"两下都不给', (tester) async {
      stubChannels();
      SharedPreferences.setMockInitialValues({});
      final h = harness(endpointListBody: oneDead);
      await pump(tester, h.page);
      await readList(tester);
      final row = find.byKey(const ValueKey('fnthink-endpoint-row-ep_dead'));
      await revealTo(tester, row);
      expect(row, findsOneWidget, reason: '那一行要看得见（它记录了停过），但不给可点的假动作');
      expect(
        find.byKey(const ValueKey('fnthink-endpoint-revoke-ep_dead')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('fnthink-endpoint-rotate-ep_dead')),
        findsNothing,
      );
    });
  });

  group('发一条给名单里那台（§4-10 片2b）', () {
    const peerAddress = 'AAAAAAAAAAAAAAAAAAAA';

    Future<void> tapSend(WidgetTester tester) async {
      final button = find.byKey(
        const ValueKey('fnthink-peer-send-$peerAddress'),
      );
      await revealTo(tester, button);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    Future<void> fill(
      WidgetTester tester, {
      String title = '',
      String body = '',
    }) async {
      await tester.enterText(
        find.byKey(const ValueKey('fnthink-send-title')),
        title,
      );
      await tester.enterText(
        find.byKey(const ValueKey('fnthink-send-body')),
        body,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('没配对过任何一台 ⇒ 这一格根本没有发送入口', (tester) async {
      stubChannels();
      final h = harness();
      await pump(tester, h.page);
      expect(
        find.byKey(const ValueKey('fnthink-peer-send-$peerAddress')),
        findsNothing,
        reason: '收件人只能来自本机名单；给一个没有候选的入口，点下去只会换回一句 403',
      );
      expect(h.sendAsked(), isEmpty);
    });

    testWidgets('填上正文点发送 ⇒ 打到契约那扇门，而标题在已签的正文里', (tester) async {
      stubChannels();
      final h = harness(
        peers: [
          const FnthinkPeer(
            peerAddress: peerAddress,
            publicKey: 'AAAApublicKeyBytesForTests',
            level: 'L1',
            grantedAt: 1800000000000,
            requestId: 'pr_9',
          ),
        ],
      );
      final l10n = await pump(tester, h.page);
      await tapSend(tester);
      await fill(tester, title: '到家了', body: '门已开');
      await tester.tap(find.byKey(const ValueKey('fnthink-send-submit')));
      await tester.pumpAndSettle();

      final request = h.sendAsked().single;
      expect(request.url.path, contract.apiPath('message'));
      final envelope = jsonDecode(request.body) as Map<String, Object?>;
      expect(envelope.keys.toSet(), {'sender', 'signature', 'fields'});
      final fields = envelope['fields']! as Map<String, Object?>;
      expect(fields['target'], peerAddress);
      expect('${fields['body']}', contains('到家了'));
      expect(
        find.text(l10n.fnthinkSendSent('m_send_1')),
        findsOneWidget,
        reason: '"已交给服务端排队"与"已送达"是两句话 —— 后者只有那台的回执说得',
      );
    });

    testWidgets('正文空着 ⇒ 「发送」是灰的，一个字节都不发', (tester) async {
      stubChannels();
      final h = harness(
        peers: [
          const FnthinkPeer(
            peerAddress: peerAddress,
            publicKey: 'AAAApublicKeyBytesForTests',
            level: 'L1',
            grantedAt: 1800000000000,
            requestId: 'pr_9',
          ),
        ],
      );
      await pump(tester, h.page);
      await tapSend(tester);
      await fill(tester, title: '只有标题没有正文');
      final submit = find.byKey(const ValueKey('fnthink-send-submit'));
      expect(
        tester.widget<TextButton>(submit).onPressed,
        isNull,
        reason: '空正文发出去那边只会收到一句空话，而回执照样算"送达"',
      );
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(h.sendAsked(), isEmpty);
    });

    testWidgets('弹层上点取消 ⇒ 那一发不发', (tester) async {
      stubChannels();
      final h = harness(
        peers: [
          const FnthinkPeer(
            peerAddress: peerAddress,
            publicKey: 'AAAApublicKeyBytesForTests',
            level: 'L1',
            grantedAt: 1800000000000,
            requestId: 'pr_9',
          ),
        ],
      );
      final l10n = await pump(tester, h.page);
      await tapSend(tester);
      await fill(tester, body: '本来要发的正文');
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(h.sendAsked(), isEmpty, reason: '取消就是取消：这一发不该有个"顺便试一下"');
      expect(find.byKey(const ValueKey('fnthink-send-note')), findsNothing);
    });

    testWidgets('403 说成"对方没给这一档权限或还没配对"，不折叠成一句"发送失败"', (tester) async {
      stubChannels();
      final h = harness(
        sendStatus: 403,
        sendBody: '{"receipt":"rejected_capability"}',
        peers: [
          const FnthinkPeer(
            peerAddress: peerAddress,
            publicKey: 'AAAApublicKeyBytesForTests',
            level: 'L1',
            grantedAt: 1800000000000,
            requestId: 'pr_9',
          ),
        ],
      );
      final l10n = await pump(tester, h.page);
      await tapSend(tester);
      await fill(tester, body: '发一条试试');
      await tester.tap(find.byKey(const ValueKey('fnthink-send-submit')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.fnthinkSendRejectedCapability), findsOneWidget);
      expect(find.byKey(const ValueKey('fnthink-send-note')), findsOneWidget);
    });

    testWidgets('被挤掉过几条 ⇒ 那句话当场出现在发送端（不静默丢）', (tester) async {
      stubChannels();
      final h = harness(
        sendBody:
            '{"receipt":"queued","messageId":"m_send_2","action":"new",'
            '"evicted":["m_old_1","m_old_2"]}',
        peers: [
          const FnthinkPeer(
            peerAddress: peerAddress,
            publicKey: 'AAAApublicKeyBytesForTests',
            level: 'L1',
            grantedAt: 1800000000000,
            requestId: 'pr_9',
          ),
        ],
      );
      final l10n = await pump(tester, h.page);
      await tapSend(tester);
      await fill(tester, body: '排队里挤掉了两条');
      await tester.tap(find.byKey(const ValueKey('fnthink-send-submit')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(l10n.fnthinkSendEvicted(2)),
        findsOneWidget,
        reason:
            '服务端那边每条已写了 dropped 回执，但要等下一次 poll 才看得见；'
            '点发送的人当场就该知道自己上一条被挤掉了',
      );
    });

    testWidgets('本机签不出来 ⇒ 说的是"还没就绪"，而一个字节都不离机', (tester) async {
      stubChannels();
      final h = harness(
        canSign: false,
        peers: [
          const FnthinkPeer(
            peerAddress: peerAddress,
            publicKey: 'AAAApublicKeyBytesForTests',
            level: 'L1',
            grantedAt: 1800000000000,
            requestId: 'pr_9',
          ),
        ],
      );
      final l10n = await pump(tester, h.page);
      await tapSend(tester);
      await fill(tester, body: '签不出来也要试');
      await tester.tap(find.byKey(const ValueKey('fnthink-send-submit')));
      await tester.pumpAndSettle();
      expect(h.sendAsked(), isEmpty);
      expect(
        find.byKey(const ValueKey('fnthink-send-note')),
        findsOneWidget,
        reason: '把"身份问题"说成"网络失败"，用户就会去检查一直好好的网络',
      );
      expect(find.text(l10n.fnthinkSendTransportError), findsNothing);
    });
  });

  group('接收卡那一行「下一次自己醒」（§4-9 片1d）', () {
    Future<void> tapSwitch(WidgetTester tester) async {
      final sw = find.byKey(const ValueKey('fnthink-receive-switch'));
      await revealTo(tester, sw);
      await tester.tap(sw);
      await tester.pumpAndSettle();
    }

    testWidgets('原生从没排过 ⇒ 说"没在醒着"，而不是一个 0 点的时间', (tester) async {
      // 默认桩回 null ⇒ Dart 那侧映射成 {0,0}。这一条钉的是"读到了、确实没排"那一支：
      // 它必须与"读不出来"分得开（后者的用例在下一条）。
      stubChannels();
      final h = harness();
      final l10n = await pump(tester, h.page);
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey('fnthink-presence-next'));
      await revealTo(tester, row);
      expect(row, findsOneWidget);
      expect(find.text(l10n.fnthinkPresenceAsleep), findsOneWidget);
      expect(find.textContaining('00:00:00'), findsNothing);
    });

    testWidgets('排上了 ⇒ 显示的是原生读回来的那个时间点与那一档秒数', (tester) async {
      // 27 这个数只出现在桩里（原生交下来的那一档）。页面若自己去读契约的默认值（20），
      // 这条就会红 —— 与 scheduler 那条"间隔只有一个作者"是同一条纪律在界面上的延伸。
      final fireAt = DateTime(2026, 9, 30, 21, 34, 56).millisecondsSinceEpoch;
      stubChannels(
        presenceStatus: () => {'nextRoundAt': fireAt, 'cadenceSeconds': 27},
      );
      final h = harness();
      final l10n = await pump(tester, h.page);
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey('fnthink-presence-next'));
      await revealTo(tester, row);
      expect(
        find.text(l10n.fnthinkPresenceNext('21:34:56', 27)),
        findsOneWidget,
      );
      expect(find.text(l10n.fnthinkPresenceAsleep), findsNothing);
    });

    testWidgets('开关开关各一下，那一行每次都跟着变（不是读一次就停在那儿）', (tester) async {
      // ⚠ 这条用例第一版是**假绿**：只翻一次开关时，"翻开那一支"自己的重读就足以让断言通过，
      //    于是"关掉那一支忘了重读"这个缺陷测不出来（反证 P1 抓出来的）。
      //    现在两下都走：翻开之后桩报"排上了"、关掉之后桩报"没排"，两次断言各钉一支。
      var armed = false;
      final fireAt = DateTime(2026, 9, 30, 21, 34, 56).millisecondsSinceEpoch;
      stubChannels(
        presenceStatus: () => armed
            ? {'nextRoundAt': fireAt, 'cadenceSeconds': 20}
            : null, // 没排（或已撤）：nextRoundAt = 0、cadence 也清掉
      );
      final h = harness();
      final l10n = await pump(tester, h.page);
      await tester.pumpAndSettle();
      expect(find.text(l10n.fnthinkPresenceAsleep), findsOneWidget);

      armed = true;
      await tapSwitch(tester);
      expect(
        find.text(l10n.fnthinkPresenceNext('21:34:56', 20)),
        findsOneWidget,
      );

      armed = false;
      await tapSwitch(tester);
      expect(find.text(l10n.fnthinkPresenceAsleep), findsOneWidget);
    });

    testWidgets('读口抛 ⇒ 这一行根本不画（不拿"没在醒着"冒充"读不出来"）', (tester) async {
      stubChannels(presenceStatus: () => throw StateError('通道那头没人接'));
      final h = harness();
      final l10n = await pump(tester, h.page);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('fnthink-presence-next')),
        findsNothing,
        reason: '读不出来时画一句"没在醒着"是假话：用户会去翻开关，而真相是这一版问不到原生',
      );
      expect(find.text(l10n.fnthinkPresenceAsleep), findsNothing);
    });
  });
}

/// 把折叠线以下的格子滚进视口（`ListView` 只 build 视口与 cacheExtent 内的行，
/// 不滚就先 `findsNothing` —— 报出来像"那一格没画"，实际只是还没滚到）。
Future<void> revealTo(WidgetTester tester, Finder target) async {
  if (target.evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

/// 走完"点那一下 → （同意时）弹层确认"（列表里的按钮在折叠线以下，先滚进视口）。
/// 拒绝没有二次确认：它是安全的那一个方向，而每一次多点一下都是用户在替自己判断值不值。
Future<void> _tapPair(
  WidgetTester tester,
  AppLocalizations l10n, {
  required bool approve,
}) async {
  final button = find.byKey(
    ValueKey(approve ? 'fnthink-pair-approve-pr_9' : 'fnthink-pair-deny-pr_9'),
  );
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
  if (!approve) return;
  await tester.tap(find.text(l10n.confirm));
  await tester.pumpAndSettle();
}

/// 签出去那一发的**载荷**（`fields.body` 是 json 字符串，套两层）。
/// 断言要落在载荷上：只看整串 body 的话，`contains('L2')` 会被签名、地址码里碰巧的
/// 那两个字符满足，用例就变成一条永远绿的东西。
Map<String, Object?> sentPayload(http.Request request) =>
    jsonDecode((jsonDecode(request.body)['fields']! as Map)['body']! as String)
        as Map<String, Object?>;

class _StubSigner implements FnthinkIdentitySigner {
  _StubSigner(this.canSign);

  final bool canSign;

  @override
  Future<String> call(List<int> canonicalBytes) async => 'AAAAc2ln';

  @override
  Future<bool> probe() async => canSign;
}

class _Harness {
  _Harness({
    required this.page,
    required this.coordinator,
    required this.builds,
    required this.armAsked,
    required this.confirmAsked,
    required this.peerRows,
    required this.peersShown,
    required this.peerReads,
    required this.revokeAsked,
    required this.endpointAsked,
    required this.endpointListAsked,
    required this.endpointRevokeAsked,
    required this.endpointRotateAsked,
    required this.sendAsked,
    required this.removed,
  });

  final FnthinkPushPage page;
  final FnthinkReceiveCoordinator coordinator;
  final int Function() builds;

  /// 挂口令那一发真实发出去的请求（假服务器记下来的）。
  final List<http.Request> Function() armAsked;

  /// 答复配对请求那一发。
  final List<http.Request> Function() confirmAsked;

  /// 写进本机名单的那几行（替身记下来的，所以能问出"记的是哪一档"）。
  final List<FnthinkPeer> Function() peerRows;

  /// 名单读咽喉那一份"表里现在有什么"（替身里的数据）。
  final List<FnthinkPeer> Function() peersShown;

  /// 名单被读了几次（页面只在进页面与答复之后各读一次，别处不许自己数）。
  final int Function() peerReads;

  /// 撤销那一发真实发出去的请求（假服务器记下来的）。
  final List<http.Request> Function() revokeAsked;

  /// 建端点那一发（同一套假服务器，按契约声明的路径分流）。
  final List<http.Request> Function() endpointAsked;

  /// 读端点列表那一发（同一套假服务器）。数得到被发了几次，是为了能断言
  /// 「翻开页面不该自己发这一发」—— 那一刻服务地址与身份还没就位，发出去只会把
  /// "还没法读"画成屏幕上的第一句话。
  final List<http.Request> Function() endpointListAsked;

  /// 关掉一把入口那一发（同一套假服务器）。数得到它被发了几次，是为了能断言
  /// "点了列表里那一下之前，一发都不该出去"（二次确认那一刀必须先过）。
  final List<http.Request> Function() endpointRevokeAsked;

  /// 换口令那一发（同一套假服务器）。数得到它被发了几次，是为了断"确认之前不发"与
  /// "换完只发这一发"—— 那一发会立刻让旧口令开始倒计时，多点一下就是再倒一次。
  final List<http.Request> Function() endpointRotateAsked;

  /// 「发一条」那一发真实发出去的请求（§4-10 片2b）。
  final List<http.Request> Function() sendAsked;

  /// 本机删行被调用时点到的地址码（替身记下来的）。
  final List<String> Function() removed;
}
