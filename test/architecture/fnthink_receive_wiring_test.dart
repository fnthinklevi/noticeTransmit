import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/di/service_locator.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/services/fnthink_inbox_display.dart';
import 'package:notice_transmit/services/fnthink_receive_coordinator.dart';
import 'package:notice_transmit/services/fnthink_receiver_service.dart';
import 'package:notice_transmit/services/fnthink_remote_command_handler.dart';
import 'package:notice_transmit/services/fnthink_remote_executors.dart';
import 'package:notice_transmit/services/fnthink_remote_runner.dart';
import 'package:notice_transmit/services/fnthink_remote_wiring.dart';

import '../support/source_guards.dart';

/// 收货链路**装配点**的守卫：落库与显示这两个副作用是不是真的都接上了，
/// 以及收件的读写是不是只剩一个咽喉。
///
/// 为什么单独钉这一处：`persist` / `display` 都是可选传参形状的同族
/// （`display` 甚至允许 null —— 那是"T48 之前那台没有显示链路的设备"的合法形状）。
/// 装配点漏掉 `display:` 时，**全部测试仍然绿**：循环会把每条 ack 报成 `delivered`、
/// 消息照样进表、服务端照样留着正文重发。表现是"通知一条都不弹但收件箱里有货"，
/// 而这个现象在 CI 里没有任何一处会喊。这一文件就是那声喊。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final contract = FnthinkContract.readFile();
  final root = projectRoot();

  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  int occurrences(String haystack, String needle) =>
      RegExp(RegExp.escape(needle)).allMatches(haystack).length;

  tearDown(() => getIt.reset());

  group('装配点', () {
    test('⚠ 远程执行那一格接上了（onCommand 从 8.183 起挂着，DI 里曾一直没有值）', () {
      setupLocator();
      final c = getIt<FnthinkReceiveCoordinator>();
      expect(
        c.onCommand,
        isNotNull,
        reason:
            '漏接时**不是崩**：远程指令消息照常按通知弹出来，而没有任何东西动手 —— '
            '用户看到的现象是"对方说发了指令，我这边响了一声"。'
            '而全场 Dart 测试仍然绿（循环的用例把 hook 当参数传进来，不经过 DI）',
      );
      // 五个对象都要在：少任何一个的表现都是"那条指令不执行"，
      // 而那与"这一格没接"在别的用例里长得一模一样（都绿）。
      expect(getIt.isRegistered<RemoteCommandWiring>(), isTrue);
      expect(getIt.isRegistered<RemoteCommandRunner>(), isTrue);
      expect(getIt.isRegistered<RemoteCommandRecognizer>(), isTrue);
      expect(getIt.isRegistered<DeviceL2Executor>(), isTrue);
      expect(getIt.isRegistered<DeviceL3Executor>(), isTrue);
    });

    test(
      'DI 起来的 coordinator 四条副作用都在（recordPeer/removePeer 被漏掉时全场仍绿，所以只能靠这条）',
      () {
        setupLocator();
        final c = getIt<FnthinkReceiveCoordinator>();
        expect(c.persist, isNotNull);
        expect(
          c.display,
          isNotNull,
          reason: '收货链路只落库不显示 ⇒ 用户看不见，而服务端按 delivered 之外的那档留着正文',
        );
        expect(
          c.recordAck,
          isNotNull,
          reason:
              'DI 漏接这一行时全场测试仍然绿，而 `ack_result`/`acked_at` 永远空着 —— '
              '收件详情那一带"回执状态"的界面就会开始显示猜出来的东西',
        );
        expect(
          c.recordPeer,
          isNotNull,
          reason:
              '`fnthink_peers` 在生产代码里**只有这一个写入者**。漏接时同意照样成功、'
              '服务端照样投得进来，而本机名单一直是空的',
        );
        expect(
          c.removePeer,
          isNotNull,
          reason:
              '撤销那一发在服务端生效之后要靠它删本机那一行。漏接时的表现不是报错，'
              '是"点了撤销而那一行一直在"——用户会以为撤销没成而再点一次，'
              '而第二次换来的是一句幂等的成功（对面其实早就推不进来了）',
        );
      },
    );

    test('收货循环的启动点不许只有页面（T33 第一片）', () {
      // 这一条存在的理由是一段已经上线的行为：`startIfEnabled()` 全仓只有 `fnthink_settings_page`
      // 那两处调用 —— 于是"总开关开着"只在用户**停留在那一页时**成立，退回首页、切 tab、
      // 把 App 划进后台（进程还活着）都不再取货。用户翻开关时读到的承诺是"这台设备会去收"。
      // 这类漏接在任何功能测试里都不会红（页面测试总是自己点开关），只能靠装配点钉。
      //
      // 反证（2026-09-30，WB1–WB5 全 exit≠0 + named + restored，基线先验过绿；
      // `outputs/_wake.report.txt`）：WB1 启动点摘掉 / WB2 装配处出现"自己拼循环"的形状 /
      // WB3 改了地址不重启 / WB4 校验没过也白重启 / WB5 恢复默认不重启。
      // ⚠ 顺带测出来的一件**不该写成断言**的事：同一回调里把启动调用复制两遍 **不红**，
      //    因为 `startIfEnabled()` 对已在跑的循环返回 already-running（幂等）——
      //    所以这里判的是"有没有启动点"，不是"是不是恰好一处"。
      final main = read('lib/main.dart');
      expect(
        occurrences(main, '.startIfEnabled()'),
        greaterThanOrEqualTo(1),
        reason:
            'App 启动链里必须有一处按开关起循环；0 处就是回到"只由页面拉起"。'
            '（多处不判红：`startIfEnabled` 对已在跑的循环返回 already-running，'
            '起两遍不出两遍货 —— 这是植入实测出来的，别把它写成会红的事）',
      );
      final from = main.indexOf('void _onServicesInitialized()');
      expect(from, isNonNegative, reason: '启动点挂在 splash 装配完成那个回调上');
      final body = main.substring(from);
      expect(
        body.substring(0, body.indexOf('\n  }')),
        contains('_startFnthinkReceive()'),
        reason: '必须在这一格里，而不是 initState / main() 顶层 —— 那里隐私还没同意',
      );
    });

    test('装配处不许自己拼循环：循环的规格只有一个作者（T33 第一片）', () {
      // 启动点"有"不等于"接对"：在装配处就地拼一个 loop，编译过、页面测试全绿，
      // 而那一份不认总开关、不带启动那一刻定型的地址码与服务地址。
      final main = read('lib/main.dart');
      for (final bypass in [
        'buildFnthinkReceiveLoop',
        'FnthinkReceiveLoop(',
        'FnthinkReceiverService(',
      ]) {
        expect(
          main,
          isNot(contains(bypass)),
          reason:
              '装配处不许出现 $bypass：循环的规格只有一个作者 = 协调者，'
              '就地拼出来的那一份没人替它裁决开关与凭证。',
        );
      }
    });

    test('spec 里的 display 会传到循环上（不是只存在 spec 里）', () async {
      final loop = buildFnthinkReceiveLoop(
        FnthinkLoopSpec(
          contract: contract,
          baseUri: Uri.https('push.example', ''),
          addressCode: 'AAAABBBBCCCCDDDDEEEE',
          signer: _StubSigner(),
          persist: (_) async => true,
          display: (_) async => true,
        ),
      );
      expect(loop.display, isNotNull);

      final bare = buildFnthinkReceiveLoop(
        FnthinkLoopSpec(
          contract: contract,
          baseUri: Uri.https('push.example', ''),
          addressCode: 'AAAABBBBCCCCDDDDEEEE',
          signer: _StubSigner(),
          persist: (_) async => true,
        ),
      );
      expect(
        bare.display,
        isNull,
        reason: 'null 是一条真实的形状（那台设备还没显示链路），不许被装配点悄悄填上',
      );
    });

    test('装配用的那枚 display 就是收件显示服务的 show（不是随手接的常量函数）', () async {
      final display = FnthinkInboxDisplay().show;
      expect(
        await display(
          const FnthinkInboxMessage(
            messageId: '',
            sender: '',
            type: 'notice',
            item: '',
            title: '',
            body: '',
            receivedAt: 0,
          ),
        ),
        isFalse,
        reason: '空 id 不该发通道：这一条同时证明接的是那个实现，而不是一枚恒真的替身',
      );
    });
  });

  group('收件读写只有一个咽喉', () {
    // 「同一件事抄几份」是本仓反复出现的故障形状：未读数、排序口径、"标已读命中没有"这三件事
    // 一旦被页面各写一份，表现是首页入口卡说还有 3 条而列表只列 2 条 —— 两处各自都"对"，
    // 谁也不报错。所以这里断的不是行号，是**这一层不许长出 SQL、页面不许绕过它**。
    //
    // 这一组被砸过什么（报告在本地 outputs/_inbox_card_falsify.report.txt，按约定不入库；
    // 六条全部 named + restored，每条只红一条用例）：
    //  C1 未读 0 也画这一格 / C2 出口没接上也画 ⇒ 各自红在首页那张卡的用例；
    //  C3 首页自己长出一枚 `unreadCount` 字段 ⇒ 红在下面那条「数是取来的」；
    //  C4 预置收件档却不预读表 ⇒ 红在历史页那条「一进来就读表」；
    //  C5 从收件档返回后不再重取 / C6 回到前台不再重取 ⇒ 红在下面那条「两个时刻」。
    // ⚠ C5 第一轮报的是**基线红**，不是植入红：`blockAfter(lib, 'void _openHistoryPage(')` 会停在
    //    命名参数表那个 `{` 上，取到的是参数表而不是函数体。锚点改成按文件取。留在这里是因为
    //    "守卫自己写错"比"守卫没效果"更难发现 —— 只有反证会告诉你它一直红着。
    test('服务层只转发，没把查询自己抄一份', () {
      final src = read('lib/services/fnthink_inbox_service.dart');
      for (final sql in ['db.query', 'db.update', 'orderBy', "'read = 0'"]) {
        expect(
          src,
          isNot(contains(sql)),
          reason: '服务层里出现了 $sql —— 排序/未读口径就此分成两份，表那一层改了它不会跟着改',
        );
      }
    });

    test('历史页的收件档走服务层，不再直连表', () {
      // 负向断言 ⇒ 读整个 library（页面将来拆 part 时只读单文件会瞎），并且剥注释
      final src = stripComments(
        librarySource(root, 'lib/pages/history_page.dart'),
      );
      for (final direct in ['loadFnthinkInbox', 'markFnthinkInboxRead']) {
        expect(
          src,
          isNot(contains(direct)),
          reason: '页面又自己调 $direct 了 —— 下一个入口（首页未读卡）就会照抄这一份',
        );
      }
      expect(
        src,
        contains('FnthinkInboxService'),
        reason: '收件档的数据来源不是服务层：本条守卫已经在空跑',
      );
    });

    test('首页那一格的数是取来的，不是页面自己数的', () {
      // 负向：首页拿到一个 int 就画。它若自己数（`list(unreadOnly: true).length` 那种），
      // 列表带着 limit ⇒ 收到第 51 条起这一格开始少报，而少报的样子和"真的没有未读"一模一样。
      final home = stripComments(
        librarySource(root, 'lib/pages/notification_page.dart'),
      );
      for (final counting in [
        'unreadCount',
        'countFnthinkInboxUnread',
        'loadFnthinkInbox',
      ]) {
        expect(
          home,
          isNot(contains(counting)),
          reason: '首页自己长出一份数法（$counting）⇒ 它和历史页收件档迟早报两个数',
        );
      }
      expect(
        home,
        contains('fnthinkInboxUnread'),
        reason: '首页不再收这个注入值了：本条守卫已经在空跑',
      );

      final main = stripComments(
        librarySource(root, 'lib/pages/main_page.dart'),
      );
      expect(
        main,
        allOf(contains('FnthinkInboxService'), contains('unreadCount(')),
        reason: '首页的未读数不是从收件咽喉取的（漏接时全场仍绿，只有这一格静默消失）',
      );
    });

    test('从收件档返回时会重取未读数（不然首页一直举着一个已经不存在的数）', () {
      // 这一条只盯**两个时刻**：从历史页弹回来、以及回到前台。取数的来源与画数的位置都在别处钉过了。
      // 少弹回来那一步的现象很具体：首页写「未读 3 条」，点进去把三条都读过，退回首页还写 3 条。
      //
      // ⚠ 锚点按**文件**取，不按函数体取：`blockAfter(lib, 'void _openHistoryPage(')` 会停在
      //    命名参数表那个 `{`（`({String direction = 'forwarded'})`）上，返回的是参数表而不是函数体 ——
      //    本条第一版就这么写错过，靠反证第一轮报出"基线本来就红"才发现（植入没动它它也红）。
      final actions = stripComments(
        File('$root/lib/pages/main_page_actions.dart').readAsStringSync(),
      );
      expect(
        actions,
        contains('_refreshFnthinkInboxUnread'),
        reason:
            '导航那一族里不再重取未读数 ⇒ 那一格的数从此不再跟着表走。'
            '如果 `_openHistoryPage` 搬去了别的文件，把这条一起搬过去，别删。',
      );
      // 收货循环在后台跑，它落库的那几条不会往 UI 推事件 ⇒ 回到前台是唯一的补偿时刻。
      final lib = stripComments(
        librarySource(root, 'lib/pages/main_page.dart'),
      );
      expect(
        lib,
        contains('unawaited(_refreshFnthinkInboxUnread())'),
        reason: 'resumed 时不再重取 ⇒ 后台新到的消息要等用户翻一次历史页才反映到首页',
      );
    });

    test('收货服务的构造只有一个出处（循环与挂口令共用同一道装配判定）', () {
      // 循环那一发与挂口令那一发都要一个 `FnthinkReceiverService`。两处各 new 一份时，
      // 装配期那三道判定（apiPaths / httpsOnly / 签名）就有了两套口径 ——
      // 表现是"循环起不来而挂口令却能发出去"，看起来像两个不相关的 bug。
      final src = read('lib/services/fnthink_receive_coordinator.dart');
      expect(
        RegExp(r'FnthinkReceiverService\(').allMatches(src).length,
        1,
        reason: 'coordinator 里又多了一处直接构造服务：请经 buildFnthinkReceiveService 拿',
      );
      expect(src, contains('buildFnthinkReceiveService(spec)'));
    });
  });

  group('配对答复与待确认列表只有一个作者（T42 第五片）', () {
    // 这一组钉的全是"漏接时全场仍绿"那一类：判据住在服务层，接它的人漏了一行，
    // 现象要等下一片（那一格界面）才看得见，而那时已经查不出是从哪一片开始断的。
    test('spec 里的 onRound 会传到循环上（后台那几轮的账不是只存在 spec 里）', () {
      final loop = buildFnthinkReceiveLoop(
        FnthinkLoopSpec(
          contract: contract,
          baseUri: Uri.https('push.example', ''),
          addressCode: 'AAAABBBBCCCCDDDDEEEE',
          signer: _StubSigner(),
          persist: (_) async => true,
          onRound: (_) {},
        ),
      );
      expect(
        loop.onRound,
        isNotNull,
        reason:
            '"有人请求配对你"的进水口就在 onRound 上。这里不接，页面就只能自己 poll 一次'
            '（第二个读法）或者只在按钮点下去时才更新 —— 而用户是盯着屏幕等对面来配的',
      );
    });

    test('待确认列表只有一个更新处，而它同时接住了后台轮次与手动那一轮', () {
      final src = read('lib/services/fnthink_receive_coordinator.dart');
      // 两个时刻都得接住：后台循环走 `onRound`，页面上"立即收取"那一下走 `runOnce`
      // （不经过 `_tick`，所以 onRound 不会响）。只接一个时的现象各不相同，
      // 但都是"某一轮带回来的请求看不见"。
      expect(
        src,
        contains('onRound: _noteRound'),
        reason:
            '后台那几轮的账不再进协调者 ⇒ 待确认栏只在点按钮时才动，'
            '而开关开着时它本来就是自动在收的',
      );
      expect(
        src,
        contains('_noteRound(report)'),
        reason: '手动那一轮不再记账 ⇒ 用户按了"立即收取"，那一栏还是旧的',
      );
      // 替身循环也得接：测试里那张假循环不接 `spec.onRound` 时，"这一格自己出现"那条
      // 会红在装配上而不是红在产品代码上 —— 但那正是它该有的行为，所以这里也钉一次。
      final pageTest = read('test/widgets/fnthink_settings_page_test.dart');
      expect(
        pageTest,
        contains('onRound: spec.onRound'),
        reason: '页面测试里的假循环不再把账交给协调者 ⇒ 那条用例从此只能靠运气绿',
      );
    });

    test('配对名单在生产代码里只有一个作者，而那一处就是 DI', () {
      var calls = 0;
      for (final entity in Directory('$root/lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        calls +=
            stripComments(
              entity.readAsStringSync(),
            ).split('.upsertFnthinkPeer').length -
            1;
      }
      expect(
        calls,
        1,
        reason:
            '`fnthink_peers` 多了一个调用点 ⇒ "我同意过谁"开始有两本账，'
            '而同码不同钥不许覆盖那条判据只会有一处写着',
      );
      expect(
        read('lib/di/service_locator.dart'),
        contains('.upsertFnthinkPeer'),
        reason: '名单的作者搬走了？那要么接进 DI，要么把这条一起搬走，别删',
      );
    });

    test('页面不自己取货、不自己开表，也不把答复词与档位抄成字面量', () {
      final page = stripComments(
        librarySource(root, 'lib/pages/fnthink_peers_page.dart'),
      );
      expect(
        page,
        contains('pairRequestsListenable'),
        reason: '页面不再从协调者那份账读了：本条守卫已经在空跑',
      );
      // T110 第二面 → T116：「我发起过的请求」与「配对历史」两张卡走的是**那一份账**的 listenable。
      // ⚠ 这一条从 `sentPairRequestsListenable` 换成了 `pairLedgerListenable` —— 换的是它依赖的前提
      //（发起面从"只活在内存这一次进程"变成"落盘的账"），不是把闸悄悄放宽：
      // 仍然要求页面从协调者取一份会自己变的账，不自己 poll、不自己开表。
      expect(
        page,
        contains('pairLedgerListenable'),
        reason:
            '发起面/历史没接上那份账 ⇒ 对面那台同意或拒绝之后，这一台屏幕上不动，'
            '而这条任务要修的正是那个「看不到进度」',
      );
      expect(
        read('lib/di/service_locator.dart'),
        allOf(contains('storePairRequest:'), contains('loadPairRequests:')),
        reason:
            '那一份账的两个口在 DI 里漏接时的表现不是崩溃：三张卡一律空着且不报错，'
            '而全场测试仍然绿（协调者用例都把 hook 当参数传进来）',
      );
      // 入口行那两句计数（T110 ④）：数只在协调者那一处算，页面只取；而且它挂了监听 ——
      // 不挂的话新请求静默等着，用户要自己点进去才知道有人在等。
      final hub = stripComments(
        librarySource(root, 'lib/pages/notification_engine_page.dart'),
      );
      expect(hub, contains('pendingPairRequestCount'));
      expect(hub, contains('outgoingPairRequestsWaiting'));
      expect(hub, contains('pairRequestsListenable.addListener'));
      // ⚠ 这一条跟着上面那张卡换：入口行数的与卡片读的是同一份，挂错 listenable 时
      // "发起完那一行还说常态、点进去已经有一行"。
      expect(hub, contains('pairLedgerListenable.addListener'));
      expect(
        hub,
        isNot(contains('pendingPairRequests.length')),
        reason:
            '入口行自己数一遍 = 第二个作者：'
            '这一行说 2 而进去那张卡画 3 行，正是这类分叉的现形方式',
      );
      expect(
        page,
        contains('grantableLevel'),
        reason: '"这一发实际给到哪一档"的算法在契约层，页面只是把它念出来',
      );
      for (final direct in [
        'pollOnce',
        'DatabaseHelper',
        'FnthinkReceiverService(',
      ]) {
        expect(
          page,
          isNot(contains(direct)),
          reason: '页面里出现了 $direct：取货口径或名单的写法开始有第二份',
        );
      }
      for (final word in ["'approved'", "'denied'", "'L1'", "'L2'", "'L3'"]) {
        expect(
          page,
          isNot(contains(word)),
          reason: '$word 被抄进界面：契约换词或换封顶之后，这一台会签出一个服务端不认识的答复',
        );
      }
    });

    test('配对名单的读与删各只有一个咽喉，而页面不许自己碰表', () {
      // 名单的读法（`granted_at DESC, peer_address ASC`）只在 `DatabaseHelper` 那一处；
      // 页面绕过读咽喉就会自己排一次序 —— 同一份数据在两个入口排出两个顺序，是本仓反复出现过的形状。
      var reads = 0;
      var deletes = 0;
      for (final entity in Directory('$root/lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final code = stripComments(entity.readAsStringSync());
        reads += code.split('.loadFnthinkPeers').length - 1;
        deletes += code.split('.removeFnthinkPeer').length - 1;
      }
      expect(
        reads,
        1,
        reason: '`fnthink_peers` 多了一个读者 ⇒ 排序/时间口径开始分叉（那一处应当是读咽喉）',
      );
      expect(
        deletes,
        1,
        reason:
            '删行也只有咽喉那一处。今天它唯一的调用方是协调者（撤销成功之后），'
            '再多一处就直接绕过了"先撤服务端再删本机行"那条顺序',
      );

      final service = read('lib/services/fnthink_peer_service.dart');
      for (final sql in ['db.query', 'orderBy', 'FnthinkPeer.table']) {
        expect(
          service,
          isNot(contains(sql)),
          reason: '咽喉里出现了 $sql：查询口径长出第二份，表那一层改了它不会跟着改',
        );
      }
      expect(
        service,
        contains('.removeFnthinkPeer'),
        reason: '删行的咽喉被搬走了？那要么接进服务层，要么把这条一起搬走，别删',
      );
      expect(
        read('lib/di/service_locator.dart'),
        contains('removePeer: FnthinkPeerService().remove'),
        reason:
            'DI 若改成直接摸 `DatabaseHelper().removeFnthinkPeer`，这一层就又变回"只有读"，'
            '而撤销那条路上没人管删行的口径（漏接时全场仍绿，只有名单开始留着已经撤掉的行）',
      );
      expect(
        read('lib/services/fnthink_receive_coordinator.dart'),
        contains('removePeer'),
        reason: '协调者不再经咽喉删行 ⇒ 上面那条"删只有一处"就只是在数空跑',
      );

      final page = stripComments(
        librarySource(root, 'lib/pages/fnthink_peers_page.dart'),
      );
      expect(
        page,
        contains('FnthinkPeerService'),
        reason: '页面的名单不再经服务层取：本条守卫已经在空跑',
      );
      expect(
        page,
        contains('_coordinator.revokePeer'),
        reason: '撤销那一下改为自己发请求或自己删行 ⇒ 顺序与失败态两份口径',
      );
      for (final direct in [
        'loadFnthinkPeers',
        'removeFnthinkPeer',
        'upsertFnthinkPeer',
      ]) {
        expect(
          page,
          isNot(contains(direct)),
          reason: '页面里出现了 $direct：名单的读写从此有两本账',
        );
      }
    });
  });

  group('接入端点那一发（T42 第七片）', () {
    test('服务层构造期的 apiPaths 判定里含 endpointCreate（缺路径要在装配期就炸）', () {
      final src = stripComments(
        read('lib/services/fnthink_receiver_service.dart'),
      );
      expect(
        src,
        contains("'endpointCreate',"),
        reason:
            '这一发要从契约反查 URL。缺了那一项判定的表现：装配期不报错，第一次点"建一个端点"'
            '才在 transport 里抛 —— 那是把契约与实现不匹配伪装成网络抖动',
      );
      expect(src, contains('kernel.endpointCreate('));
    });

    test('口令没有去处：设置存储里没这个概念，页面也不直接碰 prefs', () {
      // 这把口令的设计前提是"只出现一次"。本机一旦留副本，它就变成一份跟着备份走的明文长期凭证，
      // 而服务端那边只存了摘要 —— 谁都不知道丢了什么，包括留副本的那个人。
      final settings = stripComments(
        read('lib/services/fnthink_settings.dart'),
      );
      expect(
        settings.toLowerCase(),
        isNot(contains('secret')),
        reason: '设置项里出现了 secret：那等于给"顺手存一下"开一个正式的键',
      );
      // ⚠ T94：幻念推送页拆成两张（设备绑定那张单独成页）之后，
      //   这条断言必须两张都断：只断其中一张，另一张里的口令可以无宱地落盘。
      // ⚠ T97 片B：端点那一格又独立成页，尺要跟着宽一格 —— 这三张页才是"口令可能落盘"的全部现场。
      final page = stripComments(
        librarySource(root, 'lib/pages/fnthink_settings_page.dart') +
            librarySource(root, 'lib/pages/fnthink_peers_page.dart') +
            librarySource(root, 'lib/pages/fnthink_endpoint_page.dart'),
      );
      for (final write in ['setString', 'SharedPreferences']) {
        expect(
          page,
          isNot(contains(write)),
          reason: '页面里出现了 $write：口令那一行从此有了第二份去处，而没人负责清掉它',
        );
      }
    });
  });

  group('端点那份列表的读口（#157 第二片）', () {
    test('服务层装配判定里含 endpointList，内核那一发只有一个调用点', () {
      final src = read('lib/services/fnthink_receiver_service.dart');
      expect(
        src,
        contains("'endpointList',"),
        reason:
            '这一发也要从契约反查 URL。判定名单漏它 ⇒ 装配期不报错，第一次点"读一次我建过的入口"'
            '才在 transport 里抛，看起来像网络抖动',
      );
      expect(src, contains('kernel.endpointList('));
    });

    test('读口只有一个作者：页面走协调者，不许自己直连服务层', () {
      final coordinator = read('lib/services/fnthink_receive_coordinator.dart');
      expect(
        occurrences(coordinator, 'service.endpointList()'),
        1,
        reason: '两处就两本账：一处负责 dispose、一处不负责',
      );
      expect(
        occurrences(
          coordinator,
          'Future<FnthinkEndpointListResult> listEndpoints',
        ),
        1,
      );
      final page = stripComments(
        // T97 片B：那一下住在端点页，不在这张混合页里 —— 尺要跟着主语走。
        librarySource(root, 'lib/pages/fnthink_endpoint_page.dart'),
      );
      expect(
        page,
        contains('_coordinator.listEndpoints()'),
        reason: '页面上那一下必须走协调者（前置判定与 service 的生命周期都在那里）',
      );
      expect(
        occurrences(page, 'endpointList('),
        0,
        reason: '页面里出现 endpointList( ⇒ 它绕过协调者自己造了一份服务，dispose 谁负责？',
      );
    });

    test('摘要那一行没有口令：类体里 secret 这个概念根本不存在', () {
      // 读口的红线是"口令与它的摘要都不出门"。服务端那份投影已经去掉了这两样，
      // 设备侧一旦给 `FnthinkEndpointSummary` 加回一个 secret 字段，就等于在进程里
      // 常驻一份长期凭证 —— 而这条读口是每次翻开界面都会走的。
      final kernel = stripComments(
        librarySource(
          root,
          'packages/fnthink_push/lib/src/receive_kernel.dart',
        ),
      );
      final start = kernel.indexOf('class FnthinkEndpointSummary');
      expect(start, greaterThanOrEqualTo(0), reason: '内核里没有这个类：那一读的返回值换了地方');
      final end = kernel.indexOf('\n}', start);
      expect(end, greaterThan(start));
      final body = kernel.substring(start, end).toLowerCase();
      expect(
        body,
        isNot(contains('secret')),
        reason: '摘要类里出现 secret：读口从此带凭证，而"只出现一次"那句就成了假话',
      );
      // 解析那一段也不许读它（服务端多回一个键都不该被接住）。⚠ 边界必须量到**下一个方法的签名**
      // 而不是到 `_nonceCounter`：吊销/轮换那两个方法住在中间，而轮换**本来就要读**新口令
      // （`reply.body['secret']`）—— 拿一大段一起断言，红的是别人的合法代码，这条守卫就成了假红。
      final parseEnd = kernel.indexOf(
        'Future<FnthinkEndpointRevokeResult> endpointRevoke',
      );
      final parseStart = kernel.indexOf(
        'Future<FnthinkEndpointListResult> endpointList',
      );
      expect(parseStart, greaterThanOrEqualTo(0));
      expect(parseEnd, greaterThan(parseStart));
      final parse = kernel.substring(parseStart, parseEnd);
      expect(
        parse.toLowerCase(),
        isNot(contains('secret')),
        reason: '解析里出现 secret ⇒ 有人在把服务端可能多回的那个键接住，而它不该出现在这台设备上',
      );
    });
  });

  group('关掉一把入口那一反（#157 第四片）', () {
    test('服务层装配判定里含 endpointRevoke，内核那一发只有一个调用点', () {
      final src = read('lib/services/fnthink_receiver_service.dart');
      expect(
        src,
        contains("'endpointRevoke',"),
        reason: '漏登记 ⇒ 装配期不报错，第一次点"关掉这把"才在 transport 里抛',
      );
      expect(src, contains('kernel.endpointRevoke('));
    });

    test('那一发在 lib/ 只有一个作者：页面走协调者，不直连服务层', () {
      final coordinator = read('lib/services/fnthink_receive_coordinator.dart');
      expect(
        occurrences(coordinator, 'service.endpointRevoke('),
        1,
        reason: '两处就两本账：一处负责 dispose、一处不负责',
      );
      final page = stripComments(
        // T97 片B：那一行按钮住在端点页（混合页只剩一行入口，点下去连网络都不碰）。
        librarySource(root, 'lib/pages/fnthink_endpoint_page.dart'),
      );
      expect(
        page,
        contains('_coordinator.revokeEndpoint('),
        reason: '页面上那一行按钮必须走协调者（前置判定与 service 生命周期都在那里）',
      );
      expect(occurrences(page, 'endpointRevoke('), 0);
    });
  });

  group('换一把入口的口令那一反（#157 第六片）', () {
    test('服务层装配判定里含 endpointRotate，内核那一发只有一个调用点', () {
      final src = read('lib/services/fnthink_receiver_service.dart');
      expect(
        src,
        contains("'endpointRotate',"),
        reason: '漏登记 ⇒ 装配期不报错，第一次点"换一把口令"才在 transport 里抛',
      );
      expect(src, contains('kernel.endpointRotate('));
    });

    test('那一发在 lib/ 只有一个作者，而新口令只有一条去处 = 返回值', () {
      final coordinator = read('lib/services/fnthink_receive_coordinator.dart');
      expect(
        occurrences(coordinator, 'service.endpointRotate('),
        1,
        reason: '两处就两本账：一处负责 dispose、一处不负责',
      );
      final page = stripComments(
        // T97 片B：那一行按钮住在端点页。
        librarySource(root, 'lib/pages/fnthink_endpoint_page.dart'),
      );
      expect(
        page,
        contains('_coordinator.rotateEndpoint('),
        reason: '页面上那一行按钮必须走协调者（前置判定与 service 生命周期都在那里）',
      );
      expect(occurrences(page, 'endpointRotate('), 0);
      // 新口令与创建那一次同一红线：本机不留副本（prefs 里出现它 = 长期凭证跟着备份走）。
      for (final write in ['setString', 'SharedPreferences']) {
        expect(
          page,
          isNot(contains(write)),
          reason: '页面里出现了 $write：换出来的那把口令有了第二份去处，而没人负责清掉它',
        );
      }
    });
  });

  group('白名单通知触发那一路（契约 sources.L1 的第二条来源）', () {
    // 这一组全钉"接上了没有"，因为**接不上时没有任何症状**：白名单通知照常显示、
    // 照常推送、照常进历史，而没有任何东西动手 —— 用户配的自动化从此静默失效。
    // 每一段的功能用例都把依赖当参数传进来、不经过这三处接线，所以它们全绿也说明不了什么。

    test('DI 里 getIt<X>() 读到的每一个 X 都有注册（这一族只有模拟器会喊）', () {
      // ⚠⚠ 这一族**当场抓出三个真缺口**，而它们之前是"全量 1977 条 App 测试全绿"的状态：
      //   `getIt<SecureStorageService>()`（那个类从没注册过，它是 factory 单例，全仓八处直接 new）
      //   `getIt<DatabaseHelper>()`（同上，六处直接 new）
      //   `getIt<FnthinkSettings>()`（从没注册过，但它需要 contract ⇒ 正解是补注册）
      //
      // 为什么 widget 测试一条都不红：守卫里写的是 `isRegistered<T>()`，那**只查注册表**、
      // 不构造对象；而所有注册都是 lazy ⇒ 真正的崩发生在"谁先碰那条链"。片3c-6 之前
      // 碰那条链的只有收货循环（要等配对才跑），所以它在真机上一直藏着；
      // 挂到**首页首帧后无条件 drain** 之后，它变成"每次冷启动都崩在 getIt 上"。
      //
      // 这条判据断的是**差集为空**，不是某一行写对写错 —— 下一枚新服务忘了注册它立刻红。
      final locator = read('lib/di/service_locator.dart');
      final reads = RegExp(
        r'getIt<([A-Za-z_][A-Za-z0-9_]*)>\s*\(',
      ).allMatches(locator).map((m) => m.group(1)!).toSet();
      final regs = RegExp(
        r'register[A-Za-z]*<([A-Za-z_][A-Za-z0-9_]*)>',
      ).allMatches(locator).map((m) => m.group(1)!).toSet();
      final aliases = RegExp(
        r'as\s+([A-Za-z_][A-Za-z0-9_]*)\s*\)',
      ).allMatches(locator).map((m) => m.group(1)!).toSet();
      // ⚠ 别名必须一起收（`registerSingleton<X>(...) as Y` 会制造假差集），
      //   但也**不能**因为"差集算得出来"就当它必然为空 —— 下面那条正面锚点盯着解析本身。
      expect(reads, isNotEmpty, reason: 'getIt<X>() 一个都没解析到：本条守卫在空跑（口径漂移了）');
      expect(
        regs,
        contains('FnthinkSettings'),
        reason:
            '`DeviceL3Executor.collectInboxEnabled` 读的那一个补注册不见了 ⇒ '
            '翻 `collect_inbox` 那一档会在 getIt 上抛',
      );
      // ⚠ `difference` 而不是 `reads - regs`：Dart 的 Set **没有**差集运算符
      //   （那是 Python 的 `set - set`，照抄过来是 undefined_operator，整份文件加载失败 ——
      //   而"文件加载失败"在 CI 里表现为"这个文件没有用例"，不是红）。
      final missing = reads.difference(regs.union(aliases)).toList()..sort();
      expect(
        missing,
        isEmpty,
        reason:
            'DI 里读了但没有任何地方注册的服务：${missing.join(', ')}。'
            '所有注册都是 lazy ⇒ 谁先碰那条链谁崩，而症状（GetIt not registered）'
            '与真正的原因隔着一层，widget 测试压根构造不到它。',
      );
    });

    test('原生侧：白名单命中那一格真的把正文交出去了，且排在规则引擎之后', () {
      final service = read(
        'android/app/src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt',
      );
      expect(
        service,
        contains('LocalRemoteCommandInbox.offer('),
        reason:
            '通知监听那一格不再交出去了 ⇒ 白名单通知永远到不了 Dart，'
            '而通知照常显示、推送照常发生，没有任何一处会红',
      );
      expect(
        service,
        contains('filterResult.source == FilterSource.WHITELIST'),
        reason:
            '判定条件必须是**过滤来源**而不是白名单标题标签（`whitelistTag()`）：'
            '后者只在标题里多了三个字，改一次文案这条就静默失效',
      );
      // ⚠ 顺序是安全语义，不是排版：规则引擎说 Block 的那一条不许被交出去。
      //   放到 `RuleEngine.decide` 之前就是"规则拦得住推送、拦不住动手"。
      final decide = service.indexOf(
        'RuleEngine.decide(info, config.rulesJson)',
      );
      // ⚠⚠ 先断"只有一个交接点"再断它的位置。**只判 indexOf 是不够的**：
      //   在 `decide` 前面另插一次 `offer(...)`（那正是"提前交接"这个植入的样子），
      //   位置判据照样绿 —— 因为 indexOf 读到的是**后面**那一次真实的交接。
      //   形状可靠的那条是"交接点恰好一个"，而它也正是这一格的主语：
      //   多一个交接点 = 同一类通知可能被交出去两次。
      expect(
        occurrences(service, 'LocalRemoteCommandInbox.offer('),
        1,
        reason:
            '白名单正文出现了多个交接点 ⇒ 某条通知可能被交出去两次，'
            '而"交接点在规则引擎之后"那一问在多处时只看第一处，等于没问',
      );
      final offer = service.indexOf('LocalRemoteCommandInbox.offer(');
      expect(decide, greaterThanOrEqualTo(0), reason: '规则引擎那一发搬走了：本条守卫空跑');
      expect(
        offer,
        greaterThan(decide),
        reason: '交接被排到了规则引擎之前 ⇒ 用户明说"这条别动"的那些也会照样执行',
      );
      expect(
        service,
        contains('decision !is RuleEngine.Decision.Block'),
        reason: 'Block 那一档不再被排除 ⇒ 规则引擎拦得住推送、拦不住动手',
      );
    });

    test('原生侧：取口在执行那一格的方法表里，且方法名两端一致', () {
      final handler = read(
        'android/app/src/main/kotlin/com/fnthink/notice/channels/RemoteExecChannelHandler.kt',
      );
      expect(
        handler,
        contains('fnthinkRemoteExecTakeLocalCommand'),
        reason:
            'Dart 会去调一个没人认领的方法名 ⇒ 取口永远回 null，'
            '而症状是"白名单通知从不触发"，看起来像白名单没配对',
      );
      expect(handler, contains('LocalRemoteCommandInbox.take('));
      final notifier = read('lib/services/remote_execution_notifier.dart');
      expect(
        notifier,
        contains("'fnthinkRemoteExecTakeLocalCommand'"),
        reason: 'Dart 侧的方法名与原生那一格对不上：通道调用会静默变成 notImplemented',
      );
    });

    test('原生侧：引擎登记与注销成对（静态槽不能持着一个死引擎）', () {
      final activity = read(
        'android/app/src/main/kotlin/com/fnthink/notice/MainActivity.kt',
      );
      expect(
        occurrences(activity, 'LocalRemoteCommandInbox.attach('),
        2,
        reason:
            '成对才成形状：`configureFlutterEngine` 里登记、`cleanUpFlutterEngine` 里注销。'
            '只登记 ⇒ 每一条白名单通知都对着一具死引擎 invokeMethod（异常被吃掉，不崩、也不响应）',
      );
      expect(activity, contains('override fun cleanUpFlutterEngine('));
    });

    test('Dart 侧：DI 把取口接上了，且与执行链共用同一个 notifier', () {
      final locator = read('lib/di/service_locator.dart');
      expect(
        locator,
        contains('notifier: getIt<RemoteExecutionNotifier>()'),
        reason:
            '`RemoteCommandWiring` 的 notifier 是必填的，漏掉编译不过；'
            '而若改成自己 new 一个，读者会以为原生那一格有第二个实现（它没有）',
      );
    });

    test('Dart 侧：讯号与冷启动两个时刻都去取（否则某一条通知永远没人处理）', () {
      final page = stripComments(
        librarySource(root, 'lib/pages/main_page.dart'),
      );
      expect(
        page,
        contains("call.method == 'onLocalRemoteCommand'"),
        reason:
            '原生推的讯号没人接 ⇒ 白名单通知在 App 运行时永远不触发，'
            '只有在冷启动那一次会被取走。而那正是"我在用着手机，它一直没反应"的形状',
      );
      // 两个时刻：讯号（主路径）与首帧后（通知早于引擎起来的那一条）。
      // ⚠ 判的是**调用点**（`unawaited(_drainLocalRemoteCommands());`），不是标识符出现次数：
      //   后者把那一个**函数定义**也算进去，于是"删掉一处调用"仍是 3 >= 2 而照样绿。
      expect(
        occurrences(page, 'unawaited(_drainLocalRemoteCommands());'),
        2,
        reason:
            '两个时刻都得去取。少一个 ⇒ 另一条路（原生推 / 冷启动）上的通知永远留在原生那一堆里，'
            '而它 60 秒后过期被丢弃 —— 现象是"有时候有效有时候没反应"。'
            '（这里必须是恰好 2：多出来的调用会把同一条通知取两遍。）',
      );
      expect(
        page,
        contains('getIt<FnthinkContractLoader>().cached == null'),
        reason:
            '契约还没读到就构造 wiring 会在 `cached!` 上崩，而这次崩溃落在'
            '"首帧后回调 + 原生讯号"两条路上，现场没有任何线索指向它',
      );
    });

    test('前缀与新鲜期住在原生那一格，别在别处抄第二份', () {
      // `FRX1:` 与 60 秒各只该有一处。Dart 侧若再抄一份前缀判据，
      // 两处就会在"前缀改名"这件事上安静地错开一边。
      final inbox = read(
        'android/app/src/main/kotlin/com/fnthink/notice/LocalRemoteCommandInbox.kt',
      );
      expect(inbox, contains('"FRX1:"'), reason: '前缀判据不在交接那一格了：本条守卫空跑');
      expect(
        occurrences(inbox, 'FRX1'),
        1,
        reason: '交接那一格里 FRX1 出现多处 ⇒ 有一处是注释或第二份判据，前缀改名时会只改一边',
      );
      var dartSays = 0;
      for (final entity in Directory('$root/lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final code = stripComments(entity.readAsStringSync());
        dartSays += code.split('FRX1').length - 1;
      }
      expect(
        dartSays,
        0,
        reason:
            'lib/ 里出现了 FRX1 字面量 ⇒ Dart 侧多了一份"什么算一条本机指令"的判据，'
            '而原生那一格才是唯一定义处（判定拆信封在 Dart 的信封类里，不该在这里重抄）',
      );
    });
  });

  group('§4-10 片2：设备侧发送那一发的接线', () {
    test('装配判定里含 message，而投递面那扇门按契约词表反查（没有第二条路径）', () {
      final src = read('lib/services/fnthink_receiver_service.dart');
      expect(
        src,
        contains("'message',"),
        reason:
            '发送那一路的 URL 也从契约读。判定名单漏它 ⇒ 装配期不报错，'
            '第一次点"发一条"才在 transport 里抛，看起来像网络抖动',
      );
      expect(
        src,
        contains('contract.messageTypeLevels.containsKey(type)'),
        reason:
            '投递面的签字节 `type` 是**能力词表**里的一个，不是 clientEvents 那个事件词表里的；'
            '反查兜底必须按词表判，写死一个词就是第二个真值来源',
      );
      expect(src, contains("contract.apiPath('message')"));
      expect(
        src,
        isNot(contains('/api/fnthink/message')),
        reason: '出现字面量路径 ⇒ 契约那行声明从此没人读，改路径不会报错',
      );
    });

    test('发送只有一个作者：协调者→服务，页面不许直连；ts 与 nonce 都只有一处来源', () {
      final service = read('lib/services/fnthink_receiver_service.dart');
      final coordinator = read('lib/services/fnthink_receive_coordinator.dart');
      expect(occurrences(service, 'sendKernel.send('), 1);
      expect(occurrences(coordinator, 'service.sendNotice('), 1);
      expect(
        occurrences(service, 'signedTimestamp: () => kernel.signedTimestamp'),
        1,
        reason:
            '偏移只在收货那一侧学得会。发送侧自造一份 ⇒ 两端各有一本时钟账，'
            '表现是"收货正常而发送一路 410"，而 410 那句看起来像服务端坏了',
      );
      final page = stripComments(
        librarySource(root, 'lib/pages/fnthink_peers_page.dart'),
      );
      expect(
        page,
        contains('_coordinator.sendNotice('),
        reason:
            '那一行「发一条」现在开的是共用那张页（T98 片④），但**注入给它的那一发仍必须走协调者**：'
            '前置判定与 service 的生命周期都在那里',
      );
      expect(
        occurrences(page, 'FnthinkSendKernel('),
        0,
        reason: '页面自己造内核 = 绕过协调者那三道前置判定，而且没人 dispose 那份 HTTP 客户端',
      );
    });
  });

  group('发送健康度那一接（T60 approach B：复用 Dart 侧健康度，不碰原生 RetryQueue）', () {
    test('DI 把 recordHealth 接到了 ChannelHealthStore（漏接时发送照常、页面那行永远"从没发过"）', () {
      final locator = read('lib/di/service_locator.dart');
      expect(
        locator,
        contains('recordHealth:'),
        reason:
            '漏接 ⇒ 发送本身照常、协调者测试也能用钩子验到，但生产里没人把可达性落到 '
            'ChannelHealthStore ⇒ 幻念页那一行永远读不到东西，"通道化"退化成一个空钩子',
      );
      expect(
        locator,
        contains('getIt<ChannelHealthStore>().record('),
        reason: '健康度只有 ChannelHealthStore 这一个作者，别在装配点又 new 一份读写',
      );
      expect(
        locator,
        contains('kFnthinkServerFamily'),
        reason:
            'family 必须用那个具名常量：页面读、协调者写各打一份 "fnthink" 字面量时，'
            '改一个忘一个的表现是徽标永远"没测过"（读写键不等）。'
            '⚠ T104 片① 之后这里认的是**服务器**那一族（id＝host），不是通道那一族（id＝通道行 id）',
      );
      expect(
        RegExp(r'record\(\s*kFnthinkChannelSlug').hasMatch(locator),
        isFalse,
        reason:
            '装配点用**通道主语**那枚常量去记服务器可达性 ⇒ 两种主语又挤回一个族名了：这一发记的是'
            '"这台服务器通不通"，与首页那条通道行的徽标是两件事（串台时不报错，只会说错话）',
      );
    });

    test('协调者只在 sendNotice 那一发之后记健康度，且经纯函数判可达性', () {
      final src = read('lib/services/fnthink_receive_coordinator.dart');
      expect(
        src,
        contains('_recordSendHealth('),
        reason: '健康度落点必须在 sendNotice 之后 —— 收货循环/配对那些发不产"发送可达性"',
      );
      expect(
        src,
        contains('fnthinkSendStatusServerReachability(result.status)'),
        reason: '可达与否必须由那张 11 档词表函数判，不在调用点现编（否则"没离机"会被当成不可达）',
      );
    });

    test('chan: 字面量仍只在 channel_display.dart，fnthink 走具名 slug', () {
      // 本条切片给 identity 层加了 fnthink；钉它没有在生产 lib 里散出 'chan:' 字面量，
      // 也没有把 family 名硬编成第二处。
      final display = read('lib/services/channel_display.dart');
      expect(display, contains("kFnthinkChannelSlug = 'fnthink'"));
      expect(display, contains("'fnthink': ('幻念推送'"));
    });
  });

  group('自登记那一发（#177 —— 其余每一发的共同前置）', () {
    test('DI 把自登记接上了，且它走的是同一个服务构造', () {
      final locator = read('lib/di/service_locator.dart');
      expect(
        locator,
        contains('registerDevice:'),
        reason:
            '漏接这一行 ⇒ 全场 Dart 测试仍然绿，而真机上所有请求都换回同形的 403 '
            'rejected_unsigned（用户报的「建立端点：端点没建成」就是这条）',
      );
      expect(
        locator,
        contains('buildFnthinkReceiveService(spec)'),
        reason: '自登记那一发也得过同一个服务构造：自己 new 一份就把装配期那三道判定劈成两份口径',
      );
      expect(locator, contains('service.register('));
      expect(
        locator,
        contains('DeviceInfoService>().deviceName'),
        reason: '名字取设备信息服务那一份；随手写个空串，管理面上就认不出这是哪台',
      );
    });

    test('协调者把自登记夹在"就绪"与"交出 spec"之间（每个入口都过那里）', () {
      final src = read('lib/services/fnthink_receive_coordinator.dart');
      expect(src, contains('registerDevice'));
      expect(
        src,
        contains('final registerReason = await _ensureRegistered(spec);'),
        reason:
            '自登记的落点必须在 `_resolveSpec` 里（开始循环、挂口令、答复、撤销、端点四种、'
            '发一条都先过它）；挪到调用方那一侧就变成"谁记得谁接"',
      );
      expect(
        src,
        contains(
          'if (registerReason != null) return (spec: null, reason: registerReason);',
        ),
        reason: '登记没成还不早退 ⇒ 后面每一发都白换一句同形的 403，界面上看不出是为什么',
      );
    });

    test('服务层的自登记有两道本地闸：签不出来、或没有公钥，都不发', () {
      final src = read('lib/services/fnthink_receiver_service.dart');
      expect(
        src,
        contains("'register',"),
        reason:
            '装配期的 apiPaths 判定里缺 register ⇒ 不报错，第一次要登记时在 transport 里抛'
            '（把契约与实现不匹配伪装成网络抖动）',
      );
      expect(src, contains('kernel.register('));
      expect(
        src,
        contains('await signer.publicKey()'),
        reason: '交出去的公钥只能来自签名口 —— 那是"与私钥成对"的唯一来源',
      );
      expect(src, contains("'no-public-key'"));
    });

    test('自登记在全仓只有一个作者（每一发都过协调者，不需要第二处）', () {
      final hits =
          Directory('$root/lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              .map(
                (f) => f.path
                    .replaceAll('\\', '/')
                    .replaceFirst(RegExp(r'^\./'), ''),
              )
              .where((p) => read(p).contains('service.register('))
              .toList()
            ..sort();
      expect(
        hits,
        ['lib/di/service_locator.dart'],
        reason:
            '多一处调用 = 多一份"什么时候该登记"的口径，而其中一份会在换地址/换码之后'
            '悄悄不成立；页面尤其不许直接碰它',
      );
    });
  });

  group('启动链上不许构造需要契约的东西（这一族只有模拟器/真机会喊）', () {
    // ⚠⚠ 下面两条都是 2026-10-05 在模拟器跑集成冒烟时**当场红出来**的，而它们的症状
    //   在 widget 测试里一模一样地绿：那些 harness 预先把契约塞进了 loader，
    //   所以 `cached!` 永远不炸。真实的冷启动链（`setupLocator` → `_onServicesInitialized`
    //   → `MainPage.build`）**从不**读契约 —— 全仓唯一的 `load()` 调用在
    //   `main_page_actions` 的一个动作里（用户碰了才读）。
    //
    //   也就是说「契约还没读」是**冷启动的常态**，而任何 `cached!` 都要为此付一次白屏。

    test('撤销横幅那一格在取 runner 之前先问契约（去掉它就是冷启动白屏）', () {
      final page = stripComments(
        librarySource(root, 'lib/pages/main_page.dart'),
      );
      final at = page.indexOf('isRegistered<RemoteCommandRunner>()');
      expect(at, greaterThanOrEqualTo(0), reason: '撤销横幅那一格搬走了：请把这条一起搬过去，别删');
      // ⚠ 判的是**同一个 `if (...)` 里有没有那半句**，而不是"同一行"：
      //   `dart format` 会把两个条件折成两行（`cached != null &&` / `isRegistered<…>()`），
      //   同行判据会在格式化之后变成假红。窗口往前取够（默认 80 列放得下两个条件）。
      // ⚠ 也**不是**"文件里出现过 cached != null" —— 那会被 `_drainLocalRemoteCommands`
      //   里那一句喂成恒绿（而那一句是对的，不能算在这条账上）。
      final winStart = at > 300 ? at - 300 : 0;
      final winEnd = at + 60 > page.length ? page.length : at + 60;
      final window = page.substring(winStart, winEnd);
      expect(
        window,
        contains('cached != null'),
        reason:
            '取 RemoteCommandRunner 之前没有先问契约 ⇒ 构造那个 lazy singleton 时 '
            '`cached!` 崩 ⇒ 首页整页起不来（冷启动白屏）。'
            '判据必须与那一格同在一个 if 表达式里：文件别处也写着 `cached != null`，'
            '数它出现过几次是恒绿的假判据。',
      );
    });

    test('启动链读不读契约这件事要被看见（谁先碰 cached! 谁得自己判）', () {
      // 这条**不判**「启动链必须加载契约」—— 那是产品决定，不是我能替他做的。
      // 它只把"读契约的唯一入口在哪"钉住，免得下一个加 cached! 的人以为自己有底。
      expect(
        read('lib/services/fnthink_contract_loader.dart'),
        contains('Future<FnthinkContract> load('),
        reason: '契约装载器的读口没了：加 cached! 的人就没有兜底的判断依据',
      );
      expect(
        stripComments(read('lib/main.dart')),
        isNot(contains('FnthinkContractLoader>().load(')),
        reason:
            '启动链改成**主动**读契约了 ⇒ 上面那两条守卫的前提（cached 冷启动为 null）'
            '已经变松。请重新评估：要么它们可以删掉，要么要换成"读失败时也不许崩"。'
            '把它留成红是为了让"有人改了这件事"必须被看见，而不是让旧判据悄悄失去意义。',
      );
    });
  });

  group('非浸入探针那一发（T106 片②）', () {
    test('服务层装配判定里含 probe，内核那一发只有一个调用点', () {
      final src = read('lib/services/fnthink_receiver_service.dart');
      expect(
        src,
        contains("'probe',"),
        reason: '漏登记 ⇒ 装配期不报错，第一次自动重探才在 transport 里抛，而那一句看起来像网络抖动',
      );
      expect(src, contains('kernel.probe('));
    });

    test('这一发只有一个作者：页面走协调者，不直连服务层', () {
      // ⚠ 与上面那几条同族的"读者"（自动重探）要到片③才落 —— 这一条今天只钉"没有第二个作者"：
      //   页面直连服务层 ⇒ 前置判定（契约/地址/同意门/自登记）与 service 生命周期都被跳过。
      expect(
        read('lib/services/fnthink_receive_coordinator.dart'),
        contains('Future<FnthinkProbeResult> probePeer('),
      );
      for (final page in [
        'lib/pages/fnthink_channel_settings_page.dart',
        'lib/pages/fnthink_channel_list_page.dart',
      ]) {
        expect(
          occurrences(read(page), 'probePeer('),
          0,
          reason: '$page 直连了探针那一发',
        );
      }
    });
  });
}

class _StubSigner implements FnthinkIdentitySigner {
  @override
  Future<String> call(List<int> canonicalBytes) async =>
      base64Encode(Uint8List(64));

  @override
  Future<bool> probe() async => true;

  @override
  Future<String?> publicKey() async => base64Encode(Uint8List(32));
}
