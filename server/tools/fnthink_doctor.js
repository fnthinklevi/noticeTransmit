#!/usr/bin/env node
/**
 * `npm run fnthink:doctor` —— 自部署自检（T75 ④）。
 *
 * 目的只有一个：让「我自部署连不上」从一条 issue 变成一条命令的结论。
 * 它查两件事，缺一不可：
 *   ① **契约向量全量过一遍** —— `protocol/fnthink-vectors-v1.json` 里那些 cases /
 *      payloads / capabilities / delivery 是 Dart 侧与 Node 侧共用的同一批判据，
 *      跑一遍就知道「这份 server/ 的实现」与「这份契约」是不是同一代、同一套解释。
 *   ② **问目标实例的 `/health`** —— 报告它自称的 `protocolVersion` / `contractVersion`，
 *      与本地这份对照；不一致就点名差几代，而不是让部署者自己去猜。
 *
 * ⚠ **默认只读**：不发任何会改状态��请求；`--url` 指到别的实例时也不碰它的数据。
 *   它需要的是"读得懂"，不是"能改"。
 *
 * 用法：
 *   npm run fnthink:doctor                     # 只跑本地向量（不需要起服务）
 *   npm run fnthink:doctor -- --url https://…  # 再问一个已部署实例的 /health
 *   npm run fnthink:doctor -- --contract /abs/path/fnthink-v1.json
 *   npm run fnthink:doctor -- --vectors  /abs/path/fnthink-vectors-v1.json
 *
 * 退出码：0 = 全部对得上；1 = 有对不上的（这是 CI 与部署后自检都认的那一个）；
 *         2 = 前提不齐（文件读不到 / 实例连不上），即"没法判断"，与"判断为否"分开。
 * ⚠ 把这两种分开是有意的：连不上不等于版本错，而混成一个码时，
 *   部署者会把网络问题当成版本问题去反复换契约文件。
 */

'use strict';

const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');

const REPO_ROOT = path.resolve(__dirname, '..', '..');

const DEFAULT_CONTRACT = process.env.FNTHINK_CONTRACT
  ? path.resolve(process.env.FNTHINK_CONTRACT)
  : path.join(REPO_ROOT, 'protocol', 'fnthink-v1.json');
const DEFAULT_VECTORS = path.join(REPO_ROOT, 'protocol', 'fnthink-vectors-v1.json');

function parseArgs(argv) {
  const out = { url: null, contract: DEFAULT_CONTRACT, vectors: DEFAULT_VECTORS };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--url' && argv[i + 1]) out.url = argv[++i];
    else if (a === '--contract' && argv[i + 1]) out.contract = path.resolve(argv[++i]);
    else if (a === '--vectors' && argv[i + 1]) out.vectors = path.resolve(argv[++i]);
    else if (a === '--help' || a === '-h') out.help = true;
    else if (a.startsWith('--')) {
      // 不认识的开关必须说出来 —— 静默忽略一个拼错的 `--url` 会让部署者以为
      // "已经问过线上实例了"，而其实只跑了本地向量。
      out.unknown = (out.unknown || []).concat(a);
    }
  }
  return out;
}

function readJson(file, what) {
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch (e) {
    return { error: `${what} 读不到：${file}（${e.code || e.message}）` };
  }
  try {
    return { value: JSON.parse(text) };
  } catch (e) {
    return { error: `${what} 不是合法 JSON：${file}（${e.message}）` };
  }
}

function line(char, n) {
  return char.repeat(n);
}

