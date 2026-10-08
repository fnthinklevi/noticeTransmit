// T106 片①b：端点档的**干跑**（POST /api/fnthink/p/<endpointId>/probe + Bearer 口令）。
//
// 这一片欠的证据只有两件事，其余都是它们的推论：
//  ① **不投递**：一次都不落消息、不产回执、不写调用日志、不花端点配额 —— 这是这一发存在的全部
//    理由（否则"测一次"等于往对面真推一条），也是它与片① 之后那条 `continue`（跳过不探）的区别。
//  ② **判定复用收单那一条链**：探针说的绿必须等于真发也能进。两处各判一次的下场是
//    "绿徽标配一条 401"，而拿着徽标去查的人是我们自己。
//
// ⚠ 这一族**不开** `FNTHINK_ALLOW_INSECURE_ENDPOINT`（与 fnthink-endpoint-intake.test.js 相反）：
//   这里要验的一条就是 HTTPS-only 在探针这一发上照旧生效，而逃生阀一旦打开，那条用例就恒真。
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-probe-'));
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-probe', 10);
process.env.ENCRYPTION_KEY = 'c'.repeat(64);

const request = require('supertest');
const app = require('../lib/app');
const { loadContract, assertSupported, statusCode } = require('../lib/fnthink/contract');
const ds = require('../lib/fnthink/devicestore');
const ms = require('../lib/fnthink/messagestore');
const intake = require('../lib/fnthink/endpointintake');

const contract = assertSupported(loadContract());
const ingress = intake.ingressFromContract(contract);
const readyField = contract.clientEvents.probe.readyField;
const OWNER = '7Q2WXB8HJN4RPT5KMD';
const OWNER2 = '3HB8YV2NRC6WQK9TSJ';

function publicKey() {
  const { publicKey } = crypto.generateKeyPairSync('ed25519');
  const der = publicKey.export({ type: 'spki', format: 'der' });
  return der.subarray(der.length - 32).toString('base64');
}

let good = null; // {id, secret}：绑着设备、不限来源的那一把
let unbound = null; // 没绑设备（owner 为空）⇒ 收单会 403 unbound_endpoint
let strictIp = null; // IP 白名单里没有本机 ⇒ 与"口令错"同形
let revoked = null; // 已吊销

const probePath = (record) => `/api/fnthink/p/${record.id}/probe`;
const bearer = (secret) => ({ Authorization: `Bearer ${secret}` });
/// 每一条探针都显式声明"走 https"：`secure` 由 routes.js 直接读这个头（不依赖 trust proxy），
/// 而这一族的默认档是 reject。忘了标的后果不是"用例失败"，是**每条红都可能只是传输层拦的**。
const probeRequest = (record, secret = null) =>
  request(app)
    .post(probePath(record))
    .set('x-forwarded-proto', 'https')
    .set(bearer(secret === null ? record.secret : secret));

/// 探针之后必须一个字节都没动过的三本账。
function counts() {
  const endpoints = ds.loadEndpoints();
  return {
    messages: Object.keys(ms.loadMessages()).length,
    calls: Object.values(endpoints).reduce((n, r) => n + (r.calls || []).length, 0),
    nonces: Object.keys(ds.loadNonces()).length,
  };
}

beforeAll(() => {
  const devices = ds.loadDevices();
  ds.registerDevice(
    contract,
    devices,
    { addressCode: OWNER, publicKey: publicKey(), name: '本机' },
    Date.now(),
  );
  // 另一台登记过的设备：上面那条"A 的 id + B 的口令"要能落到一个真实存在的人身上，
  // 断言才不是"落进一个谁都不认得的字符串"。
  ds.registerDevice(
    contract,
    devices,
    { addressCode: OWNER2, publicKey: publicKey(), name: '另一台' },
    Date.now(),
  );
  ds.saveDevices(devices);
  const endpoints = ds.loadEndpoints();
  good = ds.createEndpoint(contract, endpoints, { owner: OWNER, name: 'NAS' }, Date.now());
  unbound = ds.createEndpoint(contract, endpoints, { name: '没绑设备' }, Date.now());
  strictIp = ds.createEndpoint(
    contract,
    endpoints,
    { owner: OWNER, name: '只放家里', ipAllowlist: ['203.0.113.9'] },
    Date.now(),
  );
  revoked = ds.createEndpoint(contract, endpoints, { owner: OWNER, name: '要关掉的' }, Date.now());
  ds.revokeEndpoint(contract, endpoints, revoked.id, Date.now());
  ds.saveEndpoints(endpoints);
});

