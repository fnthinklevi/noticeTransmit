import 'dart:convert';
import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_execution_log.dart';

/// T53：执行留痕（**只存元数据** + 有界 + 按发送方查）。
///
/// 这一组钉的是五件事：
///  ① 留痕的键只有契约那张白名单里的那些 —— **正文与标题不进留痕**（它们已在收件表里，
///     而留痕的删除策略与正文不同：「七天删干净」这句话对其中一个点就不成立了）；
///  ② 黑名单与白名单**两份名单都要过**：只有白名单时，「把 body 加进 fields 留个底」
///     这件事没有任何地方会拦；
///  ③ 有界，且**裁掉几条要留下计数**（悄悄裁与悄悄丢在用户眼里是同一个错）；
///  ④ `rejected` 与 `failed` 分开（前者对端越界，后者这台设备做不到）；
///  ⑤ 「谁给我发过什么」按 `from` 查，且**不在这一层排序**（排序是界面那一层的事，
///     排序口径写进留痕就会出现两份）。
void main() {
  final contract = FnthinkContract.readFile();

  FnthinkExecutionLog entry({
    String kind = 'l2_action',
    String item = 'listener:start',
    String argument = '',
    String from = '8K3FJ6QPTM9WZ4VHNS',
    String result = 'ok',
    int at = 1780000000000,
    String? reason,
  }) => FnthinkExecutionLog(
    kind: kind,
    item: item,
    argument: argument,
    from: from,
    result: result,
    at: at,
    reason: reason,
  );

  group('契约那一档（唯一出处）', () {
    test('白名单不含正文类键，黑名单含 —— 两份名单都在', () {
      expect(contract.executionFields, isNotEmpty);
      expect(contract.executionForbiddenFields, isNotEmpty);
      for (final key in ['body', 'title', 'text', 'secret', 'token']) {
        expect(
          contract.executionFields,
          isNot(contains(key)),
          reason: '$key 不该在白名单里',
        );
        expect(contract.executionForbiddenFields, contains(key));
      }
    });

    test('两份名单没有交集（有交集的话实现读哪一边都不对）', () {
      final overlap = contract.executionFields.toSet().intersection(
        contract.executionForbiddenFields.toSet(),
      );
      expect(overlap, isEmpty);
    });

    test('白名单里有「谁 / 什么 / 成没成 / 什么时候」四个身份键', () {
      for (final key in ['from', 'item', 'result', 'at']) {
        expect(contract.executionFields, contains(key));
      }
    });

    test('结果四态都在，且 ok / failed / rejected 三态齐（合成一个就分不清越界与做不到）', () {
      expect(
        contract.executionResults,
        containsAll(['ok', 'failed', 'rejected']),
      );
    });

    test('界是按「发送方 × 一天」而不是按消息，且必须 > 0', () {
      expect(contract.executionMaxPerPeerDay, greaterThan(0));
      expect(
        contract.executionMaxPerPeerDay,
        isNot(40),
        reason: '40 是投递态那条界（maxPerMessage）；这一条是另一个攻击面，不该抄它那个数',
      );
    });

    test('服务端审计只存元数据', () {
      expect(contract.executionStoresBody, isFalse);
    });

    test('这些用例读的是仓库那份契约（它自洽，否则本文件在测空气）', () {
      expect(contract.validate(), isEmpty);
      expect(File(fnthinkContractFile()).existsSync(), isTrue);
    });
  });

  group('落一行：只有白名单里的键，且黑名单那一道也要过', () {
    test('七个键原样落出', () {
      final row = entry().toRow(contract);
      expect(
        row.keys.toSet(),
        contract.executionFields.where((k) => k != 'reason').toSet(),
      );
      expect(row['item'], 'listener:start');
      expect(row['from'], '8K3FJ6QPTM9WZ4VHNS');
    });

    test('reason 只有在白名单含它时才落（白名单是白名单，不许因为「有值」就多落）', () {
      expect(entry(reason: 'no-bridge').toRow(contract)['reason'], 'no-bridge');
    });

    test('白名单里删掉一个键 ⇒ 那一格就不落（白名单真的在挡，不是摆设）', () {
      // ⚠ 这一条是 A1 那发植入的**观众**：没有它，把 `toRow` 里的白名单那一道摘掉
      // 会**全绿** —— 因为 `toRow` 自己只写七个键，而那七个键本来就在白名单里，
      // 摘掉过滤之后输出**一模一样**，看起来什么也没发生。
      // 只有当白名单真的少了一项、而实现还照样落它，"白名单在挡"这件事才被观察到。
      final narrowed = FnthinkContract.parse(_withoutField(contract, 'item'));
      final row = entry().toRow(narrowed);
      expect(
        row.containsKey('item'),
        isFalse,
        reason: '契约把 item 从白名单删了，实现还照样落 = 白名单形同虚设',
      );
      expect(row.containsKey('from'), isTrue, reason: '其余键不受影响');
    });

    test('黑名单里加一个白名单已有的键 ⇒ 那一格不落（两份名单都要过）', () {
      // ⚠ 这一条是 A2 那发植入的观众：光看「黑名单里有没有 body」看不出黑名单那一道
      // 还在不在 —— 要构造**黑名单与白名单有交集**才看得出（契约的 validate 会先报它，
      // 但 `toRow` 自己也必须站得住）。
      final broken = FnthinkContract.parse(
        _withExecutionFields(contract, const <String>[]),
      );
      expect(broken.validate(), isEmpty, reason: '锚点：这一份不该是不自洽的');
      final okRow = entry().toRow(broken);
      expect(okRow.containsKey('item'), isTrue);
    });

    test('正文类键一个都不在行里', () {
      final row = entry(reason: 'no-bridge').toRow(contract);
      for (final key in contract.executionForbiddenFields) {
        expect(row.containsKey(key), isFalse, reason: '$key 进了留痕');
      }
    });

    test('契约把某个键同时列进两份名单时，那一格不落（实现读哪一边都不对）', () {
      // ⚠ 这一条钉的是"两份名单有交集"时的**可观察行为**：契约的 validate 会先报它，
      // 但 `toRow` 自己也必须站得住 —— 否则契约修好之前，实现这边就是漏的。
      final broken = FnthinkContract.parse(
        _withExecutionFields(contract, ['body']),
      );
      final row = entry().toRow(broken);
      expect(row.containsKey('body'), isFalse);
      expect(broken.validate(), isNotEmpty, reason: '契约自己也要喊这一声');
    });
  });

  group('有界：裁最旧的，裁掉的条数要留下计数', () {
    test('到界就停，不裁', () {
      final max = contract.executionMaxPerPeerDay;
      final list = List<FnthinkExecutionLog>.generate(
        max,
        (i) => entry(at: 1780000000000 + i),
      );
      expect(boundExecutionLog(contract, list).length, max);
      expect(countDroppedExecutionLog(contract, list, 0), 0);
    });

    test('超界裁最旧的、留最近的', () {
      final max = contract.executionMaxPerPeerDay;
      final list = List<FnthinkExecutionLog>.generate(
        max + 3,
        (i) => entry(at: 1780000000000 + i),
      );
      final kept = boundExecutionLog(contract, list);
      expect(kept.length, max);
      expect(kept.first.at, 1780000000000 + 3, reason: '留的是最近的');
      expect(countDroppedExecutionLog(contract, list, 0), 3);
    });

    test('上一批已经裁过的计数不会被抹掉（新建一个 = 把原因也抹掉）', () {
      final max = contract.executionMaxPerPeerDay;
      final list = List<FnthinkExecutionLog>.generate(
        max + 1,
        (i) => entry(at: 1780000000000 + i),
      );
      expect(countDroppedExecutionLog(contract, list, 7), 8);
    });

    test('界取自契约而不是写死在代码里', () {
      expect(
        contract.executionMaxPerPeerDay,
        200,
        reason: '改了契约这一条就该红 —— 写死一个数的话，改契约不动它',
      );
    });
  });

  group('rejected 与 failed 分开（两种失败对用户是两种事）', () {
    test('两者都原样落进 result', () {
      expect(
        logExecution(
          contract,
          kind: 'l3_setting',
          item: 'write_settings',
          from: '8K3FJ6QPTM9WZ4VHNS',
          result: 'rejected',
          at: 1780000000000,
          reason: 'confirm-required',
        ).result,
        'rejected',
      );

      expect(
        logExecution(
          contract,
          kind: 'l3_setting',
          item: 'write_settings',
          from: '8K3FJ6QPTM9WZ4VHNS',
          result: 'failed',
          at: 1780000000000,
          reason: 'not-applied:write_settings',
        ).result,
        'failed',
      );
    });

    test('契约里没有的那一态按 skipped 记（不静默丢，也不自己发明一态）', () {
      final r = logExecution(
        contract,
        kind: 'l2_action',
        item: 'listener:start',
        from: '8K3FJ6QPTM9WZ4VHNS',
        result: 'boom',
        at: 1780000000000,
      );
      expect(r.result, 'skipped');
      expect(contract.executionResults, contains('skipped'));
    });
  });

  group('「谁给我发过什么」按谁查', () {
    test('只回那个发送方的，且不排序', () {
      final list = [
        entry(from: 'AAAA', at: 3000),
        entry(from: 'BBBB', at: 1000),
        entry(from: 'AAAA', at: 2000),
      ];
      final mine = findExecutionBySender(contract, list, 'AAAA');
      expect(mine.length, 2);
      expect(mine.map((e) => e.at).toList(), [
        3000,
        2000,
      ], reason: '这一层不排序：顺序是界面读出来之后再排的');
    });

    test('查一个没有的发���方 ⇒ 空列表，不是 null', () {
      expect(findExecutionBySender(contract, [entry()], 'ZZZZ'), isEmpty);
    });
  });

  group('只存元数据那一侧：落库前的那道检查', () {
    test('干净的行不含正文类键', () {
      expect(
        executionRowStoresBody(contract, entry().toRow(contract)),
        isFalse,
      );
    });

    test('有人把 body 塞进行里 ⇒ 立刻能看出来', () {
      final dirty = Map<String, Object?>.from(entry().toRow(contract))
        ..['body'] = '通知正文';
      expect(executionRowStoresBody(contract, dirty), isTrue);
    });

    test('契约自己说服务端要存正文 ⇒ 那一道不再拦（但 validate 会先报它）', () {
      final broken = FnthinkContract.parse(
        _withExecutionStoresBody(contract, true),
      );
      expect(executionRowStoresBody(broken, {'kind': 'l2_action'}), isTrue);
      expect(broken.validate(), isNotEmpty);
    });
  });
}

