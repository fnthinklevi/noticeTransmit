// #130-A4：异常突增告警（谁快满了、谁已经被拦住）。
//
// 这一片要守的四件事，也就是这个文件为什么是这几组用例：
//  ① **四个数只从契约读** —— A1 那次实现绕开契约改用环境变量，留下两份真值，
//     调 env 的人照着错的日志只会更糟。所以这里断的是**来源**（改契约副本，口径跟着变），
//     不是"解析出的值等于契约里那个数"（A3 刚被这条骗过一次：硬编码同一个数照样通过）。
//  ② **不落盘** —— 公网面上每一次写盘都是"一个请求换一次磁盘写"的放大器（T29-B 同此取舍）。
//     这条由源码守卫钉：这一段里连 `require('fs')` 都不该出现。
//  ③ **有界** —— 主体来自外部输入（地址码、对端 IP），没有上限就是挂在公网上的一段无界内存。
//  ④ **冷却** —— 没有它，告警的输出速率与请求速率成正比 ⇒ 告警自己成为第二种洪水，
//     还会挤满内存环、把真正的异常从最旧端淘汰掉。
//
// ⚠ 契约内容不达标时必须抛**可降级**的 SHAPE（而不是普通 Error）：那决定"只上传 server/ 而
//   契约是上一批"的表现是"协议面降级 503 + 横幅说破原因"，还是"整台服务起不来，连带所有
//   设备的 /api/version 一起挂"。A1 当时写进部署口径的是前者，代码走的却是后者 ——
//   这一片把它对齐了，所以这里两边都验。

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-an-'));
const ADMIN_TOKEN = 'test-admin-token-for-an';
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync(ADMIN_TOKEN, 10);
process.env.ENCRYPTION_KEY = 'c'.repeat(64);
// 认证口的限流默认 5/分钟，这个文件要跑两次管理面请求 + 若干轮闸门，抬到不会干扰的量。
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
const {
  alertsFromContract,
  createAnomalyTracker,
  sharedTracker,
  FACE_KIND,
} = require('../lib/fnthink/anomaly');
const { windowsFor, createFnthinkRateLimiter } = require('../lib/fnthink/ratelimit');
const { createSenderQuota } = require('../lib/fnthink/senderquota');

const contract = assertSupported(loadContract());
const live = alertsFromContract(contract);
const windows = windowsFor(contract);

/// 一份"单测里看得见"的告警配置（真值 0.5/300/200 在几百毫秒的测试里既打不满也验不出淘汰）。
const trackerOf = (patch = {}, log) =>
  createAnomalyTracker({
    alerts: { ...live, ...patch },
    log: log === undefined ? () => {} : log,
  });

const ev = (over = {}) => ({
  subjectKind: 'device',
  subject: 'ADDR1',
  kind: 'message',
  window: 'minute',
  limit: 10,
  count: 1,
  ...over,
});

const fakeRes = () => ({
  headers: {},
  status(code) {
    this.code = code;
    return this;
  },
  set(k, v) {
    this.headers[k] = v;
    return this;
  },
  json(body) {
    this.body = body;
    return this;
  },
});

/// 直接喂中间件（不走 HTTP）：这一层要验的是"三处计数各有没有把事件交出去"，
/// 走 supertest 就得真打满几百发，而打满不是判据。
const hitLimiter = (limiter, { p = '/register', ip = '203.0.113.90' } = {}) => {
  const res = fakeRes();
  let passed = false;
  limiter({ path: p, ip, headers: {} }, res, () => {
    passed = true;
  });
  return { res, passed };
};

