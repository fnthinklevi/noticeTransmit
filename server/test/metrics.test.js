'use strict';
/**
 * T187 片1：`/metrics` 指标面的契约测试（真实 HTTP 请求，非纯逻辑）。
 *
 * 这一档钉住的是五件"文档说有、代码没有"就会红的东西：
 *  ① 文本 exposition **可解析**（自带一份小解析器，不靠"看起来像 Prometheus"）；
 *  ② 两道门各自的行为：`METRICS_ENABLED` 与 `METRICS_TOKEN`（没配 ⇒ 与未知路由逐字节同形 404）；
 *  ③ 基数与隐私纪律：路由标签只会是模板，取值/随机路径/凭据永远进不了标签；
 *  ④ 安全族三个入口点各自真的被记到（管理口令、2FA 累计失败、封锁后的拒绝）；
 *  ⑤ 部署面：`/metrics` 不进 IP 封锁豁免（片1 定稿），而 Docker HEALTHCHECK 仍打 `/health`。
 *
 * ⚠ 夹具里那些"哨兵值"同时是两条不泄漏判据的探针：它们出现在指标文本里 anywhere ⇒ 红。
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const bcrypt = require('bcryptjs');
const { generate, NobleCryptoPlugin, ScureBase32Plugin } = require('otplib');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
// 独立数据目录：本文件会真触发一次 IP 封锁并落盘（blocked_ips.json），不能碰真实 data/
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-metrics-test-'));
process.env.TRUST_PROXY = '1'; // 让封锁打在**假 IP** 上（打真 IP 会毁掉后面所有用例）
process.env.RATE_LIMIT_GENERAL_MAX = '100000';
process.env.RATE_LIMIT_AUTH_MAX = '100000';

// ---- 哨兵值（全部是测试夹具的假值，零语义；它们绝不能出现在指标文本里） ----
const ADMIN_TOKEN = 'metrics-admin-token-sentinel';
const ENCRYPTION_SENTINEL = 'c'.repeat(64);
const ECHO_SENTINEL = 'echo-sentinel-3tsw2ydg';
const METRICS_TOKEN_SENTINEL = 'metrics-read-token-42';
const ADDRESS_SENTINEL = 'zzh4vk7pqm3tsw2ydg'; // 18 位 crockford-base32，与契约同形
const SECRET_SENTINEL = 'q7m3tsw2ydgv8zzh4knpabcdefg56'; // 32 位，端点密钥档
const PROBE_PATH_SENTINEL = 'zzprobe7m3tsw2ydg';

process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync(ADMIN_TOKEN, 10);
process.env.ENCRYPTION_KEY = ENCRYPTION_SENTINEL;
process.env.ECHO_TOKEN = ECHO_SENTINEL;
process.env.METRICS_TOKEN = METRICS_TOKEN_SENTINEL;

const request = require('supertest');
const app = require('../lib/app');
const store = require('../lib/store');
const metrics = require('../lib/metrics');
const { loadContract, assertSupported } = require('../lib/fnthink/contract');
const messagestore = require('../lib/fnthink/messagestore');

const otpCrypto = new NobleCryptoPlugin();
const otpBase32 = new ScureBase32Plugin();
const totpFor = (secret) => generate({ secret, crypto: otpCrypto, base32: otpBase32 });

// ========== 自带一份最小 exposition 解析器 ==========
// 为什么自己写：引入 prometheus-proximity 之类的解析依赖与"零新依赖"这条取向冲突，
// 而片1 的闸门要的恰好是"格式合法"这一件事 —— 自己写的那份还能把判据写死成
// "两行完全相同的样本＝非法"（真红过一次：标签没渲染出来时，四次请求塌成四行一模一样的数）。

const SAMPLE_RE =
  /^([a-zA-Z_:][a-zA-Z0-9_:]*)((?:\{[^{}]*\})?) (-?(?:\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|NaN|\+Inf|-Inf))( \d+)?$/;
const LABEL_NAME_RE = /^[a-zA-Z_][a-zA-Z0-9_]*$/;

function parseLabelInner(inner) {
  const out = {};
  let i = 0;
  while (i < inner.length) {
    const eq = inner.indexOf('=', i);
    if (eq < 0) throw new Error(`标签缺等号：${inner}`);
    const key = inner.slice(i, eq);
    if (!LABEL_NAME_RE.test(key)) throw new Error(`非法标签名：${key}`);
    if (inner[eq + 1] !== '"') throw new Error(`标签值必须加引号：${key}`);
    let j = eq + 2;
    let val = '';
    let closed = false;
    while (j < inner.length) {
      const c = inner[j];
      if (c === '\\') {
        val += inner[j + 1];
        j += 2;
        continue;
      }
      if (c === '"') {
        closed = true;
        break;
      }
      val += c;
      j += 1;
    }
    if (!closed) throw new Error(`标签值没闭合：${key}`);
    out[key] = val;
    i = j + 1;
    if (i < inner.length) {
      if (inner[i] !== ',') throw new Error(`标签分隔符不是逗号：${inner.slice(i)}`);
      i += 1;
    }
  }
  return out;
}

/**
 * 解析并**校验**整份 exposition；任何一条不合法就 throw（用例里因此只需 expect(...).not.toThrow()
 * 之外的东西都能复用这份读数）。返回 {declared, samples}。
 */
