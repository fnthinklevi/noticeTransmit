// #130-A1：限流"量谁"这件事必须写在契约上，并由两端各读同一份。
//
// 这一片要守的三件事，按代价排：
//  ① 控制类额度不许套到轮询上 —— 常态 20 秒一次就是 4320 次/天，照字面套 500/天 是"上线即
//     把所有设备卡死"；而 6/分 也比提频的 12/分 紧，等于把正常提醒延迟判成攻击。
//  ② 反过来，轮询侧的推导额度必须**比控制类松**，否则最紧的那把尺子是从设备身上摘给洪水的。
//  ③ 新加一个端点却忘了登记 ⇒ 不许静默不受专项限流：按最紧的一档拦下 + 留痕点名。
// 还有第④件是守卫自己的形状：挂载清单与契约名单必须对得上（见最后那条用例）——
// 名单与事实分离的那一刻起，它就只是一份注释。
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-scope-'));
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-scope', 10);
process.env.ENCRYPTION_KEY = 'a'.repeat(64);
process.env.TRUST_PROXY = '1';
// 面闸门抬到打不满：本文件只测"按端点的那一层"，两层混在一起就分不出是谁拦的
process.env.RATE_LIMIT_FNTHINK_MAX = '100000';

const request = require('supertest');
const app = require('../lib/app');
const { statusCode, loadContract, assertSupported } = require('../lib/fnthink/contract');
const {
  createFnthinkRateLimiter,
  windowsFor,
  endpointKindOf,
} = require('../lib/fnthink/ratelimit');

const contract = assertSupported(loadContract());
const RATE_LIMITED = statusCode(contract, 'rateLimited');
const FORBIDDEN = statusCode(contract, 'forbidden');
const windows = windowsFor(contract);

const IP = (n) => `203.0.113.${n}`;
const post = (p, from) =>
  request(app).post(`/api/fnthink/${p}`).set('X-Forwarded-For', from).send({});

