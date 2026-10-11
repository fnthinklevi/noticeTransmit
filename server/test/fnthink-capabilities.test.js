'use strict';

// 能力清单（T30）的 **Node 侧**向量断言 + 契约对表。Dart 那一半在
// packages/fnthink_push/test/capabilities_test.dart，两边吃同一份
// protocol/fnthink-vectors-v1.json 的 capabilities 段。
//
// 为什么两份都要：裁决有两条实现（设备本地一条、服务端一条）。它们不一致时不会报错，
// 只会变成"设备以为只给了 L1，服务端却按 L2 收"。共享向量就是为了让这种分叉
// 在 CI 里就红，而不是在用户手机上红。

const fs = require('fs');
const os = require('os');
const path = require('path');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-caps', 10);
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-caps-'));

const { loadContract, assertSupported, isReceipt } = require('../lib/fnthink/contract');
const {
  confirmItemVocabulary,
  decideCapability,
  endpointGrant,
  grantItemBareRejected,
  grantItemKind,
  grantItemSeparator,
  grantItemSplit,
  grantFromNode,
  normalizeConfirmItems,
} = require('../lib/fnthink/capabilities');

const contract = assertSupported(loadContract());
const vectors = JSON.parse(
  fs.readFileSync(path.join(__dirname, '..', '..', 'protocol', 'fnthink-vectors-v1.json'), 'utf8'),
);
const CAPS = vectors.capabilities;
// ⚠ 从向量文件读，不在本文件另写一份 —— 此前它与 Dart 的 `_reasonForms` 是两份手抄，
//   一端加词而另一端没加时没有任何守卫会喊。两端现在读同一处。
const REASON_FORMS = vectors._capabilityReasonWords;

function decide(given) {
  return decideCapability(contract, {
    stage: given.stage, // 两段之一；不给就抛（"忘了说自己是哪一段"不许有个默认答案）
    grant: grantFromNode(contract, given.grant),
    type: given.type,
    item: given.item === null || given.item === undefined ? undefined : given.item,
    confirmedThisTime: !!given.confirmedThisTime,
  });
}

