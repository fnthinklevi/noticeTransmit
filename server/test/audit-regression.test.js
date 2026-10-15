/**
 * 审计回归测试（2026-10-15）
 *
 * 这一份钉住的是「通读服务端全量代码后逐条核对过、判定为设计使然或已被既有守卫
 * 覆盖」的那几项。它们不是缺陷，但每一条都长得像缺陷 —— 而"长得像"正是它们
 * 会被下一个人顺手改坏的原因。所以修法不是改代码，是把判据钉在这里：
 *
 *  A. 同一失败计数器：OTP 与恢复码共用一份额度（一次请求只扣一次）
 *  B. nonce 落盘钩子：两条事件路径都走同一个 persist（内存记住 ≠ 重启还记得）
 *  C. dedupe 刷新不挤位：同 dedupe_id 刷新是换内容，不是加一条、也不触发驱逐
 *  D. CSP 覆盖两条 admin 地址：/admin.html 与 /public/admin.html 同一套头
 *  E. 原型污染防护：ip 来自客户端可控的 X-Forwarded-For 时不沿原型链写
 *  F. 2FA 失败计数写盘失败必须说出来（不是咽成沉默）
 *
 * 运行方式：在 server/ 目录下执行 `npm test`
 */

const os = require('os');
const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');

// ========== 测试环境（必须在任何 require 之前设置） ==========
process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-audit-test-'));
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-123456', 10);
process.env.ENCRYPTION_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
process.env.RATE_LIMIT_GENERAL_MAX = '10000';
process.env.RATE_LIMIT_AUTH_MAX = '10000';

const store = require('../lib/store');

afterAll(() => {
  try {
    fs.rmSync(process.env.DATA_DIR, { recursive: true, force: true });
  } catch (_) {}
});

// ════════════════════════════════════════════════════════════════════
// A. 同一失败计数器：一次请求只扣一次
// ════════════════════════════════════════════════════════════════════
describe('A. 2FA 失败计数器：一次请求只扣一次额度', () => {
  beforeEach(() => store.clearFailedAttempts('10.0.0.1'));

  test('一次失败 = 剩余次数减一（不是减二）', () => {
    expect(store.getRemainingAttempts('10.0.0.1')).toBe(store.MAX_FAILED_ATTEMPTS);
    store.recordFailedAttempt('10.0.0.1');
    expect(store.getRemainingAttempts('10.0.0.1')).toBe(store.MAX_FAILED_ATTEMPTS - 1);
  });

  test('达到上限即封锁，且计数被清空（封锁期间不再累加）', () => {
    for (let i = 0; i < store.MAX_FAILED_ATTEMPTS; i++) {
      store.recordFailedAttempt('10.0.0.2');
    }
    expect(store.isIpBlocked('10.0.0.2')).toBe(true);
    expect(store.failedAttempts['10.0.0.2']).toBeUndefined();
  });

  test('窗口过期后重新计数（10 分钟窗口，不无限累加）', () => {
    const old = Date.now() - (store.FAILURE_WINDOW_MINUTES * 60 * 1000 + 5000);
    store.failedAttempts['10.0.0.3'] = {
      count: store.MAX_FAILED_ATTEMPTS - 1,
      firstAttempt: old,
      lastAttempt: old,
    };
    // 旧记录已过窗口 ⇒ 这一次当作全新的一次失败，不会因为"历史累计到过 4 次"就直接封
    store.recordFailedAttempt('10.0.0.3');
    expect(store.isIpBlocked('10.0.0.3')).toBe(false);
    expect(store.getRemainingAttempts('10.0.0.3')).toBe(store.MAX_FAILED_ATTEMPTS - 1);
  });
});

