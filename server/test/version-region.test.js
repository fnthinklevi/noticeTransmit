/**
 * T96 GET /api/version/region —— 地理回读的真实请求测试。
 *
 * 这条接口只有一个用途：让客户端在第一次进入时知道"边缘看到的我属于哪个国家"，
 * 好在两台更新服务器之间挑一台。所以它的全部风险都不在"算得对不对"（它不算），而在：
 *  ① 拿不到地理时**必须回 null**，不许编一个 —— 编出来的国家码会让客户端稳定连错那台，
 *     而界面上一切正常（这一条与"没测过"在客户端长得一样，事后查不出来）；
 *  ② 响应**可被共享缓存**就是泄漏：第一个用户的国家码发给后面的人；
 *  ③ 它是地理查询 ⇒ 顺手把 IP / 国家码写进日志或回显给客户端，就把一件小事变成了隐私面。
 *
 * ⚠ 本文件断的是**契约**（null 而不是猜、no-store、豁免来自前缀、服务端不做裁决），
 *   不是措辞：`source` 的字面值客户端只用于"这次按什么判的"那句话，改判据不必动这里。
 *
 * 运行方式：在 server/ 目录下 `node node_modules/jest/bin/jest.js --runInBand test/version-region.test.js`
 */

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-version-region-'));
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-region', 10);
process.env.ENCRYPTION_KEY = 'a'.repeat(64);
process.env.RATE_LIMIT_GENERAL_MAX = '100000';
process.env.RATE_LIMIT_AUTH_MAX = '100000';

const request = require('supertest');
const app = require('../lib/app');
const store = require('../lib/store');

const GEO_ENVS = ['FNTHINK_GEO_HEADER', 'FNTHINK_EDGE', 'FNTHINK_GEO_ECHO'];
const savedGeoEnv = {};

beforeEach(() => {
  for (const key of GEO_ENVS) {
    savedGeoEnv[key] = process.env[key];
    delete process.env[key];
  }
});
afterEach(() => {
  for (const key of GEO_ENVS) {
    if (savedGeoEnv[key] === undefined) delete process.env[key];
    else process.env[key] = savedGeoEnv[key];
  }
});

function get(headers = {}) {
  let req = request(app).get('/api/version/region');
  for (const [k, v] of Object.entries(headers)) req = req.set(k, v);
  return req;
}

