/**
 * 服务端 HTTP 契约测试（真实请求，非纯逻辑）
 *
 * 覆盖：
 * - 安全头（CSP / nosniff / 禁用 X-Powered-By）
 * - 认证与会话（登录 / 注销吊销 / 会话过期）
 * - 版本配置保存链路（POST /api/admin/version → GET /api/version/check 读回，前后端契约）
 * - 二步验证 TOTP 全流程（setup / enable / 登录 / 恢复码消费 / 2FA 未提交反馈）
 * - IP 封锁（2FA 连续失败触发）
 *
 * 运行方式：在 server/ 目录下执行 `npm test`
 */

const request = require('supertest');
const os = require('os');
const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
const { generate, NobleCryptoPlugin, ScureBase32Plugin } = require('otplib');

const ADMIN_TOKEN = 'test-admin-token-123456';

// ========== 测试环境（必须在任何 require 之前设置） ==========
process.env.NODE_ENV = 'test';
process.env.PORT = '0';
// 独立数据目录：测试写入的 version.json / totp.json 等不污染真实 data/
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-server-test-'));
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync(ADMIN_TOKEN, 10);
// 合法 64 位十六进制密钥：覆盖 TOTP secret 的 AES-256-GCM 加解密往返
process.env.ENCRYPTION_KEY =
  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
// 放大限流阈值，避免契约测试被全局限流误伤（限流自身逻辑由常量断言覆盖）
process.env.RATE_LIMIT_GENERAL_MAX = '10000';
process.env.RATE_LIMIT_AUTH_MAX = '10000';

const app = require('../lib/app');
const store = require('../lib/store');

// 与 server/lib/otp.js 相同的插件配置，生成可被服务端 verify 接受的 TOTP 码
const otpCrypto = new NobleCryptoPlugin();
const otpBase32 = new ScureBase32Plugin();
function totpFor(secret) {
  return generate({ secret, crypto: otpCrypto, base32: otpBase32 });
}

// supertest 下默认客户端 IP（Node ≥17 为 IPv6 回环），清失败次数时两个形态都清
const TEST_IP_KEYS = ['::ffff:127.0.0.1', '127.0.0.1'];

function clearFailures() {
  for (const ip of TEST_IP_KEYS) store.clearFailedAttempts(ip);
}

describe('基础端点与安全头', () => {
  test('GET /health 返回 ok', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body.timestamp).toBeTruthy();
  });

  test('响应不暴露 X-Powered-By（Express 指纹）', async () => {
    const res = await request(app).get('/health');
    expect(res.headers['x-powered-by']).toBeUndefined();
  });

  test('安全头：nosniff / frame DENY / HSTS', async () => {
    const res = await request(app).get('/health');
    expect(res.headers['x-content-type-options']).toBe('nosniff');
    expect(res.headers['x-frame-options']).toBe('DENY');
    expect(res.headers['strict-transport-security']).toContain('max-age=31536000');
  });

  test('/admin.html 启用严格 CSP，/api/admin 禁止缓存', async () => {
    const admin = await request(app).get('/admin.html');
    expect(admin.status).toBe(200);
    expect(admin.headers['content-security-policy']).toContain("default-src 'self'");
    expect(admin.headers['content-security-policy']).toContain("frame-ancestors 'none'");

    const api = await request(app).get('/api/admin/version');
    expect(api.headers['cache-control']).toContain('no-store');
  });
});

