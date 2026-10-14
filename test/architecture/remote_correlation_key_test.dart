import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T143 片2 的架构守卫：回执关联键这一族的「两侧不分家」与「那一格真的接上了」。
///
/// ⚠ 这里钉的三种失效**都没有症状**，所以只能这么钉：
/// ① 键名分家（契约改一侧、包没改，或 lib/ 里有人手拼载荷）⇒ 回执永远不带键 ⇒
///    发起端那一行恒停在「待执行」，而界面上那句"已交出去"读起来完全没错；
/// ② 发送侧铸造两枚 id（载荷里那枚 ≠ 落库那一行的主键）⇒ 症状与 ① 逐字相同；
/// ③ 认领那一格没接上（DI 漏 `loadRecord`，或解码排在判定之后）⇒ 回执**弹成一条通知**，
///    而用户读到的是"对方回了我一句话"，其实那句话是"你那条我办完了"。
///
/// ⚠ 断的是**结构与同源**，不是写法：具名参数怎么换行、变量叫什么之外的排版都不在本条范围内
/// （T148 那条纪律 —— 钉字面抄本的守卫会在无关格式化那天假红）。
void main() {
  final root = projectRoot();
  final libCode = libCodeByRel(root);
  final contract = FnthinkContract.readFile();

  group('键名两侧不分家', () {
    test('包内那枚常量 ≡ 契约声明的那一枚（差一枚就静默失效）', () {
      expect(
        kFnthinkRemoteCorrelationKey,
        contract.remoteExecutionCorrelationKey,
        reason:
            '载荷里写的键名与协议声明的键名分家了：'
            '$kFnthinkRemoteCorrelationKey vs ${contract.remoteExecutionCorrelationKey}。\n'
            '两边各自成立，合起来的症状是"回执回来了但一行都没更新"。',
      );
    });

    test('lib/ 里不许出现第二份手拼的载荷（键名字面量只许住在包里）', () {
      // 扫的是「带引号的键名」那一种写法：具名参数 `exec: execId` 不带引号，合法；
      // 而 `'exec':` / `"exec":` 是在应用层自己拼载荷，绕开了信封那一层。
      final where = libCode.entries
          .where(
            (e) =>
                e.value.contains("'exec'") ||
                e.value.contains('"exec"') ||
                e.value.contains("'exec':") ||
                e.value.contains('"exec":'),
          )
          .map((e) => e.key)
          .toList();
      expect(where, isEmpty, reason: '应用层出现了手拼的关联键字面量：$where');
    });

    test('载荷的两端都从包里那一枚常量取（字面量在包里也只出现一次）', () {
      final src = stripComments(
        File(
          '$root/packages/fnthink_push/lib/src/remote_command.dart',
        ).readAsStringSync(),
      );
      expect(
        RegExp("'exec'").allMatches(src).length,
        1,
        reason:
            '带引号的键名在信封文件里出现了不止一次 ⇒ 常量之外有人手拼了一份。'
            '两处各自都能改，改开的症状是"回执回来但一行都没更新"。',
      );
      expect(src, contains('kFnthinkRemoteCorrelationKey'));
    });
  });

  group('发起端那一行与载荷里那枚是同一枚（同源）', () {
    test('发送页只铸造一枚 id（载荷与那一行的主键不许是两个）', () {
      final src = libCode['pages/fnthink_send_page.dart']!;
      expect(
        'newRemoteExecutionId'.allMatches(src).length,
        1,
        reason:
            '出现第二枚 id ⇒ 回执对不上是必然的。关联键的值**必须**就是那一行的主键，'
            '铸造两次等于给同一件事两个作者。（同源性本身的行为证据在 '
            '`remote_execution_pages_test.dart` 的那条「载荷里那枚 = 那一行的主键」。）',
      );
    });
  });

  group('认领那一格接在收货循环上', () {
    test('wiring：回执解码排在判定**之前**（排后面 = 弹成一条通知）', () {
      final src = libCode['services/fnthink_remote_wiring.dart']!;
      final decode = src.indexOf('RemoteReceiptEnvelope.decode');
      final judge = src.indexOf('recognizer.parse');
      expect(decode, greaterThan(-1), reason: '接线层不再解回执 = 片2 那一格被摘掉了');
      expect(judge, greaterThan(-1));
      expect(
        decode,
        lessThan(judge),
        reason: 'FRR1: 拆不进指令信封 ⇒ 排在判定之后会走 NotACommand ⇒ 按通知弹出来',
      );
    });

    test('wiring：认领动的是那张表的同一行（读 loadRecord + 写 saveRecord）', () {
      final src = libCode['services/fnthink_remote_wiring.dart']!;
      expect(src, contains('remoteOutRowForReceipt('));
      expect(src, contains('loadRecord('));
      // 必填、不给默认值：这一格漏接时没有任何症状（见类注释），所以要扫得到它被声明。
      expect(src, contains('required this.loadRecord'));
    });

    test('DI：RemoteCommandWiring 的 loadRecord 接的是那张表唯一的那个读口', () {
      final src = libCode['di/service_locator.dart']!;
      final start = src.indexOf('RemoteCommandWiring(');
      expect(start, greaterThan(-1), reason: 'DI 里不再装配接线层 ⇒ 远程执行整条链是死的');
      final block = src.substring(start, start + 1400);
      expect(
        block,
        contains('loadRecord'),
        reason: '回执认领的读口没接上：回执会照常回来，而本机一行都不更新',
      );
      expect(block, contains('remoteExecutionRecord'));
      expect(block, contains('saveRemoteExecutionRecord'));
    });
  });
}