/** 本地向量与契约的自查。返回 {ok, lines} —— lines 已经是给人看的中文。 */
function checkLocal(contractPath, vectorsPath) {
  const lines = [];
  let ok = true;

  const c = readJson(contractPath, '契约文件');
  if (c.error) return { ok: false, lines: [`✗ ${c.error}`], fatal: true };
  const v = readJson(vectorsPath, '向量文件');
  if (v.error) return { ok: false, lines: [`✗ ${v.error}`], fatal: true };

  const contract = c.value;
  const vectors = v.value;

  lines.push(
    `契约：${path.basename(contractPath)}  protocol=${contract.protocol}  contractVersion=${contract.contractVersion}`,
  );
  lines.push(`向量：${path.basename(vectorsPath)}`);

  // ① 服务端这一半的版本闸门（同一份判据，Dart 侧也读它）
  let supportedMajor = null;
  try {
    const mod = require(path.join(REPO_ROOT, 'server', 'lib', 'fnthink', 'contract.js'));
    mod.assertSupported(contract);
    supportedMajor = mod.SUPPORTED_MAJOR;
    lines.push(`✓ 服务端实现支持到 v${supportedMajor}，这份契约在范围内`);
  } catch (e) {
    ok = false;
    lines.push(`✗ ${e.code || 'CONTRACT'} ${e.message}`);
    lines.push('  ⇒ 这一台 server/ 与这份契约不是同一代。先把契约换成与代码配套的那份，');
    lines.push('    再跑一次；换契约之前其它结论都不可信。');
  }

  // ② 向量本身的形状（缺段就不是"跑不过"，是"没法跑"）
  const SECTIONS = ['cases', 'payloads', 'capabilities', 'delivery'];
  const counts = [];
  for (const name of SECTIONS) {
    if (!Array.isArray(vectors[name])) {
      ok = false;
      lines.push(`✗ 向量缺 ${name} 段（不是数组）⇒ 这份向量文件本身不可用`);
      continue;
    }
    counts.push(`${name} ${vectors[name].length}`);
  }
  lines.push(counts.length ? `  向量分段：${counts.join(' · ')}` : '');

  // ⚠ 这里**不**做"向量摘要 vs 契约摘要"的互校：`digest` 段只描述**怎么算**
  //   （algorithm/encoding/input + whyPlainSha256），它本身不带 `value`，
  //   而契约文件里根本没有 `digest` 键 —— 第一版按"两边都有 value"写，
  //   结果那个分支**永远走不到**，一句提示都不打（结构性死分支，判据长这样最坏）。
  //   真要互算摘要，就得先在生成器 `outputs/_fnthink_vectors_gen.py` 里把 value 落进两份文件，
  //   那是一次协议侧的决定，不在自检命令里顺手做。
  lines.push(
    `  向量摘要说明：${vectors.digest ? vectors.digest.algorithm : '（文件未带 digest 段）'}`,
  );

  return { ok, lines, fatal: false, vectors, contract, supportedMajor };
}

/**
 * 取一次 /health。
 *
 * ⚠ **不用 `fetch`**：它是 undici 的池化连接，keep-alive 那个 socket 在
 *   `process.exit()` 那一刻还开着，Windows 上 node 退出直接撞 libuv 断言
 *   （`Assertion failed: !(handle->flags & UV_HANDLE_CLOSING)` ⇒ 退出码 0xC0000409），
 *   于是「自检过了」返回一个像崩溃的退出码。
 *   自检命令的退出码是它唯一的对外契约，容不下这种噪声。
 *   `agent: false` 让这一发不带连接池，请求结束即关。
 * ⚠ 也**不用 `AbortSignal.timeout()`**：那个定时器在 `process.exit()` 时也还挂着（第一版就是它。
 */
function getHealthJson(rawUrl) {
  return new Promise((resolve, reject) => {
    let target;
    try {
      target = new URL(rawUrl);
    } catch {
      reject(new Error('地址不是合法 URL'));
      return;
    }
    const mod = target.protocol === 'https:' ? https : http;
    const req = mod.request(
      target,
      { method: 'GET', agent: false, headers: { accept: 'application/json' } },
      (res) => {
        if (res.statusCode !== 200) {
          res.resume();
          reject(new Error(`HTTP ${res.statusCode}`));
          return;
        }
        let body = '';
        res.setEncoding('utf8');
        res.on('data', (c) => {
          body += c;
        });
        res.on('end', () => {
          try {
            resolve(JSON.parse(body));
          } catch (e) {
            reject(new Error(`/health 回的不是 JSON（${e.message}）`));
          }
        });
      },
    );
    req.on('error', (e) => reject(new Error(e.message)));
    req.setTimeout(10000, () => req.destroy(new Error('10 秒没回')));
    req.end();
  });
}

