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
const { rememberNonce, seenNonce, saveNonces } = require('./devicestore');

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
  const forbidden = {
    ok: false,
    status: statusCode(contract, 'forbidden'),
    receipt: 'rejected_unsigned',
  };
  const sender = normalize(alphabetFromContract(contract), input.senderAddress || '');
  const device = sender === null ? undefined : state.devices[sender];

  let canonical;
  try {
    canonical = canonicalBytes(contract, input.fields || {});
  } catch (e) {
    // 客户端算的串我们不用；字段不齐是它的错，但**先不透露设备存不存在**，所以同形返回
    return forbidden;
  }

  // ① + ②：没有记录、被冻结、公钥形状不对、验签失败 —— 四种都长同一个样
  if (!device || device.status === 'frozen') return forbidden;
  if (!verifySignature(contract, device.publicKey, canonical, input.signature)) return forbidden;

  // 以下都在"身份已被证明"之后，可以照实说
  const skew = Number((contract.signature || {}).maxSkewSeconds || 0);
  const ts = Number(input.fields.ts);
  if (!Number.isFinite(ts) || Math.abs(input.now - ts * 1000) > skew * 1000) {
    return { ok: false, status: statusCode(contract, 'expired'), receipt: 'expired' };
  }
  const nonceKey = `${sender}|${input.fields.nonce}`;
  if (seenNonce(state.nonces, nonceKey, input.now)) {
    return { ok: false, status: statusCode(contract, 'duplicate'), receipt: 'duplicate' };
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

module.exports = {
  publicKeyFromRaw,
  canonicalBytes,
  verifySignature,
  acceptIncoming,
};
