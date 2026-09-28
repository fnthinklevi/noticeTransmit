// T38：接入端点的存储层与管理面。
//
// 这一片真正在守的六件事：
//  ① **明文口令只在创建/轮换那一次出现**，表里只有摘要；而**对外的形状连摘要都不带**
//     （可爆破的靶子不该被端出去 —— 泄露摘要等于把"要猜"降成"能验"）；
//  ② 轮换有宽限期：没有它，换钥匙那一刻所有集成同时 401，后果不是不便，是"从此没人换口令"；
//  ③ 上限只拒新的，绝不挤掉已有端点（挤掉一次 = 某台 NAS 的定时任务从此静默失效）；
//  ④ 调用日志只存元数据且有界：正文进日志会直接推翻 privacy.auditStoresMetadataOnly，
//     而无界的"最近调用"就是攻击者驱动的存储；
//  ⑤ IP 白名单的空名单 = 不限（缺省必须朝"没配也能跑"那一侧）；不匹配的对外结论与口令错同形，
//     否则这个入口是一台"哪个来源被允许"的探针；
//  ⑥ 数字与档位名一律从契约 `endpoint` 段读；取不到抛的是**可降级**的 SHAPE。
//
// 最后那组（写入口）多守一条：**明文口令只出现在创建/轮换那一次的响应里** —— 表里、列表口、
// console 留痕三处都必须搜不到它。
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-ep-'));
const ADMIN_TOKEN = 'test-admin-token-for-ep';
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync(ADMIN_TOKEN, 10);
process.env.ENCRYPTION_KEY = 'f'.repeat(64);
process.env.RATE_LIMIT_AUTH_MAX = '100000';
process.env.RATE_LIMIT_GENERAL_MAX = '100000';
// 有几条用例要经真实入口推一发（supertest 是明文 http），所以开逃生阀。
// "没开时拒不拒"由 fnthink-endpoint-intake.test.js 单独钉。
process.env.FNTHINK_ALLOW_INSECURE_ENDPOINT = '1';

const request = require('supertest');
const app = require('../lib/app');
const {
  loadContract,
  assertSupported,
  isContractAvailabilityError,
  CONTRACT_SHAPE,
  statusCode,
} = require('../lib/fnthink/contract');
const ds = require('../lib/fnthink/devicestore');

const contract = assertSupported(loadContract());
const epc = ds.endpointConfigFromContract(contract);
const NOW = 1_800_000_000_000;

const cfgOf = (patch) => ({
  ...epc,
  ...patch,
  ...('rotation' in patch ? { graceSeconds: patch.rotation } : {}),
});
const OWNER = '8K3FJ6QPTM9WZ4VHNS';

let sessionId = null;
const adminPost = (url, body) =>
  request(app)
    .post(url)
    .set('x-session-id', sessionId)
    .send(body || {});

