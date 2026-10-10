// 能力清单（T30）服务端这一半：一条已经证明身份的消息，这台设备准不准它做。
//
// 与 Dart 的 packages/fnthink_push/lib/src/capabilities.dart 是同一套规则的两份实现，
// 两者都只从契约 `capabilities` 段读数值，且**同一份向量**（protocol/fnthink-vectors-v1.json
// 的 capabilities 组）各断言一遍。它必须一致的理由很实在：不一致时不会报错，
// 只会变成"设备自己觉得只给了 L1，服务端却按 L2 收"。

'use strict';

const { resolvePath } = require('./contract');

/// 级别序：**直接取契约 `capabilities.levels` 里的位置**（validate 保证它按权限升序）。
/// 不写 `case 'L1': return 1` 那种表：那是在服务端存第二份档位表，契约加一档时
/// 它不报错，只会让比较结果静默错位。不在词表里 ⇒ -1（任何真实档位都比它大 ⇒ 判不过）。
function levelRank(levels, level) {
  return levels.indexOf(level);
}

/// 从**授权节点本身**读。读不到就按契约缺省档（fail-closed）——
/// "没写"永远不等于"全给"，而 `items` 不是数组也按空清单算，同样不放开。
function grantFromNode(contract, node) {
  const fallback = (contract.capabilities.grantDefaults || {}).maxLevel;
  if (!node || typeof node !== 'object' || Array.isArray(node)) {
    return { maxLevel: fallback, items: [], revision: 0 };
  }
  const items = Array.isArray(node.items)
    ? node.items.map((e) => String(e)).filter((e) => e !== '')
    : [];
  return {
    maxLevel: String(node.maxLevel || fallback),
    items,
    revision: Number(node.revision) || 0,
  };
}

/// 裁决结果。`stage` **没有默认值**，两条调用路径必须各自说清自己在哪一段：
/// - `intake`（服务端收单）：只判 词表 / 档位 / 逐条清单。**这一段判不了"每次本地确认"** ——
///   确认发生在设备上，而服务端收到的请求里那个字段是**对端自称**的：拿它当确认，
///   等于让发送方替接收方点"我确认了"（那条红线：不许远端悄悄执行本地动作）。
///   所以 intake 遇到 L3 放行时会带 `requiresApplyConfirm: true`，交给设备在 apply 那一段判。
/// - `apply`（设备落地之前）：四条全判，其中确认取自**本机**那一次用户动作。
///
/// ⚠⚠ **apply 段今天没有任何调用方**（如实登记，2026-10-05）：确认那道闸的形式
///   已改成「延时窗口内未撤销」（契约 `l3.confirmForm = cancelableDelay`，2026-10-04 定），
///   而窗口在**设备侧**走（`RemoteCommandRunner` 到点那一刻自己判）。
///   服务端**不该**再有 apply 段的调用方 —— 拿请求里那个自称的标志当确认，
///   等于让发送方替接收方点头（T30 那条红线）。这一段留着不删，是那三判的完整形状；
///   若哪天确认又回到服务端，必须重新接线并补用例。
function decideCapability(contract, input) {
  const capabilities = contract.capabilities || {};
  const defaults = capabilities.grantDefaults || {};
  const table = capabilities.messageTypes || {};
  const levels = capabilities.levels || [];
  if (input.stage !== 'intake' && input.stage !== 'apply') {
    throw new Error(`decideCapability 必须显式说清是哪一段（intake / apply），实为 ${input.stage}`);
  }
  const entry = table[input.type];
  const need = entry ? String(entry.minLevel || '') : null;
  // 认不出的 type 一律拒，不往任何一侧兜底：兜底等于把词表的解释权交给对端。
  if (!need)
    return { allowed: false, reason: `unknown-type:${input.type}`, requiresApplyConfirm: false };
  const grant = input.grant || { maxLevel: defaults.maxLevel, items: [] };
  if (levelRank(levels, need) > levelRank(levels, grant.maxLevel)) {
    return { allowed: false, reason: `level:${need}`, requiresApplyConfirm: false };
  }
  if (levelRank(levels, need) >= levelRank(levels, capabilities.itemRequiredFromLevel)) {
    const item = input.item === undefined || input.item === null ? '' : String(input.item);
    if (item === '') return { allowed: false, reason: 'missing-item', requiresApplyConfirm: false };
    if (!(grant.items || []).includes(item)) {
      return { allowed: false, reason: `item:${item}`, requiresApplyConfirm: false };
    }
  }
  const topLevel = levels.length ? levels[levels.length - 1] : '';
  const l3 = capabilities.l3 || {};
  const needsConfirm = need === topLevel && l3.confirmEveryTime === true;
  if (!needsConfirm) return { allowed: true, reason: null, requiresApplyConfirm: false };
  if (input.stage === 'intake') {
    // 收单这段判不了确认，也不许用请求里那个自称的标志替设备判 —— 交给 apply。
    return { allowed: true, reason: null, requiresApplyConfirm: true };
  }
  if (!input.confirmedThisTime) {
    return { allowed: false, reason: 'confirm-required', requiresApplyConfirm: true };
  }
  return { allowed: true, reason: null, requiresApplyConfirm: true };
}

