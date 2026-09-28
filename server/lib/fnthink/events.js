// 设备自己签的两类事件（T32 的 poll、T35 的 ack）：契约 clientEvents 段的执行处。
//
// 为什么不塞进 verify.js：verify.js 判的是「一条消息能不能收」，这里判的是「一台设备能不能问
// 它自己该问的事」。两者**共用身份段与重放段**（从 verify.js 引过来），不共用中间那层裁决 ——
// 消息要过 capabilities 的 type 词表，而事件按契约必须**不**在那张表里，所以接进
// acceptIncoming 只会让两条路互相判红。
//
// 与 acceptIncoming 同样的顺序纪律：身份之内一律同形（不透露这台设备存不存在），
// 身份证明之后才分辨 410 过期 / 409 重复 / 403 这个事件本身不合法。
// ⚠ 事件类型检查排在时间/重放**之前**：拿错接口的签名应该先被「事件不对」挡下，
//   而不是顺手消耗掉一个 nonce —— 那会让客户端一次正常的重试变成一次「重复」。

'use strict';

const { statusCode, isReceipt } = require('./contract');
const { rememberReject, rejectKeyFor, assertPublicKey } = require('./devicestore');
const { canonicalBytes, verifyIdentity, verifySignature, checkFresh } = require('./verify');
const { alphabetFromContract, normalize } = require('./credentials');

/// 身份证明之后的拒绝：状态码照实给，`reason` 只进留痕、绝不进响应体。
function denied(contract, state, input, reason) {
  const rejects = state.rejects || (state.rejects = {});
  rememberReject(
    rejects,
    rejectKeyFor(contract, input.senderAddress),
    input.now,
    'event:' + reason,
  );
  return { ok: false, status: statusCode(contract, 'forbidden'), reason };
}

/**
 * 一次设备事件的裁决。`kind` 只认契约 clientEvents 里声明过的那几种。
 *
 * 返回：
 *  - 失败 `{ok:false, status, reason}`（reason 仅内部留痕，对外形状由路由按 status 决定）
 *  - poll   `{ok:true, kind:'poll', sender, serverTime}`
 *  - ack    `{ok:true, kind:'ack', sender, messageId, result}`
 *
 * ⚠ 这里**不查消息表**：ack 那句「只能 ack 下发给自己的那一条」要有 messageId 的归属才判得了，
 * 那是路由侧拿着表来做的事；本文件只判事件自身的形状与签名。契约那一条的前半段
 * （target 必须是本机）在这里判，后半段在路由判 —— 注释写清，免得后来人以为这里已经判全了。
 */
function authorizeClientEvent(contract, state, input, kind) {
  const spec = (contract.clientEvents || {})[kind];
  if (!spec) {
    throw new Error(`契约没有 clientEvents.${kind} 段（不补默认值：补了等于在代码里发明一种事件）`);
  }

  const id = verifyIdentity(contract, state, input);
  if (id.outcome) return id.outcome;
  const fields = input.fields || {};

  if (String(fields.type) !== spec.messageType) {
    return denied(contract, state, input, 'wrong-event-type:' + String(fields.type));
  }
  // 两类事件都只能关于**自己**：poll 靠 targetMustEqualSender，ack 靠 onlyForOwnMessages 的前半段。
  const selfOnly = spec.targetMustEqualSender === true || spec.onlyForOwnMessages === true;
  if (selfOnly && String(fields.target) !== id.sender) {
    return denied(contract, state, input, 'target-not-self');
  }

  const fresh = checkFresh(contract, state, input, id.sender);
  if (fresh.outcome) return fresh.outcome;

  if (kind === 'poll') {
    return { ok: true, kind: 'poll', sender: id.sender, serverTime: input.now };
  }
  if (kind === 'ack') {
    if (spec.resultMustBeReceipt !== true) {
      throw new Error(
        '契约 clientEvents.ack.resultMustBeReceipt 必须为 true，否则 result 是个自由字符串',
      );
    }
    let payload;
    try {
      payload = JSON.parse(String(fields.body));
    } catch (e) {
      return denied(contract, state, input, 'malformed-ack');
    }
    if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) {
      return denied(contract, state, input, 'malformed-ack');
    }
    const want = (spec.fields || []).slice().sort().join('|');
    const got = Object.keys(payload).slice().sort().join('|');
    if (got !== want) {
      return denied(contract, state, input, `ack-fields:期望 [${want}] 实到 [${got}]`);
    }
    if (!isReceipt(contract, payload.result)) {
      return denied(contract, state, input, 'unknown-result:' + String(payload.result));
    }
    return {
      ok: true,
      kind: 'ack',
      sender: id.sender,
      messageId: String(payload.messageId),
      result: String(payload.result),
    };
  }
  // 契约加了第三种事件而这里没实现：**必须抛**，不能 fall through 到"当成 poll 放行"。
  throw new Error(`events.js 没有实现事件类型 "${kind}"（契约声明了它，代码没判它）`);
}

