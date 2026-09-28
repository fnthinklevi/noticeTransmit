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
const { windowsFor, endpointKindOf } = require('../lib/fnthink/ratelimit');
const devicestore = require('../lib/fnthink/devicestore');
const messagestore = require('../lib/fnthink/messagestore');

const contract = assertSupported(loadContract());
const SEP = String(contract.signature.separator);
const T0 = Date.now();
// #130-A2：配额窗口也从契约推导，测试里不另写数字（同一条「数字只有一个出处」的规矩）
const windows = windowsFor(contract);

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
  register(SENDER, senderKey);
  register(TARGET, targetKey);
  register(OTHER, keypair());
  // ⚠ #131 第三片起，登记**不再等于可以互投**：收单判的是被投那台的 grantsBy。
  // 这几条用例讲的是收单/取货/回执，所以先把关系摆好（关系本身那条闸另有一组用例）。
  const devices = devicestore.loadDevices();
  devicestore.approvePeer(contract, devices, TARGET, SENDER, 'L1', T0);
  devicestore.approvePeer(contract, devices, SENDER, TARGET, 'L1', T0);
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

  test('poll 回的每条消息，键恰好是契约 messageFields 那份名单，且 sender 真有值', async () => {
    const base = messageBody();
    const posted = await request(app).post('/api/fnthink/message').send(base).expect(202);

    const res = await request(app)
      .post('/api/fnthink/poll')
      .send(eventBody('poll', targetKey, TARGET))
      .expect(200);
    const mine = res.body.messages.find((m) => m.messageId === posted.body.messageId);
    // 逐字节比名单，不是"包含"：多回一列（存盘元数据）与少回一列（收件表没数据可灌）
    // 在这里都是同一种红 —— 而 T47 那张表读的就是这一份形状。
    expect(Object.keys(mine).sort()).toEqual([...contract.clientEvents.poll.messageFields].sort());
    expect(mine.sender).toBe(SENDER);
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
    // 这条测的是 ack 的归属，不是配对闸 ⇒ 把关系摆好（OTHER 允许 SENDER 投它）。
    const devices = devicestore.loadDevices();
    devicestore.approvePeer(contract, devices, OTHER, SENDER, 'L1', Date.now());
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

  describe('按发送方计的配额（#130-A2）', () => {
    // 本 describe 用一台**专属设备**：配额计数是按地址累计的，借用别的用例用过的地址，
    // 结果就取决于用例执行顺序 —— 那种"有时候红"的守卫比没有守卫更糟。
    const FRESH = '9ZQ4RKQPBM8XZ3VHNF';
    const freshKey = keypair();
    // 隔离性用**另一台专属设备**验：TARGET 在本文件前面的用例里已经 poll 过若干次，
    // 借它的计数就等于让这条断言依赖用例顺序。
    const FRESH2 = '9BM8XZ3VHNF4RKQPZQ';
    const fresh2Key = keypair();

    test('同一台设备超了轮询额度 ⇒ 429（契约给的码 + 空 body），另一台不受牵连', async () => {
      register(FRESH, freshKey);
      const per = windows.pollPerMinute; // 从 presence 推导出来的那个数（不是这里另写的）
      for (let i = 0; i < per; i++) {
        const ok = await request(app)
          .post('/api/fnthink/poll')
          .send(eventBody('poll', freshKey, FRESH));
        expect(ok.status).toBe(200);
      }
      const over = await request(app)
        .post('/api/fnthink/poll')
        .send(eventBody('poll', freshKey, FRESH));
      expect(over.status).toBe(statusCode(contract, 'rateLimited'));
      expect(over.body).toEqual({});
      expect(Number(over.headers['retry-after'])).toBeGreaterThan(0);

      // ⚠ 要害在这一条：**同一时刻、同一个源 IP** 的另一台设备照常取货。
      // 按 IP 计的实现会在这里一起 429 —— 那正是 A1 收成 6/分时 7 条用例红的形状。
      register(FRESH2, fresh2Key);
      const other = await request(app)
        .post('/api/fnthink/poll')
        .send(eventBody('poll', fresh2Key, FRESH2));
      expect(other.status).toBe(200);
    });
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

// ── #131 第二片 2B：把公网面开到"还没有配对关系"的那一侧 ──
// 这三条入口与上面三条的差别只有一点：签名者**可能还不在设备表里**（register），
// 或者这一步的结果不该变成任何授权（pair）。所以这里的用例几乎全围着"同形"与"什么都没给出去"写。
describe('POST /api/fnthink/register、/pair-arm、/pair', () => {
  const CODE = 'ABCDEFGHJKMNPQRSTVWX'; // 20 位 Crockford（不含 I L O U），合法形状
  const CODE2 = 'BDEFGHJKMNPQRSTVWX23'; // 第二枚（20 位）：另一条用例自己挂、自己消耗
  const NEW = '2CF4GHJKMNPQRSTVWX'; // 18 位，本轮没登记过的新设备
  const newKey = keypair();
  const requesterKey = keypair();
  const requesterCode = '7J8KMPQRSTVWX99966'; // ⚠ 不能含 I L O U —— 上一版这里写了 "KL M"，
  // 结果 /register 直接判非法地址码，后面三条用例全都红在"身份没证明"那一步（403 而不是 401）。

  function registerBody(addressCode, kp, over) {
    const fields = Object.assign(
      {
        version: '1',
        type: contract.clientEvents.register.messageType,
        target: addressCode,
        ts: String(Math.floor(Date.now() / 1000)),
        nonce: 'rg-' + crypto.randomBytes(6).toString('hex'),
        body: '',
      },
      over || {},
    );
    const signed = sign(kp, fields);
    return {
      sender: addressCode,
      publicKey: kp.rawBase64,
      name: '测试机',
      signature: signed.signature,
      fields: signed.map,
    };
  }

  function armBody(kp, addressCode, code) {
    const fields = {
      version: '1',
      type: contract.clientEvents.pairArm.messageType,
      target: addressCode,
      ts: String(Math.floor(Date.now() / 1000)),
      nonce: 'pa-' + crypto.randomBytes(6).toString('hex'),
      body: JSON.stringify({ pairingCode: code }),
    };
    const signed = sign(kp, fields);
    return { sender: addressCode, signature: signed.signature, fields: signed.map };
  }

  function pairBody(kp, requester, target, code, level) {
    const fields = {
      version: '1',
      type: contract.clientEvents.pair.messageType,
      target,
      ts: String(Math.floor(Date.now() / 1000)),
      nonce: 'pc-' + crypto.randomBytes(6).toString('hex'),
      body: JSON.stringify({ pairingCode: code, level }),
    };
    const signed = sign(kp, fields);
    return { sender: requester, signature: signed.signature, fields: signed.map };
  }

  test('/register 新设备：200，但登记不给任何授权（没有 level 可回，关系表是空的）', async () => {
    const res = await request(app)
      .post('/api/fnthink/register')
      .send(registerBody(NEW, newKey))
      .expect(200);
    expect(res.body.addressCode).toBe(NEW);
    // 旧版这里回 `level`（取自发送方自己那行），那就是"登记即许可"的接口面孔。
    expect(res.body.level).toBeUndefined();
    expect(res.body.peersGrantingMe).toBe(0);
    // 不回显公钥、不回显任何摘要：设备要确认的只是"这行记上了"。
    expect(JSON.stringify(res.body)).not.toContain(newKey.rawBase64);
    const rec = devicestore.loadDevices()[NEW];
    expect(rec).toBeDefined();
    expect(rec.grant).toBeUndefined();
    expect(rec.grantsBy).toEqual({});
  });

  test('/register 的三种身份前失败逐字节同形，且正文里不出现地址码', async () => {
    const wrongKeyShape = registerBody('3D4GHJKMNPQRSTVWX9', keypair());
    wrongKeyShape.publicKey = '不是合法的-base64';
    const a = await request(app).post('/api/fnthink/register').send(wrongKeyShape);

    const badSignature = registerBody('4E5GHJKMNPQRSTVWX9', keypair());
    badSignature.signature = crypto
      .sign(null, Buffer.from('别的'), keypair().privateKey)
      .toString('base64');
    const b = await request(app).post('/api/fnthink/register').send(badSignature);

    // 已经绑过另一把钥匙的地址码：registerDevice 抛的那条错误**带着地址码文本**，
    // 冒到 errorMiddleware 就成了"这个码存在且绑过别人"—— 必须塌回同一句话。
    const swap = registerBody(SENDER, keypair());
    const c = await request(app).post('/api/fnthink/register').send(swap);

    for (const r of [a, b, c]) {
      expect(r.status).toBe(statusCode(contract, 'forbidden'));
      expect(r.body).toEqual({ receipt: 'rejected_unsigned' });
      expect(JSON.stringify(r.body)).not.toContain(SENDER);
    }
  });

  test('/register 顶层带 privateKey：连"是谁"都不必回答，同形丢弃', async () => {
    const body = registerBody('5F6GHJKMNPQRSTVWX9', keypair());
    body.privateKey = crypto.randomBytes(32).toString('base64');
    const res = await request(app).post('/api/fnthink/register').send(body);
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
    expect(res.body).toEqual({ receipt: 'rejected_unsigned' });
  });

  test('/pair-arm：200 只回过期时间，盘上只有摘要（明文口令一个字节都不落）', async () => {
    const res = await request(app)
      .post('/api/fnthink/pair-arm')
      .send(armBody(targetKey, TARGET, CODE))
      .expect(200);
    expect(res.body.armed).toBe(true);
    expect(res.body.ttlSeconds).toBe(contract.identity.pairingCode.ttlSeconds);
    expect(JSON.stringify(res.body)).not.toContain(CODE);
    const raw = fs.readFileSync(devicestore.DEVICE_FILE, 'utf8');
    expect(raw).not.toContain(CODE);
    expect(raw).toContain('digest');
  });

  test('/pair-arm 未登记的地址码 ⇒ 与签名不对同形（这条入口不许是枚举器）', async () => {
    const unknown = await request(app)
      .post('/api/fnthink/pair-arm')
      .send(armBody(keypair(), '6G7HJKMNPQRSTVWX99', CODE));
    const badSig = armBody(targetKey, TARGET, CODE);
    badSig.signature = crypto
      .sign(null, Buffer.from('别的'), keypair().privateKey)
      .toString('base64');
    const wrong = await request(app).post('/api/fnthink/pair-arm').send(badSig);
    expect(unknown.status).toBe(statusCode(contract, 'forbidden'));
    expect(JSON.stringify(unknown.body)).toBe(JSON.stringify(wrong.body));
  });

  test('/pair 走完：202 只留一条待确认请求，TARGET 的授权一点没变', async () => {
    // 请求方也要先登记（这一步的钥匙从设备表取）。
    await request(app)
      .post('/api/fnthink/register')
      .send(registerBody(requesterCode, requesterKey))
      .expect(200);
    await request(app)
      .post('/api/fnthink/pair-arm')
      .send(armBody(targetKey, TARGET, CODE));

    const before = devicestore.loadDevices()[TARGET].grant;
    const res = await request(app)
      .post('/api/fnthink/pair')
      .send(pairBody(requesterKey, requesterCode, TARGET, CODE, 'L1'))
      .expect(statusCode(contract, 'queued'));
    expect(res.body.requestId).toMatch(/^pr_/);
    expect(res.body.status).toBe(contract.pairRequest.initialStatus);
    expect(JSON.stringify(res.body)).not.toContain(CODE);

    // 服务端从不批准：授权与配对前逐字相同（autoApprove=false 的执行处）。
    const after = devicestore.loadDevices()[TARGET].grant;
    expect(JSON.stringify(after)).toBe(JSON.stringify(before));

    // A 下一次 poll 能看见它（键名来自契约 pairRequest.pollKey）。
    const poll = await request(app)
      .post('/api/fnthink/poll')
      .send(eventBody('poll', targetKey, TARGET))
      .expect(200);
    expect(poll.body.pairRequests).toHaveLength(1);
    expect(poll.body.pairRequests[0].requester).toBe(requesterCode);
    expect(poll.body.pairRequests[0].requesterPublicKey).toBe(requesterKey.rawBase64);
    // 旧的四个键一个都不能少（新增响应键不许挤掉既有的那条契约承诺）。
    expect(Object.keys(poll.body).sort()).toEqual(
      ['messages', 'pairRequests', 'pending', 'receipts', 'serverTime'].sort(),
    );
  });

  test('/pair 消耗即失效：口令只能用一次，且"没挂过"与"已消耗"逐字节同形', async () => {
    const asker = keypair();
    const askerCode = '8KMNPQRSTVWX999777';
    await request(app)
      .post('/api/fnthink/register')
      .send(registerBody(askerCode, asker))
      .expect(200);

    // ① 一台从未挂过口令的设备（OTHER 在 beforeAll 里登记过，但没 arm）：
    //    上一版这里误用了 TARGET —— 它在前一条用例里已经挂上口令，于是这条测的是"配对成功"。
    const neverArmed = await request(app)
      .post('/api/fnthink/pair')
      .send(pairBody(asker, askerCode, OTHER, CODE, 'L1'));
    expect(neverArmed.status).toBe(statusCode(contract, 'unauthorized'));

    // ② 挂一枚新的、成功配掉它，再用同一枚配第二次 ⇒ 必须与①同一个形状。
    await request(app)
      .post('/api/fnthink/pair-arm')
      .send(armBody(targetKey, TARGET, CODE2))
      .expect(200);
    const first = await request(app)
      .post('/api/fnthink/pair')
      .send(pairBody(asker, askerCode, TARGET, CODE2, 'L1'));
    expect(first.status).toBe(statusCode(contract, 'queued'));
    const second = await request(app)
      .post('/api/fnthink/pair')
      .send(pairBody(asker, askerCode, TARGET, CODE2, 'L1'));

    expect(second.status).toBe(statusCode(contract, 'unauthorized'));
    expect(JSON.stringify(second.body)).toBe(JSON.stringify(neverArmed.body));
    expect(neverArmed.body).toEqual({ receipt: 'rejected_capability' });
  });

  test('/pair 想直接要 L3 ⇒ 拒（免本地确认的上限从契约引用，不是这里写死的）', async () => {
    await request(app)
      .post('/api/fnthink/pair-arm')
      .send(armBody(targetKey, TARGET, CODE2));
    const res = await request(app)
      .post('/api/fnthink/pair')
      .send(pairBody(requesterKey, requesterCode, TARGET, CODE2, 'L3'));
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
    expect(res.body).toEqual({ receipt: 'rejected_capability' });
  });
});

// ── #131 第三片：配对关系真的能拦住收单，而 pairConfirm 是唯一一次授权写入 ──
// 前两片的"链"其实没有授权出口，收单读的是发送方自己那一行 ⇒ 登记即许可。这一组钉的是"关系才是许可"。
describe('POST /api/fnthink/pair-confirm 与"没配对就投不进去"', () => {
  const CODE = 'DEFGHJKMNPQRSTVWX234';
  const ALICE = 'ADFGHJKMNPQRSTVWX9'; // A：被投的那台，做决定的人
  const BOB = 'BEFGHJKMNPQRSTVWX2'; // B：想投给 A 的那台
  const MALLORY = 'CEFGHJKMNPQRSTVWX3'; // 第三台：想替 A 答应这次配对
  const aliceKey = keypair();
  const bobKey = keypair();
  const malloryKey = keypair();

  function regBody(addressCode, kp) {
    const fields = {
      version: '1',
      type: contract.clientEvents.register.messageType,
      target: addressCode,
      ts: String(Math.floor(Date.now() / 1000)),
      nonce: 'rc-' + crypto.randomBytes(6).toString('hex'),
      body: '',
    };
    const signed = sign(kp, fields);
    return {
      sender: addressCode,
      publicKey: kp.rawBase64,
      name: '第三片用例',
      signature: signed.signature,
      fields: signed.map,
    };
  }

  function evBody(kind, kp, sender, target, payloadObj) {
    const spec = contract.clientEvents[kind];
    const fields = {
      version: '1',
      type: spec.messageType,
      target,
      ts: String(Math.floor(Date.now() / 1000)),
      nonce: 'e3-' + crypto.randomBytes(6).toString('hex'),
      body: payloadObj === undefined ? '' : JSON.stringify(payloadObj),
    };
    const signed = sign(kp, fields);
    return { sender, signature: signed.signature, fields: signed.map };
  }

  function msgBody(fromKp, from, to, text) {
    const fields = {
      version: '1',
      type: 'notice',
      target: to,
      ts: String(Math.floor(Date.now() / 1000)),
      nonce: 'm3-' + crypto.randomBytes(6).toString('hex'),
      body: text,
    };
    const signed = sign(fromKp, fields);
    return { sender: from, signature: signed.signature, fields: signed.map };
  }

  /// 挂口令 + 配对，返回 requestId（每条用例自己走一遍，别共用一条已消耗的关系）。
  async function pairUp(armCode, askerKp, askerCode, level) {
    await request(app)
      .post('/api/fnthink/pair-arm')
      .send(evBody('pairArm', aliceKey, ALICE, ALICE, { pairingCode: armCode }))
      .expect(200);
    const res = await request(app)
      .post('/api/fnthink/pair')
      .send(evBody('pair', askerKp, askerCode, ALICE, { pairingCode: armCode, level }))
      .expect(statusCode(contract, 'queued'));
    expect(res.body.requestId).toMatch(/^pr_/);
    return res.body.requestId;
  }

  beforeAll(async () => {
    for (const [c, kp] of [
      [ALICE, aliceKey],
      [BOB, bobKey],
      [MALLORY, malloryKey],
    ]) {
      await request(app).post('/api/fnthink/register').send(regBody(c, kp)).expect(200);
    }
  });

  test('没配对 ⇒ 收单 403，而且消息表里不会多出一条（不静默丢，也不无谓留）', async () => {
    const before = Object.keys(messagestore.loadMessages()).length;
    const res = await request(app)
      .post('/api/fnthink/message')
      .send(msgBody(bobKey, BOB, ALICE, '验证码 481902'));
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
    expect(res.body).toEqual({ receipt: 'rejected_capability' });
    // 旧版这里是 202 + 一条永远没人能取走的记录（target 不在任何关系里），
    // 七天之后 ttl_elapsed —— 那是"无谓留"，不是"收下待投"。
    expect(Object.keys(messagestore.loadMessages()).length).toBe(before);
  });

  test('A 确认 ⇒ 同一条消息立刻能投进去，且关系写在 A 那一行上', async () => {
    const requestId = await pairUp(CODE, bobKey, BOB, 'L1');

    // 别人拿同一个 requestId 替 A 答应 ⇒ 拒（requestId 猜不到不是判据，归属才是）。
    const impostor = await request(app)
      .post('/api/fnthink/pair-confirm')
      .send(
        evBody('pairConfirm', malloryKey, MALLORY, ALICE, {
          requestId,
          decision: 'approved',
          level: 'L1',
        }),
      );
    expect(impostor.status).toBe(statusCode(contract, 'forbidden'));
    expect(impostor.body).toEqual({ receipt: 'rejected_capability' });

    const ok = await request(app)
      .post('/api/fnthink/pair-confirm')
      .send(
        evBody('pairConfirm', aliceKey, ALICE, BOB, {
          requestId,
          decision: 'approved',
          level: 'L1',
        }),
      )
      .expect(200);
    // 状态名取自契约（路由与测试都不写 'approved' 字面量）。
    expect(ok.body.status).toBe(contract.clientEvents.pairConfirm.approveDecision);
    expect(ok.body.grantedLevel).toBe('L1');

    const devices = devicestore.loadDevices();
    expect(devices[ALICE].grantsBy[BOB].maxLevel).toBe('L1');
    // 反向没有：B 没授权自己，A 也没给 B"投给 A 之外的人"的许可。
    expect(devices[BOB].grantsBy[ALICE]).toBeUndefined();

    await request(app)
      .post('/api/fnthink/message')
      .send(msgBody(bobKey, BOB, ALICE, '验证码 481902'))
      .expect(202);
  });

  test('同一条请求只能被处理一次，第二次不改写授权（revision 仍为 1）', async () => {
    const CODE2 = 'EFGHJKMNPQRSTVWX2345';
    const requestId = await pairUp(CODE2, bobKey, BOB, 'L1');
    const first = await request(app)
      .post('/api/fnthink/pair-confirm')
      .send(
        evBody('pairConfirm', aliceKey, ALICE, BOB, {
          requestId,
          decision: 'approved',
          level: 'L1',
        }),
      )
      .expect(200);
    expect(first.body.grantedLevel).toBe('L1');
    const before = JSON.stringify(devicestore.loadDevices()[ALICE].grantsBy[BOB]);

    const second = await request(app)
      .post('/api/fnthink/pair-confirm')
      .send(
        evBody('pairConfirm', aliceKey, ALICE, BOB, {
          requestId,
          decision: 'approved',
          level: 'L2',
        }),
      );
    expect(second.status).toBe(statusCode(contract, 'forbidden'));
    // ⚠ 这条断的是"一次点头不能反复用"：第二次若还生效，A 早已划掉的发送方会被请回来。
    expect(JSON.stringify(devicestore.loadDevices()[ALICE].grantsBy[BOB])).toBe(before);
  });

  test('A 说不 ⇒ 请求关掉、关系不写，B 仍然投不进去', async () => {
    const CODE3 = 'FGHJKMNPQRSTVWX23456';
    const requestId = await pairUp(CODE3, malloryKey, MALLORY, 'L1');
    const res = await request(app)
      .post('/api/fnthink/pair-confirm')
      .send(
        evBody('pairConfirm', aliceKey, ALICE, MALLORY, {
          requestId,
          decision: 'denied',
          level: 'L1',
        }),
      )
      .expect(200);
    expect(res.body.status).toBe('denied');
    expect(res.body.grantedLevel).toBeNull();
    expect(devicestore.loadDevices()[ALICE].grantsBy[MALLORY]).toBeUndefined();
    const blocked = await request(app)
      .post('/api/fnthink/message')
      .send(msgBody(malloryKey, MALLORY, ALICE, '借过一次'));
    expect(blocked.status).toBe(statusCode(contract, 'forbidden'));
  });

  test('确认时想直接给 L3 ⇒ 拒，且不留下任何授权变化', async () => {
    const CODE4 = 'GHJKMNPQRSTVWX234567';
    const requestId = await pairUp(CODE4, bobKey, BOB, 'L1');
    const before = JSON.stringify(devicestore.loadDevices()[ALICE].grantsBy);
    const res = await request(app)
      .post('/api/fnthink/pair-confirm')
      .send(
        evBody('pairConfirm', aliceKey, ALICE, BOB, {
          requestId,
          decision: 'approved',
          level: 'L3',
        }),
      );
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
    expect(JSON.stringify(devicestore.loadDevices()[ALICE].grantsBy)).toBe(before);
  });

  test('授权写入只有 approvePeer 一条咽喉：路由与 pairstore 都不自己碰 grantsBy', () => {
    const routesSrc = fs.readFileSync(path.join(__dirname, '../lib/fnthink/routes.js'), 'utf8');
    const pairSrc = fs.readFileSync(path.join(__dirname, '../lib/fnthink/pairstore.js'), 'utf8');
    const code = (s) => s.replace(/\/\/[^\n]*/g, '');
    expect(code(routesSrc)).not.toMatch(/grantsBy\s*=/);
    expect(code(pairSrc)).not.toMatch(/grantsBy\s*\[/);
    expect(code(pairSrc)).toMatch(/approvePeer\(/);
  });
});

// #126 第二片把"客户端发到哪个 URL"收进契约 `transport.apiPaths`，这一组就是把那张表钉回事实。
// 它必须双向：只查"声明的都挂了"会漏掉挂了两条声明一条；只查"挂了的都声明了"则漏掉
// 声明了却没挂的那条（客户端照着 404 敲一年）。
describe('契约声明的路径 == 实际挂载的路径', () => {
  const mountedPaths = () => [
    ...new Set((app.get('fnthinkEndpoints') || []).map((line) => line.replace(/^[A-Z,]+ /, ''))),
  ];
  const declaredPaths = () => [
    ...Object.entries(contract.transport.apiPaths)
      .filter(([kind]) => !kind.startsWith('_'))
      .map(([, path]) => path),
    contract.endpoint.ingress.pathPattern,
    contract.endpoint.ingress.postBearerPath,
  ];

  test('不多不少：挂载清单与契约声明逐条对得上（改任一边都必须同时改另一边）', () => {
    expect(mountedPaths().sort()).toEqual(declaredPaths().sort());
  });

  test('每条设备面路径都能被限流那一层认回它的事件种类（尾段 ↔ 驼峰名的映射不许断）', () => {
    // 认不回来的后果不是报错，是"这个端点被当成未登记 ⇒ 按最紧的一档拦下"，
    // 而那正好是 A1 加这条兜底的初衷 —— 前提是 kind 得算对。
    for (const [kind, path] of Object.entries(contract.transport.apiPaths)) {
      if (kind.startsWith('_') || kind === 'message') continue; // /message 不是 clientEvents 事件
      expect(endpointKindOf(path)).toBe(kind);
    }
  });

  test('路由文件里不出现带前缀的全路径字面量（前缀只由 app.js 挂一次）', () => {
    const src = fs.readFileSync(path.join(__dirname, '../lib/fnthink/routes.js'), 'utf8');
    // 挂了前缀的路由等于绕开 app.js 那一次挂载 —— 契约 apiPaths 里的全路径就再没人核对了。
    expect(src).not.toMatch(/router\.(get|post)\(\s*['"]\/api\/fnthink/);
    // 端点收单那两条的形状在契约里声明，代码只挂参数化的相对路径
    expect(src).toMatch(/'\/p\/:endpointId\/:secret'/);
  });
});
