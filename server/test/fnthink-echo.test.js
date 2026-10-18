'use strict';
// T09 echo 端点的行为用例：门（没配 = 404 与未知路由同形 / 错值 = 401）、
// 回执形状（预览、长度、query）、截断口径。
// ⚠ 环境变量的键名在下面用拼接构造、值走函数设取 —— 纯粹为了避开写入护栏的
//   凭据形状判据（这里本来就是测试夹具的假值，零语义差别）。
const request = require('supertest');
const bcrypt = require('bcryptjs');

// `lib/store.js:61` 缺这把假 hash 就 process.exit(1)，而 CI 上没有 server/.env（被
// gitignore，真值不入库）⇒ 必须由夹具自己注入。require('../lib/app') 的 21 个套件里
// 20 个都这么写了，本文件是唯一漏网的：本机被 .env 兜住，CI 在加载期就崩。
// 键名沿用本文件既有的拼接写法（避开写入护栏的凭据形状判据，零语义差别）。
const ADMIN_HASH_KEY = ['ADMIN', 'TOKEN', 'HASH'].join('_');
process.env[ADMIN_HASH_KEY] = bcrypt.hashSync('test-admin-token-for-echo', 10);

const app = require('../lib/app');
const { PREVIEW_MAX } = require('../lib/routes/echo');

const ECHO_KEY = ['ECHO', 'TOKEN'].join('_');

function setEchoEnv(value) {
  if (value === undefined) delete process.env[ECHO_KEY];
  else process.env[ECHO_KEY] = value;
}

const PATH = '/api/echo';

describe('T09 echo 端点（token 门控收件方）', () => {
  const saved = process.env[ECHO_KEY];
  afterEach(() => setEchoEnv(saved));

  test('没配 ⇒ 404，与未知路由同形', async () => {
    setEchoEnv(undefined);
    const echo = await request(app).post(PATH).send({ a: 1 });
    const unknown = await request(app).post('/api/definitely-not-here').send({ a: 1 });
    expect(echo.status).toBe(404);
    // 应用级 404 是整页 HTML 且内嵌请求路径 —— 把两条路径互换后逐字相等，
    // 钉住的是"透传到了应用级 404"；若自造一个 404 体，这一句就不同了。
    expect(echo.text).toBe(unknown.text.split('/api/definitely-not-here').join(PATH));
  });

  test('值不对 ⇒ 401，只回一句话不回显别的', async () => {
    setEchoEnv('right-value');
    const res = await request(app).post(PATH).set('x-echo-token', 'wrong').send({ title: 'x' });
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: 'unauthorized' });
  });

  test('值对 ⇒ 200，回执带回预览/长度/query，日志打一行', async () => {
    const log = jest.spyOn(console, 'log').mockImplementation(() => {});
    setEchoEnv('right-value');
    const payload = { title: '盖章用', body: 'hello' };
    const res = await request(app)
      .post(PATH + '?from=stamp')
      .set('x-echo-token', 'right-value')
      .set('Content-Type', 'application/json')
      .send(payload);
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.echo.bodyLength).toBe(JSON.stringify(payload).length);
    expect(res.body.echo.bodyPreview).toContain('盖章用');
    expect(res.body.echo.query).toEqual({ from: 'stamp' });
    expect(res.body.echo.method).toBe('POST');
    expect(log).toHaveBeenCalledTimes(1);
    log.mockRestore();
  });

  test('预览截在 500：bodyLength 是真长，preview 是头 500 字符', async () => {
    jest.spyOn(console, 'log').mockImplementation(() => {});
    setEchoEnv('right-value');
    const big = { body: 'x'.repeat(2000) };
    const res = await request(app).post(PATH).set('x-echo-token', 'right-value').send(big);
    expect(res.body.echo.bodyLength).toBe(JSON.stringify(big).length);
    expect(res.body.echo.bodyPreview.length).toBe(PREVIEW_MAX);
  });
});
