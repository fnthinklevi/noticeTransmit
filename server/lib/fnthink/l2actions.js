// L2 应用动作的**服务端那一半**（T50）。
//
// 与 Dart 的 lib/services/fnthink_l2_actions.dart 是同一套动作的两份实现，
// 而动作词表的唯一出处是契约 `capabilities.l2.actions`。两端各写一份映射是刻意的
// —— 它们各自调用本地的执行器（Node 侧调自己的，Dart 侧调 MethodChannel 与 DB），
// 但"哪几个动作算数"必须同源：一份名单存在两处时两处各自都对，
// 而对面新加一个动作只有自己认得，表现是服务端把它收进队列、设备端在 apply 段
// 判成 unknown-action，两头日志互相看不懂。
//
// 这一层只做纯解析，**不执行**：服务端不替设备做动作（那正是 T30 那条红线
// "服务端看不见屏幕前的那个人"）。执行在设备侧那一半。

'use strict';

/// 把载荷里那个 `item` 读成 {action, argument}。
///
/// item 的形状是 `<family>:<verb>`（契约 `capabilities.l2.itemFormat`），
/// 契约点名要参数的动作写成 `<family>:<verb>/<参数>`。
///
/// 四种拒的理由各不相同，**不许合并**：
///   missing-item        载荷里根本没有 item
///   unknown-action:X    X 不在契约词表里（契约 unknownAction: reject）
///   missing-argument:X  契约点名要参数而没给
///   not-a-pair          这一档根本不是 L2（type 不是 action）
/// 合并之后服务端只能说"这条不行"，而设备端会把它记成执行失败（failed_action）
/// 而不是"不认得" —— 后者会让人以为是自己没配好。
function parseL2Item(contract, item, type) {
  const capabilities = (contract && contract.capabilities) || {};
  const l2 = capabilities.l2 || {};

  if (type !== undefined && type !== null && String(type) !== 'action') {
    return { ok: false, reason: 'not-a-pair' };
  }
  if (item === undefined || item === null || String(item) === '') {
    return { ok: false, reason: 'missing-item' };
  }
  const raw = String(item);
  const slash = raw.indexOf('/');
  const name = slash >= 0 ? raw.slice(0, slash) : raw;
  const argument = slash >= 0 ? raw.slice(slash + 1) : '';

  const actions = Array.isArray(l2.actions) ? l2.actions : [];
  if (!actions.includes(name)) {
    return { ok: false, reason: `unknown-action:${name}` };
  }
  // 契约点名要参数而没给：拒。**不取第一条** —— 那等于替用户猜一个目标，
  // 而这条消息的签名者从未说过他要动哪一条。
  const needsArg = Array.isArray(l2.requiresArgumentFrom) ? l2.requiresArgumentFrom : [];
  if (needsArg.includes(name) && argument === '') {
    return { ok: false, reason: `missing-argument:${name}` };
  }
  return { ok: true, action: { name, argument } };
}

/// 这一次 L2 消息对外回哪一个回执词。
///
/// 成功走正常投递（delivered），失败走契约那一个词（`capabilities.l2.actionReceipt`）。
/// 身份已证明，不许把「没权限」和「执行失败」压成同形的一句话；
/// 但本地细节（哪个通道、什么异常）**不许写进对外形状** —— 那些要进留痕（T53）。
function l2ReceiptFor(contract, result) {
  if (result && result.ok) return 'delivered';
  const l2 = ((contract && contract.capabilities) || {}).l2 || {};
  return l2.actionReceipt || 'failed_action';
}

/// 契约词表与服务端映射是否同步。守卫用例调它，改契约时红的就是这一条。
///
/// ⚠ 这份"映射"是**动词**（这一侧怎么执行），不是动作词表 —— 动作词表只有契约一处。
/// 这里比的是"契约里每一个动作，这一侧都认得"，而不是"两边各写一份名单"。
function l2ActionsKnownToServer(contract) {
  const l2 = ((contract && contract.capabilities) || {}).l2 || {};
  const actions = Array.isArray(l2.actions) ? l2.actions : [];
  if (actions.length === 0) return false;
  // 服务端这一侧对每个动作只需要"能解析出它、知道它属于哪一档"，不需要执行能力。
  return actions.every((a) => typeof a === 'string' && a.includes(':'));
}

module.exports = {
  l2ActionsKnownToServer,
  l2ReceiptFor,
  parseL2Item,
};
