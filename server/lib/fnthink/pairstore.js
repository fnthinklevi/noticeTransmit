// 配对请求表（#131 第二片 2B）：`pair` 那一步在服务端留下的「等 A 本机确认」的记录。
//
// 三条决定这张表为什么不并入别处的理由，写在头里：
//  ① **不进 messagestore**：那张表每一条都要回答「投给谁的什么内容」，还要过 capabilities 的
//     type 词表。配对请求没有正文，硬塞就得把口令写进 body —— 那是让落盘闸门去守一条
//     本该由设计守的规矩（而且请求的"收件人"要能看见它，不等于它是一条消息）。
//  ② **明文口令一个字节都不落**：记录里只有它的摘要（契约 `pairRequest.neverStored` 钉着，
//     `table.js` 的深扫再守一遍）。A poll 到这条时拿自己手上那枚算一次摘要比一下，
//     就能确认「这就是我刚挂出去的那枚」，不需要服务端复述明文。
//  ③ **服务端从不批准**：`approved` / `denied` 只能由 A 自己的签名写进来（第三片）。
//     这个模块自己能把 pending 变成的只有 expired —— 谁哪天在这里加一次 approve，
//     就等于把 `pairing.autoApprove=false` 那条红线改成注释。
//
// 键是随机 id，不是地址码：一台设备可以挂很多枚口令、被很多人扫，用地址码当键就是
// 让后来者覆盖前一条 —— 而 A 屏幕上还挂着前一条的二维码。
//
// T110 给这张表加了**第二面**：`pendingFor`（谁在请求配对你，按 `target` 选、只 pending）与
// `sentFor`（我发起的那条走到了哪儿，按 `requester` 选、含终态）。两份共用同一张表、同一条
// 到期扫描，但投影名单各自在契约上（`pollKey`／`sentPollKey` + `sentFields`）—— 一份名单
// 两面共用是这里最省事的错：要么发起方看不见终态（他要的正是那个），要么接收方多收到别人的行。

'use strict';

const crypto = require('crypto');
const path = require('path');

const { DATA_DIR } = require('../store');
const { resolvePath } = require('./contract');
const { alphabetFromContract, normalize } = require('./credentials');
// 写授权只有一条咽喉，就在设备表那一侧：本文件不自己碰 `grantsBy`（两处写 = 两份规则）。
// 方向上不成环：devicestore 不认识 pairstore。
const { approvePeer } = require('./devicestore');
const { loadTable, saveTable } = require('./table');

const REQUEST_FILE = path.join(DATA_DIR, 'fnthink_pair_requests.json');
const ID_BYTES = 9;

function loadRequests() {
  return loadTable(REQUEST_FILE, 'pairRequests');
}

function saveRequests(requests) {
  return saveTable(REQUEST_FILE, 'pairRequests', requests);
}

/// 契约里那一段必须存在且成形。**不补默认值**：补了就是在代码里发明一份第二真值，
/// 而这张表的形状（存什么、不存什么、活多久、谁能看见）全都该由契约说。
function requestSpec(contract) {
  const spec = contract.pairRequest;
  if (!spec || typeof spec !== 'object' || Array.isArray(spec)) {
    throw new Error('契约缺 pairRequest 段（创建了东西却没定义它长什么样）');
  }
  return spec;
}

function positiveInt(contract, spec, key) {
  const value = spec[key];
  if (typeof value !== 'number' || !Number.isInteger(value) || value <= 0) {
    throw new Error(`pairRequest.${key} 必须是正整数，实为 ${JSON.stringify(value)}`);
  }
  return value;
}

function ttlMs(contract, spec) {
  const dotted = spec.ttlSecondsFrom;
  const seconds = resolvePath(contract, dotted);
  if (typeof seconds !== 'number' || seconds <= 0) {
    throw new Error(
      `pairRequest.ttlSecondsFrom=${JSON.stringify(dotted)} 没指到一个正数秒：` +
        '另设一个 TTL 就会出现「口令还活着而请求已消失」',
    );
  }
  return seconds * 1000;
}

