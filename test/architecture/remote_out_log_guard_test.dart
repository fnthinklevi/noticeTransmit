import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_remote_out_record.dart';

import '../support/source_guards.dart';

/// T143 片1 的装配守卫（维护者 2026-10-12 裁定 2：发起端一发送就写一行 out）。
///
/// 这三条钉的都是"漏了不会报编译错、只会静默空转"那一族（T141 的 `onCommand`、
/// T151 的 `hiddenChannelCount`、T147 的 `executionEvents` 是同一形状）：
/// ① 装配点少接一处 ⇒ 那一档**永远空着**，而页面上那句话照样说"已发出"；
/// ② 第一写挪到 send 之后 ⇒ "按下过、结果不明"那一段读不出来（用例只从已接好线的页面进去，
///    看不出这个次序）；
/// ③ out 那一行的 `source` 必须在契约那两枚封闭词里（自己造一个词，两边各判一次）。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());
  int countOf(String src, String needle) => src.split(needle).length - 1;

  group('装配点：每一处 FnthinkSendDeps 都真的带上了那枚写口', () {
    test('lib/pages 里构造 deps 的四张页，每一处都接了 saveRemoteExecution', () {
      final sites = <String, List<int>>{};
      for (final f in Directory(
        '$root/lib/pages',
      ).listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final name = f.uri.pathSegments.last;
        // 定义那一处不算装配点：`required this.saveRemoteExecution,` 里根本没有
        // `saveRemoteExecution:` 这种写法，把它一起数会造出一处"没接线"的假红。
        if (name == 'fnthink_send_page.dart') continue;
        final src = read('lib/pages/$name');
        final built = countOf(src, 'FnthinkSendDeps(');
        final wired = countOf(src, 'saveRemoteExecution:');
        if (built > 0) sites[name] = [built, wired];
      }
      expect(
        sites.keys.toList()..sort(),
        const [
          'fnthink_peers_page.dart',
          'fnthink_remote_page.dart',
          'history_page.dart',
          'notification_engine_page.dart',
        ],
        reason:
            '这张页的装配点清单漂了要当场看见 —— 多出一个入口而没接写口，'
            '那个入口点进去就是"发"那一档永远空',
      );
      for (final entry in sites.entries) {
        expect(
          entry.value[1],
          entry.value[0],
          reason:
              '${entry.key} 构造了 ${entry.value[0]} 次 deps，只接了 '
              '${entry.value[1]} 次写口',
        );
      }
    });
  });

  group('写的次序与词表', () {
    test('第一写在 send **之前**、第二写在 send **之后**（都在 _sendCommand 那一段里）', () {
      final body = blockAfter(
        read('lib/pages/fnthink_send_page.dart'),
        'Future<void> _sendCommand() async {',
      );
      final firstWrite = body.indexOf('saveRemoteExecution(outRow)');
      final send = body.indexOf('widget.deps.send(');
      final secondWrite = body.indexOf('saveRemoteExecution(', send + 1);
      expect(firstWrite, greaterThanOrEqualTo(0));
      expect(send, greaterThanOrEqualTo(0));
      expect(
        firstWrite < send,
        isTrue,
        reason:
            '写在 send 之后 ⇒ 那一发卡在路上（或这台被杀掉）时账上什么都没有，'
            '而用户确实按下过；第一写要回答的是"我按过"，第二写才是"结果如何"',
      );
      expect(
        secondWrite > send,
        isTrue,
        reason: 'send 的结论必须有第二次写，否则这一行永远停在 pending 而没人补它',
      );
    });

    test('out 那一行的 source 在契约每一档的来源词表里', () {
      final contract = FnthinkContract.readFile();
      for (final level in contract.capabilityLevels) {
        expect(
          contract
              .remoteExecutionSourcesFor(level)
              .contains(kFnthinkRemoteOutSource),
          isTrue,
          reason:
              '$level 的来源词表里没有这一枚 ⇒ 历史页与对面的判定各读一张表，'
              '这一行会变成"谁都不认得"',
        );
      }
    });

    test('页面不直连那张表（写只经 deps 的那枚写口）', () {
      final page = read('lib/pages/fnthink_send_page.dart');
      expect(
        page,
        isNot(contains('saveRemoteExecutionRecord')),
        reason:
            '页面自己 new DatabaseHelper，就是给这张表长出第二个写入姿势 —— '
            'in 方向那几行走的是"注入一个 lambda"，out 这一路也只许走写口',
      );
    });
  });
}
