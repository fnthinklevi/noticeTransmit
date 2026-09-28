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

  test('关掉契约那条开关，行为立刻跟着变（证明判据没在本层存第二份）', () => {
    // ⚠ 这条断言的是**一份 mutate 出来的副本**上的行为，不是被放宽的真实协议：
    // 真实契约里 targetMustEqualSender 必须为 true，由 fnthink_push 的 validate() 钉着
    // （有一条 mutate 反证专抓它被改成 false）。这里要的只是「代码读契约、不读自己的常量」
    // 这一件事被证明 —— 否则改契约不会改变行为，那张表就是装饰。
    const relaxed = JSON.parse(JSON.stringify(contract));
    relaxed.clientEvents.poll.targetMustEqualSender = false;
    const out = events.authorizeClientEvent(
      relaxed,
      stateFor(kp),
      signable(kp, fields({ nonce: 'q-1', target: OTHER })),
      'poll',
    );
    expect(out.ok).toBe(true);
    // 同一份放宽后的表上，另一条判据仍然生效（不是"整层放行"）：
    // 事件类型不能冒用，ack 的 result 仍须落在回执词表里。
    const stillChecked = events.authorizeClientEvent(
      relaxed,
      stateFor(kp),
      signable(kp, fields({ nonce: 'q-2' })),
      'ack',
    );
    expect(stillChecked.ok).toBe(false);
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
});
