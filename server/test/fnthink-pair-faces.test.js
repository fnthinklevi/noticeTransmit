// 配对请求的**两面**（T110 第一片）：同一条记录，两个主语各有一份读口。
//
// 这一批用例盯的是维护者那句「新设备匹配时我填了地址码和口令，对方设备怎么看待匹配？
// 我怎么看对方进度？」里、今天在服务端缺的那一半：
//  ① 发起方（B）以前没有任何读口 —— `pair` 之后他只知道自己"提交过"，之后走到哪儿全是猜；
//  ② 两面必须**各回各的**：接收面按 `target` 选、只给 pending；发起面按 `requester` 选、
//     **含终态**（发起方要的恰恰是"后来怎么样了"）。一份名单两用是这里最省事的错：
//     要么发起方永远看不见终态，要么接收方多收到别人名下的行；
//  ③ 口令面（T110 ③）：发起方那一份投影里**既没有明文也没有摘要** —— 明文只活在那一次输入里，
//     而摘要是"能拿去比对的东西"（`endpointList._neverReturnsSecretWhy` 同一条论证），
//     多一处出口就多一处能漏的地方，且这一面拿它换不到任何信息（那枚口令本来就是他用过的）；
//  ④ 「多久之前」要有出处：状态变更那一刻在表里叫 `statusChangedAt`（答复与到期扫描**共用**这一列，
//     原先答复那一支写的是 `decidedAt` ⇒ 同一件事两个列名），出门叫 `at` —— 与 T105 片③ 的回执
//     同一个词。pending 那一条还没变过状态 ⇒ `at` = 0（"还不知道"），宁可不给也不拿当下凑。
//
// 键名、投影名单、状态词都从契约现取（测试里不写死 `'sentPairRequests'`／`'approved'`），
// 否则契约改名那天这些用例会红成一堆"看着像实现坏了"的样子。
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-pair-faces-'));
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-pair-faces', 10);
process.env.ENCRYPTION_KEY = 'a'.repeat(64);
process.env.RATE_LIMIT_GENERAL_MAX = '100000';
process.env.RATE_LIMIT_AUTH_MAX = '100000';

const request = require('supertest');
const app = require('../lib/app');
const {
  loadContract,
  assertSupported,
  canonicalOrder,
  statusCode,
} = require('../lib/fnthink/contract');
const verify = require('../lib/fnthink/verify');
const pairstore = require('../lib/fnthink/pairstore');

const contract = assertSupported(loadContract());

// ⚠ 测试地址码一律避开 I L O U（Crockford base32 的字母表里没有那四个，写了就是"非法地址码"，
//   后面整条链会红在身份没证明那一步，而不是本题）。
const HOST = '8K3FJ6QPTM9WZ4VHNS'; // 被投的那台 = 做决定的人（A）
const MINE = '7YD4RKQPBM8XZ3VHNT'; // 发起配对的那台（B）—— 本文件的主角
const OTHER = '8TQVWZ3XKR5B6YD4HM'; // 与这次配对无关的第三台

function keypair() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const der = publicKey.export({ type: 'spki', format: 'der' });
  return { rawBase64: der.subarray(der.length - 32).toString('base64'), privateKey };
}

const hostKey = keypair();
const mineKey = keypair();
const otherKey = keypair();

function sign(kp, fields) {
  const map = {};
  for (const key of canonicalOrder(contract)) map[key] = fields[key];
  const canonical = verify.canonicalBytes(contract, map);
  return {
    map,
    signature: crypto.sign(null, canonical, kp.privateKey).toString('base64'),
  };
}

function evBody(kind, kp, sender, target, payloadObj) {
  const spec = contract.clientEvents[kind];
  const signed = sign(kp, {
    version: '1',
    type: spec.messageType,
    target,
    ts: String(Math.floor(Date.now() / 1000)),
    nonce: 'pf-' + crypto.randomBytes(6).toString('hex'),
    body: payloadObj === undefined ? '' : JSON.stringify(payloadObj),
  });
  return { sender, signature: signed.signature, fields: signed.map };
}

function regBody(addressCode, kp) {
  const signed = sign(kp, {
    version: '1',
    type: contract.clientEvents.register.messageType,
    target: addressCode,
    ts: String(Math.floor(Date.now() / 1000)),
    nonce: 'pf-rg-' + crypto.randomBytes(6).toString('hex'),
    body: '',
  });
  return {
    sender: addressCode,
    publicKey: kp.rawBase64,
    name: '两面用例',
    signature: signed.signature,
    fields: signed.map,
  };
}

