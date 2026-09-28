// #130-A5：一键冻结的运维入口（列状态 / 冻结 / 解冻 / 吊销 / 一键全部失效 / 重建后废所有发送方）。
//
// 这一片要守的五件事：
//  ① **校验排在写入之前** —— "要确认的那一类"缺 confirm 时必须 400 且**表一个字节都不动**；
//     反过来（先写再拒）的表现是运维以为自己没点成，而设备已经被吊销了。
//  ② **每个动作回答"影响了谁 / 几台"** —— 0 台与"没这个钮"在现场看起来一模一样。
//  ③ **吊销不删记录**（契约 dataNeverDeletedByRevoke）—— 删记录会把"曾经是谁"与可重新配对一起带走。
//  ④ **响应白名单挑字段** —— 设备表的一行里有公钥、配对口令摘要、grantsBy。
//  ⑤ **状态名从契约词汇表读** —— 以前实现里有四处写死的状态字符串，那是第二份真值。
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-ops-'));
const ADMIN_TOKEN = 'test-admin-token-for-ops';
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync(ADMIN_TOKEN, 10);
process.env.ENCRYPTION_KEY = 'e'.repeat(64);
process.env.RATE_LIMIT_AUTH_MAX = '100000';
process.env.RATE_LIMIT_GENERAL_MAX = '100000';

const request = require('supertest');
const app = require('../lib/app');
const {
  loadContract,
  assertSupported,
  isContractAvailabilityError,
} = require('../lib/fnthink/contract');
const devicestore = require('../lib/fnthink/devicestore');

const contract = assertSupported(loadContract());
const revocation = contract.revocation;
const CODES = {
  A: '8K3FJ6QPTM9WZ4VHNS',
  B: '7YD4RKQPBM8XZ3VHNT',
  C: '8TQVWZ3XKR5B6YD4HM',
};

function keypair() {
  const { publicKey } = crypto.generateKeyPairSync('ed25519');
  const der = publicKey.export({ type: 'spki', format: 'der' });
  return der.subarray(der.length - 32).toString('base64');
}

function register(addressCode) {
  const devices = devicestore.loadDevices();
  devicestore.registerDevice(
    contract,
    devices,
    { addressCode, publicKey: keypair(), name: 'ops' },
    Date.now(),
  );
  devicestore.saveDevices(devices);
}

function statusOf(addressCode) {
  return (devicestore.loadDevices()[addressCode] || {}).status;
}

let sessionId = null;
/// supertest 的 set() 挂在具体请求上（request(app) 本身没有），所以两个 helper 各带一条链。
const adminGet = (url) => request(app).get(url).set('x-session-id', sessionId);
const adminPost = (url, body) =>
  request(app)
    .post(url)
    .set('x-session-id', sessionId)
    .send(body || {});

function readBetween(rel, from, to) {
  const src = fs.readFileSync(path.join(__dirname, rel), 'utf8');
  const start = src.indexOf(from);
  const end = src.indexOf(to);
  expect(start).toBeGreaterThan(-1);
  expect(end).toBeGreaterThan(start);
  return src.slice(start, end);
}

/// 去掉整行注释（这个仓的 JS 注释一律独占一行），免得源码守卫把注释里的词当成代码。
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

