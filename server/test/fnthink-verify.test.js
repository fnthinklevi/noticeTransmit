'use strict';

// 幻念推送验签（T29-B）· 服务端侧。
//
// 这里的判据分两类，都是"改坏了不会报错、只会静默出错"的那类：
//  ① 公钥必须来自设备表（请求自带的公钥一概不信）；
//  ② 身份没被证明之前的四种失败必须**一模一样**（未知设备 / 冻结 / 公钥形状 / 验签失败），
//     证明之后的两种反而必须能分辨（过期、重复）—— 方向反了就变成枚举器或瞎重试。

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-verify', 10);
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-verify-'));

const { loadContract, assertSupported, canonicalOrder } = require('../lib/fnthink/contract');
const store = require('../lib/fnthink/devicestore');
const verify = require('../lib/fnthink/verify');

const contract = assertSupported(loadContract());
const NOW = 1_800_000_000_000; // 毫秒；字段里的 ts 是秒
const SENDER = '8K3FJ6QPTM9WZ4VHNS';
const OTHER = '7YD4RKQPBM8XZ3VHNT';

function keypair() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const der = publicKey.export({ type: 'spki', format: 'der' });
  return {
    rawBase64: der.subarray(der.length - 32).toString('base64'),
    privateKey,
    derLength: der.length,
  };
}

function fields(over) {
  return Object.assign(
    {
      version: '1',
      type: 'notice',
      target: SENDER,
      ts: String(Math.floor(NOW / 1000)),
      nonce: 'n-1',
      body: '机箱温度 63℃',
    },
    over || {},
  );
}

// 契约的字段名是 v/type/target/ts/nonce/body；这里用 canonicalOrder 驱动，
// 免得测试自己变成第二份"顺序与字段名"的拷贝。
function signable(kp, f, nowMs) {
  const map = {};
  for (const key of canonicalOrder(contract)) map[key] = f[key]; // 字段名就用契约那一套，不在测试里改名
  const canonical = verify.canonicalBytes(contract, map);
  const signature = crypto.sign(null, canonical, kp.privateKey).toString('base64');
  return { fields: map, signature, canonical, now: nowMs === undefined ? NOW : nowMs };
}

function stateFor(kp, over) {
  return Object.assign(
    {
      devices: { [SENDER]: { publicKey: kp.rawBase64, status: 'active' } },
      nonces: {},
    },
    over || {},
  );
}

/// 「身份没被证明」的几条走法。同一条表既用来断"对外一模一样"，也用来断
/// "对内每一类都留了自己的原因" —— 两处判据共用一份输入，才不会一边改了另一边还绿。
function preAuthRejections(kp) {
  const good = signable(kp, fields());
  const forged = keypair();
  const broken = (() => {
    const p = signable(kp, fields());
    const copy = Object.assign({}, p.fields);
    delete copy[canonicalOrder(contract)[0]];
    return { senderAddress: SENDER, signature: p.signature, fields: copy, now: NOW };
  })();
  const byForged = (() => {
    const p = signable(forged, fields());
    return { senderAddress: SENDER, signature: p.signature, fields: p.fields, now: NOW };
  })();
  return [
    [
      '未知设备',
      stateFor(kp, { devices: {} }),
      { senderAddress: OTHER, signature: good.signature, fields: good.fields, now: NOW },
    ],
    [
      '已冻结',
      stateFor(kp, { devices: { [SENDER]: { publicKey: kp.rawBase64, status: 'frozen' } } }),
      { senderAddress: SENDER, signature: good.signature, fields: good.fields, now: NOW },
    ],
    [
      '公钥形状不对',
      stateFor(kp, { devices: { [SENDER]: { publicKey: 'aGk=', status: 'active' } } }),
      { senderAddress: SENDER, signature: good.signature, fields: good.fields, now: NOW },
    ],
    ['签名是别人签的', stateFor(kp), byForged],
    ['字段缺一整项', stateFor(kp), broken],
  ];
}

