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

// 契约层面的失败必须能被调用方**按种类**判断，而不是靠比对错误文案（文案一改，判断就瞎）。
// code 只可能是这四种：MISSING（文件读不到）/ UNPARSEABLE（不是合法 JSON 或顶层不是对象）/
// UNSUPPORTED（协议名形状或主版本这台实现不认识）/ SHAPE（文件在、能解析、版本也认识，但
// **内容缺这台实现要读的那些数** —— 典型形状就是只上传了 server/ 而契约仍是上一批次那份）。
// 除此之外冒出来的异常一律是代码 bug —— 挂载方（lib/app.js）不许把它们咽成"协议不可用"：
// 本片就实测过一次 app.js 漏 `require('./store')` 抛 ReferenceError，被那道降级 catch 吞掉，
// 日志上一句"请把契约文件放到 protocol/"就把 bug 伪装成了部署问题。
// ⚠ SHAPE 只许由取数处**显式**用 shapeError() 打，绝不在 catch 里按"异常从哪个文件来"判断 ——
//   那样任何 TypeError 都会被抓成"契约不可用"，上面那条教训就白记了。
//   为什么这一类必须能降级而不是崩在启动：它与 MISSING 是同一族部署问题，而崩掉的爆炸半径是
//   整台风服务，其中包括与幻念推送毫无关系的 `/api/version`（所有设备的更新通道）与管理后台。
//   A1 那次的部署口径写的是"新代码配旧契约 ⇒ 协议面降级 503"，而当时代码走的是崩启动 ——
//   #130-A4 加 alerts 段时把这条不一致逼了出来，按口径修正了代码。
const CONTRACT_MISSING = 'FNTHINK_CONTRACT_MISSING';
const CONTRACT_UNPARSEABLE = 'FNTHINK_CONTRACT_UNPARSEABLE';
const CONTRACT_UNSUPPORTED = 'FNTHINK_CONTRACT_UNSUPPORTED';
const CONTRACT_SHAPE = 'FNTHINK_CONTRACT_SHAPE';

function tagged(code, cause) {
  cause.code = code;
  return cause;
}

/// 契约内容不达标（缺键、非正数、名单为空、两份名单重叠⋯⋯）都由这里打，取数函数自己不造种类。
function shapeError(message) {
  return tagged(CONTRACT_SHAPE, new Error(message));
}

/// 只有这四类契约层面的失败可以降级；其它异常必须继续往上抛。
function isContractAvailabilityError(err) {
  return (
    err &&
    [CONTRACT_MISSING, CONTRACT_UNPARSEABLE, CONTRACT_UNSUPPORTED, CONTRACT_SHAPE].includes(
      err.code,
    )
  );
}

function loadContract() {
  let text;
  try {
    text = fs.readFileSync(CONTRACT_FILE, 'utf8');
  } catch (e) {
    throw tagged(CONTRACT_MISSING, new Error(`读不到契约文件 ${CONTRACT_FILE}：${e.message}`));
  }
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch (e) {
    throw tagged(CONTRACT_UNPARSEABLE, new Error(`契约文件不是合法 JSON：${e.message}`));
  }
  // JSON 数组也是 object —— 但 `contract.protocol` 在数组上是 undefined，
  // 于是"顶层不是对象"这种形状错误会以"协议名不合法"的面目报出来，把排查方向带偏。
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw tagged(CONTRACT_UNPARSEABLE, new Error(`契约文件顶层必须是对象：${CONTRACT_FILE}`));
  }
  return parsed;
}

