/**
 * 幻念推送服务端存储（T27）测试：设备表 + 端点表 + 两条硬规矩。
 *
 * 覆盖：明文凭证进不了盘（键名与值两道）、地址码不存在与口令错同形、配对口令一次性与过期、
 * 公钥不许静默替换、presence 在线判定来自契约、0600 权限。
 *
 * ⚠ 0600 那条只在 POSIX 上断言：Windows 的 NTFS 不承载 Unix 权限位，本机跑必假绿/假红。
 *    CI（ubuntu）与部署机（Linux）才看得见它 —— 这是这条守卫的真实边界。
 *
 * 运行：cd server && npx jest test/fnthink-devicestore.test.js
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const bcrypt = require('bcryptjs');

// ========== 测试环境（必须在任何 require 之前设置） ==========
process.env.NODE_ENV = 'test';
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-fnthink', 10);
const DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-test-'));
process.env.DATA_DIR = DATA_DIR;

const { loadContract } = require('../lib/fnthink/contract');
const store = require('../lib/fnthink/devicestore');

const contract = loadContract();
const NOW = 1_800_000_000_000;
const ADDR = '8K3FJ6QPTM9WZ4VHNS'; // 18 位合法地址码
const PUB = Buffer.alloc(32, 7).toString('base64'); // 32 字节公钥
const PAIR = '7YD4RKQPBM8XZ3VHNT6J'; // 20 位配对口令
const SECRET = '7YD4RKQPBM8XZ3VHNT6JKMNPQRSTVWXY'; // 32 位端点口令

describe('fnthink 服务端存储（T27）', () => {
  beforeEach(() => {
    for (const f of fs.readdirSync(DATA_DIR)) fs.rmSync(path.join(DATA_DIR, f), { force: true });
  });

  test('登记表按 0600 落盘（权限位那条仅 POSIX 可断言）', () => {
    expect(store.FILE_MODE).toBe(0o600); // 跨平台钉住"意图"，Windows 上也不放过
    const devices = {};
    store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
    expect(fs.existsSync(store.DEVICE_FILE)).toBe(true);
    if (process.platform === 'win32') return;
    expect(fs.statSync(store.DEVICE_FILE).mode & 0o777).toBe(0o600);
  });

  test('设备表形状就是任务书那一行：公钥/名称/状态/last_seen/能力/创建时间/owner', () => {
    const devices = {};
    const rec = store.registerDevice(
      contract,
      devices,
      { addressCode: ADDR, publicKey: PUB, name: 'NAS', level: 'L2' },
      NOW,
    );
    expect(Object.keys(rec).sort()).toEqual(
      ['createdAt', 'lastSeenAt', 'level', 'name', 'owner', 'publicKey', 'status'].sort(),
    );
    expect(rec.owner).toBeNull();
    expect(rec.lastSeenAt).toBeNull();
    expect(rec.createdAt).toBe(NOW);
    expect(rec.status).toBe('active');
    expect(rec.level).toBe('L2');
  });

  test('重复登记同一把公钥是幂等，换公钥必须拒绝（换身份要走 T31）', () => {
    const devices = {};
    store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
    const again = store.registerDevice(
      contract,
      devices,
      { addressCode: ADDR, publicKey: PUB },
      NOW,
    );
    expect(again.createdAt).toBe(NOW);
    expect(() =>
      store.registerDevice(
        contract,
        devices,
        { addressCode: ADDR, publicKey: Buffer.alloc(32, 9).toString('base64') },
        NOW,
      ),
    ).toThrow(/拒绝静默替换/);
  });

  test('公钥形状不对不进盘：32 字节之外的"公钥"只会让验签永远失败', () => {
    const devices = {};
    expect(() =>
      store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: 'abc' }, NOW),
    ).toThrow(/32 字节/);
  });

  test('能力级别只认契约那一列', () => {
    const devices = {};
    expect(() =>
      store.registerDevice(
        contract,
        devices,
        { addressCode: ADDR, publicKey: PUB, level: 'L9' },
        NOW,
      ),
    ).toThrow(/不在契约/);
  });

  test('口令成功一次即消耗（singleUse 来自契约），第二次同样失败', () => {
    const devices = {};
    store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
    store.armPairingCode(contract, devices, ADDR, PAIR, NOW);
    expect(store.verifyPairingCode(contract, devices, ADDR, PAIR, NOW).ok).toBe(true);
    expect(store.verifyPairingCode(contract, devices, ADDR, PAIR, NOW + 1000).ok).toBe(false);
  });

  test('口令过期即失效，有效期取自契约（不是代码里写死的 300）', () => {
    const ttl = contract.identity.pairingCode.ttlSeconds;
    expect(typeof ttl).toBe('number');
    const devices = {};
    store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
    store.armPairingCode(contract, devices, ADDR, PAIR, NOW);
    expect(store.verifyPairingCode(contract, devices, ADDR, PAIR, NOW + ttl * 1000 - 1).ok).toBe(
      true,
    );
    const devices2 = {};
    store.registerDevice(contract, devices2, { addressCode: ADDR, publicKey: PUB }, NOW);
    store.armPairingCode(contract, devices2, ADDR, PAIR, NOW);
    expect(store.verifyPairingCode(contract, devices2, ADDR, PAIR, NOW + ttl * 1000 + 1).ok).toBe(
      false,
    );
  });

  test('⚠ 同形规则：没有这台设备 / 口令错 / 形状不对，三者返回完全一样的东西', () => {
    const devices = {};
    store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
    store.armPairingCode(contract, devices, ADDR, PAIR, NOW);
    const unknownDevice = store.verifyPairingCode(
      contract,
      devices,
      '7YD4RKQPBM8XZ3VHNT',
      PAIR,
      NOW,
    );
    const wrongCode = store.verifyPairingCode(contract, devices, ADDR, 'K'.repeat(20), NOW);
    const malformed = store.verifyPairingCode(contract, devices, ADDR, 'ILOU'.repeat(5), NOW);
    expect(unknownDevice).toEqual(wrongCode);
    expect(unknownDevice).toEqual(malformed);
    expect(unknownDevice.status).toBe(contract.statusCodes.unauthorized);
    // 而且落盘的东西也不能泄漏差别：三次失败都没动 digest
    expect(devices[ADDR].pairing.consumedAt).toBeNull();
  });

  test('明文口令与私钥进不了盘：键名一道、值一道', () => {
    const devices = {};
    store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
    expect(() => store.saveDevices({ [ADDR]: { pairingCode: PAIR } })).toThrow(/明文凭证/);
    expect(() => store.saveDevices({ [ADDR]: { privateKey: '-----BEGIN' } })).toThrow(/明文凭证/);
    // 键名起得再干净也没用：值是一把形状完整的口令照样拦
    expect(() => store.saveDevices({ [ADDR]: { note: PAIR } })).toThrow(/形状完整的口令/);
    expect(() => store.saveEndpoints({ ep_1: { secretDigest: 'not-a-digest' } })).toThrow(
      /不是 64 位十六进制/,
    );
  });

  test('地址码是公开标识，允许出现在值里（否则每个设备名都要躲着 18 位串）', () => {
    expect(store.looksLikeCredential(contract, ADDR)).toBe(false);
    expect(store.looksLikeCredential(contract, PAIR)).toBe(true);
    expect(store.looksLikeCredential(contract, SECRET)).toBe(true);
  });

  test('在线判定读契约 presence：倍数 × 拉取间隔，从不上线的设备算离线', () => {
    const threshold =
      contract.presence.pollIntervalSeconds.default *
      contract.presence.onlineThresholdMultiplier *
      1000;
    const devices = {};
    store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
    expect(store.isOnline(contract, devices[ADDR], NOW)).toBe(false); // lastSeenAt 还是 null
    store.touchDevice(contract, devices, ADDR, NOW);
    expect(store.isOnline(contract, devices[ADDR], NOW + threshold)).toBe(true);
    expect(store.isOnline(contract, devices[ADDR], NOW + threshold + 1)).toBe(false);
    // 拉取间隔是设备自己上报的（弱网会调大），同一份表要跟着变：
    // 隔了 3×20s 再来判，按默认 20s 算已离线，但这台 60s 一轮，判在线要放宽到 3×60s。
    expect(store.isOnline(contract, devices[ADDR], NOW + threshold, 60)).toBe(true);
  });

  test('端点表：只存摘要，口令对得上才给记录；吊销后不再命中', () => {
    const endpoints = {};
    const created = store.putEndpoint(
      contract,
      endpoints,
      { name: 'NAS 告警', secret: SECRET },
      NOW,
    );
    expect(created.secretDigest).toMatch(/^[0-9a-f]{64}$/);
    expect(JSON.stringify(endpoints)).not.toContain(SECRET);
    expect(store.findEndpointBySecret(contract, endpoints, SECRET).id).toBe(created.id);
    expect(store.findEndpointBySecret(contract, endpoints, 'K'.repeat(20))).toBeNull();
    store.putEndpoint(contract, endpoints, { id: created.id, revoked: true }, NOW + 5);
    expect(store.findEndpointBySecret(contract, endpoints, SECRET)).toBeNull();
  });

  test('新建端点必须带口令；postOnly 默认取契约 transport.postOnlySwitch', () => {
    const endpoints = {};
    expect(() => store.putEndpoint(contract, endpoints, { name: '空的' }, NOW)).toThrow(
      /必须带口令/,
    );
    const one = store.putEndpoint(contract, endpoints, { name: 'a', secret: SECRET }, NOW);
    expect(one.postOnly).toBe(contract.transport.postOnlySwitch === true);
  });

  test('读写往返：saveDevices 之后 loadDevices 拿回同一份，且文件里没有明文口令', () => {
    const devices = {};
    store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
    store.armPairingCode(contract, devices, ADDR, PAIR, NOW);
    const back = store.loadDevices();
    expect(back[ADDR].publicKey).toBe(PUB);
    expect(back[ADDR].pairing.digest).toMatch(/^[0-9a-f]{64}$/);
    expect(JSON.stringify(back)).not.toContain(PAIR);
  });

  test('空表/坏文件不炸：没有文件时是空表', () => {
    expect(store.loadDevices()).toEqual({});
    fs.writeFileSync(store.DEVICE_FILE, '{这不是 JSON', 'utf8');
    expect(store.loadDevices()).toEqual({});
  });
});
