// 幻念推送消息级验签（T29-B）· 服务端这一半。
//
// 三条决定写法的规则，都来自契约，不在这里重述数值：
//  ① **公钥只从设备表取，绝不信请求里自带的公钥** —— 否则任何人都能用自己造的钥匙签一条，
//     然后声称自己是任意一个地址码；
//  ② **先验签、再看时间、最后查重放**：顺序决定哪些失败可以对外说清楚。
//     "设备不存在"与"签名不对"必须同一个形状（否则这接口是个地址码枚举器），
//     而验签通过之后，`410 已过期`/`409 重复` 可以照实返回 —— 那时对方身份已被证明；
//  ③ 规范化字节由**服务端按契约重算**，不接受客户端算好的串：契约顺序的意义就在这儿。
//
// 没有 HTTP 路由是故意的（roadmap §4 第 7 条：公网面只开一次，与 T28-B 一起评审）。

'use strict';

const crypto = require('crypto');

const { statusCode } = require('./contract');
const { normalize, alphabetFromContract } = require('./credentials');
const { decideCapability, grantFromRecord } = require('./capabilities');
const {
  rememberNonce,
  rememberReject,
  rejectKeyFor,
  seenNonce,
  saveNonces,
} = require('./devicestore');

/// 裸 32 字节 base64 → KeyObject。DER 头来自契约（Kotlin 那份由跨语言守卫对表）。
function publicKeyFromRaw(contract, publicKeyB64) {
  const encoding = (contract.signature || {}).publicKeyEncoding || {};
  const prefix = Buffer.from(String(encoding.spkiPrefixHex || ''), 'hex');
  const rawLength = Number(encoding.rawLength || 0);
  if (prefix.length !== 12 || rawLength !== 32) {
    throw new Error('契约的 publicKeyEncoding 不完整（需要 12 字节 spkiPrefixHex + rawLength=32）');
  }
  const raw = Buffer.from(String(publicKeyB64 || ''), 'base64');
  if (raw.length !== rawLength) {
    throw new Error(`公钥解出 ${raw.length} 字节，应为 ${rawLength}`);
  }
  return crypto.createPublicKey({
    key: Buffer.concat([prefix, raw]),
    format: 'der',
    type: 'spki',
  });
}

/// 按契约顺序 + 契约分隔符拼出待签字节（与 Dart 的 CanonicalMessage.bytes 同一套规则）。
function canonicalBytes(contract, fields) {
  const order = (contract.signature || {}).canonicalOrder || [];
  const separator = String((contract.signature || {} || {}).separator || '');
  if (order.length === 0 || separator === '') {
    throw new Error('契约缺 signature.canonicalOrder 或 separator');
  }
  const parts = order.map((key) => {
    if (fields[key] === undefined || fields[key] === null) {
      throw new Error(
        `签名字段 "${key}" 缺失（不补空串：那会让"没填"与"填了空值"签出同一个字节串）`,
      );
    }
    const text = String(fields[key]);
    if (text.indexOf(separator) >= 0) {
      throw new Error(`签名字段 "${key}" 的值含分隔符，拼接边界会歧义`);
    }
    return text;
  });
  return Buffer.from(parts.join(separator), 'utf8');
}

/// 只做密码学判断，不碰设备表（调用方负责"公钥从哪来"）。
function verifySignature(contract, publicKeyB64, canonical, signatureB64) {
  try {
    return crypto.verify(
      null,
      canonical,
      publicKeyFromRaw(contract, publicKeyB64),
      Buffer.from(String(signatureB64 || ''), 'base64'),
    );
  } catch (e) {
    return false; // 钥匙形状不对与验签失败同形：都不该被分辨
  }
}

