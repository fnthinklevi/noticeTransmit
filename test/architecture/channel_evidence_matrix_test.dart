import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/channel_descriptor_service.dart';

import '../support/channel_descriptor_fixtures.dart';
import '../support/source_guards.dart';

/// 通道可用性证据矩阵（roadmap T09）的**结构**守卫。
///
/// 为什么要把它变成一份 JSON + 一群断言，而不是一张 markdown 表格：表格会在改代码的人
/// 看不见的地方腐烂。三件会静默发生的事，这里都成了红：
/// 1. **新增一个通道类型，矩阵里没有它这一行**（表现是"这一类的可用性从来没人评估过"，
///    而发版检查表上看不出缺了什么）；
/// 2. **声称有证据，实际那个证据不存在**（golden 键被改名/测试类被删 ⇒ 列上还是 ✅）；
/// 3. **"真发一次"被顺手打个勾**（盖章必须带日期/构建号，且盖章总数是显式数字，
///    要涨必须先改那个数字 —— 逼一次对话"你到底验过没有"）。
void main() {
  final root = projectRoot();

  /// ⚠ 两份 JSON 与描述符表全部**惰性读取**：早先在 `main()` 顶层解码，文件改名或 JSON
  ///   语法坏掉会抛在测试体之外 ⇒ 整个文件加载失败，CI 表现为"这个文件没有用例"而不是红
  ///   （本仓库撞过三次，见 base.md（75））。
  Map<String, dynamic> readJson(String rel) =>
      jsonDecode(File('$root/$rel').readAsStringSync()) as Map<String, dynamic>;

  Map<String, dynamic> matrix() =>
      readJson('test/evidence/channel_availability_matrix.json');
  List<Map<String, dynamic>> rows() =>
      (matrix()['types'] as List<Object?>).cast<Map<String, dynamic>>();
  List<ChannelDescriptor> descriptors() => exportedDescriptors()
      .map((d) => ChannelDescriptor.fromMap(Map<dynamic, dynamic>.from(d)))
      .toList();
  Set<String> payloadKeys() =>
      (readJson(
                'android/app/src/test/resources/channel_behavior_golden.json',
              )['payloads']
              as Map<String, dynamic>)
          .keys
          .toSet();

  /// 各族"状态/备份列"的证据指针允许指向哪里（族 → 文件）。
  /// 写死在这里是有意的：证据必须落在**具体文件**上，不能是一句"看闸门"。
  const familyFiles = <String, List<String>>{
    'webhook': [
      'test/widgets/webhook_channel_list_page_test.dart',
      'test/widgets/webhook_settings_page_test.dart',
    ],
    'app': [
      'test/widgets/app_channel_list_page_test.dart',
      'test/widgets/app_channel_settings_page_test.dart',
    ],
    'email': ['test/widgets/email_settings_page_test.dart'],
  };

  List<Map<String, dynamic>> rowsWithPayload(String prefix) => rows()
      .where((r) => (r['payloadEvidence'] as String).startsWith(prefix))
      .toList();

  group('证据矩阵的结构', () {
    test('矩阵与 golden 快照的规模固定（拦住"筛出 0 行 ⇒ 下面所有循环空跑"的假绿）', () {
      expect(
        rows(),
        hasLength(15),
        reason: 'T08-C 起 email 也算一类，类型总数是 15；这数字变了要先说清楚少了谁',
      );
      expect(payloadKeys(), isNotEmpty, reason: '载荷快照一枚都没解出来 ⇒ 指针核对全体退化成空断言');
      expect(
        rowsWithPayload('golden'),
        hasLength(12),
        reason: 'golden 指针行数漂了：下面那条"四个场景键都在"覆盖的行数就变了',
      );
      expect(
        rowsWithPayload('jvm:'),
        hasLength(3),
        reason: 'jvm 指针行数漂了：下面那条"测试类真断言了载荷"覆盖的行数就变了',
      );
    });

    test('每个描述符类型恰好一行，family 与原生表一致', () {
      final declared = rows().map((r) => r['type'] as String).toList();
      expect(
        declared.toSet().length,
        declared.length,
        reason: '同一个类型两行：哪一行的结论算数？',
      );
      expect(
        declared.toSet(),
        descriptors().map((d) => d.key).toSet(),
        reason: '矩阵与描述符表分叉 ⇒ 有一类的可用性从来没被评估过',
      );
      for (final r in rows()) {
        final d = descriptors().firstWhere((x) => x.key == r['type']);
        expect(
          r['family'],
          d.family,
          reason: '${r["type"]} 的 family 与原生描述符不一致',
        );
      }
    });

    test('每一列的证据指针都非空且落在允许的取值上', () {
      for (final r in rows()) {
        final type = r['type'] as String;
        final status = r['statusEvidence'] as String;
        final backup = r['backupEvidence'] as String;
        expect(status, isNotEmpty, reason: '$type 状态列空着');
        expect(backup, isNotEmpty, reason: '$type 备份列空着');
        for (final token in [status, backup]) {
          for (final part in token.split('+')) {
            expect(
              const {'widget', 'gate', 'jvm'},
              contains(part),
              reason: '$type 的证据指针 "$part" 不是已定义的种类',
            );
          }
        }
        if (status.contains('widget')) {
          expect(
            familyFiles[r['family']],
            isNotNull,
            reason: '${r["family"]} 族没有登记任何 widget 测试文件，指针是空的',
          );
          for (final f in familyFiles[r['family']]!) {
            expect(
              File('$root/$f').existsSync(),
              isTrue,
              reason: '$type 声称状态由 $f 覆盖，但该文件不存在',
            );
          }
        }
      }
    });

    test('golden 指针：说"有四个场景"就必须真有四个场景键', () {
      final keys = payloadKeys();
      for (final r in rowsWithPayload('golden')) {
        final nativeType = (r['type'] as String).toUpperCase();
        for (final scene in const ['notify', 'sms', 'test', 'call']) {
          expect(
            keys,
            contains('$scene:$nativeType'),
            reason:
                '${r["type"]} 的 payloadEvidence=${r["payloadEvidence"]}，'
                '但 golden 里没有 $scene:$nativeType（快照被改名或删掉过）',
          );
        }
        if ((r['payloadEvidence'] as String).endsWith('bodyOverride')) {
          expect(
            keys,
            contains('body:$nativeType'),
            reason: '${r["type"]} 的实发正文覆写没有 body: 快照 ⇒ 快照虚覆盖了不存在的行为',
          );
        }
      }
    });

    test('jvm 指针：说某个测试类覆盖了载荷，该类就得真的断言载荷构造', () {
      for (final r in rowsWithPayload('jvm:')) {
        // 指针语法：jvm:<类名>[#<必须出现在类里的断言锚>]，缺省锚是 buildPayload(
        final pointer = (r['payloadEvidence'] as String).substring(4);
        final parts = pointer.split('#');
        final cls = parts[0];
        final anchor = parts.length > 1 ? parts[1] : 'buildPayload(';
        final file = File(
          '$root/android/app/src/test/java/com/fnthink/notice/$cls.kt',
        );
        expect(file.existsSync(), isTrue, reason: '${r["type"]} 的证据类 $cls 不存在');
        final src = stripComments(file.readAsStringSync());
        expect(
          src,
          contains(anchor),
          reason: '$cls 存在但没有断言 "$anchor"：载荷列不能算盖章',
        );
      }
    });

    test('未盖章的缺口是收缩棘轮：只许变少，变少要同时改数字', () {
      final pending = rowsWithPayload('todo:');
      final budget = matrix()['pendingPayloadEvidence'] as int;
      expect(
        pending.length,
        lessThanOrEqualTo(budget),
        reason:
            '载荷证据缺口从 $budget 涨到 ${pending.length}：'
            '新增类型要么给证据，要么在 base.md 里说明为什么欠着',
      );
      if (pending.length < budget) {
        fail(
          '缺口少了（$budget → ${pending.length}）：把 JSON 里的 '
          'pendingPayloadEvidence 改成 ${pending.length}，让下一次退化重新变红',
        );
      }
    });

    test('「真发一次」的章必须带日期/构建号，且总数与 ratchet 一致', () {
      final verified = rows()
          .where((r) => (r['realSend'] as Map)['state'] == 'verified')
          .toList();
      final ratchet = matrix()['verifiedRatchet'] as int;
      expect(
        verified.length,
        ratchet,
        reason:
            '盖章数与 verifiedRatchet($ratchet) 不符。涨了要顺手在 base.md 记一句'
            '"谁在哪个构建上验了哪一类"；掉了说明证据被人删了',
      );
      for (final r in verified) {
        final send = r['realSend'] as Map<String, dynamic>;
        for (final k in const ['date', 'build', 'note']) {
          expect(
            (send[k] as String?)?.isNotEmpty ?? false,
            isTrue,
            reason: '${r["type"]} 打了章却缺 $k —— 一个没有出处的 ✅ 比空白更危险',
          );
        }
        expect(
          send['date'] as String,
          matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
          reason: '${r["type"]} 的 date 要写成绝对日期（YYYY-MM-DD）',
        );
      }
      // 把还欠着的项打印出来：交付时必须能看见"哪些没验"，而不是只看见一片绿。
      final all = rows();
      final unwitnessed = all
          .where((r) => (r['realSend'] as Map)['state'] != 'verified')
          .map((r) => r['type'] as String)
          .toList();
      // ignore: avoid_print
      print(
        'T09 待人工盖章（真发一次）：${unwitnessed.join('、')} '
        '（${unwitnessed.length}/${all.length}）',
      );
    });
  });
}