describe('fnthink 限流的适用范围（#130-A1）', () => {
  test('身份未证明的那一档（register）按契约额度拦，拦的是 429 + Retry-After + 空 body', async () => {
    const from = IP(31);
    const per = windows.controlWindow.perMinute;
    for (let i = 0; i < per; i++) {
      // 每一发都因签名不过而 403 —— 但都被记了数：计数比密码学便宜
      expect((await post('register', from)).status).toBe(FORBIDDEN);
    }
    const over = await post('register', from);
    expect(over.status).toBe(RATE_LIMITED);
    expect(over.body).toEqual({});
    expect(Number(over.headers['retry-after'])).toBeGreaterThan(0);
  });

  test('轮询侧走推导额度：正常提频（12 次/分）不许被任何一档拦下', async () => {
    const from = IP(32);
    const burst = Math.ceil(60 / contract.presence.burstWhenPending.intervalSeconds);
    // 推导额度必须**盖得住**提频节奏，否则"用户刚点开一条通知"就被判成攻击
    expect(burst).toBeLessThanOrEqual(windows.pollPerMinute);
    // 而按 IP 的那一档只能更宽不能更紧 —— 反代之后一台路由器后面就是全部设备
    expect(windows.controlWindow.perMinute).toBeGreaterThanOrEqual(windows.pollPerMinute);
    for (let i = 0; i < burst; i++) {
      const res = await post('poll', from);
      expect(res.status).not.toBe(RATE_LIMITED);
    }
  });

  test('日档只对控制类存在：轮询没有日额度（4320 次/天就是设计值）', async () => {
    // 直接把窗口改小来驱动中间件本体：契约里的 perDay 是 500，用它意味着单测要发 501 个请求，
    // 而"要测的是有没有这一档"，不是"500 这个数字大不大"。
    const win = windowsFor(contract);
    win.controlWindow = { perMinute: 100, perDay: 3 };
    const limiter = createFnthinkRateLimiter(100000, win);
    const run = (p) =>
      new Promise((resolve) => {
        limiter(
          { path: p, headers: { 'x-forwarded-for': '198.51.100.88' } },
          {
            set() {
              return this;
            },
            status(code) {
              this.code = code;
              return this;
            },
            json(body) {
              resolve({ status: this.code, body });
            },
          },
          () => resolve({ status: 0 }),
        );
      });
    const day = [];
    for (let i = 0; i < 5; i++) day.push(await run('/api/fnthink/register'));
    expect(day.filter((h) => h.status === RATE_LIMITED).length).toBe(2);
    const polls = [];
    for (let i = 0; i < 5; i++) polls.push(await run('/api/fnthink/poll'));
    expect(polls.every((h) => h.status === 0)).toBe(true);
  });

  test('/message 不受专项档（按发送方计是 A2 的活；现在卡它会连坐整栋楼）', async () => {
    const from = IP(34);
    const per = windows.controlWindow.perMinute;
    for (let i = 0; i < per + 3; i++) {
      const res = await post('message', from);
      expect(res.status).not.toBe(RATE_LIMITED);
    }
  });

  test('未登记的端点按最紧的一档拦下，并留痕点名是谁（不许静默不限流）', async () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    try {
      // 造一份"名单里没这个种类"的窗口：limit 设成 2，一眼看得出是谁在拦
      const win = windowsFor(contract);
      win.controlKinds = new Set(['register']);
      win.cadenceKinds = new Set(['poll']);
      win.senderOnlyKinds = new Set();
      win.controlWindow = { perMinute: 2, perDay: 3 };
      const limiter = createFnthinkRateLimiter(100000, win);
      const hits = [];
      const run = (p) =>
        new Promise((resolve) => {
          limiter(
            { path: p, headers: { 'x-forwarded-for': '198.51.100.77' } },
            {
              set() {
                return this;
              },
              status(code) {
                this.code = code;
                return this;
              },
              json(body) {
                resolve({ status: this.code, body });
              },
            },
            () => resolve({ status: 0 }),
          );
        });
      for (let i = 0; i < 4; i++) hits.push(await run('/api/fnthink/brand-new-thing'));
      expect(hits.filter((h) => h.status === RATE_LIMITED).length).toBeGreaterThan(0);
      expect(warn.mock.calls.flat().join('\n')).toContain('brandNewThing');
    } finally {
      warn.mockRestore();
    }
  });

  test('推导本身不许"取不到数就当不限"：四种坏法都要抛', () => {
    const clone = () => JSON.parse(JSON.stringify(contract));
    expect(() =>
      windowsFor({ ...clone(), limits: { ...clone().limits, perEndpoint: [] } }),
    ).toThrow(/perEndpoint 不能为空/);
    const overlap = clone();
    overlap.limits.perEndpoint = ['poll'];
    expect(() => windowsFor(overlap)).toThrow(/重叠/);
    const missing = clone();
    delete missing.limits.pollBurstSlack;
    expect(() => windowsFor(missing)).toThrow(/pollBurstSlack/);
    const loose = clone();
    loose.limits.unauthenticatedPerMinute = 6;
    expect(() => windowsFor(loose)).toThrow(/严于轮询推导额度/);
  });

  test('挂载清单与契约名单必须对得上（漏登记要红，别等上线）', () => {
    const mounted = app.get('fnthinkEndpoints') || [];
    expect(mounted.length).toBeGreaterThan(0); // 空清单 = 协议面没起来，这条守卫也就成了摆设
    const listed = new Set([
      ...windows.controlKinds,
      ...windows.cadenceKinds,
      ...windows.senderOnlyKinds,
    ]);
    // 端点形态是**第四类**，故意不进上面那三份名单：它既不是"身份还没证明"（register 那一档按 IP
    // 量），也没有"设备地址"可当主键（按设备量），额度写在 endpoint.ingress.quota 里、由收单
    // 在口令验完之后按**端点**计。把它塞进 perEndpoint 就变成"按 IP 给一把口令计额度" ——
    // 一个 NAS 出口后面挂三个端点会互相挤，那正是 A1 那 7 条配对用例红在 429 上的形状。
    const fourthKind = endpointKindOf('/p/e_1/s_1');
    expect(listed.has(fourthKind)).toBe(false); // 第四类确实是名单之外，不是被顺手列进去了
    const missing = mounted.filter((entry) => {
      const kind = endpointKindOf(entry);
      return kind !== fourthKind && !listed.has(kind);
    });
    expect(missing).toEqual([]);
    // 放过第四类不等于放过"任何带 p 段的路由"：这几条路径必须逐条对得上契约声明的形状。
    // 否则将来在 /p/ 底下加一条没登记的形状（比如口令进 query 的那种），这里会一起放行。
    const shapes = new Set(
      mounted
        .filter((entry) => endpointKindOf(entry) === fourthKind)
        .map((entry) => entry.replace(/^[A-Z,]+ /, '')),
    );
    expect([...shapes].sort()).toEqual(
      [
        contract.endpoint.ingress.pathPattern,
        contract.endpoint.ingress.postBearerPath,
        // T106 片①b：端点档的干跑也在第四类之内（它同样是一把口令鉴权、没有设备地址可当主键），
        // 而它的额度**不花** ingress.quota —— 不花的原因写在契约 endpoint.probe 那句 _why 里。
        contract.endpoint.probe.bearerPath,
      ].sort(),
    );
  });

  test('名单与 verifyAgainst 必须一致：能证明是谁的，不许按 IP 计', () => {
    // 数据驱动，而不是在这里再抄一份"哪些端点该按 IP"的名单 —— 抄的那一份从下一次改动起就会漂。
    for (const kind of contract.limits.perEndpoint) {
      expect(contract.clientEvents[kind].verifyAgainst).toBe('presented-public-key');
    }
    for (const kind of contract.limits.perSenderOnly) {
      if (!contract.clientEvents[kind]) continue; // /message 不是 clientEvents 里的事件
      expect(contract.clientEvents[kind].verifyAgainst).toBe('device-table-public-key');
    }
    // 本片改掉的那个真实错误：配对三步曾被列进按 IP 的那一档 ⇒ NAT 后面几台设备共用一份额度
    // （撤销那一发同属这一类：一次划名单被当成攻击而拦住，用户看到的是"点了没反应"；
    //   自建端点也一样 —— 一个人给自家 NAS、群晖、监控各建一把入口，那是三次正常操作；
    //   翻自己那几把入口更一样 —— 打开推送页就是一次读，把它按 IP 计，两台设备同屋就会有一台看不到列表；
    //   关掉一把入口是同一族的动作 —— 给三块屏各关一把，会被数成"一分钟三次攻击"，而那三次全是正常操作）
    for (const kind of [
      'pairArm',
      'pair',
      'pairConfirm',
      'pairRevoke',
      'endpointCreate',
      'endpointList',
      'endpointRevoke',
      'endpointRotate',
    ]) {
      expect(contract.limits.perEndpoint).not.toContain(kind);
    }
  });

  test('启动横幅必须逐条说清"这个端点受哪一档"，不许再打一句笼统的每 IP', () => {
    const { describeKind } = require('../lib/fnthink/ratelimit');
    const serverSrc = fs.readFileSync(path.join(__dirname, '../server.js'), 'utf8');
    // 身份未证明的那一类：按 IP（这是唯一只能按 IP 计的一档）
    expect(describeKind('register')).toContain('按 IP');
    expect(describeKind('register')).toContain(String(contract.limits.unauthenticatedPerMinute));
    // 已证明身份的两类：按设备地址，主键与数字来源都要写在同一行里（#130-A2）
    expect(describeKind('poll')).toContain('按设备地址');
    expect(describeKind('poll')).toContain(String(windows.pollPerMinute));
    expect(describeKind('poll')).toContain('presence');
    expect(describeKind('poll')).toContain('无日档');
    expect(describeKind('message')).toContain('按设备地址');
    expect(describeKind('message')).toContain(String(contract.limits.perSenderPerMinute));
    expect(describeKind('message')).toContain(String(contract.limits.perSenderPerDay));
    // 第四类（端点形态）也要说清主键与数字出处，不许落在"未登记"那一支：
    // 运维照着"未登记"去抬 RATE_LIMIT_FNTHINK_MAX，抬的是洪水闸那一层，而真正管着这把口令的
    // 是端点配额 —— 两头都对不上号，比不打印更糟。
    const endpointLine = describeKind(endpointKindOf('/p/e_1/s_1'));
    expect(endpointLine).toContain('按端点');
    expect(endpointLine).toContain('口令验完');
    expect(endpointLine).toContain(String(contract.endpoint.ingress.quota.perMinute));
    expect(endpointLine).toContain(String(contract.endpoint.ingress.quota.perDay));
    expect(endpointLine).not.toContain('未登记');
    expect(describeKind('brandNewThing')).toContain('未登记');
    // 旧的形状：一行里给所有端点打同一个"每 IP N/分钟" ⇒ 数出来了就红，逼改的人看见为什么
    expect(serverSrc).not.toMatch(/限流 \$\{store\.RATE_LIMIT_FNTHINK_MAX\}\/分钟\/每 IP/);
    expect(serverSrc).toContain('describeKind');
  });

  test('源码守卫：额度数字不许在实现里再抄一份字面量', () => {
    const src = fs.readFileSync(path.join(__dirname, '../lib/fnthink/ratelimit.js'), 'utf8');
    // 只许出现"从契约取"的形状；写死 6 / 500 / 14 这类数就是第二份真值
    expect(src).not.toMatch(/perMinute\s*[:=]\s*\d+/);
    expect(src).not.toMatch(/perDay\s*[:=]\s*\d+/);
    expect(src).toContain("['limits', 'unauthenticatedPerMinute']");
    expect(src).toContain("['presence', 'burstWhenPending', 'intervalSeconds']");
  });
});