function initialStatus(contract, spec) {
  const status = spec.initialStatus;
  const statuses = spec.statuses || [];
  if (!statuses.includes(status) || (spec.terminalStatuses || []).includes(status)) {
    throw new Error(
      `pairRequest.initialStatus=${JSON.stringify(status)} 必须是 statuses 里那个非终态，实为 ${statuses.join('/')}`,
    );
  }
  return status;
}

function keyOf(contract, addressCode) {
  return normalize(alphabetFromContract(contract), addressCode);
}

/// 到期的 pending 标成 expired。返回改动的条数（"这次一条都没剪"也要能说出来，
/// 不然没人知道自己看到的空清单是没请求还是请求全被剪了）。
function expireDue(contract, requests, now) {
  const spec = requestSpec(contract);
  const pending = initialStatus(contract, spec);
  const expiredName = (spec.terminalStatuses || []).includes('expired') ? 'expired' : null;
  if (!expiredName)
    throw new Error('契约 pairRequest.terminalStatuses 里没有 expired：请求到期了却没处可去');
  let changed = 0;
  for (const record of Object.values(requests)) {
    if (record.status === pending && Number(record.expiresAt) <= now) {
      record.status = expiredName;
      record.statusChangedAt = now;
      changed += 1;
    }
  }
  if (changed) saveRequests(requests);
  return changed;
}

/// 新建一条待确认请求。返回 `{ok:false, reason}` 而不是抛：容量类拒绝是预期行为，
/// 不是代码 bug —— 把它抛出去会让路由只能按 500 处理，而那是"实例满了"不是"服务端坏了"。
function createRequest(contract, requests, input, now) {
  const spec = requestSpec(contract);
  const pending = initialStatus(contract, spec);
  expireDue(contract, requests, now);
  for (const field of ['target', 'requester', 'requesterPublicKey', 'level', 'codeDigest']) {
    if (typeof input[field] !== 'string' || input[field] === '') {
      throw new Error(`配对请求缺 ${field}（这张表的每一行都要能回答"谁向谁请求了什么"）`);
    }
  }
  // 先剪掉"早已终态且早已过期"的那些，再判全局上限：不然一台跑了几年的实例
  // 会因为一堆历史成就是记录而开始拒绝新配对，而那份历史对谁都没有意义了。
  const terminal = spec.terminalStatuses || [];
  for (const [id, record] of Object.entries(requests)) {
    if (terminal.includes(record.status) && Number(record.expiresAt) <= now) delete requests[id];
  }
  const perTarget = Object.values(requests).filter(
    (record) => record.status === pending && record.target === input.target,
  ).length;
  const perDevice = positiveInt(contract, spec, 'perDeviceLimit');
  if (perTarget >= perDevice) {
    return { ok: false, reason: 'per-device-limit', pending: perTarget, limit: perDevice };
  }
  const globalLimit = positiveInt(contract, spec, 'globalLimit');
  if (Object.keys(requests).length >= globalLimit) {
    // 到上限**拒绝新的**，不挤掉任何一条 pending：被挤掉的那条对应的二维码还挂在 A 的屏幕上，
    // 而 A 确认一个自己没见过的请求，比配对失败危险得多。
    return { ok: false, reason: 'global-limit', total: Object.keys(requests).length };
  }
  const id = 'pr_' + crypto.randomBytes(ID_BYTES).toString('hex');
  requests[id] = {
    id,
    target: input.target,
    requester: input.requester,
    requesterPublicKey: input.requesterPublicKey,
    level: input.level,
    codeDigest: input.codeDigest,
    createdAt: now,
    expiresAt: now + ttlMs(contract, spec),
    status: pending,
  };
  saveRequests(requests);
  return { ok: true, request: requests[id] };
}

