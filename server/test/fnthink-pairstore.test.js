// 配对请求表（#131 第二片 2B）：`pair` 那一步留下的"等 A 确认"记录。
//
// 这张表存在的全部理由都在这批用例里，所以每条盯的都是"改坏了不会报错"的那一类：
//  ① 明文口令一个字节都不许落盘（只有摘要）—— 它被抄过、印在二维码里、可能被拍过照；
//  ② 到上限只拒新的，**绝不挤掉已经 pending 的那条**（A 屏幕上那张二维码还等着它）；
//  ③ 取货只看自己的（target 必须等于本机）且**显式挑字段**：多一个内部键就是多一次泄露；
//  ④ TTL / 状态名 / 响应键名全部从契约读：写死的那份在契约改名那天不会报错，只会读不到。
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-pairstore', 10);
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-pairstore-'));

const { loadContract, assertSupported } = require('../lib/fnthink/contract');
const { credentialDigest, lengthFromContract } = require('../lib/fnthink/credentials');
const pairstore = require('../lib/fnthink/pairstore');

const contract = assertSupported(loadContract());
const NOW = 1800000000000;
const A = '8K3FJ6QPTM9WZ4VHNS';
const B = '7YD4RKQPBM8XZ3VHNT';

function freshCode() {
  // 用真口令的形状（20 位 Crockford），这样"值长得像口令"那条落盘闸门也一起被测到。
  const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  let out = '';
  for (let i = 0; i < lengthFromContract(contract, 'pairingCode'); i += 1) {
    out += alphabet[crypto.randomBytes(1)[0] % alphabet.length];
  }
  return out.toUpperCase();
}

const digestOf = (code) => credentialDigest(contract, 'pairingCode', code);

function input(over) {
  return Object.assign(
    {
      target: A,
      requester: B,
      requesterPublicKey: crypto.randomBytes(32).toString('base64'),
      level: 'L1',
      codeDigest: digestOf(freshCode()),
    },
    over || {},
  );
}