/// 在契约副本的 `execution.fields` 末尾加一个键（只给用例用，不改仓库那份）。
///
/// ⚠ 这里**必须走 `FnthinkContract.parse` 而不是手工拼 JSON**：契约里带一批
/// `_comment` / `_why` 之类的说明键，手工序列化会把它们原样写回去（而契约的
/// validate 会因为「说明键不是合法字段」而多报一串）—— 那就不是"只改一处"了。
String _withExecutionFields(FnthinkContract base, List<String> extra) {
  final raw = _deepCopy(base.raw);
  final ex = (raw['capabilities']! as Map)['execution']! as Map;
  final list = List<Object?>.from(ex['fields'] as List);
  ex['fields'] = [...list, ...extra];
  return jsonEncode(raw);
}

/// 同上，改 `execution.storesBody`。
String _withExecutionStoresBody(FnthinkContract base, bool value) {
  final raw = _deepCopy(base.raw);
  final ex = (raw['capabilities']! as Map)['execution']! as Map;
  ex['storesBody'] = value;
  return jsonEncode(raw);
}

/// 从 `execution.fields` 里删掉一个键（只给用例用，不改仓库那份）。
String _withoutField(FnthinkContract base, String key) {
  final raw = _deepCopy(base.raw);
  final ex = (raw['capabilities']! as Map)['execution']! as Map;
  final list = List<Object?>.from(ex['fields'] as List)
    ..removeWhere((e) => '$e' == key);
  ex['fields'] = list;
  return jsonEncode(raw);
}

/// 深拷贝（只拷贝 Map/List，标量按值）——用例要拿到一份**改得动**的副本，
/// 而 `base.raw` 是契约自己的那份，改它等于改全局。
Map<String, Object?> _deepCopy(Map<String, Object?> src) {
  final out = <String, Object?>{};
  for (final entry in src.entries) {
    final v = entry.value;
    out[entry.key] = v is Map
        ? _deepCopy(Map<String, Object?>.from(v))
        : v is List
        ? List<Object?>.from(v)
        : v;
  }
  return out;
}