/**
 * 设备自登记（契约 `clientEvents.register`）：唯一一类"表里还没有他"的事件。
 *
 * 与 poll/ack 唯一的区别是**用哪把钥匙验签**，而这件事由契约的 `verifyAgainst` 说，
 * 不由这里写死（写死的下一种事件类型会默认落到"查表"那条分支上，然后静默拒绝所有新设备）。
 * 用请求自带的公钥验，证明的是「提交者持有这把私钥」，不是「他是白名单里的谁」——
 * 此刻还没有任何名单。地址码由设备自己生成（`identity.generator=csprng`，不从公钥推导），
 * 所以这里不校验两者的绑定关系；真正的绑定发生在第二次同码登记时：
 * `devicestore.registerDevice` 遇到"同一地址码换公钥"必须抛，而不是覆盖。
 */
function authorizeRegister(contract, state, input) {
  const spec = (contract.clientEvents || {}).register;
  if (!spec) {
    throw new Error('契约没有 clientEvents.register（不补默认值：补了就等于在代码里发明一种事件）');
  }
  // 契约说这把钥匙从哪来，这里就照它做；对不上直接抛，而不是「照旧走一遍」——
  // 静默按另一条路验，等于契约那行变成了注释，而这一步的强度完全取决于用哪把钥匙。
  if (spec.verifyAgainst !== 'presented-public-key') {
    throw new Error(
      `clientEvents.register.verifyAgainst = ${spec.verifyAgainst}：自登记时表里还没有这个设备，` +
        '只能按请求自带的公钥验（私钥持有证明）。要改成查表验，先想清新设备怎么进来。',
    );
  }
  const fields = input.fields || {};
  const forbidden = (reason) => {
    const rejects = state.rejects || (state.rejects = {});
    rememberReject(
      rejects,
      rejectKeyFor(contract, input.senderAddress),
      input.now,
      `register:${reason}`,
    );
    return { ok: false, status: statusCode(contract, 'forbidden'), reason };
  };

  // 禁带字段先判：带私钥来的包，连"是谁"都不必回答就该被丢掉。
  const banned = (spec.mayNotCarry || []).filter((f) =>
    Object.prototype.hasOwnProperty.call(input, f),
  );
  if (banned.length) return forbidden(`carries-secret:${banned.join(',')}`);

  const sender = normalize(alphabetFromContract(contract), input.senderAddress || '');
  if (sender === null) return forbidden('address-code');
  if (String(fields.type) !== spec.messageType) {
    return forbidden(`wrong-event-type:${String(fields.type)}`);
  }
  if (spec.targetMustEqualSender === true && String(fields.target) !== sender) {
    return forbidden('target-not-self');
  }
  const publicKey = typeof input.publicKey === 'string' ? input.publicKey : '';
  let canonical;
  try {
    canonical = canonicalBytes(contract, fields);
    assertPublicKey(publicKey);
    if (!verifySignature(contract, publicKey, canonical, input.signature)) {
      return forbidden('signature');
    }
  } catch (e) {
    // 公钥形状不对与签名不对同形：都不该被分辨（分辨 = 一台服务器在替人枚举"哪种钥匙存在"）
    return forbidden('key-or-signature');
  }

  const fresh = checkFresh(contract, state, input, sender);
  if (fresh.outcome) return fresh.outcome;

  const name = typeof input.name === 'string' ? input.name.slice(0, 60) : '';
  return { ok: true, kind: 'register', addressCode: sender, publicKey, name };
}

module.exports = { authorizeClientEvent, authorizeRegister };