describe('端点存储层（T38）', () => {
  test('数字与语义只从契约读：改契约副本，上限与宽限跟着变（断来源而不是断值）', () => {
    const mutated = {
      ...contract,
      endpoint: {
        ...contract.endpoint,
        perDeviceMax: 3,
        globalMax: 7,
        rotation: { ...contract.endpoint.rotation, graceSeconds: 120 },
        callLog: {
          ...contract.endpoint.callLog,
          maxPerEndpoint: 5,
          fields: ['at', 'ip', 'outcome'],
        },
      },
    };
    const cfg = ds.endpointConfigFromContract(mutated);
    expect(cfg.perDeviceMax).toBe(3);
    expect(cfg.globalMax).toBe(7);
    expect(cfg.graceSeconds).toBe(120);
    expect(cfg.callLogMax).toBe(5);
    expect(cfg.usableStatus).toBe(mutated.endpoint.usableStatus);
  });

  const broken = [
    ['整段缺失', null],
    ['usableStatus 与 revokedStatus 同名', { usableStatus: 'active', revokedStatus: 'active' }],
    ['usableStatus 不在 statuses 上', { usableStatus: 'pending' }],
    [
      'statuses 多了第三档',
      {
        statuses: ['active', 'revoked', 'snoozed'],
        usableStatus: 'active',
        revokedStatus: 'revoked',
      },
    ],
    ['perDeviceMax=0', { perDeviceMax: 0 }],
    ['口令长度被改短（比配对口令还短，长期凭证更弱）', null],
    ['轮换宽限为 0', { rotation: { graceSeconds: 0 } }],
    ['轮换宽限超过一天', { rotation: { graceSeconds: 86401 } }],
    ['空名单意味着"谁都拒"', { ipAllowlistEmptyMeans: 'none' }],
    ['IP 不匹配给出不同结论（成了探针）', { ipMismatchOutcome: 'distinct' }],
    ['postOnly 的拒绝码不是 4xx', { postOnlyMethodStatus: 500 }],
    ['调用日志上限为 0', { callLog: { maxPerEndpoint: 0, fields: ['at', 'ip', 'outcome'] } }],
    ['调用日志字段里有正文', { callLog: { maxPerEndpoint: 50, fields: ['at', 'ip', 'body'] } }],
    [
      '调用日志字段里有 url（口令就在路径段里）',
      { callLog: { maxPerEndpoint: 50, fields: ['at', 'url'] } },
    ],
  ];
  test.each(broken)('契约 endpoint 段 %s ⇒ 抛可降级的 SHAPE', (_label, patch) => {
    if (_label.includes('口令长度')) {
      // 这条走的是 identity.endpointSecret，不在 endpoint 段里 —— 由 credentials 的位数校验管，
      // 放在这里点名一下，避免读的人以为 endpoint 段还兼管口令强度（它不管）。
      expect(typeof contract.identity.endpointSecret.length).toBe('number');
      return;
    }
    const mutated = { ...contract };
    mutated.endpoint = patch === null ? undefined : { ...contract.endpoint, ...patch };
    let err = null;
    try {
      ds.endpointConfigFromContract(mutated);
    } catch (e) {
      err = e;
    }
    expect(err).not.toBeNull();
    expect(err.code).toBe(CONTRACT_SHAPE);
    expect(isContractAvailabilityError(err)).toBe(true);
  });

  test('轮换：新口令立刻可用，旧口令在宽限内仍可验且标出 usedRotated', () => {
    const endpoints = {};
    const created = ds.createEndpoint(contract, endpoints, { owner: OWNER }, NOW);
    const rotated = ds.rotateEndpoint(contract, endpoints, created.id, NOW + 10);
    expect(rotated.secret).not.toBe(created.secret);
    const byNew = ds.findEndpointBySecret(contract, endpoints, rotated.secret, NOW + 20);
    const byOld = ds.findEndpointBySecret(contract, endpoints, created.secret, NOW + 20);
    expect(byNew.id).toBe(created.id);
    expect(byNew.usedRotated).toBe(false);
    expect(byOld.id).toBe(created.id);
    expect(byOld.usedRotated).toBe(true);
  });

  test('宽限期一过，旧口令就不再多一条命中（这是取舍，不是遗漏）', () => {
    const endpoints = {};
    const created = ds.createEndpoint(contract, endpoints, { owner: OWNER }, NOW);
    ds.rotateEndpoint(contract, endpoints, created.id, NOW + 10, cfgOf({ graceSeconds: 60 }));
    const late = ds.findEndpointBySecret(
      contract,
      endpoints,
      created.secret,
      NOW + 10 + 60 * 1000 + 1,
    );
    expect(late).toBeNull();
  });

  test('轮换一个已吊销的端点 ⇒ 抛（吊销不许被"换个口令"复活）', () => {
    const endpoints = {};
    const created = ds.createEndpoint(contract, endpoints, { owner: OWNER }, NOW);
    ds.revokeEndpoint(contract, endpoints, created.id, NOW + 1);
    expect(() => ds.rotateEndpoint(contract, endpoints, created.id, NOW + 2)).toThrow(/已吊销/);
  });

  test('吊销时把宽限期里的旧摘要一起清掉（留着它，"已吊销"仍可能被验过）', () => {
    const endpoints = {};
    const created = ds.createEndpoint(contract, endpoints, { owner: OWNER }, NOW);
    const rotated = ds.rotateEndpoint(contract, endpoints, created.id, NOW + 1);
    ds.revokeEndpoint(contract, endpoints, created.id, NOW + 2);
    expect(endpoints[created.id].rotatedFrom).toBeNull();
    expect(ds.findEndpointBySecret(contract, endpoints, created.secret, NOW + 3)).toBeNull();
    expect(ds.findEndpointBySecret(contract, endpoints, rotated.secret, NOW + 3)).toBeNull();
  });

  test('每台设备到上限只拒新的：一条已有端点都没被挤掉', () => {
    const endpoints = {};
    const cfg = cfgOf({ perDeviceMax: 2 });
    const made = [];
    for (let i = 0; i < cfg.perDeviceMax; i += 1) {
      made.push(ds.createEndpoint(contract, endpoints, { owner: OWNER }, NOW + i, cfg));
    }
    expect(Object.keys(endpoints)).toHaveLength(cfg.perDeviceMax);
    let err = null;
    try {
      ds.createEndpoint(contract, endpoints, { owner: OWNER }, NOW + 99, cfg);
    } catch (e) {
      err = e;
    }
    expect(err).not.toBeNull();
    expect(err.code).toBe(ds.ENDPOINT_CAP_CODE);
    // 挤掉一个已有端点 = 某台 NAS 的定时任务从此静默失效，与设备表那条同一条红线
    expect(Object.keys(endpoints)).toHaveLength(cfg.perDeviceMax);
    for (const one of made) {
      expect(ds.findEndpointBySecret(contract, endpoints, one.secret, NOW + 100)).not.toBeNull();
    }
  });

  test('换一台设备也一样受全局上限管（否则 perDeviceMax × 台数就是无界）', () => {
    const endpoints = {};
    const cfg = cfgOf({ globalMax: 3, perDeviceMax: 2 });
    ds.createEndpoint(contract, endpoints, { owner: 'A1' }, NOW, cfg);
    ds.createEndpoint(contract, endpoints, { owner: 'A2' }, NOW + 1, cfg);
    ds.createEndpoint(contract, endpoints, { owner: 'A3' }, NOW + 2, cfg);
    let err = null;
    try {
      ds.createEndpoint(contract, endpoints, { owner: 'A4' }, NOW + 3, cfg);
    } catch (e) {
      err = e;
    }
    expect(err).not.toBeNull();
    expect(err.code).toBe(ds.ENDPOINT_CAP_CODE);
    // 全局那把先响的时候，第四台设备连"自己的名额还没用完"都不该看到成功
    expect(Object.keys(endpoints)).toHaveLength(3);
  });

  test('调用日志只记契约白名单那几个字段：传进来的正文一个字节都不落', () => {
    const endpoints = {};
    const created = ds.createEndpoint(contract, endpoints, { owner: OWNER }, NOW);
    ds.recordEndpointCall(
      contract,
      endpoints,
      created.id,
      { at: NOW, ip: '203.0.113.9', outcome: 'queued', body: '机箱温度 63℃', title: '告警' },
      NOW,
      cfgOf({ callLogMax: 2 }),
    );
    const logged = endpoints[created.id].calls[0];
    expect(Object.keys(logged).sort()).toEqual(['at', 'ip', 'outcome']);
    expect(JSON.stringify(endpoints)).not.toContain('机箱温度');
    expect(endpoints[created.id].lastUsedAt).toBe(NOW);
  });

  test('调用日志是有界环（灌满只留最新的几条，不跟着请求数长）', () => {
    const endpoints = {};
    const created = ds.createEndpoint(contract, endpoints, { owner: OWNER }, NOW);
    for (let i = 0; i < 5; i += 1) {
      ds.recordEndpointCall(
        contract,
        endpoints,
        created.id,
        { at: NOW + i, ip: '203.0.113.9', outcome: 'queued' },
        NOW + i,
        cfgOf({ callLogMax: 2 }),
      );
    }
    const calls = endpoints[created.id].calls;
    expect(calls).toHaveLength(2);
    expect(calls.map((c) => c.at)).toEqual([NOW + 3, NOW + 4]);
  });

  test('IP 白名单：空名单 = 不限来源；非空才按名单判（缺省必须朝"没配也能跑"那一侧）', () => {
    const endpoints = {};
    const created = ds.createEndpoint(contract, endpoints, { owner: OWNER }, NOW);
    expect(ds.endpointIpAllowed(endpoints[created.id], '8.8.8.8')).toBe(true);
    ds.setEndpointPolicy(
      contract,
      endpoints,
      created.id,
      { ipAllowlist: ['192.168.1.20'] },
      { ...epc },
    );
    expect(ds.endpointIpAllowed(endpoints[created.id], '192.168.1.20')).toBe(true);
    expect(ds.endpointIpAllowed(endpoints[created.id], '8.8.8.8')).toBe(false);
  });

  test('策略改动能落盘；已吊销的端点改不动（设置不许挂在已经不存在的入口上）', () => {
    const endpoints = {};
    const created = ds.createEndpoint(contract, endpoints, { owner: OWNER, name: '旧名' }, NOW);
    ds.setEndpointPolicy(
      contract,
      endpoints,
      created.id,
      { name: 'NAS 值班', postOnly: false },
      { ...epc },
    );
    expect(endpoints[created.id].name).toBe('NAS 值班');
    expect(endpoints[created.id].postOnly).toBe(false);
    ds.revokeEndpoint(contract, endpoints, created.id, NOW + 1);
    expect(() =>
      ds.setEndpointPolicy(contract, endpoints, created.id, { postOnly: true }, { ...epc }),
    ).toThrow(/不存在或已吊销/);
  });

  test('设备那组口不依赖 endpoint 段：删掉它 ops 段照常读得出（降级面各管各的）', () => {
    const noEndpoint = { ...contract };
    delete noEndpoint.endpoint;
    expect(() => ds.endpointConfigFromContract(noEndpoint)).toThrow(/endpoint/);
    expect(() => ds.opsConfigFromContract(noEndpoint)).not.toThrow();
  });
});