describe('pairRequest 表（#131 2B）', () => {
  beforeEach(() => {
    // 每张用例都从空表开始：上一轮的残留既能假红也能靠它假绿。
    if (fs.existsSync(pairstore.REQUEST_FILE)) fs.rmSync(pairstore.REQUEST_FILE);
  });

  test('建一条就真落盘一次，且状态名与 TTL 都来自契约', () => {
    const requests = pairstore.loadRequests();
    const created = pairstore.createRequest(contract, requests, input(), NOW);
    expect(created.ok).toBe(true);
    const ttlSeconds = contract.identity.pairingCode.ttlSeconds;
    expect(created.request.status).toBe(contract.pairRequest.initialStatus);
    expect(created.request.expiresAt).toBe(NOW + ttlSeconds * 1000);
    // 重新读盘：只在内存里那条等于没存（重启后 A 看不见任何待确认请求）。
    const again = pairstore.loadRequests();
    expect(Object.keys(again)).toEqual([created.request.id]);
  });

  test('明文口令进不了这张表：落盘咽喉把"值是一把形状完整的口令"也拦下', () => {
    const code = freshCode();
    const requests = pairstore.loadRequests();
    expect(() =>
      pairstore.saveRequests(
        Object.assign({}, requests, {
          pr_leak: Object.assign(input(), { pairingCode: code }),
        }),
      ),
    ).toThrow(/明文凭证|形状完整的口令/);
    // 键名干净、只把口令塞进别的名目下 —— 同一条闸门也拦得住（值不会说谎）。
    expect(() =>
      pairstore.saveRequests(
        Object.assign({}, requests, { pr_leak: Object.assign(input(), { note: code }) }),
      ),
    ).toThrow(/形状完整的口令/);
  });

  test('落盘的只有摘要：整份文件里找不到那枚口令的一个连续片段', () => {
    const code = freshCode();
    const requests = pairstore.loadRequests();
    pairstore.createRequest(contract, requests, input({ codeDigest: digestOf(code) }), NOW);
    const onDisk = fs.readFileSync(pairstore.REQUEST_FILE, 'utf8');
    expect(onDisk).not.toContain(code);
    expect(onDisk).not.toContain(code.slice(0, 8));
    expect(onDisk).toContain('codeDigest');
  });

  test('每台设备的待确认数到上限就拒新的，且不挤掉已有那一条', () => {
    const limit = contract.pairRequest.perDeviceLimit;
    const requests = pairstore.loadRequests();
    for (let i = 0; i < limit; i += 1) {
      expect(pairstore.createRequest(contract, requests, input(), NOW + i).ok).toBe(true);
    }
    const first = Object.values(requests)[0].id;
    const out = pairstore.createRequest(contract, requests, input(), NOW + limit);
    expect(out.ok).toBe(false);
    expect(out.reason).toBe('per-device-limit');
    expect(Object.values(requests).map((r) => r.id)).toContain(first);
    expect(Object.keys(requests).length).toBe(limit);
  });

  test('另一个人的配额不受影响（上限是按"等谁确认"计的）', () => {
    const limit = contract.pairRequest.perDeviceLimit;
    const requests = pairstore.loadRequests();
    for (let i = 0; i < limit; i += 1)
      pairstore.createRequest(contract, requests, input(), i + NOW);
    expect(pairstore.createRequest(contract, requests, input({ target: B }), NOW).ok).toBe(true);
  });

  test('全局上限走的是**一份 mutate 出来的契约副本**（真实值 2000 台测不到那个规模）', () => {
    const small = JSON.parse(JSON.stringify(contract));
    small.pairRequest.globalLimit = 2;
    small.pairRequest.perDeviceLimit = 5;
    const requests = pairstore.loadRequests();
    expect(pairstore.createRequest(small, requests, input(), NOW).ok).toBe(true);
    expect(pairstore.createRequest(small, requests, input({ requester: A }), NOW + 1).ok).toBe(
      true,
    );
    const out = pairstore.createRequest(small, requests, input({ target: B }), NOW + 2);
    expect(out.ok).toBe(false);
    expect(out.reason).toBe('global-limit');
  });

  test('早已终态又早已过期的记录会被剪掉，剪完就能继续收新的', () => {
    const small = JSON.parse(JSON.stringify(contract));
    small.pairRequest.globalLimit = 2;
    small.pairRequest.perDeviceLimit = 5;
    const requests = pairstore.loadRequests();
    pairstore.createRequest(small, requests, input(), NOW);
    const second = pairstore.createRequest(small, requests, input({ requester: A }), NOW + 1);
    expect(second.ok).toBe(true);
    // 把第二条改成"已拒绝且早已过期"，再取一次：它既不该再被看见，也不该继续占额度。
    requests[second.request.id].status = 'denied';
    requests[second.request.id].expiresAt = NOW - 1;
    const third = pairstore.createRequest(small, requests, input({ target: B }), NOW + 10);
    expect(third.ok).toBe(true);
    expect(requests[second.request.id]).toBeUndefined();
  });

  test('到期未确认的 pending 被标成 expired，返回的条数能说出来', () => {
    const requests = pairstore.loadRequests();
    const created = pairstore.createRequest(contract, requests, input(), NOW);
    const later = NOW + contract.identity.pairingCode.ttlSeconds * 1000 + 1;
    expect(pairstore.expireDue(contract, requests, later)).toBe(1);
    expect(requests[created.request.id].status).toBe('expired');
    // 再跑一次不重复计数（幂等：状态已经是终态了）。
    expect(pairstore.expireDue(contract, requests, later + 1)).toBe(0);
  });

  test('取货只看自己的、按时间正序、终态不再出现', () => {
    const requests = pairstore.loadRequests();
    pairstore.createRequest(contract, requests, input(), NOW + 10);
    pairstore.createRequest(contract, requests, input(), NOW + 5);
    pairstore.createRequest(contract, requests, input({ target: B }), NOW + 1);
    const mine = pairstore.pendingFor(contract, requests, A, NOW + 20);
    expect(mine.map((r) => r.createdAt)).toEqual([NOW + 5, NOW + 10]);
    expect(pairstore.pendingFor(contract, requests, B, NOW + 20).length).toBe(1);
    requests[mine[0].id].status = 'denied';
    expect(pairstore.pendingFor(contract, requests, A, NOW + 21).length).toBe(1);
  });

  test('响应里显式挑字段：内部键与 target 都不回显', () => {
    const requests = pairstore.loadRequests();
    const created = pairstore.createRequest(contract, requests, input(), NOW);
    // 模拟"哪天有人顺手在记录上多存一个内部键"（留痕原因是最典型的例子）。
    requests[created.request.id].internalNote = '口令在第 2 次尝试时不对';
    const out = pairstore.pendingFor(contract, requests, A, NOW);
    expect(Object.keys(out[0]).sort()).toEqual(
      [
        'codeDigest',
        'createdAt',
        'expiresAt',
        'id',
        'level',
        'requester',
        'requesterPublicKey',
      ].sort(),
    );
    expect(out[0].requester).toBe(B);
  });

  test('契约那段缺形状时是抛，不是按一个默认值办', () => {
    const broken = JSON.parse(JSON.stringify(contract));
    delete broken.pairRequest;
    expect(() => pairstore.createRequest(broken, pairstore.loadRequests(), input(), NOW)).toThrow(
      /pairRequest/,
    );
    const badTtl = JSON.parse(JSON.stringify(contract));
    badTtl.pairRequest.ttlSecondsFrom = 'identity.notThere';
    expect(() => pairstore.createRequest(badTtl, {}, input(), NOW)).toThrow(/ttlSecondsFrom/);
    const badInitial = JSON.parse(JSON.stringify(contract));
    badInitial.pairRequest.initialStatus = 'denied';
    expect(() => pairstore.createRequest(badInitial, {}, input(), NOW)).toThrow(/initialStatus/);
  });

  test('pollKey：visibleVia=poll 却没写键名 ⇒ 抛（请求落进表里却没人取得到）', () => {
    const noKey = JSON.parse(JSON.stringify(contract));
    delete noKey.pairRequest.pollKey;
    expect(() => pairstore.pollKey(noKey)).toThrow(/pollKey/);
    const other = JSON.parse(JSON.stringify(contract));
    other.pairRequest.visibleVia = 'webhook';
    expect(() => pairstore.pollKey(other)).toThrow(/visibleVia/);
    expect(pairstore.pollKey(contract)).toBe('pairRequests');
  });

  test('缺字段的请求不落地：抛，而不是写一条"谁都不知道是谁请求的"记录', () => {
    for (const field of ['target', 'requester', 'requesterPublicKey', 'level', 'codeDigest']) {
      const missing = input();
      delete missing[field];
      expect(() => pairstore.createRequest(contract, {}, missing, NOW)).toThrow(new RegExp(field));
    }
  });
});