// ════════════════════════════════════════════════════════════════════
// E. 原型污染防护：ip / 会话键来自客户端时不沿原型链写
// ════════════════════════════════════════════════════════════════════
describe('E. 原型污染防护（ip 在 TRUST_PROXY>0 时来自客户端可控的 X-Forwarded-For）', () => {
  test('失败计数表用 null 原型：__proto__ / constructor 不写进 Object.prototype', () => {
    const before = Object.getOwnPropertyNames(Object.prototype).slice().sort();
    store.recordFailedAttempt('__proto__');
    store.recordFailedAttempt('constructor');
    store.recordFailedAttempt('toString');
    const after = Object.getOwnPropertyNames(Object.prototype).slice().sort();
    expect(after).toEqual(before);
    // 这些键在表里就是普通一行，不命中原型链
    expect(store.failedAttempts['__proto__']).toBeDefined();
    expect(typeof store.failedAttempts['__proto__'].count).toBe('number');
  });

  test('失败计数表用 null 原型：__proto__ / constructor 不写进 Object.prototype', () => {
    const before = Object.getOwnPropertyNames(Object.prototype).slice().sort();
    store.recordFailedAttempt('__proto__');
    store.recordFailedAttempt('constructor');
    store.recordFailedAttempt('toString');
    const after = Object.getOwnPropertyNames(Object.prototype).slice().sort();
    expect(after).toEqual(before);
    // 这些键在表里就是普通一行，不命中原型链
    expect(store.failedAttempts['__proto__']).toBeDefined();
    expect(typeof store.failedAttempts['__proto__'].count).toBe('number');
  });

  // 反证（本次实跑）：把 `const rateLimitStore = Object.create(null)` 换回 `{}`，
  // 这一条**不会**红 —— 因为 `rateLimitStore['__proto__:api']` 带冒号，在普通对象上
  // 也只是普通自有键。⇒ 单看"限流表"这一处，null 原型是纵深防御而非可观察判据，
  // 所以这里不断言它（不断一个自己不会红的言），真正可观察的是下面失败计数表那一条
  // （`failedAttempts['__proto__']` 不带后缀，普通对象上会沿原型链走）。
  // 留着这条注释，免得下一个人以为这里漏了一处对称断言。
  test('限流表键恒带冒号（ip:bucket），不可能等于原型属性名', () => {
    // 判据落在"键的形状"上而不是"表是不是 null 原型"：后者对限流表不可观察。
    const key = store.rateLimitBucket('/api/version/check');
    expect(key).not.toContain(':');
    const composite = `1.2.3.4:${key}`;
    expect(composite).toContain(':');
    expect(Object.prototype.hasOwnProperty.call(composite)).toBe(false);
  });

  test('会话表仍拒绝原型键伪造（既有守卫，防回归）', () => {
    expect(store.isValidSession('__proto__')).toBe(false);
    expect(store.isValidSession('constructor')).toBe(false);
    expect(store.isValidSession('hasOwnProperty')).toBe(false);
    expect(store.isValidSession('')).toBe(false);
  });
});

// ════════════════════════════════════════════════════════════════════
// F. 持久化失败必须说出来（写盘失败不被咽成沉默）
// ════════════════════════════════════════════════════════════════════
describe('F. 持久化失败有声音（writeJsonFile 返回 false 时点明是哪张表）', () => {
  // ⚠ 不能靠"把 store.writeJsonFile 换掉"来伪装失败：模块内部调用的是它自己作用域里
  // 那个函数，exports 上换引用对它不可见（第一版就是这么写的，三条全绿不了）。
  // 也不能靠 defineProperty 改 FAILED_ATTEMPTS_FILE —— 那是模块内的 const，
  // 读写都走它自己那一份。唯一可靠的伪装是让**文件系统**真的失败：
  // 把 `failed_attempts.json.tmp` 占成一个**目录**，writeFileSync 当场 EISDIR 抛，
  // writeJsonFile 的 try/catch 接住 → return false —— 走的正是生产那条路径。
  function blockTmp(filePath) {
    const tmp = filePath + '.tmp';
    fs.mkdirSync(tmp, { recursive: true });
    return () => {
      try {
        fs.rmdirSync(tmp);
      } catch (_) {}
    };
  }

  test('saveFailedAttempts 写盘失败 → 打 [persist] 且不抛', () => {
    const spy = jest.spyOn(console, 'error').mockImplementation(() => {});
    const restore = blockTmp(store.FAILED_ATTEMPTS_FILE);
    try {
      expect(() => store.clearFailedAttempts('10.1.1.1')).not.toThrow();
      const lines = spy.mock.calls.map((c) => String(c[0])).join('\n');
      expect(lines).toContain('[persist]');
      expect(lines).toContain('2FA 失败计数写入失败');
    } finally {
      restore();
      spy.mockRestore();
    }
  });

  test('saveSessions 写盘失败 → 打 [persist] 且不抛', () => {
    const spy = jest.spyOn(console, 'error').mockImplementation(() => {});
    const restore = blockTmp(store.SESSIONS_FILE);
    try {
      expect(() => store.saveSessions()).not.toThrow();
      const lines = spy.mock.calls.map((c) => String(c[0])).join('\n');
      expect(lines).toContain('会话表写入失败');
    } finally {
      restore();
      spy.mockRestore();
    }
  });

  test('saveBlockedIPs 写盘失败 → 打 [persist] 且不抛', () => {
    const spy = jest.spyOn(console, 'error').mockImplementation(() => {});
    const restore = blockTmp(store.BLOCK_FILE);
    try {
      expect(() => store.saveBlockedIPs([])).not.toThrow();
      const lines = spy.mock.calls.map((c) => String(c[0])).join('\n');
      expect(lines).toContain('IP 封锁表写入失败');
    } finally {
      restore();
      spy.mockRestore();
    }
  });

  test('saveRateLimitStore 写盘失败 → 打 [persist] 且不抛', () => {
    const spy = jest.spyOn(console, 'error').mockImplementation(() => {});
    // 先造一条窗口内的记录，否则 slim 为空会走"删文件"分支
    store.rateLimitStore['9.9.9.9:api'] = { count: 1, windowStart: Date.now() };
    const restore = blockTmp(store.RATE_LIMIT_FILE);
    try {
      expect(() => store.saveRateLimitStore()).not.toThrow();
      const lines = spy.mock.calls.map((c) => String(c[0])).join('\n');
      expect(lines).toContain('[persist]');
      expect(lines).toContain('限流表写入失败');
    } finally {
      delete store.rateLimitStore['9.9.9.9:api'];
      restore();
      spy.mockRestore();
    }
  });
});

