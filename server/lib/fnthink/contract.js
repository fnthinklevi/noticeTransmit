// 幻念推送协议契约（T71）· 服务端这一半。
//
// 单一真值是仓库根的 `protocol/fnthink-v1.json`：Dart 侧（packages/fnthink_push）与这里
// 都读同一份，**谁都不许把表抄进代码**。抄一份的下场在本仓库已经见过多次——
// 两份常量一开始一致，第一次改动只落到一边，而它不会报错，只会表现成
// "设备按 7 天排队、服务端第 3 天就删了"这类查不出来的缺陷。
//
// 这里只放取值与两条真正会跑的逻辑（字段容错取词、在线阈值换算），
// 不放业务：端点、投递状态机、能力分级各自在后续任务里实现，都从这里读表。

'use strict';

const fs = require('fs');
const path = require('path');

/// 本模块实现的协议主版本。与契约文件里的 `contractVersion` 不一致就必须拒绝，
/// 而不是"能读多少算多少"——半懂不懂地解释一个新协议比直接报错危险得多。
const SUPPORTED_MAJOR = 1;

/// 契约文件位置：默认取仓库根的 `protocol/`；部署侧（本仓的规矩是"只上传 server/"）
/// 可以用 `FNTHINK_CONTRACT` 把它指过去。为什么留这个口子，而不是把 JSON 复制进 server/：
/// 复制一份协议文件就是第二份真值，而它的表现永远是"改了没生效"。
const CONTRACT_FILE = process.env.FNTHINK_CONTRACT
  ? path.resolve(process.env.FNTHINK_CONTRACT)
  : path.resolve(__dirname, '..', '..', '..', 'protocol', 'fnthink-v1.json');

function loadContract() {
  return JSON.parse(fs.readFileSync(CONTRACT_FILE, 'utf8'));
}

/// 版本闸门：不兼容时抛错（调用方在启动时跑一次，运行期不再判）。
function assertSupported(contract) {
  const declared = /^fnthink-v(\d+)$/.exec(contract.protocol);
  if (!declared) {
    throw new Error(`protocol 名不是 fnthink-v<N> 的形状：${contract.protocol}`);
  }
  if (Number(declared[1]) !== contract.contractVersion) {
    throw new Error(
      `protocol 名里的版本（v${declared[1]}）与 contractVersion（${contract.contractVersion}）不一致`,
    );
  }
  if (contract.contractVersion !== SUPPORTED_MAJOR) {
    throw new Error(
      `契约 contractVersion=${contract.contractVersion}，服务端只实现到 v${SUPPORTED_MAJOR}`,
    );
  }
  return contract;
}

/// 同步响应码表（`_` 开头的说明键与 `indistinguishable` 都不算码）。
function statusCodes(contract) {
  const table = contract.statusCodes || {};
  const out = {};
  for (const [key, value] of Object.entries(table)) {
    if (key.startsWith('_') || key === 'indistinguishable') continue;
    if (typeof value === 'number') out[key] = value;
  }
  return out;
}

function statusCode(contract, name) {
  const value = statusCodes(contract)[name];
  if (value === undefined) {
    throw new Error(`状态码表里没有 ${name}（新增状态必须先改契约文件）`);
  }
  return value;
}

function isReceipt(contract, name) {
  return (contract.receipts || []).includes(name);
}

/// 签名的规范化字节顺序：**顺序本身就是协议**，换序即换签名。
function canonicalOrder(contract) {
  return (contract.signature && contract.signature.canonicalOrder) || [];
}

/// 字段容错的别名表（title / body）。首项就是规范名。
function aliasesFor(contract, field) {
  const list = (contract.fieldTolerance || {})[field] || [];
  return list;
}

/// 按契约的"取第一个非空"规则从外部载荷里取一个规范字段。
/// 这是本模块唯一真正跑在请求路径上的函数：每接一个新平台都要改服务端，
/// 就是因为没有这一层（别名表可以扩，代码不用动）。
function pickField(contract, field, source) {
  const aliases = aliasesFor(contract, field);
  const pick = aliases.length > 0 ? aliases : [field];
  for (const key of pick) {
    const value = source ? source[key] : undefined;
    if (value === null || value === undefined) continue;
    const text = typeof value === 'string' ? value : String(value);
    if (text.trim() !== '') return text;
  }
  return '';
}

/// 在线阈值 = 倍数 × 拉取间隔（毫秒）。不另设心跳协议：poll 即心跳。
function onlineThresholdMs(contract, pollIntervalSeconds) {
  const presence = contract.presence || {};
  const poll =
    pollIntervalSeconds === undefined
      ? (presence.pollIntervalSeconds || {}).default
      : pollIntervalSeconds;
  const multiplier = presence.onlineThresholdMultiplier;
  if (typeof poll !== 'number' || typeof multiplier !== 'number') {
    throw new Error('presence 段缺 pollIntervalSeconds.default 或 onlineThresholdMultiplier');
  }
  return poll * multiplier * 1000;
}

module.exports = {
  SUPPORTED_MAJOR,
  CONTRACT_FILE,
  loadContract,
  assertSupported,
  statusCodes,
  statusCode,
  isReceipt,
  canonicalOrder,
  aliasesFor,
  pickField,
  onlineThresholdMs,
};
