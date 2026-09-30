// 投递状态机（T34）· 服务端这一半。
//
// 与 Dart 的 packages/fnthink_push/lib/src/delivery.dart 是同一套规则的两份实现，
// 两边都只从契约 `delivery` / `retention` / `limits` / `waitingOnline` 段读表，
// 并共读 protocol/fnthink-vectors-v1.json 的 `delivery` 组各断言一遍。
// 不一致不会报错，只会变成「设备以为还能重试、服务端已经转 waiting_online」，
// 而中间态意味着正文一直删不掉 —— 所以这张表在契约里，不在任何一边的代码里。

'use strict';

const DAY_MS = 24 * 60 * 60 * 1000;

function states(contract) {
  return (contract.delivery || {}).states || [];
}

function transitions(contract) {
  return (contract.delivery || {}).transitions || {};
}

/// 总尝试数 = 首次投递 + 重试次数（契约 `_retryTotalMeans` 就是为了这一行不歧义）。
function maxAttempts(contract) {
  const retry = ((contract.limits || {}).deliveryRetryTotal || 0) + 0;
  if (typeof retry !== 'number' || Number.isNaN(retry)) {
    throw new Error(`limits.deliveryRetryTotal 不是数值：${retry}`);
  }
  return retry + 1;
}

/// 状态名取自契约表；不在表里直接抛（两边都不许自己造状态）。
function initialState(contract) {
  const state = (contract.delivery || {}).initialState;
  if (!states(contract).includes(state)) {
    throw new Error(`delivery.initialState 不在 states 里：${state}`);
  }
  return state;
}

function isTerminal(contract, state) {
  return ((contract.delivery || {}).terminalStates || []).includes(state);
}

/// 「哪些状态要释放正文」按契约表回答，绝不写 `state === 'delivered' || ...`：
/// 那是在代码里存第二份释放条件（第一版就漏了 dropped，而漏的那条正文会合法地留到 7 天）。
function releasesBody(contract, state) {
  return ((contract.retention || {}).deleteBodyOn || []).includes(state);
}

function canTransition(contract, from, to) {
  const targets = transitions(contract)[from] || [];
  return targets.includes(to);
}

/// 排队中的消息是否已过最长保留期。**到期时刻只有一个算式**（下面那一行），
/// 判"过没过"和给人看"还剩多久"必须是同一个数 —— 分成两处写，视图就能显示"还有 6 天"
/// 而状态机已经把这条判成过期。
function retentionDeadline(contract, queuedAtMs) {
  const days = ((contract.retention || {}).maxRetentionDays || 0) + 0;
  return queuedAtMs + days * DAY_MS;
}

function isExpired(contract, queuedAtMs, nowMs) {
  const days = ((contract.retention || {}).maxRetentionDays || 0) + 0;
  if (days <= 0) return true;
  return nowMs >= retentionDeadline(contract, queuedAtMs);
}

/// 「取走了没等到 ack」的超时档，单位秒。**取不到就抛**而不是回落缺省：
/// 没这一档 = poll 的扫描什么都不做 = no_ack 那个分支永远没人调 =
/// 被取走却没 ack 的消息静默卡在 delivering（delivery.js 顶部那串注释就是它）。
/// Dart 的 delivery.dart 有同一份读法与同一道抛（两个 state-machine 半边不许各补一个默认）。
function ackDeadlineSeconds(contract) {
  const seconds = Number(((contract || {}).delivery || {}).ackDeadlineSeconds);
  if (!Number.isInteger(seconds) || seconds <= 0) {
    throw new Error(
      `delivery.ackDeadlineSeconds 必须是正整数（实际 ${((contract || {}).delivery || {}).ackDeadlineSeconds}）：` +
        '没有它，「发了没等到 ack」的恢复那条路（no_ack）就没有触发条件，' +
        '取走的消息会永久停在 delivering',
    );
  }
  return seconds;
}

/// 一条消息是否**已过 ack 超时**（该被 poll 的扫描判成 no_ack）。
/// 只看两件事：它现在在不在 delivering，以及从**进入 delivering 那一刻**
/// （`applyStep` 写的 `updatedAt`）到现在过了多久。终态与还没发出去的都不算超时。
function isAckOverdue(contract, message, nowMs) {
  if (!message || message.state !== 'delivering') return false;
  const deadlineMs = ackDeadlineSeconds(contract) * 1000;
  // ⚠ 先判"有没有那一刻"再看它是不是数：`Number(null) === 0` 而 0 是有限数，
  // 于是写成 `!Number.isFinite(since)` 会把 null 当成"1970 年" ⇒ 立刻判超时（这条是
  // 反证 D2 当场抓出来的）。缺 updatedAt 一律**不猜**，当作还没超时。
  const since = message.updatedAt;
  if (typeof since !== 'number' || !Number.isFinite(since)) return false;
  return nowMs - since >= deadlineMs;
}

