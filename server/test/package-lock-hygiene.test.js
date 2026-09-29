'use strict';

/**
 * `package-lock.json` 的卫生判据（2026-09-29 那次服务器上 `npm ci` 直接 EALLOWREMOTE 换来的）。
 *
 * 成因不是服务器配错：lock 是在某台把 registry 指到镜像的机器上生成的，于是 **468 条 `resolved`
 * 带着那台机器的镜像主机**进了清单。npm 11 的默认 `replace-registry-host=npmjs` 只改写
 * `registry.npmjs.org` 的主机 —— 镜像主机既不被改写、也不等于新机配置的 registry，
 * 就被判成 remote tarball 直接拒：`Refusing to fetch "yargs-parser@https://mirrors.cloud.tencent.com/…"`。
 *
 * 这一类缺陷的形状是「**生成物里带着生成它的那台机器的配置**」：换一台机器才现形，本机永远绿。
 * 所以这里断的是清单本身，而不是任何一机的 npm 配置。
 *
 * ⚠ 本文件**不许 require `../lib/app`**：那条路会走到 `lib/store.js` 的
 * `ADMIN_TOKEN_HASH` 缺失 ⇒ `process.exit(1)`，把 jest worker 整个打死（CI 上只留下
 * "Jest worker encountered N child process exceptions"，真因被盖掉）。这里只读两个 JSON 文件。
 */

const fs = require('fs');
const path = require('path');

const LOCK = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'package-lock.json'), 'utf8'));
const PKG = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf8'));

/** 唯一允许的 tarball 来源：官方 registry 的 https。镜像/私有源/明文/`file:` 都不算。 */
const CANONICAL_HOST = 'registry.npmjs.org';

/**
 * 违规提取器 —— 判据只有这一处（host 与 scheme 各抄一份就会分叉）。
 * 返回 `[]` 之外的东西都带 key、resolved 与**是哪一条判据**，让红灯能点名到包。
 * 读不懂的 resolved（不是 URL）也算违规：不许把异常当"通过"。
 */
function violations(entries) {
  const out = [];
  for (const [key, v] of entries) {
    let url;
    try {
      url = new URL(v.resolved);
    } catch (e) {
      out.push({ key, resolved: v.resolved, rule: '不是能解析的 URL' });
      continue;
    }
    if (url.host !== CANONICAL_HOST)
      out.push({ key, resolved: v.resolved, rule: '主机不是官方 registry' });
    if (url.protocol !== 'https:') out.push({ key, resolved: v.resolved, rule: '不是 https' });
  }
  return out;
}

function withResolved() {
  return Object.entries(LOCK.packages || {}).filter(
    ([, v]) => v && typeof v === 'object' && typeof v.resolved === 'string',
  );
}

function onlyRule(list, rule) {
  return list.filter((x) => x.rule === rule).map((x) => `${x.key} → ${x.resolved}`);
}

describe('package-lock 的卫生（防"生成物带着本机配置"）', () => {
  test('lockfileVersion 必须是 3 且不留 legacy `dependencies` 段（两种真值来源就别留着）', () => {
    expect(LOCK.lockfileVersion).toBeGreaterThanOrEqual(3);
    expect(Object.prototype.hasOwnProperty.call(LOCK, 'dependencies')).toBe(false);
  });

  test('每条 resolved 的主机都是官方 registry（镜像主机换台机器就 EALLOWREMOTE）', () => {
    const list = withResolved();
    expect(list.length).toBeGreaterThan(0); // 空清单不算通过：提取器失效时它只会变绿
    expect(onlyRule(violations(list), '主机不是官方 registry')).toEqual([]);
  });

  test('resolved 必须是 https（明文镜像不因"有哈希兜底"就放过——链路上可被观察）', () => {
    expect(onlyRule(violations(withResolved()), '不是 https')).toEqual([]);
  });

  test('有 resolved 就必须有 integrity：换主机不换来路的前提是哈希在那儿', () => {
    const found = withResolved()
      .filter(([, v]) => !v.integrity)
      .map(([k, v]) => `${k} → ${v.resolved}`);
    expect(found).toEqual([]);
  });

  test('清单头部的 name/version 与 package.json 一致（不一致 = lock 不是这份 package.json 生成的）', () => {
    expect(LOCK.name).toBe(PKG.name);
    expect(LOCK.version).toBe(PKG.version);
    expect(LOCK.packages[''].name).toBe(PKG.name);
    expect(LOCK.packages[''].version).toBe(PKG.version);
  });

  test('提取器自己认得两类违规（自测：判据不认违规就等于没有守卫）', () => {
    const fake = [
      ['node_modules/a', { resolved: 'https://mirrors.example.net/npm/a/-/a-1.0.0.tgz' }], // 主机违规
      ['node_modules/b', { resolved: 'http://registry.npmjs.org/b/-/b-1.0.0.tgz' }], // 主机对、明文
      ['node_modules/c', { resolved: 'not-a-url' }], // 读不懂
      ['node_modules/d', { resolved: 'https://registry.npmjs.org/d/-/d-1.0.0.tgz' }], // 合规
    ];
    const found = violations(fake);
    expect(found.map((x) => `${x.key}｜${x.rule}`)).toEqual([
      'node_modules/a｜主机不是官方 registry',
      'node_modules/b｜不是 https',
      'node_modules/c｜不是能解析的 URL',
    ]);
    // 合规那条一条都不许报：否则这守卫会因为噪声被人关掉
    expect(found.some((x) => x.key === 'node_modules/d')).toBe(false);
  });
});