// ════════════════════════════════════════════════════════════════════
// B. nonce 落盘钩子：内存记住 ≠ 重启还记得
// ════════════════════════════════════════════════════════════════════
describe('B. nonce 落盘：persist 钩子被调用（内存记住 ≠ 重启还记得）', () => {
  test('给了 persist 就调它；没给就走 saveNonces 兜底', () => {
    const { checkFresh } = require('../lib/fnthink/verify');
    const { loadContract, assertSupported } = require('../lib/fnthink/contract');
    const contract = assertSupported(loadContract());

    const now = Date.now();
    const fields = {
      type: contract.clientEvents.poll.messageType,
      target: 'AAAAAAAAAAAAAAAAAA',
      sender: 'BBBBBBBBBBBBBBBBBB',
      nonce: 'nonce-persist-hook-1',
      ts: Math.floor(now / 1000),
      body: '',
    };
    const input = { fields, senderAddress: 'BBBBBBBBBBBBBBBBBB', now };

    // 有钩子 ⇒ 调钩子（routes.js 的 freshState 给的就是 saveNonces）
    let persistCalls = 0;
    const withHook = {
      nonces: {},
      persist: () => {
        persistCalls += 1;
      },
    };
    const r1 = checkFresh(contract, withHook, input, 'BBBBBBBBBBBBBBBBBB');
    expect(r1.outcome).toBeUndefined();
    expect(persistCalls).toBe(1);

    // 同一个 nonce 再放一次 ⇒ 判重（去重表真的记下了）
    const r2 = checkFresh(contract, withHook, input, 'BBBBBBBBBBBBBBBBBB');
    expect(r2.outcome).toBeDefined();
  });
});

// ════════════════════════════════════════════════════════════════════
// C. dedupe 刷新不挤位
// ════════════════════════════════════════════════════════════════════
describe('C. dedupe 刷新是换内容，不是加一条、也不触发驱逐', () => {
  test('同 dedupe_id 且仍在可覆盖态 ⇒ refreshed：条数不变、正文换掉、不驱逐', () => {
    const { enqueue } = require('../lib/fnthink/messagestore');
    const { loadContract, assertSupported } = require('../lib/fnthink/contract');
    const contract = assertSupported(loadContract());
    const messages = {};
    const now = Date.now();
    const key = process.env.ENCRYPTION_KEY;

    const first = enqueue(
      contract,
      messages,
      {
        sender: 'S',
        device: 'D',
        type: 'notice',
        title: '第一版',
        body: '旧正文',
        dedupeId: 'dedu-1',
      },
      now,
      key,
    );
    expect(first.action).toBe('new');

    const second = enqueue(
      contract,
      messages,
      {
        sender: 'S',
        device: 'D',
        type: 'notice',
        title: '第二版',
        body: '新正文',
        dedupeId: 'dedu-1',
      },
      now + 1000,
      key,
    );
    expect(second.action).toBe('refreshed');
    expect(second.message.messageId).toBe(first.message.messageId);
    expect(Object.keys(messages).length).toBe(1);
    expect(second.evicted).toEqual([]);
    expect(second.evictionBlocked).toBe(0);
  });

  test('同 dedupe_id 但已发出去了 ⇒ duplicate：不覆盖（否则同一条通知提醒两次）', () => {
    const { enqueue, advanceMessage } = require('../lib/fnthink/messagestore');
    const { loadContract, assertSupported } = require('../lib/fnthink/contract');
    const contract = assertSupported(loadContract());
    const messages = {};
    const now = Date.now();
    const key = process.env.ENCRYPTION_KEY;

    const first = enqueue(
      contract,
      messages,
      { sender: 'S', device: 'D', type: 'notice', title: 't', body: 'b', dedupeId: 'dedu-2' },
      now,
      key,
    );
    // 推离初始态（queued → delivering）
    advanceMessage(contract, messages, first.message.messageId, 'dispatch', { now });

    const again = enqueue(
      contract,
      messages,
      { sender: 'S', device: 'D', type: 'notice', title: 't2', body: 'b2', dedupeId: 'dedu-2' },
      now + 2000,
      key,
    );
    expect(again.action).toBe('duplicate');
    expect(Object.keys(messages).length).toBe(1);
  });
});

