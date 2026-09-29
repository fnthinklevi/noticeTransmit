// T45 第一片：管理面的**投递状态读口**（GET /api/admin/fnthink/messages）。
//
// 这一片真正在守的四件事：
//  ① **一行投递记录里没有正文，也没有密信封与 dedupe 摘要** —— 「审计只存元数据」
//     （privacy.auditStoresMetadataOnly）在读口这一侧才算数：盘上加密、接口端出明文，
//     等于把 7 天保留期变成"任何时候都能从管理面捞一遍正文"。
//  ② **档位计数不受筛选影响**（先数后筛）：筛选后的那份计数会让运维把"这一档 3 条"
//     读成"整张表 3 条"，而这两句话在"要不要冻结"上是相反的决定。
//  ③ **数字从契约读，且用例喂的是改过数值的契约副本**（与 X5、Z4、SA1、RC1 同一类假绿：
//     拿实现读的同一份契约去断言，"写死"与"读契约"当场分不出来）。
//  ④ **这个口只在管理面**：协议面没有"查看投递"这个角色（delivery.senderPollsStatusEndpoint
//     明写 false，回执由状态机当作一条消息推回发送端）。挂到协议面就要为"谁能看别人的投递"
//     再造一套判据 —— 那是第二个信任根。
//
// ⚠ 刻意**没有**时间线相关的用例：表里今日只有当前态 + queuedAt/updatedAt/attempts/receipt，
//    "几点下发、几点 ack"要等推进留痕那片才有出处。为它写断言就是逼实现编一份日志出来。
//
// 反证（2026-09-29，十条全 named + restored，基线先验过绿；报告 `outputs/_msgview.report.txt`）：
// MD1 投影多带一个 body 字段 / MD2 先筛后数 / MD3 上限不夹 / MD4 排序反向 / MD5 非法档位不拒 /
// MD6 垃圾地址码不验形状 / MD7 设备不在表里也编在线时刻 / MD8 terminal 写死词表 /
// MD9 expiresAt 写死 7 天 / MD10 路由自己拼一行。
// MD9 与本文件那条"喂改过数值的契约副本"是同一件事的两面：**没有那份副本，写死与读契约红不出来**
// （X5/Z4/SA1/RC1 四次撞的同一个坑，这是第五次，只是这次在第一片就避开了）。
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-msgview-'));
const ADMIN_TOKEN = 'test-admin-token-for-msgview';
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync(ADMIN_TOKEN, 10);
process.env.ENCRYPTION_KEY = 'd'.repeat(64);
process.env.RATE_LIMIT_AUTH_MAX = '100000';
process.env.RATE_LIMIT_GENERAL_MAX = '100000';

const request = require('supertest');
const app = require('../lib/app');
const { loadContract, assertSupported } = require('../lib/fnthink/contract');
const devicestore = require('../lib/fnthink/devicestore');
const store = require('../lib/fnthink/messagestore');

const contract = assertSupported(loadContract());
const DAY = 24 * 60 * 60 * 1000;
const T0 = 1_700_000_000_000;
const KEY = 'b'.repeat(40);

const CODES = {
  A: '8K3FJ6QPTM9WZ4VHNS',
  B: '7YD4RKQPBM8XZ3VHNT',
};

function keypair() {
  const { publicKey } = crypto.generateKeyPairSync('ed25519');
  const der = publicKey.export({ type: 'spki', format: 'der' });
  return der.subarray(der.length - 32).toString('base64');
}

function register(addressCode, lastSeenAt) {
  const devices = devicestore.loadDevices();
  devicestore.registerDevice(
    contract,
    devices,
    { addressCode, publicKey: keypair(), name: '投递视图' },
    T0,
  );
  if (lastSeenAt !== undefined) devices[addressCode].lastSeenAt = lastSeenAt;
  devicestore.saveDevices(devices);
}