/// 一次完整的「A 挂口令 + B 扫并签一条握手」，返回那条请求的 id。
/// 每条用例自己走一遍并自带一枚没消耗过的口令：口令是 singleUse 的，共用一枚会让第二条
/// 红在"口令已消耗"上而不是本题。
async function pairUp(code, level, target) {
  const to = target || HOST;
  const armKey = to === HOST ? hostKey : otherKey;
  await request(app)
    .post('/api/fnthink/pair-arm')
    .send(evBody('pairArm', armKey, to, to, { pairingCode: code }))
    .expect(200);
  const res = await request(app)
    .post('/api/fnthink/pair')
    .send(evBody('pair', mineKey, MINE, to, { pairingCode: code, level }))
    .expect(statusCode(contract, 'queued'));
  expect(res.body.requestId).toMatch(/^pr_/);
  return res.body.requestId;
}

async function poll(kp, addressCode) {
  const res = await request(app)
    .post('/api/fnthink/poll')
    .send(evBody('poll', kp, addressCode, addressCode))
    .expect(200);
  return res.body;
}

/// 发起方那一面（键名来自契约，不在这里写死）。
const outgoingOf = (body) => body[contract.pairRequest.sentPollKey];
/// 接收方那一面。
const incomingOf = (body) => body[contract.pairRequest.pollKey];

