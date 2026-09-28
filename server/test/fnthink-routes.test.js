// 幻念推送 HTTP 入口（#126）的真实请求测试。
//
// 这一批盯的不是"纯函数返回值"（那些在 fnthink-verify / fnthink-events / fnthink-messagestore 里），
// 而是**接上线之后才会出现**的四件事：
//  ① 响应体的形状：失败只回一个 receipt，`reason` 绝不外泄（否则三个入口合起来就是探针）；
//  ② 身份没证明之前的失败**跨原因逐字节同形**（未知设备 / 签名不对 / 状态不可投递）；
//  ③ 表与盘：poll 取走一条之后，消息状态真的推进了、正文真的加密在盘上、ack 之后真的删了；
//  ④ 中间件次序：IP 封锁豁免只豁免这一段，而契约文件缺失时**不许**把 /api/version 一起拖死。
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-routes-'));
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-routes', 10);
// 64 位十六进制：既是 TOTP 的 AES 密钥格式，也满足正文信封的派生输入下限
process.env.ENCRYPTION_KEY = 'a'.repeat(64);
process.env.RATE_LIMIT_GENERAL_MAX = '100000';
process.env.RATE_LIMIT_AUTH_MAX = '100000';
// 反代拓扑：让 getClientIp 认 X-Forwarded-For，这样本文件才能拿一个**固定的假 IP** 去触发封锁
// （store 没有解封接口，拿测试机的真实 IP 封锁会把后续用例一起毁掉）。
process.env.TRUST_PROXY = '1';

const request = require('supertest');
const app = require('../lib/app');
const store = require('../lib/store');
const {
  loadContract,
  assertSupported,
  canonicalOrder,
  statusCode,
} = require('../lib/fnthink/contract');
const verify = require('../lib/fnthink/verify');
const devicestore = require('../lib/fnthink/devicestore');
const messagestore = require('../lib/fnthink/messagestore');

const contract = assertSupported(loadContract());
const SEP = String(contract.signature.separator);
const T0 = Date.now();

const SENDER = '8K3FJ6QPTM9WZ4VHNS'; // 发送方设备
const TARGET = '7YD4RKQPBM8XZ3VHNT'; // 接收方设备（取货的那台）
const OTHER = '8TQVWZ3XKR5B6YD4HM'; // 与本轮无关的第三台

function keypair() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const der = publicKey.export({ type: 'spki', format: 'der' });
  return { rawBase64: der.subarray(der.length - 32).toString('base64'), privateKey };
}

const senderKey = keypair();
const targetKey = keypair();

function register(addressCode, kp, over) {
  const devices = devicestore.loadDevices();
  devicestore.registerDevice(
    contract,
    devices,
    Object.assign({ addressCode, publicKey: kp.rawBase64, name: 'test' }, over || {}),
    T0,
  );
  devicestore.saveDevices(devices);
}

/// 按契约顺序拼出已签字节并签一次（与客户端同一套规则，不在测试里改字段名）。
function sign(kp, fields) {
  const map = {};
  for (const key of canonicalOrder(contract)) map[key] = fields[key];
  const canonical = verify.canonicalBytes(contract, map);
  return {
    map,
    signature: crypto.sign(null, canonical, kp.privateKey).toString('base64'),
    signedText: canonical.toString('utf8'),
  };
}

function messageBody(over) {
  const fields = Object.assign(
    {
      version: '1',
      type: 'notice',
      target: TARGET,
      ts: String(Math.floor(T0 / 1000)),
      nonce: 'msg-' + crypto.randomBytes(6).toString('hex'),
      body: '机箱温度 63℃',
    },
    over || {},
  );
  const signed = sign(senderKey, fields);
  return {
    sender: SENDER,
    signature: signed.signature,
    fields: signed.map,
    title: '温度告警',
    body: '温度告警' + SEP + '机箱温度 63℃', // 让 title 真的出现在已签字节里（对照用）
  };
}

function eventBody(kind, kp, addressCode, over) {
  const spec = contract.clientEvents[kind];
  const fields = Object.assign(
    {
      version: '1',
      type: spec.messageType,
      target: addressCode,
      ts: String(Math.floor(Date.now() / 1000)),
      nonce: 'ev-' + crypto.randomBytes(6).toString('hex'),
      body: kind === 'ack' ? JSON.stringify({ messageId: 'm_x', result: 'displayed' }) : '',
    },
    over || {},
  );
  const signed = sign(kp, fields);
  return { sender: addressCode, signature: signed.signature, fields: signed.map };
}

