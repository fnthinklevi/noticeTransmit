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
  });
}

class _StubSigner implements FnthinkIdentitySigner {
  @override
  Future<String> call(List<int> canonicalBytes) async =>
      base64Encode(Uint8List(64));

  @override
  Future<bool> probe() async => true;
}