/// 版本闸门：不兼容时抛错（调用方在启动时跑一次，运行期不再判）。
function assertSupported(contract) {
  const declared = /^fnthink-v(\d+)$/.exec(contract.protocol);
  if (!declared) {
    throw tagged(
      CONTRACT_UNSUPPORTED,
      new Error(`protocol 名不是 fnthink-v<N> 的形状：${contract.protocol}`),
    );
  }
  if (Number(declared[1]) !== contract.contractVersion) {
    throw tagged(
      CONTRACT_UNSUPPORTED,
      new Error(
        `protocol 名里的版本（v${declared[1]}）与 contractVersion（${contract.contractVersion}）不一致`,
      ),
    );
  }
  if (contract.contractVersion !== SUPPORTED_MAJOR) {
    throw tagged(
      CONTRACT_UNSUPPORTED,
      new Error(
        `契约 contractVersion=${contract.contractVersion}，服务端只实现到 v${SUPPORTED_MAJOR}`,
      ),
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

/// 「这一步能作用于谁」的规则名单（契约 `clientEvents.selfOnlyRules`）。
/// 名单从契约读、代码里不写第二份：写死了，将来契约新增一条规则时的表现是
/// 「名单上有、实现里没分支」，而那不会报错 —— 第一片的判据就是这么瞎的。
function selfOnlyRules(contract) {
  const rules = (contract.clientEvents || {}).selfOnlyRules;
  if (!Array.isArray(rules) || rules.length === 0) {
    throw new Error(
      '契约缺 clientEvents.selfOnlyRules（不补默认名单：补了就等于在代码里发明一种作用范围）',
    );
  }
  return rules.slice();
}

/// 字段容错的别名表（title / body）。首项就是规范名。
function aliasesFor(contract, field) {
  const list = (contract.fieldTolerance || {})[field] || [];
  return list;
}

/// 沿点分路径在**外部载荷**里取值（`text.content` 这种嵌一层的正文）。
/// 每一段都只认 own property —— 与 `resolvePath` 同一条纪律，而且这里的输入完全来自请求：
/// `{"text":{"constructor":…}}` 不该顺着原型链摸到东西去。走到非对象上就停手回 undefined。
function readAliasPath(source, path) {
  let node = source;
  for (const key of String(path).split('.')) {
    if (node === null || typeof node !== 'object') return undefined;
    if (!Object.prototype.hasOwnProperty.call(node, key)) return undefined;
    node = node[key];
  }
  return node;
}

/// 按契约的"取第一个非空"规则从外部载荷里取一个规范字段。
/// 这是本模块唯一真正跑在请求路径上的函数：每接一个新平台都要改服务端，
/// 就是因为没有这一层（别名表可以扩，代码不用动）。
///
/// ⚠ **值是对象或数组时跳过这一档、继续往下找别名**，不许 `String(v)` 兜底。
///   钉钉／企业微信的形状是 `{"msgtype":"text","text":{"content":"…"}}`：顶层那个
///   `text` 是个对象，转成字符串就是 `[object Object]`，而 intake 那道闸是"标题正文
///   **都**空才拒" ⇒ 一半是乱码就放行，用户收到的是一条标题写着 `[object Object]`
///   的通知。宁可少取一档，也不要把容器当值。
function pickField(contract, field, source) {
  const aliases = aliasesFor(contract, field);
  const pick = aliases.length > 0 ? aliases : [field];
  for (const key of pick) {
    const value = readAliasPath(source, key);
    if (value === null || value === undefined) continue;
    if (typeof value === 'object') continue;
    const text = typeof value === 'string' ? value : String(value);
    if (text.trim() !== '') return text;
  }
  return '';
}

/// 按点分路径取契约里的值：`pairRequest.ttlSecondsFrom`、`pair.levelCeilingFrom` 这类
/// 「一个键引用另一个键」的关系就靠它解析，省得在代码里再写一份秒数或档位。
/// 取不到返回 undefined —— 调用方必须自己判并抛，这里**不补默认值**：
/// "引用没解析到就按一个常用值办"正是本仓反复见过的那类静默（skew 那两个旋钮就是它）。
/// 用 hasOwnProperty 而不是 `in`：契约文件是部署侧可以被人手改的，
/// `ttlSecondsFrom: "constructor"` 这种输入不该顺着原型链拿到东西。
function resolvePath(contract, dotted) {
  let node = contract;
  for (const key of String(dotted === undefined ? '' : dotted).split('.')) {
    if (!node || typeof node !== 'object' || !Object.prototype.hasOwnProperty.call(node, key)) {
      return undefined;
    }
    node = node[key];
  }
  return node;
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
  CONTRACT_MISSING,
  CONTRACT_UNPARSEABLE,
  CONTRACT_UNSUPPORTED,
  CONTRACT_SHAPE,
  shapeError,
  isContractAvailabilityError,
  loadContract,
  assertSupported,
  statusCodes,
  statusCode,
  isReceipt,
  canonicalOrder,
  selfOnlyRules,
  resolvePath,
  aliasesFor,
  pickField,
  onlineThresholdMs,
};
