'use strict';

// 未送达消息存储（T34-B）的服务端测试。
//
// 这一批用例盯的不是"函数返回值对不对"，而是三条**只有落盘才看得见**的不变量：
// ① 盘上搜不到明文正文（"静态加密"不是注释里写了就算做了）；
// ② 没有密钥就拒绝入队，而不是退回明文（本仓既有的 TOTP 路径就是退回明文的，那条路对正文不成立）；
// ③ 状态推进只有 delivery.advance() 一个入口（源码守卫逐字检查本模块不出现任何状态名字面量）。
//
// 两条被这些用例当场逮到的缺陷也留在这儿当回归：
// ④ `ack_fail` 后留在 delivering 自环 ⇒ 没有任何事件能再触发投递（dispatch 只认 queued），
//    重试是假的 —— 迁移表已改成"失败回到 queued"；
// ⑤ 裸 UUID 去掉连字符正好 32 位 = 端点口令位数，会被"值长得像口令"那道落盘闸门拒写
//    —— 于是 messageId 带 `m_` 前缀、dedupe_id 只存摘要。

const fs = require('fs');
const os = require('os');
const path = require('path');

process.env.NODE_ENV = 'test';
const bcrypt = require('bcryptjs');
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-msgstore', 10);
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-msgs-'));

const { loadContract, assertSupported } = require('../lib/fnthink/contract');
const delivery = require('../lib/fnthink/delivery');
const store = require('../lib/fnthink/messagestore');

const contract = assertSupported(loadContract());
const KEY = 'a'.repeat(40); // 派生正文密钥用的模拟 ENCRYPTION_KEY（≥16 字符即可）
const DAY = 24 * 60 * 60 * 1000;
const T0 = 1_700_000_000_000;

const fresh = () => ({});

function put(messages, device, seq, now, key) {
  return store.enqueue(
    contract,
    messages,
    {
      device,
      type: 'notice',
      item: 'app:a',
      title: `标题${seq}`,
      body: `正文${seq}-MARKER-${seq}`,
      dedupeId: `d-${seq}`,
    },
    now === undefined ? T0 + seq : now,
    key === undefined ? KEY : key,
  );
}