describe('poll 的两面（T110：谁在请求配对你 / 我发起的那条走到了哪儿）', () => {
  beforeAll(async () => {
    for (const [code, kp] of [
      [HOST, hostKey],
      [MINE, mineKey],
      [OTHER, otherKey],
    ]) {
      await request(app).post('/api/fnthink/register').send(regBody(code, kp)).expect(200);
    }
  });

  beforeEach(() => {
    // 每条用例从空请求表开始：`perDeviceLimit` 只有 3，同面的残留会把配额填满，
    // 而"这一面读到几条"这类断言最怕的就是上一轮那条还挂着。
    if (fs.existsSync(pairstore.REQUEST_FILE)) fs.rmSync(pairstore.REQUEST_FILE);
  });

  test('刚提交：发起方能读到自己那一条 pending，而这一条不在他的接收面上', async () => {
    await pairUp('ABCDEFGHJKMNPQRSTVWX', 'L1');

    const body = await poll(mineKey, MINE);
    const sent = outgoingOf(body);
    expect(sent).toHaveLength(1);
    expect(sent[0].status).toBe(contract.pairRequest.initialStatus);
    expect(sent[0].target).toBe(HOST);
    expect(sent[0].level).toBe('L1');
    // 主语没串：这一面是"我发起的"，而他名下此刻没有"别人请求配对他"的行。
    expect(incomingOf(body)).toHaveLength(0);
    // 还没人改过状态 ⇒"什么时候变的"就是不知道（0），界面那句要跟着不说，而不是拿当下凑。
    expect(sent[0].at).toBe(0);
    // 多久之前的出处在这一条里（发起时刻由服务端给，本机时钟不算数）。
    expect(Number(sent[0].createdAt)).toBeGreaterThan(0);
  });

  test('两面各回各的：同一时刻 A 的接收面有这一条、他的发起面空着；第三台两面都空', async () => {
    const requestId = await pairUp('BDEFGHJKMNPQRSTVWX23', 'L1');

    const host = await poll(hostKey, HOST);
    expect(incomingOf(host)).toHaveLength(1);
    expect(incomingOf(host)[0].id).toBe(requestId);
    expect(outgoingOf(host)).toHaveLength(0);

    // 无关的第三台：既不是这条的 target 也不是 requester ⇒ 一行都读不到。
    // （这条同时挡住"忘了按主语过滤"：忘了的话这一面就成了跨设备枚举配对请求的读口。）
    const stranger = await poll(otherKey, OTHER);
    expect(incomingOf(stranger)).toHaveLength(0);
    expect(outgoingOf(stranger)).toHaveLength(0);
  });

  test('发起面投影的键集合 == 契约 pairRequest.sentFields（名单是两份实现唯一的共同出处）', async () => {
    await pairUp('CFGHJKMNPQRSTVWX2345', 'L1');
    const sent = outgoingOf(await poll(mineKey, MINE));
    // 先确认有货：0 条会让下面这个 for 空转，从而"名单没实现"也能绿（假绿）。
    expect(sent).toHaveLength(1);
    for (const item of sent) {
      expect(Object.keys(item).sort()).toEqual([...contract.pairRequest.sentFields].sort());
    }
  });

  test('口令一面都不出门：发起面里既没有明文也没有摘要（③ 只放地址码与状态）', async () => {
    const code = 'DFGHJKMNPQRSTVWX2347';
    const requestId = await pairUp(code, 'L1');
    // 表里那条的摘要（接收方那一面确实要拿它比对，所以它**在盘上**、也在接收面的投影里）。
    const digest = pairstore.loadRequests()[requestId].codeDigest;

    const text = JSON.stringify(outgoingOf(await poll(mineKey, MINE)));
    expect(text).not.toContain(code);
    expect(text).not.toContain(digest);
    expect(text).not.toContain('codeDigest');
    // 他自己的公钥也不复述（那就是他手上那把，回一遍只是多一处能漏的地方）。
    expect(text).not.toContain(mineKey.rawBase64);
    // 对照：同一时刻接收面**确实**带着摘要 —— 这一面把它拿掉是刻意的，不是投影整个漏了。
    expect(JSON.stringify(incomingOf(await poll(hostKey, HOST)))).toContain(digest);
  });

  test('A 批准 ⇒ 发起方读到 approved 且 `at` 是批准那一刻；A 自己的接收面不再列这条', async () => {
    const requestId = await pairUp('EFGHJKMNPQRSTVWX2348', 'L1');

    const before = Date.now();
    await request(app)
      .post('/api/fnthink/pair-confirm')
      .send(
        evBody('pairConfirm', hostKey, HOST, MINE, {
          requestId,
          decision: contract.clientEvents.pairConfirm.approveDecision,
          level: 'L1',
        }),
      )
      .expect(200);
    const after = Date.now();

    const sent = outgoingOf(await poll(mineKey, MINE));
    const mine = sent.find((r) => r.id === requestId);
    expect(mine.status).toBe(contract.clientEvents.pairConfirm.approveDecision);
    // 那个时刻必须是"批准这一次"：既晚于请求成立，也不许是设备侧自己估的当下。
    expect(Number(mine.at)).toBeGreaterThanOrEqual(before);
    expect(Number(mine.at)).toBeLessThanOrEqual(after);
    expect(Number(mine.at)).toBeGreaterThan(Number(mine.createdAt));
    // 状态词必须落在契约那个封闭集里（界面按它取词，词表外的值只能画成"不认识"）。
    expect(contract.pairRequest.statuses).toContain(mine.status);

    // 同一张表、另一种主语：A 的接收面此刻不该还挂着这条（他已经答过了）。
    const host = incomingOf(await poll(hostKey, HOST));
    expect(host.find((r) => r.id === requestId)).toBeUndefined();
  });

  test('A 拒绝 ⇒ 发起方读到 denied（拒绝也是一个结论，不是"列表里悄悄少一条"）', async () => {
    const requestId = await pairUp('FGHJKMNPQRSTVWX23490', 'L1');
    const deniedWord = contract.pairRequest.terminalStatuses.find(
      (s) => s !== contract.clientEvents.pairConfirm.approveDecision && s !== 'expired',
    );

    await request(app)
      .post('/api/fnthink/pair-confirm')
      .send(
        evBody('pairConfirm', hostKey, HOST, MINE, {
          requestId,
          decision: deniedWord,
          level: 'L1',
        }),
      )
      .expect(200);

    const mine = outgoingOf(await poll(mineKey, MINE)).find((r) => r.id === requestId);
    expect(mine.status).toBe(deniedWord);
    expect(Number(mine.at)).toBeGreaterThan(0);
  });

  test('一次发起给两台：发起面两条都在且按发起时刻正序，接收面各自只看见自己那一条', async () => {
    const first = await pairUp('HJKMNPQRSTVWX2349012', 'L1');
    const second = await pairUp('JKNMNPQRSTVWX2349012', 'L1', OTHER);

    const sent = outgoingOf(await poll(mineKey, MINE));
    expect(sent.map((r) => r.id)).toEqual([first, second]);
    expect(sent.map((r) => r.target)).toEqual([HOST, OTHER]);
    const times = sent.map((r) => Number(r.createdAt));
    expect(times).toEqual([...times].sort((a, b) => a - b));

    // HOST 那台只看得见投向自己那条；另一条在它自己的接收面上不存在（也不该在 OTHER 那里）。
    expect(incomingOf(await poll(hostKey, HOST)).map((r) => r.id)).toEqual([first]);
    expect(incomingOf(await poll(otherKey, OTHER)).map((r) => r.id)).toEqual([second]);
  });

  test('一次状态变更只留一个时刻列（decidedAt 那个名字已经并掉，不许长回来）', async () => {
    const requestId = await pairUp('KMPQRSTVWX2349012345', 'L1');
    await request(app)
      .post('/api/fnthink/pair-confirm')
      .send(
        evBody('pairConfirm', hostKey, HOST, MINE, {
          requestId,
          decision: contract.clientEvents.pairConfirm.approveDecision,
          level: 'L1',
        }),
      )
      .expect(200);
    const record = pairstore.loadRequests()[requestId];
    expect(Number(record.statusChangedAt)).toBeGreaterThan(0);
    // 旧名字回来 = 同一件事两个列名回来了 = 投影与界面又要猜哪一个非空。
    expect(record.decidedAt).toBeUndefined();
  });
});