/// poll 响应里那个键名。**不回落成字面量**：路由拼键名时如果这里返回 undefined，
/// 响应里就会出现一个 "undefined" 键，而"请求取到了却挂在没人读的键上"与"没取到"在设备上看不出区别。
function pollKey(contract) {
  const spec = requestSpec(contract);
  const via = spec.visibleVia;
  const key = spec.pollKey;
  if (via === 'poll' && (typeof key !== 'string' || key === '')) {
    throw new Error(
      '契约缺 pairRequest.pollKey（不补默认值）：visibleVia=poll 却没写键名 —— 请求落进了表里，却没人取得到它',
    );
  }
  if (via !== 'poll') {
    throw new Error(`pairRequest.visibleVia=${JSON.stringify(via)}：本实现只会走 poll`);
  }
  return key;
}

/// 发出方那一面的响应键名（T110 的第一面之另一面：「我发起给谁、现在算什么状态」）。
///
/// 它与 `pollKey` 同一条判据（缺就抛，不补默认值），再多一条**不许同名**：同名的话一次 poll
/// 长出两个同键，后写的盖掉先写的（盖掉顺序是 JS 的插入顺序），B 屏幕上就会画出
/// 「谁在请求配对你」而发起请求的正是他自己 —— 那一句还会诱导他去点同意。
function sentPollKey(contract) {
  const spec = requestSpec(contract);
  const key = spec.sentPollKey;
  if (typeof key !== 'string' || key === '') {
    throw new Error(
      '契约缺 pairRequest.sentPollKey（不补默认值）：发起了请求的那台没有读口，' +
        '界面上只能显示"我提交了"这一瞬间，之后走到哪儿全是猜',
    );
  }
  if (key === pollKey(contract)) {
    throw new Error(
      `pairRequest.sentPollKey 与 pollKey 同名（都是 ${JSON.stringify(key)}）：` +
        '两面共用一个键 ⇒ 一面把另一面盖掉，而被盖掉的那一面在屏幕上看不出来',
    );
  }
  return key;
}

/// 发出方那一条投影的字段名单（含 `at` 那一个对外别名）。启动期判，不在每次 poll 的热路径上判：
/// 这几条判的都是"契约被人手改过之后这份投影还算不算数"，那种错要**当场**让进程起不来。
///
/// ⚠ 名单里为什么没有 `codeDigest`：摘要是「能拿去比对的东西」（`endpointList._neverReturnsSecretWhy`
///   同一条论证），而发起方本来就知道自己用过的那枚口令 —— 这一面拿它换不到任何信息，
///   多回一份就多一处能漏的地方。这条**显式挡**而不只靠白名单：白名单是投影照抄的名单，
///   哪天有人往名单里补一项时，只有这条挡箭牌会说"这一项不许出现在面向发出方的投影里"。
function sentFields(contract) {
  const spec = requestSpec(contract);
  const fields = spec.sentFields;
  if (!Array.isArray(fields) || fields.length === 0) {
    throw new Error(
      '契约缺 pairRequest.sentFields（非空数组）：投影照它挑字段，没有名单就是自己拼一份',
    );
  }
  const stored = spec.storedFields || [];
  const neverStored = spec.neverStored || [];
  for (const field of fields) {
    if (typeof field !== 'string' || field === '') {
      throw new Error(`pairRequest.sentFields 里有一项不是名字：${JSON.stringify(field)}`);
    }
    // ⚠ 这两条口令类的挡箭牌排在"表里有没有这一列"**之前**：`neverStored` 那几项本来就不在
    //   storedFields 里，排在后面就永远轮不到它们说话 —— 报出来的会是"表里没这列"这种次要理由，
    //   而真正该说破的是「口令类字段不许出这一面的门」。判据要能报对原因，不然下一个人会去
    //   补列而不是删名单。
    if (neverStored.includes(field)) {
      throw new Error(
        `pairRequest.sentFields 含 neverStored 的那一项「${field}」：这一面要把口令类字段带出门，` +
          '而"只活在那一次输入里"那条红线就是它写的',
      );
    }
    if (field === 'codeDigest') {
      throw new Error(
        'pairRequest.sentFields 里有 codeDigest：面向发出方的投影不回摘要 —— ' +
          '摘要是能拿去比对的东西，而发起方本来就知道自己用过的那枚口令',
      );
    }
    // `at` 是 `statusChangedAt` 的对外别名（见契约 `_storedFieldsWhy`），表里没有叫 `at` 的列。
    const inRow = stored.includes(field) || WIRE_ALIASES[field] !== undefined;
    if (!inRow) {
      throw new Error(
        `pairRequest.sentFields 里的「${field}」在这张表的 storedFields 里根本没有：` +
          '投影会当场把它读成 undefined —— 那一列在界面上永远空着，而空着与"这条没有那个时刻"分不出来',
      );
    }
  }
  const unique = new Set(fields);
  if (unique.size !== fields.length) {
    throw new Error(`pairRequest.sentFields 有重名项：${fields.join('/')}`);
  }
  // `status` 与两个时刻是这一面存在的全部理由：少了 status 它就是接收方那份的复制品，
  // 少了 createdAt/at 界面答不了「多久之前」。
  for (const must of ['status', 'createdAt', 'at']) {
    if (!unique.has(must)) {
      throw new Error(
        `pairRequest.sentFields 少了「${must}」：这一面答的就是"现在算什么状态、什么时候变的"`,
      );
    }
  }
  return fields.slice();
}

