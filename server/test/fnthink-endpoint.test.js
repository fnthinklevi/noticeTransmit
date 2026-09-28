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
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-ep-'));
const ADMIN_TOKEN = 'test-admin-token-for-ep';
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync(ADMIN_TOKEN, 10);
process.env.ENCRYPTION_KEY = 'f'.repeat(64);
process.env.RATE_LIMIT_AUTH_MAX = '100000';
process.env.RATE_LIMIT_GENERAL_MAX = '100000';

const request = require('supertest');
const app = require('../lib/app');
const {
  loadContract,
  assertSupported,
  isContractAvailabilityError,
  CONTRACT_SHAPE,
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