describe('发起面那份名单不达标 ⇒ 读口抛（可降级的契约内容不达标，不是每轮 poll 冒 500）', () => {
  const broken = (mutate) => {
    const c = JSON.parse(JSON.stringify(contract));
    mutate(c);
    return c;
  };

  test('真实契约这一对读口不抛（判据自证：别把"永远抛"当"有效"）', () => {
    expect(() => {
      pairstore.sentPollKey(contract);
      pairstore.sentFields(contract);
    }).not.toThrow();
  });

  test('缺 sentPollKey ⇒ 抛（发起了请求的那台没有读口）', () => {
    expect(() => pairstore.sentPollKey(broken((c) => delete c.pairRequest.sentPollKey))).toThrow(
      /sentPollKey/,
    );
  });

  test('两面同名 ⇒ 抛（一次响应里两面互相盖掉，被盖的那面在屏幕上看不出来）', () => {
    expect(() =>
      pairstore.sentPollKey(broken((c) => (c.pairRequest.sentPollKey = c.pairRequest.pollKey))),
    ).toThrow(/同名/);
  });

  test('投影名单为空 ⇒ 抛（实现只能自己拼一份，那是第二份真值）', () => {
    expect(() => pairstore.sentFields(broken((c) => (c.pairRequest.sentFields = [])))).toThrow(
      /sentFields/,
    );
  });

  test('少了 status／createdAt／at 之一 ⇒ 抛（这一面答的就是这三句）', () => {
    for (const must of ['status', 'createdAt', 'at']) {
      expect(() =>
        pairstore.sentFields(
          broken(
            (c) => (c.pairRequest.sentFields = c.pairRequest.sentFields.filter((f) => f !== must)),
          ),
        ),
      ).toThrow(new RegExp(must));
    }
  });

  test('名单里有摘要 ⇒ 抛（发起方不需要它，而一份能比对的摘要多一处出口）', () => {
    expect(() =>
      pairstore.sentFields(broken((c) => c.pairRequest.sentFields.push('codeDigest'))),
    ).toThrow(/codeDigest/);
  });

  test('名单里有 neverStored 那一项 ⇒ 抛（口令类字段绝不出这一面的门）', () => {
    expect(() =>
      pairstore.sentFields(
        broken((c) => c.pairRequest.sentFields.push(c.pairRequest.neverStored[0])),
      ),
    ).toThrow(/neverStored/);
  });

  test('名单里出现表里根本没有的列 ⇒ 抛（投影当场读成 undefined，那一列永远空着）', () => {
    expect(() =>
      pairstore.sentFields(broken((c) => c.pairRequest.sentFields.push('trailDropped'))),
    ).toThrow(/storedFields/);
  });

  test('名单里有重名项 ⇒ 抛（同一列被写两次，后写的盖掉先写的）', () => {
    expect(() =>
      pairstore.sentFields(
        broken((c) => c.pairRequest.sentFields.push(c.pairRequest.sentFields[0])),
      ),
    ).toThrow(/重名/);
  });
});
