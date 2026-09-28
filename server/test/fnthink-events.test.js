// 设备侧签名事件（poll / ack）· 服务端裁决。
//
// 这批用例盯的是四件「改坏了不会报错、只会静默变宽」的事：
//  ① 事件与消息**不能互相冒用**（同一条签名换个接口再放一次）；
//  ② poll 只能问自己的队列（否则一台设备能读走别人的标题与正文）；
//  ③ 身份没证明之前的失败在 poll 入口仍然同形（否则 poll 成了新的地址码枚举器）；
//  ④ nonce 空间与消息**共用**（各记一份的话，重放窗口就在两个接口之间重新打开了）。
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-events', 10);
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-events-'));

const {
  loadContract,
  assertSupported,
  canonicalOrder,
  statusCode,
} = require('../lib/fnthink/contract');
const verify = require('../lib/fnthink/verify');
const events = require('../lib/fnthink/events');

const contract = assertSupported(loadContract());
const NOW = 1800000000000;
const SELF = '8K3FJ6QPTM9WZ4VHNS';
const OTHER = '7YD4RKQPBM8XZ3VHNT';

function keypair() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const der = publicKey.export({ type: 'spki', format: 'der' });
  return { rawBase64: der.subarray(der.length - 32).toString('base64'), privateKey };
}

function fields(over) {
  return Object.assign(
    {
      version: '1',
      type: contract.clientEvents.poll.messageType,
      target: SELF,
      ts: String(Math.floor(NOW / 1000)),
      nonce: 'e-1',
      body: '',
    },
    over || {},
  );
}

/// 签字节由契约顺序驱动：测试自己不写第二份「顺序与字段名」。
function signable(kp, f, nowMs) {
  const map = {};
  for (const key of canonicalOrder(contract)) map[key] = f[key];
  const canonical = verify.canonicalBytes(contract, map);
  return {
    senderAddress: SELF,
    fields: map,
    signature: crypto.sign(null, canonical, kp.privateKey).toString('base64'),
    now: nowMs === undefined ? NOW : nowMs,
  };
}

function stateFor(kp, over) {
  return Object.assign(
    {
      devices: { [SELF]: { publicKey: kp.rawBase64, status: 'active' } },
      nonces: {},
      persist() {},
    },
    over || {},
  );
}

const ackBody = (over) =>
  JSON.stringify(Object.assign({ messageId: 'm_0a1b', result: 'displayed' }, over || {}));

