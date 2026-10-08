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

// ── A 处理这条请求（#131 第三片）：pairstore 是"归属 + 只能一次"的执行处，授权交给 approvePeer ──
describe('decideRequest（#131 第三片）', () => {
  const devicestore = require('../lib/fnthink/devicestore');

  function seeded() {
    const devices = {};
    devicestore.registerDevice(
      contract,
      devices,
      { addressCode: A, publicKey: Buffer.alloc(32, 5).toString('base64') },
      NOW,
    );
    devicestore.registerDevice(
      contract,
      devices,
      { addressCode: B, publicKey: Buffer.alloc(32, 6).toString('base64') },
      NOW,
    );
    const requests = {};
    const created = pairstore.createRequest(contract, requests, input(), NOW);
    expect(created.ok).toBe(true);
    return { devices, requests, id: created.request.id };
  }

  const decide = (over) =>
    Object.assign(
      { requestId: null, target: A, requester: B, decision: 'approved', level: 'L1' },
      over || {},
    );

  test('未知 requestId / 不是你的 / 已处理过：三种走法各有各的原因，对外由路由塌成同一句话', () => {
    const { devices, requests, id } = seeded();
    expect(
      pairstore.decideRequest(contract, requests, devices, decide({ requestId: 'pr_nope' }), NOW)
        .reason,
    ).toBe('unknown-request');
    // 别人拿着真 id 来替 A 答应（契约 pairConfirm.requestMustBelongToTarget 的执行处）。
    expect(
      pairstore.decideRequest(
        contract,
        requests,
        devices,
        decide({ requestId: id, target: B, requester: A }),
        NOW,
      ).reason,
    ).toBe('not-yours');
    const ok = pairstore.decideRequest(contract, requests, devices, decide({ requestId: id }), NOW);
    expect(ok.ok).toBe(true);
    expect(
      pairstore.decideRequest(contract, requests, devices, decide({ requestId: id }), NOW).reason,
    ).toBe('already-decided');
  });

  test('同意：关系写到 A 那一行、请求进终态；拒绝：什么都不写', () => {
    const s1 = seeded();
    const ok = pairstore.decideRequest(
      contract,
      s1.requests,
      s1.devices,
      decide({ requestId: s1.id }),
      NOW,
    );
    expect(ok.grant.maxLevel).toBe('L1');
    expect(devicestore.peerGrant(contract, s1.devices[A], B).maxLevel).toBe('L1');
    // B 那一行上没有给 A 的授权 —— 方向错了就是"B 自己允许自己"。
    expect(devicestore.peerGrant(contract, s1.devices[B], A)).toBeNull();
    expect(s1.requests[s1.id].status).toBe(contract.clientEvents.pairConfirm.approveDecision);

    const s2 = seeded();
    const denied = pairstore.decideRequest(
      contract,
      s2.requests,
      s2.devices,
      decide({ requestId: s2.id, decision: 'denied' }),
      NOW,
    );
    expect(denied.ok).toBe(true);
    expect(denied.grant).toBeNull();
    expect(devicestore.peerGrant(contract, s2.devices[A], B)).toBeNull();
    expect(s2.requests[s2.id].status).toBe('denied');
  });

  test('早已过期的请求不能被"同意"：expireDue 排在判定之前', () => {
    const { devices, requests, id } = seeded();
    const late = NOW + contract.identity.pairingCode.ttlSeconds * 1000 + 1000;
    const out = pairstore.decideRequest(
      contract,
      requests,
      devices,
      decide({ requestId: id }),
      late,
    );
    expect(out.ok).toBe(false);
    expect(out.reason).toBe('already-decided');
    expect(devicestore.peerGrant(contract, devices[A], B)).toBeNull();
  });

  test('契约说不清哪个词算同意 ⇒ 抛（不敢猜：猜错的方向是把请求关掉又不给授权）', () => {
    const { devices, requests, id } = seeded();
    const broken = JSON.parse(JSON.stringify(contract));
    delete broken.clientEvents.pairConfirm.approveDecision;
    expect(() =>
      pairstore.decideRequest(broken, requests, devices, decide({ requestId: id }), NOW),
    ).toThrow(/approveDecision/);
    const bogus = JSON.parse(JSON.stringify(contract));
    bogus.clientEvents.pairConfirm.decisions = ['approved'];
    expect(() =>
      pairstore.decideRequest(
        bogus,
        requests,
        devices,
        decide({ requestId: id, decision: 'denied' }),
        NOW,
      ),
    ).toThrow(/decisions/);
  });
});