describe('端点档的干跑：绿的那一半（T106 片①b）', () => {
  test('口令对 + https ⇒ 200，而响应里只有「结论 + 服务器时间」两个键', async () => {
    const res = await probeRequest(good);
    expect(res.status).toBe(200);
    expect(Object.keys(res.body).sort()).toEqual(['serverTime', readyField].sort());
    expect(res.body[readyField]).toBe(true);
  });

  test('不投递：消息表、nonce 台账、调用日志三本账一条都不多（这一发存在的全部理由）', async () => {
    const before = counts();
    expect((await probeRequest(good)).body[readyField]).toBe(true);
    const after = counts();
    expect(after.messages).toBe(before.messages);
    expect(after.nonces).toBe(before.nonces);
    expect(after.calls).toBe(before.calls);
  });

  test('带正文来探测也**不会**投进一条正文：探针一个载荷字段都不读', async () => {
    const before = counts();
    const res = await request(app)
      .post(probePath(good))
      .set('x-forwarded-proto', 'https')
      .set(bearer(good.secret))
      .send({ title: '这一条绝不能落地', body: 'x'.repeat(5000), type: 'action', level: 'L3' });
    expect(res.status).toBe(200);
    expect(res.body[readyField]).toBe(true);
    expect(counts().messages).toBe(before.messages);
  });

  test('不花端点配额：连打 perMinute+5 次仍全绿，而紧接着的真发照样排队成功', async () => {
    const n = ingress.perMinute + 5;
    for (let i = 0; i < n; i++) {
      // 探针一旦开始计费，这里会在第 perMinute 次变红 —— 表现正是"监测把被监测的那条路挤死"。
      expect((await probeRequest(good)).body[readyField]).toBe(true);
    }
    const push = await request(app)
      .post(`/api/fnthink/p/${good.id}`)
      .set('x-forwarded-proto', 'https')
      .set(bearer(good.secret))
      .send({ title: '真的一条', body: '这条该落地' });
    expect(push.status).toBe(statusCode(contract, 'queued'));
    expect(push.body.messageId).toMatch(/^m_/);
  });

  test('探针读的是**当前**状态：当场把那一把吊销，下一发立刻变红（不缓存结论）', async () => {
    const fresh = ds.createEndpoint(
      contract,
      ds.loadEndpoints(),
      { owner: OWNER, name: '临时' },
      Date.now(),
    );
    expect((await probeRequest(fresh)).body[readyField]).toBe(true);
    const endpoints = ds.loadEndpoints();
    ds.revokeEndpoint(contract, endpoints, fresh.id, Date.now());
    ds.saveEndpoints(endpoints);
    expect((await probeRequest(fresh)).body[readyField]).toBe(false);
  });
});

