// 设备这一路的标题信封 —— **服务端那一半**的跨端向量断言（§4 第 10 条定稿）。
//
// 与 Dart 侧（`packages/fnthink_push/test/title_envelope_test.dart`）吃同一份
// `protocol/fnthink-vectors-v1.json` 的 `titleEnvelope` 段，但断的是**另一件事**：
//   Dart 断「编码怎么拼、收件端怎么拆」；
//   本文件断「服务端**不参与**这件事」—— 整段 wireBody 当不透明正文存、原样回，
//   而标题列永远是空的（`canonicalOrder` 里没有 title，未签的顶层 title 一定被丢）。
//
// ⚠ 为什么值得两端各吃一份同一的表：这条链上「谁拆信封」是一个会漂的边界。
// 哪天有人"顺手"在服务端把标题解出来填进 title 列，设备侧一行代码都不用改，
// 而同一条消息在两台手机上会显示成两样 —— 本文件的那一列空串就是它的红。
//
// 真实 HTTP（supertest）而不是纯函数：标题的丢弃发生在路由里（整段比对那一句），
// 打纯函数等于测另一个地方。

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-envelope-'));
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-envelope', 10);
process.env.ENCRYPTION_KEY = 'a'.repeat(64);
process.env.RATE_LIMIT_GENERAL_MAX = '100000';
process.env.RATE_LIMIT_AUTH_MAX = '100000';
process.env.RATE_LIMIT_FNTHINK_MAX = '100000';
process.env.TRUST_PROXY = '1';

const request = require('supertest');
const app = require('../lib/app');
const devicestore = require('../lib/fnthink/devicestore');
const verify = require('../lib/fnthink/verify');
const {
  loadContract,
  assertSupported,
  canonicalOrder,
  statusCode,
} = require('../lib/fnthink/contract');

const contract = assertSupported(loadContract());
const T0 = Date.now();

const SENDER = '8K3FJ6QPTM9WZ4VHNS';
const TARGET = '7YD4RKQPBM8XZ3VHNT';

function keypair() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const der = publicKey.export({ type: 'spki', format: 'der' });
  return { rawBase64: der.subarray(der.length - 32).toString('base64'), privateKey };
}

const senderKey = keypair();
const targetKey = keypair();

function register(addressCode, kp) {
  const devices = devicestore.loadDevices();
  devicestore.registerDevice(
    contract,
    devices,
    { addressCode, publicKey: kp.rawBase64, name: 'test' },
    T0,
  );
  devicestore.saveDevices(devices);
}

function approveBothWays() {
  const devices = devicestore.loadDevices();
  devicestore.approvePeer(contract, devices, TARGET, SENDER, 'L1', [], T0);
  devicestore.approvePeer(contract, devices, SENDER, TARGET, 'L1', [], T0);
  devicestore.saveDevices(devices);
}

/// 按契约顺序拼已签字节并签一次（与客户端同一套规则；测试里不改字段名）。
function sign(kp, fields) {
  const map = {};
  for (const key of canonicalOrder(contract)) map[key] = fields[key];
  const canonical = verify.canonicalBytes(contract, map);
  return { map, signature: crypto.sign(null, canonical, kp.privateKey).toString('base64') };
}

function messageEnvelope(wireBody, over) {
  const fields = Object.assign(
    {
      version: '1',
      type: 'notice',
      target: TARGET,
      ts: String(Math.floor(Date.now() / 1000)),
      nonce: 'env-' + crypto.randomBytes(6).toString('hex'),
      body: wireBody,
    },
    over || {},
  );
  const signed = sign(senderKey, fields);
  return { sender: SENDER, signature: signed.signature, fields: signed.map };
}

function pollEnvelope() {
  const fields = {
    version: '1',
    type: contract.clientEvents.poll.messageType,
    target: TARGET,
    ts: String(Math.floor(Date.now() / 1000)),
    nonce: 'poll-' + crypto.randomBytes(6).toString('hex'),
    body: '',
  };
  const signed = sign(targetKey, fields);
  return { sender: TARGET, signature: signed.signature, fields: signed.map };
}

const vectors = JSON.parse(
  fs.readFileSync(
    path.resolve(__dirname, '..', '..', 'protocol', 'fnthink-vectors-v1.json'),
    'utf8',
  ),
);
const rows = vectors.titleEnvelope.rows;