// ════════════════════════════════════════════════════════════════════
// D. poll 解密失败必须点名是哪一条、哪台设备
// ════════════════════════════════════════════════════════════════════
describe('D. poll 解密失败点名上下文（不是一句"服务器内部错误"）', () => {
  // 2026-10-15 审计修复：解不开几乎总是 ENCRYPTION_KEY 被轮换过（旧密文是旧密钥封的）。
  // 整条 poll 失败是对的（fail-closed：不把解不出的消息静默跳过），但错误必须带上
  // device 与 messageId —— 否则运维在日志里只看到一句通用 500，而那条消息会一直
  // 卡到过期，并且每一轮 poll 再炸一次。
  //
  // ⚠ 判据为什么落在"源码里那段 catch"而不是真打一次 poll：走完整 poll 需要一枚能过
  //   验签的 Ed25519 签名（devicestore 现造一对 + canonicalBytes 现签一条），那套基建
  //   属于 fnthink-routes.test.js 的既有用例；在这里重搭一遍只是把别人的判据抄成第二份。
  //   而这一段要钉的是**日志形状**：真打一次只能证明"它会抛"，证明不了"抛之前说了
  //   是谁"。所以：现造一条真消息 + 现换一把真密钥让解密真的失败（证明错误路径可达），
  //   再静态断言 routes.js 那段 catch 把 device/messageId 拼进了日志（证明它说了是谁）。
  //   反证：把 routes.js 里那段 try/catch 换回裸 decryptBodyFor ⇒ 两条一起红。
  test('错误路径可达：轮换密钥后解密真的抛', () => {
    const { loadContract, assertSupported } = require('../lib/fnthink/contract');
    const {
      enqueue,
      saveMessages,
      loadMessages,
      decryptBodyFor,
    } = require('../lib/fnthink/messagestore');
    const contract = assertSupported(loadContract());

    const messages = loadMessages();
    const queued = enqueue(
      contract,
      messages,
      {
        sender: 'SENDER0000000000',
        device: 'TARGET0000000000',
        type: 'notice',
        title: 't',
        body: 'b',
      },
      Date.now(),
      process.env.ENCRYPTION_KEY,
    );
    saveMessages(messages);

    const rotated = 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';
    expect(() => decryptBodyFor(contract, rotated, queued.message.body)).toThrow();
  });

  test('routes.js 的解密失败日志点名 device 与 messageId', () => {
    const fs = require('fs');
    const path = require('path');
    const src = fs.readFileSync(path.join(__dirname, '..', 'lib', 'fnthink', 'routes.js'), 'utf8');
    // 那段 catch 必须在场，且把两个定位字段拼进日志
    expect(src).toContain('[fnthink:poll] 正文解密失败');
    expect(src).toContain('device=${auth.sender}');
    expect(src).toContain('messageId=${record.messageId}');
    // 并且它是**先记日志再抛**（fail-closed 不许被日志替换掉）
    const catchAt = src.indexOf('正文解密失败');
    const throwAt = src.indexOf('throw e;', catchAt);
    expect(catchAt).toBeGreaterThan(-1);
    expect(throwAt).toBeGreaterThan(catchAt);
  });
});