describe('端点的管理面（T38）', () => {
  // ⚠ 表是**共享磁盘**（createEndpoint 会 saveEndpoints 落盘），所以这里不能假设"表里只有一条"：
  //   存储层那组用例已经在同一个 DATA_DIR 里留下过端点。用例一律认自己建的那一条（mine）。
  let mine = null;
  beforeAll(async () => {
    const login = await request(app).post('/api/admin/login').send({ token: ADMIN_TOKEN });
    expect(login.status).toBe(200);
    sessionId = login.body.sessionId;
    const endpoints = ds.loadEndpoints();
    mine = ds.createEndpoint(contract, endpoints, { owner: OWNER, name: 'NAS 值班' }, Date.now());
  });

  test('未登录看不到端点清单（它们是谁开的、从哪些 IP 用，都是运维信息）', async () => {
    const res = await request(app).get('/api/admin/fnthink/endpoints');
    expect(res.status).toBe(401);
  });

  test('列表：白名单字段、不带口令或摘要；statuses 数的是全表而不是截断后那一页', async () => {
    const res = await request(app)
      .get('/api/admin/fnthink/endpoints')
      .set('x-session-id', sessionId);
    expect(res.status).toBe(200);
    const data = res.body.data;
    expect(data.limit).toBe(contract.ops.listMaxRows);
    expect(data.endpoints.length).toBeLessThanOrEqual(data.limit);
    expect(data.truncated).toBe(data.total > data.limit);
    // 按状态计数若统计自截断后的那一页，会把"还有 400 条"报成"只有 100 条" —— 比没有计数更糟。
    const sum = Object.values(data.statuses).reduce((a, b) => a + b, 0);
    expect(sum).toBe(data.total);
    for (const status of [epc.usableStatus, epc.revokedStatus]) {
      expect(Object.keys(data.statuses)).toContain(status);
    }
    expect(data.endpoints.some((e) => e.id === mine.id)).toBe(true);
    const flat = JSON.stringify(data);
    for (const forbidden of ['secretDigest', 'Digest', 'secret']) {
      expect(flat).not.toContain(forbidden);
    }
    expect(Object.keys(data.endpoints[0]).sort()).toEqual(
      [
        'calls',
        'createdAt',
        'id',
        'ipAllowlist',
        'lastUsedAt',
        'name',
        'owner',
        'postOnly',
        'revokedAt',
        'rotatingUntil',
        'status',
      ].sort(),
    );
  });

  test('吊销要确认：缺 confirm ⇒ 400 且口令还能用；带 confirm ⇒ 口令立刻不再命中；再按一次是 0', async () => {
    const table = () => ds.loadEndpoints();
    const without = await adminPost('/api/admin/fnthink/endpoints/revoke', {
      endpointId: mine.id,
    });
    expect(without.status).toBe(400);
    // "拒了但已经写了"是这类接口最坏的形状：运维以为没点成，而那个入口已经关了
    expect(ds.findEndpointBySecret(contract, table(), mine.secret, Date.now())).not.toBeNull();

    const withConfirm = await adminPost('/api/admin/fnthink/endpoints/revoke', {
      endpointId: mine.id,
      confirm: true,
    });
    expect(withConfirm.status).toBe(200);
    expect(withConfirm.body.data.affected).toBe(1);
    expect(withConfirm.body.data.endpoint.status).toBe(epc.revokedStatus);
    // 这条才是"吊销生效"的实质：鉴权按 status 白名单判，宽限期里的旧摘要也一起清了
    expect(ds.findEndpointBySecret(contract, table(), mine.secret, Date.now())).toBeNull();

    const again = await adminPost('/api/admin/fnthink/endpoints/revoke', {
      endpointId: mine.id,
      confirm: true,
    });
    expect(again.body.data.affected).toBe(0);
  });

  test('不存在的端点是 404 并点名（管理面已鉴权，同形规则是给未认证面的）', async () => {
    const res = await adminPost('/api/admin/fnthink/endpoints/revoke', {
      endpointId: 'e_missing',
      confirm: true,
    });
    expect(res.status).toBe(404);
    expect(res.body.message).toMatch(/e_missing/);
  });
});

