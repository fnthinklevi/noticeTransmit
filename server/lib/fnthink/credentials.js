// 幻念推送凭证（T26）· 服务端这一半：地址码 / 配对口令的校验与摘要。
//
// 位数为什么是 18 和 20：地址码要印在二维码和设置页上、要能被人抄给别人，18 位 Crockford
// = 90 bit，随机撞中别人设备的概率低到不需要限流来兜；口令 20 位 = 100 bit，且 5 分钟过期、
// 配对即消耗 —— 口令是"短暂共享一个秘密"，不需要长期熵。
//
// 为什么排除 I L O U：这四个字符和 1 0 V 在人眼和低端屏幕上分不开。凭证设计里"看错一个字符"
// 的成本是用户重配一遍，所以字母表宁可少四个字符。
//
// ⚠ 字母表、排除集、位数、ttl 全部来自仓库根 protocol/fnthink-v1.json；跨端一致性由
// protocol/fnthink-vectors-v1.json 与 server/test/fnthink-credentials.test.js 钉住。

'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const VECTORS_FILE = path.resolve(
  __dirname,
  '..',
  '..',
  '..',
  'protocol',
  'fnthink-vectors-v1.json',
);

const STANDARD_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const STANDARD_EXCLUDED = 'ILOU';

function loadVectors() {
  return JSON.parse(fs.readFileSync(VECTORS_FILE, 'utf8'));
}

/// 字母表闸门：契约若写了别的字母表或别的排除集，这里直接抛。
/// 静默按实现里这份表继续跑，产出的是对端永远解不开的码。
function alphabetFromContract(contract) {
  const identity = (contract && contract.identity && contract.identity.addressCode) || {};
  if (identity.alphabet !== 'crockford-base32') {
    throw new Error(`本模块只实现 crockford-base32，契约写的是 ${identity.alphabet}`);
  }
  if (identity.excludedChars !== STANDARD_EXCLUDED) {
    throw new Error(
      `契约排除集 ${identity.excludedChars} 与实现（${STANDARD_EXCLUDED}）不一致：换排除集是协议变更`,
    );
  }
  return STANDARD_ALPHABET;
}

function lengthFromContract(contract, which) {
  const length =
    contract && contract.identity && contract.identity[which] && contract.identity[which].length;
  if (typeof length !== 'number' || length <= 0) {
    throw new Error(`契约缺 identity.${which}.length（不补默认位数：默认位数等于换协议）`);
  }
  return length;
}

/// 归一化：转大写、丢掉空格与连字符；含字母表以外的字符返回 null。
/// 与 Dart 侧 CrockfordBase32.normalize 必须逐字符等价 —— 由向量文件钉。
function normalize(alphabet, raw) {
  if (typeof raw !== 'string') return null;
  const upper = String(raw).toUpperCase().replace(/[\s-]/g, '');
  for (const char of upper) {
    if (alphabet.indexOf(char) < 0) return null;
  }
  return upper;
}

/// 通用校验：归一化 + 位数。which 就是契约 identity 下的键名，不在这里各写一套。
function isValidCode(contract, which, raw) {
  const normalized = normalize(alphabetFromContract(contract), raw);
  return normalized !== null && normalized.length === lengthFromContract(contract, which);
}

function isValidAddressCode(contract, raw) {
  return isValidCode(contract, 'addressCode', raw);
}

function isValidPairingCode(contract, raw) {
  return isValidCode(contract, 'pairingCode', raw);
}

/// 落盘形式：sha256(归一化值) 的 hex，**明文口令绝不落盘**（T27 红线）。
///
/// [which] 必填并在此完成完整校验（字母表 + 位数）：不合法就抛，而不是返回 null。
/// 两个原因：① 拿没校验过的字符串去查库，等于把"用户输错"变成一次可枚举的查询，
/// 而 null 与"查不到"在这条路径上长得一模一样；② 空串会算出一个**稳定**的摘要，
/// 于是"字段没填"与"填了个空"命中同一条记录 —— 那是配对口子里最经典的一次越权。
function credentialDigest(contract, which, raw) {
  const normalized = normalize(alphabetFromContract(contract), raw);
  const length = lengthFromContract(contract, which);
  if (normalized === null || normalized.length !== length) {
    throw new Error(`不是合法的 identity.${which}（应为 ${length} 位 Crockford），拒绝计算摘要`);
  }
  return crypto.createHash('sha256').update(Buffer.from(normalized, 'ascii')).digest('hex');
}

module.exports = {
  VECTORS_FILE,
  STANDARD_ALPHABET,
  STANDARD_EXCLUDED,
  loadVectors,
  alphabetFromContract,
  lengthFromContract,
  normalize,
  isValidCode,
  isValidAddressCode,
  isValidPairingCode,
  credentialDigest,
};