/// 表里那一列 → 线上那个键。只有这一个别名（其余字段名两面相同，所以名单能直接当投影用）。
const WIRE_ALIASES = { at: 'statusChangedAt' };

/// 一台设备**自己发起过**的那些配对请求，含终态（T110 第二面）。
///
/// 三条与接收方那份不同的地方，各有理由：
///  ① 选择键是 `requester` 而不是 `target`：这一面问的是"我发出去的那条怎么样了"。
///  ② **终态要回**（approved / denied / expired）： pending 那一条接收方已经看得见，
///     发起方要的恰恰是"后来怎么样了"——只看 pending 的那份等于回答"还没人同意"然后永远停在那儿。
///  ③ 表里的 `statusChangedAt` 出门叫 `at`（与 T105 片③ 的回执同一个词；0 = 旧记录没记过）。
/// 到期的先落地（expireDue）：一条早已过期的请求不该还在发起方屏幕上挂着 pending。
function sentFor(contract, requests, addressCode, now, limit) {
  expireDue(contract, requests, now);
  const fields = sentFields(contract);
  const me = keyOf(contract, addressCode);
  const rows = Object.values(requests)
    .filter((record) => String(record.requester) === me)
    .sort((a, b) => Number(a.createdAt) - Number(b.createdAt) || (a.id < b.id ? -1 : 1))
    .slice(0, Math.max(0, Number(limit) || 0));
  return rows.map((record) => {
    const out = {};
    for (const field of fields) {
      const source = WIRE_ALIASES[field] || field;
      // `at` 是唯一可能缺的一列（本片之前的记录写的是 decidedAt／到期扫描没写）：
      // 缺 = 0 = "不知道"，宁可不给也不拿当下时间凑一个（同 T105 片③ 那条）。
      out[field] = field === 'at' ? Number(record[source] || 0) : record[source];
    }
    return out;
  });
}

/// 一台设备 poll 到的待确认请求。**显式挑字段**：将来记录里多一个内部键（比如留痕用的原因）
/// 不会顺手出现在响应里。target 不回显（问的人就是它）。
function pendingFor(contract, requests, addressCode, now) {
  const spec = requestSpec(contract);
  const pending = initialStatus(contract, spec);
  expireDue(contract, requests, now);
  const me = keyOf(contract, addressCode);
  return Object.values(requests)
    .filter((record) => record.status === pending && record.target === me)
    .sort((a, b) => Number(a.createdAt) - Number(b.createdAt))
    .map((record) => ({
      id: record.id,
      requester: record.requester,
      requesterPublicKey: record.requesterPublicKey,
      level: record.level,
      codeDigest: record.codeDigest,
      createdAt: record.createdAt,
      expiresAt: record.expiresAt,
    }));
}

