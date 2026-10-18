// T156 片1：`POST /api/fnthink/peer-presence` —— 设备面对「对端多久没来取」的那条读口。
//
// 这一批发出来要盯住的四件事（每一件都有一句"写反了会怎样"）：
//  ① 三态的**唯一作者仍是 devicestore.devicePresence**：本文件断言的是"这一发把三态原样端出来"，
//     不在这里重算一遍（重算就是第二份在线判据，分叉的表现是那页写在线、投递那侧说这台早掉了）；
//  ② 边界方向只有一个：**他把我列进他的名单**，我才看得见他的年龄。反过来（按本机 grantsBy 列人）
//     在本文件里必须红 —— 那条写法看起来"更实用"，实际是本机单方面决定观察谁；
//  ③ 年龄的单位与主语：交出去的是服务端算好的**整数秒**，不是任何往返时延（`Xms` 那一形已被否）；
//  ④ 缺席不是状态：关系不存在时那一行根本不出现在响应里，而"从没上过线"是 `unknown` + 两个 null。
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-peer-presence-'));
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-peer-presence', 10);
process.env.ENCRYPTION_KEY = 'b'.repeat(64);
process.env.RATE_LIMIT_GENERAL_MAX = '100000';
process.env.RATE_LIMIT_AUTH_MAX = '100000';
process.env.RATE_LIMIT_FNTHINK_MAX = '100000';

const request = require('supertest');
const app = require('../lib/app');
const {
  loadContract,
  assertSupported,
  canonicalOrder,
  statusCode,
} = require('../lib/fnthink/contract');
const verify = require('../lib/fnthink/verify');
const devicestore = require('../lib/fnthink/devicestore');

const contract = assertSupported(loadContract());
const readout = devicestore.peerReadoutFromContract(contract);

const ME = 'PPRA7RABQKPZ3STVWX'; // 签名者（要读对端年龄的那台）
const ONL = 'PPRB7RABQKPZ3STVWX'; // 刚来取过
const OFF = 'PPRC7RABQKPZ3STVWX'; // 很久没来
const NEVER = 'PPRD7RABQKPZ3STVWX'; // 一次都没来过
const ONEWAY = 'PPRE7RABQKPZ3STVWX'; // 我把他列进名单，他没列我
const STRANGER = 'PPRF7RABQKPZ3STVWX'; // 谁的名单里都没有

function keypair() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const der = publicKey.export({ type: 'spki', format: 'der' });
  return { rawBase64: der.subarray(der.length - 32).toString('base64'), privateKey };
}

const keys = {};
for (const code of [ME, ONL, OFF, NEVER, ONEWAY, STRANGER]) keys[code] = keypair();

function register(addressCode, kp) {
  const devices = devicestore.loadDevices();
  devicestore.registerDevice(
    contract,
    devices,
    { addressCode, publicKey: kp.rawBase64, name: 'peer-presence-test' },
    Date.now(),
  );
  devicestore.saveDevices(devices);
}

/// 写一条"GRANTOR 允许 GRANTED 投进来"的关系（授权写入的唯一咽喉，它自己落盘）。
function grant(grantor, granted) {
  const devices = devicestore.loadDevices();
  devicestore.approvePeer(contract, devices, grantor, granted, 'L1', [], Date.now());
}

function seedSeen(addressCode, at) {
  devicestore.touchDevice(contract, devicestore.loadDevices(), addressCode, at);
}

function sign(kp, fields) {
  const map = {};
  for (const key of canonicalOrder(contract)) map[key] = fields[key];
  const canonical = verify.canonicalBytes(contract, map);
  return { map, signature: crypto.sign(null, canonical, kp.privateKey).toString('base64') };
}

/// 这一族的载荷今日为空 ⇒ body 就是 `{}`（与 endpointList 同一写法，测试里不发明第二种）。
function presenceBody(kp, sender, target, payloadObj) {
  const spec = contract.clientEvents.peerPresence;
  const fields = Object.assign(
    {
      version: '1',
      type: spec.messageType,
      target,
      ts: String(Math.floor(Date.now() / 1000)),
      nonce: 'pp-' + crypto.randomBytes(6).toString('hex'),
      body: payloadObj === undefined ? '{}' : JSON.stringify(payloadObj),
    },
    { sender },
  );
  // canonicalOrder 里的 sender 位（与 routes 那边 signedFields 取同一批键）
  const signed = sign(kp, fields);
  return { sender, signature: signed.signature, fields: signed.map };
}

function post(body) {
  return request(app).post('/api/fnthink/peer-presence').send(body);
}

function rowsOf(res) {
  return res.body[readout.peersField];
}

function rowOf(res, code) {
  return rowsOf(res).find((r) => r[readout.addressCodeField] === code);
}