describe('突增告警（#130-A4）', () => {
  test('四个数只从契约读：改契约副本，口径就跟着变（断来源而不是断值）', () => {
    const mutated = {
      ...contract,
      alerts: {
        ...contract.alerts,
        nearQuotaRatio: 0.25,
        cooldownSeconds: 45,
        maxActiveAlerts: 17,
      },
    };
    const a = alertsFromContract(mutated);
    expect(a.nearQuotaRatio).toBe(0.25);
    expect(a.cooldownMs).toBe(45 * 1000);
    expect(a.maxActiveAlerts).toBe(17);
    // 反向也钉：缺省那份确实是仓库里这份契约，而不是实现里硬写的三个数
    expect(live.nearQuotaRatio).toBe(contract.alerts.nearQuotaRatio);
    expect(live.cooldownMs).toBe(contract.alerts.cooldownSeconds * 1000);
    expect(live.maxActiveAlerts).toBe(contract.alerts.maxActiveAlerts);
  });

  const broken = [
    ['整段缺失', null],
    ['nearQuotaRatio=1（那只是 denied 的另一种写法）', { nearQuotaRatio: 1 }],
    ['nearQuotaRatio=0', { nearQuotaRatio: 0 }],
    ['cooldownSeconds=0（告警速率与请求速率成正比）', { cooldownSeconds: 0 }],
    ['maxActiveAlerts=0（无界内存挂在公网上）', { maxActiveAlerts: 0 }],
    ['maxActiveAlerts 不是整数', { maxActiveAlerts: 2.5 }],
    ['persistToDisk=true（本仓两处已定过"公网面不写盘"）', { persistToDisk: true }],
    ['persistToDisk 缺省（读不到不等于 false，更不等于"随便"）', { persistToDisk: undefined }],
    ['subjectKinds 空名单', { subjectKinds: [] }],
    ['subjectKinds 少了 device', { subjectKinds: ['ip'] }],
    ['subjectKinds 少了 ip', { subjectKinds: ['device'] }],
  ];
  test.each(broken)('契约 %s ⇒ 抛可降级的 SHAPE，而不是把整台服务打挂', (_label, patch) => {
    let mutated;
    if (patch === null) {
      mutated = { ...contract };
      delete mutated.alerts;
    } else {
      mutated = { ...contract, alerts: { ...contract.alerts, ...patch } };
    }
    let err = null;
    try {
      alertsFromContract(mutated);
    } catch (e) {
      err = e;
    }
    expect(err).not.toBeNull();
    expect(err.code).toBe(CONTRACT_SHAPE);
    expect(isContractAvailabilityError(err)).toBe(true);
  });

  test('跨过契约那条线的那一发才记 near；线以下每一发都不记', () => {
    const t = trackerOf({ nearQuotaRatio: 0.5 });
    expect(t.nearThreshold(10)).toBe(5);
    expect(t.observe(ev({ count: 1 }))).toBeNull();
    expect(t.observe(ev({ count: 4 }))).toBeNull();
    const hit = t.observe(ev({ count: 5 }));
    expect(hit.outcome).toBe('near');
    expect(t.size()).toBe(1);
  });

  test('一次里不各记两条：被拦住就是被拦住（denied 优先）', () => {
    const t = trackerOf({});
    const hit = t.observe(ev({ count: 11, denied: true }));
    expect(hit.outcome).toBe('denied');
    expect(t.size()).toBe(1);
  });

  test('near 与 denied 是两个结论，分开各一条 —— 运维要能分"快满了"与"已经在拒"', () => {
    const t = trackerOf({});
    t.observe(ev({ count: 5 }));
    t.observe(ev({ count: 11, denied: true }));
    const outcomes = t
      .recent()
      .map((a) => a.outcome)
      .sort();
    expect(outcomes).toEqual(['denied', 'near']);
  });

  test('冷却期内同一结论只写一次日志，但次数照加（看不出规模的告警等于没说）', () => {
    const lines = [];
    const t = trackerOf({ cooldownSeconds: 300 }, (line) => lines.push(line));
    t.observe(ev({ count: 5, at: 1_000 }));
    t.observe(ev({ count: 6, at: 2_000 }));
    t.observe(ev({ count: 7, at: 3_000 }));
    expect(lines).toHaveLength(1);
    expect(t.size()).toBe(1);
    expect(t.recent()[0].times).toBe(3);
    expect(t.recent()[0].count).toBe(7);
    expect(t.recent()[0].firstAt).toBe(1_000);
    // 过了冷却 ⇒ 再说一次（不是"一辈子只说一次"）
    t.observe(ev({ count: 8, at: 3_000 + 300 * 1000 }));
    expect(lines).toHaveLength(2);
  });

  test('内存环有界：第 N+1 个主体挤掉最旧那条，而不是跟着请求数无限长', () => {
    const t = trackerOf({ maxActiveAlerts: 3 });
    for (const s of ['A1', 'A2', 'A3']) t.observe(ev({ subject: s, count: 5 }));
    expect(t.size()).toBe(3);
    t.observe(ev({ subject: 'A4', count: 5 }));
    expect(t.size()).toBe(3);
    const subjects = t.recent().map((a) => a.subject);
    expect(subjects).toContain('A4');
    expect(subjects).not.toContain('A1');
  });

  test('没有上限的窗口不记：那种档是"故意不设"，不是"永远不会到"', () => {
    const t = trackerOf({});
    expect(t.observe(ev({ count: 999_999, limit: null }))).toBeNull();
    expect(t.observe(ev({ count: 5, limit: Number.POSITIVE_INFINITY }))).toBeNull();
    expect(t.observe(ev({ count: 5, limit: 0 }))).toBeNull();
    expect(t.size()).toBe(0);
  });

  test('主体种类不在契约名单 ⇒ 抛，而不是"这条告警安静地没了"', () => {
    const t = trackerOf({});
    // 契约里现在只有 device/ip；endpoint 要等 W3c 的端点流量入口起来才同时加进名单。
    expect(() => t.observe(ev({ subjectKind: 'endpoint', count: 5 }))).toThrow(/subjectKinds/);
  });

  test('不同 IP、不同端点种类、不同窗口各算一条（否则"谁在被打"看不出来）', () => {
    const t = trackerOf({});
    t.observe(
      ev({ subjectKind: 'ip', subject: '10.0.0.1', kind: 'register', window: 'minute', count: 5 }),
    );
    t.observe(
      ev({ subjectKind: 'ip', subject: '10.0.0.2', kind: 'register', window: 'minute', count: 5 }),
    );
    t.observe(
      ev({ subjectKind: 'ip', subject: '10.0.0.1', kind: 'register', window: 'day', count: 5 }),
    );
    t.observe(
      ev({ subjectKind: 'ip', subject: '10.0.0.1', kind: 'poll', window: 'minute', count: 5 }),
    );
    expect(t.size()).toBe(4);
  });
});