describe('能力清单向量（Node 侧，T30-A）', () => {
  test('逐条：allowed 与 reason 都要对上（失败点名到 id）', () => {
    expect(CAPS.length).toBeGreaterThan(0);
    for (const c of CAPS) {
      const got = decide(c.given);
      expect([c.id, got.allowed, got.reason, got.requiresLocalConfirm]).toEqual([
        c.id,
        c.expect.allowed,
        c.expect.reason,
        c.expect.requiresLocalConfirm,
      ]);
    }
  });

  test('实现产出的每个 reason 都在词表里；词表每一形都有用例覆盖', () => {
    const covered = new Set();
    for (const c of CAPS) {
      const reason = decide(c.given).reason;
      if (reason === null) continue;
      const form = REASON_FORMS.find((f) => reason.indexOf(f) === 0);
      expect([c.id, reason, form]).toEqual([c.id, reason, expect.any(String)]);
      covered.add(form);
      expect([c.id, c.expect.reason]).toEqual([c.id, reason]);
    }
    expect([...covered].sort()).toEqual([...REASON_FORMS].sort());
  });

  test('契约的 type 词表 = 向量用到的 type（新增一档却不补向量 ⇒ 红）', () => {
    const declared = Object.keys(contract.capabilities.messageTypes);
    const used = new Set(CAPS.map((c) => c.given.type));
    expect(declared.filter((t) => !used.has(t))).toEqual([]);
    for (const ghost of ['teleport', 'Notice']) expect(declared.includes(ghost)).toBe(false);
  });

  test('每一条 messageTypes 的 minLevel 都是 levels 里的一档（词表自洽）', () => {
    const levels = contract.capabilities.levels;
    for (const [type, spec] of Object.entries(contract.capabilities.messageTypes)) {
      expect([type, spec.minLevel]).toEqual([type, expect.stringMatching(/^L\d$/)]);
      expect(levels.includes(spec.minLevel)).toBe(true);
    }
    // 每一档都得有 type 能进，否则那档是死档（配对了却什么都发不出来）
    expect(
      new Set(Object.values(contract.capabilities.messageTypes).map((s) => s.minLevel)),
    ).toEqual(new Set(levels));
  });

  test('能力拒绝用的回执在契约 receipts 里（不是随手起的名）', () => {
    expect(isReceipt(contract, 'rejected_capability')).toBe(true);
  });

  // #131 第三片：授权住在被投那台的 grantsBy 里，每一项**就是**这份节点
  //（旧版还有一层 `grantFromRecord(record)` 去读 `record.grant`，那既是第二份形状也是死路）。
  test('grantFromNode：节点里没有 maxLevel ⇒ 按缺省档；有 ⇒ 逐项读', () => {
    expect(grantFromNode(contract, null).maxLevel).toBe(
      contract.capabilities.grantDefaults.maxLevel,
    );
    expect(grantFromNode(contract, null).items).toEqual([]);
    const rec = { maxLevel: 'L2', items: ['app:a/b', ''], revision: '3' };
    const got = grantFromNode(contract, rec);
    expect(got.maxLevel).toBe('L2');
    expect(got.items).toEqual(['app:a/b']); // 空串不算一项
    expect(got.revision).toBe(3);
  });

  test('stage 不许有默认值：没说哪一段就抛', () => {
    expect(() =>
      decideCapability(contract, { grant: { maxLevel: 'L3', items: [] }, type: 'notice' }),
    ).toThrow(/哪一段/);
    expect(() =>
      decideCapability(contract, {
        stage: 'whatever',
        grant: { maxLevel: 'L3', items: [] },
        type: 'notice',
      }),
    ).toThrow(/哪一段/);
  });

  test('端点走同一个裁决函数：契约说它只能产 L1，动作就归到 rejected_capability 那一类', () => {
    const g = endpointGrant(contract);
    expect(g.maxLevel).toBe(contract.capabilities.endpointMaxLevel);
    expect(g.items).toEqual([]);
    expect(
      decideCapability(contract, { stage: 'intake', grant: g, type: 'action', item: 'app:a/b' })
        .reason,
    ).toBe('level:L2');
    expect(decideCapability(contract, { stage: 'intake', grant: g, type: 'notice' }).allowed).toBe(
      true,
    );
  });

  test('裁决不吃"外部传来的 maxLevel"：只有记录里的 grant 能放大权限', () => {
    // 攻击面：请求体里塞一个 grant。decideCapability 只认调用方递进来的那个，
    // 而调用方（verify）递的是**设备表里读出来的**那一份。
    const smuggled = { maxLevel: 'L3', items: ['setting:whatever'] };
    const stored = grantFromNode(contract, null); // 关系里没写档位 ⇒ 缺省 L1
    expect(
      decideCapability(contract, {
        stage: 'apply',
        grant: stored,
        type: 'setting',
        item: 'setting:whatever',
        confirmedThisTime: true,
      }).allowed,
    ).toBe(false);
    expect(smuggled.maxLevel).toBe('L3'); // 它自己没被采纳，只是躺在参数里
  });
});

