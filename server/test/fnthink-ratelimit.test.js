// fnthink 面独立限流（#130 第一片）的行为测试。
//
// 这一片要守的东西只有一件：**fnthink 的洪水不许把升级通道一起淹掉**。
// 所以关键用例不是"429 会来"，而是"429 来了之后 /api/version/check 还活着"——
// 那恰好是拆桶之前会失败的方向（旧教训：TRUST_PROXY 没配 ⇒ 所有设备算作同一个 IP ⇒ 共享额度先撞线）。
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-rl-'));
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-rl', 10);
process.env.ENCRYPTION_KEY = 'a'.repeat(64);
// 反代拓扑：让 X-Forwarded-For 真的能区分出不同 IP（否则"不同 IP 不共享额度"那条测不出东西）
process.env.TRUST_PROXY = '1';
// 专职额度设到 3 才能在本文件里真的把 429 打出来；同时把全局那把闸门抬到很高 ——
// 否则"专职路径跳过全局桶"这件事没法被隔离验证（两把闸门会互相掩盖）
process.env.RATE_LIMIT_FNTHINK_MAX = '3';
process.env.RATE_LIMIT_GENERAL_MAX = '100000';

const request = require('supertest');
const app = require('../lib/app');
const store = require('../lib/store');
const { statusCode, loadContract, assertSupported } = require('../lib/fnthink/contract');
const { createFnthinkRateLimiter } = require('../lib/fnthink/ratelimit');

const contract = assertSupported(loadContract());
const FORBIDDEN = statusCode(contract, 'forbidden');
const RATE_LIMITED = statusCode(contract, 'rateLimited');

const IP_A = '203.0.113.11';
const IP_B = '203.0.113.12';

function poll(from) {
  return request(app).post('/api/fnthink/poll').set('X-Forwarded-For', from).send({});
}

describe('fnthink 独立限流', () => {
  test('超过专职额度 ⇒ 契约里的 429 + Retry-After + 空 body（不发明回执词）', async () => {
    for (let i = 0; i < 3; i++) {
      const res = await poll(IP_A);
      // 每一发都因为签名不过而 403，但**都被记了数**：限流判在验签之前（计数比密码学便宜）
      expect(res.status).toBe(FORBIDDEN);
      expect(res.body).toEqual({ receipt: 'rejected_unsigned' });
    }
    const over = await poll(IP_A);
    expect(over.status).toBe(RATE_LIMITED);
    expect(Number(over.headers['retry-after'])).toBeGreaterThan(0);
    expect(over.body).toEqual({});
  });

  test('fnthink 被打满之后，升级通道照常（这才是拆桶的全部意义）', async () => {
    for (let i = 0; i < 6; i++) await poll(IP_B); // 确定已过线
    const version = await request(app)
      .get('/api/version/check?version=1.0.0&build=1&platform=android')
      .set('X-Forwarded-For', IP_B)
      .expect(200);
    expect(version.body.code).toBe(0);
  });

  test('不同 IP 各拿一份额度，互不牵连', async () => {
    // IP_A 已经过线；新来的 IP 必须还能拿到"签名不过"这种业务响应，而不是被连坐成 429
    const fresh = await poll('198.51.100.9');
    expect(fresh.status).toBe(FORBIDDEN);
    expect(fresh.body).toEqual({ receipt: 'rejected_unsigned' });
  });

  test('专职路径不再吃全局桶（两边各记一遍数时，紧的那把先响 = 拆桶等于没拆）', () => {
    expect(store.dedicatedRateLimitCovers('/api/fnthink/poll')).toBe(true);
    expect(store.dedicatedRateLimitCovers('/api/version/check')).toBe(false);
    expect(store.dedicatedRateLimitCovers('/api/admin/login')).toBe(false); // 管理面既有行为不动
    expect(store.rateLimitBucket('/api/fnthink/poll')).toBe('api-fnthink');
  });

  test('全局那把闸门对专职路径必须直接放行（否则两把闸门各记一遍数，紧的先响）', () => {
    // 直接驱动中间件本体，而不是等 HTTP：本文件的 GENERAL 被抬到 10 万，
    // 从外面看不出"有没有跳过"，必须在这里用一把**紧的**全局闸门来证明跳过真的发生了。
    const middleware = require('../lib/middleware');
    const seen = [];
    const fakeLimiter = middleware.createRateLimitMiddleware(2, 60 * 1000, '太频繁');
    const run = (p) =>
      new Promise((resolve) => {
        const req = { path: p, ip: '203.0.113.90', headers: {} };
        const res = {
          statusCode: 0,
          body: null,
          status(code) {
            this.statusCode = code;
            return this;
          },
          json(payload) {
            this.body = payload;
            resolve({ status: this.statusCode, counted: false });
          },
        };
        fakeLimiter(req, res, () => {
          seen.push(p);
          resolve({ status: 0, counted: true });
        });
      });

    // 同一个假 IP 连打 5 发 fnthink：跳过了就不会有任何一发被 2/分钟的闸门拦下
    return Promise.all([1, 2, 3, 4, 5].map(() => run('/api/fnthink/poll')))
      .then((rs) => {
        expect(rs.every((r) => r.counted)).toBe(true);
        // 而普通 api 路径仍受全局闸门管（证明不是"把闸门整个关了"）
        return Promise.all([1, 2, 3, 4].map(() => run('/api/version/check')));
      })
      .then((rs) => {
        expect(rs.filter((r) => r.status === 429).length).toBeGreaterThan(0);
      });
  });

  test('上限不许缺省成"不限"，也不许静默按 0 全拒', () => {
    for (const bad of [0, -1, NaN, '', undefined, 'abc']) {
      expect(() => createFnthinkRateLimiter(bad)).toThrow(/正整数/);
    }
    expect(() => createFnthinkRateLimiter(300)).not.toThrow();
  });

  test('源码守卫：桶分支必须排在通用 /api/ 之前，且前缀白名单只有一处', () => {
    const storeSrc = fs.readFileSync(path.join(__dirname, '../lib/store.js'), 'utf8');
    const middleware = fs.readFileSync(path.join(__dirname, '../lib/middleware.js'), 'utf8');
    const fnthinkBucketLine = storeSrc.indexOf(
      "if (p.startsWith('/api/fnthink')) return 'api-fnthink'",
    );
    const genericLine = storeSrc.indexOf("if (p.startsWith('/api/')) return 'api'");
    expect(fnthinkBucketLine).toBeGreaterThan(-1);
    expect(genericLine).toBeGreaterThan(-1);
    // 顺序错了就永远进不了专职桶 —— 这种缺陷不报错，只会让"拆桶"静默失效
    expect(fnthinkBucketLine).toBeLessThan(genericLine);
    expect(middleware).toContain('store.dedicatedRateLimitCovers(req.path)');
    expect(middleware).not.toMatch(/\/api\/fnthink/); // 前缀不许在中间件里再抄一份
    expect(storeSrc).toContain('DEDICATED_RATE_LIMIT_PREFIXES');
  });
});