// ── 第二面（T110）：发起方读自己发起过的那些，含终态。放在这里而不是只放 HTTP 那一层，
// 因为"到期那一刻"要能控制 `now`：路由里那个数是 Date.now()，HTTP 用例钉不住等值。
describe('sentFor（T110 第二面：我发起的那条走到了哪儿）', () => {
  const devicestore = require('../lib/fnthink/devicestore');

  beforeEach(() => {
    // 上面那个 describe 的 beforeEach 管不到这一节：`expireDue` 与"读到几条"都是全表口径，
    // 上一节留下的行会把计数与截断一起带歪。
    if (fs.existsSync(pairstore.REQUEST_FILE)) fs.rmSync(pairstore.REQUEST_FILE);
  });

  /// 两张都登记好的设备表：`decideRequest` 批准那一支要往 A 那一行写授权。
  function deviceTable() {
    const devices = {};
    devicestore.registerDevice(
      contract,
      devices,
      { addressCode: A, publicKey: Buffer.alloc(32, 5).toString('base64') },
      NOW,
    );
    devicestore.registerDevice(
      contract,
      devices,
      { addressCode: B, publicKey: Buffer.alloc(32, 6).toString('base64') },
      NOW,
    );
    return devices;
  }

  test('两面主语相反：pendingFor 按 target 选且只 pending，sentFor 按 requester 选且含终态', () => {
    const requests = pairstore.loadRequests();
    // A←B（会被批准）与 B←A（A 发起给 B 的）两条，同一张表里两个方向。
    const toA = pairstore.createRequest(contract, requests, input(), NOW + 1).request.id;
    const toB = pairstore.createRequest(
      contract,
      requests,
      input({ target: B, requester: A, requesterPublicKey: 'pk-a', codeDigest: 'a'.repeat(64) }),
      NOW + 2,
    ).request.id;
    expect(pairstore.pendingFor(contract, requests, A, NOW + 3).map((r) => r.id)).toEqual([toA]);
    expect(pairstore.sentFor(contract, requests, A, NOW + 3, 50).map((r) => r.id)).toEqual([toB]);

    // 批准掉 toA：A 的接收面少一条，B 的发起面**多出一个终态**（那正是这一面存在的全部理由）。
    pairstore.decideRequest(
      contract,
      requests,
      deviceTable(),
      { requestId: toA, target: A, requester: B, decision: 'approved', level: 'L1' },
      NOW + 4,
    );
    expect(pairstore.pendingFor(contract, requests, A, NOW + 5)).toHaveLength(0);
    const sentB = pairstore.sentFor(contract, requests, B, NOW + 5, 50);
    expect(sentB.map((r) => r.id)).toEqual([toA]);
    expect(sentB[0].status).toBe(contract.clientEvents.pairConfirm.approveDecision);
  });

  test('到期扫描与本机答复共用同一列，出门叫 at（旧记录没记过 ⇒ 0，不拿当下凑）', () => {
    const requests = pairstore.loadRequests();
    const id = pairstore.createRequest(contract, requests, input(), NOW).request.id;
    // 还没人答过 ⇒ "状态什么时候变的"不知道。
    expect(pairstore.sentFor(contract, requests, B, NOW + 1, 50)[0].at).toBe(0);

    const later = NOW + contract.identity.pairingCode.ttlSeconds * 1000 + 7;
    expect(pairstore.expireDue(contract, requests, later)).toBe(1);
    const out = pairstore.sentFor(contract, requests, B, later, 50);
    // 「服务端从不批准」在词表上的形状：到期写的那个终态，本机答复那两发永远写不出来
    // （它必须落在 pairConfirm.decisions 之外，否则"过期"与"被拒"就是同一个词）。
    const expiredWord = contract.pairRequest.terminalStatuses.find(
      (s) => !contract.clientEvents.pairConfirm.decisions.includes(s),
    );
    expect(out[0].status).toBe(expiredWord);
    expect(out[0].at).toBe(later);
    // 表里只有一个时刻列（decidedAt 那个旧名字不许回来，否则两面各认一个）。
    expect(requests[id].statusChangedAt).toBe(later);
    expect(requests[id].decidedAt).toBeUndefined();
  });

  test('按发起时刻正序、到 limit 截最旧之外的，且显式挑字段（内部键与摘要都不出门）', () => {
    const requests = pairstore.loadRequests();
    const first = pairstore.createRequest(contract, requests, input(), NOW + 10).request.id;
    const second = pairstore.createRequest(contract, requests, input(), NOW + 4).request.id;
    requests[second].internalNote = '口令在第 2 次尝试时不对';

    const all = pairstore.sentFor(contract, requests, B, NOW + 20, 50);
    expect(all.map((r) => r.id)).toEqual([second, first]);
    expect(Object.keys(all[0]).sort()).toEqual([...contract.pairRequest.sentFields].sort());
    const text = JSON.stringify(all);
    expect(text).not.toContain('internalNote');
    expect(text).not.toContain('codeDigest');
    expect(text).not.toContain('requesterPublicKey');
    // 截断留的是**最旧**那几条（与 receiptsForSender 同一排干方向）：这一面的正常规模是
    // perDeviceLimit 那个量级（个位数），limit 只是响应体大小的防线，不是常态。
    expect(pairstore.sentFor(contract, requests, B, NOW + 20, 1).map((r) => r.id)).toEqual([
      second,
    ]);
    expect(pairstore.sentFor(contract, requests, B, NOW + 20, 0)).toHaveLength(0);
  });
});
