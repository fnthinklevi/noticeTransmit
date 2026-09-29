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

  tearDown(() => getIt.reset());

  group('装配点', () {
    test('DI 起来的 coordinator 两条副作用都在（display 被漏掉时全场仍绿，所以只能靠这条）', () {
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
}

class _StubSigner implements FnthinkIdentitySigner {
  @override
  Future<String> call(List<int> canonicalBytes) async =>
      base64Encode(Uint8List(64));

  @override
  Future<bool> probe() async => true;
}