beforeAll(() => {
  register(SENDER, senderKey, { level: 'L1' });
  register(TARGET, targetKey, { level: 'L1' });
  register(OTHER, keypair(), { level: 'L1' });
});

describe('POST /api/fnthink/message', () => {
  test('合法签名的消息收单：202 + queued + 服务端生成的 messageId', async () => {
    const payload = messageBody();
    const res = await request(app).post('/api/fnthink/message').send(payload).expect(202);
    expect(res.body.receipt).toBe('queued');
    expect(res.body.messageId).toMatch(/^m_/);
    expect(res.body.action).toBe('new');
    const messages = messagestore.loadMessages();
    expect(messages[res.body.messageId]).toBeDefined();
    // 盘上是密文：正文与标题都不该能以明文搜到
    messagestore.saveMessages(messages);
    const raw = fs.readFileSync(messagestore.MESSAGE_FILE, 'utf8');
    expect(raw).not.toContain('机箱温度');
    expect(raw).not.toContain('温度告警');
  });

  test('未配对的地址码与签名不对 ⇒ 响应体逐字节相同（这三个入口不能当枚举器）', async () => {
    const unknown = messageBody();
    unknown.sender = '9ZZZ0123456789ABCDEF';
    const a = await request(app).post('/api/fnthink/message').send(unknown);
    const badSig = messageBody();
    badSig.signature = crypto
      .sign(null, Buffer.from('别的'), keypair().privateKey)
      .toString('base64');
    const b = await request(app).post('/api/fnthink/message').send(badSig);
    const frozen = messageBody();
    // 状态不可投递（revoked）也必须落在同一个形状里
    const devices = devicestore.loadDevices();
    devicestore.setDeviceStatus(contract, devices, SENDER, 'revoked', T0);
    const c = await request(app).post('/api/fnthink/message').send(frozen);
    devicestore.setDeviceStatus(contract, devices, SENDER, 'active', T0);

    expect(a.status).toBe(statusCode(contract, 'forbidden'));
    expect(b.status).toBe(statusCode(contract, 'forbidden'));
    expect(c.status).toBe(statusCode(contract, 'forbidden'));
    expect(JSON.stringify(a.body)).toBe(JSON.stringify(b.body));
    expect(JSON.stringify(a.body)).toBe(JSON.stringify(c.body));
    expect(a.body).toEqual({ receipt: 'rejected_unsigned' });
  });

  test('重复 nonce ⇒ 409（身份已证明，所以才可以说）', async () => {
    const fields = {
      version: '1',
      type: 'notice',
      target: TARGET,
      ts: String(Math.floor(Date.now() / 1000)),
      nonce: 'dup-nonce-1',
      body: 'b',
    };
    const signed = sign(senderKey, fields);
    const body = { sender: SENDER, signature: signed.signature, fields: signed.map };
    await request(app).post('/api/fnthink/message').send(body).expect(202);
    const again = await request(app).post('/api/fnthink/message').send(body);
    expect(again.status).toBe(statusCode(contract, 'duplicate'));
    expect(again.body).toEqual({ receipt: 'duplicate' });
  });

  test('没签在字节里的 title 被丢掉，消息照常收下（不谎报成功也不误判失败）', async () => {
    const base = messageBody();
    const fields = Object.assign({}, base.fields, {
      nonce: 'title-' + crypto.randomBytes(4).toString('hex'),
    });
    const signed = sign(senderKey, fields);
    const res = await request(app)
      .post('/api/fnthink/message')
      .send({ sender: SENDER, signature: signed.signature, fields: signed.map, title: '伪装标题' })
      .expect(202);
    const messages = messagestore.loadMessages();
    const record = messages[res.body.messageId];
    const content = messagestore.decryptBodyFor(contract, process.env.ENCRYPTION_KEY, record.body);
    expect(content.title).toBe('');
    expect(content.body).toBe(fields.body);
  });

  test('多余字段一概不看也不回显（请求里塞 isAdmin 不会出现在响应里）', async () => {
    const base = messageBody();
    const res = await request(app)
      .post('/api/fnthink/message')
      .send(Object.assign({}, base, { isAdmin: true, someOther: 'x' }));
    expect(Object.keys(res.body).sort()).toEqual(
      expect.arrayContaining(['receipt', 'messageId', 'action', 'evicted']),
    );
    expect(res.body.isAdmin).toBeUndefined();
    expect(res.body.someOther).toBeUndefined();
  });
});