// ── T134 片2：配对同意那一屏的勾选表 —— 取值域与归一化（裁决函数本身不动，见上面的向量组）──
describe('confirmItemVocabulary / normalizeConfirmItems（T134 片2）', () => {
  test('取值域从契约那两张词表现取：名单与键控表两种形状都要认出来', () => {
    const vocabulary = confirmItemVocabulary(contract);
    // 期望值不从"被量的那个函数"算出来（那样两边一起错就永远绿）：这里直接读契约的两处。
    expect(vocabulary).toContain('alert:ring'); // capabilities.l2.actions 是名单
    expect(vocabulary).toContain('notification'); // capabilities.l3.settings 是键控表：键名才是 item
    expect(vocabulary).toHaveLength(
      contract.capabilities.l2.actions.length +
        Object.keys(contract.capabilities.l3.settings).length,
      // 只认名单的那份写法会把 l3 整张表读成空 ⇒ 少六项，而"少的那六项"在界面上就是没勾。
    );
    // 排好序且无重复：表里那一份是一个集合，两个写法会让比对时输时赢。
    expect(vocabulary).toEqual(vocabulary.slice().sort());
    expect(new Set(vocabulary).size).toBe(vocabulary.length);
  });

  test('itemsVocabularyFrom 指空 / 指错 ⇒ 抛，不读成"没有任何一项能勾"', () => {
    const empty = JSON.parse(JSON.stringify(contract));
    empty.clientEvents.pairConfirm.itemsVocabularyFrom = [];
    expect(() => confirmItemVocabulary(empty)).toThrow(/必须是非空名单/);
    const wrong = JSON.parse(JSON.stringify(contract));
    wrong.clientEvents.pairConfirm.itemsVocabularyFrom = ['capabilities.nope'];
    expect(() => confirmItemVocabulary(wrong)).toThrow(/既不是非空名单也不是非空键控表/);
    const mapWrong = JSON.parse(JSON.stringify(contract));
    mapWrong.clientEvents.pairConfirm.itemsVocabularyFrom = ['capabilities.l3.settings.mode'];
    expect(() => confirmItemVocabulary(mapWrong)).toThrow(/既不是非空名单也不是非空键控表/);
  });

  test('归一化：去重、排序、词表外点名到哪一项', () => {
    expect(normalizeConfirmItems(contract, ['notification', 'alert:ring', 'notification'])).toEqual(
      { items: ['alert:ring', 'notification'] },
    );
    expect(normalizeConfirmItems(contract, [])).toEqual({ items: [] });
    expect(normalizeConfirmItems(contract, [' alert:ring '])).toEqual({ items: ['alert:ring'] });
    expect(normalizeConfirmItems(contract, ['wipe_everything'])).toEqual({
      reason: 'unknown-item:wipe_everything',
    });
  });

  test('形状那三种各有各的理由，不许合成一句"清单不对"', () => {
    expect(normalizeConfirmItems(contract, 'alert:ring')).toEqual({ reason: 'items-not-array' });
    expect(normalizeConfirmItems(contract, null)).toEqual({ reason: 'items-not-array' });
    expect(normalizeConfirmItems(contract, ['alert:ring', 7])).toEqual({
      reason: 'item-not-string',
    });
    expect(normalizeConfirmItems(contract, ['  '])).toEqual({ reason: 'item-empty' });
  });
});
// ── T134 片4：勾选项的整串语法（粒度＝参数级）。四边同片，服务端这一边管"别收下没人能发的串"──
describe('整串语法（T134 片4：itemGrammar / requiresArgumentFrom / reports / channelTargetShape）', () => {
  test('切串那把刀来自契约：分隔符不是写死的斜杠', () => {
    expect(grantItemSeparator(contract)).toBe(
      contract.clientEvents.pairConfirm.itemGrammar.argumentSeparator,
    );
    expect(grantItemSplit(contract, 'channel:toggle/webhook:acme:off')).toEqual({
      base: 'channel:toggle',
      argument: 'webhook:acme:off',
      hasSeparator: true,
    });
    // 名字自己不含分隔符（那一条由 contract.dart 的 validate 钉住），所以"切第一段"是唯一拆法。
    expect(grantItemSplit(contract, 'alert:ring').hasSeparator).toBe(false);
    const other = JSON.parse(JSON.stringify(contract));
    other.clientEvents.pairConfirm.itemGrammar.argumentSeparator = '~';
    expect(grantItemSplit(other, 'app:launch~demo').base).toBe('app:launch');
    // 分隔符写歪 ⇒ 抛，不"退化成按斜杠切"：那会把一整批合法串读成词表外。
    const broken = JSON.parse(JSON.stringify(contract));
    broken.clientEvents.pairConfirm.itemGrammar.argumentSeparator = '//';
    expect(() => grantItemSeparator(broken)).toThrow(/必须是单个字符/);
  });

  test('带参数的整串被收下，裸名字被拒且回的是契约那一句', () => {
    expect(
      normalizeConfirmItems(contract, [
        'channel:toggle/webhook:acme:off',
        'app:launch/demo-shortcut',
      ]),
    ).toEqual({
      items: ['app:launch/demo-shortcut', 'channel:toggle/webhook:acme:off'],
    });
    const rejected = normalizeConfirmItems(contract, ['channel:toggle']);
    expect(rejected).toEqual({
      reason: grantItemBareRejected(contract, 'channel:toggle'),
    });
    expect(rejected.reason).toBe('item-argument-required:channel:toggle');
    // 模板换词 ⇒ 理由跟着换：这句话服务端没有第二份，与设备侧同一句才核对得上。
    const renamed = JSON.parse(JSON.stringify(contract));
    renamed.clientEvents.pairConfirm.itemGrammar.bareNameRejected = 'needs-argument:X';
    expect(grantItemBareRejected(renamed, 'sms:search')).toBe('needs-argument:sms:search');
    const shapeBroken = JSON.parse(JSON.stringify(contract));
    shapeBroken.clientEvents.pairConfirm.itemGrammar.bareNameRejected = 'needs-argument';
    expect(() => grantItemBareRejected(shapeBroken, 'sms:search')).toThrow(/必须是「词:X」形状/);
  });

  test('不要参数的项带了参数 ⇒ unexpected-argument（带个尾斜杠也算带了）', () => {
    expect(normalizeConfirmItems(contract, ['alert:ring/x'])).toEqual({
      reason: 'unexpected-argument:alert:ring',
    });
    // ⚠ 这一条钉的是 `hasSeparator` 与"参数空不空"的区别：`alert:ring/` 的参数段是空串，
    //   只按空串判就会把一格"线上永远发不出的串"签进授权表，而界面上写着已授权。
    expect(normalizeConfirmItems(contract, ['alert:ring/'])).toEqual({
      reason: 'unexpected-argument:alert:ring',
    });
    expect(normalizeConfirmItems(contract, ['alert:ring'])).toEqual({
      items: ['alert:ring'],
    });
  });

  test('词表外点名到**名字**那一段（不是整串），原型链上的名字不算设置项', () => {
    expect(normalizeConfirmItems(contract, ['no-such-item/x'])).toEqual({
      reason: 'unknown-item:no-such-item',
    });
    // `settings` 是解析出来的对象：用 `in` 会让原型上的名字被当成设置项（#130-A 那批同族）。
    for (const smuggled of ['__proto__', 'toString', 'constructor']) {
      expect(normalizeConfirmItems(contract, [smuggled])).toEqual({
        reason: `unknown-item:${smuggled}`,
      });
    }
  });

  test('count / keyword 两种形状各报各的（上下界从契约现取，不抄一份数字）', () => {
    const spec = contract.capabilities.l2.reports['notifications:report'];
    const ok = `notifications:report/${spec.minItems}`;
    expect(normalizeConfirmItems(contract, [ok])).toEqual({ items: [ok] });
    expect(normalizeConfirmItems(contract, ['notifications:report/0'])).toEqual({
      reason: 'bad-report-count:0',
    });
    expect(normalizeConfirmItems(contract, ['notifications:report/abc'])).toEqual({
      reason: 'bad-report-count:abc',
    });
    expect(normalizeConfirmItems(contract, [`notifications:report/${spec.maxItems + 1}`])).toEqual({
      reason: `bad-report-count:${spec.maxItems + 1}`,
    });
    const keyword = contract.capabilities.l2.reports['sms:search'];
    expect(
      normalizeConfirmItems(contract, [`sms:search/${'x'.repeat(keyword.maxChars + 1)}`]),
    ).toEqual({ reason: `bad-keyword:${'x'.repeat(keyword.maxChars + 1)}` });
    // 控制字符：一句话在对面读起来断成两截，而 item 是整串比对的键。
    expect(normalizeConfirmItems(contract, ['sms:search/a\tb'])).toEqual({
      reason: 'bad-keyword:a\tb',
    });
  });

  test('通道目标那一段：段数／族／空 id／目标词四种坏法各有各的拒', () => {
    const shape = contract.capabilities.l2.channelTargetShape;
    const family = shape.families[0];
    expect(normalizeConfirmItems(contract, [`channel:toggle/${family}:acme:off`])).toEqual({
      items: [`channel:toggle/${family}:acme:off`],
    });
    expect(normalizeConfirmItems(contract, [`channel:toggle/${family}:acme`])).toEqual({
      reason: `bad-channel-argument:${family}:acme`,
    });
    // 多一段也要拒（静默取前三段的话，对面拼错一个字符就变成另一条指令）。
    expect(normalizeConfirmItems(contract, [`channel:toggle/${family}:acme:off:extra`])).toEqual({
      reason: `bad-channel-argument:${family}:acme:off:extra`,
    });
    expect(normalizeConfirmItems(contract, ['channel:toggle/sms:acme:off'])).toEqual({
      reason: 'bad-channel-argument:sms:acme:off',
    });
    expect(normalizeConfirmItems(contract, [`channel:toggle/${family}::off`])).toEqual({
      reason: `bad-channel-argument:${family}::off`,
    });
    expect(normalizeConfirmItems(contract, [`channel:toggle/${family}:acme:ON`])).toEqual({
      reason: `bad-channel-argument:${family}:acme:ON`,
    });
  });

  test('多一段而尾部仍是合法目标词 ⇒ 也拒（段数这一维不许靠目标词兜住）', () => {
    // 上面那条"四种坏法"里的多一段用的是 `…:off:extra`，那种串**目标词那一格也会拒** ——
    // 于是"段数"这一维看着有测试，其实摘掉段数判据仍然全绿（本条反证当时就是这么红的）。
    const family = contract.capabilities.l2.channelTargetShape.families[0];
    const word = contract.capabilities.l2.channelTargetShape.targetWords[1];
    expect(
      normalizeConfirmItems(contract, [`channel:toggle/${family}:acme:extra:${word}`]),
    ).toEqual({ reason: `bad-channel-argument:${family}:acme:extra:${word}` });
  });

  test('L3 那两枚 toggle：目标词只认契约那两个，grant 型那几项不许带参数', () => {
    const words = contract.capabilities.l3.itemTargetWords;
    expect(words).toEqual(['on', 'off']);
    expect(normalizeConfirmItems(contract, ['monitoring/on'])).toEqual({
      items: ['monitoring/on'],
    });
    expect(normalizeConfirmItems(contract, ['monitoring/up'])).toEqual({
      reason: 'unknown-target-word:up',
    });
    expect(normalizeConfirmItems(contract, ['notification/on'])).toEqual({
      reason: 'unexpected-argument:notification',
    });
  });

  test('两处说法不一致 ⇒ 抛（requiresArgumentFrom 与 l2.reports 各说一套）', () => {
    const missing = JSON.parse(JSON.stringify(contract));
    delete missing.capabilities.l2.reports['channel:toggle'];
    expect(() => grantItemKind(missing, 'channel:toggle')).toThrow(/两处说法不一致/);
    const extra = JSON.parse(JSON.stringify(contract));
    extra.capabilities.l2.requiresArgumentFrom = extra.capabilities.l2.requiresArgumentFrom.filter(
      (a) => a !== 'channel:toggle',
    );
    expect(() => grantItemKind(extra, 'channel:toggle')).toThrow(/两处说法不一致/);
    // 看不懂的 argumentKind：只剩"照着猜一种拼法"可走 ⇒ 同样抛。
    const unknownKind = JSON.parse(JSON.stringify(contract));
    unknownKind.capabilities.l2.reports['sms:search'].argumentKind = 'flag';
    expect(() => grantItemKind(unknownKind, 'sms:search')).toThrow(/读不出形状/);
    // 设置项被当成动作列进 requiresArgumentFrom ⇒ 抛（两份身份，读的人只能猜）。
    const dual = JSON.parse(JSON.stringify(contract));
    dual.capabilities.l2.requiresArgumentFrom = [
      ...dual.capabilities.l2.requiresArgumentFrom,
      'monitoring',
    ];
    expect(() => grantItemKind(dual, 'monitoring')).toThrow(/既在/);
  });

  test('写进表的整串与收单那一判对得上：勾这一条放行不了那一条', () => {
    // 这一条把片4 的两端接起来：**勾的是整串** ⇒ 授权表里是整串 ⇒ decideCapability 的
    // 逐条比对（同样是整串相等）才判得到"这一条"。名字级的那份写法在这里会假绿
    // （表里是 `app:launch`，线上是 `app:launch/demo`，两边都"看起来收了"却永远判不过）。
    const granted = normalizeConfirmItems(contract, ['app:launch/demo']);
    const levels = contract.capabilities.levels;
    const decide = (item) =>
      decideCapability(contract, {
        stage: 'intake',
        type: 'action',
        item,
        grant: { maxLevel: levels[levels.length - 2], items: granted.items },
      });
    expect(decide('app:launch/demo').allowed).toBe(true);
    expect(decide('app:launch/other')).toEqual(
      expect.objectContaining({ reason: 'item:app:launch/other' }),
    );
    expect(decide('app:launch').allowed).toBe(false);
  });
});