describe('告警与闸门读同一个计数器（接线）', () => {
  test('按设备那一层把 near 与 denied 都交出去，主键是设备地址而不是 IP', () => {
    const seen = [];
    const quota = createSenderQuota(
      { ...windows, senderWindows: new Map([['message', { perMinute: 4, perDay: null }]]) },
      { observe: (e) => seen.push(e) },
    );
    for (let i = 0; i < 4; i += 1) expect(quota.charge('message', 'ADDR1', 1_000_000)).toBeNull();
    const over = quota.charge('message', 'ADDR1', 1_000_000);
    expect(over).not.toBeNull();
    expect(over.window).toBe('minute');
    expect(seen.every((e) => e.subjectKind === 'device')).toBe(true);
    expect(seen.every((e) => e.subject === 'ADDR1')).toBe(true);
    expect(seen.every((e) => e.kind === 'message' && e.window === 'minute')).toBe(true);
    expect(seen[0].denied).toBe(false);
    expect(seen[seen.length - 1].denied).toBe(true);
    // 线是 ceil(4 × 0.5) = 2 ⇒ 第 2 发起就该有 near 事件
    expect(seen.filter((e) => e.count >= 2 && !e.denied).length).toBeGreaterThan(0);
  });

  test('按设备的日档同样接线（只有分钟档有告警 = 慢速跑飞看不见）', () => {
    const seen = [];
    const quota = createSenderQuota(
      { ...windows, senderWindows: new Map([['message', { perMinute: 100, perDay: 2 }]]) },
      { observe: (e) => seen.push(e) },
    );
    for (let i = 0; i < 3; i += 1) quota.charge('message', 'ADDR9', 1_000_000);
    expect(seen.some((e) => e.window === 'day')).toBe(true);
    expect(seen.some((e) => e.window === 'day' && e.denied)).toBe(true);
  });

  const ipWindows = () => ({
    controlKinds: new Set(['register']),
    cadenceKinds: new Set(['poll']),
    senderOnlyKinds: new Set(['message']),
    // 日档故意比分钟档紧：否则分钟档先拒、后面那行 `return deny(...)` 让日档永远轮不到被观察，
    // 这条用例就会"看起来测了日档，其实只测了分钟档"。
    controlWindow: { perMinute: 3, perDay: 2 },
    cadenceWindow: { perMinute: 2 },
    pollPerMinute: 2,
    senderWindows: new Map([
      ['poll', { perMinute: 2, perDay: null }],
      ['message', { perMinute: 10, perDay: 20 }],
    ]),
  });

  test('层 1（整个面按 IP 的洪水闸）被拒时记一条，且 kind 明确是 face', () => {
    const seen = [];
    const limiter = createFnthinkRateLimiter(2, ipWindows(), { observe: (e) => seen.push(e) });
    hitLimiter(limiter, { p: '/message' });
    hitLimiter(limiter, { p: '/message' });
    const third = hitLimiter(limiter, { p: '/message' });
    expect(third.passed).toBe(false);
    expect(seen.every((e) => e.subjectKind === 'ip')).toBe(true);
    expect(seen.every((e) => e.subject === '203.0.113.90')).toBe(true);
    const face = seen.filter((e) => e.kind === FACE_KIND);
    expect(face.length).toBe(3);
    expect(face[face.length - 1].denied).toBe(true);
  });

  test('未认证端点档的分钟与日两处都接线，并把"这台 IP"带进主体', () => {
    const seen = [];
    const limiter = createFnthinkRateLimiter(1000, ipWindows(), { observe: (e) => seen.push(e) });
    for (let i = 0; i < 4; i += 1) hitLimiter(limiter, { p: '/register' });
    const minute = seen.filter((e) => e.kind === 'register' && e.window === 'minute');
    const day = seen.filter((e) => e.kind === 'register' && e.window === 'day');
    expect(minute.length).toBeGreaterThan(0);
    expect(minute.some((e) => e.denied)).toBe(true);
    expect(day.length).toBeGreaterThan(0);
    expect(day.some((e) => e.denied)).toBe(true);
  });

  test('按设备计额的那一类不在 IP 层记账（否则又回到"一个出口共用一份额度"）', () => {
    const seen = [];
    const limiter = createFnthinkRateLimiter(1000, ipWindows(), { observe: (e) => seen.push(e) });
    for (let i = 0; i < 5; i += 1) hitLimiter(limiter, { p: '/message' });
    expect(seen.filter((e) => e.kind === 'message')).toHaveLength(0);
    expect(seen.every((e) => e.kind === FACE_KIND)).toBe(true);
  });
});