/// A 处理自己的一条配对请求（#131 第三片）。`devices` 传进来是因为同意要写授权，
/// 而写授权只有一条咽喉：`devicestore.approvePeer`（本文件不自己碰 `grantsBy`）。
///
/// 三条顺序上的取舍，都写在代码旁边：
///  ① 先查归属再查状态：把"不是你的请求"和"已经处理过"分开报，是给运维看的；
///     对外两者同形（路由那边只看一个 reason）。
///  ② 过期先落地（expireDue）：一条早已过期的请求不该还能被"同意"。
///  ③ **先写授权、后关请求**：反过来做的话，一次 approvePeer 落盘失败会留下
///     "请求显示已同意、B 却一条都发不进来"——A 看见自己点了同意而对面没反应，
///     那是最难查的一种静默。现在的顺序最坏只到"授权写了、请求还挂着"，
///     A 再确认一次即可（revision +1，方向仍然由 A 决定）。
function decideRequest(contract, requests, devices, input, now) {
  const spec = requestSpec(contract);
  const pending = initialStatus(contract, spec);
  expireDue(contract, requests, now);
  const record = Object.prototype.hasOwnProperty.call(requests, String(input.requestId))
    ? requests[String(input.requestId)]
    : null;
  if (!record) return { ok: false, reason: 'unknown-request' };
  if (
    String(record.target) !== String(input.target) ||
    String(record.requester) !== String(input.requester)
  ) {
    // 契约 pairConfirm.requestMustBelongToTarget 的执行处：requestId 是随机串，但"猜不到"不是判据。
    return { ok: false, reason: 'not-yours' };
  }
  if (record.status !== pending) return { ok: false, reason: 'already-decided' };
  const confirm = (contract.clientEvents || {}).pairConfirm || {};
  const decisions = confirm.decisions || [];
  // ⚠ 这条必须排在"哪个词算同意"的比较**之前**：写在比较里面的话，approveDecision 一旦被删，
  //   比较就恒不等 ⇒ 同意被静默当成不同意（请求关掉、授权没写），而那正是最像"配对失败"的缺陷。
  if (!confirm.approveDecision || !decisions.includes(confirm.approveDecision)) {
    throw new Error(
      `契约 pairConfirm.approveDecision=${JSON.stringify(confirm.approveDecision)} 必须存在且在 ` +
        `decisions（${decisions.join('/')}）里：不知道哪个词算同意，就不敢动这张表`,
    );
  }
  if (!decisions.includes(input.decision)) {
    throw new Error(
      `pairConfirm.decisions 里没有 ${JSON.stringify(input.decision)}（可取：${decisions.join('/')}）`,
    );
  }
  let grant = null;
  if (input.decision === confirm.approveDecision) {
    // `input.items` 是 events 那一侧过完词表与形状两道闸的那一份（T134 片2）。
    // 这里不重判、也不"缺省成空清单"：缺这一枚键说明调用方漏接了，静默补 [] 就等于
    // 把"用户勾了而表里没有"写成一条看不见的缺陷 —— approvePeer 会因为它不是数组而抛。
    grant = approvePeer(
      contract,
      devices,
      input.target,
      input.requester,
      input.level,
      input.items,
      now,
    );
  }
  record.status = input.decision;
  // 与到期扫描那一支同一个列名（原先这里写 `decidedAt`、那里写 `statusChangedAt`，说的是
  // 同一件事「状态最后一次变的时刻」）：两个名字 ⇒ 发起方那一面的投影要认两遍，
  // 而"这一条什么时候变的"在界面上就成了猜哪个键非空。契约 `_storedFieldsWhy` 钉的是这一条。
  record.statusChangedAt = now;
  saveRequests(requests);
  return { ok: true, request: record, grant };
}

module.exports = {
  ID_BYTES,
  REQUEST_FILE,
  WIRE_ALIASES,
  createRequest,
  decideRequest,
  expireDue,
  initialStatus,
  loadRequests,
  pendingFor,
  pollKey,
  requestSpec,
  saveRequests,
  sentFields,
  sentFor,
  sentPollKey,
};