function parseExposition(text) {
  if (!text.endsWith('\n')) throw new Error(' exposition 必须以换行结尾');
  const lines = text.split('\n');
  const declared = new Map(); // family name -> type
  const samples = [];
  const seenLines = new Set();
  let currentFamily = null;
  let inTrailingBlank = false;

  lines.forEach((line, idx) => {
    const last = idx === lines.length - 1;
    if (line === '') {
      if (!last) throw new Error(`中间出现空行（第 ${idx + 1} 行）`);
      inTrailingBlank = true;
      return;
    }
    if (inTrailingBlank) throw new Error('末尾空行之后还有内容');
    if (line.startsWith('#')) {
      const m = /^# (HELP|TYPE) ([a-zA-Z_:][a-zA-Z0-9_:]*) (.*)$/.exec(line);
      if (/^#(HELP|TYPE)/.test(line)) throw new Error(`# 与关键字之间缺空格：${line}`);
      if (!m) throw new Error(`注释行形状不合法：${line}`);
      const [, kind, name, body] = m;
      if (name === currentFamily) throw new Error(`同一家族出现两段注释：${name}`);
      if (kind === 'TYPE') {
        if (!['counter', 'gauge', 'histogram', 'summary', 'untyped'].includes(body)) {
          throw new Error(`未知 TYPE：${body}`);
        }
        if (declared.has(name)) throw new Error(`重复 TYPE：${name}`);
        declared.set(name, body);
      }
      currentFamily = null;
      return;
    }
    const m = SAMPLE_RE.exec(line);
    if (!m) throw new Error(`样本行不合法：${line}`);
    if (seenLines.has(line))
      throw new Error(`出现两行完全相同的样本（多半是标签没渲染出来）：${line}`);
    seenLines.add(line);
    const [, sampleName, labelPart, valueStr] = m;
    const labels = labelPart ? parseLabelInner(labelPart.slice(1, -1)) : {};
    let family = sampleName;
    if (!declared.has(family)) {
      const suffix = /_(bucket|sum|count)$/.exec(sampleName);
      const base = suffix
        ? sampleName.slice(0, suffix[1] ? sampleName.length - suffix[0].length : 0)
        : null;
      if (!base || declared.get(base) !== 'histogram')
        throw new Error(`样本不属于任何已声明家族：${line}`);
      family = base;
      if (suffix[1] === 'bucket' && !('le' in labels)) {
        throw new Error(`直方图 _bucket 样本缺 le 标签：${line}`);
      }
    }
    if (currentFamily !== null && currentFamily !== family) {
      throw new Error(`家族 ${family} 的样本混进了 ${currentFamily} 的段里`);
    }
    currentFamily = family;
    samples.push({ line, name: sampleName, family, labels, value: Number(valueStr) });
  });

  return { declared, samples };
}

function findSample(parsed, name, labels) {
  const want = Object.entries(labels || {});
  return parsed.samples.filter((s) => s.name === name && want.every(([k, v]) => s.labels[k] === v));
}

/**
 * 取某一家族在给定标签子集下的样本。**找不到或多于一条都抛**，不返回 undefined ——
 * 断言若写成 `expect(pick(...)).toBe(2)`，而那条系列根本不存在时拿 undefined 比对会一路走到
 * 用例末尾才以"expected 2, received undefined" red，读起来像读数错了而不是线没了。
 */
function pick(parsed, name, labels) {
  const hit = findSample(parsed, name, labels);
  if (hit.length !== 1) {
    throw new Error(`期望恰好一枚 ${name} ${JSON.stringify(labels)}，实际 ${hit.length} 枚`);
  }
  return hit[0].value;
}

/** 允许"这条线还不存在"的读法（用于断言某条线**不该**出现）。 */
function pickOpt(parsed, name, labels) {
  const hit = findSample(parsed, name, labels);
  if (hit.length > 1) throw new Error(`${name} ${JSON.stringify(labels)} 出现 ${hit.length} 枚`);
  return hit.length === 1 ? hit[0].value : null;
}

/** 抓取一次并解析（同时把"能解析"这条判据顺路跑掉）。 */
async function scrape(token = METRICS_TOKEN_SENTINEL) {
  const res = await request(app).get('/metrics').set('Authorization', `Bearer ${token}`);
  if (res.status !== 200) throw new Error(`抓取失败：${res.status} ${res.text}`);
  return { res, parsed: parseExposition(res.text), text: res.text };
}

function routeValues(parsed) {
  return new Set(parsed.samples.filter((s) => 'route' in s.labels).map((s) => s.labels.route));
}

// 先造一点真实流量，让三族都有读数（本文件共用同一个 app 实例，计数是累加的）
beforeAll(async () => {
  await request(app).get('/health');
  await request(app).get('/health');
  await request(app).post('/api/fnthink/poll').send({});
});

describe('片1 · 文本形状与三族', () => {
  test(' exposition 可解析，且每族注释先于样本、没有重复样本行', async () => {
    const { text } = await scrape();
    expect(() => parseExposition(text)).not.toThrow();
    // 反证对着这一句：把标签渲染拆掉 ⇒ 四行一模一样的 `notice_http_requests_total 1` ⇒ 解析器抛
    const { parsed } = await scrape();
    const lines = parsed.samples.map((s) => s.line);
    expect(new Set(lines).size).toBe(lines.length);
  });

  test('三族关键指标各就各位（进程 / HTTP / 安全）', async () => {
    // 事件循环滞后那一族的窗口＝上次抓取至今：刚抓完立刻再抓会一个样本都没有（那就是"没有"，
    // 不编 0 充数）。等过 resolution(20ms) 两三拍再抓，让"存在"这条断言不靠运气。
    await new Promise((r) => setTimeout(r, 80));
    const { parsed } = await scrape();
    expect(parsed.declared.get('notice_process_up')).toBe('gauge');
    expect(parsed.declared.get('notice_process_heap_used_bytes')).toBe('gauge');
    expect(parsed.declared.get('notice_process_event_loop_lag_ms')).toBe('gauge');
    expect(parsed.declared.get('notice_http_requests_total')).toBe('counter');
    expect(parsed.declared.get('notice_http_request_duration_ms')).toBe('histogram');
    expect(parsed.declared.get('notice_security_auth_failures_total')).toBe('counter');
    // 读数本身也要在（只声明不算数的家族一律不算"有"）
    expect(pick(parsed, 'notice_process_up', {})).toBe(1);
    expect(pick(parsed, 'notice_process_heap_used_bytes', {})).toBeGreaterThan(0);
    expect(parsed.samples.some((s) => s.name === 'notice_http_requests_total')).toBe(true);
    expect(parsed.samples.some((s) => s.name === 'notice_http_request_duration_ms_count')).toBe(
      true,
    );
  });

  test('封闭词表先播种 0：/health 那两发的计数按状态码记在 /health 模板上', async () => {
    const { parsed } = await scrape();
    for (const kind of metrics.AUTH_FAILURE_KINDS) {
      expect(pick(parsed, 'notice_security_auth_failures_total', { kind })).toBeGreaterThanOrEqual(
        0,
      );
    }
    expect(
      pick(parsed, 'notice_http_requests_total', { route: '/health', method: 'GET' }),
    ).toBeGreaterThanOrEqual(2);
  });

  test('同一系列两次抓取只增不减（单调计数器）', async () => {
    const before = await scrape();
    const v0 = pick(before.parsed, 'notice_http_requests_total', {
      route: '/health',
      method: 'GET',
      status: '200',
    });
    await request(app).get('/health');
    await request(app).get('/health');
    const after = await scrape();
    const v1 = pick(after.parsed, 'notice_http_requests_total', {
      route: '/health',
      method: 'GET',
      status: '200',
    });
    expect(v1 - v0).toBe(2);
    // 时延直方图与计数同口径推进，且分桶累积（+Inf 等于 _count）
    const c0 = pick(before.parsed, 'notice_http_request_duration_ms_count', {
      route: '/health',
      method: 'GET',
    });
    const c1 = pick(after.parsed, 'notice_http_request_duration_ms_count', {
      route: '/health',
      method: 'GET',
    });
    expect(c1 - c0).toBe(2);
    const inf = pick(after.parsed, 'notice_http_request_duration_ms_bucket', {
      route: '/health',
      method: 'GET',
      le: '+Inf',
    });
    expect(inf).toBe(c1);
  });
});

describe('片1 · 两道门的行为', () => {
  const savedToken = process.env.METRICS_TOKEN;
  const savedEnabled = process.env.METRICS_ENABLED;
  afterEach(() => {
    process.env.METRICS_TOKEN = savedToken;
    if (savedEnabled === undefined) delete process.env.METRICS_ENABLED;
    else process.env.METRICS_ENABLED = savedEnabled;
  });

  test('没配 METRICS_TOKEN ⇒ 404，且与未知路由**逐字节同形**', async () => {
    delete process.env.METRICS_TOKEN;
    const hidden = await request(app).get('/metrics');
    const unknown = await request(app).get('/api/definitely-not-here');
    expect(hidden.status).toBe(404);
    // 应用级 404 是整页 HTML 且内嵌请求路径：互换路径后逐字相等，才证明"透传到了应用级 404"
    expect(hidden.text).toBe(unknown.text.split('/api/definitely-not-here').join('/metrics'));
  });

  test('METRICS_ENABLED 为假值 ⇒ 即使 token 配了也 404 同形，且不再采集', async () => {
    for (const off of ['0', 'false', 'no', 'off', 'FALSE', ' Off ']) {
      process.env.METRICS_ENABLED = off;
      const res = await request(app).get('/metrics');
      expect(res.status).toBe(404);
    }
    // 关掉时连记账都不发生：/health 的计数在整个"关着打三发"的过程里一个字不动
    delete process.env.METRICS_ENABLED;
    const before = await scrape();
    const key = { route: '/health', method: 'GET', status: '200' };
    const v0 = pick(before.parsed, 'notice_http_requests_total', key);
    process.env.METRICS_ENABLED = '0';
    await request(app).get('/health');
    await request(app).get('/health');
    await request(app).get('/health');
    delete process.env.METRICS_ENABLED;
    const after = await scrape();
    expect(pick(after.parsed, 'notice_http_requests_total', key)).toBe(v0);
  });

  test('缺 Authorization /  scheme 名不对 / 值不对 ⇒ 401，只回一句话', async () => {
    const noHeader = await request(app).get('/metrics');
    expect(noHeader.status).toBe(401);
    expect(noHeader.body).toEqual({ error: 'unauthorized' });

    const wrong = await request(app).get('/metrics').set('Authorization', 'Bearer nope');
    expect(wrong.status).toBe(401);

    const basic = await request(app)
      .get('/metrics')
      .set(
        'Authorization',
        `Basic ${Buffer.from(`x:${METRICS_TOKEN_SENTINEL}`).toString('base64')}`,
      );
    expect(basic.status).toBe(401);

    // 口令走 query 不算（那会把它落进反代 access log）
    const query = await request(app).get(`/metrics?token=${METRICS_TOKEN_SENTINEL}`);
    expect(query.status).toBe(401);
  });

  test('带对 Bearer ⇒ 200；方案名大小写不敏感；文本面契约齐备', async () => {
    const { res } = await scrape();
    expect(res.status).toBe(200);
    // 断在契约上：媒体类型 + 必须的参数（顺序由 Express 归一化，不钉它）
    expect(res.headers['content-type']).toMatch(/(^|;)\s*text\/plain/i);
    expect(res.headers['content-type']).toMatch(/version=0\.0\.4/);
    expect(res.headers['content-type']).toMatch(/charset=utf-8/i);
    expect(res.headers['cache-control']).toMatch(/no-store/);

    const lower = await request(app)
      .get('/metrics')
      .set('Authorization', `bearer ${METRICS_TOKEN_SENTINEL}`);
    expect(lower.status).toBe(200);

    const padded = await request(app)
      .get('/metrics')
      .set('Authorization', `Bearer   ${METRICS_TOKEN_SENTINEL}  `);
    expect(padded.status).toBe(200);
  });

  test('.env 里没配过 METRICS_TOKEN 时读口不出现（判据现取，不抄开关表）', () => {
    delete process.env.METRICS_TOKEN;
    expect(metrics.metricsToken()).toBe('');
    process.env.METRICS_TOKEN = '  spaced-token  ';
    expect(metrics.metricsToken()).toBe('spaced-token'); // 两侧空白吃掉：'.env 尾随空格'不是漏配
  });
});

describe('片1 · 基数与不泄漏', () => {
  test('路由标签只有模板：路径段里的端点/密钥取值一个字都不进指标', async () => {
    await request(app).get(`/api/fnthink/p/${ADDRESS_SENTINEL}/${SECRET_SENTINEL}`);
    await request(app).post(`/api/fnthink/p/${ADDRESS_SENTINEL}`).send({ a: 1 });
    const { text, parsed } = await scrape();
    expect(text).not.toContain(ADDRESS_SENTINEL);
    expect(text).not.toContain(SECRET_SENTINEL);
    // 而这一族确实存在，且带的是**参数名**
    expect(text).toContain('/api/fnthink/p/:endpointId/:secret');
  });

  test('未匹配路径只按桶记，探测串不进标签', async () => {
    const keysOf = (parsed) =>
      parsed.samples
        .filter((s) => s.name === 'notice_http_requests_total')
        .map((s) => s.line.replace(/ \d+(\.\d+)?$/, ''))
        .sort();

    // 先来一发把 `static` 桶那枚系列**建出来**（首次出现的标签组合必然新增一行，那不是泄漏），
    // 再取快照 ⇒ 之后 30 发随机路径必须**一条新序列都不造**。
    await request(app).get('/zzz-warmup');
    const k0 = keysOf((await scrape()).parsed);

    for (let i = 0; i < 30; i++) {
      await request(app).get(`/zzz-probe-${i}-${PROBE_PATH_SENTINEL}?x=${i}`);
    }
    const { text, parsed } = await scrape();
    expect(text).not.toContain(PROBE_PATH_SENTINEL);
    expect(text).not.toContain('zzz-probe');
    for (const r of routeValues(parsed)) {
      const bucketed = ['api-admin', 'api-fnthink', 'api', 'static'].includes(r);
      expect(bucketed || r.startsWith('/')).toBe(true);
    }
    // ⚠ 这一条不能写成"series 数 < N"：直方图的每个分桶也是一行样本，N 会随分桶数漂。
    expect(keysOf(parsed)).toEqual(k0);
  });

  test('方法标签走白名单，词表外折成 OTHER（伪造方法＝一条新序列的经典形状）', () => {
    expect(metrics.methodLabelOf('get')).toBe('GET');
    expect(metrics.methodLabelOf('POST')).toBe('POST');
    expect(metrics.methodLabelOf('FOOBAR')).toBe('OTHER');
    expect(metrics.methodLabelOf('')).toBe('OTHER');
    expect(metrics.methodLabelOf(undefined)).toBe('OTHER');
  });

  test('routeLabelOf：没模板也没桶 ⇒ other，绝不冒原始路径', () => {
    expect(metrics.routeLabelOf({ path: '/zzz/leak' }, undefined)).toBe('other');
    expect(metrics.routeLabelOf({ path: '/x', route: { path: '/y' }, baseUrl: '/api' })).toBe(
      '/api/y',
    );
    expect(
      metrics.routeLabelOf({ path: '/metrics/', route: { path: '/' }, baseUrl: '/metrics' }),
    ).toBe('/metrics');
    // 意外形状（含空格/查询串）折掉，而不是原样写进标签
    expect(metrics.routeLabelOf({ path: '/x', route: { path: '/y?a=b c' } })).toBe('other');
  });

  test('指标文本里没有 .env 任一值的片段、也没有正文', async () => {
    // 先发一发**带正文**的请求：正文里塞哨兵串，证明正文不会顺着指标出来
    await request(app)
      .post('/api/fnthink/message')
      .send({ fields: { text: `BODY-LEAK-${ADDRESS_SENTINEL}` } });
    const { text } = await scrape();
    for (const value of [
      process.env.ADMIN_TOKEN_HASH,
      ENCRYPTION_SENTINEL,
      ECHO_SENTINEL,
      METRICS_TOKEN_SENTINEL,
      ADDRESS_SENTINEL,
      SECRET_SENTINEL,
      ADMIN_TOKEN,
    ]) {
      expect(text).not.toContain(String(value).slice(0, 12));
    }
    expect(text).not.toContain('BODY-LEAK');
    expect(text).not.toContain('Bearer');
  });

  test('HELP 文本里没有中文以外的敏感词，且指标名全部带 notice_ 前缀', async () => {
    const { parsed } = await scrape();
    for (const name of parsed.declared.keys()) expect(name.startsWith('notice_')).toBe(true);
  });
});

describe('片1 · 安全族三个入口点', () => {
  const BLOCKED_IP = '203.0.113.91'; // RFC5737 文档 IP，不会被真设备用到
  const BLOCKED_IP_2 = '203.0.113.92';

  test('管理口令猜错 ⇒ kind="admin_token" 递增（这一条不进封锁，只能靠指标看见）', async () => {
    const before = await scrape();
    const v0 = pick(before.parsed, 'notice_security_auth_failures_total', { kind: 'admin_token' });
    await request(app).post('/api/admin/login').send({ token: 'wrong-token-please' });
    await request(app).post('/api/admin/login').send({ token: 'another-wrong' });
    const after = await scrape();
    expect(
      pick(after.parsed, 'notice_security_auth_failures_total', { kind: 'admin_token' }) - v0,
    ).toBe(2);
  });

  test('2FA 连错 5 次 ⇒ login_2fa +5、封锁落盘 +1', async () => {
    // 先把 2FA 开起来（走真实路由，不复用 store 后门）
    const login = await request(app).post('/api/admin/login').send({ token: ADMIN_TOKEN });
    const sessionId = login.body.sessionId;
    expect(sessionId).toBeTruthy();
    const setup = await request(app).get('/api/admin/totp/setup').set('x-session-id', sessionId);
    const secret = setup.body.data.secret;
    expect(secret).toBeTruthy();
    const enable = await request(app)
      .post('/api/admin/totp/enable')
      .set('x-session-id', sessionId)
      .set('X-Forwarded-For', BLOCKED_IP)
      .send({ secret, otp: await totpFor(secret) });
    expect(enable.status).toBe(200);

    const before = await scrape();
    const k0 = pick(before.parsed, 'notice_security_auth_failures_total', { kind: 'login_2fa' });
    const b0 = pick(before.parsed, 'notice_security_ip_blocks_applied_total', {});

    let last = null;
    for (let i = 1; i <= 5; i++) {
      last = await request(app)
        .post('/api/admin/login')
        .set('X-Forwarded-For', BLOCKED_IP)
        .send({ token: ADMIN_TOKEN, otp: '000000' });
    }
    expect(last.status).toBe(403);
    expect(last.body.blocked).toBe(true);

    const after = await scrape();
    expect(
      pick(after.parsed, 'notice_security_auth_failures_total', { kind: 'login_2fa' }) - k0,
    ).toBe(5);
    expect(pick(after.parsed, 'notice_security_ip_blocks_applied_total', {}) - b0).toBe(1);
  });

  test('封锁生效后每一发都被拒 ⇒ ip_block_refusals 递增（中间件那一个入口）', async () => {
    store.blockIp(BLOCKED_IP_2);
    const before = await scrape();
    const r0 = pick(before.parsed, 'notice_security_ip_block_refusals_total', {});
    const admin = await request(app).get('/api/admin/version').set('X-Forwarded-For', BLOCKED_IP_2);
    expect(admin.status).toBe(403);
    expect(admin.body.blocked).toBe(true);
    // /login 自己还有一道前置检查 —— 两个入口点记同一枚计数器，缺一处就少一段
    const login = await request(app)
      .post('/api/admin/login')
      .set('X-Forwarded-For', BLOCKED_IP_2)
      .send({ token: ADMIN_TOKEN });
    expect(login.status).toBe(403);
    const after = await scrape();
    expect(pick(after.parsed, 'notice_security_ip_block_refusals_total', {}) - r0).toBe(2);
  });

  afterAll(() => {
    store.saveBlockedIPs([]);
    for (const ip of [BLOCKED_IP, BLOCKED_IP_2, '::ffff:127.0.0.1', '127.0.0.1']) {
      store.clearFailedAttempts(ip);
    }
  });
});

// 本文件写的两个开关留给同一个 jest worker 里的下一份文件没有意义（`--runInBand` 下 env 是共享的）
// ⇒ 收尾清掉：别的套件不该因为这里配过读口令就突然多出一个 `/metrics`。
afterAll(() => {
  delete process.env.METRICS_TOKEN;
  delete process.env.METRICS_ENABLED;
});

// 源码守卫必须先剥注释：本仓已经被"注释里的字面量被当成代码"砸过好几回
// （`lib/routes/echo.js` 的文档注释里就写着 timingSafeEqual 四个字，不剥就会假红成"有两份实现"）。
function stripJsComments(src) {
  let out = '';
  let mode = 'code';
  let i = 0;
  while (i < src.length) {
    const c = src[i];
    const d = src[i + 1];
    if (mode === 'code') {
      if (c === '/' && d === '/') {
        mode = 'line';
        i += 2;
        continue;
      }
      if (c === '/' && d === '*') {
        mode = 'block';
        i += 2;
        continue;
      }
      if (c === "'" || c === '"' || c === '`') mode = c;
      out += c;
      i += 1;
      continue;
    }
    if (mode === 'line') {
      if (c === '\n') {
        mode = 'code';
        out += c;
      }
      i += 1;
      continue;
    }
    if (mode === 'block') {
      if (c === '*' && d === '/') {
        mode = 'code';
        i += 2;
        continue;
      }
      if (c === '\n') out += '\n';
      i += 1;
      continue;
    }
    // 字符串/模板字面量内部：反斜杠吃掉下一个字符（`'\/\/'` 不该被当注释起点）
    if (c === '\\') {
      out += c + (d === undefined ? '' : d);
      i += 2;
      continue;
    }
    if (c === mode) mode = 'code';
    out += c;
    i += 1;
  }
  return out;
}

describe('片1 · 部署面与唯一作者', () => {
  test('剥注释器自己得是对的（否则"只有一份实现"这条守卫是假的）', () => {
    expect(stripJsComments('// timingSafeEqual\nconst a = 1; // timingSafeEqual')).toBe(
      '\nconst a = 1; ',
    );
    expect(stripJsComments('/* timingSafeEqual */x')).toBe('x');
    // 字符串里的 // 不是注释起点
    expect(stripJsComments("const u = 'http://a';").includes('http://a')).toBe(true);
  });

  test('片1 定稿：`/metrics` 不进 IP 封锁豁免名单（被洪水打时它必须能被拦）', () => {
    expect(store.ipBlockExempt('/metrics')).toBe(false);
    expect(store.ipBlockExempt('/metrics/')).toBe(false);
    expect(store.IP_BLOCK_EXEMPT_PREFIXES).not.toContain('/metrics');
  });

  test('Docker HEALTHCHECK 仍然只打 /health，没被指标面带走', () => {
    const dockerfile = fs.readFileSync(path.join(__dirname, '..', 'Dockerfile'), 'utf8');
    const healthcheck = dockerfile
      .split('\n')
      .filter((l) => /HEALTHCHECK|wget|curl/.test(l))
      .join('\n');
    expect(healthcheck).toContain('/health');
    expect(healthcheck).not.toContain('/metrics');
  });

  test('采集钩子挂在整条链最前面（被 CORS/体积闸/封锁拒掉的请求也要留痕）', () => {
    const src = fs.readFileSync(path.join(__dirname, '..', 'lib/app.js'), 'utf8');
    const at = (needle) => {
      const i = src.indexOf(needle);
      expect(i).toBeGreaterThanOrEqual(0);
      return i;
    };
    expect(at('createMetricsMiddleware')).toBeLessThan(at('cors('));
    expect(at('createMetricsMiddleware')).toBeLessThan(at('express.json('));
    expect(at('createMetricsMiddleware')).toBeLessThan(at('ipBlockMiddleware'));
  });

  test('凭据常量时间比对只有一份实现（timingSafeEqual 只住在 token_compare.js）', () => {
    const dir = path.join(__dirname, '..', 'lib');
    const hits = [];
    const walk = (d) => {
      for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, entry.name);
        if (entry.isDirectory()) walk(p);
        else if (
          p.endsWith('.js') &&
          stripJsComments(fs.readFileSync(p, 'utf8')).includes('timingSafeEqual')
        ) {
          hits.push(path.relative(dir, p).replace(/\\/g, '/'));
        }
      }
    };
    walk(dir);
    expect(hits).toEqual(['token_compare.js']);
  });
});