describe('告警口的边界（管理面）', () => {
  test('未登录读不到：这份列表本身是一台"哪些地址码活跃"的探针', async () => {
    const res = await request(app).get('/api/admin/fnthink/alerts');
    expect(res.status).toBe(401);
    expect(res.body.code).not.toBe(0);
  });

  test('登录后能读，且每条只有白名单那十个键（不许顺手把正文带出去）', async () => {
    const login = await request(app).post('/api/admin/login').send({ token: ADMIN_TOKEN });
    expect(login.status).toBe(200);
    const sessionId = login.body.sessionId;
    sharedTracker().observe({
      subjectKind: 'device',
      subject: 'ADDR-PUBLIC-TEST',
      kind: 'message',
      window: 'minute',
      count: 9,
      limit: 10,
      denied: false,
    });
    const res = await request(app).get('/api/admin/fnthink/alerts').set('x-session-id', sessionId);
    expect(res.status).toBe(200);
    expect(res.body.code).toBe(0);
    const data = res.body.data;
    expect(data.persisted).toBe(false);
    expect(data.nearQuotaRatio).toBe(contract.alerts.nearQuotaRatio);
    expect(data.cooldownSeconds).toBe(contract.alerts.cooldownSeconds);
    expect(data.maxActiveAlerts).toBe(contract.alerts.maxActiveAlerts);
    const hit = data.alerts.find((a) => a.subject === 'ADDR-PUBLIC-TEST');
    expect(hit).toBeTruthy();
    expect(Object.keys(hit).sort()).toEqual(
      [
        'count',
        'firstAt',
        'kind',
        'lastAt',
        'limit',
        'outcome',
        'subject',
        'subjectKind',
        'times',
        'window',
      ].sort(),
    );
    // 告警里绝不允许出现正文/标题/签名/口令这类键（哪怕值恰好是空）
    const flat = JSON.stringify(data.alerts);
    for (const forbidden of ['body', 'title', 'signature', 'pairingCode', 'secret']) {
      expect(flat).not.toContain(forbidden);
    }
  });
});