describe('认证与会话', () => {
  test('错误 token 登录 → 401 code -1', async () => {
    const res = await request(app)
      .post('/api/admin/login')
      .send({ token: 'wrong-token' });
    expect(res.status).toBe(401);
    expect(res.body.code).toBe(-1);
  });

  test('正确 token 登录（2FA 未启用）→ 返回会话', async () => {
    const res = await request(app)
      .post('/api/admin/login')
      .send({ token: ADMIN_TOKEN });
    expect(res.status).toBe(200);
    expect(res.body.code).toBe(0);
    expect(res.body.sessionId).toBeTruthy();
    expect(res.body.need2FA).toBe(false);
    expect(res.body.twoFAEnabled).toBe(false);
  });

  test('受保护端点：未认证 → 401；带会话 → 200', async () => {
    const unauth = await request(app).get('/api/admin/version');
    expect(unauth.status).toBe(401);

    const login = await request(app)
      .post('/api/admin/login')
      .send({ token: ADMIN_TOKEN });
    const authed = await request(app)
      .get('/api/admin/version')
      .set('x-session-id', login.body.sessionId);
    expect(authed.status).toBe(200);
    expect(authed.body.code).toBe(0);
  });

  test('注销后会话被吊销，原会话 ID 失效', async () => {
    const login = await request(app)
      .post('/api/admin/login')
      .send({ token: ADMIN_TOKEN });
    const sessionId = login.body.sessionId;

    const logout = await request(app)
      .post('/api/admin/logout')
      .set('x-session-id', sessionId);
    expect(logout.status).toBe(200);
    expect(logout.body.code).toBe(0);

    const after = await request(app)
      .get('/api/admin/version')
      .set('x-session-id', sessionId);
    expect(after.status).toBe(401);
  });

  test('会话过期（>24h）→ 401 提示重新登录', async () => {
    const login = await request(app)
      .post('/api/admin/login')
      .send({ token: ADMIN_TOKEN });
    const sessionId = login.body.sessionId;
    store.sessions[sessionId].createdAt = Date.now() - 25 * 60 * 60 * 1000;

    const res = await request(app)
      .get('/api/admin/version')
      .set('x-session-id', sessionId);
    expect(res.status).toBe(401);
    expect(res.body.message).toContain('会话已过期');
  });
});

describe('版本保存链路（前后端契约）', () => {
  let sessionId;

  beforeAll(async () => {
    const login = await request(app)
      .post('/api/admin/login')
      .send({ token: ADMIN_TOKEN });
    sessionId = login.body.sessionId;
  });

  const validBody = {
    latestVersion: '2.0.0',
    latestBuild: 20,
    changelog: '测试版本更新',
    downloads: {
      arm64: 'https://example.com/app_arm64.apk',
      arm32: 'https://example.com/app_arm32.apk',
      x86_64: 'https://example.com/app_x86.apk',
      all: ''
    },
    fileSizes: { arm64: 123456, arm32: 0, x86_64: 100 },
    minSupportedVersion: '1.0.0'
  };

  test('未认证 POST 保存 → 401', async () => {
    const res = await request(app)
      .post('/api/admin/version')
      .send(validBody);
    expect(res.status).toBe(401);
  });

  test('字段校验：非 https 下载链接 / 非法 build → 400 code -4', async () => {
    const badUrl = await request(app)
      .post('/api/admin/version')
      .set('x-session-id', sessionId)
      .send({ ...validBody, downloads: { ...validBody.downloads, arm64: 'http://insecure.com/a.apk' } });
    expect(badUrl.status).toBe(400);
    expect(badUrl.body.code).toBe(-4);
    expect(badUrl.body.message).toContain('https');

    const badBuild = await request(app)
      .post('/api/admin/version')
      .set('x-session-id', sessionId)
      .send({ ...validBody, latestBuild: 0 });
    expect(badBuild.status).toBe(400);
    expect(badBuild.body.code).toBe(-4);
  });

  test('保存成功 → code 0；version.json 落盘', async () => {
    const res = await request(app)
      .post('/api/admin/version')
      .set('x-session-id', sessionId)
      .send(validBody);
    expect(res.status).toBe(200);
    expect(res.body.code).toBe(0);

    // 落盘校验：写入的是明文契约，不含加密干扰
    const onDisk = store.readJsonFile(store.VERSION_FILE, {});
    expect(onDisk.latestVersion).toBe('2.0.0');
    expect(onDisk.latestBuild).toBe(20);
  });

  test('保存链路读回：/api/version/check 反映新版本（前后端契约）', async () => {
    const older = await request(app)
      .get('/api/version/check')
      .query({ version: '1.0.0', build: 1 });
    expect(older.status).toBe(200);
    expect(older.body.code).toBe(0);
    expect(older.body.data.hasUpdate).toBe(true);
    expect(older.body.data.latestVersion).toBe('2.0.0');
    // 平台解析：默认 android → arm64
    expect(older.body.data.downloadUrl).toBe('https://example.com/app_arm64.apk');
    expect(older.body.data.fileSize).toBe(123456);

    const current = await request(app)
      .get('/api/version/check')
      .query({ version: '2.0.0', build: 20 });
    expect(current.body.data.hasUpdate).toBe(false);
  });

  test('forceUpdate 契约：低于阈值 needForce=true，达到后 false', async () => {
    await request(app)
      .post('/api/admin/version')
      .set('x-session-id', sessionId)
      .send({
        latestVersion: '2.0.0',
        latestBuild: 20,
        forceUpdate: true,
        forceUpdateVersion: '1.5.0',
        forceUpdateBuild: 50,
        downloads: validBody.downloads,
        fileSizes: validBody.fileSizes,
        minSupportedVersion: '1.0.0'
      });

    const below = await request(app)
      .get('/api/version/check')
      .query({ version: '1.4.0', build: 40 });
    expect(below.body.data.forceUpdate).toBe(true);

    const above = await request(app)
      .get('/api/version/check')
      .query({ version: '2.0.0', build: 60 });
    expect(above.body.data.forceUpdate).toBe(false);
  });

  test('GET /api/admin/version 读回已保存配置', async () => {
    const res = await request(app)
      .get('/api/admin/version')
      .set('x-session-id', sessionId);
    expect(res.status).toBe(200);
    expect(res.body.code).toBe(0);
    expect(res.body.data.latestVersion).toBe('2.0.0');
  });
});

