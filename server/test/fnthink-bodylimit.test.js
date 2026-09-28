// #130-A3：公网面的请求体上限。
//
// 这一片守的是一句容易写在日志里、却没人验证的话："公网面有大小限制"。
// 三件事各自都要红得起来：
//  ① 上限确实生效，且**数字来自契约**（不是实现里再抄一个 1mb / 65536）；
//  ② 它只卡公网面 —— 管理面的备份导入就是要更大的 body，把两把尺子并成一把，
//     症状会是"用户的备份传不上来"，而那与限流毫无关系；
//  ③ 挂载顺序：body-parser 见到已解析的 req._body 就跳过 ⇒ 顺序错了不报错，
//     只是公网面静默地继续吃管理面那把 1 MB（这类"看起来配了其实没配"正是本仓反复犯的形状）。
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-size-'));
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-size', 10);
process.env.ENCRYPTION_KEY = 'a'.repeat(64);

const request = require('supertest');
const app = require('../lib/app');
const { loadContract, assertSupported, statusCode } = require('../lib/fnthink/contract');
const { createFnthinkBodyLimit, bodyMaxBytes } = require('../lib/fnthink/bodylimit');

const contract = assertSupported(loadContract());
const MAX = contract.limits.requestBodyMaxBytes;
const TOO_LARGE = statusCode(contract, 'requestTooLarge');

const pad = (n) => JSON.stringify({ pad: 'x'.repeat(n) });

describe('fnthink 请求体上限（#130-A3）', () => {
  test('超过契约上限 ⇒ 契约里的 413 + 空 body（不区分哪个字段太长）', async () => {
    const res = await request(app)
      .post('/api/fnthink/message')
      .set('Content-Type', 'application/json')
      .send(pad(MAX + 4096));
    expect(res.status).toBe(TOO_LARGE);
    expect(res.body).toEqual({});
  });

  test('上限之内照常走到裁决层（闸没把合法请求一起关掉）', async () => {
    const res = await request(app)
      .post('/api/fnthink/message')
      .set('Content-Type', 'application/json')
      .send(pad(Math.floor(MAX / 4)));
    expect(res.status).not.toBe(TOO_LARGE);
    expect(res.body).toEqual({ receipt: 'rejected_unsigned' });
  });

  test('管理面不受公网那把尺子管（备份导入就是要更大的 body）', async () => {
    // 挑一个未认证也会走到业务判定的入口：它必须回"凭证不对"，而不是"太大"。
    const res = await request(app)
      .post('/api/admin/login')
      .set('Content-Type', 'application/json')
      .send(pad(MAX + 4096));
    expect(res.status).not.toBe(TOO_LARGE);
  });

  test('畸形 JSON 走协议自己的形状，不再冒成管理面的 500', async () => {
    // 这是本片顺手抓到的真实缺陷：改造前这个请求回的是 `{code:-5, message:'Internal server
    // error'}` + 500 —— 公网面上出现管理面的错误契约，而 500 会让设备端以为是自己坏了，
    // 于是把一个永远不可能成功的请求重试三遍。
    const bad = await request(app)
      .post('/api/fnthink/message')
      .set('Content-Type', 'application/json')
      .send('{"a":');
    expect(bad.status).toBe(statusCode(contract, 'badRequest'));
    expect(bad.body).toEqual({});
    // 对照：管理面同一类失败仍是它自己那套形状 ⇒ 两套错误契约没被并成一套
    const admin = await request(app)
      .post('/api/admin/login')
      .set('Content-Type', 'application/json')
      .send('{"a":');
    expect(admin.status).toBe(500);
    expect(admin.body.code).toBe(-5);
  });

  test('数字来自契约：实现里没有第二份字面量，且挂载顺序是"先公网、后管理面"', () => {
    expect(createFnthinkBodyLimit().max).toBe(MAX);
    const src = fs.readFileSync(path.join(__dirname, '../lib/app.js'), 'utf8');
    const fnthinkMount = src.indexOf("app.use('/api/fnthink', fnthinkBody.middlewares)");
    const globalMount = src.indexOf("app.use(express.json({ limit: '1mb' }))");
    expect(fnthinkMount).toBeGreaterThan(-1);
    expect(globalMount).toBeGreaterThan(-1);
    // 反了不报错，只会让公网面静默吃 1 MB —— 与本仓那个"桶分支必须排在通用 /api/ 之前"同族
    expect(fnthinkMount).toBeLessThan(globalMount);
    expect(src).not.toMatch(/\/api\/fnthink'[^)]*limit:/); // 上限不许在 app.js 里另写一份
    // ⚠ 只断言"解析出来的 max 等于契约值"**拦不住写死**：把 65536 硬编码进 bodylimit.js，
    // 它今天照样等于契约值 ⇒ 断言空转（这一条是被反证 M3 当场抓出来的）。所以要钉的是**来源**：
    // 数字必须是从契约里取的那个变量。
    const limSrc = fs.readFileSync(path.join(__dirname, '../lib/fnthink/bodylimit.js'), 'utf8');
    expect(limSrc).toMatch(/express\.json\(\{ limit: max \}\)/);
    expect(limSrc).not.toMatch(/limit:\s*\d/);
    expect(app.get('fnthinkBodyMaxBytes')).toBe(MAX);
  });

  test('读不到上限就抛，不许缺省成"不限"', () => {
    for (const bad of [undefined, 0, -5, 1024, '65536', NaN, null]) {
      expect(() => bodyMaxBytes({ limits: { requestBodyMaxBytes: bad } })).toThrow(/4096|整数/);
    }
    expect(bodyMaxBytes({ limits: { requestBodyMaxBytes: 65536 } })).toBe(65536);
  });
});