/// 往**盘上那张表**写一条（走真入口 enqueue + saveMessages，不手搓行形状：
/// 手搓的行可以正好避开落盘闸门，于是用例绿而真实数据长得不一样）。
/// `events` 是一串状态机事件（queued 上直接 ack_ok 会被判 ignored，所以要按迁移表走）。
function put({ device = CODES.A, seq = 1, sender = CODES.B, at = T0, events = [] } = {}) {
  const messages = store.loadMessages();
  const { message } = store.enqueue(
    contract,
    messages,
    {
      device,
      sender,
      type: 'notice',
      item: 'app:view',
      title: `标题${seq}`,
      body: `正文${seq}-SECRET-MARKER-${seq}`,
      dedupeId: `dedupe-${seq}`,
    },
    at,
    KEY,
  );
  let now = at;
  for (const event of events) {
    now += 1000;
    store.advanceMessage(contract, messages, message.messageId, event, { now });
  }
  store.saveMessages(messages);
  return message.messageId;
}

/// 排队 → 已下发 → 已送达：投递走完整的那条路（终态才有回执）
const TO_DELIVERED = ['dispatch', 'ack_ok'];

const clearTable = () => store.saveMessages({});

let sessionId = null;
const get = async (query = '') => {
  const res = await request(app)
    .get(`/api/admin/fnthink/messages${query}`)
    .set('x-session-id', sessionId);
  return res;
};

function readSource(rel) {
  return fs.readFileSync(path.join(__dirname, rel), 'utf8');
}

/// 去掉整行注释（本仓 JS 注释一律独占一行），免得源码守卫把注释里的词当成代码。
function stripComments(src) {
  return src
    .split('\n')
    .filter((line) => !/^\s*(\/\/|\/\*|\*)/.test(line))
    .join('\n');
}

beforeAll(async () => {
  const login = await request(app).post('/api/admin/login').send({ token: ADMIN_TOKEN });
  expect(login.status).toBe(200);
  sessionId = login.body.sessionId;
});