describe('源码守卫（形状不靠自觉）', () => {
  const readFn = (file, from, to) => {
    const src = fs.readFileSync(path.join(__dirname, '../lib/fnthink', file), 'utf8');
    const start = src.indexOf(from);
    const end = src.indexOf(to);
    expect(start).toBeGreaterThan(-1);
    expect(end).toBeGreaterThan(start);
    return src.slice(start, end);
  };

  test('告警这一段不碰文件系统：不落盘是契约里的取舍，不是"暂时没写"', () => {
    const src = fs.readFileSync(path.join(__dirname, '../lib/fnthink/anomaly.js'), 'utf8');
    expect(src).not.toMatch(/require\('fs'\)/);
    expect(src).not.toMatch(/writeFile|appendFile|createWriteStream/);
  });

  test('契约取数处只许抛 shapeError：否则"旧契约配新代码"会崩掉整台服务而不是降级那一段', () => {
    const bodies = [
      ['anomaly.js', 'function alertsFromContract', 'function createAnomalyTracker'],
      ['ratelimit.js', 'function windowsFor', 'const contractWindows'],
      ['bodylimit.js', 'function bodyMaxBytes', 'function createFnthinkBodyLimit'],
    ];
    for (const [file, from, to] of bodies) {
      const body = readFn(file, from, to);
      expect(body).not.toContain('throw new Error');
      expect(body).toContain('shapeError');
    }
  });

  test('实现里没有第二份告警数字（阈值·冷却·环上限只能从契约来）', () => {
    const src = fs.readFileSync(path.join(__dirname, '../lib/fnthink/anomaly.js'), 'utf8');
    expect(src).toContain('alertsFromContract');
    expect(src).not.toMatch(/\b0\.5\b/);
    expect(src).not.toMatch(/\b300\b/);
    expect(src).not.toMatch(/maxActiveAlerts\s*={1,2}\s*\d/);
    expect(src).not.toMatch(/nearQuotaRatio\s*[:=]\s*0?\.\d/);
  });

  test('两处闸门都把计数交给同一个告警环（不是各建一份）', () => {
    const quota = fs.readFileSync(path.join(__dirname, '../lib/fnthink/senderquota.js'), 'utf8');
    const limit = fs.readFileSync(path.join(__dirname, '../lib/fnthink/ratelimit.js'), 'utf8');
    for (const src of [quota, limit]) {
      expect(src).toContain("require('./anomaly')");
      expect(src).toContain('sharedTracker()');
    }
    // 告警读取口看的必须就是那两个模块写进去的同一份单例
    const route = fs.readFileSync(path.join(__dirname, '../lib/routes/alerts.js'), 'utf8');
    expect(route).toContain('sharedTracker()');
  });

  test('告警只读：管理面这个口不许顺手带上任何写操作（处置归 A5，两件事不混在一个口）', () => {
    const route = fs.readFileSync(path.join(__dirname, '../lib/routes/alerts.js'), 'utf8');
    // ⚠ 锚点必须换行感知：这一条最初写成单行 substring（`router.get('/fnthink/alerts', authMiddleware`），
    //   prettier 把参数拆成多行后它就红了 —— 红的内容是"看起来没挂鉴权"，而鉴权其实挂得好好的。
    //   守卫断的是契约（这一条路由 GET 且要鉴权），不是某一版排版的行形状。
    expect(route).toMatch(/router\.get\(\s*['"]\/fnthink\/alerts['"],\s*authMiddleware/);
    expect(route).not.toMatch(/router\.(post|put|patch|delete)\(/);
  });
});