/// 一次入站消息的完整裁决。`now` 由调用方注入（服务端时间，且测试要能把时钟拧动）。
function acceptIncoming(contract, state, input) {
  // 每次现造一个对象：同形那条判据要真的比"两份各自造出来的东西"，
  // 复用同一个实例会让断言在"其实两条走法形状不同"被改坏的那一天也照样绿。
  const forbidden = (reason) =>
    counted(
      contract,
      state,
      input,
      { ok: false, status: statusCode(contract, 'forbidden'), receipt: 'rejected_unsigned' },
      reason,
    );
  // 留痕与对外形状是两件事：`reason` 只进 state.rejects，**绝不出现在响应里**，
  // 所以"未知设备"和"签名不对"在服务端内部可分辨（将来显示"有 N 次冒充你的尝试"），
  // 在网络上看仍是同一个包。
  const sender = normalize(alphabetFromContract(contract), input.senderAddress || '');
  const device = sender === null ? undefined : state.devices[sender];

  let canonical;
  try {
    canonical = canonicalBytes(contract, input.fields || {});
  } catch (e) {
    // 客户端算的串我们不用；字段不齐是它的错，但**先不透露设备存不存在**，所以同形返回
    return forbidden('fields');
  }

  // ① + ②：没有记录、状态不在白名单里、公钥形状不对、验签失败 —— 这几种都长同一个样。
  // ⚠ 判定问的是"这台设备的状态在不在**允许投递**那张表里"，不是"它是不是 frozen"：
  // 后者是黑名单，将来契约新增一个状态（如 awaitingRepair）会静默地"没被枚举到 = 继续投递"。
  const allowedStatuses = (contract.revocation || {}).deliveryAllowedStatuses || [];
  if (!device) return forbidden('unknown_device');
  if (!allowedStatuses.includes(device.status)) return forbidden('status:' + device.status);
  if (!verifySignature(contract, device.publicKey, canonical, input.signature))
    return forbidden('signature');

  // ── 以下是"身份已被证明"的区域，可以照实说（T27/T28 那条同形规则到此为止）──
  const denied = (receipt, reason) =>
    counted(
      contract,
      state,
      input,
      { ok: false, status: statusCode(contract, 'forbidden'), receipt },
      reason,
    );
  // 授权判定要用的 item 必须**出现在已签字节里**：签名覆盖的是 body，
  // 从一个没签过的字段里读"要执行哪个动作"，等于给中间人（或给服务端自己的一次误接）
  // 留一个"借一条已签通知触发一个没签过的动作"的口子。
  const item = typeof input.item === 'string' ? input.item : '';
  if (item !== '' && canonical.toString('utf8').indexOf(item) < 0) {
    return denied('rejected_capability', 'unsigned-item');
  }
  const cap = decideCapability(contract, {
    // 收单这一段判不了"每次本地确认"：那是设备上的一次用户动作。
    // ⚠ 这里**故意不读** `input.confirmedThisTime` —— 从请求里取那个值，
    // 等于让发送方替接收方点"我确认了"，而 L3 那条红线写的正是"不许远端悄悄执行本地动作"。
    stage: 'intake',
    grant: grantFromRecord(contract, device),
    type: String(input.fields.type),
    item,
  });
  if (!cap.allowed) return denied('rejected_capability', 'capability:' + cap.reason);

  // 时间容差与重放
  const skew = Number((contract.signature || {}).maxSkewSeconds || 0);
  const ts = Number(input.fields.ts);
  if (!Number.isFinite(ts) || Math.abs(input.now - ts * 1000) > skew * 1000) {
    return counted(
      contract,
      state,
      input,
      { ok: false, status: statusCode(contract, 'expired'), receipt: 'expired' },
      'expired',
    );
  }
  const nonceKey = `${sender}|${input.fields.nonce}`;
  if (seenNonce(state.nonces, nonceKey, input.now)) {
    return counted(
      contract,
      state,
      input,
      { ok: false, status: statusCode(contract, 'duplicate'), receipt: 'duplicate' },
      'duplicate',
    );
  }
  rememberNonce(
    state.nonces,
    nonceKey,
    input.now,
    Number((contract.signature || {}).nonceDedupeSeconds || 0),
  );
  // 去重表必须落盘：只在内存里记一遍，等于每次重启就重开一次重放窗口。
  // 传了 saveNonces 却不落盘 = "记住了"和"重启还记得"是两件事，这里把后者也接上。
  if (typeof state.persist === 'function') state.persist();
  else saveNonces(state.nonces);
  return { ok: true, status: statusCode(contract, 'queued'), receipt: 'queued' };
}

/// 拒收都要计一次数（任务书"失败即丢并计数"那条）。只写内存，理由见 devicestore 那段注释。
function counted(contract, state, input, outcome, reason) {
  const rejects = state.rejects || (state.rejects = {});
  rememberReject(rejects, rejectKeyFor(contract, input.senderAddress), input.now, reason);
  return outcome;
}

module.exports = {
  publicKeyFromRaw,
  canonicalBytes,
  verifySignature,
  acceptIncoming,
};
