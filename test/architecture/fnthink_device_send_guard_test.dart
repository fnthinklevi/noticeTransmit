import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/di/service_locator.dart';
import 'package:notice_transmit/services/fnthink_receive_coordinator.dart';

import '../support/source_guards.dart';

/// 设备侧发送第一片（§4 第 10 条）的**守卫**：标题信封这件事只剩一个出处、一个拆的人。
///
/// 为什么这些判据值得单独钉，而不是靠包侧那 21 条用例：
///  - 用例测的是"实现对不对"，这里钉的是"下一个改动还能不能只对一半"。
///    信封这件事最坏的走法不是算错，而是**两处各算一次**：发送端一套、收件端一套、
///    页面再来一套 —— 那三套在各自那一天都可能是对的，而它们两两之间的差别没有任何一条用例看得见。
///  - 前缀与键名一旦在代码里写死一次，契约上那一行就从此没人读了：换 v2 时表现是
///    "旧客户端把新信封整段当正文显示"，而这件事在两端各自的测试里都是绿的。
void main() {
  final contract = FnthinkContract.readFile();
  final root = projectRoot();
  final prefix = contract.deviceTitlePrefix;

  String readCode(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  List<String> dartFiles(String dirRel) {
    // Windows 上 listSync 给的是反斜杠路径：先归一再截，否则"截掉根目录长度"这一刀
    // 会截出半截文件名（这条在新守卫第一次跑时就红过）。
    final normRoot = root.replaceAll(r'\', '/');
    final dir = Directory('$root/$dirRel');
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.path.replaceAll(r'\', '/').substring(normRoot.length + 1))
        .toList()
      ..sort();
  }

  int occurrences(String haystack, String needle) =>
      RegExp(RegExp.escape(needle)).allMatches(haystack).length;

  group('唯一出处', () {
    test('前缀与键名的字面量不许出现在任何一端的代码里（契约与向量文件之外一处都没有）', () {
      final scanned = [
        ...dartFiles('lib'),
        ...dartFiles('packages/fnthink_push/lib'),
      ];
      // 基线：先证明"这一批文件确实被读到了"，否则这条断言会在文件树改名之后照样绿。
      expect(
        scanned.any((p) => p.endsWith('title_envelope.dart')),
        isTrue,
        reason: '扫描没覆盖到包侧的 src 目录 ⇒ 本守卫今天空转',
      );
      final hits = <String>[];
      for (final rel in scanned) {
        final code = readCode(rel);
        for (final needle in [prefix, 'fnthink-title']) {
          if (code.contains(needle)) hits.add('$rel → $needle');
        }
      }
      expect(hits, isEmpty, reason: '写死一份就是第二个真值来源：契约那一行从此没人读');
    });

    test('编解码的调用点各只有一处，而 App 侧一处都不自己拆', () {
      final encode = occurrences(
        readCode('packages/fnthink_push/lib/src/send_kernel.dart'),
        'FnthinkTitleEnvelope.encode',
      );
      final unwrap = occurrences(
        readCode('packages/fnthink_push/lib/src/receive_kernel.dart'),
        'FnthinkTitleEnvelope.unwrap',
      );
      expect(encode, 1, reason: '编码点不止一处 ⇒ 两处会漂，而漂了的表现是标题静默消失');
      expect(
        unwrap,
        1,
        reason: '收件端只许有一个拆的人（契约 splitBy=receiving-client 的实现形式）',
      );

      final appFiles = dartFiles('lib');
      final appHits = [
        for (final rel in appFiles)
          if (readCode(rel).contains('FnthinkTitleEnvelope')) rel,
      ];
      expect(
        appHits,
        isEmpty,
        reason:
            '页面/服务里再拆一次 = 同一台机器上两处拆信封，而其中一处漏了"已签标题非空就不拆"，'
            '显示出来的就是猜出来的标题',
      );
    });

    test('跨端向量两侧的读者都还在（少一侧 ⇒ 这份表退化成一端的家谱）', () {
      final dartReader = File(
        '$root/packages/fnthink_push/test/title_envelope_test.dart',
      ).readAsStringSync();
      final jsReader = File(
        '$root/server/test/fnthink-title-envelope.test.js',
      ).readAsStringSync();
      expect(occurrences(dartReader, "'titleEnvelope'"), greaterThan(0));
      expect(occurrences(jsReader, 'titleEnvelope'), greaterThan(0));
      expect(
        occurrences(dartReader, 'FnthinkTitleEnvelope.encode'),
        greaterThan(0),
        reason: 'Dart 侧不再复放编码 ⇒ 这一半向量只剩 Node 在读，而 Node 不编码',
      );
    });
  });

  group('形状', () {
    test('发送那一发没有"顶层 title"这条路：内核构造的信封只有三个键', () {
      final code = readCode('packages/fnthink_push/lib/src/send_kernel.dart');
      // 只看**构造对外信封**那一段字面量：整文件找 'title' 会撞上本地判据用的映射，
      // 而那种命中既不是这条守卫要防的，也不该防（防它就是防自己写清楚"哪个字段含分隔符"）。
      final built = blockAfter(code, 'final envelope = <String, Object?>{');
      expect(
        occurrences(built, "'title'"),
        0,
        reason:
            '签名字节里没有 title，顶层那个一定被服务端丢掉。允许它出现在构造处，'
            '就是允许下一个读代码的人以为"带上试试有用"',
      );
      expect(
        [
          for (final key in ["'sender'", "'signature'", "'fields'"])
            occurrences(built, key),
        ],
        [1, 1, 1],
      );
    });

    test('设备面投递那条路径不是一种 clientEvents 事件（否则会被按 messageType 反查认领）', () {
      // 接线层是**按签字节里的 type 反查事件种类**来选 URL 的。设备发送的 `type` 是能力词表里的
      // `notice`，所以它绝不能落进那张反查表 —— 落进去的表现是"一条消息被当成某种事件发进门"。
      expect(contract.apiPaths.containsKey('message'), isTrue);
      final eventTypes = [
        for (final kind in contract.apiPaths.keys)
          contract.str(['clientEvents', kind, 'messageType']),
      ];
      expect(
        eventTypes.whereType<String>().toSet().intersection(
          contract.messageTypeLevels.keys.toSet(),
        ),
        isEmpty,
        reason: '能力词表里的 type 与事件词表撞上了：反查会先把消息认成某种事件',
      );
    });

    test('发送结论那句话只有一个作者（两个入口共用一份，不许各说各的）', () {
      // T48 收尾：发送这一发现在有两个入口（幻念推送页名单行、历史页收件详情）。
      // 11 档状态各有各的原话，抄第二份的下场是"同一个状态在两个页面说两句话" ——
      // 而用户看哪一句，取决于他当时在哪一页。
      final senders = dartFiles('lib')
          .where((p) => readCode(p).contains('FnthinkSendStatus.accepted =>'))
          .toList();
      expect(
        senders,
        ['lib/widgets/fnthink_send_dialog.dart'],
        reason:
            '把"状态 → 原话"的 switch 抄进第二个文件 ⇒ 那一档以后只在一边改。'
            '结论文案的唯一作者是 `fnthinkSendResultText`（两页都调它）',
      );
      for (final page in const [
        'lib/pages/fnthink_push_page.dart',
        'lib/pages/history_page.dart',
      ]) {
        expect(
          readCode(page),
          contains('fnthinkSendResultText('),
          reason: '$page 必须经那一份文案，而不是自己拼句子',
        );
      }
    });

    test('「我发过的」那一档的写入者接在装配点上（漏接时那一档永远是空的）', () {
      // T43：发送被受理之后由协调者把这一条落进表（方向 out）。DI 漏接时的表现不是崩，
      // 是**历史页那一档永远是空的** —— 用户发过的每一条都查不到，而全场测试仍然绿
      // （协调者的用例都把 recordSent 当参数传进来，不经过 DI）。
      setupLocator();
      final c = getIt<FnthinkReceiveCoordinator>();
      expect(
        c.recordSent,
        isNotNull,
        reason: '漏接 `recordSent:` 这一行 ⇒ 「我发过的」那一档没有作者',
      );
    });

    test('历史页那一发也走同一套发送层（不许自己拼 HTTP、也不许自己读名单表）', () {
      final history = readCode('lib/pages/history_page.dart');
      expect(
        history,
        contains('GetIt.instance<FnthinkReceiveCoordinator>().sendNotice('),
        reason: '收件详情里的回复/重发必须调协调者那一发 —— 签约、请求体、状态码全在它后面',
      );
      expect(
        history,
        contains('GetIt.instance<FnthinkPeerService>().list()'),
        reason: '找"发送方还在不在名单里"要走名单读咽喉（唯一读口）',
      );
      for (final forbidden in const [
        'fnthink_peers', // 直连名单表
        'loadFnthinkPeers', // 绕过读咽喉
        'apiPath(', // 自己拼路径
        'http.Client(', // 自己拼 HTTP
      ]) {
        expect(
          history,
          isNot(contains(forbidden)),
          reason: '历史页里出现 $forbidden ⇒ 这一页长出了第二套发送/名单实现',
        );
      }
    });
  });
}
