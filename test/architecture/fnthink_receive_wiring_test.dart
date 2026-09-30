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
      // 这一条存在的理由是一段已经上线的行为：`startIfEnabled()` 全仓只有 `fnthink_push_page`
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
      final pageTest = read('test/widgets/fnthink_push_page_test.dart');
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
        librarySource(root, 'lib/pages/fnthink_push_page.dart'),
      );
      expect(
        page,
        contains('pairRequestsListenable'),
        reason: '页面不再从协调者那份账读了：本条守卫已经在空跑',
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
        librarySource(root, 'lib/pages/fnthink_push_page.dart'),
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
      final page = stripComments(
        librarySource(root, 'lib/pages/fnthink_push_page.dart'),
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
        librarySource(root, 'lib/pages/fnthink_push_page.dart'),
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
        librarySource(root, 'lib/pages/fnthink_push_page.dart'),
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
        librarySource(root, 'lib/pages/fnthink_push_page.dart'),
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
        librarySource(root, 'lib/pages/fnthink_push_page.dart'),
      );
      expect(
        page,
        contains('_coordinator.sendNotice('),
        reason: '页面上那一行「发一条」必须走协调者：前置判定与 service 的生命周期都在那里',
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
        contains('kFnthinkChannelSlug'),
        reason:
            'family 必须用那个具名常量：页面读、协调者写各打一份 "fnthink" 字面量时，'
            '改一个忘一个的表现是徽标永远"没测过"（读写键不等）',
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
