// T155：客户端契约版本的**关联键**（`contractVersion` ↔ 服务器那份）。
//
// 要抓的是一件事：**只上传了 server/、protocol/ 里还是上一批那份**。
// 那份部署的第一个症状不是崩溃，是"一切照常，只是有几条消息发不出去" ——
// 于是它能一直挂着。本文件钉的三条就是让它**可见**的那三格。
//
// ⚠ 三条纪律来自一次真实回归（第一版把收件箱放在 `fnthink/routes.js`，
//   `/health` 那边去 require 它 ⇒ `routes.js` 顶层读契约 `alerts` 段 ⇒
//   旧契约部署下崩在 `app.js` 的 try/catch 之外，把 A1 修好的
//   「只降级协议面、更新面照常」从背后绕过去）。
//   第三条守卫就是那次回归的墓碑 —— 它红过一次，不许它再绿回去。

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-ver-echo-'));
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-version-echo', 10);
process.env.ENCRYPTION_KEY = 'e'.repeat(64);

const request = require('supertest');

const contractModule = require('../lib/fnthink/contract');
const versionEcho = require('../lib/fnthink/version_echo');
const contract = contractModule.assertSupported(contractModule.loadContract());
const { field, healthKey } = contractModule.versionEchoSpec(contract);
const app = require('../lib/app');

beforeEach(() => versionEcho.reset());

describe('契约版本关联键', () => {
  test('键名两侧都从契约读，不许各写一个字面量', () => {
    expect(typeof field).toBe('string');
    expect(field.length).toBeGreaterThan(0);
    expect(typeof healthKey).toBe('string');
    expect(healthKey).not.toBe(field);
    // ⚠ 这里只能断**本侧**的读口：Dart 侧那个（`contract.versionEchoField`）
    //   要在 `test/services/fnthink_receiver_service_test.dart` 里断 ——
    //   JS 侧引用一个只有 Dart 才有的属性，测出来的是"我敲错了一个名字"。
    //   两侧读的是契约 `versionEcho` 同一段；跨语言那一半由 Dart 那条用例钉。
    expect(contract.versionEcho.field).toBe(field);
    expect(contract.versionEcho.healthKey).toBe(healthKey);
    expect(contract.versionEcho.reportOn).toBe('/health');
  });

  test('没收到过任何带版本的请求 ⇒ /health 回 null（不是 false）', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body[healthKey]).toBeNull();
  });

  test('三档分得开：不一致 / 读不出来 / 一致，不折成同一个值', async () => {
    // 一致：直接喂收件箱，不走 HTTP —— 这条测的是判据本身。
    versionEcho.note(
      contractModule.compareClientContractVersion(contract, { [field]: contract.contractVersion }),
      1,
    );
    expect(versionEcho.read()).toEqual({ verdict: 'match' });

    // 不一致：客户端报一个别的数。
    versionEcho.note(
      contractModule.compareClientContractVersion(contract, {
        [field]: contract.contractVersion + 7,
      }),
      contract.contractVersion + 7,
    );
    expect(versionEcho.read()).toEqual({ verdict: 'mismatch' });

    // 读不出来：带了但不是可比的形状。折进 mismatch 就与"客户端在说谎"同形了。
    versionEcho.note(contractModule.compareClientContractVersion(contract, { [field]: '1' }), '1');
    expect(versionEcho.read()).toEqual({ verdict: 'unreadable' });
  });

  test('老客户端不带这一格 ⇒ 不算不一致（它压根不知道有这回事）', () => {
    expect(contractModule.compareClientContractVersion(contract, {})).toBe('match');
    expect(contractModule.compareClientContractVersion(contract, undefined)).toBe('match');
    expect(contractModule.compareClientContractVersion(contract, { [field]: null })).toBe('match');
  });

  test('收件箱只回 verdict，不把客户端自报的值原样吐出去', () => {
    versionEcho.note('mismatch', { evil: 'payload' });
    expect(versionEcho.read()).toEqual({ verdict: 'mismatch' });
    expect(JSON.stringify(versionEcho.read())).not.toContain('evil');
  });

  // ── 那次回归的墓碑 ──────────────────────────────────────────────────────
  //
  // ⚠ 第一版把收件箱放在 `fnthink/routes.js`，`lib/routes/version.js` 去 require 它。
  //   `routes.js` 的**模块顶层**要构造 `createSenderQuota()`，而那一构造读契约的
  //   `alerts` 段 ⇒ 「protocol/ 是上一批那份」的部署下，`version.js` 崩在启动，
  //   `/health` 与整个更新面一起死 —— 而 A1 那次事故修好的口径恰恰是"只降级协议面"。
  //
  // ⚠ 判据是**行为**（旧契约下 `/health` 仍 200），不是"某个文件不许 require 某个文件"：
  //   后者会把重构也拦下来（那个依赖未必永远不正当），而前者正是那次事故的口径本身。
  test('旧契约部署下 /health 仍然活着（收件箱不许把降级机制绕过去）', () => {
    const stale = { ...contract };
    delete stale.alerts;
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-ver-echo-stale-'));
    const file = path.join(dir, 'fnthink-v1.json');
    fs.writeFileSync(file, JSON.stringify(stale));
    // ⚠ 必须另起一个进程：契约路径在 `contract.js` 模块加载时就定下来了，
    //   同一进程里改 FNTHINK_CONTRACT 等于没改（这正是这份部署文档一路在防的形状）。
    const { spawnSync } = require('child_process');
    const script = `
      process.env.NODE_ENV='test'; process.env.PORT='0';
      process.env.DATA_DIR=require('fs').mkdtempSync(require('path').join(require('os').tmpdir(),'nt-ve-'));
      process.env.ADMIN_TOKEN_HASH=require('bcryptjs').hashSync('t',10);
      process.env.ENCRYPTION_KEY='e'.repeat(64);
      process.env.FNTHINK_CONTRACT=${JSON.stringify(file)};
      const request=require('supertest'); const app=require(${JSON.stringify(require.resolve('../lib/app'))});
      request(app).get('/health').then(r=>{
        process.stdout.write(JSON.stringify({status:r.status,body:r.body}));
        process.exit(0);
      }).catch(e=>{process.stdout.write(JSON.stringify({error:String(e)}));process.exit(1);});
    `;
    const out = spawnSync(process.execPath, ['-e', script], { encoding: 'utf8' });
    const parsed = JSON.parse(out.stdout);
    expect(parsed.error).toBeUndefined();
    expect(parsed.status).toBe(200);
    expect(parsed.body[healthKey]).toBeNull();
  });
});
