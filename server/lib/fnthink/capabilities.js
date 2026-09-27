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

/// {allowed, reason}。reason 只进日志与留痕；能力拒绝发生在身份已证明之后，
/// 所以它可以被说清楚（与 T27 那条"预授权失败只有一句话"是两回事）。
function decideCapability(contract, input) {
  const capabilities = contract.capabilities || {};
  const defaults = capabilities.grantDefaults || {};
  const table = capabilities.messageTypes || {};
  const levels = capabilities.levels || [];
  const entry = table[input.type];
  const need = entry ? String(entry.minLevel || '') : null;
  // 认不出的 type 一律拒，不往任何一侧兜底：兜底等于把词表的解释权交给对端。
  if (!need) return { allowed: false, reason: `unknown-type:${input.type}` };
  const grant = input.grant || {
    maxLevel: defaults.maxLevel,
    items: [],
  };
  if (levelRank(levels, need) > levelRank(levels, grant.maxLevel)) {
    return { allowed: false, reason: `level:${need}` };
  }
  if (levelRank(levels, need) >= levelRank(levels, capabilities.itemRequiredFromLevel)) {
    const item = input.item === undefined || input.item === null ? '' : String(input.item);
    if (item === '') return { allowed: false, reason: 'missing-item' };
    if (!(grant.items || []).includes(item)) {
      return { allowed: false, reason: `item:${item}` };
    }
  }
  const topLevel = levels.length ? levels[levels.length - 1] : '';
  const l3 = capabilities.l3 || {};
  if (need === topLevel && l3.confirmEveryTime === true && !input.confirmedThisTime) {
    return { allowed: false, reason: 'confirm-required' };
  }
  return { allowed: true, reason: null };
}

module.exports = { decideCapability, grantFromNode, grantFromRecord };