describe('clientEvents（poll / ack）裁决', () => {
  const kp = keypair();

  test('poll 自己：放行，并带回服务端时间', () => {
    const out = events.authorizeClientEvent(
      contract,
      stateFor(kp),
      signable(kp, fields({ nonce: 'p-ok' })),
      'poll',
    );
    expect(out.ok).toBe(true);
    expect(out.kind).toBe('poll');
    // serverTime 就是裁决用的那个 now：T29 的「ts 以服务端时间判定」要有承载处
    expect(out.serverTime).toBe(NOW);
    expect(out.sender).toBe(SELF);
  });

  test('poll 别人的地址码：拒绝（一台设备读走别人队列就是这个形状）', () => {
    const st = stateFor(kp);
    const out = events.authorizeClientEvent(
      contract,
      st,
      signable(kp, fields({ nonce: 'p-other', target: OTHER })),
      'poll',
    );
    expect(out.ok).toBe(false);
    expect(out.status).toBe(statusCode(contract, 'forbidden'));
    expect(out.reason).toBe('target-not-self');
    // ⚠ 事件形状判在时间/重放之前 ⇒ 一次「填错 target」不该烧掉 nonce。
    // 烧了的话，客户端把 target 改回自己再发同一条会被判 409，看着像它自己的重放缺陷。
    const retry = events.authorizeClientEvent(
      contract,
      st,
      signable(kp, fields({ nonce: 'p-other' })),
      'poll',
    );
    expect(retry.ok).toBe(true);
  });

  test('拿 poll 的签名去放 ack ⇒ 事件类型不对（同一条签名不能两个接口都用）', () => {
    const st = stateFor(kp);
    const out = events.authorizeClientEvent(
      contract,
      st,
      signable(kp, fields({ nonce: 'x-1' })),
      'ack',
    );
    expect(out.ok).toBe(false);
    expect(out.reason).toBe('wrong-event-type:' + contract.clientEvents.poll.messageType);
  });

  test('拿 ack 的签名去 poll ⇒ 同样被挡（反方向）', () => {
    const out = events.authorizeClientEvent(
      contract,
      stateFor(kp),
      signable(
        kp,
        fields({
          nonce: 'x-2',
          type: contract.clientEvents.ack.messageType,
          body: ackBody(),
        }),
      ),
      'poll',
    );
    expect(out.ok).toBe(false);
    expect(out.reason).toMatch(/^wrong-event-type:/);
  });

  test('没配过的设备 poll 与签名不对的 poll 逐字节同形（poll 不许成为新的枚举器）', () => {
    const stUnknown = { devices: {}, nonces: {}, persist() {} };
    const a = events.authorizeClientEvent(
      contract,
      stUnknown,
      signable(kp, fields({ nonce: 's-1' })),
      'poll',
    );
    const bogus = signable(kp, fields({ nonce: 's-2' }));
    bogus.signature = crypto
      .sign(null, Buffer.from('别的'), keypair().privateKey)
      .toString('base64');
    const b = events.authorizeClientEvent(contract, stateFor(kp), bogus, 'poll');
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
    expect(a.ok).toBe(false);
    expect(a.receipt).toBe('rejected_unsigned');
    // 对外的对象里**没有** reason 这个键：原因只进 state.rejects（将来要能显示
    // 「有 N 次冒充你的尝试」），一旦它出现在响应上，本接口就又是枚举器。
    expect(a.reason).toBeUndefined();
    expect(JSON.stringify(stUnknown.rejects)).toContain('unknown_device');
  });

  test('被吊销的设备 poll 不进队列（身份还在，状态白名单说了算）', () => {
    const st = stateFor(kp, {
      devices: { [SELF]: { publicKey: kp.rawBase64, status: 'revoked' } },
    });
    const out = events.authorizeClientEvent(
      contract,
      st,
      signable(kp, fields({ nonce: 'r-1' })),
      'poll',
    );
    expect(out.ok).toBe(false);
    expect(out.receipt).toBe('rejected_unsigned');
    expect(JSON.stringify(st.rejects)).toContain('status:revoked');
  });

  test('ts 超出容差 ⇒ 与消息入口同一个 410', () => {
    const skew = contract.signature.maxSkewSeconds;
    const out = events.authorizeClientEvent(
      contract,
      stateFor(kp),
      signable(kp, fields({ nonce: 't-1', ts: String(Math.floor(NOW / 1000) - skew - 30) })),
      'poll',
    );
    expect(out.ok).toBe(false);
    expect(out.status).toBe(statusCode(contract, 'expired'));
    expect(out.receipt).toBe('expired');
  });

  test('nonce 与消息共用一个空间：poll 用过的 nonce，ack 再拿就是 409', () => {
    const st = stateFor(kp);
    const first = events.authorizeClientEvent(
      contract,
      st,
      signable(kp, fields({ nonce: 'shared' })),
      'poll',
    );
    expect(first.ok).toBe(true);
    const second = events.authorizeClientEvent(
      contract,
      st,
      signable(
        kp,
        fields({
          nonce: 'shared',
          type: contract.clientEvents.ack.messageType,
          body: ackBody(),
        }),
      ),
      'ack',
    );
    expect(second.ok).toBe(false);
    expect(second.status).toBe(statusCode(contract, 'duplicate'));
    expect(second.receipt).toBe('duplicate');
  });

  test('ack 形状齐全 ⇒ 放行并带出 messageId/result', () => {
    const out = events.authorizeClientEvent(
      contract,
      stateFor(kp),
      signable(
        kp,
        fields({
          nonce: 'a-ok',
          type: contract.clientEvents.ack.messageType,
          body: ackBody({ messageId: 'm_9f2c', result: 'delivered' }),
        }),
      ),
      'ack',
    );
    expect(out.ok).toBe(true);
    expect(out.messageId).toBe('m_9f2c');
    expect(out.result).toBe('delivered');
  });

  test('ack 的 result 不在回执词表里 ⇒ 拒（不然路由会把它当成一次投递结果写进账）', () => {
    const out = events.authorizeClientEvent(
      contract,
      stateFor(kp),
      signable(
        kp,
        fields({
          nonce: 'a-bad',
          type: contract.clientEvents.ack.messageType,
          body: ackBody({ result: 'shown' }),
        }),
      ),
      'ack',
    );
    expect(out.ok).toBe(false);
    expect(out.reason).toBe('unknown-result:shown');
  });

  test('ack 的 body 多给一个字段 ⇒ 拒（这是设备自己签的，不适用「多余字段容忍」那条）', () => {
    const out = events.authorizeClientEvent(
      contract,
      stateFor(kp),
      signable(
        kp,
        fields({
          nonce: 'a-extra',
          type: contract.clientEvents.ack.messageType,
          body: ackBody({ isAdmin: true }),
        }),
      ),
      'ack',
    );
    expect(out.ok).toBe(false);
    expect(out.reason).toMatch(/^ack-fields:/);
  });

  test('ack 的 body 不是 JSON ⇒ 拒，且不抛（一条坏包不该让请求挂在那里）', () => {
    const out = events.authorizeClientEvent(
      contract,
      stateFor(kp),
      signable(
        kp,
        fields({
          nonce: 'a-junk',
          type: contract.clientEvents.ack.messageType,
          body: 'not-json',
        }),
      ),
      'ack',
    );
    expect(out.ok).toBe(false);
    expect(out.reason).toBe('malformed-ack');
  });

  test('契约侧：两类事件的 type 都不在 capabilities 词表里（否则冒用就变成合法）', () => {
    const vocabulary = Object.keys(contract.capabilities.messageTypes);
    expect(vocabulary).not.toContain(contract.clientEvents.poll.messageType);
    expect(vocabulary).not.toContain(contract.clientEvents.ack.messageType);
  });

  test('源码守卫：events.js 不写死状态码、也不写投递状态名', () => {
    // 状态码只能来自契约表（403/409/410 各抄一份就是第二份状态码表）；
    // 投递状态名出现在这里，意味着有人在本层自己判了一次状态、绕开了状态机。
    const src = fs.readFileSync(path.join(__dirname, '../lib/fnthink/events.js'), 'utf8');
    const noComments = src
      .split('\n')
      .filter((l) => !l.trim().startsWith('//'))
      .join('\n');
    expect(noComments).not.toMatch(/status:\s*4\d\d/);
    for (const s of ['queued', 'delivering', 'waiting_online', 'delivered', 'expired', 'dropped']) {
      expect(noComments).not.toContain("'" + s + "'");
    }
  });

  test('契约里没声明的事件种类 ⇒ 抛，不是当成 poll 放行', () => {
    expect(() =>
      events.authorizeClientEvent(contract, stateFor(kp), signable(kp, fields()), 'sneaky'),
    ).toThrow(/clientEvents\.sneaky/);
  });

  // ── 三选一的作用范围判据（#131 第二片 2A）──
  // 下面这几条断言的都是**mutate 出来的契约副本**上的行为，不是被放宽的真实协议：
  // 真实契约里每种事件声明哪条规则由 fnthink_push 的 validate() 钉住（有 mutate 反证）。
  // 这里要证明的只有一件事：events.js 读的是契约名单，不是自己那份常量。
  const counterpartPoll = () => {
    const c = JSON.parse(JSON.stringify(contract));
    delete c.clientEvents.poll.targetMustEqualSender;
    c.clientEvents.poll.mustContainCounterpartAddress = true;
    return c;
  };

  test('把 poll 换成 mustContainCounterpartAddress ⇒ 行为立刻跟着变（关于别人合法了）', () => {
    const c = counterpartPoll();
    const out = events.authorizeClientEvent(
      c,
      stateFor(kp),
      signable(kp, fields({ nonce: 'q-1', target: OTHER })),
      'poll',
    );
    expect(out.ok).toBe(true);
    // 同一份副本上其它判据仍然生效（不是"整层放行"）：事件类型不许冒用。
    const stillChecked = events.authorizeClientEvent(
      c,
      stateFor(kp),
      signable(kp, fields({ nonce: 'q-2' })),
      'ack',
    );
    expect(stillChecked.ok).toBe(false);
  });

  test('mustContainCounterpartAddress 下 target 填自己 ⇒ 拒（"自己跟自己配对"就是没人确认的那一条）', () => {
    const out = events.authorizeClientEvent(
      counterpartPoll(),
      stateFor(kp),
      signable(kp, fields({ nonce: 'q-3', target: SELF })),
      'poll',
    );
    expect(out.ok).toBe(false);
    expect(out.reason).toBe('counterpart-is-self');
  });

  test('mustContainCounterpartAddress 下 target 不是合法地址码 ⇒ 拒，不是"当成没有对方"放行', () => {
    const out = events.authorizeClientEvent(
      counterpartPoll(),
      stateFor(kp),
      signable(kp, fields({ nonce: 'q-4', target: 'NOPE' })),
      'poll',
    );
    expect(out.ok).toBe(false);
    expect(out.reason).toBe('counterpart-address-code');
  });

  test('声明两条规则 ⇒ 抛：OR 判下比一条更宽，不是更严', () => {
    const two = JSON.parse(JSON.stringify(contract));
    two.clientEvents.poll.mustContainCounterpartAddress = true; // targetMustEqualSender 仍在
    expect(() =>
      events.authorizeClientEvent(
        two,
        stateFor(kp),
        signable(kp, fields({ nonce: 'q-5' })),
        'poll',
      ),
    ).toThrow(/恰好一条/);
  });

  test('一条规则都不声明 ⇒ 抛，而不是"没有这条判据"放行', () => {
    const none = JSON.parse(JSON.stringify(contract));
    delete none.clientEvents.poll.targetMustEqualSender;
    expect(() =>
      events.authorizeClientEvent(
        none,
        stateFor(kp),
        signable(kp, fields({ nonce: 'q-6', target: OTHER })),
        'poll',
      ),
    ).toThrow(/恰好一条/);
  });

  test('契约名单里加一条本文件不认识的规则 ⇒ 抛（咽成"当成关于本机"就是替契约猜权限）', () => {
    const weird = JSON.parse(JSON.stringify(contract));
    delete weird.clientEvents.poll.targetMustEqualSender;
    weird.clientEvents.selfOnlyRules.push('mayTargetAnyone');
    weird.clientEvents.poll.mayTargetAnyone = true;
    expect(() =>
      events.authorizeClientEvent(
        weird,
        stateFor(kp),
        signable(kp, fields({ nonce: 'q-7' })),
        'poll',
      ),
    ).toThrow(/没有实现作用范围规则/);
  });

  test('契约名单被清空 ⇒ 抛（读不到名单不等于这条判据不存在）', () => {
    const empty = JSON.parse(JSON.stringify(contract));
    empty.clientEvents.selfOnlyRules = [];
    expect(() =>
      events.authorizeClientEvent(
        empty,
        stateFor(kp),
        signable(kp, fields({ nonce: 'q-8' })),
        'poll',
      ),
    ).toThrow(/selfOnlyRules/);
  });

  test('target 的大小写与连字符不是权限：归一化后仍是本机 ⇒ 放行', () => {
    // 签名覆盖的是客户端写下的原始串（这里就是小写带连字符那一串），
    // 而"能不能读这条队列"判的是归一化之后的同一个地址码。
    const mixed = SELF.slice(0, 9).toLowerCase() + '-' + SELF.slice(9).toLowerCase();
    const out = events.authorizeClientEvent(
      contract,
      stateFor(kp),
      signable(kp, fields({ nonce: 'q-9', target: mixed })),
      'poll',
    );
    expect(out.ok).toBe(true);
  });
  // ── 设备自登记（#131 第一片）：唯一一类"表里还没有他"的事件 ──
  describe('authorizeRegister（私钥持有证明）', () => {
    const kp = keypair();
    const regFields = (over) =>
      fields(
        Object.assign(
          { type: contract.clientEvents.register.messageType, nonce: 'reg-1', body: '' },
          over || {},
        ),
      );
    function regInput(over) {
      const f = regFields(over && over.fields);
      const signed = signable(kp, f);
      return Object.assign(
        { senderAddress: SELF, publicKey: kp.rawBase64, name: '我的手机', now: NOW },
        { fields: signed.fields, signature: signed.signature },
        over && over.extra ? over.extra : {},
      );
    }

    test('合法自登记：放行，并带回地址码与公钥', () => {
      const out = events.authorizeRegister(contract, stateFor(kp), regInput());
      expect(out.ok).toBe(true);
      expect(out.addressCode).toBe(SELF);
      expect(out.publicKey).toBe(kp.rawBase64);
      expect(out.name).toBe('我的手机');
    });

    test('公钥形状不对与签名不匹配同形（登记入口不许当枚举器）', () => {
      const badShape = events.authorizeRegister(
        contract,
        stateFor(kp),
        Object.assign(regInput(), { publicKey: 'not-a-key' }),
      );
      const otherKey = keypair();
      const mismatchFields = regFields();
      const signedByOther = signable(otherKey, mismatchFields);
      const badSig = events.authorizeRegister(
        contract,
        stateFor(kp),
        Object.assign(regInput(), {
          fields: signedByOther.fields,
          signature: signedByOther.signature,
        }),
      );
      expect(badShape.ok).toBe(false);
      expect(badSig.ok).toBe(false);
      expect(badShape.status).toBe(badSig.status);
      expect(badShape.status).toBe(statusCode(contract, 'forbidden'));
      // 内部仍分得开（将来要能显示"有 N 次拿着别人的钥匙来登记"）
      expect(badShape.reason).not.toBe(badSig.reason);
    });

    test('带私钥来的包连验签都不进 ⇒ 拒绝', () => {
      const out = events.authorizeRegister(
        contract,
        stateFor(kp),
        Object.assign(regInput(), { privateKey: 'MFIB私钥' }),
      );
      expect(out.ok).toBe(false);
      expect(out.reason).toMatch(/^carries-secret:privateKey/);
    });

    test('拿 poll 的签名来登记 ⇒ 事件类型不对（跨接口冒用同样被挡）', () => {
      const signed = signable(kp, fields({ nonce: 'cross-1' })); // type = poll
      const out = events.authorizeRegister(
        contract,
        stateFor(kp),
        Object.assign(regInput(), { fields: signed.fields, signature: signed.signature }),
      );
      expect(out.ok).toBe(false);
      expect(out.reason).toMatch(/^wrong-event-type:/);
    });

    test('target 填别人的地址码 ⇒ 拒（登记只能关于自己）', () => {
      const signed = signable(kp, regFields({ target: OTHER }));
      const out = events.authorizeRegister(
        contract,
        stateFor(kp),
        Object.assign(regInput(), { fields: signed.fields, signature: signed.signature }),
      );
      expect(out.ok).toBe(false);
      expect(out.reason).toBe('target-not-self');
    });

    test('契约把 verifyAgainst 改错 ⇒ 抛，不是静默按另一把钥匙验', () => {
      const broken = JSON.parse(JSON.stringify(contract));
      broken.clientEvents.register.verifyAgainst = 'device-table-public-key';
      expect(() => events.authorizeRegister(broken, stateFor(kp), regInput())).toThrow(
        /verifyAgainst/,
      );
    });
  });

  // ── 配对链的两步（#131 第二片 2B）：A 把自己那枚口令挂上，B 带着它来握手 ──
  describe('authorizePairArm 与 authorizePair', () => {
    const CODE = 'ABCDEFGHJKMNPQRSTVWX'; // 20 位 Crockford（不含 I L O U）
    const kpArm = keypair();
    const peerKey = keypair();

    /// 握手这一侧要看的表比 poll/ack 多：签名者必须在表里，**对方**也得在表里且挂着口令。
    /// 挂口令用的是 `devicestore.armPairingCode` 本尊（不是手搓一个形状），
    /// 所以这条链测的是"生产里那两个纯函数真被串起来了"。
    function stateArmed() {
      const devices = {
        [SELF]: { publicKey: kpArm.rawBase64, status: 'active' },
        [OTHER]: { publicKey: peerKey.rawBase64, status: 'active' },
      };
      require('../lib/fnthink/devicestore').armPairingCode(contract, devices, OTHER, CODE, NOW);
      return { devices, nonces: {}, persist() {} };
    }

    const armFields = (over) =>
      fields(
        Object.assign(
          {
            type: contract.clientEvents.pairArm.messageType,
            body: JSON.stringify({ pairingCode: CODE }),
            nonce: 'arm-1',
          },
          over || {},
        ),
      );
    const pairFields = (over) =>
      fields(
        Object.assign(
          {
            type: contract.clientEvents.pair.messageType,
            target: OTHER,
            body: JSON.stringify({ pairingCode: CODE, level: 'L1' }),
            nonce: 'pr-1',
          },
          over || {},
        ),
      );

    test('A 挂口令：签一条 pairArm 就通过，口令原样交给路由去落摘要', () => {
      const out = events.authorizePairArm(contract, stateArmed(), signable(kpArm, armFields()));
      expect(out.ok).toBe(true);
      expect(out.addressCode).toBe(SELF);
      expect(out.pairingCode).toBe(CODE);
    });

    test('载荷键集多一个少一个都判：那是一枚口令的位置，不许由实现猜', () => {
      const extra = events.authorizePairArm(
        contract,
        stateArmed(),
        signable(kpArm, armFields({ body: JSON.stringify({ pairingCode: CODE, level: 'L3' }) })),
      );
      expect(extra.ok).toBe(false);
      expect(extra.reason).toMatch(/^pairArm-fields:/);
      const missing = events.authorizePairArm(
        contract,
        stateArmed(),
        signable(kpArm, armFields({ body: JSON.stringify({ level: 'L1' }) })),
      );
      expect(missing.reason).toMatch(/^pairArm-fields:/);
    });

    test('body 不是 JSON ⇒ malformed-pairArm（与 ack 同一套 reason 形状）', () => {
      const out = events.authorizePairArm(
        contract,
        stateArmed(),
        signable(kpArm, armFields({ body: '不是 JSON' })),
      );
      expect(out.reason).toBe('malformed-pairArm');
    });

    test('口令形状不对 ⇒ 拒，且与"口令不对"用同一句话（不许成为口令格式探针）', () => {
      const out = events.authorizePairArm(
        contract,
        stateArmed(),
        signable(kpArm, armFields({ body: JSON.stringify({ pairingCode: '短' }) })),
      );
      expect(out.ok).toBe(false);
      expect(out.reason).toBe('pairing-code');
      expect(out.status).toBe(statusCode(contract, 'forbidden'));
    });

    test('pairArm 的 target 填别人 ⇒ 拒：挂口令只能关于自己', () => {
      const out = events.authorizePairArm(
        contract,
        stateArmed(),
        signable(kpArm, armFields({ target: OTHER })),
      );
      expect(out.reason).toBe('target-not-self');
    });

    test('拿 poll 的签名来挂口令 ⇒ 拒（三种事件共用签字节，type 必须各走各的门）', () => {
      const out = events.authorizePairArm(
        contract,
        stateArmed(),
        signable(kpArm, armFields({ type: contract.clientEvents.poll.messageType })),
      );
      expect(out.reason).toMatch(/^wrong-event-type:/);
    });

    test('B 握手成功：口令被消耗，返回的是"谁向谁请求了什么"，**没有任何授权**', () => {
      const state = stateArmed();
      const out = events.authorizePair(contract, state, signable(kpArm, pairFields()));
      expect(out.ok).toBe(true);
      expect(out.target).toBe(OTHER);
      expect(out.requester).toBe(SELF);
      expect(out.requesterPublicKey).toBe(kpArm.rawBase64);
      expect(out.level).toBe('L1');
      // 摘要而不是明文：这条就是"表会跟着备份走"那一条红线的落点。
      expect(out.codeDigest).toMatch(/^[0-9a-f]{64}$/);
      expect(JSON.stringify(out)).not.toContain(CODE);
      // 一次配对只配一台：口令已消耗，第二次同码必须不再成立。
      const again = events.authorizePair(
        contract,
        state,
        signable(kpArm, pairFields({ nonce: 'pr-2' })),
      );
      expect(again.ok).toBe(false);
    });

    test('target 填自己 ⇒ 拒（自己跟自己配对就是没有落在任何人屏幕上的那次确认）', () => {
      const out = events.authorizePair(
        contract,
        stateArmed(),
        signable(kpArm, pairFields({ target: SELF })),
      );
      expect(out.reason).toBe('counterpart-is-self');
    });

    test('免本地确认的档位上限从契约引用：L3 来了 ⇒ 拒', () => {
      const ceiling = contract.pairing.maxRequestableLevelWithoutLocalAuth;
      const rank = (l) => contract.capabilities.levels.indexOf(l);
      expect(rank(ceiling)).toBeLessThan(rank('L3'));
      const out = events.authorizePair(
        contract,
        stateArmed(),
        signable(kpArm, pairFields({ body: JSON.stringify({ pairingCode: CODE, level: 'L3' }) })),
      );
      expect(out.ok).toBe(false);
      expect(out.reason).toMatch(/^level-too-high:/);
    });

    test('引用被改歪 ⇒ 抛（拿不到上限时不许"那就不限"）', () => {
      const broken = JSON.parse(JSON.stringify(contract));
      broken.clientEvents.pair.levelCeilingFrom = 'pairing.notThere';
      expect(() =>
        events.authorizePair(broken, stateArmed(), signable(kpArm, pairFields())),
      ).toThrow(/levelCeilingFrom/);
    });

    test('四种"口令没过"对外同一个形状（服务端不许是"谁挂着口令"的枚举器）', () => {
      const shape = (out) => JSON.stringify([out.ok, out.status, out.reason]);
      const unknownTarget = events.authorizePair(
        contract,
        (() => {
          const devices = { [SELF]: { publicKey: kpArm.rawBase64, status: 'active' } };
          return { devices, nonces: {}, persist() {} };
        })(),
        // 一个**合法但表里没有**的地址码（18 位）：这条与"口令错"必须同形，
        // 否则 /pair 就是一台"哪些地址码挂着口令"的枚举器。
        signable(kpArm, pairFields({ target: 'ABCDEFGHJKMNPQRSTV' })),
      );
      const notArmed = events.authorizePair(
        contract,
        (() => {
          const devices = {
            [SELF]: { publicKey: kpArm.rawBase64, status: 'active' },
            [OTHER]: { publicKey: peerKey.rawBase64, status: 'active' },
          };
          return { devices, nonces: {}, persist() {} };
        })(),
        signable(kpArm, pairFields({ nonce: 'pr-3' })),
      );
      const wrongState = stateArmed();
      const wrongCode = events.authorizePair(
        contract,
        wrongState,
        signable(
          kpArm,
          pairFields({
            body: JSON.stringify({ pairingCode: 'ZZZZZZZZZZZZZZZZZZZZ', level: 'L1' }),
          }),
        ),
      );
      const late = NOW + contract.identity.pairingCode.ttlSeconds * 1000 + 1000;
      const expiredState = stateArmed();
      const expired = events.authorizePair(
        contract,
        expiredState,
        signable(kpArm, pairFields({ nonce: 'pr-4', ts: String(Math.floor(late / 1000)) }), late),
      );
      const shapes = [unknownTarget, notArmed, wrongCode, expired].map(shape);
      expect(shapes[0]).toBe(shapes[1]);
      expect(shapes[1]).toBe(shapes[2]);
      expect(shapes[2]).toBe(shapes[3]);
      expect(notArmed.status).toBe(statusCode(contract, 'unauthorized'));
    });

    test('一次过期不烧口令：消耗排在全部判据之后', () => {
      const state = stateArmed();
      // ts 落在容差之外，而服务端时间就是 NOW —— 这条必须被判"过期"。
      // ⚠ 反过来写（把 input.now 也一起拧到过去）判据是过不了的，那样测的其实是"时钟一致"。
      const stale = NOW - (contract.signature.maxSkewSeconds + 30) * 1000;
      const out = events.authorizePair(
        contract,
        state,
        signable(kpArm, pairFields({ ts: String(Math.floor(stale / 1000)) })),
      );
      expect(out.receipt).toBe('expired');
      // 口令还该能用：拿它再走一次正常握手（另一个 nonce）必须成功。
      // 这条就是"顺序即判据"的证据 —— 消耗如果提前，一次网络重试就白烧一枚有效口令，
      // 而 A 屏幕上那张二维码还没被人扫过，现场看起来与"配对失败"一模一样。
      const ok = events.authorizePair(
        contract,
        state,
        signable(kpArm, pairFields({ nonce: 'pr-5' })),
      );
      expect(ok.ok).toBe(true);
    });

    test('两步串起来：挂上之后才配得上，没挂之前一条都配不成', () => {
      const armed = stateArmed();
      const fresh = (() => {
        const devices = {
          [SELF]: { publicKey: kpArm.rawBase64, status: 'active' },
          [OTHER]: { publicKey: peerKey.rawBase64, status: 'active' },
        };
        return { devices, nonces: {}, persist() {} };
      })();
      const before = events.authorizePair(contract, fresh, signable(kpArm, pairFields()));
      expect(before.ok).toBe(false);
      const after = events.authorizePair(
        contract,
        armed,
        signable(kpArm, pairFields({ nonce: 'pr-6' })),
      );
      expect(after.ok).toBe(true);
    });
  });
});
