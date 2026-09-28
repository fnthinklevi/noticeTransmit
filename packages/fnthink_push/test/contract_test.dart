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
      // 第三片之后 counterpart 这条规则有**两个**使用者（pair 与 pairConfirm），
      // 所以只改一个不会被判出来 —— 这条用例要一起摘掉，才是真的"没人用"。
      final broken = mutate((raw) {
        for (final kind in ['pair', 'pairConfirm']) {
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
      expectProblem(broken, '必须小于 pollIntervalSeconds.min', '比常态还慢的"提频"没有意义');
    });
  });
}