describe('POST /api/fnthink/poll', () => {
  test('取货即心跳：lastSeenAt 落盘、正文解密、带 serverTime', async () => {
    const base = messageBody();
    const posted = await request(app).post('/api/fnthink/message').send(base).expect(202);

    const res = await request(app)
      .post('/api/fnthink/poll')
      .send(eventBody('poll', targetKey, TARGET))
      .expect(200);
    const mine = res.body.messages.find((m) => m.messageId === posted.body.messageId);
    expect(mine).toBeDefined();
    expect(mine.body).toBe(base.fields.body);
    expect(res.body.serverTime).toBeGreaterThan(0);
    expect(res.body.pending).toBeGreaterThanOrEqual(0);

    const devices = devicestore.loadDevices();
    expect(devices[TARGET].lastSeenAt).toBeGreaterThan(0);
    // poll 之后消息进了 delivering（还没有 ack）
    const messages = messagestore.loadMessages();
    expect(messages[posted.body.messageId].state).toBe('delivering');
    expect(messages[posted.body.messageId].attempts).toBe(1);
  });

  test('poll 别人的队列 ⇒ 拒绝，且响应里没有任何一条别人的消息', async () => {
    const fields = {
      version: '1',
      type: contract.clientEvents.poll.messageType,
      target: TARGET, // 用 OTHER 的钥匙签，但 target 填 TARGET
      ts: String(Math.floor(Date.now() / 1000)),
      nonce: 'steal-' + crypto.randomBytes(4).toString('hex'),
      body: '',
    };
    const signed = sign(targetKey, fields);
    const res = await request(app)
      .post('/api/fnthink/poll')
      .send({ sender: OTHER, signature: signed.signature, fields: signed.map });
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
    expect(res.body).toEqual({ receipt: 'rejected_unsigned' });
  });

  test('拿消息的签名来 poll ⇒ 事件类型不对（跨接口冒用在 HTTP 层同样被挡）', async () => {
    const base = messageBody();
    const res = await request(app)
      .post('/api/fnthink/poll')
      .send({ sender: SENDER, signature: base.signature, fields: base.fields });
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
    expect(res.body).toEqual({ receipt: 'rejected_capability' });
  });

  test('缺一个签字段 ⇒ 与"未知设备"同形，不透露到底是哪一项没齐', async () => {
    const good = eventBody('poll', targetKey, TARGET);
    const broken = Object.assign({}, good, { fields: Object.assign({}, good.fields) });
    delete broken.fields.nonce;
    broken.sender = '9ZZZ0123456789ABCDEF';
    const res = await request(app).post('/api/fnthink/poll').send(broken);
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
    expect(res.body).toEqual({ receipt: 'rejected_unsigned' });
  });
});