describe('正文静态加密（T34-B 的核心那条）', () => {
  test('落盘的文件里搜不到明文正文与标题', () => {
    const messages = fresh();
    put(messages, 'DEV-1', 1);
    store.saveMessages(messages);
    const raw = fs.readFileSync(store.MESSAGE_FILE, 'utf8');
    expect(raw).not.toContain('MARKER');
    expect(raw).not.toContain('正文1');
    expect(raw).not.toContain('标题1');
    // 密文确实在盘上（不是"字段被顺手删了"造成的假绿）
    expect(raw).toMatch(/"body":\s*"v1\./);
  });

  test('解回来是原样：标题与正文装的是同一个信封', () => {
    const messages = fresh();
    const { message } = put(messages, 'DEV-1', 7);
    expect(store.decryptBodyFor(contract, KEY, message.body)).toEqual({
      title: '标题7',
      body: '正文7-MARKER-7',
    });
  });

  test('没有密钥 / 密钥太短 ⇒ 抛错拒绝入队，表里也不留东西', () => {
    const messages = fresh();
    expect(() => put(messages, 'DEV-1', 1, T0, '')).toThrow(/ENCRYPTION_KEY/);
    expect(() => put(messages, 'DEV-1', 1, T0, 'short')).toThrow(/ENCRYPTION_KEY/);
    expect(Object.keys(messages)).toEqual([]);
  });

  test('同一条正文两次入队得到两份不同密文（IV 每次新），解出来却一样', () => {
    const a = fresh();
    const b = fresh();
    const first = put(a, 'DEV-1', 3).message.body;
    const second = put(b, 'DEV-2', 3).message.body;
    expect(first).not.toBe(second);
    expect(store.decryptBodyFor(contract, KEY, first)).toEqual(
      store.decryptBodyFor(contract, KEY, second),
    );
  });

  test('密文被改一个字符 ⇒ 解不开（GCM 的 tag 真的在把关，不是摆设）', () => {
    const messages = fresh();
    const { message } = put(messages, 'DEV-1', 1);
    const at = Math.floor(message.body.length / 2);
    const ch = message.body[at];
    const tampered =
      message.body.slice(0, at) + (ch === 'A' ? 'B' : 'A') + message.body.slice(at + 1);
    expect(() => store.decryptBodyFor(contract, KEY, tampered)).toThrow();
  });
});

describe('标识的形状：不能被自己的落盘闸门拒写', () => {
  test('messageId 由服务端生成、带前缀，调用方给的不算', () => {
    const messages = fresh();
    const r = store.enqueue(
      contract,
      messages,
      { device: 'DEV-1', type: 'notice', body: 'b', messageId: 'HACK' },
      T0,
      KEY,
    );
    expect(r.message.messageId).toMatch(/^m_[0-9a-f]{24}$/);
    expect(r.droppedFields).toContain('messageId');
  });

  test('发送方给一个 UUID 形状的 dedupe_id 也能正常落盘（它被折成摘要）', () => {
    const messages = fresh();
    const uuid = '3f2b8c9a-1d4e-5f60-7182-93a4b5c6d7e8';
    store.enqueue(
      contract,
      messages,
      { device: 'DEV-1', type: 'notice', body: 'b', dedupeId: uuid },
      T0,
      KEY,
    );
    expect(() => store.saveMessages(messages)).not.toThrow();
    const stored = Object.values(messages)[0];
    expect(stored.dedupeIdDigest).toMatch(/^[0-9a-f]{64}$/);
    expect(stored.dedupeIdDigest).not.toBe(uuid);
    // 幂等匹配照样成立：同 id 再来一条是覆盖，不是新增
    const again = store.enqueue(
      contract,
      messages,
      { device: 'DEV-1', type: 'notice', body: 'b2', dedupeId: uuid },
      T0 + 1,
      KEY,
    );
    expect(again.action).toBe('refreshed');
  });
});

describe('名单裁剪与状态推进的唯一入口', () => {
  test('名单之外的字段被丢弃，机器自持的字段不许调用方给', () => {
    const messages = fresh();
    const r = store.enqueue(
      contract,
      messages,
      {
        device: 'DEV-1',
        type: 'notice',
        body: 'b',
        title: 't',
        senderIp: '1.2.3.4',
        rawPayload: { anything: true },
        state: 'delivered',
        attempts: 99,
      },
      T0,
      KEY,
    );
    expect(r.droppedFields).toEqual(
      expect.arrayContaining(['senderIp', 'rawPayload', 'state', 'attempts']),
    );
    const stored = Object.values(messages)[0];
    expect(stored.senderIp).toBeUndefined();
    expect(stored.rawPayload).toBeUndefined();
    expect(stored.state).toBe(contract.delivery.initialState);
    expect(stored.attempts).toBe(0);
    expect(Object.keys(stored).every((k) => contract.retention.storedFields.includes(k))).toBe(
      true,
    );
    for (const required of ['messageId', 'device', 'state', 'attempts', 'queuedAt', 'body']) {
      expect(stored[required]).toBeDefined();
    }
  });

  test('本模块不出现任何状态名字面量：推进只有 advance 一个入口（源码守卫）', () => {
    const src = fs.readFileSync(
      path.join(__dirname, '..', 'lib', 'fnthink', 'messagestore.js'),
      'utf8',
    );
    const code = src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
    const hits = contract.delivery.states
      .map((s) => `'${s}'`)
      .filter((literal) => code.includes(literal));
    expect(hits).toEqual([]);
  });

  test('可投递状态表来自契约：改表，本模块的行为跟着变', () => {
    const mutated = JSON.parse(JSON.stringify(contract));
    mutated.delivery.pollableStates = [...mutated.delivery.pollableStates, 'delivering'];
    const messages = fresh();
    const { message } = put(messages, 'DEV-1', 1);
    store.advanceMessage(contract, messages, message.messageId, 'dispatch', { now: T0 });
    expect(message.state).toBe('delivering');
    // 默认口径下 delivering 不算 pending；改表后就算
    expect(store.pendingCountFor(contract, messages, 'DEV-1')).toBe(0);
    expect(store.pendingCountFor(mutated, messages, 'DEV-1')).toBe(1);
  });
});

describe('dedupe_id：覆盖而非新增（只在还没发出去时）', () => {
  test('同 dedupeId 两次 ⇒ 一条记录，正文换新，时钟重开', () => {
    const messages = fresh();
    const first = store.enqueue(
      contract,
      messages,
      { device: 'DEV-1', type: 'notice', body: '旧', dedupeId: 'same' },
      T0,
      KEY,
    );
    const second = store.enqueue(
      contract,
      messages,
      { device: 'DEV-1', type: 'notice', body: '新', dedupeId: 'same' },
      T0 + 5000,
      KEY,
    );
    expect(first.action).toBe('new');
    expect(second.action).toBe('refreshed');
    expect(Object.keys(messages).length).toBe(1);
    expect(second.message.messageId).toBe(first.message.messageId);
    expect(store.decryptBodyFor(contract, KEY, second.message.body).body).toBe('新');
    expect(second.message.queuedAt).toBe(T0 + 5000);
  });

  test('已经发出去之后再收到同 dedupeId ⇒ 判 duplicate，不覆盖', () => {
    const messages = fresh();
    const { message } = store.enqueue(
      contract,
      messages,
      { device: 'DEV-1', type: 'notice', body: '旧', dedupeId: 'same' },
      T0,
      KEY,
    );
    store.advanceMessage(contract, messages, message.messageId, 'dispatch', { now: T0 });
    const again = store.enqueue(
      contract,
      messages,
      { device: 'DEV-1', type: 'notice', body: '新', dedupeId: 'same' },
      T0 + 1000,
      KEY,
    );
    expect(again.action).toBe('duplicate');
    expect(Object.keys(messages).length).toBe(1);
    expect(store.decryptBodyFor(contract, KEY, message.body).body).toBe('旧');
  });

  test('不同设备的同 dedupeId 互不影响', () => {
    const messages = fresh();
    store.enqueue(
      contract,
      messages,
      { device: 'DEV-1', type: 'notice', body: 'a', dedupeId: 'same' },
      T0,
      KEY,
    );
    const other = store.enqueue(
      contract,
      messages,
      { device: 'DEV-2', type: 'notice', body: 'b', dedupeId: 'same' },
      T0,
      KEY,
    );
    expect(other.action).toBe('new');
    expect(Object.keys(messages).length).toBe(2);
  });
});

describe('每设备 pending 上限：丢最旧并回执，不静默丢', () => {
  test('挤位发生在入队时，被挤的那条正文立刻从盘上消失', () => {
    const max = contract.retention.pendingPerDeviceMax;
    const messages = fresh();
    for (let i = 0; i < max; i += 1) put(messages, 'DEV-1', i, T0 + i);
    expect(store.pendingCountFor(contract, messages, 'DEV-1')).toBe(max);
    const r = store.enqueue(
      contract,
      messages,
      { device: 'DEV-1', type: 'notice', body: '挤不进来的', dedupeId: 'last' },
      T0 + max,
      KEY,
    );
    expect(r.evicted.length).toBe(1);
    expect(r.evicted[0].receipt).toBe(contract.retention.overflowReceipt);
    expect(store.pendingCountFor(contract, messages, 'DEV-1')).toBe(max);
    const victim = messages[r.evicted[0].messageId];
    expect(victim.body).toBeUndefined();
    expect(delivery.isTerminal(contract, victim.state)).toBe(true);
    store.saveMessages(messages);
    expect(fs.readFileSync(store.MESSAGE_FILE, 'utf8')).not.toContain('挤不进来的');
  });

  test('正好满额时一条都不该丢；换设备不动别人的队列', () => {
    const max = contract.retention.pendingPerDeviceMax;
    const messages = fresh();
    for (let i = 0; i < max; i += 1) put(messages, 'DEV-1', i, T0 + i);
    expect(store.evictOverflow(contract, messages, 'DEV-1', T0).length).toBe(0);
    put(messages, 'DEV-2', 0, T0);
    expect(store.pendingCountFor(contract, messages, 'DEV-1')).toBe(max);
  });
});

describe('重试与 poll 取货', () => {
  test('失败后回到 queued，下一次 poll 才真的重试（自环等于没重试）', () => {
    const messages = fresh();
    const { message } = put(messages, 'DEV-1', 1);
    store.dispatchForDevice(contract, messages, 'DEV-1', T0);
    expect(message.state).toBe('delivering');
    store.advanceMessage(contract, messages, message.messageId, 'no_ack', { now: T0 + 1 });
    expect(message.state).toBe(contract.delivery.initialState);
    expect(message.attempts).toBe(1);
    const again = store.dispatchForDevice(contract, messages, 'DEV-1', T0 + 2);
    expect(again.taken.map((x) => x.messageId)).toEqual([message.messageId]);
    expect(message.attempts).toBe(2);
  });

  test('按排队顺序取走（先进先出，不是按 id）', () => {
    const messages = fresh();
    const late = store.enqueue(
      contract,
      messages,
      { device: 'DEV-1', type: 'notice', body: '后到', dedupeId: 'b' },
      T0 + 100,
      KEY,
    ).message;
    const early = store.enqueue(
      contract,
      messages,
      { device: 'DEV-1', type: 'notice', body: '先到', dedupeId: 'a' },
      T0 + 10,
      KEY,
    ).message;
    const r = store.dispatchForDevice(contract, messages, 'DEV-1', T0 + 200);
    expect(r.taken.map((x) => x.messageId)).toEqual([early.messageId, late.messageId]);
    expect(r.skipped).toEqual([]);
  });

  test('预算用尽后不再从 queued 走；设备再 poll 时按新一轮重发（尝试数回到 1）', () => {
    const messages = fresh();
    const { message } = put(messages, 'DEV-1', 1);
    const budget = delivery.maxAttempts(contract);
    for (let i = 0; i < budget; i += 1) {
      store.dispatchForDevice(contract, messages, 'DEV-1', T0 + i);
      store.advanceMessage(contract, messages, message.messageId, 'no_ack', { now: T0 + i });
    }
    // 到这里它已经不在初态（= 本轮预算用尽），但仍然"可投递"（等上线补发）
    expect(message.state).not.toBe(contract.delivery.initialState);
    expect(delivery.isTerminal(contract, message.state)).toBe(false);
    expect(store.pendingCountFor(contract, messages, 'DEV-1')).toBe(1);
    const r = store.dispatchForDevice(contract, messages, 'DEV-1', T0 + 99);
    expect(r.taken.map((x) => x.messageId)).toEqual([message.messageId]);
    expect(message.attempts).toBe(1);
  });

  test('可投递态却没有正文 ⇒ 拒绝下发空内容（而不是渲染一条空白通知）', () => {
    const messages = fresh();
    const { message } = put(messages, 'DEV-1', 1);
    delete message.body;
    expect(() => store.dispatchForDevice(contract, messages, 'DEV-1', T0)).toThrow(/没有正文/);
  });

  test('到期扫描：非终态过 7 天全部 expired 并删正文，且幂等', () => {
    const messages = fresh();
    const { message } = put(messages, 'DEV-1', 1, T0);
    const later = T0 + contract.retention.maxRetentionDays * DAY;
    expect(store.expireDueMessages(contract, messages, later - 1).expired).toEqual([]);
    const first = store.expireDueMessages(contract, messages, later);
    expect(first.expired.map((e) => e.messageId)).toEqual([message.messageId]);
    expect(message.body).toBeUndefined();
    expect(delivery.isTerminal(contract, message.state)).toBe(true);
    expect(store.expireDueMessages(contract, messages, later + DAY).expired).toEqual([]);
  });
});