describe('端点档的干跑：红的那一半，且所有红**逐字节同形**', () => {
  const shapeOf = (res) =>
    `${res.status}|${Object.keys(res.body).sort().join(',')}|${res.body[readyField]}`;

  test('口令错 ⇒ ready:false（结论走正文，与签名面那条 /probe 同一个形状）', async () => {
    const res = await probeRequest(good, 'X'.repeat(good.secret.length));
    expect(res.status).toBe(200);
    expect(res.body[readyField]).toBe(false);
  });

  test('认出来的是**口令**而不是路径里那个 id（与收单同一条）：探针不说谎', async () => {
    // 看着多余，其实是"判定复用同一处"的最强证据：`findEndpointBySecret` 的主键是口令摘要，
    // 路径里那个 endpointId 在裁决里不参与识别。所以「A 的 id + B 的口令」这一对在两张面上必须
    // 是**同一个结论**。哪天只给探针补了 id 核查而收单没补，症状就是"徽标绿而推送 401"。
    const other = ds.createEndpoint(
      contract,
      ds.loadEndpoints(),
      { owner: OWNER2, name: '另一台' },
      Date.now(),
    );
    const crossed = await probeRequest({ id: good.id, secret: other.secret });
    expect(crossed.status).toBe(200);
    expect(crossed.body[readyField]).toBe(true);
    // 同一对组合走真发：也是受理，而且落的是**口令那把的 owner**（不是路径里那个 id 的主人）。
    const push = await request(app)
      .post(`/api/fnthink/p/${good.id}`)
      .set('x-forwarded-proto', 'https')
      .set(bearer(other.secret))
      .send({ title: '这一条按口令归属', body: '落哪台由摘要说了算' });
    expect(push.status).toBe(statusCode(contract, 'queued'));
    expect(ms.loadMessages()[push.body.messageId].device).toBe(OWNER2);
  });

  test('口令不属于任何人 / 空口令 / IP 不在名单 ⇒ 逐字节同形（这一面不是端点枚举器）', async () => {
    const nobody = await probeRequest({
      id: 'e_notthere',
      secret: crypto.randomBytes(16).toString('hex'),
    });
    const wrong = await probeRequest(good, 'wrong');
    const ip = await probeRequest(strictIp);
    expect(nobody.body[readyField]).toBe(false);
    expect(wrong.body[readyField]).toBe(false);
    expect(ip.body[readyField]).toBe(false);
    expect(new Set([shapeOf(nobody), shapeOf(wrong), shapeOf(ip)]).size).toBe(1);
  });

  test('端点已吊销 ⇒ 红（那一行还在表里，所以这不是"不存在"那一支，但对外同形）', async () => {
    const res = await probeRequest(revoked);
    expect(res.status).toBe(200);
    expect(res.body[readyField]).toBe(false);
  });

  test('端点没绑设备 ⇒ 红，而真发那一条确实是 403：探针说的红就是这件事', async () => {
    const res = await probeRequest(unbound);
    expect(res.status).toBe(200);
    expect(res.body[readyField]).toBe(false);
    const push = await request(app)
      .post(`/api/fnthink/p/${unbound.id}`)
      .set('x-forwarded-proto', 'https')
      .set(bearer(unbound.secret))
      .send({ title: '试试', body: '看' });
    expect(push.status).toBe(statusCode(contract, 'forbidden'));
  });

  test('明文传输 ⇒ 红：HTTPS-only 在探针这一发上一步都没让（逃生阀确实没开）', async () => {
    expect(process.env.FNTHINK_ALLOW_INSECURE_ENDPOINT).toBeFalsy();
    const res = await request(app).post(probePath(good)).set(bearer(good.secret));
    expect(res.status).toBe(200);
    expect(res.body[readyField]).toBe(false);
  });

  test('连口令都没出示 ⇒ 同一枚红、同一个形状（这一发不给"你漏了头"这种提示）', async () => {
    const res = await request(app).post(probePath(good)).set('x-forwarded-proto', 'https');
    expect(res.status).toBe(200);
    expect(res.body[readyField]).toBe(false);
    expect(shapeOf(res)).toBe(shapeOf(await probeRequest(good, 'wrong')));
  });
});