beforeAll(() => {
  for (const code of [ME, ONL, OFF, NEVER, ONEWAY, STRANGER]) register(code, keys[code]);
  // 边界只认"他把我列进他的名单"这四条关系：
  grant(ONL, ME);
  grant(OFF, ME);
  grant(ME, OFF); // 双向那一半：他列我、我也列他 —— 划掉他那一半时，我这一半必须还在
  grant(NEVER, ME);
  grant(ME, ONEWAY); // 反向那一发：我列了他 ⇒ 他的年龄对我**不**可见
});

describe('POST /api/fnthink/peer-presence（T156 片1）', () => {
  test('三态原样端出来：在线／离线／从没来过是三个答案，不是两个', async () => {
    const now = Date.now();
    seedSeen(ONL, now - 5000);
    seedSeen(OFF, now - 15 * 60 * 1000);
    const res = await post(presenceBody(keys[ME], ME, ME)).expect(200);
    expect(Array.isArray(rowsOf(res))).toBe(true);
    expect(rowOf(res, ONL)[readout.presenceField]).toBe('online');
    expect(rowOf(res, OFF)[readout.presenceField]).toBe('offline');
    expect(rowOf(res, NEVER)[readout.presenceField]).toBe('unknown');
  });

  test('从没来过的那台两个数都是 null（回 0 会被读成"刚刚来过"）', async () => {
    const res = await post(presenceBody(keys[ME], ME, ME)).expect(200);
    const row = rowOf(res, NEVER);
    expect(row[readout.lastSeenField]).toBeNull();
    expect(row[readout.ageField]).toBeNull();
    // unknown 不许画成离线：这一档必须真的没有"上次"，而不是"上次=0"
    expect(row[readout.presenceField]).not.toBe('offline');
  });

  test('年龄是服务端算好的整数秒，且与同一发里的 serverTime 自洽（不是时延、不是本地钟）', async () => {
    const res = await post(presenceBody(keys[ME], ME, ME)).expect(200);
    const row = rowOf(res, OFF);
    const age = row[readout.ageField];
    expect(Number.isInteger(age)).toBe(true);
    // 秒而不是毫秒：那一档离线约 15 分钟，毫秒数会是 90 万；这条断言把"单位"钉在数上而不是注释上
    expect(age).toBeGreaterThanOrEqual(60);
    expect(age).toBeLessThan(3600);
    // 与响应自带的 lastSeenAt / serverTime 相减一致（向下取整）：客户端不需要第三把钟
    expect(age * 1000).toBeLessThanOrEqual(res.body.serverTime - row[readout.lastSeenField]);
    expect((age + 1) * 1000).toBeGreaterThan(res.body.serverTime - row[readout.lastSeenField]);
    expect(readout.ageUnit).toBe('seconds');
  });

  test('响应里一个 ms 形状都没有：字段名单恰好是契约声明的那四个', async () => {
    const res = await post(presenceBody(keys[ME], ME, ME)).expect(200);
    const declared = [
      readout.addressCodeField,
      readout.presenceField,
      readout.lastSeenField,
      readout.ageField,
    ].sort();
    for (const row of rowsOf(res)) {
      expect(Object.keys(row).sort()).toEqual(declared);
    }
    expect(JSON.stringify(res.body)).not.toMatch(/"latency/i);
  });

  test('边界方向只有一个：他没把我列进他的名单，他的年龄就不出现在这一发里', async () => {
    const now = Date.now();
    seedSeen(ONL, now - 5000); // 让他"在线"，这样缺席就不可能是"没读数所以省掉了"
    const res = await post(presenceBody(keys[ME], ME, ME)).expect(200);
    expect(rowOf(res, ONL)).toBeTruthy();
    expect(rowOf(res, ONEWAY)).toBeUndefined();
    expect(rowOf(res, STRANGER)).toBeUndefined();
    // 我自己那一行也不回答：这一发的主语是"对端"
    expect(rowOf(res, ME)).toBeUndefined();
  });

  test('他把我从名单里划掉 ⇒ 当场不可见（可达集合读的是关系，不是一份缓存名单）', async () => {
    const devices = devicestore.loadDevices();
    // 划的是"他给我的那一半"：revokePeer 的唯一删除口径只能落在签名者自己那一行上（incoming）。
    devicestore.revokePeer(contract, devices, OFF, ME, Date.now());
    const res = await post(presenceBody(keys[ME], ME, ME)).expect(200);
    expect(rowOf(res, OFF)).toBeUndefined();
    // 而我给他的那一半还在（两件事不许并成一件：那一半的主语是他，划它的得是他自己）
    const after = devicestore.loadDevices();
    expect(devicestore.peerGrant(contract, after[ME], OFF)).toBeTruthy();
  });

  test('点名查询被拒：载荷里带 peer 就是一条枚举器，一律 403 且与"没配过对"同一句话', async () => {
    const res = await post(presenceBody(keys[ME], ME, ME, { peer: STRANGER }));
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
    expect(res.body).toEqual({ receipt: 'rejected_capability' });
  });

  test('target 写成别人 ⇒ 拒（替他查他那份名单，与 probe 那一条同一个论证）', async () => {
    const res = await post(presenceBody(keys[ME], ME, ONL));
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
    expect(res.body).toEqual({ receipt: 'rejected_capability' });
  });

  test('带着私钥来的包与"没签上"逐字节同形，且一个字段都不读', async () => {
    const body = presenceBody(keys[ME], ME, ME);
    body.privateKey = crypto.randomBytes(32).toString('base64');
    const res = await post(body);
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
    expect(res.body).toEqual({ receipt: 'rejected_unsigned' });
  });

  test('未登记与签名不对逐字节同形（这一发不是地址码枚举器）', async () => {
    const unknown = await post(presenceBody(keypair(), 'PPRG7RABQKPZ3STVWX', 'PPRG7RABQKPZ3STVWX'));
    const forged = presenceBody(keys[ME], ME, ME);
    forged.signature = crypto
      .sign(null, Buffer.from('别的'), keypair().privateKey)
      .toString('base64');
    const bad = await post(forged);
    expect(unknown.status).toBe(statusCode(contract, 'forbidden'));
    expect(unknown.status).toBe(bad.status);
    expect(unknown.body).toEqual(bad.body);
  });

  test('这条路由挂在契约声明的那条路径上（改任一边都必须同时改另一边）', async () => {
    const mounted = (app.get('fnthinkEndpoints') || []).map((line) =>
      String(line).replace(/^[A-Z,]+ /, ''),
    );
    expect(mounted).toContain(contract.transport.apiPaths.peerPresence);
    expect(contract.limits.perSenderOnly).toContain('peerPresence');
  });
});

describe('presence.peerReadout 的四道形状闸（读不出来就不回答）', () => {
  function clone(mutate) {
    const copy = JSON.parse(JSON.stringify(contract));
    mutate(copy);
    return copy;
  }

  test('缺整段 ⇒ 抛（不补默认字段名：拼出来那份与设备侧读的名单一旦不同，症状是永远"还不知道"）', () => {
    const broken = clone((c) => delete c.presence.peerReadout);
    expect(() => devicestore.peerReadoutFromContract(broken)).toThrow(/peerReadout/);
  });

  test('单位被改成毫秒 ⇒ 抛（那一格的主语是"那台多久没来取"，不是链路时延）', () => {
    const broken = clone((c) => (c.presence.peerReadout.ageUnit = 'milliseconds'));
    expect(() => devicestore.peerReadoutFromContract(broken)).toThrow(/ageUnit/);
  });

  test('边界被换成"任何持地址码者可查" ⇒ 抛（那是维护者否掉的方案 3）', () => {
    const broken = clone((c) => (c.presence.peerReadout.boundary = 'any-address-code'));
    expect(() => devicestore.peerReadoutFromContract(broken)).toThrow(/boundary/);
  });

  test('缺席那一档被塞进三态词表 ⇒ 抛（把"他不让我看"说成"他设备没开机"是一句不实陈述）', () => {
    const broken = clone((c) => c.presence.states.push(c.presence.peerReadout.absentMeans));
    expect(() => devicestore.peerReadoutFromContract(broken)).toThrow(/absentMeans/);
  });

  test('event 指向一种没声明的事件 ⇒ 抛（年龄读口没有裁决处）', () => {
    const broken = clone((c) => (c.presence.peerReadout.event = 'peerPresentiaa'));
    expect(() => devicestore.peerReadoutFromContract(broken)).toThrow(/event/);
  });

  test('今天这份读数的可达集合是"他给我的那一半"，不是"我给他的那一半"（方向写反必须红）', () => {
    const devices = devicestore.loadDevices();
    const rows = devicestore.peerPresenceReadout(contract, devices, ME, Date.now());
    const codes = rows.map((r) => r[readout.addressCodeField]);
    expect(codes).toContain(NEVER); // 他把我列进名单（哪怕他一次没来过）
    expect(codes).not.toContain(ONEWAY); // 我只列了他，他没列我 ⇒ 不可见
    // 一把尺照两半数：换成按本机 grantsBy 列人，这一发就会把 ONEWAY 端出来 —— 那条方向是 fail-open
    expect(devicestore.peerGrant(contract, devices[ME], ONEWAY)).toBeTruthy();
  });
});
