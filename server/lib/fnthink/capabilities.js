// 能力清单（T30）服务端这一半：一条已经证明身份的消息，这台设备准不准它做。
//
// 与 Dart 的 packages/fnthink_push/lib/src/capabilities.dart 是同一套规则的两份实现，
// 两者都只从契约 `capabilities` 段读数值，且**同一份向量**（protocol/fnthink-vectors-v1.json
// 的 capabilities 组）各断言一遍。它必须一致的理由很实在：不一致时不会报错，
// 只会变成"设备自己觉得只给了 L1，服务端却按 L2 收"。

'use strict';

/// 级别序：**直接取契约 `capabilities.levels` 里的位置**（validate 保证它按权限升序）。
/// 不写 `case 'L1': return 1` 那种表：那是在服务端存第二份档位表，契约加一档时
/// 它不报错，只会让比较结果静默错位。不在词表里 ⇒ -1（任何真实档位都比它大 ⇒ 判不过）。
function levelRank(levels, level) {
  return levels.indexOf(level);
}

/// 从设备/端点记录里读（记录形如 `{grant: {...}}`）。
function grantFromRecord(contract, record) {
  return grantFromNode(contract, record ? record.grant : null);
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
///   所以 intake 遇到 L3 放行时会带 `requiresLocalConfirm: true`，交给设备在 apply 那一段判。
/// - `apply`（设备落地之前）：四条全判，其中确认取自**本机**那一次用户动作。
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
    return { allowed: false, reason: `unknown-type:${input.type}`, requiresLocalConfirm: false };
  const grant = input.grant || { maxLevel: defaults.maxLevel, items: [] };
  if (levelRank(levels, need) > levelRank(levels, grant.maxLevel)) {
    return { allowed: false, reason: `level:${need}`, requiresLocalConfirm: false };
  }
  if (levelRank(levels, need) >= levelRank(levels, capabilities.itemRequiredFromLevel)) {
    const item = input.item === undefined || input.item === null ? '' : String(input.item);
    if (item === '') return { allowed: false, reason: 'missing-item', requiresLocalConfirm: false };
    if (!(grant.items || []).includes(item)) {
      return { allowed: false, reason: `item:${item}`, requiresLocalConfirm: false };
    }
  }
  const topLevel = levels.length ? levels[levels.length - 1] : '';
  const l3 = capabilities.l3 || {};
  const needsConfirm = need === topLevel && l3.confirmEveryTime === true;
  if (!needsConfirm) return { allowed: true, reason: null, requiresLocalConfirm: false };
  if (input.stage === 'intake') {
    // 收单这段判不了确认，也不许用请求里那个自称的标志替设备判 —— 交给 apply。
    return { allowed: true, reason: null, requiresLocalConfirm: true };
  }
  if (!input.confirmedThisTime) {
    return { allowed: false, reason: 'confirm-required', requiresLocalConfirm: true };
  }
  return { allowed: true, reason: null, requiresLocalConfirm: true };
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

module.exports = {
  decideCapability,
  endpointGrant,
  grantFromNode,
  grantFromRecord,
  // 档位比较开给配对（#131）：级别顺序的出处只能有一个（capabilities.levels 的位置）。
  // 各写一份 rank 表，改档位顺序时只会红一边 —— T30-A 就是为了删掉 pairing.dart 里那份私有表。
  levelRank,
};
