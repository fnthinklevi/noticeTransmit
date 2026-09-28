// 契约"内容不达标"必须只降级那一段，而不是把整台服务拖死（#130-A4 顺手对齐的一处不一致）。
//
// 形状与线上完全一致：只上传了 server/ 而 protocol/ 里还是上一批那份 ⇒ 新代码读不到新加的键。
// A1 当时写进部署口径的是"协议面降级 503，更新面与管理面不受影响"，而代码走的是**崩在启动**
// （windowsFor 抛的是普通 Error，lib/app.js 那道 catch 只咽 MISSING/UNPARSEABLE/UNSUPPORTED）。
// 这一片加 alerts 段时把它逼了出来 ⇒ 补了第四类标记 CONTRACT_SHAPE。这个文件就是那条口径的证据。
//
// ⚠ 必须在 require('../lib/app') **之前**设 FNTHINK_CONTRACT：契约路径在 contract.js 模块加载时
//   就定下来了，晚设等于没设（而那类"设了但没生效"的表现正是这份部署文档一路在防的东西）。

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-stale-'));
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-stale', 10);
process.env.ENCRYPTION_KEY = 'd'.repeat(64);

const repoContract = JSON.parse(
  fs.readFileSync(path.join(__dirname, '../../protocol/fnthink-v1.json'), 'utf8'),
);
// 只删掉实现新读的那一段：其余部分照旧有效（协议名、版本、limits 全在），
// 所以走的确实是"内容不达标"这一类，不是"文件坏了"那一类。
const stale = { ...repoContract };
delete stale.alerts;
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-contract-'));
const staleFile = path.join(dir, 'fnthink-v1.json');
fs.writeFileSync(staleFile, JSON.stringify(stale));
process.env.FNTHINK_CONTRACT = staleFile;

const request = require('supertest');
const app = require('../lib/app');

describe('旧契约配新代码（只降级那一段）', () => {
  test('协议面降级为契约里那三个专属响应之一：503 + fnthink_protocol_unavailable', async () => {
    const res = await request(app).post('/api/fnthink/poll').send({});
    expect(res.status).toBe(503);
    expect(res.body.error).toBe('fnthink_protocol_unavailable');
  });

  test('与幻念推送毫无关系的更新面照常活着（这才是"崩在启动"与"降级一段"的分别）', async () => {
    const health = await request(app).get('/health');
    expect(health.status).toBe(200);
    const check = await request(app)
      .get('/api/version/check')
      .query({ version: '1.5.76', build: '116', channel: 'default' });
    expect(check.status).toBeLessThan(500);
    expect(check.body.code).toBeDefined();
  });

  test('管理面也照常应答（未登录是 401，不是连整个进程都没起来）', async () => {
    const res = await request(app).get('/api/admin/fnthink/alerts');
    expect(res.status).toBe(401);
  });

  test('启动清单里一条幻念端点都没有：横幅不许报"开了"而其实没开', () => {
    expect(app.get('fnthinkEndpoints')).toEqual([]);
  });

  test('抛的确实是可降级那一类（而不是被 catch 无条件咽掉）', () => {
    jest.resetModules();
    const { alertsFromContract } = require('../lib/fnthink/anomaly');
    const { isContractAvailabilityError, CONTRACT_SHAPE } = require('../lib/fnthink/contract');
    let err = null;
    try {
      alertsFromContract(stale);
    } catch (e) {
      err = e;
    }
    expect(err).not.toBeNull();
    expect(err.code).toBe(CONTRACT_SHAPE);
    expect(isContractAvailabilityError(err)).toBe(true);
    // 反向钉：代码 bug 不属于这一类，绝不能被那道 catch 咽成"协议不可用"
    const bug = new ReferenceError('x is not defined');
    expect(isContractAvailabilityError(bug)).toBe(false);
  });
});
