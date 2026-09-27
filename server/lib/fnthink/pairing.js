// 幻念推送配对载荷（T28）· 服务端这一半：只负责"这份载荷算不算本协议的配对载荷"。
//
// Dart 那一半在 packages/fnthink_push/lib/src/pairing.dart，两端**必须产出同一套 reason 字符串**
// —— 由 protocol/fnthink-vectors-v1.json 的 payloads 段钉住。reason 是内部诊断（日志/回执），
// 不是用户文案：用户那边所有预授权失败都是同一句话（pairing.failureMessageShape）。
//
// 为什么不照搬 fieldTolerance.ignoreUnknownFields=true：那是给第三方推送正文用的（title/body 别名），
// 而配对载荷是**身份交换** —— 在这里容错，等于给对方一个往身份交换里塞料的口子。

'use strict';

const {
  alphabetFromContract,
  normalize,
  isValidAddressCode,
  isValidPairingCode,
} = require('./credentials');

function qrPrefix(contract) {
  const value = (contract.pairing || {}).qrPrefix;
  if (!value) throw new Error('契约缺 pairing.qrPrefix（不补默认前缀）');
  return value;
}

function payloadFields(contract) {
  return ((contract.pairing || {}).payloadFields || []).slice();
}

function neverCarry(contract) {
  return ((contract.pairing || {}).neverCarry || []).slice();
}

function rejectUnknownFields(contract) {
  const value = (contract.pairing || {}).rejectUnknownFields;
  if (typeof value !== 'boolean') {
    throw new Error('契约缺 pairing.rejectUnknownFields（不补默认值）');
  }
  return value;
}

/// 拼一份载荷（服务端正常情况下不发起配对，这里存在只为让"两端产出同一串文本"可被向量测到）。
function buildPairingPayload(contract, request) {
  const values = {
    v: String(request.v),
    to: request.to,
    code: request.code,
    level: request.level,
  };
  for (const field of payloadFields(contract)) {
    if (!(field in values)) {
      throw new Error(`契约要求载荷带 ${field}，本实现不会造这个字段`);
    }
  }
  if (!isValidAddressCode(contract, values.to)) throw new Error('载荷里的地址码不合法');
  if (!isValidPairingCode(contract, values.code)) throw new Error('载荷里的配对口令不合法');
  const levels = (contract.capabilities || {}).levels || [];
  if (!levels.includes(values.level))
    throw new Error(`级别 ${values.level} 不在契约的 ${levels.join('/')} 里`);
  const query = payloadFields(contract)
    .map((f) => `${f}=${values[f]}`)
    .join('&');
  return `${qrPrefix(contract)}?${query}`;
}

/// 解析。**不抛**：返回 {ok:false, reason}。reason 的取值表就是向量文件里那一份。
function parsePairingPayload(contract, text) {
  const fail = (reason) => ({ ok: false, reason });
  if (typeof text !== 'string') return fail('shape:non-string');
  const prefix = `${qrPrefix(contract)}?`;
  if (!text.startsWith(prefix)) return fail('prefix');
  const query = text.slice(prefix.length);
  if (query === '') return fail('empty');

  const fields = new Map();
  for (const part of query.split('&')) {
    const at = part.indexOf('=');
    if (at <= 0) return fail(`shape:${part}`);
    const key = part.slice(0, at);
    if (fields.has(key)) return fail(`repeat:${key}`); // 同一个键出现两次 = 载荷被人拼过
    fields.set(key, part.slice(at + 1));
  }

  if (rejectUnknownFields(contract)) {
    // 先查禁带秘密再查"未知字段"：`signature=` 两者都命中，日志里该看到的是前者。
    for (const key of neverCarry(contract)) {
      if (fields.has(key)) return fail(`carries-secret:${key}`);
    }
    for (const key of fields.keys()) {
      if (!payloadFields(contract).includes(key)) return fail(`unknown:${key}`);
    }
  }

  for (const required of payloadFields(contract)) {
    if (!fields.has(required)) return fail(`missing:${required}`);
  }
  const version = Number(fields.get('v'));
  if (!Number.isInteger(version)) return fail('version-unparseable');
  if (version !== contract.contractVersion) return fail(`version:${version}`);

  const alphabet = alphabetFromContract(contract);
  const to = normalize(alphabet, fields.get('to') || '');
  const code = normalize(alphabet, fields.get('code') || '');
  if (to === null || !isValidAddressCode(contract, to)) return fail('address-code');
  if (code === null || !isValidPairingCode(contract, code)) return fail('pairing-code');
  const level = fields.get('level');
  const levels = (contract.capabilities || {}).levels || [];
  if (!levels.includes(level)) return fail(`level:${level}`);

  return { ok: true, request: { v: version, to, code, level } };
}

module.exports = {
  qrPrefix,
  payloadFields,
  neverCarry,
  rejectUnknownFields,
  buildPairingPayload,
  parsePairingPayload,
};