describe('投递状态读口（T45 第一片）', () => {
  beforeEach(() => clearTable());

  test('未登录读不到：这份视图知道谁在给谁发消息', async () => {
    const anon = await request(app).get('/api/admin/fnthink/messages');
    expect(anon.status).toBe(401);
  });

  test('空表也是一份答复：每个契约状态都有键（0 与"没这一档"不能同形）', async () => {
    const res = await get();
    expect(res.status).toBe(200);
    expect(res.body.data.messages).toEqual([]);
    expect(res.body.data.total).toBe(0);
    expect(res.body.data.truncated).toBe(false);
    for (const name of contract.delivery.states) {
      expect(res.body.data.states).toHaveProperty(name, 0);
    }
  });

  test('一行里只有元数据：正文、密信封与 dedupe 摘要都不出门', async () => {
    put({ seq: 7 });
    const res = await get();
    expect(res.status).toBe(200);
    const row = res.body.data.messages[0];
    expect(row.type).toBe('notice');
    expect(Object.keys(row).sort()).toEqual(
      [
        'attempts',
        'device',
        'expiresAt',
        'hasBody',
        'item',
        'messageId',
        'queuedAt',
        'receipt',
        'receiptSentAt',
        'sender',
        'state',
        'targetLastSeenAt',
        'terminal',
        'type',
        'updatedAt',
      ].sort(),
    );
    expect(row.hasBody).toBe(true);
    // 整份响应文本里搜不到明文（不是"这一行没有 body 键"那么弱：信封要是被换个键名端出去，
    // 键名断言抓不到，而"能不能从管理面捞出正文"抓得到）。
    expect(JSON.stringify(res.body)).not.toContain('SECRET-MARKER');
    expect(res.text).not.toContain('dedupeIdDigest');
    expect(res.text).not.toContain('dedupe-7');
  });

  test('终态那一行：terminal 为真且正文已释放（这一对就是不变量的现场体检）', async () => {
    const id = put({ seq: 11, events: TO_DELIVERED });
    const res = await get(`?state=${contract.delivery.terminalStates[0]}`);
    expect(res.status).toBe(200);
    expect(res.body.data.messages.map((m) => m.messageId)).toEqual([id]);
    const row = res.body.data.messages[0];
    expect(row.state).toBe('delivered');
    expect(row.terminal).toBe(true);
    expect(row.hasBody).toBe(false);
    // 「终态必有回执」也在这里看得见：receipt 是状态机写的，不是路由猜的
    expect(row.receipt).toBe('delivered');
  });

  test('state 筛选：非法档位 400，合法档位只回那一档而计数仍是全表的', async () => {
    put({ seq: 1, device: CODES.A });
    put({ seq: 2, device: CODES.A, events: TO_DELIVERED });
    put({ seq: 3, device: CODES.B });

    const bad = await get('?state=not_a_state');
    expect(bad.status).toBe(400);
    // 说清能填什么：运维面不是只有写过这份代码的人能用
    expect(bad.body.message).toContain(contract.delivery.states.join(' / '));

    const queued = await get(`?state=${contract.delivery.initialState}`);
    expect(queued.status).toBe(200);
    expect(queued.body.data.total).toBe(2);
    expect(queued.body.data.messages.every((m) => m.state === 'queued')).toBe(true);
    // 全表计数：3 条里 2 条 queued、1 条 delivered。**筛完还数全表**是这条用例的全部内容。
    // 期望值按契约词表搭（写死状态名 ⇒ 契约改名时这条红在"找不到那一档"，而不是"计数不对"）
    const expected = {};
    for (const name of contract.delivery.states) expected[name] = 0;
    expected[contract.delivery.initialState] = 2;
    expected[contract.delivery.terminalStates[0]] = 1;
    expect(queued.body.data.states).toEqual(expected);
  });

  test('device 筛选：垃圾地址码是 400，不是"筛出一条都没有"', async () => {
    put({ seq: 4, device: CODES.A });
    // I L O U 不在 Crockford 字母表里（与设备侧那批测试同一条坑）
    const bad = await get('?device=AAAA');
    expect(bad.status).toBe(400);
    expect(bad.body.message).toContain('地址码');

    const mine = await get(`?device=${CODES.A}`);
    expect(mine.status).toBe(200);
    expect(mine.body.data.total).toBe(1);
    const other = await get(`?device=${CODES.B}`);
    expect(other.body.data.total).toBe(0);
  });

  test('上限与 truncated：一份"没列全"与一份"就只有这些"是相反的两个结论', async () => {
    for (const seq of [1, 2, 3]) put({ seq, at: T0 + seq * 1000 });
    const res = await get('?limit=2');
    expect(res.status).toBe(200);
    expect(res.body.data.total).toBe(3);
    expect(res.body.data.returned).toBe(2);
    expect(res.body.data.truncated).toBe(true);
    expect(res.body.data.messages).toHaveLength(2);
    // 超过契约 ops.listMaxRows 的请求要被夹住，不是"给多少取多少"
    const over = await get(`?limit=${contract.ops.listMaxRows + 50}`);
    expect(over.body.data.limit).toBe(contract.ops.listMaxRows);
  });

  test('排序：最近有动静的在最前，同一时刻按 id 定序（不靠对象遍历顺序）', async () => {
    const old = put({ seq: 1, at: T0 });
    const fresh = put({ seq: 2, at: T0 + 5 });
    // 第一条后来被投递并 ack 了 ⇒ updatedAt 反超，而它是最早排队的
    const messages = store.loadMessages();
    store.advanceMessage(contract, messages, old, 'dispatch', { now: T0 + 50000 });
    store.advanceMessage(contract, messages, old, 'ack_ok', { now: T0 + 99999 });
    store.saveMessages(messages);

    const res = await get();
    const ids = res.body.data.messages.map((m) => m.messageId);
    expect(ids).toEqual([old, fresh]);
  });

  test('targetLastSeenAt：表里有那台才带时间，没有就 null（不编一个"从未在线"）', async () => {
    register(CODES.A, T0 + 4242);
    put({ seq: 5, device: CODES.A });
    const seen = await get();
    expect(seen.body.data.messages[0].targetLastSeenAt).toBe(T0 + 4242);

    clearTable();
    put({ seq: 6, device: CODES.B });
    const unknown = await get();
    expect(unknown.body.data.messages[0].targetLastSeenAt).toBeNull();
  });
});