describe('运维入口（#130-A5）', () => {
  test('未登录既读不到也按不动：这一组会动设备，不能是个开放口', async () => {
    const list = await request(app).get('/api/admin/fnthink/devices');
    expect(list.status).toBe(401);
    const frozen = await request(app)
      .post('/api/admin/fnthink/devices/freeze')
      .send({ addressCode: CODES.A });
    expect(frozen.status).toBe(401);
  });

  test('冻结：状态写进表、返回那一台，且动作名回显（运维要知道自己刚才是按了哪一颗）', async () => {
    register(CODES.A);
    const res = await adminPost('/api/admin/fnthink/devices/freeze', {
      addressCode: CODES.A,
    });
    expect(res.status).toBe(200);
    expect(res.body.data.action).toBe('freeze');
    expect(res.body.data.affected).toBe(1);
    // 期望档位从契约读，不在测试里写死状态名（写死就是测试与实现各一份真值）
    expect(res.body.data.device.status).toBe(revocation.frozenStatus);
    expect(statusOf(CODES.A)).toBe(revocation.frozenStatus);
  });

  test('解冻：去处是契约里"允许投递"那一档，不是代码里写回某个字符串', async () => {
    const res = await adminPost('/api/admin/fnthink/devices/resume', {
      addressCode: CODES.A,
    });
    expect(res.status).toBe(200);
    expect(res.body.data.device.status).toBe(revocation.resumableStatus);
    expect(statusOf(CODES.A)).toBe(revocation.resumableStatus);
  });

  test('缺 confirm ⇒ 400 且表一个字节都不动（先写再拒是最坏的那个顺序）', async () => {
    const before = statusOf(CODES.A);
    const res = await adminPost('/api/admin/fnthink/devices/revoke', {
      addressCode: CODES.A,
    });
    expect(res.status).toBe(400);
    expect(res.body.message).toMatch(/confirm/);
    expect(statusOf(CODES.A)).toBe(before);
  });

  test('吊销：状态改掉、记录与公钥都留着（吊销不删历史）', async () => {
    const res = await adminPost('/api/admin/fnthink/devices/revoke', {
      addressCode: CODES.A,
      confirm: true,
    });
    expect(res.status).toBe(200);
    expect(res.body.data.device.status).toBe(revocation.revokedStatus);
    const record = devicestore.loadDevices()[CODES.A];
    expect(record.revokedAt).toBeTruthy();
    // 这一条才是"不删"的实质：公钥还在，所以看得见曾经是谁，也能重新配对回去
    expect(record.publicKey).toBeTruthy();
  });

  test('一键全部失效：返回被改动的台数；再按一次是 0 台而不是"没反应"', async () => {
    register(CODES.B);
    register(CODES.C);
    const first = await adminPost('/api/admin/fnthink/devices/revoke-all', {
      confirm: true,
    });
    expect(first.status).toBe(200);
    // 已经吊销那台不该被再算一次：affected 是"被改动的台数"，不是"表里的台数"
    expect(first.body.data.affected).toBe(2);
    expect(first.body.data.total).toBe(3);
    const second = await adminPost('/api/admin/fnthink/devices/revoke-all', {
      confirm: true,
    });
    expect(second.body.data.affected).toBe(0);
    expect(second.body.data.total).toBe(3);
  });

  test('重建身份后废所有发送方：只动在册可投递的那些，不动已吊销的（也不覆盖 revokedAt）', async () => {
    // 解冻 A 把它放回"可投递"那一档。**不能**用重新登记来做这件事：同一个地址码换公钥会被
    // "公钥不许静默替换"那条拒掉（DEVICE_KEY_SWAP），那是另一条判据在生效，不是这里想测的东西。
    await adminPost('/api/admin/fnthink/devices/resume', { addressCode: CODES.A });
    expect(statusOf(CODES.A)).toBe(revocation.resumableStatus);
    const revokedBefore = devicestore.loadDevices()[CODES.B];
    const res = await adminPost('/api/admin/fnthink/devices/rebuild-invalidation', {
      confirm: true,
    });
    expect(res.status).toBe(200);
    expect(res.body.data.affected).toBe(1);
    expect(statusOf(CODES.A)).toBe(revocation.afterRebuildStatus);
    expect(statusOf(CODES.B)).toBe(revocation.revokedStatus);
    expect(devicestore.loadDevices()[CODES.B].revokedAt).toBe(revokedBefore.revokedAt);
  });

  test('地址码形状不对 ⇒ 400（不把垃圾当键去查表）；不在表里 ⇒ 404 并点名是哪台', async () => {
    const bad = await adminPost('/api/admin/fnthink/devices/freeze', {
      addressCode: 'not a code',
    });
    expect(bad.status).toBe(400);
    const missing = await adminPost('/api/admin/fnthink/devices/freeze', {
      addressCode: 'ZZZZZZZZZZZZZZZZZZ',
    });
    expect(missing.status).toBe(404);
    expect(missing.body.message).toMatch(/ZZZZ/);
  });

  test('列状态：每档计数都覆盖契约状态表，limit 被契约上限夹住，truncated 必须说出口', async () => {
    const res = await adminGet('/api/admin/fnthink/devices');
    expect(res.status).toBe(200);
    const data = res.body.data;
    for (const status of Object.keys(revocation.deviceStatuses)) {
      expect(Object.keys(data.statuses)).toContain(status);
    }
    expect(data.limit).toBe(contract.ops.listMaxRows);
    expect(data.returned).toBe(Math.min(data.total, data.limit));
    expect(data.truncated).toBe(data.total > data.limit);
    const over = await adminGet('/api/admin/fnthink/devices?limit=999999');
    expect(over.body.data.limit).toBe(contract.ops.listMaxRows);
  });

  test('列状态的 status 参数只认契约里的档位（拼错不许静默返回空列表）', async () => {
    const bad = await adminGet('/api/admin/fnthink/devices?status=nonsense');
    expect(bad.status).toBe(400);
    const ok = await adminGet(`/api/admin/fnthink/devices?status=${revocation.revokedStatus}`);
    expect(ok.status).toBe(200);
    expect(ok.body.data.devices.length).toBeGreaterThan(0);
    expect(ok.body.data.devices.every((d) => d.status === revocation.revokedStatus)).toBe(true);
  });

  test('响应只有白名单那几个键：公钥、配对摘要、授权表一律不端出去', async () => {
    const res = await adminGet('/api/admin/fnthink/devices');
    const row = res.body.data.devices[0];
    expect(Object.keys(row).sort()).toEqual(
      ['addressCode', 'createdAt', 'lastSeenAt', 'name', 'status', 'statusChangedAt'].sort(),
    );
    const flat = JSON.stringify(res.body.data);
    for (const forbidden of ['publicKey', 'pairingCodeDigest', 'grantsBy', 'secret', 'Digest']) {
      expect(flat).not.toContain(forbidden);
    }
  });

  test('状态名真的从契约读：改副本里的档位名，写入的档位跟着变', () => {
    const renamed = {
      ...contract,
      revocation: {
        ...revocation,
        resumableStatus: revocation.afterRebuildStatus,
      },
    };
    const devices = devicestore.loadDevices();
    const record = devicestore.resumeDevice(renamed, devices, CODES.C, Date.now());
    expect(record.status).toBe(renamed.revocation.resumableStatus);
  });

  test('档位名漂在契约状态表外 ⇒ 抛可降级的 SHAPE（不是"写进去一个没人认得的字符串"）', () => {
    const broken = {
      ...contract,
      revocation: { ...revocation, revokedStatus: 'deleted' },
    };
    let err = null;
    try {
      devicestore.revokeDevice(broken, devicestore.loadDevices(), CODES.C, Date.now());
    } catch (e) {
      err = e;
    }
    expect(err).not.toBeNull();
    expect(isContractAvailabilityError(err)).toBe(true);
  });

  test('契约取数处只许抛 shapeError（状态词汇表与 ops 那两个函数）', () => {
    const names = readBetween(
      '../lib/fnthink/devicestore.js',
      'function statusNameOf',
      'function opsConfigFromContract',
    );
    expect(names).not.toContain('throw new Error');
    expect(names).toContain('shapeError');
    const cfg = readBetween(
      '../lib/fnthink/devicestore.js',
      'function opsConfigFromContract',
      'function setDeviceStatus',
    );
    expect(cfg).not.toContain('throw new Error');
    expect(cfg).toContain('shapeError');
    // 缺 ops 段 ⇒ 同样是"可降级的契约内容问题"（运维口答 503，而不是把整台服务打挂）
    const noOps = { ...contract };
    delete noOps.ops;
    let err = null;
    try {
      devicestore.opsConfigFromContract(noOps);
    } catch (e) {
      err = e;
    }
    expect(err).not.toBeNull();
    expect(isContractAvailabilityError(err)).toBe(true);
  });

  test('源码守卫：实现里不再出现写死的设备档位名（那四处以前各写一份）', () => {
    const names = Object.keys(revocation.deviceStatuses);
    for (const rel of [
      '../lib/fnthink/devicestore.js',
      '../lib/routes/ops.js',
      '../lib/fnthink/verify.js',
    ]) {
      const src = stripComments(fs.readFileSync(path.join(__dirname, rel), 'utf8'));
      for (const name of names) {
        expect(src).not.toContain(`'${name}'`);
        expect(src).not.toContain(`"${name}"`);
      }
    }
  });

  test('运维入口只挂在管理面：公网面上按不到这些钮', async () => {
    const viaPublic = await request(app).post('/api/fnthink/devices/freeze').send({});
    expect([404, 403]).toContain(viaPublic.status);
    const src = fs.readFileSync(path.join(__dirname, '../lib/app.js'), 'utf8');
    expect(src).toContain("app.use('/api/admin', opsRoutes)");
    expect(src).not.toContain("app.use('/api/fnthink', opsRoutes)");
  });
});