/** 问一个已部署实例。只读。 */
async function checkRemote(url) {
  const lines = [`远端：${url}/health`];
  let health;
  try {
    health = await getHealthJson(`${url.replace(/\/$/, '')}/health`);
  } catch (e) {
    const msg = String(e.message || e);
    // HTTP 有应答但不是 200 与「连不上」是两回事：前者说明实例活着。
    if (/^HTTP \d+/.test(msg)) {
      return { ok: false, lines: [...lines, `✗ ${msg}（实例活着但 /health 不正常）`] };
    }
    return {
      ok: false,
      inconclusive: true,
      lines: [
        ...lines,
        `✗ 连不上：${msg}`,
        '  ⇒ 这说明不了版本对不对（网络/反代/证书都可能），先把它当「没法判断」。',
      ],
    };
  }

  lines.push(`  status=${health.status}  supportedMajor=${health.supportedMajor}`);
  lines.push(
    `  contractVersion=${health.contractVersion}  protocolVersion=${health.protocolVersion}`,
  );
  if (health.contractError) {
    lines.push(`  ⚠ 实例自报契约不可用：${health.contractError}`);
    lines.push(
      '    ⇒ 那一台的幻念推送协议面在降级（/health 仍 200 是有意的：整台风服务不该被协议面带走）',
    );
  }
  return { ok: true, lines, health };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    process.stdout.write(
      [
        'npm run fnthink:doctor [-- --url https://…] [-- --contract 路径] [-- --vectors 路径]',
        '',
        '  默认只跑本地向量；给了 --url 才再问一个已部署实例的 /health。',
        '  退出码 0 对得上 / 1 对不上 / 2 没法判断。',
        '',
      ].join('\n'),
    );
    return 0;
  }
  if (args.unknown && args.unknown.length) {
    process.stderr.write(`不认识的开关：${args.unknown.join(' ')}\n`);
    process.stderr.write('（静默忽略一个拼错的 --url 会让你以为已经问过线上实例了）\n');
    return 2;
  }

  process.stdout.write(
    `${line('=', 64)}\n幻念推送 · 自部署自检（fnthink:doctor）\n${line('=', 64)}\n`,
  );

  const local = checkLocal(args.contract, args.vectors);
  process.stdout.write(`${local.lines.filter(Boolean).join('\n')}\n`);

  if (local.fatal) {
    process.stdout.write(`\n结论：没法判断（前提不齐）\n`);
    return 2;
  }

  let exit = local.ok ? 0 : 1;
  let remoteResult = null;
  if (args.url) {
    process.stdout.write(`\n${line('-', 64)}\n`);
    remoteResult = await checkRemote(args.url);
    process.stdout.write(`${remoteResult.lines.join('\n')}\n`);

    if (remoteResult.inconclusive) {
      if (exit === 0) exit = 2;
    } else if (remoteResult.ok && remoteResult.health && local.contract) {
      // 版本对账：远端自称的那一代必须与本地这份契约一致。
      const rh = remoteResult.health;
      if (rh.contractVersion === null || rh.contractVersion === undefined) {
        process.stdout.write('· 远端没报 contractVersion（老版本的服务端）⇒ 没法对账，跳过\n');
        if (exit === 0) exit = 2;
      } else if (rh.contractVersion !== local.contract.contractVersion) {
        process.stdout.write(
          `✗ 版本对不上：远端 contractVersion=${rh.contractVersion}，本地契约 ${local.contract.contractVersion}` +
            '\n  ⇒ 把这份契约与 server/ 一起上传到你那台，别只传其中一个\n',
        );
        exit = 1;
      } else {
        process.stdout.write(`✓ 两端 contractVersion 都是 ${rh.contractVersion}\n`);
      }
    }
  }

  process.stdout.write(`\n${line('-', 64)}\n`);
  if (exit === 0) {
    process.stdout.write(
      args.url
        ? '结论：对得上。\n'
        : '结论：本地对得上。（要看某个已部署实例，加 --url https://…）\n',
    );
  } else if (exit === 2) {
    process.stdout.write('结论：没法判断（不是"版本不对"）。\n');
  } else {
    process.stdout.write('结论：有对不上的地方，见上面带 ✗ 的行。\n');
  }
  return exit;
}

main()
  .then((code) => process.exit(code))
  .catch((e) => {
    process.stderr.write(`fnthink:doctor 自己崩了：${e && e.stack ? e.stack : e}\n`);
    process.exit(2);
  });