describe('投影本身（纯函数，喂的是改过数值的契约副本）', () => {
  test('expiresAt 从契约 maxRetentionDays 算：改成 2 天就必须说 2 天', () => {
    // ⚠ 这条是防那第四次撞上的同一个坑（X5/Z4/SA1/RC1）的：如果拿真契约去断言，
    //    "写死 7 天"与"读契约"算出来是同一个数，植入反证就红不了。
    const mutated = JSON.parse(JSON.stringify(contract));
    mutated.retention.maxRetentionDays = 2;
    const row = store.publicMessage(mutated, {
      messageId: 'm_x',
      device: CODES.A,
      state: mutated.delivery.initialState,
      attempts: 0,
      queuedAt: T0,
      updatedAt: T0,
    });
    expect(row.expiresAt).toBe(T0 + 2 * DAY);
    expect(row.expiresAt).not.toBe(T0 + 7 * DAY);
    expect(row.terminal).toBe(false);
    expect(row.hasBody).toBe(false);
  });

  test('terminal 判的是契约那一组，不是"state 等不等于某个词"', () => {
    const mutated = JSON.parse(JSON.stringify(contract));
    // 把终态名单换成只认 waiting_online：如果实现是写死词表，这里不会跟着变
    mutated.delivery.terminalStates = ['waiting_online'];
    const inTable = mutated.delivery.terminalStates;
    const mk = (state) =>
      store.publicMessage(mutated, {
        messageId: 'm_y',
        device: CODES.A,
        state,
        attempts: 1,
        queuedAt: T0,
        updatedAt: T0,
      }).terminal;
    expect(mk(inTable[0])).toBe(true);
    expect(mk('delivered')).toBe(false);
  });

  test('缺字段不留 undefined：sender/receipt 读不出来时是空串与 null', () => {
    const row = store.publicMessage(contract, {
      messageId: 'm_z',
      device: CODES.A,
      state: contract.delivery.states[0],
      attempts: 0,
      queuedAt: T0,
      updatedAt: T0,
    });
    expect(row.sender).toBe('');
    expect(row.receipt).toBeNull();
    expect(row.receiptSentAt).toBeNull();
    expect(Object.values(row).some((v) => v === undefined)).toBe(false);
  });
});

describe('结构与形状的守卫（断契约，也断"这个口开在哪"）', () => {
  test('协议面没有投递读口：这个形状只住在管理面', () => {
    const routes = stripComments(readSource('../lib/fnthink/routes.js'));
    // 按"注册了一条什么路径"判，不按子串判：`require('./messagestore')` 里就带着 `/messages`
    expect(routes).not.toMatch(/router\.(get|post|put|delete)\(\s*['"`][^'"`]*messages/i);
    // 发送端不轮询状态接口，是契约写的，不是这里选的
    expect(contract.delivery.senderPollsStatusEndpoint).toBe(false);
  });

  test('路由自己不许拼行：一行投递记录的形状只有 messagestore 一个出处', () => {
    const ops = stripComments(readSource('../lib/routes/ops.js'));
    const from = ops.indexOf("'/fnthink/messages'");
    expect(from).toBeGreaterThan(-1);
    const body = ops.slice(from, ops.indexOf('// ── 端点（T38）', from));
    expect(body).toContain('ms.publicMessage(');
    // 在路由里自己挑字段 = 第二份"哪些字段能出门"的名单，
    // 而它会比投影先忘记 body 不该出门
    expect(body).not.toContain('message.body');
    expect(body).not.toContain('dedupeIdDigest');
  });

  test('messagestore 不许出现投递状态名字面量（投影也算这一条）', () => {
    const src = stripComments(readSource('../lib/fnthink/messagestore.js'));
    for (const name of contract.delivery.states) {
      expect(new RegExp(`['"\`]${name}['"\`]`).test(src)).toBe(false);
    }
    // 事件名不在这一条里：dispatch / peer_online / ttl_elapsed 是本模块**主动发起**的动作，
    // 那是出处，不是第二份真值（第二份真值长什么样的例子见上面那批状态名）。
  });
});
