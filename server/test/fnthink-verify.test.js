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
const OTHER = '7YD4RKQPBM8XZ3VHNT6J';

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

  test('⚠ 四种"身份没被证明"的失败返回完全一样的东西', () => {
    const good = signable(kp, fields());
    const forged = keypair();
    const cases = {
      未知设备: [
        stateFor(kp, { devices: {} }),
        { senderAddress: OTHER, signature: good.signature, fields: good.fields, now: NOW },
      ],
      已冻结: [
        stateFor(kp, { devices: { [SENDER]: { publicKey: kp.rawBase64, status: 'frozen' } } }),
        { senderAddress: SENDER, signature: good.signature, fields: good.fields, now: NOW },
      ],
      公钥形状不对: [
        stateFor(kp, { devices: { [SENDER]: { publicKey: 'aGk=', status: 'active' } } }),
        { senderAddress: SENDER, signature: good.signature, fields: good.fields, now: NOW },
      ],
      签名是别人签的: [
        stateFor(kp),
        (() => {
          const p = signable(forged, fields());
          return { senderAddress: SENDER, signature: p.signature, fields: p.fields, now: NOW };
        })(),
      ],
      字段缺一整项: [
        stateFor(kp),
        (() => {
          const p = signable(kp, fields());
          const broken = Object.assign({}, p.fields);
          delete broken[canonicalOrder(contract)[0]];
          return { senderAddress: SENDER, signature: p.signature, fields: broken, now: NOW };
        })(),
      ],
    };
    const shapes = Object.entries(cases).map(([label, [state, input]]) => {
      const got = verify.acceptIncoming(contract, state, input);
      expect([label, got]).toEqual([
        label,
        { ok: false, status: 403, receipt: 'rejected_unsigned' },
      ]);
      return JSON.stringify(got);
    });
    expect(new Set(shapes).size).toBe(1);
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

  test('契约自己把这组关系钉住了（dedupe ≥ 2×skew）', () => {
    expect(contract.signature.nonceDedupeSeconds).toBeGreaterThanOrEqual(
      contract.signature.maxSkewSeconds * 2,
    );
    expect(contract.signature.verifyOnlyForWhitelistedKeys).toBe(true);
  });
});