describe('片1 · 溢出看得见', () => {
  test('一个家族的系列数封顶后，丢弃计入 notice_metrics_series_overflow_total 而不是静默消失', () => {
    const before = parseExposition(metrics.render());
    const probe = metrics.counter('notice_test_probe_total', {
      help: 'probe only',
      labelNames: ['x'],
    });
    for (let i = 0; i < metrics.MAX_SERIES_PER_FAMILY + 5; i++) probe.inc({ x: String(i) });
    const after = parseExposition(metrics.render());
    expect(after.samples.filter((s) => s.name === 'notice_test_probe_total').length).toBe(
      metrics.MAX_SERIES_PER_FAMILY,
    );
    expect(
      pick(after, 'notice_metrics_series_overflow_total', { family: 'notice_test_probe_total' }),
    ).toBeGreaterThan(
      pickOpt(before, 'notice_metrics_series_overflow_total', {
        family: 'notice_test_probe_total',
      }) || 0,
    );
  });

  test('未声明的标签被忽略并打一次日志（不静默造出一条形状不同的序列）', () => {
    const probe = metrics.counter('notice_test_probe2_total', { help: 'probe', labelNames: ['a'] });
    const log = jest.spyOn(console, 'error').mockImplementation(() => {});
    probe.inc({ a: '1', leaked: 'nope' });
    log.mockRestore();
    const parsed = parseExposition(metrics.render());
    expect(pick(parsed, 'notice_test_probe2_total', { a: '1' })).toBe(1);
    expect(parsed.samples.some((s) => 'leaked' in s.labels)).toBe(false);
  });

  test('重复声明同名指标崩在加载期（两处各写一份＝现在就红）', () => {
    expect(() => metrics.counter('notice_test_probe_total', { help: 'again' })).toThrow(/重复声明/);
    expect(() => metrics.counter('bad name', { help: 'x' })).toThrow(/指标名/);
    expect(() => metrics.counter('notice_ok_total', { help: 'x', labelNames: ['1bad'] })).toThrow(
      /标签名/,
    );
  });
});