describe('POST /api/fnthink/ack', () => {
  test('ack displayed ⇒ 进 delivered 并立刻释放正文；回执随后只被 poll 取走一次', async () => {
    const posted = await request(app).post('/api/fnthink/message').send(messageBody()).expect(202);
    const messageId = posted.body.messageId;
    await request(app)
      .post('/api/fnthink/poll')
      .send(eventBody('poll', targetKey, TARGET))
      .expect(200);

    const ack = await request(app)
      .post('/api/fnthink/ack')
      .send(
        eventBody('ack', targetKey, TARGET, {
          body: JSON.stringify({ messageId, result: 'displayed' }),
        }),
      )
      .expect(200);
    expect(ack.body.state).toBe('delivered');
    const messages = messagestore.loadMessages();
    expect(messages[messageId].body).toBeUndefined(); // 送达即删正文
    expect(messages[messageId].receipt).toBe('delivered');

    // 回执的收件人是**发送方**（不是刚 ack 的那台设备）：TARGET 取自己的队列取不到它，
    // 要 SENDER 来 poll 才会拿到这条 delivered。
    const withReceipt = await request(app)
      .post('/api/fnthink/poll')
      .send(eventBody('poll', senderKey, SENDER))
      .expect(200);
    expect(JSON.stringify(withReceipt.body.receipts)).toContain(messageId);
    const second = await request(app)
      .post('/api/fnthink/poll')
      .send(eventBody('poll', senderKey, SENDER))
      .expect(200);
    expect(JSON.stringify(second.body.receipts)).not.toContain(messageId);
  });

  test('ack 一条不属于我的消息 ⇒ 拒绝（不能替别人把消息标成已送达）', async () => {
    const posted = await request(app).post('/api/fnthink/message').send(messageBody()).expect(202);
    const ack = eventBody('ack', targetKey, TARGET, {
      body: JSON.stringify({ messageId: 'not-a-real-id', result: 'displayed' }),
    });
    const res = await request(app).post('/api/fnthink/ack').send(ack);
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
    expect(res.body).toEqual({ receipt: 'rejected_capability' });
    void posted;
  });

  test('messageId 用 __proto__ ⇒ 干净拒绝，不通过也不 500', async () => {
    const ack = eventBody('ack', targetKey, TARGET, {
      body: JSON.stringify({ messageId: '__proto__', result: 'displayed' }),
    });
    const res = await request(app).post('/api/fnthink/ack').send(ack);
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
    expect(res.body).toEqual({ receipt: 'rejected_capability' });
  });

  test('device 与 target 不是同一台 ⇒ 拒绝（表里那条是发给别人的）', async () => {
    // 先造一条"发给 OTHER"的消息，再用 TARGET 去 ack 它
    const fields = {
      version: '1',
      type: 'notice',
      target: OTHER,
      ts: String(Math.floor(Date.now() / 1000)),
      nonce: 'other-' + crypto.randomBytes(4).toString('hex'),
      body: '给别人的消息',
    };
    const signed = sign(senderKey, fields);
    const posted = await request(app)
      .post('/api/fnthink/message')
      .send({ sender: SENDER, signature: signed.signature, fields: signed.map })
      .expect(202);

    const ack = eventBody('ack', targetKey, TARGET, {
      body: JSON.stringify({ messageId: posted.body.messageId, result: 'displayed' }),
    });
    const res = await request(app).post('/api/fnthink/ack').send(ack);
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
    expect(messagestore.loadMessages()[posted.body.messageId].state).toBe('queued');
  });

  test('设备报 expired（服务端自己的决定）⇒ 拒绝', async () => {
    const posted = await request(app).post('/api/fnthink/message').send(messageBody()).expect(202);
    await request(app)
      .post('/api/fnthink/poll')
      .send(eventBody('poll', targetKey, TARGET))
      .expect(200);
    const ack = eventBody('ack', targetKey, TARGET, {
      body: JSON.stringify({ messageId: posted.body.messageId, result: 'expired' }),
    });
    const res = await request(app).post('/api/fnthink/ack').send(ack);
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
  });
});

describe('中间件次序与降级', () => {
  const BLOCKED_IP = '203.0.113.77'; // RFC5737 的文档 IP，不会被真设备用到

  test('豁免表：只免 fnthink 这一段，相邻路径不误免', () => {
    expect(store.ipBlockExempt('/api/fnthink/poll')).toBe(true);
    expect(store.ipBlockExempt('/api/fnthink')).toBe(true);
    expect(store.ipBlockExempt('/api/version')).toBe(true);
    expect(store.ipBlockExempt('/health')).toBe(true);
    expect(store.ipBlockExempt('/api/admin/version')).toBe(false);
    // ⚠ 这条是写用例时抓到的：判据原来只写 startsWith(prefix)，于是**前缀相似**的
    //  /api/fnthinkx 也一起被免掉封锁 —— 豁免面悄悄变大，而且没有任何一行代码会报错。
    expect(store.ipBlockExempt('/api/fnthinkx/poll')).toBe(false);
    expect(store.ipBlockExempt('/api/versionx')).toBe(false);
  });

  test('IP 被封锁时：/api/fnthink 仍可通，/api/admin 被挡（豁免只管这一段）', async () => {
    store.blockIp(BLOCKED_IP);
    const admin = await request(app)
      .get('/api/admin/version')
      .set('X-Forwarded-For', BLOCKED_IP)
      .expect(403);
    expect(admin.body.blocked).toBe(true);

    // fnthink 的 poll 会因为签名不过而 403，但那**不是封锁**：封锁回的是 code:-3 + blocked:true
    const poll = await request(app)
      .post('/api/fnthink/poll')
      .set('X-Forwarded-For', BLOCKED_IP)
      .send({});
    expect(poll.status).toBe(statusCode(contract, 'forbidden'));
    expect(poll.body.code).toBeUndefined();
    expect(poll.body).toEqual({ receipt: 'rejected_unsigned' });

    // 而前缀相似的未豁免路径必须仍然被挡（证明收紧后的判据真的走通了中间件，不只是单测里对）
    const similar = await request(app)
      .get('/api/fnthinkx/anything')
      .set('X-Forwarded-For', BLOCKED_IP);
    expect(similar.body.blocked).toBe(true);
  });

  test('契约文件找不到 ⇒ /api/fnthink 明确 503，而 /api/version 照常 200', async () => {
    // 部署侧的规矩是"只上传 server/"，而契约默认在仓库根 protocol/。
    // 那种情况下这条链必须在**自己这一段**失败，不能把更新检查一起拖死。
    const prev = process.env.FNTHINK_CONTRACT;
    process.env.FNTHINK_CONTRACT = path.join(process.env.DATA_DIR, 'definitely-missing-v1.json');
    jest.resetModules();
    try {
      const degraded = require('../lib/app');
      const down = await request(degraded).post('/api/fnthink/poll').send({});
      expect(down.status).toBe(503);
      expect(down.body).toEqual({ error: 'fnthink_protocol_unavailable' });
      const alive = await request(degraded)
        .get('/api/version/check?version=1.0.0&build=1&platform=android')
        .expect(200);
      expect(alive.body.code).toBe(0); // 更新检查这条链完全没被连累（它才是全 App 的命脉）
    } finally {
      if (prev === undefined) delete process.env.FNTHINK_CONTRACT;
      else process.env.FNTHINK_CONTRACT = prev;
      jest.resetModules();
    }
  });
});

