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
  void stubChannels({bool identityOk = true}) {
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
    int armStatus = 200,
    String armBody =
        '{"armed":true,"expiresAt":1800000300000,"ttlSeconds":300,'
        '"serverTime":1800000000000}',
    int confirmStatus = 200,
    String confirmBody =
        '{"requestId":"pr_9","status":"approved","grantedLevel":"L1",'
        '"serverTime":1800000000000}',
    Future<FnthinkPeerWrite> Function(FnthinkPeer peer)? recordPeer,
    List<FnthinkPeer> peers = const [],
    bool peersFail = false,
  }) {
    final loader = FnthinkContractLoader(
      readAsset: (_) async {
        if (!contractOk) return '{ 这不是合法 JSON';
        return File('protocol/fnthink-v1.json').readAsStringSync();
      },
    );
    final armAsked = <http.Request>[];
    final confirmAsked = <http.Request>[];
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
        ),
      ),
      coordinator: coordinator,
      builds: () => builds,
      armAsked: () => armAsked,
      confirmAsked: () => confirmAsked,
      peerRows: () => peerRows,
      peersShown: () => peersShown,
      peerReads: () => peerReads,
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
            '"这里删掉一行不会让推送停下来"必须与名单同屏，而且必须是**这一句**：'
            '少了它，这一格就会被读成撤销的入口',
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
}
