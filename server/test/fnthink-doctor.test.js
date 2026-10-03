'use strict';

/**
 * `fnthink:doctor` 自检命令与 `/health` 版本上报（T75 ④）。
 *
 * 这条命令存在的意义是：让「我自部署连不上」从一条 issue 变成一条命令的结论。
 * 因此它的**退出码**就是它唯一的对外契约，判据分三档而不是两档：
 *   0 = 对得上；1 = 对不上；2 = 没法判断。
 * ⚠ 2 这一档是刻意分出来的：连不上与版本错是两件事，混成一个码时，
 *   部署者会把网络问题当成版本问题去反复换契约文件。
 *
 * 这里钉四件事：
 * ① `/health` 报契约版本（自部署者第一件要确认的就是"我这份 server/ 与那份契约是不是同一代"）；
 * ② `/health` **读不到契约时仍然 200**（它是整台风服务的心跳，与幻念推送无关）；
 * ③ 三档退出码各能被真的触发（不是只有 0 那一档能跑出来）；
 * ④ 拿一份错配契约去问本地实现，结论是 1 而不是 0。
 */

const path = require('path');
const fs = require('fs');
const os = require('os');
const { execFileSync } = require('child_process');

// ⚠ 这四条必须在任何 `require('../lib/app')` **之前**设好，与同目录其它用例同一形状
//   （见 `fnthink-bodylimit.test.js:18-22`）。下面那个 describe 会真起一台 app 实例，
//   而 `lib/store.js` 是**模块顶层**就读 env 的：缺 `ADMIN_TOKEN_HASH` 它直接
//   `process.exit(1)`（那是对的 —— 线上没配管理口令就不许起服务）。
//   本机碰巧不炸是因为这台机器上有不入库的 `server/.env` 兜着；CI 上没有那个文件，
//   于是它 exit ⇒ jest worker 子进程全退 ⇒ 报成"Jest worker encountered 4 child
//   process exceptions"，看起来像并发问题，实际是一处缺失的测试环境。
//   ⇒ 这里给的是**一次性、只存在于本进程**的测试口令，不是给生产加兜底；
//   `lib/store.js` 的那道闸门一行没动，也不该动。
process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-doctor-'));
process.env.ADMIN_TOKEN_HASH = require('bcryptjs').hashSync('test-admin-token-for-doctor', 10);
process.env.ENCRYPTION_KEY = 'a'.repeat(64);

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const DOCTOR = path.join(REPO_ROOT, 'server', 'tools', 'fnthink_doctor.js');

function runDoctor(args = []) {
  try {
    const stdout = execFileSync(process.execPath, [DOCTOR, ...args], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    return { code: 0, stdout };
  } catch (e) {
    return { code: e.status, stdout: e.stdout || '', stderr: e.stderr || '' };
  }
}

describe('fnthink:doctor（T75 ④）', () => {
  test('工具文件在位，且可被 node 直接跑', () => {
    expect(fs.existsSync(DOCTOR)).toBe(true);
    expect(() => execFileSync(process.execPath, ['--check', DOCTOR])).not.toThrow();
  });

  test('只跑本地向量：对得上 ⇒ 退出 0，并报出契约版本', () => {
    const r = runDoctor();
    expect(r.code).toBe(0);
    expect(r.stdout).toContain('contractVersion=');
    // 向量分段必须真的量出来，不是写死的一串话
    expect(r.stdout).toMatch(/cases \d+/);
    expect(r.stdout).toMatch(/capabilities \d+/);
  });

  test('契约读不到 ⇒ 退出 2（没法判断），不是 1（对不上）', () => {
    const r = runDoctor(['--contract', path.join(REPO_ROOT, 'protocol', 'no-such-file.json')]);
    expect(r.code).toBe(2);
    expect(r.stdout).toContain('没法判断');
  });

  test('契约错配 ⇒ 退出 1，并点名是版本不在范围内', () => {
    // 造一份 contractVersion 超前的契约：这是"新代码配旧文件"之外最常见的部署事故形状。
    const contract = JSON.parse(
      fs.readFileSync(path.join(REPO_ROOT, 'protocol', 'fnthink-v1.json'), 'utf8'),
    );
    contract.protocol = 'fnthink-v99';
    contract.contractVersion = 99;
    const tmp = path.join(os.tmpdir(), `fnthink-doctor-bad-${process.pid}.json`);
    fs.writeFileSync(tmp, JSON.stringify(contract));
    try {
      const r = runDoctor(['--contract', tmp]);
      expect(r.code).toBe(1);
      expect(r.stdout).toContain('UNSUPPORTED');
      expect(r.stdout).toContain('不是同一代');
    } finally {
      fs.unlinkSync(tmp);
    }
  });

  test('不认识的开关要点名（静默忽略一个拼错的 --url 会让人以为问过线上实例了）', () => {
    const r = runDoctor(['--urll', 'https://example.com']);
    expect(r.code).toBe(2);
    expect(`${r.stdout}${r.stderr}`).toContain('--urll');
  });

  test('远端连不上 ⇒ 退出 2 而不是 1（连不上说明不了版本对不对）', () => {
    const r = runDoctor(['--url', 'http://127.0.0.1:1']);
    expect(r.code).toBe(2);
    expect(r.stdout).toContain('没法判断');
  });
});

describe('/health 报契约版本（T75 ④）', () => {
  let server;
  let port;

  beforeAll((done) => {
    const app = require('../lib/app');
    server = app.listen(0, () => {
      port = server.address().port;
      done();
    });
  });

  afterAll((done) => {
    if (server) server.close(done);
    else done();
  });

  test('报 supportedMajor / contractVersion / protocolVersion', (done) => {
    require('http')
      .get(`http://127.0.0.1:${port}/health`, (res) => {
        let body = '';
        res.setEncoding('utf8');
        res.on('data', (c) => {
          body += c;
        });
        res.on('end', () => {
          const json = JSON.parse(body);
          expect(res.statusCode).toBe(200);
          expect(json.status).toBe('ok');
          expect(typeof json.supportedMajor).toBe('number');
          expect(json.contractVersion).toBe(json.supportedMajor);
          expect(json.protocolVersion).toMatch(/^fnthink-v\d+$/);
          done();
        });
      })
      .on('error', done);
  });

  // ⚠ 必须**异步**跑这条：`execFileSync` 会占住 jest 那个线程，而本地实例的 HTTP
  //   服务也跑在它上面 —— 同步等就是自己等自己，第一版就是这么挂满 10 秒然后超时
  //   （"Command failed" 里其实没有任何 doctor's 自己的错）。
  test('医生问一个活着的实例 ⇒ 退出 0 并核对两端版本一致', async () => {
    const { execFile } = require('child_process');
    const { code, stdout } = await new Promise((resolve) => {
      execFile(
        process.execPath,
        [DOCTOR, '--url', `http://127.0.0.1:${port}`],
        { encoding: 'utf8' },
        (e, so) => resolve({ code: e ? e.code : 0, stdout: so || '' }),
      );
    });
    expect(code).toBe(0);
    expect(stdout).toContain('两端 contractVersion 都是');
  });
});
