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
    expect(store.evictOverflow(contract, messages, 'DEV-1', T0).evicted.length).toBe(0);
    put(messages, 'DEV-2', 0, T0);
    expect(store.pendingCountFor(contract, messages, 'DEV-1')).toBe(max);
  });

  // ── §4-8：挤位只挤"还没发出去的"那一档（原缺陷：在飞的那条被报成 dropped）────────
  describe('挤位候选只有初态那一条（在飞的不算、也不白扣预算）', () => {
    /// 上限压到 1 的**契约副本**（不是同一份真值：拿实现读的那份去断言，写死与读契约分不出来）。
    const capped = () => {
      const c = JSON.parse(JSON.stringify(contract));
      c.retention.pendingPerDeviceMax = 1;
      return c;
    };

    /// 把一条推到 waiting_online：dispatch/ack_fail 成对走到迁移表把它送进去。
    function toWaitingOnline(c, messages, id) {
      const rounds = (c.limits.deliveryRetryTotal || 0) + 3;
      for (let i = 0; i < rounds && messages[id].state !== 'waiting_online'; i += 1) {
        store.advanceMessage(c, messages, id, 'dispatch', { now: T0 + i * 4 });
        store.advanceMessage(c, messages, id, 'ack_fail', { now: T0 + i * 4 + 2 });
      }
      expect(messages[id].state).toBe('waiting_online');
    }

    test('最旧的那条正在飞 ⇒ 不动它、也不给它回 dropped 回执', () => {
      const c = capped();
      const messages = fresh();
      // 一条排队、一条在飞，然后入队第三行 ⇒ 触发挤位（max=1）
      const inflight = put(messages, 'DEV-1', 1, T0).message.messageId;
      toWaitingOnline(c, messages, inflight);
      const queued = put(messages, 'DEV-1', 2, T0 + 100).message.messageId;
      const result = store.enqueue(
        c,
        messages,
        { device: 'DEV-1', type: 'notice', body: 'b' },
        T0 + 200,
        KEY,
      );

      const evictedIds = result.evicted.map((e) => e.messageId);
      // 在飞那条是**最旧**的：老实现按"可投递"挑候选，第一下就挑到它 —— 迁移表判 ignored，
      // 可它照样进 evicted 并回一条 dropped。
      expect(evictedIds).toContain(queued);
      expect(evictedIds).not.toContain(inflight);
      expect(messages[inflight].state).toBe('waiting_online');
      expect(messages[inflight].receipt).not.toBe(c.retention.overflowReceipt);
      expect(messages[inflight].body).toBeDefined();
    });

    test('挤完之后还超着上限 ⇒ evictionBlocked 说清"还有几条挤不动"', () => {
      const c = capped();
      const messages = fresh();
      const first = put(messages, 'DEV-1', 1, T0).message.messageId;
      toWaitingOnline(c, messages, first);
      const second = put(messages, 'DEV-1', 2, T0 + 1).message.messageId;
      toWaitingOnline(c, messages, second);
      const result = store.enqueue(
        c,
        messages,
        { device: 'DEV-1', type: 'notice', body: 'b' },
        T0 + 200,
        KEY,
      );

      // 两条都在飞 ⇒ 一条都挤不动；新来的那条是唯一能挤的，挤掉之后仍超着上限
      const evictedIds = result.evicted.map((e) => e.messageId);
      expect(evictedIds).not.toContain(first);
      expect(evictedIds).not.toContain(second);
      expect(result.evictionBlocked).toBe(1);
      expect(store.pendingCountFor(c, messages, 'DEV-1')).toBe(2);
    });

    test('没有挤位时 blocked 是 0，不是 undefined（"没腾出来"与"不用腾"要分得开）', () => {
      const messages = fresh();
      put(messages, 'DEV-1', 1, T0);
      const r = store.enqueue(
        contract,
        messages,
        { device: 'DEV-1', type: 'notice', body: 'b' },
        T0 + 1,
        KEY,
      );
      expect(r.evicted).toEqual([]);
      expect(r.evictionBlocked).toBe(0);
      const dup = store.enqueue(
        contract,
        messages,
        { device: 'DEV-1', type: 'notice', body: 'b2', dedupeId: 'x' },
        T0 + 2,
        KEY,
      );
      expect(dup.evictionBlocked).toBe(0);
    });

    test('挤位的候选从契约 initialState 读，不是在代码里写死一档', () => {
      const c = JSON.parse(JSON.stringify(contract));
      c.retention.pendingPerDeviceMax = 0;
      const messages = fresh();
      put(messages, 'DEV-1', 1, T0);
      put(messages, 'DEV-1', 2, T0 + 1);
      const ev = store.evictOverflow(c, messages, 'DEV-1', T0 + 5);
      // 两条都在初态 ⇒ 两条都该被挤掉（blocked 归 0：没有挤不动的剩着）
      expect(ev.evicted.length).toBe(2);
      expect(ev.blocked).toBe(0);
      for (const id of Object.keys(messages)) {
        expect(delivery.isTerminal(contract, messages[id].state)).toBe(true);
      }
    });
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

// ── 回执账（T35 的前提）──
// 写 poll 路由时才发现的缺口：消息表只记 device（投给谁），没记 sender（谁发的），
// 于是"到了终态之后把结果告诉发送端"这句话**根本没有收件人可查** —— 回执通道不是没实现，
// 是无从实现。契约 storedFields 因此加了 sender，这几条用例钉的就是它的下游三件事。
describe('回执账（T35）', () => {
  const SENDER = '8K3FJ6QPTM9WZ4VHNS';
  const OTHER_SENDER = '7YD4RKQPBM8XZ3VHNT';

  function putFrom(messages, sender, device, seq, now) {
    return store.enqueue(
      contract,
      messages,
      {
        sender,
        device,
        type: 'notice',
        item: 'app:a',
        title: '标题' + seq,
        body: '正文' + seq + '-MARKER-' + seq,
        dedupeId: 'rd-' + seq,
      },
      now === undefined ? T0 + seq : now,
      KEY,
    );
  }

  test('sender 落盘；receipt / receiptSentAt 是机器自持字段，调用方给不进去', () => {
    const messages = {};
    const r = store.enqueue(
      contract,
      messages,
      {
        sender: SENDER,
        device: 'DEV-1',
        type: 'notice',
        body: 'b',
        // 这两个字段一旦被调用方能写，就等于让发送端自己宣布"这条已经 dropped/delivered"
        receipt: 'delivered',
        receiptSentAt: 1,
        messageId: 'attacker-chosen-id',
      },
      T0,
      KEY,
    );
    expect(r.message.sender).toBe(SENDER);
    expect(r.message.receipt).toBeUndefined();
    expect(r.message.receiptSentAt).toBeUndefined();
    expect(r.message.messageId).not.toBe('attacker-chosen-id');
    expect(r.droppedFields).toEqual(expect.arrayContaining(['receipt', 'receiptSentAt']));
  });

  test('ack_ok 进 delivered ⇒ 状态机把回执留档，同时正文按契约释放', () => {
    const messages = {};
    const { message } = putFrom(messages, SENDER, 'DEV-1', 1);
    store.advanceMessage(contract, messages, message.messageId, 'dispatch', { now: T0 + 10 });
    const step = store.advanceMessage(contract, messages, message.messageId, 'ack_ok', {
      now: T0 + 20,
    });
    expect(step.message.receipt).toBe('delivered');
    expect(step.message.body).toBeUndefined();
  });

  test('回执只报一次：第二次取是空的（同一条结果每次 poll 刷屏不是"送达可见"）', () => {
    const messages = {};
    const { message } = putFrom(messages, SENDER, 'DEV-1', 2);
    store.advanceMessage(contract, messages, message.messageId, 'dispatch', { now: T0 + 10 });
    store.advanceMessage(contract, messages, message.messageId, 'ack_ok', { now: T0 + 20 });

    const first = store.receiptsForSender(contract, messages, SENDER, T0 + 30, 50);
    expect(first).toEqual([
      {
        messageId: message.messageId,
        target: 'DEV-1',
        receipt: 'delivered',
        // T105 片③：对面收下那一刻（终态迁移那一下的 now）——
        // 发送侧那句「对端接收时间」全靠它。
        at: T0 + 20,
      },
    ]);
    // ⚠ 返回对象里**没有 body**：正文早已删除，回执是元数据（契约 auditStoresMetadataOnly）
    expect(Object.keys(first[0]).sort()).toEqual(['at', 'messageId', 'receipt', 'target']);
    expect(store.receiptsForSender(contract, messages, SENDER, T0 + 40, 50)).toEqual([]);
  });

  test('别人发的消息不进我的回执账', () => {
    const messages = {};
    const { message } = putFrom(messages, OTHER_SENDER, 'DEV-1', 3);
    store.advanceMessage(contract, messages, message.messageId, 'dispatch', { now: T0 + 10 });
    store.advanceMessage(contract, messages, message.messageId, 'ack_ok', { now: T0 + 20 });
    expect(store.receiptsForSender(contract, messages, SENDER, T0 + 30, 50)).toEqual([]);
    expect(store.receiptsForSender(contract, messages, '', T0 + 30, 50)).toEqual([]);
  });

  test('非终态不回回执；迟到的重复 ack 也不会把已落的回执擦掉', () => {
    const messages = {};
    const { message } = putFrom(messages, SENDER, 'DEV-1', 4);
    // 还在排队：没有任何结论可报
    expect(store.receiptsForSender(contract, messages, SENDER, T0 + 30, 50)).toEqual([]);
    store.advanceMessage(contract, messages, message.messageId, 'dispatch', { now: T0 + 10 });
    store.advanceMessage(contract, messages, message.messageId, 'ack_ok', { now: T0 + 20 });
    // 第二次 ack_ok 是"ignored"步：状态、回执、时间都不能动（擦掉回执就是丢账）
    const late = store.advanceMessage(contract, messages, message.messageId, 'ack_ok', {
      now: T0 + 99,
    });
    expect(late.step.ignored).toBeTruthy();
    expect(messages[message.messageId].receipt).toBe('delivered');
    expect(messages[message.messageId].updatedAt).toBe(T0 + 20);
  });

  test('被上限挤位的那些，发送端也会收到一条 dropped 回执（不许静默丢）', () => {
    const messages = {};
    const max = contract.retention.pendingPerDeviceMax;
    const putMany = (sender, seqBase, count) => {
      for (let i = 0; i < count; i++) putFrom(messages, sender, 'DEV-BULK', seqBase + i);
    };
    putMany(SENDER, 1000, max);
    putMany(SENDER, 2000, 3); // 超出的三条把最旧的挤掉
    const receipts = store.receiptsForSender(contract, messages, SENDER, T0 + 5000, 50);
    const dropped = receipts.filter((r) => r.receipt === 'dropped');
    expect(dropped.length).toBe(3);
    // 挤位回执是**元数据**：这三条的正文必须已经不在表里
    for (const r of dropped) expect(messages[r.messageId].body).toBeUndefined();
    expect(store.receiptsForSender(contract, messages, SENDER, T0 + 5001, 50).length).toBe(0);
  });

  test('回执上限跟着参数走，不会一次把整段历史倒出来', () => {
    const messages = {};
    for (let i = 0; i < 5; i++) {
      const { message } = putFrom(messages, SENDER, 'DEV-N', 3000 + i);
      store.advanceMessage(contract, messages, message.messageId, 'ttl_elapsed', { now: T0 });
    }
    expect(store.receiptsForSender(contract, messages, SENDER, T0 + 1, 2).length).toBe(2);
  });

  test('就算有人把 receipt 写进契约的 storedFields，MACHINE_OWNED 仍是第二道闸', () => {
    // 这条是被自己的反证逼出来的：把 'receipt' 从 MACHINE_OWNED 里删掉时**没有一顶用例变红**
    // —— 因为 storedFields 本来就不含 receipt，白名单先把它拦下了，于是那道闸今天不可观察。
    // 不可观察不等于没用：它防的是"将来有人往 storedFields 里加一个 receipt"，
    // 那一次改动的后果是发送端可以自己宣布 delivered（正文随之被契约判成可释放）。
    // 所以这里在 mutate 出来的契约副本上证明第二道闸真的独立生效。
    const loose = JSON.parse(JSON.stringify(contract));
    loose.retention.storedFields.push('receipt', 'receiptSentAt');
    const messages = {};
    const r = store.enqueue(
      loose,
      messages,
      {
        sender: SENDER,
        device: 'DEV-1',
        type: 'notice',
        body: 'b',
        receipt: 'delivered',
        receiptSentAt: 1,
      },
      T0,
      KEY,
    );
    expect(r.message.receipt).toBeUndefined();
    expect(r.message.receiptSentAt).toBeUndefined();
    expect(r.message.state).toBe(contract.delivery.initialState);
  });
  // 这条是被反证 G3 逼出来的：把过滤里的 isTerminal 去掉，原先**没有任何用例变红**。
  // 原因不在实现，在判据组合 —— waiting_online 也带一个 receipt 字符串（状态机在那一步就发了它），
  // 光看"有没有 receipt"会把**还没送达**的东西报出去，违反已定决策「进入 waiting_online 不主动通知发送端」。
  test('waiting_online 带得回回执字符串，但不能当成结论报给发送端', () => {
    const messages = {};
    const { message } = putFrom(messages, SENDER, 'DEV-W', 4000);
    const budget = 1 + contract.limits.deliveryRetryTotal;
    for (let i = 0; i < budget; i++) {
      store.advanceMessage(contract, messages, message.messageId, 'dispatch', {
        now: T0 + i * 10,
      });
      store.advanceMessage(
        contract,
        messages,
        message.messageId,
        i + 1 < budget ? 'ack_fail' : 'no_ack',
        { now: T0 + i * 10 + 5 },
      );
    }
    expect(messages[message.messageId].state).toBe('waiting_online');
    expect(messages[message.messageId].receipt).toBe('waiting_online');
    // 仍在等对端上线 ⇒ 没有结论可报；等它真送达了再报那一条 delivered
    expect(store.receiptsForSender(contract, messages, SENDER, T0 + 1000, 50)).toEqual([]);
    store.advanceMessage(contract, messages, message.messageId, 'peer_online', {
      now: T0 + 2000,
    });
    store.advanceMessage(contract, messages, message.messageId, 'ack_ok', { now: T0 + 2001 });
    expect(store.receiptsForSender(contract, messages, SENDER, T0 + 3000, 50)).toEqual([
      {
        messageId: message.messageId,
        target: 'DEV-W',
        receipt: 'delivered',
        at: T0 + 2001,
      },
    ]);
  });

  // 这条是 #126 把路由接上之后才暴露的：修复前**任何不带 dedupe_id 的消息都存不进盘**
  // （`dedupeDigest('')` 返回空串，而落盘闸门要求任何 `*Digest` 都是 64 位十六进制 ⇒ 抛）。
  // 此前 20 多条用例每条都自带 dedupeId，于是最常见的形状一条没测到，而 jest 全绿。
  describe('不带 dedupe_id 的形状（#126 暴露的回归）', () => {
    test('缺 dedupeId 也能收单、落盘、重读，且表里不留一个空串的 *Digest', () => {
      const messages = {};
      const r = store.enqueue(
        contract,
        messages,
        { sender: 'SENDERSITE', device: 'DEV-NODEDUPE', type: 'notice', body: '没有去重号的正文' },
        T0,
        KEY,
      );
      expect(r.message.dedupeIdDigest).toBeUndefined();
      store.saveMessages(messages);
      const back = store.loadMessages();
      expect(back[r.message.messageId].device).toBe('DEV-NODEDUPE');
      const raw = fs.readFileSync(store.MESSAGE_FILE, 'utf8');
      expect(raw).not.toContain('"dedupeIdDigest":""');
      expect(raw).not.toContain('没有去重号的正文');
    });
  });

  /// 「取走了没等到 ack」的恢复扫描（#178 真机现形）。这条路此前**只有测试在跑**：
  /// `no_ack` 那个分支在 delivery.js 里写好了，可生产代码没有任何地方触发它 ——
  /// 被 poll 取走却没回 ack 的消息就永远停在 `delivering`（pollableStates 不含它，
  /// 没有任何事件能把它推回去），正文留满保留期后按过期删掉，**从不补发**。
  describe('没等到 ack 的那条由 poll 扫回来（#178）', () => {
    const DEADLINE_MS = delivery.ackDeadlineSeconds(contract) * 1000;

    /// 造一条"被取走了、还没 ack"的消息：enqueue 之后走一次 dispatch。
    function inflight(messages, device, seq, now) {
      const { message } = store.enqueue(
        contract,
        messages,
        { device, type: 'notice', body: `正文${seq}`, dedupeId: `d-${seq}` },
        now,
        KEY,
      );
      store.dispatchForDevice(contract, messages, device, now);
      expect(messages[message.messageId].state).toBe('delivering');
      return message;
    }

    test('过期的 delivering ⇒ 按 no_ack 推回 queued（还有预算就重发）', () => {
      const messages = fresh();
      const message = inflight(messages, 'DEV-STALE', 1, T0);

      const moved = store.requeueUnackedStale(contract, messages, 'DEV-STALE', T0 + DEADLINE_MS);

      expect(moved).toHaveLength(1);
      expect(moved[0].messageId).toBe(message.messageId);
      expect(messages[message.messageId].state).toBe('queued');
    });

    test('还没过档的那条一律不动（正常往返不能被当成丢 ack）', () => {
      const messages = fresh();
      const message = inflight(messages, 'DEV-FRESH', 1, T0);

      const moved = store.requeueUnackedStale(
        contract,
        messages,
        'DEV-FRESH',
        T0 + DEADLINE_MS - 1,
      );

      expect(moved).toEqual([]);
      expect(messages[message.messageId].state).toBe('delivering');
    });

    test('预算用完的那条 ⇒ 转 waiting_online 并带上回执（不是静默卡住，也不是静默丢）', () => {
      const messages = fresh();
      const message = inflight(messages, 'DEV-SPENT', 1, T0);
      // 预算按**全局尝试数**消耗，而 ack_fail 之后那条回到 queued —— 所以要
      // dispatch/ack_fail 成对推进（⚠ 我第一版把它写成"连着 ack_fail"，
      // 第二次调用打在 queued 上是 ignored 步，用例红得莫名其妙 —— 记在这里免得再犯）。
      const budget = delivery.maxAttempts(contract);
      let guard = 0;
      while (messages[message.messageId].state === 'delivering' && guard++ < budget + 2) {
        store.advanceMessage(contract, messages, message.messageId, 'ack_fail', {
          now: T0 + guard,
        });
        if (messages[message.messageId].state === 'queued') {
          store.dispatchForDevice(contract, messages, 'DEV-SPENT', T0 + guard);
        }
      }
      expect(messages[message.messageId].state).toBe('waiting_online');
      expect(messages[message.messageId].receipt).toBe('waiting_online');

      // 已在 waiting_online 的那条不该被这个扫描再推一次（它等的是 peer_online 事件）。
      const moved = store.requeueUnackedStale(contract, messages, 'DEV-SPENT', T0 + DEADLINE_MS);
      expect(moved).toEqual([]);
      expect(messages[message.messageId].state).toBe('waiting_online');
    });

    test('别的设备的在飞消息不会被这一轮扫走（按 device 过滤）', () => {
      const messages = fresh();
      const mine = inflight(messages, 'DEV-A', 1, T0);
      const theirs = inflight(messages, 'DEV-B', 2, T0);

      store.requeueUnackedStale(contract, messages, 'DEV-A', T0 + DEADLINE_MS);

      expect(messages[mine.messageId].state).toBe('queued');
      expect(messages[theirs.messageId].state).toBe('delivering');
    });

    test('扫描排在 dispatch 之前时，那一轮就能把它重发出去（顺序本身就是判据）', () => {
      // 这条是本片最要紧的一条：先 dispatch 后扫描，重发要再等一个 cadence，
      // 而"卡住"这个形状就还在（只是慢了一拍）。所以这个顺序必须有用例钉住。
      const messages = fresh();
      const message = inflight(messages, 'DEV-ORDER', 1, T0);
      const now = T0 + DEADLINE_MS;

      store.requeueUnackedStale(contract, messages, 'DEV-ORDER', now);
      const dispatched = store.dispatchForDevice(contract, messages, 'DEV-ORDER', now);

      expect(dispatched.taken.map((t) => t.messageId)).toEqual([message.messageId]);
      expect(messages[message.messageId].state).toBe('delivering');
      expect(messages[message.messageId].attempts).toBe(2);
    });

    test('源码守卫：poll 里那一步扫描必须排在取货之前（顺序本身就是判据）', () => {
      // 为什么这一条不能省：把扫描挪到 dispatch 之后，功能**照样在**（下一轮 poll 就重发），
      // 运行期用例全绿 —— 变的只是"每条卡住的消息要多等一个 cadence"，症状是"推送时快时慢"。
      // 顺序错没有任何一条运行期用例能看见，所以钉在源码上。
      // 用全文件 indexOf 比较是安全的：`requeueUnackedStale` 与 `dispatchForDevice`
      // 各自**只在 poll 那一个处理器里出现一次**（守卫本身也钉住这一点，见下面两条）。
      const src = fs.readFileSync(path.join(__dirname, '../lib/fnthink/routes.js'), 'utf8');
      const scan = src.indexOf('requeueUnackedStale(contract, messages, auth.sender, now);');
      const take = src.indexOf('dispatchForDevice(contract, messages, auth.sender, now);');
      expect(scan).toBeGreaterThan(-1);
      expect(take).toBeGreaterThan(-1);
      // poll 必须先扫「没等到 ack」的再取货：晚一步那条要多等一个 cadence 才重发
      // （而症状看起来只是"时快时慢"）。
      if (scan >= take) {
        throw new Error(
          'poll 必须先扫「没等到 ack」的再取货：晚一步那条要多等一个 cadence 才重发' +
            `（scan=${scan} take=${take}）`,
        );
      }
      // 两处调用各自只许出现一次（import 那行是裸标识符，不带调用括号，所以数不到）。
      expect(src.split('requeueUnackedStale(contract, messages, auth.sender, now);')).toHaveLength(
        2,
      );
      expect(src.split('dispatchForDevice(contract, messages, auth.sender, now);')).toHaveLength(2);
    });
  });
});
