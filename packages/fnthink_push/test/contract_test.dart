import 'dart:convert';
import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:test/test.dart';

/// 双端契约测试的 **Dart 这一半**（T71）。服务端那一半在
/// `server/test/fnthink-contract.test.js`，两边读的是同一个 `protocol/fnthink-v1.json`。
///
/// 为什么不只测"文件能解析"：那等于只检查了文件存在。这里测的是三件会静默生效的事：
/// ① 版本声明一致（名字里的 v 号、`contractVersion`、本包实现的 major 三者必须相等）；
/// ② 契约表**自身**自洽（`validate()` 为空）；
/// ③ 把任何一条红线改反，`validate()` 必须报出**那一条**（下面的反证组）。
void main() {
  late FnthinkContract c;

  setUp(() => c = FnthinkContract.readFile());

  group('版本声明', () {
    test('protocol 名、contractVersion、本包 major 三者一致', () {
      expect(c.protocol, 'fnthink-v1');
      expect(c.contractVersion, fnthinkProtocolMajor);
      expect(c.unsupportedReason(), isNull);
    });

    test('名字里的 v 号与 contractVersion 不一致 ⇒ 立刻判不兼容', () {
      final broken = FnthinkContract.parse(
        jsonEncode({...c.raw, 'protocol': 'fnthink-v2', 'contractVersion': 2}),
      );
      expect(
        broken.unsupportedReason(),
        contains('本包只实现到 v$fnthinkProtocolMajor'),
      );
    });

    test('protocol 名形状不对也判不兼容（不是回落到"能读"）', () {
      final broken = FnthinkContract.parse(
        jsonEncode({...c.raw, 'protocol': 'fnthinkV1'}),
      );
      expect(broken.unsupportedReason(), contains('fnthink-v<N>'));
    });
  });

  group('取值层', () {
    test('签名规范化的字段顺序逐字段钉住（换序就是换签名）', () {
      expect(c.canonicalOrder, [
        'version',
        'type',
        'target',
        'ts',
        'nonce',
        'body',
      ]);
      expect(c.str(const ['signature', 'timestampSource']), 'serverTime');
    });

    test('同步状态码表与"同一形状"的声明', () {
      expect(c.statusCodes['queued'], 202);
      expect(c.statusCodes['unauthorized'], 401);
      expect(c.statusCodes['forbidden'], 403);
      expect(c.statusCodes['duplicate'], 409);
      expect(c.statusCodes['expired'], 410);
      expect(c.statusCodes['rateLimited'], 429);
      expect(
        c.indistinguishable,
        containsAll(['unauthorized', 'notFoundEndpoint']),
      );
    });

    test('在线阈值 = 3 × 拉取间隔，且提频必须比常规更短', () {
      expect(c.onlineThresholdSeconds(), 60, reason: '默认 20s × 3');
      expect(c.onlineThresholdSeconds(pollIntervalSeconds: 30), 90);
      expect(
        c.intOf(const ['presence', 'burstWhenPending', 'intervalSeconds']),
        lessThan(c.intOf(const ['presence', 'pollIntervalSeconds', 'min'])!),
      );
    });

    test('字段容错：首项是规范名，title 与 body 的别名不相交', () {
      expect(c.aliases['title'], ['title', 'message', 'text', 'msg']);
      expect(c.aliases['body'], ['body', 'content', 'description']);
      expect(
        c.aliases['title']!.toSet().intersection(c.aliases['body']!.toSet()),
        isEmpty,
      );
    });
  });

  test('契约表自洽（validate 必须为空；不空就把全部问题打出来）', () {
    expect(c.validate(), isEmpty);
  });

  test('服务端那一半读的是同一个文件、同一个 major', () {
    // 跨语言守卫：两侧各读各的 JSON 没问题，但如果 JS 指向了另一份文件或另写一个
    // SUPPORTED_MAJOR，"双端一致"就只剩名字了。
    final contractFile = File(fnthinkContractFile());
    final js = File(
      '${contractFile.parent.parent.path}/server/lib/fnthink/contract.js',
    ).readAsStringSync();
    expect(js, contains('protocol/fnthink-v1.json'));
    expect(js, contains('SUPPORTED_MAJOR = $fnthinkProtocolMajor'));
    expect(js, isNot(contains('readFileSync(\'protocol/fnthink-v2')));
  });

  // ── 反证：把红线一条条改反，validate() 必须报出**那一条** ──
  group('反证（契约表被改坏时必须报）', () {
    FnthinkContract mutate(void Function(Map<String, Object?> raw) change) {
      final copy = jsonDecode(jsonEncode(c.raw)) as Map<String, Object?>;
      change(copy);
      return FnthinkContract(copy);
    }

    void expectProblem(FnthinkContract broken, String needle, String why) {
      final problems = broken.validate();
      expect(
        problems.any((p) => p.contains(needle)),
        isTrue,
        reason: '$why ⇒ 期望报出「$needle」，实际 $problems',
      );
    }

    test('端点被允许产 L3 ⇒ 报', () {
      final broken = mutate((raw) {
        (raw['capabilities'] as Map<String, Object?>)['endpointMaxLevel'] =
            'L3';
      });
      expectProblem(broken, 'endpointMaxLevel', '端点只能产 L1 是红线');
    });

    test('私钥改成可导出 ⇒ 报', () {
      final broken = mutate((raw) {
        ((raw['identity'] as Map)['identityKey']
                as Map)['privateKeyExportable'] =
            true;
      });
      expectProblem(broken, '不可导出', '私钥进 AndroidKeyStore 不可导出是红线');
    });

    test('端点长期口令比配对口令还短 ⇒ 报（长期凭证要更长，不是更短）', () {
      final broken = mutate((raw) {
        ((raw['identity'] as Map)['endpointSecret'] as Map)['length'] = 12;
      });
      expectProblem(broken, 'endpointSecret', '配反方向的安全参数');
    });

    test('正文在 expired 时不删 ⇒ 报', () {
      final broken = mutate((raw) {
        (raw['retention'] as Map<String, Object?>)['deleteBodyOn'] = [
          'delivered',
        ];
      });
      expectProblem(broken, 'deleteBodyOn 必须包含 expired', '不无谓留存');
    });

    test('口令错误与端点不存在不再同形 ⇒ 报', () {
      final broken = mutate((raw) {
        (raw['statusCodes'] as Map<String, Object?>)['indistinguishable'] = [
          'unauthorized',
        ];
      });
      expectProblem(broken, 'indistinguishable', '否则返回码可用来枚举端点');
    });

    test('开始信任本机时钟 ⇒ 报', () {
      final broken = mutate((raw) {
        (raw['signature'] as Map<String, Object?>)['trustLocalClock'] = true;
      });
      expectProblem(broken, 'trustLocalClock', '时间判定必须用服务端时间');
    });

    test('L3 允许免确认 ⇒ 报', () {
      final broken = mutate((raw) {
        ((raw['capabilities'] as Map)['l3'] as Map)['allowSkipConfirm'] = true;
      });
      expectProblem(broken, 'allowSkipConfirm', 'L3 每次必须确认');
    });

    test('未知 action 改成放行 ⇒ 报', () {
      final broken = mutate((raw) {
        ((raw['capabilities'] as Map)['l3'] as Map)['unknownAction'] = 'allow';
      });
      expectProblem(broken, 'unknownAction', '两边不认识的 action 一律拒');
    });

    test('提频间隔不比常规更短 ⇒ 报（"pending 时提频"是假的）', () {
      final broken = mutate((raw) {
        ((raw['presence'] as Map)['burstWhenPending']
                as Map)['intervalSeconds'] =
            30;
      });
      expectProblem(broken, 'burstWhenPending.intervalSeconds', '提频必须真的更快');
    });

    test('口令改成可复用 ⇒ 报', () {
      final broken = mutate((raw) {
        ((raw['identity'] as Map)['pairingCode'] as Map)['singleUse'] = false;
      });
      expectProblem(broken, '一次性的', '配对口令配对即消耗');
    });

    test('备用补推与排队补发可以并存 ⇒ 报（会重复提醒两次）', () {
      final broken = mutate((raw) {
        (raw['waitingOnline'] as Map<String, Object?>)['mutuallyExclusive'] =
            false;
      });
      expectProblem(broken, 'mutuallyExclusive', '两条路径不可并存');
    });
  });
}