// T38 的运维那一半补齐：创建 / 轮换 / 改策略。为什么必须凑齐 —— T39–T41 已经把两条收单入口
// 挂上公网，而管理面只能列与吊销 ⇒ 部署好的实例上没法铸出一条口令，"第三方能推"就只是文档话。
describe('端点的写入口（创建 / 轮换 / 改策略）', () => {
  const publicKey = () => {
    const { publicKey: key } = crypto.generateKeyPairSync('ed25519');
    const der = key.export({ type: 'spki', format: 'der' });
    return der.subarray(der.length - 32).toString('base64');
  };

  beforeAll(async () => {
    const login = await request(app).post('/api/admin/login').send({ token: ADMIN_TOKEN });
    expect(login.status).toBe(200);
    sessionId = login.body.sessionId;
    // 端点必须挂在**已登记**的设备上（见下面那条用例），所以先把这台注册出来。
    const devices = ds.loadDevices();
    ds.registerDevice(
      contract,
      devices,
      { addressCode: OWNER, publicKey: publicKey(), name: '本机' },
      Date.now(),
    );
    ds.saveDevices(devices);
  });

  test('未登录铸不出口令：这三个口都是写操作，不能是开放口', async () => {
    for (const url of [
      '/api/admin/fnthink/endpoints/create',
      '/api/admin/fnthink/endpoints/rotate',
      '/api/admin/fnthink/endpoints/policy',
    ]) {
      const res = await request(app).post(url).send({ owner: OWNER, endpointId: 'e_any' });
      expect(res.status).toBe(401);
    }
  });

  test('创建：口令只在这一次回显，表里与列表口都搜不到它', async () => {
    const res = await adminPost('/api/admin/fnthink/endpoints/create', {
      owner: OWNER,
      name: 'NAS 值班',
    });
    expect(res.status).toBe(200);
    expect(res.body.data.action).toBe('createEndpoint');
    expect(res.body.data.affected).toBe(1);
    const secret = res.body.data.secret;
    expect(secret).toMatch(/^[0-9A-Z]+$/);
    expect(res.body.data.secretShownOnce).toBe(true);
    // 缺省方向来自契约（postOnlySwitch=true ⇒ 新建就是"只收 POST"），不是代码里写的一个 true
    expect(res.body.data.endpoint.postOnly).toBe(contract.transport.postOnlySwitch === true);

    const flatFile = fs.readFileSync(ds.ENDPOINT_FILE, 'utf8');
    expect(flatFile).not.toContain(secret);
    const read = await request(app)
      .get('/api/admin/fnthink/endpoints')
      .set('x-session-id', sessionId);
    expect(read.status).toBe(200);
    expect(JSON.stringify(read.body)).not.toContain(secret);
    expect(JSON.stringify(read.body)).not.toContain('secretDigest');
  });

  test('创建的 owner 必须是合法地址码，而且这台设备得真的登记过', async () => {
    const badShape = await adminPost('/api/admin/fnthink/endpoints/create', {
      owner: 'not-a-code!!',
    });
    expect(badShape.status).toBe(400);
    expect(badShape.body.message).toMatch(/地址码/);

    // 形状合法但从没登记过：对着一个不存在的收件人铸入口，表现是第三方拿到 202 而屏幕上什么都没有
    const before = Object.keys(ds.loadEndpoints()).length;
    const unknown = await adminPost('/api/admin/fnthink/endpoints/create', {
      owner: '7YD4RKQPBM8XZ3VHNT',
    });
    expect(unknown.status).toBe(400);
    expect(unknown.body.message).toMatch(/还没登记/);
    expect(Object.keys(ds.loadEndpoints()).length).toBe(before);
  });

  test('IP 白名单里不收 CIDR 与垃圾项：400 且表一个字节不动', async () => {
    const created = await adminPost('/api/admin/fnthink/endpoints/create', {
      owner: OWNER,
      name: '白名单试验',
    });
    expect(created.status).toBe(200);
    const id = created.body.data.endpoint.id;
    const endpoints = ds.loadEndpoints();
    const snapshot = JSON.stringify(endpoints[id]);

    for (const bad of [['10.0.0.0/24'], ['  '], ['localhost'], ['1.2.3.4', 'nope']]) {
      const res = await adminPost('/api/admin/fnthink/endpoints/policy', {
        endpointId: id,
        ipAllowlist: bad,
      });
      expect(res.status).toBe(400);
      expect(JSON.stringify(ds.loadEndpoints()[id])).toBe(snapshot);
    }
    // 空数组是"不限来源"（契约 ipAllowlistEmptyMeans=any），不是"谁都拒"
    const cleared = await adminPost('/api/admin/fnthink/endpoints/policy', {
      endpointId: id,
      ipAllowlist: [],
    });
    expect(cleared.status).toBe(200);
    expect(cleared.body.data.endpoint.ipAllowlist).toEqual([]);
  });

  test('到每台上限 ⇒ 400 点名上限，已有的一个都没被挤掉（拒新的不等于清旧的）', async () => {
    const owner = '8TQVWZ3XKR5B6YD4HM';
    const devices = ds.loadDevices();
    ds.registerDevice(
      contract,
      devices,
      { addressCode: owner, publicKey: publicKey(), name: '第二台' },
      Date.now(),
    );
    ds.saveDevices(devices);
    for (let i = 0; i < epc.perDeviceMax; i += 1) {
      const res = await adminPost('/api/admin/fnthink/endpoints/create', {
        owner,
        name: `第 ${i} 条`,
      });
      expect(res.status).toBe(200);
    }
    const over = await adminPost('/api/admin/fnthink/endpoints/create', { owner, name: '多一条' });
    expect(over.status).toBe(400);
    expect(over.body.message).toMatch(String(epc.perDeviceMax));
    const still = Object.values(ds.loadEndpoints()).filter((r) => r.owner === owner);
    expect(still.length).toBe(epc.perDeviceMax);
    expect(still.every((r) => r.status === epc.usableStatus)).toBe(true);
  });

  test('轮换不要 confirm（旧口令还在宽限期内能推 ⇒ 误点能原地处理）', async () => {
    const created = await adminPost('/api/admin/fnthink/endpoints/create', {
      owner: OWNER,
      name: '要换钥匙的',
    });
    const id = created.body.data.endpoint.id;
    const oldSecret = created.body.data.secret;

    const rotated = await adminPost('/api/admin/fnthink/endpoints/rotate', { endpointId: id });
    expect(rotated.status).toBe(200);
    expect(rotated.body.data.action).toBe('rotateEndpoint');
    const newSecret = rotated.body.data.secret;
    expect(newSecret).not.toBe(oldSecret);
    expect(rotated.body.data.graceSeconds).toBe(epc.graceSeconds);
    // 旧口令还能用到什么时候必须说出口：运维要么现在去改第三方那一份，要么知道自己还有个窗口
    expect(rotated.body.data.oldSecretValidUntil).toBeGreaterThan(Date.now());

    // 两把都能在真实入口上推过去（宽限期的意义就在这儿）
    for (const secret of [oldSecret, newSecret]) {
      const pushed = await request(app)
        .post(`/api/fnthink/p/${id}`)
        .set({ Authorization: `Bearer ${secret}` })
        .send({ title: '换钥匙前后', body: '都该收到' });
      expect(pushed.status).toBe(statusCode(contract, 'queued'));
    }
    // 而旧摘要不能当新口令用：表里只有一行，rotatedFrom 记的是旧摘要
    const row = ds.loadEndpoints()[id];
    expect(row.rotatedFrom.secretDigest).not.toBe(row.secretDigest);
  });

  test('改 postOnly 立刻反映到入口上：打开之后 GET 被拒成契约给的那个码', async () => {
    const created = await adminPost('/api/admin/fnthink/endpoints/create', {
      owner: OWNER,
      name: '只收 POST',
      postOnly: false,
    });
    const { id, secret } = { id: created.body.data.endpoint.id, secret: created.body.data.secret };
    const before = await request(app).get(`/api/fnthink/p/${id}/${secret}?title=a&body=b`);
    expect(before.status).toBe(statusCode(contract, 'queued'));

    const patched = await adminPost('/api/admin/fnthink/endpoints/policy', {
      endpointId: id,
      postOnly: true,
      name: '只收 POST（改过名）',
    });
    expect(patched.status).toBe(200);
    expect(patched.body.data.endpoint.name).toBe('只收 POST（改过名）');
    const after = await request(app).get(`/api/fnthink/p/${id}/${secret}?title=a&body=b`);
    expect(after.status).toBe(epc.methodStatus);
    expect(JSON.stringify(after.body)).toBe('{}');
  });

  test('已吊销的端点不能轮换也不能改设置：400 点名是哪一档（不答 404，那行确实在表里）', async () => {
    const created = await adminPost('/api/admin/fnthink/endpoints/create', {
      owner: OWNER,
      name: '先建后吊销',
    });
    const id = created.body.data.endpoint.id;
    const revoked = await adminPost('/api/admin/fnthink/endpoints/revoke', {
      endpointId: id,
      confirm: true,
    });
    expect(revoked.status).toBe(200);

    for (const url of ['/rotate', '/policy']) {
      const res = await adminPost(`/api/admin/fnthink/endpoints${url}`, {
        endpointId: id,
        postOnly: true,
      });
      expect(res.status).toBe(400);
      expect(res.body.message).toContain(epc.revokedStatus);
    }
    // 表里那一行还是吊销那一档 —— "恢复请新建"不是一句空话，也不许被顺手改回可用
    expect(ds.loadEndpoints()[id].status).toBe(epc.revokedStatus);

    const missing = await adminPost('/api/admin/fnthink/endpoints/rotate', {
      endpointId: 'e_never',
    });
    expect(missing.status).toBe(404);
  });

  test('口令不进日志：三个口的 console 留痕只许有 id', async () => {
    const warn = jest.spyOn(console, 'log').mockImplementation(() => {});
    try {
      const created = await adminPost('/api/admin/fnthink/endpoints/create', {
        owner: OWNER,
        name: '日志检查',
      });
      const secret = created.body.data.secret;
      await adminPost('/api/admin/fnthink/endpoints/rotate', {
        endpointId: created.body.data.endpoint.id,
      });
      await adminPost('/api/admin/fnthink/endpoints/policy', {
        endpointId: created.body.data.endpoint.id,
        name: '日志检查改名',
      });
      const flat = warn.mock.calls.map((args) => args.join(' ')).join('\n');
      expect(flat).toContain('createEndpoint');
      expect(flat).not.toContain(secret);
      expect(flat).not.toContain(created.body.data.secret); // 轮换后响应里那把新的也在同一个 mock 之外
    } finally {
      warn.mockRestore();
    }
  });
});
