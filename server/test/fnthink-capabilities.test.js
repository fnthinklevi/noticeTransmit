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
  decideCapability,
  endpointGrant,
  grantFromNode,
  grantFromRecord,
} = require('../lib/fnthink/capabilities');

const contract = assertSupported(loadContract());
const vectors = JSON.parse(
  fs.readFileSync(path.join(__dirname, '..', '..', 'protocol', 'fnthink-vectors-v1.json'), 'utf8'),
);
const CAPS = vectors.capabilities;
const REASON_FORMS = ['unknown-type:', 'level:L', 'item:', 'missing-item', 'confirm-required'];

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

  test('grantFromRecord：记录里没有 grant ⇒ 按缺省档；有 grant ⇒ 逐项读', () => {
    expect(grantFromRecord(contract, {}).maxLevel).toBe(
      contract.capabilities.grantDefaults.maxLevel,
    );
    expect(grantFromRecord(contract, null).items).toEqual([]);
    const rec = { grant: { maxLevel: 'L2', items: ['app:a/b', ''], revision: '3' } };
    const got = grantFromRecord(contract, rec);
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
    const stored = grantFromRecord(contract, {}); // 表里没授权 ⇒ 缺省 L1
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