describe('二步验证 TOTP 全流程', () => {
  let sessionId;
  let secret;
  let recoveryCodes;

  beforeAll(async () => {
    const login = await request(app)
      .post('/api/admin/login')
      .send({ token: ADMIN_TOKEN });
    sessionId = login.body.sessionId;
  });

  test('setup 生成 secret（未启用）', async () => {
    const res = await request(app)
      .get('/api/admin/totp/setup')
      .set('x-session-id', sessionId);
    expect(res.status).toBe(200);
    expect(res.body.code).toBe(0);
    expect(res.body.data.enabled).toBe(false);
    expect(res.body.data.secret).toBeTruthy();
    expect(res.body.data.qrCodeUrl).toContain('data:image');
    secret = res.body.data.secret;
  });

  test('enable 校验 OTP：错误码 → 400；正确码 → 启用并返回 8 个恢复码', async () => {
    const bad = await request(app)
      .post('/api/admin/totp/enable')
      .set('x-session-id', sessionId)
      .send({ secret, otp: '000000' });
    expect(bad.status).toBe(400);

    const code = await totpFor(secret);
    const good = await request(app)
      .post('/api/admin/totp/enable')
      .set('x-session-id', sessionId)
      .send({ secret, otp: code });
    expect(good.status).toBe(200);
    expect(good.body.code).toBe(0);
    expect(good.body.data.enabled).toBe(true);
    expect(good.body.data.recoveryCodes).toHaveLength(8);
    recoveryCodes = good.body.data.recoveryCodes;
  });

  test('status：enabled=true 且持有恢复码', async () => {
    const res = await request(app)
      .get('/api/admin/totp/status')
      .set('x-session-id', sessionId);
    expect(res.body.code).toBe(0);
    expect(res.body.data.enabled).toBe(true);
    expect(res.body.data.hasRecoveryCodes).toBe(true);
  });

  test('已启用后 setup 不再泄露 secret', async () => {
    const res = await request(app)
      .get('/api/admin/totp/setup')
      .set('x-session-id', sessionId);
    expect(res.body.data.enabled).toBe(true);
    expect(res.body.data.secret).toBeUndefined();
    expect(res.body.data.rebindable).toBe(true);
  });

  test('2FA 启用后：纯 token 请求受保护端点 → 401 require2FA', async () => {
    const res = await request(app)
      .get('/api/admin/version')
      .set('x-admin-token', ADMIN_TOKEN);
    expect(res.status).toBe(401);
    expect(res.body.code).toBe(-2);
    expect(res.body.require2FA).toBe(true);
  });

  test('登录：未提交验证码 → 提示输入二步验证验证码', async () => {
    const res = await request(app)
      .post('/api/admin/login')
      .send({ token: ADMIN_TOKEN });
    expect(res.status).toBe(200);
    expect(res.body.code).toBe(0);
    expect(res.body.twoFAEnabled).toBe(true);
    expect(res.body.sessionId).toBeUndefined();
  });

  test('登录：错误 OTP → 401 且提示剩余次数（可感知的反馈）', async () => {
    const res = await request(app)
      .post('/api/admin/login')
      .send({ token: ADMIN_TOKEN, otp: '000000' });
    expect(res.status).toBe(401);
    expect(res.body.code).toBe(-1);
    expect(res.body.remainingAttempts).toBe(4);
    expect(res.body.message).toContain('次尝试机会');
    clearFailures(); // 隔离，避免影响后续 IP 封锁测试
  });

  test('登录：正确 OTP → 成功并返回 twoFAEnabled=true', async () => {
    const code = await totpFor(secret);
    const res = await request(app)
      .post('/api/admin/login')
      .send({ token: ADMIN_TOKEN, otp: code });
    expect(res.status).toBe(200);
    expect(res.body.code).toBe(0);
    expect(res.body.need2FA).toBe(false);
    expect(res.body.twoFAEnabled).toBe(true);
    expect(res.body.sessionId).toBeTruthy();
  });

  test('登录：恢复码一次性消费（8 → 7）', async () => {
    const recovery = recoveryCodes[0];
    const res = await request(app)
      .post('/api/admin/login')
      .send({ token: ADMIN_TOKEN, recoveryCode: recovery });
    expect(res.status).toBe(200);
    expect(res.body.code).toBe(0);

    const config = store.getTotpConfig();
    expect(config.recoveryCodes).toHaveLength(7);

    // 已消费的恢复码再次使用 → 失败
    const again = await request(app)
      .post('/api/admin/login')
      .send({ token: ADMIN_TOKEN, recoveryCode: recovery });
    expect(again.status).toBe(401);
    clearFailures();
  });
});

describe('IP 封锁（2FA 连续失败 5 次）', () => {
  afterAll(() => {
    store.saveBlockedIPs([]);
  });

  test('第 5 次失败触发 403 封锁，公开接口不受影响', async () => {
    clearFailures();

    let blockedRes = null;
    for (let i = 1; i <= 5; i++) {
      const res = await request(app)
        .post('/api/admin/login')
        .send({ token: ADMIN_TOKEN, otp: '000000' });
      if (i < 5) {
        expect(res.status).toBe(401);
        expect(res.body.remainingAttempts).toBe(5 - i);
      } else {
        blockedRes = res;
      }
    }

    expect(blockedRes.status).toBe(403);
    expect(blockedRes.body.code).toBe(-3);
    expect(blockedRes.body.blocked).toBe(true);

    // 封锁只针对非公开接口；版本检查 / health 仍可用
    const health = await request(app).get('/health');
    expect(health.status).toBe(200);
    const version = await request(app).get('/api/version/check').query({ version: '1.0.0', build: 1 });
    expect(version.status).toBe(200);
  });
});