function requireKnown(contract, state, event) {
  if (!states(contract).includes(state)) {
    throw new Error(`不是契约里的投递状态：${state}`);
  }
  const events = (contract.delivery || {}).events || [];
  if (!events.includes(event)) {
    throw new Error(`不是契约里的投递事件：${event}`);
  }
}

/// 进入 waiting_online 时该走哪条补发路 —— 取自契约 `waitingOnline` 段，
/// 且**二选一**（备用补推与排队补发并存 = 同一条消息提醒两次）。
function resendRoute(contract, hasBackupChannel) {
  const section = (contract.delivery || {}).resendDecisionFrom || 'waitingOnline';
  const table = contract[section] || {};
  return hasBackupChannel ? table.withBackupChannel : table.withoutBackupChannel;
}

/**
 * 状态机走一步，返回 `{state, attempts, receipt, deleteBody, resend, ignored}`。
 *
 * `ignored` 非空表示"这个状态遇到这个事件什么都不该做"（迟到的 ack、重复的 poll）。
 * 刻意不抛：这类事件来自网络上不可信的时序，抛错只会让调用方在错误处理里再造一个状态机。
 * 但**未知的事件名/状态名**照抛 —— 那是编程错误，不是网络噪声。
 */
function advance(contract, input) {
  const state = input.state;
  const event = input.event;
  const attempts = input.attempts || 0;
  const hasBackupChannel = input.hasBackupChannel === true;
  requireKnown(contract, state, event);
  const budget = maxAttempts(contract);
  const step = (next, extra) =>
    Object.assign(
      {
        state: next,
        // 步里带上**是哪个事件**推进的：留痕要能回答"这条是被什么挪走的"，
        // 而让调用方把 event 再传一遍给 applyStep，就会有第四处传错标签的机会。
        event,
        attempts,
        receipt: null,
        // 被忽略的那一步什么都不该发生（见 Dart 侧同一处注释）。
        deleteBody: !(extra && extra.ignored) && releasesBody(contract, next),
        resend: null,
        ignored: null,
      },
      extra || {},
    );
  const ignore = () => step(state, { ignored: `ignored:${state}+${event}` });
  const toWaiting = () =>
    step('waiting_online', {
      receipt: 'waiting_online',
      resend: resendRoute(contract, hasBackupChannel),
    });

  switch (event) {
    case 'dispatch':
      if (state !== 'queued') return ignore();
      // 尝试数已经用满 ⇒ 不再投，直接转 waiting_online（重试的出口在这里，不在 ack 分支）。
      if (attempts >= budget) return toWaiting();
      return step('delivering', { attempts: attempts + 1 });
    case 'peer_online':
      if (state !== 'waiting_online') return ignore();
      // 尝试数按「投递轮次」算：转 waiting_online 已经结束了上一轮，补发是新一轮 ⇒ 回到 1。
      // 若把预算算成全局的，waiting_online 就成了死路（永远发不出去），与 §1 那张图直接矛盾。
      return step('delivering', { attempts: 1 });
    case 'ack_ok':
      if (state !== 'delivering') return ignore();
      return step('delivered', { receipt: 'delivered' });
    case 'ack_fail':
    case 'no_ack':
      if (state !== 'delivering') return ignore();
      if (attempts >= budget) return toWaiting();
      // 还有重试预算 ⇒ **回到 queued 等下一次 poll**。服务端不能主动推，
      // 留在 delivering 自环等于卡住：没有任何事件能再从 delivering 触发一次投递。
      return step('queued');
    case 'ttl_elapsed':
      if (isTerminal(contract, state)) return ignore();
      return step('expired', { receipt: 'expired' });
    case 'evicted':
      // 只有还没发出去的消息会被挤位；已经在飞的那条等它的 ack。
      if (state !== 'queued') return ignore();
      return step('dropped', { receipt: 'dropped' });
    default:
      throw new Error(`契约里有、实现没处理的事件：${event}`);
  }
}

/// pending 上限的溢出策略：**丢最旧并给每条补一条回执**（静默丢是明令禁止的那一半）。
function evictionReceipts(contract) {
  const retention = contract.retention || {};
  if (retention.overflowAction !== 'drop_oldest') {
    throw new Error(`契约的 overflowAction 不是 drop_oldest：${retention.overflowAction}`);
  }
  if (!retention.overflowReceipt) {
    throw new Error('retention.overflowReceipt 缺省：挤位必须发回执，不许静默丢');
  }
  return [retention.overflowReceipt];
}

/// 新消息进来后需要挤掉多少条最旧的（0 = 不用挤）。
function evictCount(contract, pendingNow, incoming) {
  const max = ((contract.retention || {}).pendingPerDeviceMax || 0) + 0;
  if (max <= 0) return 0;
  const overflow = pendingNow + (incoming === undefined ? 1 : incoming) - max;
  return overflow <= 0 ? 0 : overflow;
}

module.exports = {
  ackDeadlineSeconds,
  advance,
  canTransition,
  evictionReceipts,
  evictCount,
  initialState,
  isAckOverdue,
  isExpired,
  isTerminal,
  maxAttempts,
  releasesBody,
  retentionDeadline,
};