/// 端点（长期口令、无签名）这一侧的授权：**只有档位，没有逐条清单**。
/// 契约 `capabilities.endpointMaxLevel` 说端点只能产 L1，而它声明的拒绝回执
/// （`endpointActionReceipt`）就是 `rejected_capability` —— 走同一个裁决函数，
/// 不在别处再写一份"端点不许发动作"的判断。
function endpointGrant(contract) {
  return {
    maxLevel: String(
      (contract.capabilities || {}).endpointMaxLevel ||
        ((contract.capabilities || {}).grantDefaults || {}).maxLevel,
    ),
    items: [],
  };
}

/// 配对同意那一屏能勾的**取值域**（T134 片2）：从契约 `pairConfirm.itemsVocabularyFrom`
/// 指过去的那几张表现取，服务端不存第二份清单。
///
/// 两种形状都认，而且必须两种都认：`l2.actions` 是名单（值就是 item），`l3.settings`
/// 是键控表（**键名**才是 item，值里装的是怎么执行）。只读名单的那份写法会把 `l3.settings`
/// 读成"一张空表"，于是所有 L3 勾选一律算词表外 —— 而界面上那看起来就像"用户没勾"。
///
/// 抛而不回落成空表：`itemsVocabularyFrom` 写错路径时，空表意味着"任何勾选都不合法"，
/// 那与"这个词表还没定义"是两件事，前者会被读成用户在乱勾。
function confirmItemVocabulary(contract) {
  const spec = (contract.clientEvents || {}).pairConfirm || {};
  const paths = spec.itemsVocabularyFrom;
  if (!Array.isArray(paths) || paths.length === 0) {
    throw new Error(
      'pairConfirm.itemsVocabularyFrom 必须是非空名单：有 items 这一枚键却没有取值域，' +
        '服务端只剩"收下并忽略"这一种写法',
    );
  }
  const out = [];
  for (const path of paths) {
    const node = resolvePath(contract, path);
    const entries = Array.isArray(node)
      ? node
      : node && typeof node === 'object'
        ? Object.keys(node)
        : null;
    if (!entries || entries.length === 0) {
      throw new Error(
        `pairConfirm.itemsVocabularyFrom 指向的 ${JSON.stringify(path)} 既不是非空名单也不是非空键控表`,
      );
    }
    for (const entry of entries) {
      const value = String(entry).trim();
      if (value !== '' && out.indexOf(value) < 0) out.push(value);
    }
  }
  return out.sort();
}

/// 把答复载荷里那一枚 `items` 读成"可以写进授权表的清单"（T134 片2）。
///
/// 四种拒的理由各不相同，**不许合并**（与 parseL2Item / parseL3Item 同一条纪律）：
///   items-not-array     形状就不是清单（老客户端不会走到这里：契约 optionalFields 缺省填 []）
///   item-not-string     混进了数字/对象 —— 写进表里下一次读它的是 `includes`，比对的是字符串
///   item-empty          空项：空串在授权表里与"没有那一项"同形，留着只会让人以为勾上了
///   unknown-item:<x>    词表外 —— 词表外的勾无从执行，收下就等于把"我给了权限"写成一句空话
/// 返回 `{reason}` 或 `{items}`，不自己造拒绝对象（状态码由调用处按契约那枚旋钮挑）。
///
/// ⚠ **比的是整串，没有通配**（向量 `c-action-item-not-granted` 那条 note 说的就是这件事）：
///   词表里那 18 项中，带参数的那几项（契约 `l2.requiresArgumentFrom` 六项 + `l3` 两枚 toggle）
///   在线上的 item 长成 `<名>/<参数>`，因此勾了名字也判不过。粒度那条不在这里拍，
///   登记在 roadmap T134 片3 前面。
function normalizeConfirmItems(contract, raw) {
  if (!Array.isArray(raw)) return { reason: 'items-not-array' };
  const vocabulary = confirmItemVocabulary(contract);
  const out = [];
  for (const entry of raw) {
    if (typeof entry !== 'string') return { reason: 'item-not-string' };
    const value = entry.trim();
    if (value === '') return { reason: 'item-empty' };
    if (vocabulary.indexOf(value) < 0) return { reason: `unknown-item:${value}` };
    // 重复项**静默去重**而不是拒：一次重试、一份把同一项列了两遍的清单，落进表里都该是同一件事；
    // 拒掉它的表现是"用户点了同意而界面只回一句与口令错同形的话"。
    if (out.indexOf(value) < 0) out.push(value);
  }
  return { items: out.sort() };
}

module.exports = {
  confirmItemVocabulary,
  decideCapability,
  endpointGrant,
  grantFromNode,
  // 档位比较开给配对（#131）：级别顺序的出处只能有一个（capabilities.levels 的位置）。
  // 各写一份 rank 表，改档位顺序时只会红一边 —— T30-A 就是为了删掉 pairing.dart 里那份私有表。
  levelRank,
  normalizeConfirmItems,
};