describe('路由形状：这一发打到的是探针，不是收单（注册顺序在这里有语义）', () => {
  test('POST 尾段字面量 probe ⇒ 命中探针；同一串走 GET 收单那条 ⇒ 401（两条路各判各的）', async () => {
    // 排错了的表现：POST 时被 `/p/:endpointId/:secret` 先接走，把 `probe` 当成口令 ⇒ 401 空 body，
    // 运维读到的却是"口令错了"。这一条就是把那个静默形状变成会红的形状。
    const asProbe = await probeRequest(good);
    expect(asProbe.status).toBe(200);
    expect(asProbe.body[readyField]).toBe(true);
    const asIngress = await request(app)
      .get(`/api/fnthink/p/${good.id}/probe`)
      .set('x-forwarded-proto', 'https');
    expect(asIngress.status).toBe(statusCode(contract, 'unauthorized'));
    expect(asIngress.body[readyField]).toBeUndefined();
  });

  test('探针只挂 POST：GET 那一形（口令在路径段）在这里不存在', async () => {
    const res = await request(app).get(probePath(good)).set('x-forwarded-proto', 'https');
    // 没挂 GET ⇒ 落到收单那条并把 `probe` 当口令，回 401。要的是"绝不是一次成功的探测"。
    expect(res.body[readyField]).toBeUndefined();
    expect(res.status).not.toBe(200);
  });

  test('结论键只有契约那一枚作者：两张面都读 PROBE_READY_FIELD，源码里没有第二处写死的 ready', () => {
    const routes = fs.readFileSync(
      path.join(__dirname, '..', 'lib', 'fnthink', 'routes.js'),
      'utf8',
    );
    // 少了任何一处 ⇒ 那半改成了写死的键名（改契约不报错，设备永远读到 null 而判成"探针没结论"）。
    expect((routes.match(/\[PROBE_READY_FIELD\]/g) || []).length).toBeGreaterThanOrEqual(2);
    expect(/json\(\{\s*ready:/.test(routes)).toBe(false);
  });
});

describe('契约不达标 ⇒ 装载就抛（可降级 SHAPE，而不是等第一条请求冒 500）', () => {
  const clone = () => JSON.parse(JSON.stringify(contract));

  test('缺 endpoint.probe 段就抛：路径与策略没有第二个来源', () => {
    const c = clone();
    delete c.endpoint.probe;
    expect(() => intake.probeFromContract(c)).toThrow(/endpoint\.probe/);
  });

  test('口令放进路径段（bearerPath 里出现 :secret）就抛：探针会被反复自动打，不多送副本', () => {
    const c = clone();
    c.endpoint.probe.bearerPath = '/api/fnthink/p/:endpointId/:secret/probe';
    expect(() => intake.probeFromContract(c)).toThrow(/:secret/);
  });

  test('尾段是参数就抛：它会与收单的 :secret 撞位，而探针会打到收单那条', () => {
    const c = clone();
    c.endpoint.probe.bearerPath = '/api/fnthink/p/:endpointId/:mode';
    expect(() => intake.probeFromContract(c)).toThrow(/字面量/);
  });

  test('落在脱敏前缀之外就抛：这一条与口令同面', () => {
    const c = clone();
    c.endpoint.probe.bearerPath = '/api/fnthink/endpoint-probe';
    expect(() => intake.probeFromContract(c)).toThrow(/accessLogRedactPathPattern/);
  });

  test('secretPlacement 改向就抛：改成 path-segment 不会静默生效', () => {
    const c = clone();
    c.endpoint.probe.secretPlacement = 'path-segment';
    expect(() => intake.probeFromContract(c)).toThrow(/bearer-header/);
  });

  test('writesCallLog 改成 true 就抛：有界日志会被自动重探把自己观察的那份历史挤掉', () => {
    const c = clone();
    c.endpoint.probe.writesCallLog = true;
    expect(() => intake.probeFromContract(c)).toThrow(/writesCallLog/);
  });

  test('chargesIngressQuota 不是布尔就抛（它是取舍，可以翻，但必须写下来并说清理由）', () => {
    const c = clone();
    delete c.endpoint.probe.chargesIngressQuota;
    expect(() => intake.probeFromContract(c)).toThrow(/chargesIngressQuota/);
    const flipped = clone();
    flipped.endpoint.probe.chargesIngressQuota = true;
    expect(() => intake.probeFromContract(flipped)).not.toThrow();
  });

  test('判据自证：probeFromContract 对**当前契约**不抛，且读回来的就是那四条', () => {
    const p = intake.probeFromContract(contract);
    expect(p.bearerPath).toBe(contract.endpoint.probe.bearerPath);
    expect(p.chargesIngressQuota).toBe(false);
    expect(p.writesCallLog).toBe(false);
    expect(p.secretPlacement).toBe('bearer-header');
  });
});
