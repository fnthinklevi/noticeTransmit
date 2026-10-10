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
const PEER = '7YD4RKQPBM8XZ3VHNT'; // 另一台（关系是写给它的，所以不能复用 ADDR）
const PUB = Buffer.alloc(32, 7).toString('base64'); // 32 字节公钥
const PUB2 = Buffer.alloc(32, 11).toString('base64');
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

  test('设备表形状就是任务书那一行：公钥/名称/状态/last_seen/关系表/创建时间/owner', () => {
    const devices = {};
    const rec = store.registerDevice(
      contract,
      devices,
      { addressCode: ADDR, publicKey: PUB, name: 'NAS' },
      NOW,
    );
    expect(Object.keys(rec).sort()).toEqual(
      ['createdAt', 'grantsBy', 'lastSeenAt', 'name', 'owner', 'publicKey', 'status'].sort(),
    );
    expect(rec.owner).toBeNull();
    expect(rec.lastSeenAt).toBeNull();
    expect(rec.createdAt).toBe(NOW);
    expect(rec.status).toBe('active');
    // ⚠ 授权不在这张表的这一行上（#131 第三片）：登记只是"这台设备能签名"，
    //   而「谁能投给我」住在**被投那台**的 grantsBy 里。过去这里写一份 grant 并被收单读取，
    //   效果就是"登记即许可"。
    expect(rec.grantsBy).toEqual({});
    expect(rec.grant).toBeUndefined();
  });

  test('登记改不了任何授权：re-register 带 level 也不写，已有关系逐字不动', () => {
    const devices = {};
    store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
    store.approvePeer(contract, devices, ADDR, PEER, 'L2', [], NOW);
    const before = JSON.stringify(devices[ADDR].grantsBy);
    // 老客户端还会带 level 上来 —— 现在它不再有任何作用：既不改关系，也不新增关系。
    const again = store.registerDevice(
      contract,
      devices,
      { addressCode: ADDR, publicKey: PUB, level: 'L3' },
      NOW + 1000,
    );
    expect(JSON.stringify(again.grantsBy)).toBe(before);
    expect(again.grant).toBeUndefined();
    // 一个新地址码带着 level 来登记，也不该在**别人**的表上长出关系来。
    const stranger = store.registerDevice(
      contract,
      devices,
      { addressCode: PEER, publicKey: PUB2, level: 'L3' },
      NOW,
    );
    expect(stranger.grantsBy).toEqual({});
  });

  test('覆盖升级：老行里那份 grant 被清掉，补上空的 grantsBy（不留一份没人读的授权）', () => {
    const devices = {
      [ADDR]: {
        createdAt: NOW,
        status: 'active',
        lastSeenAt: null,
        owner: null,
        publicKey: PUB,
        grant: { maxLevel: 'L3', items: ['app:a/b'], revision: 4, grantedAt: NOW },
      },
    };
    const rec = store.registerDevice(
      contract,
      devices,
      { addressCode: ADDR, publicKey: PUB },
      NOW + 1,
    );
    expect(rec.grant).toBeUndefined();
    expect(rec.grantsBy).toEqual({});
    // 落盘的也真是这个形状（内存里删了、盘上还留一份 = 下次读回来又是一份假权威）：
    // 走一次真读盘才算数。
    const reloaded = store.loadDevices();
    expect(reloaded[ADDR].grant).toBeUndefined();
    expect(reloaded[ADDR].grantsBy).toEqual({});
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

  test('档位只认契约那一列 —— 现在这条守在授权写入处（approvePeer），登记已经碰不到授权', () => {
    const devices = {};
    store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
    expect(() => store.approvePeer(contract, devices, ADDR, PEER, 'L9', [], NOW)).toThrow(
      /不在契约/,
    );
    expect(devices[ADDR].grantsBy).toEqual({});
  });

  // ── 授权写入的唯一咽喉（#131 第三片）──
  describe('approvePeer / peerGrant', () => {
    test('确认一次就写下关系：档位照输入、revision 递增、勾选整份覆盖', () => {
      const devices = {};
      store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
      const first = store.approvePeer(contract, devices, ADDR, PEER, 'L2', ['alert:ring'], NOW);
      expect(first).toEqual({ maxLevel: 'L2', items: ['alert:ring'], revision: 1, grantedAt: NOW });
      // 再确认一次（重新扫一次码），而这一次一条都没勾：
      // ⚠ 重新配对**不继承**旧的逐条勾选 —— L2/L3 那些"每次都要看一眼"的条目，
      //   不该因为重新扫一次码就自动回来（契约 itemRequiredFromLevel 的方向）。
      devices[ADDR].grantsBy[PEER].items = ['notification']; // 盘上先有的一份，不是下一次的答案
      const second = store.approvePeer(contract, devices, ADDR, PEER, 'L1', [], NOW + 1000);
      expect(second.revision).toBe(2);
      expect(second.items).toEqual([]);
      expect(second.maxLevel).toBe('L1');
      // 真落盘：重启后关系还在。
      expect(store.loadDevices()[ADDR].grantsBy[PEER].revision).toBe(2);
    });

    test('勾选项真写进表里，且去重排序（T134 片2：grant.items 从此有值可判）', () => {
      const devices = {};
      store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
      const grant = store.approvePeer(
        contract,
        devices,
        ADDR,
        PEER,
        'L2',
        ['notification', 'alert:ring', 'notification', ' alert:ring '],
        NOW,
      );
      expect(grant.items).toEqual(['alert:ring', 'notification']);
      // 落盘再读回来还是同一份：内存里对了、盘上飘了，表现是"重启一次勾选换了一套"。
      expect(store.loadDevices()[ADDR].grantsBy[PEER].items).toEqual([
        'alert:ring',
        'notification',
      ]);
    });

    test('授权写入那道咽喉不信任上游：词表外、非数组、空项都抛，且一个字节都不写', () => {
      const devices = {};
      store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
      expect(() =>
        store.approvePeer(contract, devices, ADDR, PEER, 'L2', ['wipe_everything'], NOW),
      ).toThrow(/不在契约词表/);
      expect(() =>
        store.approvePeer(contract, devices, ADDR, PEER, 'L2', 'alert:ring', NOW),
      ).toThrow(/必须是数组/);
      // 缺这一枚键**不**当成"用户一条都没勾"：那正是 T134 之前几个月的现实，
      // 而它的表现是"配对成功、L2 全 403、两端日志都说自己没错"。
      expect(() => store.approvePeer(contract, devices, ADDR, PEER, 'L2', undefined, NOW)).toThrow(
        /必须是数组/,
      );
      expect(() => store.approvePeer(contract, devices, ADDR, PEER, 'L2', [''], NOW)).toThrow(
        /空项/,
      );
      expect(devices[ADDR].grantsBy).toEqual({});
      expect(store.loadDevices()[ADDR].grantsBy).toEqual({});
    });

    test('授权不能挂在没有记录的设备上，也不能写给一个不像地址码的东西', () => {
      const devices = {};
      expect(() => store.approvePeer(contract, devices, ADDR, PEER, 'L1', [], NOW)).toThrow(
        /未登记/,
      );
      store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
      expect(() => store.approvePeer(contract, devices, ADDR, '短', 'L1', [], NOW)).toThrow(
        /对方地址码/,
      );
    });

    test('peerGrant 读不到就返回 null（不回落成缺省档 —— 那是 fail-open）', () => {
      const devices = {};
      store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
      expect(store.peerGrant(contract, devices[ADDR], PEER)).toBeNull();
      store.approvePeer(contract, devices, ADDR, PEER, 'L2', [], NOW);
      expect(store.peerGrant(contract, devices[ADDR], PEER).maxLevel).toBe('L2');
      // 列名从契约读：换了名字就读不到（而不是读到别的东西）
      const renamed = JSON.parse(JSON.stringify(contract));
      renamed.pairing.relationshipField = 'grantsTo';
      expect(store.peerGrant(renamed, devices[ADDR], PEER)).toBeNull();
      expect(() => {
        const broken = JSON.parse(JSON.stringify(contract));
        broken.pairing.relationshipField = '';
        store.relationshipField(broken);
      }).toThrow(/relationshipField/);
    });

    test('关系查的是这一列自己的键，不是原型链上的东西（纵深防御）', () => {
      const record = { grantsBy: {} };
      // 把一个"看起来像合法地址码"的键挂到 Object.prototype 上：
      // 用 `by[key]` 直接取就会命中它，于是没人授权过的设备凭空有了一份授权。
      Object.prototype[PEER] = { maxLevel: 'L3', items: ['app:a/b'] };
      try {
        expect(store.peerGrant(contract, record, PEER)).toBeNull();
      } finally {
        delete Object.prototype[PEER];
      }
      expect(store.peerGrant(contract, record, PEER)).toBeNull();
    });
  });

  // ── T130 片2：一次确认写两段、划掉只划自己那一段 ────────────────────────
  describe('grantPairLegs / revokeDirection（一次确认两段）', () => {
    function two() {
      const devices = {};
      store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
      store.registerDevice(contract, devices, { addressCode: PEER, publicKey: PUB2 }, NOW);
      return devices;
    }

    test('两段各写自己那一行：正向带勾选项，反向只带档位', () => {
      const devices = two();
      const legs = store.grantPairLegs(contract, devices, ADDR, PEER, 'L2', ['alert:ring'], NOW);
      expect(legs.forward.maxLevel).toBe('L2');
      expect(legs.forward.items).toEqual(['alert:ring']);
      expect(legs.reverse.maxLevel).toBe('L2');
      expect(legs.reverse.items).toEqual([]);
      expect(legs.reverseSkipped).toBeNull();
      // 各自落在各自主键的那一行上：写反一侧就是"A 允许 A"，收单永远读不到。
      expect(store.peerGrant(contract, devices[ADDR], PEER).items).toEqual(['alert:ring']);
      expect(store.peerGrant(contract, devices[PEER], ADDR).items).toEqual([]);
      // 落过盘：只在内存里有两段，重启后两边都退回"没配过对"。
      const again = store.loadDevices();
      expect(store.peerGrant(contract, again[PEER], ADDR).maxLevel).toBe('L2');
    });

    test('对面不在表上 ⇒ 正向照写、反向跳过并说清是哪一类跳过', () => {
      const devices = {};
      store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
      const legs = store.grantPairLegs(contract, devices, ADDR, PEER, 'L1', [], NOW);
      expect(legs.forward.maxLevel).toBe('L1');
      expect(legs.reverse).toBeNull();
      expect(legs.reverseSkipped).toBe('requester-unregistered');
      // 只写了正向那一行：不许出现"给一个没有记录的地址挂一条授权"的那种半行。
      expect(devices[PEER]).toBeUndefined();
    });

    test('契约关掉双写 ⇒ 只留正向那一段（单段语义仍可部署）', () => {
      const devices = two();
      const off = JSON.parse(JSON.stringify(contract));
      off.pairing.reverseGrantOnConfirm = false;
      const legs = store.grantPairLegs(off, devices, ADDR, PEER, 'L1', [], NOW);
      expect(legs.reverse).toBeNull();
      expect(legs.reverseSkipped).toBe('disabled-by-contract');
      expect(store.peerGrant(contract, devices[PEER], ADDR)).toBeNull();
      expect(store.peerGrant(contract, devices[ADDR], PEER).maxLevel).toBe('L1');
    });

    test('旋钮缺失或指向实现不执行的取值 ⇒ 抛，且两段都不写', () => {
      for (const breakIt of [
        (p) => {
          delete p.reverseGrantOnConfirm;
        },
        (p) => {
          p.reverseGrantMaxLevel = 'from-request';
        },
        (p) => {
          p.reverseGrantItems = 'copy-forward';
        },
      ]) {
        const devices = two();
        const broken = JSON.parse(JSON.stringify(contract));
        breakIt(broken.pairing);
        expect(() => store.grantPairLegs(broken, devices, ADDR, PEER, 'L2', [], NOW)).toThrow();
        // ⚠ 判据排在写之前：先写完正向再抛会留下一张半份表，而它对设备侧与一次成功同形。
        expect(store.peerGrant(contract, devices[ADDR], PEER)).toBeNull();
        expect(store.peerGrant(contract, devices[PEER], ADDR)).toBeNull();
      }
    });

    test('划掉只划自己那一段：反向那一行分毫不动', () => {
      const devices = two();
      store.grantPairLegs(contract, devices, ADDR, PEER, 'L1', [], NOW);
      const otherSide = JSON.stringify(devices[PEER].grantsBy);
      const res = store.revokePeer(contract, devices, ADDR, PEER, NOW);
      expect(res.removed).toBe(true);
      expect(store.peerGrant(contract, devices[ADDR], PEER)).toBeNull();
      expect(JSON.stringify(devices[PEER].grantsBy)).toBe(otherSide);
    });

    test('撤销方向不是实现执行的那一个 ⇒ 抛在删之前（一条都不许少）', () => {
      const devices = two();
      store.grantPairLegs(contract, devices, ADDR, PEER, 'L1', [], NOW);
      const before = JSON.stringify(devices);
      const outgoing = JSON.parse(JSON.stringify(contract));
      outgoing.pairing.revokeDirection = 'outgoing';
      expect(() => store.revokePeer(outgoing, devices, ADDR, PEER, NOW)).toThrow(/revokeDirection/);
      expect(JSON.stringify(devices)).toBe(before);
      const missing = JSON.parse(JSON.stringify(contract));
      delete missing.pairing.revokeDirection;
      expect(() => store.revokePeer(missing, devices, ADDR, PEER, NOW)).toThrow(/revokeDirection/);
      expect(JSON.stringify(devices)).toBe(before);
      expect(store.revokeDirection(contract)).toBe('incoming');
    });
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

  test('⚠ 在线三态：从未上线 ≠ 掉线（显示层不许拿 isOnline 的 false 猜）', () => {
    const devices = {};
    store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
    expect(store.devicePresence(contract, devices[ADDR], NOW)).toBe('unknown');
    // isOnline 对同一件事答 false —— 这正是"两个概念被压成一个"的地方，用例把差异钉住
    expect(store.isOnline(contract, devices[ADDR], NOW)).toBe(false);
    const threshold =
      contract.presence.pollIntervalSeconds.default *
      contract.presence.onlineThresholdMultiplier *
      1000; // lastSeenAt 是毫秒，阈值也得换成毫秒再比
    store.touchDevice(contract, devices, ADDR, NOW);
    expect(store.devicePresence(contract, devices[ADDR], NOW + threshold)).toBe('online');
    expect(store.devicePresence(contract, devices[ADDR], NOW + threshold + 1)).toBe('offline');
    expect(store.devicePresence(contract, undefined, NOW)).toBe('unknown');
    // 状态表本身是契约读来的，不是这里写死的
    expect(contract.presence.states).toEqual(['online', 'offline', 'unknown']);
  });

  test('重置配对口令 = 覆盖那一条摘要：旧口令立刻算不出匹配（契约 resetPairingCodeInvalidatesOutstanding）', () => {
    const devices = {};
    store.registerDevice(contract, devices, { addressCode: ADDR, publicKey: PUB }, NOW);
    store.armPairingCode(contract, devices, ADDR, PAIR, NOW);
    const rotated = store.armPairingCode(contract, devices, ADDR, 'K'.repeat(20), NOW + 1);
    expect(rotated.rotatedAt).toBe(NOW + 1);
    expect(devices[ADDR].pairing.consumedAt).toBeNull(); // 重置顺带把"已消耗"清掉
    expect(store.verifyPairingCode(contract, devices, ADDR, PAIR, NOW + 2).ok).toBe(false);
    expect(store.verifyPairingCode(contract, devices, ADDR, 'K'.repeat(20), NOW + 2).ok).toBe(true);
    // 契约那条旗标不是装饰：实现靠的是"只存一条摘要"这个结构，改不成"存一份历史"
    expect(contract.revocation.resetPairingCodeInvalidatesOutstanding).toBe(true);
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
    const created = store.createEndpoint(
      contract,
      endpoints,
      { name: 'NAS 告警', secret: SECRET },
      NOW,
    );
    expect(created.endpoint.name).toBe('NAS 告警');
    // 明文口令只在那一次返回值里出现；表里从头到尾只有摘要
    expect(endpoints[created.id].secretDigest).toMatch(/^[0-9a-f]{64}$/);
    expect(JSON.stringify(endpoints)).not.toContain(SECRET);
    // ⚠ 对外的形状里连摘要都不许有：可爆破的靶子不该端出去（T38）
    expect(JSON.stringify(created.endpoint)).not.toContain('secretDigest');
    expect(store.findEndpointBySecret(contract, endpoints, SECRET, NOW).id).toBe(created.id);
    expect(store.findEndpointBySecret(contract, endpoints, 'K'.repeat(32), NOW)).toBeNull();
    store.revokeEndpoint(contract, endpoints, created.id, NOW + 5);
    expect(store.findEndpointBySecret(contract, endpoints, SECRET, NOW + 5)).toBeNull();
  });

  test('端点：口令形状不符就拒；postOnly 默认取契约 transport.postOnlySwitch；缺口令时服务端生成的那把符合契约位数', () => {
    const endpoints = {};
    // 创建方自带口令是留给"迁移已有部署"的，但它不能是任意串 —— 形状不符直接拒，
    // 否则表里会躺着一把 findEndpointBySecret 永远算不出匹配的摘要（静默失效的入口）。
    expect(() =>
      store.createEndpoint(contract, endpoints, { name: '坏的', secret: 'not*valid' }, NOW),
    ).toThrow(/形状不符/);
    const one = store.createEndpoint(contract, endpoints, { name: 'a', secret: SECRET }, NOW);
    expect(one.endpoint.postOnly).toBe(contract.transport.postOnlySwitch !== false);
    const gen = store.createEndpoint(contract, endpoints, { name: 'b' }, NOW);
    expect(gen.secret).toHaveLength(contract.identity.endpointSecret.length);
    expect(store.findEndpointBySecret(contract, endpoints, gen.secret, NOW).id).toBe(gen.id);
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
