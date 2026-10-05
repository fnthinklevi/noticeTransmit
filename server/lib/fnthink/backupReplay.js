// 补推与补发的二选一裁决（T46）· 服务端这一半。
//
// 与 Dart 的 packages/fnthink_push/lib/src/backup_replay.dart 是同一套规则的两份实现，
// 两边都只从契约 `waitingOnline` / `limits` 段读词与读数，并共读
// protocol/fnthink-vectors-v1.json 的 backupReplay 组各断言一遍。
//
// 为什么要有这个函数：delivery.advance 的步里只回答「该走哪条路」，而那条路线词之后
// 的三件事今天没有第二份答案 —— 能不能再补推一次（幂等键）、最多补推几次（上限）、
// 这一发在记录上叫什么（标签）。三样都写在契约里，于是三样都从这里读。
//
// ⚠ 互斥靠「只返回一个 action」兑现，不靠调用方自觉：两条路径并存 = 同一条消息提醒两次。

'use strict';

const SUPPORTED_IDEMPOTENCY_KEY = 'message_id';

const ACTION = {
  backupReplay: 'backup_replay',
  queueResend: 'queue_resend',
  none: 'none',
};

function waitingSection(contract) {
  return (contract.delivery || {}).resendDecisionFrom || 'waitingOnline';
}

/// 补推次数上限（limits.backupReplayMax）。取不到就抛，不退回 0：
/// 退回 0 等于把备用补推这条路悄悄关掉，而这一段就是它唯一的判据。
function backupReplayMax(contract) {
  const max = (contract.limits || {}).backupReplayMax;
  if (typeof max !== 'number' || Number.isNaN(max) || max <= 0) {
    throw new Error(
      `契约缺 limits.backupReplayMax（正整数）：备用补推有几条路可走是这一段的唯一判据`,
    );
  }
  return max;
}

/// 幂等键的字段名（waitingOnline.backupReplayIdempotencyKey）。
/// 本实现只兑现 message_id：契约点名别的键名时照抛，不静默拿旧键顶替 ——
/// 顶替之后去重仍然「看着在跑」，而实际上按另一个字段去重，那正是重复补推的入口。
function idempotencyKeyName(contract) {
  const key = (contract[waitingSection(contract)] || {}).backupReplayIdempotencyKey;
  if (!key) {
    throw new Error('契约缺 waitingOnline.backupReplayIdempotencyKey');
  }
  if (key !== SUPPORTED_IDEMPOTENCY_KEY) {
    throw new Error(
      `waitingOnline.backupReplayIdempotencyKey 是「${key}」，而本实现只兑现「${SUPPORTED_IDEMPOTENCY_KEY}」`,
    );
  }
  return key;
}

/// 裁决：这条已经进了 waiting_online，接下来怎么办。
///
/// route 是状态机给出的那一条路线词；alreadyReplayed / replayCount 由调用方从账里查出来 ——
/// 账在服务端这一份与设备那一份不是同一份，两个实现自己去查就会各查各的。
function decide(contract, input) {
  const opts = input || {};
  const route = opts.route;
  const section = waitingSection(contract);
  const table = contract[section] || {};
  if (route !== table.withBackupChannel) {
    // 路线词不属于这两条之一 = 契约改了而这里没跟上。抛，不猜：猜错的方向是「当成排队补发」
    // （于是和备用补推并存 = 提醒两次），另一头是「当成备用补推」（没备用渠道时用户什么都收不到）。
    if (route !== table.withoutBackupChannel) {
      throw new Error(
        `不是契约 ${section} 里的两条补发路线：${table.withBackupChannel} / ${table.withoutBackupChannel}（收到 ${route}）`,
      );
    }
    return { action: ACTION.queueResend, route: table.withoutBackupChannel, label: null, dedupeKey: null, max: 0, limitReason: null };
  }
  if (opts.alreadyReplayed === true) {
    return { action: ACTION.none, route: null, label: null, dedupeKey: null, max: 0, limitReason: 'already-replayed' };
  }
  const max = backupReplayMax(contract);
  const count = Number(opts.replayCount || 0);
  if (count >= max) {
    return { action: ACTION.none, route: null, label: null, dedupeKey: null, max: 0, limitReason: 'cap-reached' };
  }
  const keyName = idempotencyKeyName(contract);
  const dedupeKey = opts.messageId || '';
  if (!dedupeKey) {
    throw new Error(`补推要按「${keyName}」去重，而它没给出来：拿空键去重等于没去重`);
  }
  const label = table.backupReplayLabel;
  if (!label) {
    throw new Error('契约缺 waitingOnline.backupReplayLabel：补推那一发在记录上叫什么');
  }
  return { action: ACTION.backupReplay, route: table.withBackupChannel, label, dedupeKey, max, limitReason: null };
}

module.exports = {
  ACTION,
  SUPPORTED_IDEMPOTENCY_KEY,
  backupReplayMax,
  decide,
  idempotencyKeyName,
};