// 路由**注册时写的那条路径**从源码里取，不在这里抄第二份。
// ⚠ 为什么：豁免来自 `/api/version` 这个**前缀**，而下面那两条断言若硬编码字面路径，
//   把路由改名成 /api/geo/region 时它们照绿 —— 于是"豁免面悄悄变小"这件事没人喊。
//   取的是形状（router.get 的字符串实参），不是某一行。
function declaredRegionPath() {
  const src = fs.readFileSync(path.join(__dirname, '..', 'lib', 'routes', 'version.js'), 'utf8');
  const paths = [...src.matchAll(/router\.get\('([^']+)'/g)].map((m) => m[1]);
  return paths.find((p) => p.endsWith('/region'));
}

describe('cf-ipcountry 在场（Cloudflare 那台）', () => {
  test('国家码原样上报，来源与边缘都点名', async () => {
    const res = await get({ 'cf-ipcountry': 'CN', 'cf-ray': 'abc-123-LHR' });
    expect(res.status).toBe(200);
    expect(res.body.code).toBe(0);
    expect(res.body.data).toMatchObject({
      country: 'CN',
      source: 'cf-ipcountry',
      edge: 'cloudflare',
    });
  });

  test('小写与前后空格归一：cn / " US " 都读成 CN / US', async () => {
    expect((await get({ 'cf-ipcountry': 'cn' })).body.data.country).toBe('CN');
    expect((await get({ 'cf-ipcountry': ' US ' })).body.data.country).toBe('US');
  });

  test('XX / T1 这两个"边缘自己也说不清"的值照原样回，不在服务端过滤', async () => {
    // 形状合法 ⇒ 是事实，不是错误。"这两种都不能当结论"属于客户端判据：
    // 在这里把它们变成 null 的话，界面上"探测到了但判不出来"与"什么都没探测到"就同一形状了。
    for (const code of ['XX', 'T1']) {
      const data = (await get({ 'cf-ipcountry': code })).body.data;
      expect(data.country).toBe(code);
      expect(data.source).toBe('cf-ipcountry');
    }
  });

  test('值是畸形形状 ⇒ country 为 null，并区分"头到了但不成形状"', async () => {
    for (const bad of ['C', 'CHN', 'C N', '1']) {
      const data = (await get({ 'cf-ipcountry': bad })).body.data;
      expect(data.country).toBeNull();
      // source 的不变量：它只在真的给出结论时才有值
      expect(data.source).toBe('none');
      expect(data.rawUnusable).toBe(true);
    }
  });

  test('cf-* 中只有 cf-ipcountry 也算 cloudflare（不要求 cf-ray 一起在场）', async () => {
    const data = (await get({ 'cf-ipcountry': 'JP' })).body.data;
    expect(data.edge).toBe('cloudflare');
    expect(data.country).toBe('JP');
  });
});

describe('没有地理头（腾讯 EdgeOne 那台今天的状态）', () => {
  test('country 回 null 而不是猜一个 —— 这是本端点最重要的一条', async () => {
    const res = await get();
    expect(res.status).toBe(200);
    expect(res.body.data.country).toBeNull();
    expect(res.body.data.source).toBe('none');
    // 边缘标识也不许猜："另一个域名前面一定是 EdgeOne"正是本端点要测出来的事
    expect(res.body.data.edge).toBe('unknown');
    // 没有结论不等于出错：不许把降级写成 5xx 或 code≠0
    expect(res.body.code).toBe(0);
  });

  test('cf-* 全不在场时，显式标注的边缘值生效（FNTHINK_EDGE）', async () => {
    process.env.FNTHINK_EDGE = 'edgeone';
    const data = (await get()).body.data;
    expect(data.edge).toBe('edgeone');
    expect(data.country).toBeNull();
  });

  test('cf 在场时优先于标注：自证压过声明', async () => {
    process.env.FNTHINK_EDGE = 'edgeone';
    const data = (await get({ 'cf-ipcountry': 'DE' })).body.data;
    expect(data.edge).toBe('cloudflare');
  });

  test('边缘标注非法（含空格/过长）当作没配，回 unknown', async () => {
    for (const bad of ['Tencent EdgeOne', 'x'.repeat(33)]) {
      process.env.FNTHINK_EDGE = bad;
      expect((await get()).body.data.edge).toBe('unknown');
    }
  });
});

describe('自定义地理头 FNTHINK_GEO_HEADER（部署后实测 EdgeOne 用）', () => {
  test('头到了 ⇒ source 点名 geo-header，并回显配的是哪个头', async () => {
    process.env.FNTHINK_GEO_HEADER = 'x-geo-country';
    const data = (await get({ 'x-geo-country': 'SG' })).body.data;
    expect(data.country).toBe('SG');
    expect(data.source).toBe('geo-header');
    expect(data.geoHeader).toBe('x-geo-country');
    expect(data.geoHeaderMissing).toBeUndefined();
  });

  test('配了头但请求里没有 ⇒ geoHeaderMissing，country 仍为 null', async () => {
    // 这一条把"我配错了头名"与"这台根本没有地理头"分开：否则部署后只能看到 null，
    // 而 null 有两种成因，选错那一种就会白改一轮配置。
    process.env.FNTHINK_GEO_HEADER = 'x-geo-country';
    const data = (await get()).body.data;
    expect(data.geoHeaderMissing).toBe(true);
    expect(data.geoHeader).toBe('x-geo-country');
    expect(data.country).toBeNull();
    expect(data.source).toBe('none');
  });

  test('cf 优先于自定义头（两台同时给了结论时，用可自证的那一个）', async () => {
    process.env.FNTHINK_GEO_HEADER = 'x-geo-country';
    const data = (await get({ 'cf-ipcountry': 'CN', 'x-geo-country': 'US' })).body.data;
    expect(data.source).toBe('cf-ipcountry');
    expect(data.country).toBe('CN');
  });

  test('头名非法（含空格/冒号）当作没配：不进 Vary、也不回显', async () => {
    // 非法头名若照抄进 Vary，就是把运维手误变成响应头注入面。
    for (const bad of ['x geo country', 'x-geo-country: hack', '']) {
      process.env.FNTHINK_GEO_HEADER = bad;
      const res = await get();
      expect(res.body.data.geoHeader).toBeUndefined();
      expect(res.headers.vary).toBe('cf-ipcountry');
    }
  });
});

describe('缓存：这条响应每个用户都不一样', () => {
  test('Cache-Control 必须含 no-store（no-cache 仍允许存储，会把上一个个用户的国家码发给下一个人）', async () => {
    const res = await get({ 'cf-ipcountry': 'CN' });
    expect(res.headers['cache-control']).toBe('no-store');
  });

  test('Vary 按地理头变；配了自定义头时那一个也在里面', async () => {
    expect((await get()).headers.vary).toBe('cf-ipcountry');
    process.env.FNTHINK_GEO_HEADER = 'x-geo-country';
    expect((await get()).headers.vary).toBe('cf-ipcountry, x-geo-country');
  });
});

describe('隐私面：不回显 IP，也不带任何地理记录字段', () => {
  test('响应体里没有客户端 IP（v4 / v6 回环两种形态都不许出现）', async () => {
    const res = await get({ 'cf-ipcountry': 'CN' });
    const text = JSON.stringify(res.body);
    expect(text).not.toMatch(/127\.0\.0\.1/);
    expect(text).not.toMatch(/::ffff:/i);
    expect(text).not.toMatch(/"ip"/i);
  });

  test('Echo 打开时只列头名、不带头值', async () => {
    // FNTHINK_GEO_ECHO 是给"部署后跑一次 curl 看 EdgeOne 到底带了什么头"用的临时仪器；
    // 它必须只暴露名字。把值一起吐出来就等于把这条公开接口变成请求头抄写机。
    process.env.FNTHINK_GEO_ECHO = '1';
    const res = await get({ 'cf-ipcountry': 'CN', 'x-secret-probe': 'must-not-appear' });
    expect(res.body.data.headerNames).toContain('cf-ipcountry');
    expect(res.body.data.headerNames).toContain('x-secret-probe');
    expect(JSON.stringify(res.body)).not.toMatch(/must-not-appear/);
    for (const name of res.body.data.headerNames) {
      expect(name).toBe(String(name).toLowerCase());
    }
  });

  test('默认（未开 Echo）不回 headerNames', async () => {
    const data = (await get({ 'cf-ipcountry': 'CN' })).body.data;
    expect(data.headerNames).toBeUndefined();
  });

  test('一次地理查询不在 stdout/stderr 留下国家码或客户端 IP', async () => {
    // 这一条钉的是"顺手加一行日志"：地理查询一旦进了日志，日志就成了第二份地理记录
    // （而日志的保留期与脱敏口径是另一套约束，T89 量的就是这类差异）。
    const spoken = [];
    const spies = ['log', 'warn', 'error'].map((level) => {
      const original = console[level];
      console[level] = (...args) => spoken.push(args.map(String).join(' '));
      return { level, original };
    });
    try {
      await get({ 'cf-ipcountry': 'FJ' });
    } finally {
      for (const { level, original } of spies) console[level] = original;
    }
    const text = spoken.join('\n');
    expect(text).not.toMatch(/FJ/);
    expect(text).not.toMatch(/127\.0\.0\.1|::ffff:/i);
  });
});

describe('挂载与豁免：路径改名会悄悄把它关进 IP 封锁', () => {
  test('注册的那条路径落在豁免前缀内（NAT 出口下一次误封会殃及全部设备的选路）', () => {
    const declared = declaredRegionPath();
    // 尺自己也可能读到空 ⇒ 先坐实"确实有一条以 /region 结尾的路由"，再判豁免
    expect(typeof declared).toBe('string');
    expect(store.ipBlockExempt(declared)).toBe(true);
  });

  test('它没有专职限流器，吃的是全局那一道（与 /api/version/check 同一档）', () => {
    expect(store.dedicatedRateLimitCovers(declaredRegionPath())).toBe(false);
  });

  test('公开：不带任何凭证也能拿到 200', async () => {
    const res = await get();
    expect(res.status).toBe(200);
    expect(res.headers['x-powered-by']).toBeUndefined();
  });

  test('外层信封与 /api/version/check 一致（{code:0,message,data}）', async () => {
    const res = await get({ 'cf-ipcountry': 'CN' });
    expect(Object.keys(res.body).sort()).toEqual(['code', 'data', 'message']);
    expect(res.body.code).toBe(0);
    expect(res.body.message).toBe('success');
  });
});
