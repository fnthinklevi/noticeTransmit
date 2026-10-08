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

    test('在线阈值 = 3 × 拉取间隔，且提频不许比常态下界更慢', () {
      expect(c.onlineThresholdSeconds(), 60, reason: '默认 20s × 3');
      expect(c.onlineThresholdSeconds(pollIntervalSeconds: 30), 90);
      expect(
        c.intOf(const ['presence', 'burstWhenPending', 'intervalSeconds']),
        // T88 之后是**不大于**而不是小于：常态下界被压到 5s、与提频档同值，严格小于会让
        // 这份契约自己判红。这一档真正要拦的是"提频比常态还慢"那个倒挂。
        lessThanOrEqualTo(
          c.intOf(const ['presence', 'pollIntervalSeconds', 'min'])!,
        ),
        reason: '相等是定稿的结果（下界 5s == 提频 5s），比它大才是自相矛盾',
      );
    });

    test('收取间隔的范围只有一份作者：契约的 min/max/default（T88）', () {
      final range = c.pollIntervalRange;
      expect(
        range,
        (min: 5, max: 60),
        reason:
            '维护者 2026-10-01 定稿：下界 5s（服务端额度本来就是按提频 5s 推的）、'
            '上界 60s（再长就不是慢，是在线状态失真）',
      );
      expect(range.min, lessThanOrEqualTo(c.pollIntervalSeconds));
      expect(c.pollIntervalSeconds, lessThanOrEqualTo(range.max));
      // 边界本身：两端都在范围内（悄悄夹掉的那一档必须由调用方自己判红）
      expect(c.checkedPollIntervalSeconds(range.min), range.min);
      expect(c.checkedPollIntervalSeconds(range.max), range.max);
      expect(
        () => c.checkedPollIntervalSeconds(range.min - 1),
        throwsStateError,
        reason: '比下界还快 ⇒ 那一档会把按设备地址推的额度打穿，必须报而不是夹',
      );
      expect(
        () => c.checkedPollIntervalSeconds(range.max + 1),
        throwsStateError,
      );
      // 没选过 = 用契约 default；选过 = 用那一档（两处读数都从这里走）
      expect(c.effectivePollIntervalSeconds(null), c.pollIntervalSeconds);
      expect(c.effectivePollIntervalSeconds(45), 45);
      expect(
        c.validate(),
        isEmpty,
        reason: '定稿那对数字必须让整张表自洽（ackDeadline 已与 3×max 一起抬到 180s）',
      );
    });

    test('字段容错：首项是规范名，title 与 body 的别名不相交', () {
      expect(c.aliases['title'], [
        'title',
        'subject',
        'message',
        'text',
        'msg',
      ]);
      expect(
        c.aliases['body'],
        const <String>[
          'body',
          'content',
          'description',
          'text.content',
          'content.text',
          'data.content',
        ],
        reason:
            'T99：钉钉/企微的正文在 text.content、飞书 legacy 在 content.text —— '
            '别名表是这份契约的一部分，谁把嵌一层的那几档删了，这里就要问一句',
      );
      expect(
        c.aliases['title']!.toSet().intersection(c.aliases['body']!.toSet()),
        isEmpty,
      );
      // 点分路径从今天起是合法别名，那就得钉住形状：只允许"名.名"一层，
      // 空段（`text.`、`.content`）与三层以上都是写错了 —— 服务端只会把它当成
      // 一个取不到的键，静默。
      for (final entry in c.aliases.entries) {
        for (final alias in entry.value) {
          expect(
            RegExp(
              r'^[a-z][a-zA-Z0-9]*(\.[a-z][a-zA-Z0-9]*)?$',
            ).hasMatch(alias),
            isTrue,
            reason: '${entry.key} 的别名 "$alias" 不是"名"或"名.名"的形状',
          );
        }
      }
    });

    test('poll 每条消息的名单：主键与归属都在，且每个名字都投影得出来', () {
      expect(c.pollMessageFields, containsAll(['messageId', 'sender']));
      expect(c.pollMessageFields.toSet().length, c.pollMessageFields.length);
      // T105 片②：`sentAt`（服务端受理那一刻）也在可投影面里 ——
      // 它不是 `state`/`attempts`/`queuedAt` 那三个名字（投递状态的账），而是一个不会再变的时刻。
      final projectable = {
        'messageId',
        'type',
        'item',
        'sender',
        'sentAt',
        ...c.aliases.keys,
      };
      expect(
        projectable.containsAll(c.pollMessageFields),
        isTrue,
        reason: '可投影面只有 $projectable，名单里多一个名字就是让服务端回一个空值',
      );
    });

    test('双域名都在 fnthink 的注册域下（钉的是"归属"，不是整串主机名）', () {
      // 为什么这样钉：大陆那条曾经写成 `pushfnthink.com`（少一个点，是**另一个域**），
      // 而契约里这行此前没人读也没人校验，错串就一直挂着。断言 endsWith('.fnthink.<tld>')
      // 既能抓住这种"少一个点"的写法（它落到了别人的注册域上），又不必把 push 这个
      // 子域标签写死 —— 换子域是实现细节，换注册域是新买了一个域名。
      final endpoints = c.map(const ['transport', 'endpoints'])!;
      expect(endpoints['international'], isNotEmpty);
      expect(endpoints['mainland'], isNotEmpty);
      expect(
        endpoints['international'].toString().endsWith('.fnthink.top'),
        isTrue,
        reason: '国际域名必须挂在 fnthink.top 下，实际 ${endpoints['international']}',
      );
      expect(
        endpoints['mainland'].toString().endsWith('.fnthink.com'),
        isTrue,
        reason: '大陆域名必须挂在 fnthink.com 下，实际 ${endpoints['mainland']}',
      );
    });
  });

  group('答复配对请求时能答应到哪一档（T42 第五片）', () {
    test('封顶是从契约那条**路径**读出来的，不是代码里写死的一档', () {
      expect(c.pairConfirmLevelCeiling, 'L2');
      expect(
        c.pairConfirmLevelCeiling,
        c.str(const ['pairing', 'maxRequestableLevelFromPairing']),
        reason:
            '服务端 authorizePairConfirm 读的是同一条路径：两端共用一个旋钮。'
            '这里写死 L2 的话，改契约不会报错，只会变成"本机发得出去、服务端整条拒"',
      );
      expect(c.capabilityLevels, contains(c.pairConfirmLevelCeiling));
    });

    test('请求不高于封顶 ⇒ 原样答应；高于封顶 ⇒ 压到封顶', () {
      expect(c.grantableLevel('L1'), 'L1');
      expect(c.grantableLevel('L2'), 'L2');
      expect(
        c.grantableLevel('L3'),
        'L2',
        reason:
            'L3 要在这台设备上本地确认（锁屏/生物认证），远程这一发给不出去；'
            '原样发过去只换回一句与"口令错"同形的 403',
      );
    });

    test('词表里没有的档位 ⇒ null（调用方据此**不发**，而不是猜一个）', () {
      expect(c.grantableLevel('L9'), isNull);
      expect(c.grantableLevel(''), isNull);
      expect(c.grantableLevel('l1'), isNull, reason: '档位词是大小写敏感的，不是"差不多就行"');
    });

    test('契约没写那条路径 ⇒ 抛，不补一个默认档位', () {
      final copy = jsonDecode(jsonEncode(c.raw)) as Map<String, Object?>;
      ((copy['clientEvents']! as Map)['pairConfirm']! as Map).remove(
        'levelCeilingFrom',
      );
      final broken = FnthinkContract(copy);
      expect(
        () => broken.grantableLevel('L1'),
        throwsStateError,
        reason: '补一个默认档位 = 在代码里发明一种授权',
      );
    });

    test('路径取到的不是档位 ⇒ 抛（那道闸在读一个不存在的值）', () {
      final copy = jsonDecode(jsonEncode(c.raw)) as Map<String, Object?>;
      (copy['pairing']! as Map)['maxRequestableLevelFromPairing'] = 'L9';
      final broken = FnthinkContract(copy);
      expect(() => broken.pairConfirmLevelCeiling, throwsStateError);
    });
  });

  group('B 侧请求配对时够得着哪几档（#176 片3）', () {
    test('只列出到封顶为止的那几档，顺序照 capabilities.levels', () {
      expect(
        c.pairRequestableLevels,
        ['L1', 'L2'],
        reason:
            'L3 要在那台设备本地确认，远程请求超档是整条拒（level-too-high），'
            '把它摆进选项等于让用户点一句必被拒的话',
      );
    });

    test('封顶从 clientEvents.pair.levelCeilingFrom 那条**路径**读，不是写死的档位', () {
      final copy = jsonDecode(jsonEncode(c.raw)) as Map<String, Object?>;
      (copy['pairing']! as Map)['maxRequestableLevelFromPairing'] = 'L1';
      final lowered = FnthinkContract(copy);
      expect(lowered.pairRequestableLevels, [
        'L1',
      ], reason: '把契约那一档改了界面就得跟着变；写死 L2 时这条用例当场绿不了');
    });

    test('读的是 pair 那一条路径，不是 pairConfirm 的（两条各管一头）', () {
      final copy = jsonDecode(jsonEncode(c.raw)) as Map<String, Object?>;
      ((copy['clientEvents']! as Map)['pair']! as Map)['levelCeilingFrom'] =
          'capabilities.endpointMaxLevel';
      final moved = FnthinkContract(copy);
      expect(
        moved.pairRequestableLevels,
        ['L1'],
        reason:
            '这一条走的是 `pair.levelCeilingFrom`；若实现图省事复用 pairConfirm 的路径，'
            '这里改一边不会有任何反应，而两端各有上限时界面就在摆一发必拒的请求',
      );
      expect(
        moved.pairConfirmLevelCeiling,
        c.pairConfirmLevelCeiling,
        reason: '同一份改动能把两条路径分开：答复那一侧不该跟着动',
      );
    });

    test('路径缺了 / 取到的不是词表里的一档 ⇒ 抛，不补默认档位', () {
      final noPath = jsonDecode(jsonEncode(c.raw)) as Map<String, Object?>;
      ((noPath['clientEvents']! as Map)['pair']! as Map).remove(
        'levelCeilingFrom',
      );
      expect(
        () => FnthinkContract(noPath).pairRequestableLevels,
        throwsStateError,
      );

      final bogus = jsonDecode(jsonEncode(c.raw)) as Map<String, Object?>;
      ((bogus['clientEvents']! as Map)['pair']! as Map)['levelCeilingFrom'] =
          'pairing.nope';
      expect(
        () => FnthinkContract(bogus).pairRequestableLevels,
        throwsStateError,
        reason: '取不到值就补一个默认档位 = 在代码里发明一种授权',
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

    Map<String, Object?> remoteOf(Map<String, Object?> raw) {
      final caps = raw['capabilities'] as Map<String, Object?>;
      return caps['remoteExecution'] as Map<String, Object?>;
    }

    // ── 远程执行（片1：五组条款，判据与用例成对）──

    test('远程执行：L2/L3 的来源只许幻念推送，且每一档都要有渠道', () {
      for (final push in ['L2', 'L3']) {
        final broken = mutate((raw) {
          final remote = remoteOf(raw);
          final sources = remote['sources'] as Map<String, Object?>;
          sources[push] = ['fnthink', 'webhook'];
        });
        expectProblem(broken, 'sources.$push', '$push 只许幻念推送');
      }
      final empty = mutate((raw) {
        final remote = remoteOf(raw);
        final sources = remote['sources'] as Map<String, Object?>;
        sources['L1'] = <String>[];
      });
      expectProblem(empty, 'sources.L1', '一档没有任何渠道，等于把它禁掉');
    });

    test('远程执行：凭据是 L2 可选、L3 必填（写反了就是安全漏）', () {
      final broken = mutate((raw) {
        final auth = remoteOf(raw)['auth'] as Map<String, Object?>;
        auth['l2Requires'] = true;
      });
      expectProblem(broken, 'L2 可选、L3 必填', '写反就是漏');
    });

    test('远程执行：auth.modes 少了 totp ⇒ 报', () {
      final broken = mutate((raw) {
        final auth = remoteOf(raw)['auth'] as Map<String, Object?>;
        auth['modes'] = ['key'];
      });
      expectProblem(broken, 'auth.modes', 'L3 二者其一即可用，少一种就少一条路');
    });

    test('远程执行：延时默认值超出上下限 ⇒ 报', () {
      final broken = mutate((raw) {
        final delay = remoteOf(raw)['delay'] as Map<String, Object?>;
        delay['defaultSeconds'] = 120;
      });
      expectProblem(broken, '默认值要落在', '默认值必须在窗口内');
    });

    test('远程执行：超时语义不是 execute ⇒ 报（维护者定：超时默认执行）', () {
      final broken = mutate((raw) {
        final delay = remoteOf(raw)['delay'] as Map<String, Object?>;
        delay['onTimeout'] = 'notify';
      });
      expectProblem(broken, '超时语义必须是 execute', '改掉它等于改了模型');
    });

    test('远程执行：状态词表少了 cancelled ⇒ 报（撤销那一档没了）', () {
      final broken = mutate((raw) {
        remoteOf(raw)['states'] = ['pending', 'executing', 'done', 'failed'];
      });
      expectProblem(broken, 'executing', '两段回执与撤销都靠这张表');
    });

    test('远程执行：回执词不在 receipts 词表里 ⇒ 报（不许另造一份词表）', () {
      final broken = mutate((raw) {
        final receipts = remoteOf(raw)['receipts'] as Map<String, Object?>;
        receipts['finished'] = 'finished_ok';
      });
      expectProblem(broken, 'receipts 词表里的词', '第二份词表就是漂移的起点');
    });

    test('L3 的闸不是 cancelableDelay ⇒ 报（改形不改内核要有落点）', () {
      final broken = mutate((raw) {
        final caps = raw['capabilities'] as Map<String, Object?>;
        final l3 = caps['l3'] as Map<String, Object?>;
        l3['confirmForm'] = 'dialog';
      });
      expectProblem(broken, 'cancelableDelay', '闸的形式改了，模型就断了');
    });

    test('远程执行：auth.keyMinLength 缺了或不是正整数 ⇒ 报（长度是安全参数）', () {
      for (final bad in [null, 0, -1]) {
        final broken = mutate((raw) {
          final auth = remoteOf(raw)['auth'] as Map<String, Object?>;
          if (bad == null) {
            auth.remove('keyMinLength');
          } else {
            auth['keyMinLength'] = bad;
          }
        });
        expectProblem(broken, 'keyMinLength', '补一个默认值就是代码替协议决定安全强度');
      }
    });

    test('远程执行：totpDigits 与 totpPeriodSeconds 少一个 ⇒ 报', () {
      for (final key in ['totpDigits', 'totpPeriodSeconds']) {
        final broken = mutate((raw) {
          (remoteOf(raw)['auth'] as Map<String, Object?>).remove(key);
        });
        expectProblem(broken, 'totpDigits', '位数与步长只有一个时，另一半的默认值就是代码在发明协议');
      }
      final zero = mutate((raw) {
        (remoteOf(raw)['auth'] as Map<String, Object?>)['totpPeriodSeconds'] =
            0;
      });
      expectProblem(zero, 'totpPeriodSeconds', '步长 0 秒 = 校验器给什么码都过');
    });

    test('远程执行：onMissingOrWrong 不是 reject ⇒ 报（安全方向不许反）', () {
      final broken = mutate((raw) {
        (remoteOf(raw)['auth'] as Map<String, Object?>)['onMissingOrWrong'] =
            'execute';
      });
      expectProblem(broken, 'onMissingOrWrong', '改成 execute 就是把"没带凭据也执行"写进协议');
    });

    test('远程执行：delay 的 min/max 缺一个 ⇒ 报；区间反了也报（走同一条）', () {
      // ⚠ **只有一条判据管延时范围**：min 与 max 都必须存在且 min 非负；而"区间反了"
      //   （min > max）**不再另立判据** —— 那时 default 必然掉出区间，"默认值要落在"
      //   已经必然红，所以次序判据是**永远不可观察**的（R10 那发植入摘掉它之后全绿）。
      //   下面第一条用例据此改钉"删掉 min"，点名才是本条判据自己的。
      final missing = mutate((raw) {
        final delay = remoteOf(raw)['delay'] as Map<String, Object?>;
        // ⚠ **default 必须一起搬进区间**：minSeconds 缺了之后读口会给 -1，
        //   而"默认值要落在"那条判据走的是**同一批 getter**，所以它也会红 ——
        //   那就是 R10 零失败的真正原因（相邻判据替它响了），不是本条没被覆盖。
        delay['defaultSeconds'] = 0;
        delay['maxSeconds'] = 60;
        delay.remove('minSeconds');
      });
      // 点名本条判据自己的那句，而不是"有没有报出什么问题"：
      // "哪一条报了"才是这条用例要断的东西。
      expect(
        missing.validate().where((p) => p.contains('都必须存在且 min 非负')),
        isNotEmpty,
        reason: 'min 缺了、default 已搬进 [?,60] ⇒ 只有本条判据能报它',
      );
      final reversed = mutate((raw) {
        final delay = remoteOf(raw)['delay'] as Map<String, Object?>;
        delay['minSeconds'] = 90;
        delay['maxSeconds'] = 30;
      });
      expectProblem(reversed, '区间反了', '范围反了 = 界面上那根滑杆不存在');
    });

    test('远程执行：localTriggerReceipt 换成自造的词 ⇒ 报', () {
      final broken = mutate((raw) {
        remoteOf(raw)['localTriggerReceipt'] = 'local_none';
      });
      expectProblem(broken, 'localTriggerReceipt', '另造一个回执词 = 第二份词表');
    });

    test('远程执行：localTriggerSource 换成不在来源词表里的名字 ⇒ 报', () {
      // ⚠ 这一条是片3c 补那条判据的**反证**：摘掉「必须在 sources.L1 里」那一半之后，
      // 本用例必须红。它此前不存在 ⇒ 那条判据属于"写了但没人证明它有效"。
      // 症状若不钉住就是最坏的一种：写一个不存在的来源名，判据绿着，
      // 而"本机那一路按契约不回执"永远不成立（永远没有一条指令来自那个名字）。
      final broken = mutate((raw) {
        remoteOf(raw)['localTriggerSource'] = 'somewhere_else';
      });
      expectProblem(
        broken,
        'localTriggerSource',
        '来源名不在 L1 词表里 ⇒ 代码判不出本机那一路，回执会照发',
      );
      expectProblem(
        mutate((raw) {
          remoteOf(raw)['localTriggerSource'] = '';
        }),
        'localTriggerSource',
        '来源名留空 = 判据不成立时最可能的写法（照抄那一行会写空串）',
      );
      // 正向：契约里这一行与 L1 的词表一致（否则上面两条红而这一条绿 = 判据指错了地方）。
      expect(
        mutate(
          (raw) {},
        ).validate().where((p) => p.contains('localTriggerSource')),
        isEmpty,
      );
    });

    test('远程执行：localTriggerReceipt 只能是 none 或 receipts 词表里的词', () {
      // 「none」是刻意不在 receipts 词表里的那个哨兵：它说的不是"回哪一个回执"，
      // 而是"这一路上没有任何人可以回"（本机白名单触发的那一路）。
      expect(c.remoteExecutionLocalTriggerReceipt, 'none');
      expect(
        c.receipts,
        isNot(contains('none')),
        reason: '把 none 塞进 receipts 等于为一件不存在的事造一个对外形状',
      );
      expect(
        mutate((raw) {
          remoteOf(raw)['localTriggerReceipt'] = 'delivered';
        }).validate(),
        isEmpty,
        reason: '真回执词当然收',
      );
    });

    test('正向：仓库这份契约的远程执行条款读出来就是维护者定的那套', () {
      expect(c.remoteExecutionSourcesFor('L1'), [
        'fnthink',
        'localNotificationWhitelist',
      ]);
      expect(c.remoteExecutionSourcesFor('L2'), ['fnthink']);
      expect(c.remoteExecutionSourcesFor('L3'), ['fnthink']);
      expect(c.remoteExecutionAuthModes, ['key', 'totp']);
      expect(c.remoteExecutionL2RequiresAuth, isFalse);
      expect(c.remoteExecutionL3RequiresAuth, isTrue);
      expect(c.remoteExecutionDelayDefaultSeconds, 10);
      expect(c.remoteExecutionDelayMinSeconds, 0);
      expect(c.remoteExecutionDelayMaxSeconds, 60);
      expect(c.remoteExecutionOnTimeout, 'execute');
      expect(c.remoteExecutionPresenceAffectsTiming, isFalse);
      expect(c.remoteExecutionStates.contains('cancelled'), isTrue);
      expect(c.remoteExecutionReceipts, {
        'started': 'executing',
        'finished': 'execution_done',
      });
      expect(c.l3ConfirmForm, 'cancelableDelay');
    });

    test('端点被允许产 L3 ⇒ 报', () {
      final broken = mutate((raw) {
        (raw['capabilities'] as Map<String, Object?>)['endpointMaxLevel'] =
            'L3';
      });
      expectProblem(broken, 'endpointMaxLevel', '端点只能产 L1 是红线');
    });

    test('presence 少了 unknown 那一态 ⇒ 报（"从未配过"会被显示成"掉线"）', () {
      final broken = mutate((raw) {
        (raw['presence'] as Map)['states'] = ['online', 'offline'];
      });
      expectProblem(broken, 'presence.states', '三态缺一态就是让显示层去猜');
    });

    test('把 revoked 也加进"允许投递"的白名单 ⇒ 报（吊销了还能收到，等于没吊销）', () {
      final broken = mutate((raw) {
        ((raw['revocation'] as Map)['deliveryAllowedStatuses'] as List).add(
          'revoked',
        );
      });
      expectProblem(broken, 'deliveryAllowedStatuses', '白名单只能有 active');
    });

    test('白名单里写一个状态表里没有的名字 ⇒ 报（打错字的方向必须是"判不过"）', () {
      final broken = mutate((raw) {
        (raw['revocation'] as Map)['deliveryAllowedStatuses'] = ['actve'];
      });
      expectProblem(broken, '不在 deviceStatuses', '状态名要拼错就先报错');
    });

    test('吊销顺手清历史 ⇒ 报（破坏性动作不塞进安全动作的副作用里）', () {
      final broken = mutate((raw) {
        (raw['revocation'] as Map)['dataNeverDeletedByRevoke'] = false;
      });
      expectProblem(broken, 'dataNeverDeletedByRevoke', '吊销只停投递，历史要单独一次显式操作');
    });

    test('重建身份不再让所有发送方重配 ⇒ 报（换手机不能悄悄续上旧信任）', () {
      final broken = mutate((raw) {
        (raw['revocation'] as Map)['identityRebuildInvalidatesAllPeers'] =
            false;
      });
      expectProblem(
        broken,
        'identityRebuildInvalidatesAllPeers',
        '重建身份必须作废全部配对',
      );
    });

    test('又冒出第二个 skew 数值键（T71 那个 clockSkewSeconds 复活）⇒ 报', () {
      // 这一条守的是"删掉的键别再回来"：两处数值并排，改一处忘一处不会报错，
      // 只会表现成某一端偶尔把合法包判成过期。
      final broken = mutate((raw) {
        (raw['signature'] as Map)['clockSkewSeconds'] = 120;
      });
      expectProblem(broken, 'skew 类的键', '一根轴只许一个 skew 旋钮');
    });

    test('认不出的 type 改成"先收下" ⇒ 报（词表的解释权不许交给对端）', () {
      final broken = mutate((raw) {
        (raw['capabilities'] as Map)['unknownMessageType'] = 'accept';
      });
      expectProblem(broken, 'unknownMessageType', '未知 type 一律拒是红线');
    });

    test('缺省授权档放宽到 L3 ⇒ 报（查不到清单时必须 fail-closed）', () {
      final broken = mutate((raw) {
        ((raw['capabilities'] as Map)['grantDefaults'] as Map)['maxLevel'] =
            'L3';
      });
      expectProblem(broken, 'grantDefaults', '缺省只能是最窄那档');
    });

    test('逐条勾选的起始档写成契约里没有的档 ⇒ 报', () {
      final broken = mutate((raw) {
        (raw['capabilities'] as Map)['itemRequiredFromLevel'] = 'L0';
      });
      expectProblem(broken, 'itemRequiredFromLevel', '那一档必须真的存在于 levels');
    });

    test('某个 type 不写 minLevel ⇒ 报（空串会被判成"级别不存在"而静默放行到最窄档）', () {
      final broken = mutate((raw) {
        ((raw['capabilities'] as Map)['messageTypes'] as Map)['action'] = {
          '_comment': '忘了写 minLevel',
        };
      });
      expectProblem(broken, 'minLevel', '每项都要写明最低级别');
    });

    test('把 notice 整档删掉 ⇒ 报（那一档没有任何 type 能进 = 死档）', () {
      final broken = mutate((raw) {
        ((raw['capabilities'] as Map)['messageTypes'] as Map).remove('notice');
      });
      expectProblem(broken, '没有任何 type 能进', 'L1 变成发不出东西的死档');
    });

    // ── T50：L2 动作词表 ──
    // ⚠ 这一组是 A10 那条反证的**前提**。之前「l2.actions 不能为空」这一判
    // **不可单独观察**：没有任何用例把表清空过，于是把判据改成恒真后全套照样绿。
    // 补了下面这几条之后，「表空了却不报」这件事才有人喊。
    test('L2 动作表清空 ⇒ 报（这一档没有任何动作 = messageTypes.action 指着空处）', () {
      final broken = mutate((raw) {
        ((raw['capabilities'] as Map)['l2'] as Map)['actions'] = <String>[];
      });
      expectProblem(broken, 'l2.actions 不能为空', '空表与「这一档没有任何动作」在下游读起来一样');
    });

    test('L2 动作表整段删掉 ⇒ 报（不是"读起来空"，是那一档根本不存在）', () {
      final broken = mutate((raw) {
        (raw['capabilities'] as Map).remove('l2');
      });
      expectProblem(broken, 'l2.actions 不能为空', '整段删掉与清空是同一个后果，不能只有后者报错');
    });

    test('L2 动作表里有重复项 ⇒ 报（两端按位置读，重复会让"第几个动作"两处不同）', () {
      final broken = mutate((raw) {
        final l2 = (raw['capabilities'] as Map)['l2'] as Map;
        (l2['actions'] as List).add('channel:toggle');
      });
      expectProblem(broken, '重复项', '重复项让"这一条是第几个动作"在两端给出不同答案');
    });

    test('L2 动作不写成 <family>:<verb> ⇒ 报（itemFormat 那一列就失去了依据）', () {
      final broken = mutate((raw) {
        final l2 = (raw['capabilities'] as Map)['l2'] as Map;
        (l2['actions'] as List)[0] = 'listenerStart';
      });
      expectProblem(broken, '<family>:<verb>', '形状变了，逐条勾选的那一项就没法从它拼出来');
    });

    test('L2 认不出的动作改成"跳过" ⇒ 报（那等于让对端拿编出来的动作名试边界）', () {
      final broken = mutate((raw) {
        ((raw['capabilities'] as Map)['l2'] as Map)['unknownAction'] = 'skip';
      });
      expectProblem(broken, 'unknownAction 必须是 reject', '跳过 = 不设防');
    });

    test('L3 那条 unknownAction 也改成"跳过" ⇒ 报（两份刻意不共用，各改各的都要被看见）', () {
      final broken = mutate((raw) {
        (((raw['capabilities'] as Map)['l3']) as Map)['unknownAction'] = 'skip';
      });
      expectProblem(broken, 'unknownAction 必须是 reject', 'L3 那一档同样不许跳过');
    });

    test('点名要参数的动作指到词表外 ⇒ 报（那条要求就永远不会被触发）', () {
      final broken = mutate((raw) {
        ((raw['capabilities'] as Map)['l2'] as Map)['requiresArgumentFrom'] = [
          'made:up',
        ];
      });
      expectProblem(broken, 'requiresArgumentFrom', '要求一个不存在的动作带参数，等于没要求');
    });

    test('执行失败的回执词不在顶层 receipts 里 ⇒ 报（对外形状只能取那一处的词）', () {
      final broken = mutate((raw) {
        ((raw['capabilities'] as Map)['l2'] as Map)['actionReceipt'] =
            'action_broke';
      });
      expectProblem(broken, '不在顶层 receipts', '回执词只能从那张表里取');
    });

    test('itemFormat 改了形状 ⇒ 报（actions 那张表按 <family>:<verb> 写）', () {
      final broken = mutate((raw) {
        ((raw['capabilities'] as Map)['l2'] as Map)['itemFormat'] = 'a.b';
      });
      expectProblem(broken, 'itemFormat', '格式与那张表的写法对不上，两端会各行其是');
    });

    test('messageTypes.action 不再指向 L2 ⇒ 报（L2 动作表存在却没有读者）', () {
      final broken = mutate((raw) {
        ((raw['capabilities'] as Map)['messageTypes'] as Map)['action'] = {
          'minLevel': 'L3',
          '_comment': '把它挪到 L3 了',
        };
      });
      expectProblem(broken, '没有读者', '表在而 type 侧不指向它 = 这张表没人读');
    });

    // ── T51：L3 设置词表 ──
    // ⚠ 这一组是 B6 那条反证的**前提**。「l3.settings 不能为空」这一判只有
    // **表真的被清空**时才可观察 —— 上一批（T50 的 A10）就是没有这种用例，
    // 把判据改成恒真后全套照样绿。补了这一组之后那一判才有观众。
    test('L3 设置表清空 ⇒ 报（这一档没有任何设置项 = type 侧指着空处）', () {
      final broken = mutate((raw) {
        ((raw['capabilities'] as Map)['l3'] as Map)['settings'] =
            <String, Object?>{};
      });
      expectProblem(broken, 'l3.settings 不能为空', '空表与「这一档没有任何设置项」在下游读起来一样');
    });

    test('L3 设置表整段删掉 ⇒ 报（不是"读起来空"，是那一档根本不存在）', () {
      final broken = mutate((raw) {
        (raw['capabilities'] as Map)['l3'].remove('settings');
      });
      expectProblem(broken, 'l3.settings 不能为空', '整段删掉与清空是同一个后果，不能只有后者报错');
    });

    test('某一项的 mode 写成 modes 之外的词 ⇒ 报（两端会各读各的）', () {
      final broken = mutate((raw) {
        final s =
            ((raw['capabilities'] as Map)['l3'] as Map)['settings'] as Map;
        (s['autostart'] as Map)['mode'] = 'quietly';
      });
      expectProblem(broken, '不在 modes', 'mode 不在词表里 = 这一项的形态两端读出来不一样');
    });

    test('modes 清空 ⇒ 报（没有那张词表就没人能判 mode 写对了没有）', () {
      final broken = mutate((raw) {
        ((raw['capabilities'] as Map)['l3'] as Map)['modes'] = <String>[];
      });
      expectProblem(broken, 'l3.modes 不能为空', '词表空了，每一项的 mode 都成了一道没有标准答案的判据');
    });

    test('某一项不写 native ⇒ 报（契约说有、设备上找不到）', () {
      final broken = mutate((raw) {
        final s =
            ((raw['capabilities'] as Map)['l3'] as Map)['settings'] as Map;
        (s['collect_inbox'] as Map)['native'] = '';
      });
      expectProblem(broken, '没写 native', '没有落点的那一项等于"契约说有、设备上找不到"');
    });

    test('先有授权才谈得上翻的项不是 toggle ⇒ 报（自相矛盾）', () {
      final broken = mutate((raw) {
        ((raw['capabilities'] as Map)['l3']
            as Map)['requiresExistingGrantFrom'] = [
          'monitoring',
          'write_settings',
        ];
      });
      expectProblem(
        broken,
        '不是 toggle',
        '要求「先有授权才翻」的只可能是 toggle，而 grant 要的正是去拿那项授权',
      );
    });

    test('L3 执行失败的回执词不在顶层 receipts 里 ⇒ 报（对外形状只能取那一处的词）', () {
      final broken = mutate((raw) {
        ((raw['capabilities'] as Map)['l3'] as Map)['settingsReceipt'] =
            'setting_broke';
      });
      expectProblem(broken, '不在顶层 receipts', '回执词只能从那张表里取');
    });

    test('messageTypes.setting 不再指向 L3 ⇒ 报（设置表存在却没有读者）', () {
      final broken = mutate((raw) {
        ((raw['capabilities'] as Map)['messageTypes'] as Map)['setting'] = {
          'minLevel': 'L2',
          '_comment': '把它挪到 L2 了',
        };
      });
      expectProblem(broken, '没有读者', '表在而 type 侧不指向它 = 这张表没人读');
    });

    test('验签失败不计数 ⇒ 报（T29 任务书那句「并计数」）', () {
      final broken = mutate((raw) {
        ((raw['signature'] as Map)['onFailure'] as Map)['count'] = false;
      });
      expectProblem(broken, 'onFailure.count', '拒了不留数就是静默丢弃');
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

    test('30 以下改成"软件明文存私钥" ⇒ 报（红线被改成注释也不行）', () {
      final broken = mutate((raw) {
        ((raw['identity'] as Map)['identityKey'] as Map)['belowNativeSdk'] =
            'softwarePlaintext';
      });
      expectProblem(broken, 'belowNativeSdk', '私钥不可导出是任务书原文');
    });

    test('平台门槛写回 30（能生成 ≠ 能签名）⇒ 报', () {
      final broken = mutate((raw) {
        ((raw['identity'] as Map)['identityKey']
                as Map)['nativeMinSdkVersion'] =
            30;
      });
      expectProblem(
        broken,
        'nativeMinSdkVersion',
        'KeyStore 的 EdDSA 自 API 30 起',
      );
    });

    test('不上报 keystoreBacked 能力位 ⇒ 报（两条路径强度不同，用户有权知道）', () {
      final broken = mutate((raw) {
        ((raw['identity'] as Map)['identityKey']
                as Map)['keystoreBackedCapability'] =
            false;
      });
      expectProblem(broken, 'keystoreBacked', '能力位必须上报');
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

    // ── 投递状态机（T34-A）：这张表少一条边不会报错，只会让消息停在中间态 = 正文删不掉 ──
    test('dropped 从 deleteBodyOn 里去掉 ⇒ 报（本批第一次就漏了这条）', () {
      final broken = mutate((raw) {
        (raw['retention'] as Map<String, Object?>)['deleteBodyOn'] = [
          'delivered',
          'expired',
        ];
      });
      expectProblem(
        broken,
        'retention.deleteBodyOn 必须覆盖全部终态',
        '被挤位那条消息永远不会再投，正文却按契约合法地留到 7 天',
      );
    });

    test('终态被加了一条出边 ⇒ 报（"有出边的终态"说明它不是终点）', () {
      final broken = mutate((raw) {
        (raw['delivery'] as Map<String, Object?>)['transitions'] = {
          ...((raw['delivery'] as Map<String, Object?>)['transitions']
              as Map<String, Object?>),
          'delivered': ['queued'],
        };
      });
      expectProblem(broken, '终态不许有出边', '终态必须没有出边');
    });

    test('waiting_online 两条出边都清空 ⇒ 报（非终态没有出边 = 消息卡死）', () {
      final broken = mutate((raw) {
        (raw['delivery'] as Map<String, Object?>)['transitions'] = {
          ...((raw['delivery'] as Map<String, Object?>)['transitions']
              as Map<String, Object?>),
          'waiting_online': const <Object?>[],
        };
      });
      expectProblem(broken, '非终态必须有出边', 'waiting_online 变黑洞');
    });

    test('加一个从初态走不到的状态 ⇒ 报（写出来却到不了，早晚被两边按不同方式处理）', () {
      final broken = mutate((raw) {
        final d = raw['delivery'] as Map<String, Object?>;
        d['states'] = [...(d['states'] as List<Object?>), 'zombie'];
        d['transitions'] = {
          ...(d['transitions'] as Map<String, Object?>),
          'zombie': const <Object?>[],
        };
        d['terminalStates'] = [
          ...(d['terminalStates'] as List<Object?>),
          'zombie',
        ];
        (raw['retention'] as Map<String, Object?>)['deleteBodyOn'] = [
          ...((raw['retention'] as Map<String, Object?>)['deleteBodyOn']
              as List<Object?>),
          'zombie',
        ];
      });
      expectProblem(broken, '走不到的状态', '不可达状态必须报');
    });

    test('迁移表指向一个不存在的状态 ⇒ 报', () {
      final broken = mutate((raw) {
        (raw['delivery'] as Map<String, Object?>)['transitions'] = {
          ...((raw['delivery'] as Map<String, Object?>)['transitions']
              as Map<String, Object?>),
          'queued': ['teleporting'],
        };
      });
      expectProblem(broken, '指向不存在的状态', '迁移表的目标必须在 states 里');
    });

    test('事件表清空 ⇒ 报（没有事件表，两边就只能各编一套触发条件）', () {
      final broken = mutate((raw) {
        (raw['delivery'] as Map<String, Object?>)['events'] = const [];
      });
      expectProblem(broken, 'delivery.events 必须非空', '事件表不能缺');
    });

    test('把重试次数改成 -1 ⇒ 报（它是重试次数，不是"总次数减一"的任意整数）', () {
      final broken = mutate((raw) {
        (raw['limits'] as Map<String, Object?>)['deliveryRetryTotal'] = -1;
      });
      expectProblem(broken, 'limits.deliveryRetryTotal', '重试预算必须 ≥ 0');
    });

    test('状态机要发的回执不在回执词表里 ⇒ 报（两张表必须同源）', () {
      final broken = mutate((raw) {
        raw['receipts'] = (raw['receipts'] as List<Object?>)
            .where((e) => e != 'dropped')
            .toList();
      });
      expectProblem(broken, '不在 receipts 里', '挤位回执必须在词表里');
    });

    test('resendDecisionFrom 指向一个没有的段 ⇒ 报（补发路向不许在别处再抄一份）', () {
      final broken = mutate((raw) {
        (raw['delivery'] as Map<String, Object?>)['resendDecisionFrom'] =
            'somewhereElse';
      });
      expectProblem(broken, 'delivery.resendDecisionFrom', '补发路向必须来自契约里那一段');
    });

    // ── 存储侧（T34-B）：「只保留必要字段」与「正文静态加密」要能被实现，得有名单与参数 ──
    test('storedFields 里去掉 body ⇒ 报（正文没地方放，等于"不存正文"这条被悄悄改掉）', () {
      final broken = mutate((raw) {
        (raw['retention'] as Map<String, Object?>)['storedFields'] =
            ((raw['retention'] as Map<String, Object?>)['storedFields']
                    as List<Object?>)
                .where((e) => e != 'body')
                .toList();
      });
      expectProblem(broken, 'retention.storedFields 少了 body', '正文必须有存放字段');
    });

    test('只留必要字段=true 却不给名单 ⇒ 报（没有名单，那句话就只是愿望）', () {
      final broken = mutate((raw) {
        (raw['retention'] as Map<String, Object?>).remove('storedFields');
      });
      expectProblem(broken, '必须给出一份 storedFields', '白名单必须存在');
    });

    // ── 投递留痕（T45 第二片）：时间线必须有界，而且必须有地方放 ──
    test('auditTrail 整段拿掉 ⇒ 报（没界就别记，服务端那一侧是抛不是退回默认值）', () {
      final broken = mutate((raw) {
        (raw['retention'] as Map<String, Object?>).remove('auditTrail');
      });
      expectProblem(
        broken,
        'retention.auditTrail.maxPerMessage 必须是正整数',
        '投递时间线要么有界，要么就别记',
      );
    });

    test('maxPerMessage 改成 0 ⇒ 报（0 读起来像"不记"，实现却会当成"记了再全裁掉"）', () {
      final broken = mutate((raw) {
        ((raw['retention'] as Map<String, Object?>)['auditTrail']
                as Map<String, Object?>)['maxPerMessage'] =
            0;
      });
      expectProblem(broken, 'maxPerMessage 必须是正整数', '上限必须为正');
    });

    test('留痕字段名单空着 ⇒ 报（没有名单就等于允许往时间线里塞正文）', () {
      final broken = mutate((raw) {
        ((raw['retention'] as Map<String, Object?>)['auditTrail']
                as Map<String, Object?>)['fields'] =
            <Object?>[];
      });
      expectProblem(broken, 'retention.auditTrail.fields 必须非空且不重复', '留痕的键要有名单');
    });

    test('留痕字段名单重复 ⇒ 报（同一格出现两次说明这份名单是抄的，不是定的）', () {
      final broken = mutate((raw) {
        ((raw['retention'] as Map<String, Object?>)['auditTrail']
            as Map<String, Object?>)['fields'] = <Object?>[
          'state',
          'state',
        ];
      });
      expectProblem(broken, 'retention.auditTrail.fields 必须非空且不重复', '名单不许有重复');
    });

    test('storedFields 少了 trail ⇒ 报（有留痕却没有存放它的字段，症状是时间线永远是空的）', () {
      final broken = mutate((raw) {
        (raw['retention'] as Map<String, Object?>)['storedFields'] =
            ((raw['retention'] as Map<String, Object?>)['storedFields']
                    as List<Object?>)
                .where((e) => e != 'trail')
                .toList();
      });
      expectProblem(broken, 'retention.storedFields 少了 trail', '留痕必须有存放字段');
    });

    test('storedFields 少了 trailDropped ⇒ 报（裁掉多少没有地方记，就成了悄悄丢）', () {
      final broken = mutate((raw) {
        (raw['retention'] as Map<String, Object?>)['storedFields'] =
            ((raw['retention'] as Map<String, Object?>)['storedFields']
                    as List<Object?>)
                .where((e) => e != 'trailDropped')
                .toList();
      });
      expectProblem(
        broken,
        'retention.storedFields 少了 trailDropped',
        '裁掉的条数要留得下',
      );
    });

    test('GCM 的 IV 长度改成 16 ⇒ 报（那是 CBC 的习惯，GCM 用 12）', () {
      final broken = mutate((raw) {
        ((raw['retention'] as Map<String, Object?>)['bodyAtRest']
                as Map<String, Object?>)['ivBytes'] =
            16;
      });
      expectProblem(broken, 'ivBytes 必须是 12', 'IV 长度写错会削弱 GCM');
    });

    test('没有密钥时允许退回明文 ⇒ 报（正文这条不允许，TOTP 那条取舍不外溢）', () {
      final broken = mutate((raw) {
        ((raw['retention'] as Map<String, Object?>)['bodyAtRest']
                as Map<String, Object?>)['refuseWithoutKey'] =
            false;
      });
      expectProblem(broken, 'refuseWithoutKey 必须为 true', '缺密钥只能拒绝入队');
    });

    test('把终态列进 pollableStates ⇒ 报（终态已经没有正文可发）', () {
      final broken = mutate((raw) {
        (raw['delivery'] as Map<String, Object?>)['pollableStates'] = [
          ...((raw['delivery'] as Map<String, Object?>)['pollableStates']
              as List<Object?>),
          'delivered',
        ];
      });
      expectProblem(broken, 'pollableStates 里有终态', '终态不可投递');
    });

    test('初态不在 pollableStates 里 ⇒ 报（新消息永远不会被取走）', () {
      final broken = mutate((raw) {
        (raw['delivery'] as Map<String, Object?>)['pollableStates'] = [
          'waiting_online',
        ];
      });
      expectProblem(broken, '必须含初态', 'poll 取不到新消息');
    });

    test('ackDeadlineSeconds 不是一个正数 ⇒ 报（no_ack 就永远没有触发时机）', () {
      final broken = mutate((raw) {
        (raw['delivery'] as Map<String, Object?>)['ackDeadlineSeconds'] = 0;
      });
      expectProblem(
        broken,
        'ackDeadlineSeconds 必须是正整数',
        '没有这一档，被取走却没 ack 的消息静默卡在 delivering',
      );
    });

    test('ackDeadlineSeconds 收得比三轮 poll 还紧 ⇒ 报（把正常往返误判成丢 ack）', () {
      final broken = mutate((raw) {
        (raw['delivery'] as Map<String, Object?>)['ackDeadlineSeconds'] = 30;
      });
      expectProblem(
        broken,
        '3× cadence max',
        '太紧会把一次正常往返判成没收到 ack，设备只是离了一小会儿网就重收',
      );
    });

    test('同意门那一档拿掉或不是正数 ⇒ 报（没有判据就等于替用户做了决定）', () {
      final missing = mutate((raw) {
        (raw['privacy'] as Map<String, Object?>)['relayConsentVersion'] = 0;
      });
      expectProblem(
        missing,
        'relayConsentVersion 必须是正整数',
        '拿掉它 ⇒ 同意永远算成立，等于替用户点了同意',
      );
      final nulled = mutate((raw) {
        (raw['privacy'] as Map<String, Object?>).remove('relayConsentVersion');
      });
      expectProblem(nulled, 'relayConsentVersion', '同意的判据不许缺省');
    });

    test('dedupeRefreshWhile 写成一个不存在的状态 ⇒ 报（"什么时候可以覆盖"也是状态机的事）', () {
      final broken = mutate((raw) {
        (raw['privacy'] as Map<String, Object?>)['dedupeRefreshWhile'] =
            'fresh';
      });
      expectProblem(broken, 'dedupeRefreshWhile 必须是一个投递状态', '覆盖条件必须落在状态表里');
    });

    test('域名写成带 scheme 的整 URL ⇒ 报（客户端还要拼 https:// 前缀）', () {
      final broken = mutate((raw) {
        (raw['transport'] as Map<String, Object?>)['endpoints'] = {
          ...(raw['transport'] as Map<String, Object?>)['endpoints']
              as Map<String, Object?>,
          'international': 'https://push.fnthink.top',
        };
      });
      expectProblem(
        broken,
        '必须是裸主机名',
        '带 scheme 会拼成 https://https//…，而这条错要到用户点推送才现形',
      );
    });

    test('默认域名指向没声明过的第三条 ⇒ 报（装了 App 检查更新正常、推送全连不上）', () {
      final broken = mutate((raw) {
        (raw['transport'] as Map<String, Object?>)['endpoints'] = {
          ...(raw['transport'] as Map<String, Object?>)['endpoints']
              as Map<String, Object?>,
          'default': 'push.fnthink.cn',
        };
      });
      expectProblem(broken, '必须是两个域名之一', 'default 不在表里 = 客户端连一个协议没声明的域名');
    });

    test('两个域名写成同一条 ⇒ 报（双域名部署退化成一条）', () {
      final broken = mutate((raw) {
        (raw['transport'] as Map<String, Object?>)['endpoints'] = {
          ...(raw['transport'] as Map<String, Object?>)['endpoints']
              as Map<String, Object?>,
          'mainland': 'push.fnthink.top',
        };
      });
      expectProblem(broken, '双域名必须不同', '同域就没有"大陆/国际可达性不同"这回事，T57 落空');
    });

    test('poll 的事件类型改用 notice ⇒ 报（一次 poll 的签名就能冒充一条已授权通知）', () {
      final broken = mutate((raw) {
        ((raw['clientEvents'] as Map<String, Object?>)['poll']
                as Map<String, Object?>)['messageType'] =
            'notice';
      });
      expectProblem(
        broken,
        '出现在 capabilities.messageTypes',
        '事件与消息共用签字节，type 撞车就是同一把签名两个接口都能用',
      );
    });

    test('poll 允许 target 填别人的地址码 ⇒ 报（一台设备能读走别人的队列）', () {
      final broken = mutate((raw) {
        ((raw['clientEvents'] as Map<String, Object?>)['poll']
                as Map<String, Object?>)['targetMustEqualSender'] =
            false;
      });
      expectProblem(
        broken,
        'targetMustEqualSender 必须为 true',
        '不钉这条，任何已配对设备都能拿到别人的标题与正文',
      );
    });

    test('ack.fields 与 delivery.ackFields 分叉 ⇒ 报（两张表早晚各改一份）', () {
      final broken = mutate((raw) {
        ((raw['clientEvents'] as Map<String, Object?>)['ack']
            as Map<String, Object?>)['fields'] = [
          'messageId',
        ];
      });
      expectProblem(
        broken,
        '必须与 delivery.ackFields 逐字相同',
        '字段名分叉的表现是 ack 静默读不到 result',
      );
    });

    test('poll 响应里没有 serverTime ⇒ 报（ts 以服务端时间判定就没有承载处）', () {
      final broken = mutate((raw) {
        ((raw['clientEvents'] as Map<String, Object?>)['poll']
            as Map<String, Object?>)['returns'] = [
          'messages',
          'pending',
        ];
      });
      expectProblem(
        broken,
        '必须含 serverTime',
        '设备自算偏移只能在拿到响应之后进行，缺这字段 T29 那半条永远落不了地',
      );
    });

    test('回执改成另开一个状态接口 ⇒ 报（与 senderPollsStatusEndpoint=false 矛盾）', () {
      final broken = mutate((raw) {
        (raw['delivery'] as Map<String, Object?>)['receiptDelivery'] =
            'status_endpoint';
      });
      expectProblem(
        broken,
        'receiptDelivery 必须是 poll_response',
        '两条并存的路会让发送端去轮一个契约没定义的入口',
      );
    });

    test('ack 的 resultToEvent 允许设备自报 expired ⇒ 报（服务端自己的决定）', () {
      final broken = mutate((raw) {
        final map =
            ((raw['clientEvents'] as Map<String, Object?>)['ack']
                    as Map<String, Object?>)['resultToEvent']
                as Map<String, Object?>;
        map['expired'] = 'ttl_elapsed';
      });
      expectProblem(
        broken,
        '那是服务端自己的决定',
        '设备能报 expired，就等于替服务端下"这条已过期"的结论并提前释放正文',
      );
    });

    test('resultToEvent 的值指向一个不存在的事件 ⇒ 报（路由会照表推进到 nowhere）', () {
      final broken = mutate((raw) {
        ((raw['clientEvents'] as Map<String, Object?>)['ack']
            as Map<String, Object?>)['resultToEvent'] = {
          'displayed': 'ack_yes',
        };
      });
      expectProblem(broken, 'ack_ok', 'displayed 必须推进到 ack_ok，改成没定义的事件必须报');
    });

    // ── 泛化后的事件种类判据：新增一种必须同样被三条规则覆盖（写死 poll/ack 的旧版做不到这点）──
    test('新增第四种事件却不写 messageType ⇒ 报', () {
      final broken = mutate((raw) {
        final ce = raw['clientEvents'] as Map<String, Object?>;
        ce['unsubscribe'] = {
          'verifyAgainst': 'device-table-public-key',
          'targetMustEqualSender': true,
        };
      });
      expectProblem(broken, '缺 messageType', '「这一步是哪种事件」不许由实现猜');
    });

    test('两种事件共用同一个 messageType ⇒ 报（一次签名两个接口都能用）', () {
      final broken = mutate((raw) {
        ((raw['clientEvents'] as Map<String, Object?>)['register']
                as Map<String, Object?>)['messageType'] =
            'poll';
      });
      expectProblem(broken, '与已声明的事件种类重复', 'type 撞车 = poll 的签名可以当登记用');
    });

    test('register 的字段表自相矛盾（publicKey 既必带又禁带）⇒ 报', () {
      final broken = mutate((raw) {
        final reg =
            ((raw['clientEvents'] as Map<String, Object?>)['register']
                as Map<String, Object?>);
        (reg['mayNotCarry'] as List<Object?>).add('publicKey');
      });
      expectProblem(broken, '既"必带"又"禁带"', '这种键写进契约后实现选哪边都不对');
    });

    // ── 三选一的作用范围判据（#131 第二片 2A）──
    test('poll 不声明任何 self-only 规则 ⇒ 报（那它就既能关于自己也能关于别人）', () {
      final broken = mutate((raw) {
        ((raw['clientEvents'] as Map<String, Object?>)['poll']
                as Map<String, Object?>)
            .remove('targetMustEqualSender');
      });
      expectProblem(broken, '恰好一条', '零条 = 一台已配对设备能读走别人队列里的标题与正文');
    });

    test('poll 同时声明两条规则 ⇒ 报（OR 判下是放宽，不是收紧）', () {
      final broken = mutate((raw) {
        ((raw['clientEvents'] as Map<String, Object?>)['poll']
                as Map<String, Object?>)['mustContainCounterpartAddress'] =
            true;
      });
      expectProblem(broken, '恰好一条', '两条都为真 + 实现按 OR 判 = 一个接口既能关于自己又能关于别人');
    });

    test('selfOnlyRules 名单被清空 ⇒ 报（名单空时「恰好一条」恒假，整套判据一起瞎）', () {
      final broken = mutate((raw) {
        (raw['clientEvents'] as Map<String, Object?>)['selfOnlyRules'] = [];
      });
      expectProblem(broken, '非空且无重复', '名单本身就是判据的一部分，不是注释');
    });

    test('自带公钥却声明查表验 ⇒ 报（那把随请求来的钥匙成了没人读的摆设）', () {
      final broken = mutate((raw) {
        final reg =
            ((raw['clientEvents'] as Map<String, Object?>)['register']
                as Map<String, Object?>);
        reg['verifyAgainst'] = 'device-table-public-key';
      });
      expectProblem(broken, '自相矛盾', '「用哪把钥匙验」与「这一步带不带公钥」必须互为充要，单向查会留下摆设');
    });

    test('对方地址码不在被签字节里却声明了 counterpart 规则 ⇒ 报', () {
      final broken = mutate((raw) {
        final ce = raw['clientEvents'] as Map<String, Object?>;
        final poll = ce['poll'] as Map<String, Object?>;
        poll.remove('targetMustEqualSender');
        poll['mustContainCounterpartAddress'] = true;
        (raw['signature'] as Map<String, Object?>)['canonicalOrder'] = [
          'version',
          'type',
          'ts',
          'nonce',
          'body',
        ];
      });
      expectProblem(
        broken,
        'canonicalOrder 里没有 target',
        '对方地址码没被签，等于谁都能在转发时换一个收件人',
      );
    });

    test('register 被改成按设备表验签 ⇒ 报（表里还没有他这一行，无从验起）', () {
      final broken = mutate((raw) {
        ((raw['clientEvents'] as Map<String, Object?>)['register']
                as Map<String, Object?>)['verifyAgainst'] =
            'device-table-public-key';
      });
      expectProblem(
        broken,
        '钥匙来源与公钥字段自相矛盾',
        '这条私钥证明的豁免必须与"自带公钥"同真同假，锁死在带钥匙的那一种事件上',
      );
    });

    test('register 被改成查表验且不再自带公钥 ⇒ 报（地址码是客户端带来的，表里没有他）', () {
      // 上面那条走的是充要判据；这一条把两个旗标一起删掉，充要判据就"自洽"了 ——
      // 抓它的是 addressCodeSource 那条蕴含式（泛化版，不点名 register）。
      final broken = mutate((raw) {
        final reg =
            ((raw['clientEvents'] as Map<String, Object?>)['register']
                as Map<String, Object?>);
        reg['verifyAgainst'] = 'device-table-public-key';
        reg.remove('carriesOwnPublicKey');
      });
      expectProblem(broken, '地址码来自客户端', '拿设备表去验一个还不存在的身份，只能验出"不认识"——整条链在第一步就断');
    });

    // ── 配对链两步的判据（#131 第二片 2B）：挂的人、消耗的人、以及那张请求表自己 ──
    Map<String, Object?> ceOf(Map<String, Object?> raw) =>
        raw['clientEvents'] as Map<String, Object?>;
    Map<String, Object?> kindOf(Map<String, Object?> raw, String kind) =>
        ceOf(raw)[kind] as Map<String, Object?>;

    test('pair 消耗的字段没被自己签上 ⇒ 报（口令不在被签字节里就是可换的）', () {
      final broken = mutate((raw) {
        (kindOf(raw, 'pair')['fields'] as List<Object?>).remove('pairingCode');
      });
      expectProblem(
        broken,
        '不在它自己的 fields 清单里',
        'consumes 指向一个没进签名字节的键 = 挂上去的和消耗掉的不是同一样东西',
      );
    });

    test('只有消耗、没人挂 ⇒ 报（服务端手上根本没有可对照的摘要）', () {
      final broken = mutate((raw) {
        kindOf(raw, 'pairArm').remove('arms');
      });
      expectProblem(broken, '一一对应', '配对口令永远不过期地挂着，或永远没人挂：都是半条链');
    });

    test('同一个事件自己挂自己消耗 ⇒ 报（配对必须有两个参与者）', () {
      final broken = mutate((raw) {
        kindOf(raw, 'pair')['arms'] = 'pairingCode';
      });
      expectProblem(broken, '自己挂自己消耗', '一步之内自挂自消 = 中间没有"对方确认"那一环');
    });

    test('pairRequest.neverStored 放开 pairingCode ⇒ 报（明文口令会跟着备份走）', () {
      final broken = mutate((raw) {
        ((raw['pairRequest'] as Map<String, Object?>)['neverStored']
                as List<Object?>)
            .remove('pairingCode');
      });
      expectProblem(
        broken,
        'neverStored 必须含 pairingCode',
        '那 20 位被抄过、印在二维码里、可能被拍过照',
      );
    });

    test('pairRequest.storedFields 少 requester ⇒ 报（不知道是谁请求的）', () {
      final broken = mutate((raw) {
        ((raw['pairRequest'] as Map<String, Object?>)['storedFields']
                as List<Object?>)
            .remove('requester');
      });
      expectProblem(broken, '必须同时有 target', '一条没人认领的请求没法显示给任何人');
    });

    test('poll.returns 里没有 pairRequest.pollKey ⇒ 报（创建了东西却没人取得它）', () {
      final broken = mutate((raw) {
        (kindOf(raw, 'poll')['returns'] as List<Object?>).remove(
          'pairRequests',
        );
      });
      expectProblem(broken, '不在那份清单上', '请求躺在表里、A 屏幕上永远显示"等待配对"，那是最难的静默之一');
    });

    test('poll 名单里没有 sender ⇒ 报（收件表那一行无处归属）', () {
      final broken = mutate((raw) {
        (kindOf(raw, 'poll')['messageFields'] as List<Object?>).remove(
          'sender',
        );
      });
      expectProblem(broken, '少了 sender', '「是谁发的」只有这一个数据源');
    });

    test('poll 名单里没有 messageId ⇒ 报（没有主键那条永远 ack 不了）', () {
      final broken = mutate((raw) {
        (kindOf(raw, 'poll')['messageFields'] as List<Object?>).remove(
          'messageId',
        );
      });
      expectProblem(broken, '少了 messageId', '设备手上没有 id 就无法对那一条表态');
    });

    test('poll 名单里写一个投影不出来的名字 ⇒ 报（服务端会静默回一个空值）', () {
      final broken = mutate((raw) {
        // dedupeIdDigest 是盘上的摘要，设备拿它做不了任何事；把它抄进名单正是
        // "看起来名单里本该有这一个"的那类错 —— 后果不是报错，是那列永远为空。
        kindOf(raw, 'poll')['messageFields'] = [
          'messageId',
          'type',
          'item',
          'title',
          'body',
          'sender',
          'dedupeIdDigest',
        ];
      });
      expectProblem(broken, '投影不出来', '名单是投影的唯一依据，错一个名字就少一列');
    });

    test('poll 名单为空 ⇒ 报（"回一个空对象"不是名单为空的意思）', () {
      final broken = mutate((raw) {
        kindOf(raw, 'poll')['messageFields'] = <Object?>[];
      });
      expectProblem(broken, '必须非空且无重复', '空名单会让每条消息变成 {}');
    });

    test('ttlSecondsFrom 指到一个不存在的键 ⇒ 报（不补默认 TTL）', () {
      final broken = mutate((raw) {
        (raw['pairRequest'] as Map<String, Object?>)['ttlSecondsFrom'] =
            'identity.pairingCode.notThere';
      });
      expectProblem(broken, '必须指向契约里一个真实存在的秒数', '另设一个 TTL 会出现"口令还活着而请求已消失"');
    });

    test('每台的上限高过全局上限 ⇒ 报（两条数反了方向）', () {
      final broken = mutate((raw) {
        final pr = raw['pairRequest'] as Map<String, Object?>;
        pr['perDeviceLimit'] = 500;
        pr['globalLimit'] = 100;
      });
      expectProblem(broken, '两条上限不成样子', 'perDevice 只能 ≤ global，否则那条永远不生效');
    });

    test('删掉 limits.devicesMax ⇒ 报（未认证流量面前不许有无限增长的表）', () {
      final broken = mutate((raw) {
        (raw['limits'] as Map<String, Object?>).remove('devicesMax');
      });
      expectProblem(
        broken,
        'limits.devicesMax 必须是正整数',
        '/register 的代价对攻击者是一把密钥、对服务端是一行记录加一次磁盘写',
      );
    });

    test('名单里的规则没人用 ⇒ 报（2A 欠的那条现在能判了）', () {
      // counterpart 这条规则现在有**三个**使用者（pair / pairConfirm / pairRevoke），
      // 所以只摘一两个不会被判出来 —— 这条用例要一起摘掉，才是真的"没人用"。
      // ⚠ 新增一个声明它的事件种类时必须同时加进这个名单：漏了它，这条反证就会一直在
      //    "还有一个使用者"上假过，而名单与实现的分叉从此没人看门。
      final broken = mutate((raw) {
        for (final kind in ['pair', 'pairConfirm', 'pairRevoke']) {
          final spec =
              (raw['clientEvents'] as Map<String, Object?>)[kind]
                  as Map<String, Object?>;
          spec.remove('mustContainCounterpartAddress');
          spec['targetMustEqualSender'] = true;
        }
      });
      expectProblem(broken, '没有任何事件声明它', '写了却没人用的那条早晚被当成注释，而它下次被真用时多半没有实现分支');
    });

    // ── 配对关系存在哪张表、由哪一端判，以及 A 那次确认（#131 第三片）──
    Map<String, Object?> pairOf(Map<String, Object?> raw) =>
        ((raw['clientEvents'] as Map<String, Object?>)['pairConfirm']
            as Map<String, Object?>);

    test('关系改回存在发送方记录上 ⇒ 报（登记即许可就是那样）', () {
      final broken = mutate((raw) {
        (raw['pairing'] as Map<String, Object?>)['relationshipStoredOn'] =
            'sender-device-record';
      });
      expectProblem(
        broken,
        'relationshipStoredOn 只能是 target-device-record',
        '存在发送方那一行时，"逐条勾选/每次本地确认/重建后重配"三条都执行不了',
      );
    });

    test('关系列名缺了 ⇒ 报（收单不知道去哪读）', () {
      final broken = mutate((raw) {
        (raw['pairing'] as Map<String, Object?>).remove('relationshipField');
      });
      expectProblem(broken, 'relationshipField 不能缺', '缺了这道判据就是没有的');
    });

    test('执行点写成设备侧判 ⇒ 报（本实现没有那条路径，声明了就是装饰）', () {
      final broken = mutate((raw) {
        (raw['pairing'] as Map<String, Object?>)['enforcedAt'] = 'device-only';
      });
      expectProblem(broken, 'enforcedAt 只能是 server-intake', '声明一条没人执行的闸比没有更危险');
    });

    test('查不到关系时允许回落缺省档 ⇒ 报（那正是 fail-open）', () {
      final broken = mutate((raw) {
        (raw['pairing']
                as Map<String, Object?>)['relationshipRequiredForIntake'] =
            false;
      });
      expectProblem(
        broken,
        'relationshipRequiredForIntake 不为 true',
        '"谁都没配过对"变成默认放行，方向正好反了',
      );
    });

    test('关系项少 maxLevel ⇒ 报（缺省档补不进这份节点，配对过的设备反被自己卡住）', () {
      final broken = mutate((raw) {
        ((raw['pairing'] as Map<String, Object?>)['relationshipEntryFields']
                as List<Object?>)
            .remove('maxLevel');
      });
      expectProblem(
        broken,
        'relationshipEntryFields 缺 maxLevel',
        '两处形状必须一致才只有一份规则',
      );
    });

    test('确认的某个状态不是终态 ⇒ 报（那条请求永远处理不完）', () {
      final broken = mutate((raw) {
        (pairOf(raw)['decisions'] as List<Object?>).add('pending');
      });
      expectProblem(
        broken,
        '不属于 pairRequest.terminalStatuses',
        '把非终态写回去等于请求不会结束',
      );
    });

    test('没声明哪个词算"同意" ⇒ 报（不敢猜：猜错的方向是关掉请求却不给授权）', () {
      final broken = mutate((raw) {
        pairOf(raw).remove('approveDecision');
      });
      expectProblem(
        broken,
        'approveDecision 必须是 decisions 里那一个',
        '让实现自己认这个词，状态改名就会把同意当拒绝',
      );
    });

    test('decisions 有了但载荷里没有 decision ⇒ 报（那张表没人能推进）', () {
      final broken = mutate((raw) {
        (pairOf(raw)['fields'] as List<Object?>).remove('decision');
      });
      expectProblem(broken, '却不在 fields 里带 decision', '声明了状态却没有承载它的字段');
    });

    test('去掉"只能处理关于自己的"那条 ⇒ 报（别人的 requestId 就能替别人答应）', () {
      final broken = mutate((raw) {
        pairOf(raw)['requestMustBelongToTarget'] = false;
      });
      expectProblem(
        broken,
        '必须同时声明 requestMustBelongToTarget 与 consumesRequest',
        '一次点头变成可反复使用的凭证，或替别人点头',
      );
    });

    test('载荷带 level 却没有上限引用 ⇒ 报（那道上限闸没人读）', () {
      final broken = mutate((raw) {
        pairOf(raw).remove('levelCeilingFrom');
      });
      expectProblem(
        broken,
        '档位与它的上限必须同进同出',
        '只有 L2 以下能从这里进来，靠的是这个引用而不是实现里的字面量',
      );
    });

    test('decides 指向一个不存在的段 ⇒ 报（在处理一张没定义过的表）', () {
      final broken = mutate((raw) {
        pairOf(raw)['decides'] = 'pairRequestV2';
      });
      expectProblem(broken, '但契约顶层没有 pairRequestV2 这一段', '创建了/处理了东西却没定义它长什么样');
    });

    test('storedFields 去掉 sender ⇒ 报（回执通道没有收件人）', () {
      final broken = mutate((raw) {
        final keep =
            ((raw['retention'] as Map<String, Object?>)['storedFields']
                    as List<Object?>)
                .where((f) => '$f' != 'sender')
                .toList();
        (raw['retention'] as Map<String, Object?>)['storedFields'] = keep;
      });
      expectProblem(
        broken,
        '投递/回执少了归属',
        '只记 device 不记 sender，"到终态后告诉发送端"就无从实现（#126 写 poll 时撞上的）',
      );
    });

    // #130-A1：那两个数字原先只写了大小没写"量谁"，实现于是绕开它们自己定了一个 ⇒ 两份真值。
    // 下面每条都对应一次真实发生过的错（最后两条是这一片自己改错了才发现的那一类）。
    test('perEndpoint 里写了一个不存在的事件种类 ⇒ 报（映射到不存在的东西上＝静默不限流）', () {
      final broken = mutate((raw) {
        (raw['limits'] as Map<String, Object?>)['perEndpoint'] = [
          'register',
          'teleport',
        ];
      });
      expectProblem(
        broken,
        '不是 clientEvents 里的事件种类',
        '限流按 URL 段映射到事件种类，映射到一个不存在的东西上就是静默不限流',
      );
    });

    test('cadenceGoverned 漏掉 poll ⇒ 报（把 4320 次/天的正常轮询塞进按 IP 那一档）', () {
      final broken = mutate((raw) {
        (raw['limits'] as Map<String, Object?>)['cadenceGoverned'] = ['ack'];
      });
      expectProblem(broken, 'cadenceGoverned 必须含 poll', '轮询属节奏类，不能按登记额度卡');
    });

    test('两份名单重叠 ⇒ 报（同一端点两把尺子，谁先响取决于实现顺序）', () {
      final broken = mutate((raw) {
        (raw['limits'] as Map<String, Object?>)['perEndpoint'] = [
          'register',
          'poll',
        ];
      });
      expectProblem(broken, '不许重叠', '两把尺子同时量一个端点时，OR 判出来的不是更严而是更宽');
    });

    test('把"已经能证明是谁"的操作放进按 IP 计的那一档 ⇒ 报（这一片真的犯过）', () {
      // 第一版 perEndpoint 里列了 register + 配对三步，结果 7 条配对路由用例全红：
      // 手机、手表、家里三台在 Nginx 之后是同一个源，共用 6 次/分＝「同时配对两台」被判成攻击。
      // 分界不是"哪种请求少见"，而是"签名能不能证明他是谁"。
      final broken = mutate((raw) {
        (raw['limits'] as Map<String, Object?>)['perEndpoint'] = [
          'register',
          'pairConfirm',
        ];
      });
      expectProblem(
        broken,
        '不能按 IP 计',
        'verifyAgainst=device-table-public-key ⇒ 该按发送方计',
      );
    });

    test('反过来把 register 放进按发送方那一档 ⇒ 报（它还没有身份可计）', () {
      final broken = mutate((raw) {
        (raw['limits'] as Map<String, Object?>)['perSenderOnly'] = [
          'message',
          'register',
        ];
        (raw['limits'] as Map<String, Object?>)['perEndpoint'] = <String>[];
      });
      expectProblem(broken, '只能按 IP 计', '自带公钥的那一类没有"发送方"可计，按 IP 是唯一选择');
    });

    test('按 IP 那一档被收到比轮询推导额度还紧 ⇒ 报（7 条路由用例的真实教训）', () {
      // 我第一版就把方向搞反了：收成 6 看似"最紧的尺子对着未认证流量"，实际是
      // "家里一次装四台设备"先被 429 —— 反代之后所有设备都是同一个源。
      final broken = mutate((raw) {
        (raw['limits'] as Map<String, Object?>)['unauthenticatedPerMinute'] = 6;
      });
      expectProblem(broken, '不许严于轮询侧的推导额度', '按 IP 计的端点额度只能当洪水闸，卡紧了误伤的是诚实用户');
    });

    test('提频与常态之间的重叠余量被抹成零 ⇒ 报（切换那一分钟会被判成攻击）', () {
      final broken = mutate((raw) {
        (raw['limits'] as Map<String, Object?>)['pollBurstSlack'] = 0;
      });
      expectProblem(broken, 'pollBurstSlack 必须 ≥ 1', '两种节奏在同一分钟里会重叠计数');
    });

    test('提频间隔不比常态间隔快 ⇒ 报（推导所依据的那组参数本身自相矛盾）', () {
      final broken = mutate((raw) {
        ((raw['presence'] as Map<String, Object?>)['burstWhenPending']
                as Map<String, Object?>)['intervalSeconds'] =
            25;
      });
      expectProblem(broken, '必须不大于 pollIntervalSeconds.min', '比常态还慢的"提频"没有意义');
    });

    test('请求体上限写成一页纸大小 ⇒ 报（闸比正文还小＝合法通知永远 413）', () {
      final broken = mutate((raw) {
        (raw['limits'] as Map<String, Object?>)['requestBodyMaxBytes'] = 1024;
      });
      expectProblem(
        broken,
        'requestBodyMaxBytes',
        '公网面没有可信的体积闸，或闸小到收不下一条正常通知，都是配错了',
      );
    });

    test('413 与 429 撞成同一个码 ⇒ 报（客户端分不清该退避还是该缩正文）', () {
      final broken = mutate((raw) {
        (raw['statusCodes'] as Map<String, Object?>)['requestTooLarge'] = 429;
      });
      expectProblem(broken, '同步状态码有重复值', '两个不同结论共用一个码＝等于没有结论');
    });

    // #130-A4：突增告警。这一段真正会写歪的不是数字大小，而是"它管谁"和"它持不持久"。
    test('alerts 段整段缺失 ⇒ 报（实现只剩两种走法：自己写一份缺省，或者静默不告警）', () {
      final broken = mutate((raw) {
        raw.remove('alerts');
      });
      expectProblem(broken, 'alerts 段缺失', '读不到就该判红，不是当作"没这回事"');
    });

    test('nearQuotaRatio=1 ⇒ 报（那就是 denied 的另一种写法，near 的意义是"还没拒"）', () {
      final broken = mutate((raw) {
        (raw['alerts'] as Map<String, Object?>)['nearQuotaRatio'] = 1;
      });
      expectProblem(broken, 'nearQuotaRatio 必须在', '开区间外的阈值让 near 失去存在意义');
    });

    test('nearQuotaRatio=0 ⇒ 报（每一发都算告警＝洪水替攻击者把列表刷满）', () {
      final broken = mutate((raw) {
        (raw['alerts'] as Map<String, Object?>)['nearQuotaRatio'] = 0;
      });
      expectProblem(broken, 'nearQuotaRatio 必须在', '零阈值等于不设阈值，而设了个看起来有值的数更糟');
    });

    test('冷却短于一分钟 ⇒ 报（告警的输出速率与请求速率成正比＝第二种洪水）', () {
      final broken = mutate((raw) {
        (raw['alerts'] as Map<String, Object?>)['cooldownSeconds'] = 5;
      });
      expectProblem(broken, 'cooldownSeconds 必须 ≥ 60', '没冷却的告警会自己变成攻击面');
    });

    test('内存环上限为 0 ⇒ 报（主体来自外部输入，无界＝挂在公网上的一段内存）', () {
      final broken = mutate((raw) {
        (raw['alerts'] as Map<String, Object?>)['maxActiveAlerts'] = 0;
      });
      expectProblem(broken, 'maxActiveAlerts 必须是正整数', '无界内存是这批限流要防的东西之一');
    });

    test('persistToDisk=true ⇒ 报（公网面每次写盘都是一个请求换一次磁盘写的放大器）', () {
      final broken = mutate((raw) {
        (raw['alerts'] as Map<String, Object?>)['persistToDisk'] = true;
      });
      expectProblem(broken, 'persistToDisk 必须是 false', '本仓两处已对同一形状做过同一条取舍');
    });

    test('subjectKinds 少了 device ⇒ 报（按设备计额那两档的告警会被安静丢掉）', () {
      final broken = mutate((raw) {
        (raw['alerts'] as Map<String, Object?>)['subjectKinds'] = ['ip'];
      });
      expectProblem(broken, '必须含 device', '最容易把正常用户拦住的正是这一类');
    });

    test('subjectKinds 少了 ip ⇒ 报（身份未证明那一档只能按 IP 计，看不见它就没有洪水证据）', () {
      final broken = mutate((raw) {
        (raw['alerts'] as Map<String, Object?>)['subjectKinds'] = ['device'];
      });
      expectProblem(broken, '必须含 ip', '反代后"同一个出口后面有多少台"全靠这一类');
    });

    test('subjectKinds 重叠 ⇒ 报（同一类主体两个名字＝两份计数器）', () {
      final broken = mutate((raw) {
        (raw['alerts'] as Map<String, Object?>)['subjectKinds'] = [
          'device',
          'device',
        ];
      });
      expectProblem(broken, '不许重叠', '重叠名单是本仓反复判红的那一类');
    });

    test('subjectKinds 写了实现不产出的名字 ⇒ 报（名单看着齐全，告警永远少一类）', () {
      final broken = mutate((raw) {
        (raw['alerts'] as Map<String, Object?>)['subjectKinds'] = [
          'device',
          'ip',
          'sender',
        ];
      });
      expectProblem(broken, '不是服务端认识的种类', '名字写错的方向是静默，不是报错');
    });

    test('仓库里这份契约的 alerts 四个数读得出来（两端同一口径的正向证据）', () {
      expect(c.at(const ['alerts', 'nearQuotaRatio']), isA<num>());
      expect((c.at(const ['alerts', 'nearQuotaRatio']) as num) > 0, isTrue);
      expect((c.at(const ['alerts', 'nearQuotaRatio']) as num) < 1, isTrue);
      expect(
        c.intOf(const ['alerts', 'cooldownSeconds']),
        greaterThanOrEqualTo(60),
      );
      expect(c.intOf(const ['alerts', 'maxActiveAlerts']), greaterThan(0));
      expect(c.boolOf(const ['alerts', 'persistToDisk']), isFalse);
      expect(
        c.strings(const ['alerts', 'subjectKinds']),
        containsAll(['device', 'ip']),
      );
    });

    // #130-A2：按发送方计的那一档。两条判据都是这一片真正在守的东西。
    test('已证明身份的端点漏出"按设备计"的名单 ⇒ 报（它只能被按 IP 计＝共用一份配额）', () {
      final broken = mutate((raw) {
        (raw['limits'] as Map<String, Object?>)['perSenderOnly'] = [
          'pairArm',
          'pair',
          'message',
        ];
      });
      expectProblem(
        broken,
        'clientEvents.pairConfirm',
        'pairConfirm 的签名已经能证明是谁，按 IP 计等于让同一出口后面的设备共用配额',
      );
    });

    test('按设备那档被收到比匿名那档还紧 ⇒ 报（先卡住的是自己人）', () {
      final broken = mutate((raw) {
        (raw['limits'] as Map<String, Object?>)['perSenderPerMinute'] = 5;
      });
      expectProblem(
        broken,
        '不许比按 IP 的',
        '这一档是"跑飞保护"不是反垃圾；比匿名档紧，第一个挨打的是已证明身份的设备',
      );
    });

    // #130-A5：运维入口。这一段真正会写歪的是"档位名的第二份真值"和"确认压在哪一类动作上"。
    test('档位名指向状态表外的一档 ⇒ 报（写进去没人认得，比写不进去更难查）', () {
      final broken = mutate((raw) {
        (raw['revocation'] as Map<String, Object?>)['revokedStatus'] =
            'deleted';
      });
      expectProblem(broken, '必须是 deviceStatuses 表上的一个', '状态词汇表外的名字是一条静默的孤儿');
    });

    test('缺 frozenStatus ⇒ 报（冻结与解冻成对，少一个就有一侧只能靠猜）', () {
      final broken = mutate((raw) {
        (raw['revocation'] as Map<String, Object?>).remove('frozenStatus');
      });
      expectProblem(broken, '必须是 deviceStatuses 表上的一个', '缺的名字必须点名，不许默默落进某个缺省');
    });

    test('两个动作写进同一档 ⇒ 报（吊销与"待重建"在记录上分不开）', () {
      final broken = mutate((raw) {
        (raw['revocation'] as Map<String, Object?>)['revokedStatus'] =
            'awaitingRepair';
      });
      expectProblem(broken, '互不相同', '后续完全相反的两件事不许长成同一行');
    });

    test('解冻的去处不在投递白名单里 ⇒ 报（解完冻仍然一条都投不进去）', () {
      final broken = mutate((raw) {
        (raw['revocation'] as Map<String, Object?>)['resumableStatus'] =
            'frozen';
      });
      expectProblem(broken, '必须就是 deliveryAllowedStatuses', '解冻必须回到允许投递那一档');
    });

    test('已吊销那一档出现在投递白名单里 ⇒ 报（吊销了却还收得到）', () {
      final broken = mutate((raw) {
        (raw['revocation'] as Map<String, Object?>)['deliveryAllowedStatuses'] =
            ['active', 'revoked'];
      });
      expectProblem(broken, '不许出现在 deliveryAllowedStatuses', '白名单里混进被停用的档位');
    });

    test('确认名单为空 ⇒ 报（回不去的那一类动作挂在一次误点上）', () {
      final broken = mutate((raw) {
        (raw['ops'] as Map<String, Object?>)['confirmationRequiredFor'] = [];
      });
      expectProblem(broken, '必须非空且无重复', '一个都不要求确认就是没有确认这回事');
    });

    test('确认名单里有重复项 ⇒ 报（同一个动作两条判据，谁生效取决于实现顺序）', () {
      final broken = mutate((raw) {
        (raw['ops'] as Map<String, Object?>)['confirmationRequiredFor'] = [
          'revoke',
          'revoke',
          'revokeAll',
        ];
      });
      expectProblem(broken, '必须非空且无重复', '重叠名单在本仓反复判红，这里不能因为它"看起来只是多写一遍"就放过');
    });

    test('支持一键全部失效却不要求确认 ⇒ 报（这条交叉判据是本片真正的收获）', () {
      final broken = mutate((raw) {
        (raw['ops'] as Map<String, Object?>)['confirmationRequiredFor'] = [
          'revoke',
          'rebuildInvalidation',
        ];
      });
      expectProblem(
        broken,
        '就必须把它列进 confirmationRequiredFor',
        'massRevokeSupported 与确认名单必须对得上',
      );
    });

    test('把 freeze 也压进确认名单 ⇒ 报（可即时撤销的动作不该消耗注意力）', () {
      final broken = mutate((raw) {
        (raw['ops'] as Map<String, Object?>)['confirmationRequiredFor'] = [
          'freeze',
          'revoke',
          'revokeAll',
        ];
      });
      expectProblem(broken, 'freeze / resume 不许要求确认', '确认疲劳会让人连该确认的那一下也一并点掉');
    });

    test('列状态没有上限 ⇒ 报（管理面成了"一次拉走整张设备表"的机器）', () {
      final broken = mutate((raw) {
        (raw['ops'] as Map<String, Object?>)['listMaxRows'] = 0;
      });
      expectProblem(broken, 'listMaxRows 必须是正整数', '0 不是"不限"，是配错了');
    });

    test('列状态上限大过设备表上限 ⇒ 报（那条限制本身没意义，还会骗人列表是全的）', () {
      final broken = mutate((raw) {
        (raw['ops'] as Map<String, Object?>)['listMaxRows'] = 999999;
      });
      expectProblem(broken, '不许大于 limits.devicesMax', '超过表上限的上限只会造成误读');
    });

    test('仓库里这份契约的运维段读得出来，且四个档位名互不相同', () {
      final names = [
        c.str(const ['revocation', 'revokedStatus']),
        c.str(const ['revocation', 'frozenStatus']),
        c.str(const ['revocation', 'resumableStatus']),
        c.str(const ['revocation', 'afterRebuildStatus']),
      ];
      expect(names.toSet().length, names.length);
      expect(
        c.strings(const ['ops', 'confirmationRequiredFor']),
        contains('revokeAll'),
      );
      expect(c.intOf(const ['ops', 'listMaxRows']), greaterThan(0));
    });

    // T38：接入端点。这一段最值得钉的是"缺省值朝哪个方向"与"日志字段里有什么"。
    test('endpoint 段整段缺失 ⇒ 报（上限与日志形状没有第二个来源）', () {
      final broken = mutate((raw) {
        raw.remove('endpoint');
      });
      expectProblem(
        broken,
        'endpoint.statuses 必须正好是 active 与 revoked',
        '整段不在时，第一条读不到的判据必须点名，而不是让实现各写一份缺省',
      );
    });

    test('usableStatus 与 revokedStatus 同名 ⇒ 报（"能不能用"这个判定失去两个取值）', () {
      final broken = mutate((raw) {
        (raw['endpoint'] as Map<String, Object?>)['revokedStatus'] = 'active';
      });
      expectProblem(broken, '必须都在 statuses 上且互不相同', '同名等于吊销与在册长成一行');
    });

    test('usableStatus 不在 statuses 上 ⇒ 报（名字漂在表外，没有任何代码认得它）', () {
      final broken = mutate((raw) {
        (raw['endpoint'] as Map<String, Object?>)['usableStatus'] = 'pending';
      });
      expectProblem(broken, '必须都在 statuses 上且互不相同', '映射到不存在的东西上＝静默放行');
    });

    test('端点状态多出第三档 ⇒ 报（多一档就多一次「被吊销的端点还在收信」）', () {
      final broken = mutate((raw) {
        (raw['endpoint'] as Map<String, Object?>)['statuses'] = [
          'active',
          'revoked',
          'snoozed',
        ];
      });
      expectProblem(
        broken,
        'endpoint.statuses 必须正好是 active 与 revoked',
        '第三档没有定义"算不算能用"',
      );
    });

    test('端点上限为 0 ⇒ 报（一个都创建不了与"没配"在现场看起来一样）', () {
      final broken = mutate((raw) {
        (raw['endpoint'] as Map<String, Object?>)['perDeviceMax'] = 0;
      });
      expectProblem(broken, '必须是正整数', '0 不是"不限"');
    });

    test('每台上限大过全局上限 ⇒ 报（那条限制永远不会生效，却让人以为它管着什么）', () {
      final broken = mutate((raw) {
        (raw['endpoint'] as Map<String, Object?>)['perDeviceMax'] = 900;
        (raw['endpoint'] as Map<String, Object?>)['globalMax'] = 500;
      });
      expectProblem(broken, '不许大于 globalMax', '永不生效的上限是假的安全感');
    });

    test('轮换宽限为 0 ⇒ 报（换钥匙那一刻所有集成同时 401，从此没人换口令）', () {
      final broken = mutate((raw) {
        (raw['endpoint'] as Map<String, Object?>)['rotation'] = {
          'graceSeconds': 0,
        };
      });
      expectProblem(broken, '至少 60 秒', '短于一次运维操作的宽限等于没有宽限');
    });

    test('轮换宽限超过一天 ⇒ 报（宽限越长，被拖走的旧口令还能用的窗口也越长）', () {
      final broken = mutate((raw) {
        (raw['endpoint'] as Map<String, Object?>)['rotation'] = {
          'graceSeconds': 86401,
        };
      });
      expectProblem(broken, '不许超过一天', '这是取舍，不是可以无限给的好事');
    });

    test('空 IP 名单意味着"谁都拒" ⇒ 报（缺省必须朝"没配也能跑"那一侧）', () {
      final broken = mutate((raw) {
        (raw['endpoint'] as Map<String, Object?>)['ipAllowlistEmptyMeans'] =
            'none';
      });
      expectProblem(broken, '只能是 any', '否则表现是"口令对却全 401"，看起来像服务端坏了');
    });

    test('IP 不匹配给出不同结论 ⇒ 报（这个入口就成了"哪个 IP 被允许"的探针）', () {
      final broken = mutate((raw) {
        (raw['endpoint'] as Map<String, Object?>)['ipMismatchOutcome'] =
            'distinct';
      });
      expectProblem(broken, '必须是 same-as-bad-secret', '同形在这里是防枚举，不是洁癖');
    });

    test('postOnly 的拒绝码不是 4xx ⇒ 报（500 会让客户端以为可以重试）', () {
      final broken = mutate((raw) {
        (raw['endpoint'] as Map<String, Object?>)['postOnlyMethodStatus'] = 500;
      });
      expectProblem(broken, '必须是 4xx', '方式不对是请求的问题，不是服务端的');
    });

    test('postOnly 的码与既有状态码撞车 ⇒ 报（两个结论共用一个码＝等于没有结论）', () {
      final broken = mutate((raw) {
        (raw['endpoint'] as Map<String, Object?>)['postOnlyMethodStatus'] = 429;
      });
      expectProblem(broken, '与 statusCodes 里的某个码重复', '客户端只能猜');
    });

    test('调用日志上限为 0 ⇒ 报（无界日志就是攻击者驱动的存储）', () {
      final broken = mutate((raw) {
        (raw['endpoint'] as Map<String, Object?>)['callLog'] = {
          'maxPerEndpoint': 0,
          'fields': ['at', 'ip', 'outcome'],
        };
      });
      expectProblem(broken, '必须是 1–1000 的整数', '日志是洪水最容易打到的那一项');
    });

    test('调用日志字段里有正文 ⇒ 报（auditStoresMetadataOnly 直接成空话）', () {
      final broken = mutate((raw) {
        (raw['endpoint'] as Map<String, Object?>)['callLog'] = {
          'maxPerEndpoint': 50,
          'fields': ['at', 'ip', 'body'],
        };
      });
      expectProblem(broken, 'endpoint.callLog.fields 里出现了 body', '中转服务器不留正文');
    });

    test('调用日志字段里有 url ⇒ 报（端点口令就在路径段里）', () {
      final broken = mutate((raw) {
        (raw['endpoint'] as Map<String, Object?>)['callLog'] = {
          'maxPerEndpoint': 50,
          'fields': ['at', 'url'],
        };
      });
      expectProblem(
        broken,
        'endpoint.callLog.fields 里出现了 url',
        '记 url 等于把口令写进日志',
      );
    });

    test('仓库里这份契约的端点段读得出来（正向证据）', () {
      expect(c.strings(const ['endpoint', 'statuses']).length, 2);
      expect(c.str(const ['endpoint', 'usableStatus']), isNotNull);
      expect(c.str(const ['endpoint', 'ipAllowlistEmptyMeans']), 'any');
      expect(
        c.intOf(const ['endpoint', 'rotation', 'graceSeconds']),
        greaterThanOrEqualTo(60),
      );
      expect(
        c.strings(const ['endpoint', 'callLog', 'fields']),
        contains('outcome'),
      );
    });

    // T39/T40/T41：端点收单那两条入口。这一段的方向性判据一条都不能少 —— 它们拦的不是
    // "键在不在"，而是"缺省朝哪一侧"（口令放 query、允许外部指定 target、明文默认允许，
    // 三个写反了都不报错，只是把长期口令与整台实例的安静交出去）。
    test('ingress 整段缺失 ⇒ 报（配额与长度上限没有第二个来源）', () {
      final broken = mutate((raw) {
        (raw['endpoint'] as Map<String, Object?>).remove('ingress');
      });
      expectProblem(broken, 'endpoint.ingress 必须存在', '缺段时两份实现会各猜一套配额与放法');
    });

    test('日额度不大于分钟额度 ⇒ 报（正常用一天会被自己的配额拦住）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['ingress']
            as Map<String, Object?>)['quota'] = {
          'perMinute': 15,
          'perDay': 5,
        };
      });
      expectProblem(broken, '日额度必须大于分钟额度', '次序反了的那条限制永远在拦自己人');
    });

    test('配额里有一个数不是正整数 ⇒ 报（0 与"没配"在现场看起来一样）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['ingress']
            as Map<String, Object?>)['quota'] = {
          'perMinute': 0,
          'perDay': 500,
        };
      });
      expectProblem(broken, 'quota 两个数必须是正整数', '没有配额的收单入口就是公网上的无闸机');
    });

    test('正文字符上限大过字节闸 ⇒ 报（那条限制本身不存在）', () {
      final broken = mutate((raw) {
        final byteMax =
            (raw['limits'] as Map<String, Object?>)['requestBodyMaxBytes']
                as int;
        ((raw['endpoint'] as Map<String, Object?>)['ingress']
                as Map<String, Object?>)['maxBodyChars'] =
            byteMax + 1;
      });
      expectProblem(
        broken,
        'maxBodyChars',
        '字符数上限比字节闸还宽＝这道限制不生效，而读契约的人以为它管着什么',
      );
    });

    test('口令不在 pathPattern 的最后一段 ⇒ 报（放法一旦有两种，脱敏就只盖住那一种）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['ingress']
                as Map<String, Object?>)['pathPattern'] =
            '/api/fnthink/p/:secret/:endpointId';
      });
      expectProblem(
        broken,
        '必须以 :secret 作最后一段',
        '口令的位置只由 transport.secretPlacement 说一次，这里查的是形状：尾段之外都会多出一种放法',
      );
    });

    test('允许外部指定投递目标 ⇒ 报（一把口令泄露换成骚扰全部设备）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['ingress']
                as Map<String, Object?>)['maySpecifyTarget'] =
            true;
      });
      expectProblem(broken, '必须把投递目标锁在', 'target 只能来自端点记录所属那台设备');
    });

    test('投递目标换了出处 ⇒ 报（同一条判据的另一半：从请求里读 target）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['ingress']
                as Map<String, Object?>)['targetSource'] =
            'request-field';
      });
      expectProblem(
        broken,
        '必须把投递目标锁在',
        'targetSource 与 maySpecifyTarget 是一个决定的两面，只查一半会漏',
      );
    });

    test('明文传输默认允许 ⇒ 报（HTTPS-only 是承诺不是建议）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['ingress']
                as Map<String, Object?>)['insecureTransport'] =
            'allow';
      });
      expectProblem(broken, 'insecureTransport 只能是 reject', '逃生阀在环境变量里，不在契约里');
    });

    test('收单路径落在脱敏规则之外 ⇒ 报（口令进 access log）', () {
      final broken = mutate((raw) {
        final ingress =
            (raw['endpoint'] as Map<String, Object?>)['ingress']
                as Map<String, Object?>;
        ingress['pathPattern'] = '/api/fnthink/endpoint/:endpointId/:secret';
        ingress['postBearerPath'] = '/api/fnthink/endpoint/:endpointId';
      });
      expectProblem(
        broken,
        '必须落在 transport.accessLogRedactPathPattern',
        '脱敏规则盖不住这个路径，口令就进了别人的日志',
      );
    });

    test('只有 GET 形态那条落在脱敏前缀之外 ⇒ 报（口令在路径段的那条）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['ingress']
                as Map<String, Object?>)['pathPattern'] =
            '/api/fnthink/endpoint/:endpointId/:secret';
      });
      expectProblem(
        broken,
        '必须落在 transport.accessLogRedactPathPattern',
        '两个项各拦一条形状：只查 postBearerPath 等于 GET 那条没人管，而它才是口令真在 URL 里的那条',
      );
    });

    test('只有 POST 形态那条落在脱敏前缀之外 ⇒ 报（两条都要盖住）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['ingress']
                as Map<String, Object?>)['postBearerPath'] =
            '/api/fnthink/endpoint/:endpointId';
      });
      expectProblem(
        broken,
        '必须落在 transport.accessLogRedactPathPattern',
        '一条判据管两条形状：只查 pathPattern 等于另一半没人管，而泄露的是 Bearer 那条的口令',
      );
    });

    test('POST 形态的路径里也带 :secret ⇒ 报（一种放法说成两种）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['ingress']
                as Map<String, Object?>)['postBearerPath'] =
            '/api/fnthink/p/:endpointId/:secret';
      });
      expectProblem(
        broken,
        'postBearerPath 不许带它',
        '那条形状的口令在 Authorization 里，写进路径就等于同时支持两种放法',
      );
    });

    test('路径里出现 query ⇒ 报（"只进路径段"当场失效）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['ingress']
                as Map<String, Object?>)['pathPattern'] =
            '/api/fnthink/p/:endpointId?secret=:secret';
      });
      expectProblem(broken, '不许出现 query', '口令一旦能进 query，脱敏与路径段这两句都作废');
    });

    test('能力拒绝的词不在回执表里 ⇒ 报（对外发明第九个词）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['ingress']
                as Map<String, Object?>)['rejectedCapabilityReceipt'] =
            'nope_not_a_receipt';
      });
      expectProblem(broken, '必须是 receipts 里的一个词', '回执词表只有一份，实现里不许再造');
    });

    test('能力拒绝的词合法但与 capabilities 那边不同名 ⇒ 报（同一个拒绝两种说法）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['ingress']
                as Map<String, Object?>)['rejectedCapabilityReceipt'] =
            'failed_action';
      });
      expectProblem(broken, '必须是 receipts 里的一个词', '两个出处指同一个拒绝时，必须逐字节同名');
    });

    // ── endpoint.probe（T106 片①b：端点档的干跑）──
    // 这一段在设备侧还没有读口（接线是片①b 格2），但**判据必须先落地**：路径形状与口令放法
    // 一旦由服务端单方面定下来，客户端下一次就只能顺着它拼 URL —— 那正是 T87 那条"别重打路径"的债。
    test('缺 endpoint.probe 整段 ⇒ 报（干跑的路径与策略没有第二个来源）', () {
      final broken = mutate((raw) {
        (raw['endpoint'] as Map<String, Object?>).remove('probe');
      });
      expectProblem(
        broken,
        'endpoint.probe.bearerPath',
        '缺段读回来是空串，而空串落在脱敏前缀之外 ⇒ 必须报，不许"没有就不判"',
      );
    });

    test('探针路径落在脱敏前缀之外 ⇒ 报（这一条与口令同面）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['probe']
                as Map<String, Object?>)['bearerPath'] =
            '/api/fnthink/endpoint-probe';
      });
      expectProblem(
        broken,
        '必须落在 transport.accessLogRedactPathPattern',
        '脱敏规则盖不住这一条，就是让探针与收单各用一套日志口径',
      );
    });

    test('探针路径里出现 :secret ⇒ 报（口令进 URL，而它会被反复自动打）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['probe']
                as Map<String, Object?>)['bearerPath'] =
            '/api/fnthink/p/:endpointId/:secret/probe';
      });
      expectProblem(
        broken,
        'endpoint.probe.bearerPath',
        '探针的口令在请求头里是它能被自动重探反复打的前提',
      );
    });

    test('探针尾段是参数 ⇒ 报（会与收单的 :secret 撞位，而 Express 按注册顺序匹配）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['probe']
                as Map<String, Object?>)['bearerPath'] =
            '/api/fnthink/p/:endpointId/:mode';
      });
      expectProblem(broken, '固定字面量', '撞位之后探针打到收单那条并回 401，看起来像"口令错了"');
    });

    test('探针路径不在 postBearerPath 之下 ⇒ 报（多插一层参数就换了识别主键）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['probe']
                as Map<String, Object?>)['bearerPath'] =
            '/api/fnthink/p/probe/:endpointId';
      });
      expectProblem(
        broken,
        '固定字面量',
        '这一条管的是"探针与收单认同一个 endpointId 位"，尾段字面量只是它的表象',
      );
    });

    test('口令放法改成 path-segment ⇒ 报（改向不会静默生效）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['probe']
                as Map<String, Object?>)['secretPlacement'] =
            'path-segment';
      });
      expectProblem(broken, 'bearer-header', '契约写了放法而实现读另一套，就是两份真值');
    });

    test('探针改成写调用日志 ⇒ 报（有界日志会被自动重探把自己观察的历史挤掉）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['probe']
                as Map<String, Object?>)['writesCallLog'] =
            true;
      });
      expectProblem(
        broken,
        'writesCallLog 只能是 false',
        '那份日志回答的是「为什么那条没到」，而探针不是一条「那一条」',
      );
    });

    test('chargesIngressQuota 少了 ⇒ 报（这件取舍必须写下来，不许留空）', () {
      final broken = mutate((raw) {
        ((raw['endpoint'] as Map<String, Object?>)['probe']
                as Map<String, Object?>)
            .remove('chargesIngressQuota');
      });
      expectProblem(broken, '必须是布尔', '健康监测花不花被监测那条路的额度，是实现里顺手一个 if 说不出理由的那一类');
    });

    test('判据自证：当前契约这一段一条都不报，且四条键都读得回来', () {
      expect(c.validate(), isEmpty);
      final probe =
          (c.raw['endpoint'] as Map<String, Object?>)['probe']
              as Map<String, Object?>;
      expect(probe['bearerPath'], '/api/fnthink/p/:endpointId/probe');
      expect(probe['secretPlacement'], 'bearer-header');
      expect(probe['chargesIngressQuota'], false);
      expect(probe['writesCallLog'], false);
    });

    // ── transport.apiPaths（#126 第二片：客户端发到哪个 URL 的唯一出处）──
    test('apiPaths 整段缺失 ⇒ 报（路径不能两边各拼一份）', () {
      final broken = mutate((raw) {
        (raw['transport'] as Map<String, Object?>).remove('apiPaths');
      });
      expectProblem(
        broken,
        'transport.apiPaths 必须非空',
        '设备面路径没有第二个来源，缺段就是让两份实现各猜一次',
      );
    });

    test('少一种事件的路径 ⇒ 报（漏的那个客户端发不出去）', () {
      final broken = mutate((raw) {
        (raw['transport'] as Map<String, Object?>)['apiPaths'] = {
          ...(raw['transport'] as Map<String, Object?>)['apiPaths']
              as Map<String, Object?>,
        }..remove('ack');
      });
      expectProblem(broken, '必须覆盖每一种设备签名事件', '少一行配置在两边各拼一份的实现里是完全看不见的');
    });

    test('apiPaths 里多一个不是事件种类的键 ⇒ 报（这条路径没人挂）', () {
      final broken = mutate((raw) {
        (raw['transport'] as Map<String, Object?>)['apiPaths'] = {
          ...(raw['transport'] as Map<String, Object?>)['apiPaths']
              as Map<String, Object?>,
          'debugPeek': '/api/fnthink/debug-peek',
        };
      });
      expectProblem(
        broken,
        '不属于 clientEvents 的键',
        '声明了一条没人挂的路径，比少一条更容易被当成"服务端还支持这个"',
      );
    });

    test('路径不在 /api/fnthink/ 前缀之下 ⇒ 报（前缀是反代与脱敏都依赖的那一段）', () {
      final broken = mutate((raw) {
        (raw['transport'] as Map<String, Object?>)['apiPaths'] = {
          ...(raw['transport'] as Map<String, Object?>)['apiPaths']
              as Map<String, Object?>,
          'poll': '/fnthink/poll',
        };
      });
      expectProblem(
        broken,
        '必须是 /api/fnthink/ 下的纯路径',
        '换了前缀就是换了门，而两边各拼一份时没人会发现',
      );
    });

    test('路径写成带 query ⇒ 报（口令类参数进 query 正是本协议禁的事）', () {
      final broken = mutate((raw) {
        (raw['transport'] as Map<String, Object?>)['apiPaths'] = {
          ...(raw['transport'] as Map<String, Object?>)['apiPaths']
              as Map<String, Object?>,
          'poll': '/api/fnthink/poll?source=app',
        };
      });
      expectProblem(broken, '必须是 /api/fnthink/ 下的纯路径', '带 query 等于把参数写进协议路径');
    });

    test('两条事件共用一条路径 ⇒ 报（服务端只能按其中一种裁决）', () {
      final broken = mutate((raw) {
        (raw['transport'] as Map<String, Object?>)['apiPaths'] = {
          ...(raw['transport'] as Map<String, Object?>)['apiPaths']
              as Map<String, Object?>,
          'ack': '/api/fnthink/poll',
        };
      });
      expectProblem(broken, '值有重复', '两个事件同一条路径时，限流与裁决都会静默偏向一边');
    });

    test('端点收单的路径混进 apiPaths ⇒ 报（那张表是设备面，不携带口令）', () {
      final broken = mutate((raw) {
        (raw['transport'] as Map<String, Object?>)['apiPaths'] = {
          ...(raw['transport'] as Map<String, Object?>)['apiPaths']
              as Map<String, Object?>,
          'message':
              ((raw['endpoint'] as Map<String, Object?>)['ingress']
                  as Map<String, Object?>)['postBearerPath'],
        };
      });
      expectProblem(broken, '出现了端点收单的路径', '混表的下一个人会以为设备面也能携带口令');
    });

    test('仓库里这份契约的 apiPaths 与 clientEvents 对得上（正向证据）', () {
      expect(c.apiPaths.containsKey('poll'), isTrue);
      expect(c.apiPaths['ack'], '/api/fnthink/ack');
      expect(c.apiPath('poll'), startsWith('/api/fnthink/'));
      expect(() => c.apiPath('nope'), throwsStateError);
    });

    test('仓库里这份契约的收单段读得出来（正向证据）', () {
      final perMinute = c.intOf(const [
        'endpoint',
        'ingress',
        'quota',
        'perMinute',
      ])!;
      final perDay = c.intOf(const ['endpoint', 'ingress', 'quota', 'perDay'])!;
      expect(perDay, greaterThan(perMinute));
      expect(
        c.str(const ['endpoint', 'ingress', 'targetSource']),
        'owner-device-record',
      );
      expect(
        c.boolOf(const ['endpoint', 'ingress', 'maySpecifyTarget']),
        false,
      );
      expect(
        c.str(const ['endpoint', 'ingress', 'insecureTransport']),
        'reject',
      );
      expect(
        c.str(const ['endpoint', 'ingress', 'pathPattern'])!,
        startsWith(c.str(const ['transport', 'accessLogRedactPathPattern'])!),
      );
      expect(
        c.str(const ['endpoint', 'ingress', 'rejectedCapabilityReceipt']),
        c.str(const ['capabilities', 'endpointActionReceipt']),
      );
    });
  });
}