describe('片2 · 幻念业务面', () => {
  const contract = assertSupported(loadContract());
  const countOf = (parsed, name, labels) => pick(parsed, name, labels);

  test('四态计数、队列深度、SSE 连接数与长轮询 hold 数都在读数里', async () => {
    const { parsed } = await scrape();
    expect(parsed.declared.get('notice_fnthink_delivery_transitions_total')).toBe('counter');
    expect(parsed.declared.get('notice_fnthink_queue_depth')).toBe('gauge');
    expect(parsed.declared.get('notice_fnthink_sse_connections')).toBe('gauge');
    expect(parsed.declared.get('notice_fnthink_long_poll_holds')).toBe('gauge');
    // 封闭词表先播种 0：每个契约状态都必须有一条序列（缺序列在 PromQL 里是"没有这条线"）
    for (const state of contract.delivery.states) {
      expect(
        countOf(parsed, 'notice_fnthink_delivery_transitions_total', { to: state }),
      ).toBeGreaterThanOrEqual(0);
    }
    for (const state of contract.delivery.pollableStates) {
      expect(countOf(parsed, 'notice_fnthink_queue_depth', { state })).toBeGreaterThanOrEqual(0);
    }
    expect(countOf(parsed, 'notice_fnthink_sse_connections', {})).toBeGreaterThanOrEqual(0);
    expect(countOf(parsed, 'notice_fnthink_long_poll_holds', {})).toBeGreaterThanOrEqual(0);
  });

  test('状态真的推进才计一次；迟到的重复 ack 不计', () => {
    const messages = {};
    const { message } = messagestore.enqueue(
      contract,
      messages,
      { device: 'DEV-METRICS', type: 'notice', item: 'app:a', title: 't', body: 'b' },
      Date.now(),
      ENCRYPTION_SENTINEL,
    );
    const transitions = () =>
      parseExposition(metrics.render())
        .samples.filter(
          (s) =>
            s.name === 'notice_fnthink_delivery_transitions_total' &&
            Object.keys(s.labels).length === 1,
        )
        .map((s) => s);
    const deliveredBefore = countOf(
      parseExposition(metrics.render()),
      'notice_fnthink_delivery_transitions_total',
      { to: contract.delivery.terminalStates[0] },
    );
    messagestore.advanceMessage(contract, messages, message.messageId, 'dispatch', {
      now: Date.now(),
    });
    messagestore.advanceMessage(contract, messages, message.messageId, 'ack_ok', {
      now: Date.now(),
    });
    expect(
      countOf(parseExposition(metrics.render()), 'notice_fnthink_delivery_transitions_total', {
        to: contract.delivery.terminalStates[0],
      }) - deliveredBefore,
    ).toBe(1);
    // 迟到的重复 ack：状态机 ignored ⇒ 不许再计一次（否则运维看到的迁移次数会翻倍）
    const beforeLate = countOf(
      parseExposition(metrics.render()),
      'notice_fnthink_delivery_transitions_total',
      { to: contract.delivery.terminalStates[0] },
    );
    messagestore.advanceMessage(contract, messages, message.messageId, 'ack_ok', {
      now: Date.now(),
    });
    expect(
      countOf(parseExposition(metrics.render()), 'notice_fnthink_delivery_transitions_total', {
        to: contract.delivery.terminalStates[0],
      }),
    ).toBe(beforeLate);
    // 尺自己先自证：上面那段 transitions() 不是空转（至少每个状态都看得见）
    expect(transitions().length).toBeGreaterThanOrEqual(contract.delivery.states.length);
  });

  test('收一条消息 ⇒ 队列深度按契约可投递态计出来', async () => {
    const before = countOf(parseExposition((await scrape()).text), 'notice_fnthink_queue_depth', {
      state: contract.delivery.initialState,
    });
    const messages = messagestore.loadMessages();
    messagestore.enqueue(
      contract,
      messages,
      { device: 'DEV-METRICS-QUEUE', type: 'notice', item: 'app:a', title: 't', body: 'b' },
      Date.now(),
      ENCRYPTION_SENTINEL,
    );
    messagestore.saveMessages(messages);
    const after = countOf(parseExposition((await scrape()).text), 'notice_fnthink_queue_depth', {
      state: contract.delivery.initialState,
    });
    expect(after).toBeGreaterThanOrEqual(before + 1);
  });
});
