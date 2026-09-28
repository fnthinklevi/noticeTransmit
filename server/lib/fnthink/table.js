// fnthink 各表的落盘底座（T27 建立，T34-B 抽出一处共用）。
//
// 这里放的是**与具体表无关**的三件事：0600 权限 + 原子写 + 明文凭证闸门。
// 抽出来的理由和当初写它的理由一样：闸门复制一份就会漂移一份，
// 而"消息表也自己扫一遍"的下场是——某张表哪天忘了扫，没人会报错。
// devicestore / messagestore 都从这里过，谁都不许再写第二份。

'use strict';

const path = require('path');

const { DATA_DIR, readJsonFile, writeJsonFile } = require('../store');
const { assertSupported, loadContract } = require('./contract');
const { alphabetFromContract, lengthFromContract, normalize } = require('./credentials');

const FILE_MODE = 0o600;
const TABLE_VERSION = 1;

/// 会被当成"存了明文凭证"的字段名；以 `Digest` 结尾的除外（那正是允许落盘的形式）。
const SECRETISH = /pairingcode|secret|token|privatekey|passphrase|pin/i;
const DIGEST_ONLY = /digest$/i;
const HEX64 = /^[0-9a-f]{64}$/;

/** 深扫结构，拒绝任何"像凭证却不是摘要"的字段。 */
function assertNoPlaintextSecrets(contract, node, trail) {
  const where = trail || '$';
  if (Array.isArray(node)) {
    node.forEach((item, i) => assertNoPlaintextSecrets(contract, item, `${where}[${i}]`));
    return;
  }
  if (node && typeof node === 'object') {
    for (const [key, value] of Object.entries(node)) {
      const at = `${where}.${key}`;
      if (SECRETISH.test(key) && !DIGEST_ONLY.test(key)) {
        throw new Error(`${at} 看起来是明文凭证，一律不落盘（要存就存摘要，键名以 Digest 结尾）`);
      }
      if (DIGEST_ONLY.test(key) && typeof value === 'string' && !HEX64.test(value)) {
        throw new Error(`${at} 以 Digest 结尾却不是 64 位十六进制摘要：${value}`);
      }
      // 键名可以起错，值不会说谎：任何字段里塞进一把"形状正确的口令"都拦下来，
      // 于是 `name: '口令是 XXXXXXXXXXXXXXXXXXXX'` 这种"就存这一次"也过不去。
      if (typeof value === 'string' && looksLikeCredential(contract, value)) {
        throw new Error(`${at} 的值是一把形状完整的口令（${value.length} 位），拒绝落盘`);
      }
      assertNoPlaintextSecrets(contract, value, at);
    }
  }
}

/// 只认**秘密**那两档长度（配对口令、端点长期口令）。地址码是公开标识，不参与判定。
function looksLikeCredential(contract, text) {
  const normalized = normalize(alphabetFromContract(contract), text);
  if (normalized === null) return false;
  const lengths = ['pairingCode', 'endpointSecret'].map((which) => {
    try {
      return lengthFromContract(contract, which);
    } catch (e) {
      return -1;
    }
  });
  return lengths.includes(normalized.length);
}

function loadTable(filePath, key) {
  const raw = readJsonFile(filePath, null);
  if (!raw || typeof raw !== 'object' || !raw[key] || typeof raw[key] !== 'object') return {};
  return raw[key];
}

/// 写咽喉自己读的这份契约：与调用方传进来的无关，就是为了让"任何一次落盘"都过同一道闸。
let writeContract = null;
function contractForWrite() {
  if (!writeContract) writeContract = assertSupported(loadContract());
  return writeContract;
}

function saveTable(filePath, key, table) {
  assertNoPlaintextSecrets(contractForWrite(), table, key);
  // 写不进去必须抛：静默返回会让调用方以为"设备已登记 / 口令已消耗"，
  // 而对端什么都不知道 —— 宁可 500，也不要一次假装成功的配对。
  if (!writeJsonFile(filePath, { version: TABLE_VERSION, [key]: table }, { mode: FILE_MODE })) {
    throw new Error(`写入 ${filePath} 失败（没落盘就不算成功）`);
  }
  return table;
}

module.exports = {
  DATA_DIR,
  FILE_MODE,
  TABLE_VERSION,
  assertNoPlaintextSecrets,
  contractForWrite,
  loadTable,
  looksLikeCredential,
  saveTable,
};