describe('源码守卫', () => {
  test('routes.js 不写死 4xx 状态码，也不把 reason 放进响应', () => {
    const src = fs.readFileSync(path.join(__dirname, '../lib/fnthink/routes.js'), 'utf8');
    const code = src
      .split('\n')
      .filter((l) => !l.trim().startsWith('//'))
      .join('\n');
    expect(code).not.toMatch(/status\(\s*4\d\d/);
    expect(code).not.toMatch(/\.json\(\{\s*reason/);
    // 状态码只能来自契约表
    expect(code).toContain('statusCode(contract,');
  });

  test('降级 catch 只咽契约类错误，代码 bug 必须继续抛', () => {
    const appSrc = fs.readFileSync(path.join(__dirname, '../lib/app.js'), 'utf8');
    // 这一条是被实测逼出来的：app.js 漏了 `require('./store')` 时抛 ReferenceError，
    // 当时的 catch 把它吞成 503 + 一句"请把契约文件放到 protocol/"，
    // 于是**代码 bug 伪装成部署问题**，测试里只看到一串莫名 503。
    expect(appSrc).toContain('isContractAvailabilityError(e)');
    expect(appSrc).toContain('throw e;');
    const {
      isContractAvailabilityError,
      CONTRACT_MISSING,
      CONTRACT_UNSUPPORTED,
    } = require('../lib/fnthink/contract');
    expect(
      isContractAvailabilityError(Object.assign(new Error('x'), { code: CONTRACT_MISSING })),
    ).toBe(true);
    expect(
      isContractAvailabilityError(Object.assign(new Error('x'), { code: CONTRACT_UNSUPPORTED })),
    ).toBe(true);
    expect(isContractAvailabilityError(new ReferenceError('store is not defined'))).toBe(false);
    expect(isContractAvailabilityError(new SyntaxError('bad js'))).toBe(false);
  });

  test('IP 封锁豁免只有一处白名单（中间件不许再抄一份前缀）', () => {
    const middleware = fs.readFileSync(path.join(__dirname, '../lib/middleware.js'), 'utf8');
    const storeSrc = fs.readFileSync(path.join(__dirname, '../lib/store.js'), 'utf8');
    expect(middleware).toContain('store.ipBlockExempt(');
    // 判据只许写在 store.IP_BLOCK_EXEMPT_PREFIXES 里；中间件里再出现任何一条路径前缀
    // 就是第二份白名单 —— 两处各写一份的结局是"加了路由忘了加豁免"，而那看起来像推送坏了。
    expect(middleware).not.toMatch(/'\/api\/version'/);
    expect(middleware).not.toMatch(/'\/health'/);
    expect(storeSrc).toContain('IP_BLOCK_EXEMPT_PREFIXES');
  });
});