describe('标题信封：服务端把整段 body 当不透明正文（跨端向量的 Node 那一半）', () => {
  beforeAll(() => {
    register(SENDER, senderKey);
    register(TARGET, targetKey);
    approveBothWays();
  });

  test('向量表非空，且每行的 serverTitle 都是空串（这一列一旦有了值就是本文件要拦的那件事）', () => {
    expect(rows.length).toBeGreaterThan(0);
    for (const row of rows) {
      expect(row.expect.serverTitle).toBe('');
    }
  });

  test('逐条：发出去什么串，poll 回来还是什么串，而 title 一直是空的', async () => {
    const wrong = [];
    for (const row of rows) {
      const body = messageEnvelope(row.expect.wireBody);
      if (row.given.claimedTopLevelTitle) body.title = row.given.claimedTopLevelTitle;
      const sent = await request(app)
        .post('/api/fnthink/message')
        .set('x-forwarded-proto', 'https')
        .send(body);
      if (sent.status !== statusCode(contract, 'queued')) {
        wrong.push(`${row.id}: 收单回 ${sent.status}（期望 202）`);
        continue;
      }
      const got = await request(app)
        .post('/api/fnthink/poll')
        .set('x-forwarded-proto', 'https')
        .send(pollEnvelope());
      const messages = got.body.messages || [];
      if (messages.length !== 1) {
        wrong.push(`${row.id}: poll 回了 ${messages.length} 条（期望正好 1 条）`);
        continue;
      }
      const m = messages[0];
      // 标题列：全表都必须是空串。`claimedTopLevelTitle` 那一行就是这个协议的判据本身 ——
      // 标题字符串确实"出现在已签字节里"，但是**作为 body 的一部分**，而服务端是整段比对。
      if (m.title !== row.expect.serverTitle) {
        wrong.push(`${row.id}: 服务端给出了标题「${m.title}」，而它不该拆信封`);
      }
      if (m.body !== row.expect.serverBody) {
        wrong.push(`${row.id}: body 被改写了（出去 ${row.expect.serverBody} 回来 ${m.body}）`);
      }
    }
    expect(wrong).toEqual([]);
  });

  test('服务端源码里不出现这个前缀：拆信封的人只有一个（收件端）', () => {
    // 负向断言 ⇒ **剥注释**再比：契约文件与本文件的说明里都有这个词，注释不算实现。
    const prefix = contract.deviceSend.titleEnvelope.prefix;
    const dir = path.join(__dirname, '..', 'lib');
    const files = [];
    const walk = (d) => {
      for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, entry.name);
        if (entry.isDirectory()) walk(p);
        else if (entry.name.endsWith('.js')) files.push(p);
      }
    };
    walk(dir);
    const hits = files
      .map((p) => {
        const code = fs
          .readFileSync(p, 'utf8')
          .split('\n')
          .filter((line) => !line.trimStart().startsWith('//'))
          .join('\n');
        return code.includes(prefix) ? path.relative(dir, p) : null;
      })
      .filter(Boolean);
    expect(hits).toEqual([]);
    expect(files.length).toBeGreaterThan(10);
  });

  test('契约这一节在服务端侧读得通：前缀不含分隔符、两个键名不撞、拆的人写的是收件端', () => {
    const envelope = contract.deviceSend.titleEnvelope;
    expect(typeof envelope.prefix).toBe('string');
    expect(envelope.prefix.length).toBeGreaterThan(0);
    // 分隔符出现在被签字段的值里 ⇒ canonicalBytes 直接抛（防伪边界）。
    // 这一条今天红不了任何用例 —— 它红的是"哪天有人把分隔符换成可见字符"那一刻。
    expect(envelope.prefix.indexOf(String(contract.signature.separator))).toBe(-1);
    const probe = verify.canonicalBytes(contract, {
      version: '1',
      type: 'notice',
      target: TARGET,
      ts: String(Math.floor(T0 / 1000)),
      nonce: 'probe-1',
      body: envelope.prefix + '{"t":"x","b":"y"}',
    });
    expect(probe.length).toBeGreaterThan(0);
    expect(envelope.titleKey).not.toBe(envelope.bodyKey);
    expect(envelope.splitBy).toBe('receiving-client');
    expect(contract.signature.canonicalOrder).toContain('body');
  });
});
