// poll 的字段名单（`clientEvents.poll.messageFields`）与这台实现能投影出来的那几列对不上时，
// 必须是**装载即抛的可降级 SHAPE**，而不是"第一条带货的 poll 冒 500"、更不是"那一列静默地空着"。
//
// 这条口径的出处是 #130-A4（旧契约配新代码崩在启动、连带拖死 /api/version 那次归入可降级），
// "崩启动 vs 降级一段"的端到端证据在 fnthink-contract-shape.test.js，本文件只钉取数处打的类别。
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
// 装载 routes 会连带 require 到 store/devicestore：盘路径必须落在临时目录，
// 不能是真在跑的那份数据（本文件不写数据，但"顺手 require 了生产目录"这种事故本仓有过）。
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-poll-fields-data-'));
process.env.ENCRYPTION_KEY = 'a'.repeat(64);
// store.js 在没有 ADMIN_TOKEN_HASH 时是直接 process.exit(1)：这里不登录，但必须有它
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-poll-fields', 10);

const repoContract = JSON.parse(
  fs.readFileSync(path.join(__dirname, '../../protocol/fnthink-v1.json'), 'utf8'),
);
const originalContractPath = process.env.FNTHINK_CONTRACT;

afterAll(() => {
  // 别让本文件的夹具契约留在这台 worker 的环境里（下一批用例读到的就该是仓库那份）。
  if (originalContractPath === undefined) delete process.env.FNTHINK_CONTRACT;
  else process.env.FNTHINK_CONTRACT = originalContractPath;
});

/// 用一份改过的契约重新装载 routes（契约路径与模块都在 jest 的掌控下）。
function loadRoutesWith(mutate) {
  const raw = JSON.parse(JSON.stringify(repoContract));
  mutate(raw);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-poll-fields-'));
  const file = path.join(dir, 'fnthink-v1.json');
  fs.writeFileSync(file, JSON.stringify(raw));
  jest.resetModules();
  process.env.FNTHINK_CONTRACT = file;
  return () => require('../lib/fnthink/routes');
}

function shapeErr(load) {
  try {
    load();
    return null;
  } catch (e) {
    return e;
  }
}

describe('clientEvents.poll.messageFields 与实现对不上 ⇒ 装载即抛', () => {
  test('名单里有一个投影不出来的名字 ⇒ SHAPE（不是回一个空值）', () => {
    const load = loadRoutesWith((raw) => {
      // dedupeIdDigest 在盘上是**摘要**，设备拿它做不了任何事，而"幂等覆盖"要靠的是原值：
      // 把它抄进名单正是那种"看起来是名单里该有的一个"的错。
      raw.clientEvents.poll.messageFields = ['messageId', 'type', 'dedupeIdDigest'];
    });
    const err = shapeErr(load);
    expect(err).not.toBeNull();
    expect(err.code).toBe('FNTHINK_CONTRACT_SHAPE');
    expect(err.message).toMatch(/dedupeIdDigest/);
  });

  test('名单缺失（上一批那份契约）⇒ SHAPE，且消息里点名 messageFields', () => {
    const load = loadRoutesWith((raw) => {
      delete raw.clientEvents.poll.messageFields;
    });
    const err = shapeErr(load);
    expect(err).not.toBeNull();
    expect(err.code).toBe('FNTHINK_CONTRACT_SHAPE');
    expect(err.message).toMatch(/messageFields/);
  });

  test('空名单同样不算"就回空对象"：那是契约内容不达标', () => {
    const load = loadRoutesWith((raw) => {
      raw.clientEvents.poll.messageFields = [];
    });
    expect(shapeErr(load)).not.toBeNull();
  });

  test('正向：仓库这份契约装载得起来，名单里确实带 sender（收件表那一行的归属）', () => {
    const load = loadRoutesWith(() => {});
    expect(shapeErr(load)).toBeNull();
    const fields = repoContract.clientEvents.poll.messageFields;
    expect(fields).toContain('messageId');
    expect(fields).toContain('sender');
  });
});