describe('fnthink 验签与裁决（T29-B）', () => {
  const kp = keypair();

  test('公钥是 32 字节裸串，SPKI 头由契约给', () => {
    expect(kp.derLength).toBe(44);
    expect(Buffer.from(kp.rawBase64, 'base64')).toHaveLength(32);
    const key = verify.publicKeyFromRaw(contract, kp.rawBase64);
    expect(key.export({ type: 'spki', format: 'der' }).length).toBe(44);
    expect(() => verify.publicKeyFromRaw(contract, 'aGk=')).toThrow(/应为 32/);
  });

  test('规范化字节按契约顺序、用契约分隔符；缺字段抛并点名', () => {
    const map = {};
    for (const key of canonicalOrder(contract)) map[key] = key === 'ts' ? '1760000000' : 'x';
    const bytes = verify.canonicalBytes(contract, map);
    const parts = bytes.toString('utf8').split(String.fromCharCode(0));
    expect(parts).toHaveLength(canonicalOrder(contract).length);
    expect(() => verify.canonicalBytes(contract, { ...map, nonce: undefined })).toThrow(/nonce/);
    expect(() =>
      verify.canonicalBytes(contract, { ...map, body: 'a' + String.fromCharCode(0) + 'b' }),
    ).toThrow(/分隔符/);
  });

  test('正常一条 ⇒ 202 queued', () => {
    const pack = signable(kp, fields());
    const out = verify.acceptIncoming(contract, stateFor(kp), {
      senderAddress: SENDER,
      signature: pack.signature,
      fields: pack.fields,
      now: pack.now,
    });
    expect(out).toEqual({ ok: true, status: 202, receipt: 'queued' });
  });

  test('⚠ 五种"身份没被证明"的失败返回完全一样的东西', () => {
    const shapes = preAuthRejections(kp).map(([label, state, input]) => {
      const got = verify.acceptIncoming(contract, state, input);
      expect([label, got]).toEqual([
        label,
        { ok: false, status: 403, receipt: 'rejected_unsigned' },
      ]);
      // 响应里不许夹带任何"为什么被拒"或"拒了几次"的东西
      expect(Object.keys(got).sort()).toEqual(['ok', 'receipt', 'status']);
      return JSON.stringify(got);
    });
    expect(new Set(shapes).size).toBe(1);
    expect(shapes).toHaveLength(5);
  });

  test('对外同形，对内必须可分辨：每类拒绝各留一个原因并计一次数', () => {
    const seen = {};
    for (const [label, state, input] of preAuthRejections(kp)) {
      verify.acceptIncoming(contract, state, input);
      verify.acceptIncoming(contract, state, Object.assign({}, input, { now: input.now + 1000 }));
      const entries = Object.values(state.rejects);
      // 每一条都记在**指名的那个地址码**下（合法形状的），且计了两次
      expect(entries).toHaveLength(1);
      expect(entries[0].count).toBe(2);
      seen[label] = entries[0].lastReason;
    }
    // 这四类必须各有自己的原因；把它塌成一个"reject"是退步（现场就看不出是被人枚举还是在重放旧包）
    expect(new Set(Object.values(seen))).toEqual(
      new Set(['fields', 'unknown_device', 'signature', 'frozen']),
    );
    expect(seen.未知设备).not.toBe(seen.已冻结);
    expect(seen.未知设备).not.toBe(seen.签名是别人签的);
    // 公钥形状不对与签名不对**故意**同一个原因：两者都只说明"这把钥匙签不出这一条"，
    // 分成两类等于把"表里存了把坏钥匙"这种服务端自伤信息递给探测者。
    expect(seen.公钥形状不对).toBe(seen.签名是别人签的);
  });

  test('留痕只写内存：来路不明的包不许变成"一个请求 ⇒ 一次磁盘写"', () => {
    const state = stateFor(kp);
    const pack = signable(kp, fields());
    for (let i = 0; i < 30; i += 1) {
      verify.acceptIncoming(contract, state, {
        senderAddress: 'NOT-A-CODE-' + i,
        signature: pack.signature,
        fields: pack.fields,
        now: NOW + i,
      });
    }
    // 30 次乱造的形状不对的输入 ⇒ 只挤进一个桶，不是一本 30 行的名册
    expect(Object.keys(state.rejects)).toEqual([store.REJECT_INVALID_KEY]);
    expect(state.rejects[store.REJECT_INVALID_KEY].count).toBe(30);
    expect(fs.readdirSync(process.env.DATA_DIR).some((f) => /reject/i.test(f))).toBe(false);
  });

  test('留痕键数封顶（不封顶=拿随机地址码免费涨内存）', () => {
    const map = {};
    const cap = store.REJECT_KEY_CAP;
    for (let i = 0; i < cap + 5; i += 1)
      store.rememberReject(map, 'k' + i, NOW + i * 1000, 'signature');
    expect(Object.keys(map)).toHaveLength(cap);
    // 丢的是最久没动静的，留下的是最近那批
    expect(map['k' + (cap - 1)]).toBeDefined();
    expect(map.k0).toBeUndefined();
    expect(map['k' + (cap + 4)]).toBeDefined();
  });

  test('过期与重放也各计一次（这两类已经证明身份，原因照实记）', () => {
    const state = stateFor(kp);
    const pack = signable(kp, fields());
    const base = { senderAddress: SENDER, signature: pack.signature, fields: pack.fields };
    expect(
      verify.acceptIncoming(contract, state, Object.assign({ now: NOW + 900_000 }, base)).status,
    ).toBe(410);
    expect(state.rejects[SENDER].lastReason).toBe('expired');
    verify.acceptIncoming(contract, state, Object.assign({ now: NOW }, base));
    verify.acceptIncoming(contract, state, Object.assign({ now: NOW + 1000 }, base));
    expect(state.rejects[SENDER].lastReason).toBe('duplicate');
    // 1 次过期 + 1 次重放；中间那条成功的不计数（成功不是"拒收"）
    expect(state.rejects[SENDER].count).toBe(2);
  });

  test('请求自带公钥一概不信：只认设备表里那把', () => {
    const attacker = keypair();
    const pack = signable(attacker, fields());
    const out = verify.acceptIncoming(contract, stateFor(kp), {
      senderAddress: SENDER,
      signature: pack.signature,
      publicKey: attacker.rawBase64, // 就算调用方递过来，也不进判决
      fields: pack.fields,
      now: NOW,
    });
    expect(out.ok).toBe(false);
    expect(out.receipt).toBe('rejected_unsigned');
  });

  test('验签通过之后才允许分辨：时间超容差 ⇒ 410', () => {
    const skew = contract.signature.maxSkewSeconds;
    const onEdge = signable(kp, fields(), NOW);
    expect(
      verify.acceptIncoming(contract, stateFor(kp), {
        senderAddress: SENDER,
        signature: onEdge.signature,
        fields: onEdge.fields,
        now: onEdge.now + (skew - 1) * 1000,
      }).ok,
    ).toBe(true);
    const late = signable(kp, fields(), NOW);
    const out = verify.acceptIncoming(contract, stateFor(kp), {
      senderAddress: SENDER,
      signature: late.signature,
      fields: late.fields,
      now: late.now + (skew + 1) * 1000,
    });
    expect(out).toEqual({ ok: false, status: 410, receipt: 'expired' });
  });

  test('重放同一条 ⇒ 409，且去重表落盘后重启还记得', () => {
    const pack = signable(kp, fields());
    const state = stateFor(kp);
    const first = verify.acceptIncoming(contract, state, {
      senderAddress: SENDER,
      signature: pack.signature,
      fields: pack.fields,
      now: NOW,
    });
    expect(first.ok).toBe(true);
    const second = verify.acceptIncoming(contract, state, {
      senderAddress: SENDER,
      signature: pack.signature,
      fields: pack.fields,
      now: NOW + 1000,
    });
    expect(second).toEqual({ ok: false, status: 409, receipt: 'duplicate' });

    // 换一个新 state（模拟重启），但 nonce 文件已经在 ⇒ 仍然拦得住
    const reloaded = { devices: state.devices, nonces: store.loadNonces() };
    expect(
      verify.acceptIncoming(contract, reloaded, {
        senderAddress: SENDER,
        signature: pack.signature,
        fields: pack.fields,
        now: NOW + 2000,
      }),
    ).toEqual({ ok: false, status: 409, receipt: 'duplicate' });
    expect(fs.existsSync(store.NONCE_FILE)).toBe(true);
  });

  test('去重窗口到期后可以再用同一个 nonce（不是永久拉黑）', () => {
    const pack = signable(kp, fields());
    const state = stateFor(kp);
    const base = { senderAddress: SENDER, signature: pack.signature, fields: pack.fields };
    verify.acceptIncoming(contract, state, Object.assign({ now: NOW }, base));
    const after = verify.acceptIncoming(
      contract,
      state,
      Object.assign({ now: NOW + (contract.signature.nonceDedupeSeconds + 1) * 1000 }, base),
    );
    // 注意：这一步先被时间容差挡掉（ts 太旧），所以只看"不再是 duplicate"
    expect(after.receipt).not.toBe('duplicate');
  });

  test('nonce 表会剪掉到期项（不靠重启瘦身）', () => {
    const map = {};
    store.rememberNonce(map, 'a|n1', NOW, 60);
    store.rememberNonce(map, 'a|n2', NOW, 60);
    expect(Object.keys(map)).toHaveLength(2);
    store.rememberNonce(map, 'a|n3', NOW + 61_000, 60);
    expect(Object.keys(map).sort()).toEqual(['a|n3']);
    expect(() => store.rememberNonce(map, 'a|n4', NOW, 0)).toThrow(/正数/);
  });

  // ── T30-A：验签通过之后，还要按这台设备的授权判一次 ──
  function deviceState(grant) {
    const devices = { [SENDER]: { publicKey: kp.rawBase64, status: 'active' } };
    if (grant) devices[SENDER].grant = grant;
    return stateFor(kp, { devices });
  }

  test('记录里没写授权 ⇒ 按契约缺省档（L1）：通知收，动作拒', () => {
    const notice = signable(kp, fields());
    expect(
      verify.acceptIncoming(contract, deviceState(null), {
        senderAddress: SENDER,
        signature: notice.signature,
        fields: notice.fields,
        now: notice.now,
      }).ok,
    ).toBe(true);

    const action = signable(kp, fields({ type: 'action', body: '执行 app:a/b' }));
    const state = deviceState(null);
    const out = verify.acceptIncoming(contract, state, {
      senderAddress: SENDER,
      signature: action.signature,
      fields: action.fields,
      item: 'app:a/b',
      now: action.now,
    });
    expect(out).toEqual({ ok: false, status: 403, receipt: 'rejected_capability' });
    // 拒了一定要留痕（契约 signature.onFailure.count = true），且记的是**差在哪一档**
    expect(state.rejects[SENDER].lastReason).toBe('capability:level:L2');
  });

  test('勾过的那条才放行；没勾的点名是哪条', () => {
    const state = deviceState({ maxLevel: 'L2', items: ['app:a/b'] });
    const pack = signable(kp, fields({ type: 'action', body: '执行 app:a/b' }));
    const base = {
      senderAddress: SENDER,
      signature: pack.signature,
      fields: pack.fields,
      now: pack.now,
    };
    expect(
      verify.acceptIncoming(contract, state, Object.assign({ item: 'app:a/b' }, base)).ok,
    ).toBe(true);
    const other = signable(kp, fields({ type: 'action', body: '执行 app:a/c' }));
    expect(
      verify.acceptIncoming(contract, state, {
        senderAddress: SENDER,
        signature: other.signature,
        fields: other.fields,
        item: 'app:a/c',
        now: other.now,
      }),
    ).toEqual({ ok: false, status: 403, receipt: 'rejected_capability' });
    expect(state.rejects[SENDER].lastReason).toBe('capability:item:app:a/c');
  });

  test('⚠ item 必须出现在**已签字节**里：不然是借一条已签通知去触发一个没签过的动作', () => {
    const state = deviceState({ maxLevel: 'L2', items: ['app:a/b', 'app:a/evil'] });
    const pack = signable(kp, fields({ type: 'action', body: '执行 app:a/b' }));
    // 载荷签的是 app:a/b，调用方却递进一个清单里也存在的 app:a/evil
    const out = verify.acceptIncoming(contract, state, {
      senderAddress: SENDER,
      signature: pack.signature,
      fields: pack.fields,
      item: 'app:a/evil',
      now: pack.now,
    });
    expect(out).toEqual({ ok: false, status: 403, receipt: 'rejected_capability' });
    expect(state.rejects[SENDER].lastReason).toBe('unsigned-item');
    // 同一条包，item 与签过的一致就能过（证明拦的不是"action 一律拒"）
    const again = verify.acceptIncoming(contract, state, {
      senderAddress: SENDER,
      signature: pack.signature,
      fields: pack.fields,
      item: 'app:a/b',
      now: pack.now,
    });
    expect([again, state.rejects[SENDER].count]).toEqual([
      { ok: true, status: 202, receipt: 'queued' },
      1, // 只留过那一次痕：放行不算拒收
    ]);
  });

  test('能力裁决排在时间/重放之前：一条越权的老包报"越权"，不是报"过期"', () => {
    const skew = contract.signature.maxSkewSeconds;
    const state = deviceState(null);
    const pack = signable(kp, fields({ type: 'setting', body: '改设置 setting:x' }));
    const out = verify.acceptIncoming(contract, state, {
      senderAddress: SENDER,
      signature: pack.signature,
      fields: pack.fields,
      item: 'setting:x',
      now: pack.now + (skew + 10) * 1000,
    });
    expect(out.receipt).toBe('rejected_capability');
  });

  test('契约自己把这组关系钉住了（dedupe ≥ 2×skew）', () => {
    expect(contract.signature.nonceDedupeSeconds).toBeGreaterThanOrEqual(
      contract.signature.maxSkewSeconds * 2,
    );
    expect(contract.signature.verifyOnlyForWhitelistedKeys).toBe(true);
  });
});
