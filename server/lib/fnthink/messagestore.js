// 未送达消息的存储（T34-B）：投递状态机第一次有了能落地的地方。
//
// 这个模块存在的理由，是把三件本来会各写一遍的事收到一处：
//  ① **状态推进只能经由 delivery.advance()** —— 本文件里不出现任何状态名字面量
//     （有一条源码守卫逐字检查这一点）。写第二份 `if (state === 'queued')` 的后果不是难维护，
//     而是将来加一个可重发态时，这里不报错，只是那条状态永远取不到。
//  ② **正文只在盘上以密文存在**，且"进入终态 ⇒ 立刻删正文"由契约的 deleteBodyOn 决定
//     （不是由这里决定 —— 见 applyStep 里那行）。
//  ③ **每设备 pending 上限的溢出策略**：丢最旧 + 给每条被丢的补一条 dropped 回执，
//     绝不静默丢。
//
// ⚠ 本模块**不含任何 HTTP 路由**。收单与 poll 的入口在 §4 第 7 条 ① 那次公网面评审里一次开完；
// 现在这些函数没有调用方，这正是"先做内核、后开门"的形状。

'use strict';

const crypto = require('crypto');
const path = require('path');

const { DATA_DIR } = require('./table');
const { loadTable, saveTable } = require('./table');
const delivery = require('./delivery');
const { encryptBody, decryptBody } = require('./bodycrypto');

const MESSAGE_FILE = path.join(DATA_DIR, 'fnthink_messages.json');

/// dedupe_id 只存摘要：它是发送方给的任意串，长度完全可能正好等于口令位数，
/// 而落盘闸门按值形状扫（那是防"顺手多存一个配对口令"的）—— 存摘要两头都干净：
/// 匹配照样成立，表里也永远不会有"像口令的值"。键名以 Digest 结尾是闸门认的形式。
function dedupeDigest(dedupeId) {
  if (!dedupeId) return '';
  return crypto.createHash('sha256').update(String(dedupeId), 'utf8').digest('hex');
}

function loadMessages() {
  return loadTable(MESSAGE_FILE, 'messages');
}

function saveMessages(table) {
  return saveTable(MESSAGE_FILE, 'messages', table);
}

/// 只从契约读，不写死：poll 能取走哪些状态、初态是哪个、"覆盖"允许发生在哪个状态。
function pollableStates(contract) {
  return contract.delivery.pollableStates;
}

function isPollable(contract, state) {
  return pollableStates(contract).includes(state);
}

/// 标题与正文一起装进同一个密信封 —— 分开存就是把标题明文留在盘上，
/// 而验证码、金额、姓名常常就在标题里。
function sealContent(contract, envKey, title, body) {
  return encryptBody(contract, envKey, JSON.stringify({ t: title || '', b: body || '' }));
}

function openContent(contract, envKey, envelope) {
  const parsed = JSON.parse(decryptBody(contract, envKey, envelope));
  return { title: parsed.t || '', body: parsed.b || '' };
}

/// 管理面（T45 投递状态视图）能看到的一行。**逐字段挑，不许 spread**：
/// 一行的旁边就躺着 `body`（密信封）与 `dedupeIdDigest`（发送方给的任意串折成的摘要，
/// 是可离线爆破的靶子），一个 spread 就把 `privacy.auditStoresMetadataOnly` 从承诺变成运气。
/// 这也是端点那侧定过的同一条口径：摘要与明文都不出门。
///
/// `hasBody` 是**给运维看的体检项**，不是给协议用的字段：按契约每个终态都该已释放正文，
/// 所以"终态却有正文"就是那条不变量在真实数据上坏了的痕迹（单测证不了生产盘上没漏）。
///
/// `trail` 是投递时间线（T45 第二片）：`[]` 表示"这条什么都没走过"（一直在初态），
/// **`null` 表示这一行比留痕那一列更早** —— 两者在运维眼里不是同一句话，
/// 前者可以说"没重试过"，后者只能说"没有记录"。`trailDropped` 同理：悄悄裁与悄悄丢是同一个错。
function publicMessage(contract, message) {
  return {
    messageId: message.messageId,
    sender: message.sender || '',
    device: message.device || '',
    type: message.type || '',
    item: message.item || '',
    state: message.state,
    terminal: delivery.isTerminal(contract, message.state),
    attempts: message.attempts,
    queuedAt: message.queuedAt,
    updatedAt: message.updatedAt,
    // 到期的那一刻：视图上那句"最长保留 7 天"要么给时刻要么不给，不许只给天数让人自己加。
    expiresAt: delivery.retentionDeadline(contract, message.queuedAt),
    receipt: message.receipt || null,
    receiptSentAt: message.receiptSentAt || null,
    hasBody: message.body !== undefined,
    trail: Array.isArray(message.trail) ? message.trail : null,
    trailDropped: Number.isInteger(message.trailDropped) ? message.trailDropped : null,
  };
}

/// 这几个字段只能由状态机与本层写。调用方递进来的一律当"名单之外"丢掉 ——
/// 否则 `enqueue({... state: 'delivered'})` 就能绕过整张迁移表，而那条消息的正文
/// 会因为它"自称终态"而被立刻删掉：一个字段换来一次静默丢消息。
const MACHINE_OWNED = [
  'messageId',
  'state',
  'attempts',
  'queuedAt',
  'updatedAt',
  'body',
  'dedupeIdDigest',
  // 这两个也是机器写的：回执由状态机在哪一步产生、报没报过给发送端，都不是调用方能声明的。
  // 让调用方给 `receipt`，等于让它替服务端宣布"这条已经 dropped/delivered"。
  'receipt',
  'receiptSentAt',
  // 时间线同理：它记的是"状态机真的这么走过"，调用方能塞一条进去，视图就成了一台可写的话术。
  'trail',
  'trailDropped',
];

/// 留痕的界只能从契约读（写死一个数 = 改契约不动它，而那正是这条判据存在的理由）。
/// 缺这一档是**抛**而不是退回默认值：没界就是这条消息每 15 秒长一条，7 天四万条 ——
/// 无界的日志是攻击者驱动的存储（端点调用日志那处已经算过这笔账）。
function auditTrailConfig(contract) {
  const trail = ((contract || {}).retention || {}).auditTrail;
  const max = Number(trail && trail.maxPerMessage);
  if (!Number.isInteger(max) || max <= 0) {
    throw new Error(
      `retention.auditTrail.maxPerMessage 必须是正整数（实际 ${trail && trail.maxPerMessage}）：` +
        '投递时间线要么有界，要么就别记',
    );
  }
  return max;
}

/// 落一条留痕。**只有真的推进了才记**（ignored 的那一步什么都没发生，记进去就是把网络噪声
/// 写成历史）；裁的是最旧的、留的是最近的，而**裁掉几条要留下计数** —— 悄悄裁与悄悄丢
/// 在运维眼里是同一个错。
function appendTrail(contract, message, step, now) {
  const max = auditTrailConfig(contract);
  const entries = Array.isArray(message.trail) ? message.trail.slice() : [];
  entries.push({ state: step.state, at: now, event: step.event });
  const overflow = entries.length - max;
  message.trailDropped =
    (Number.isInteger(message.trailDropped) ? message.trailDropped : 0) +
    (overflow > 0 ? overflow : 0);
  message.trail = overflow > 0 ? entries.slice(overflow) : entries;
}

/// 这两个是**输入**而不是存储字段：标题被装进密信封、dedupe_id 被折成摘要。
/// 把它们算进 droppedFields 会让调用方以为"我给的字段被扔了"，其实是被换了个形式存。
const CONSUMED = ['title', 'dedupeId'];

/// 白名单裁剪：名单之外的入参一律丢弃。
/// 「只保留必要字段」没有名单就只是一句愿望，所以名单在契约 `retention.storedFields` 里。
function pickStoredFields(contract, input) {
  const allowed = contract.retention.storedFields.filter((f) => !MACHINE_OWNED.includes(f));
  const out = {};
  const dropped = [];
  for (const [key, value] of Object.entries(input)) {
    if (value === undefined) continue; // 没给值 = 缺省，不是"多给了字段"
    if (!allowed.includes(key)) {
      if (!CONSUMED.includes(key)) dropped.push(key);
      continue;
    }
    out[key] = value;
  }
  return { node: out, dropped };
}

function pendingCountFor(contract, messages, device) {
  return Object.values(messages).filter((m) => m.device === device && isPollable(contract, m.state))
    .length;
}

/// 落一条状态机推进的结果。**删正文这件事只在这里发生**，判据取自契约表（advance 带回来的）。
function applyStep(contract, messages, message, step, now) {
  message.state = step.state;
  message.attempts = step.attempts;
  // 回执由**状态机**产生并留在这里（不是由路由另写一份 state→receipt 映射）。
  // 忽略步不覆盖：`ignored` 意味着什么都没发生，把上一次的回执擦掉就是丢账。
  if (step.receipt) message.receipt = step.receipt;
  if (step.ignored) {
    // ⚠ 这一支对**时间线**是纵深防御，不是唯一那道闸：ack 那一路的忽略步在 `advanceMessage`
    //   开头就返回了，根本到不了这里（反证 TL1 因此红不了，2026-09-29 实测）。
    //   今日真能走到这一支的只有 `evictOverflow` 里"在飞的那条挤不掉"那一次。
    //   留痕不记 ignored 步这条判据由 `advanceMessage` 那条返回钉住（用例：被忽略的那一步不进时间线）。
    messages[message.messageId] = message;
    return step;
  }
  // 留痕排在擦正文之前：记的是"这一步发生了什么"，与正文走不走无关
  appendTrail(contract, message, step, now);
  if (step.deleteBody) {
    // 记录本身留着（审计只要元数据：privacy.auditStoresMetadataOnly），正文必须走。
    delete message.body;
  }
  message.updatedAt = now;
  messages[message.messageId] = message;
  return step;
}

/// 回执账：把"我发出去、且已经到了终态"的消息回给发送端。
///
/// 三条判据都得在这里，而不是在路由里：
///  ① 只回**终态**（非终态还没有结论，回出去就是谎报）；
///  ② 只回**没报过**的（`receiptSentAt` 一置，同一条回执不会每次 poll 重复刷屏）；
///  ③ 正文已经按契约删掉了，回执照样发得出 ——「送达了没有」是元数据，不是内容。
function receiptsForSender(contract, messages, sender, now, limit) {
  if (!sender) return [];
  const mine = Object.values(messages)
    .filter(
      (m) =>
        m.sender === sender &&
        delivery.isTerminal(contract, m.state) &&
        m.receipt &&
        !m.receiptSentAt,
    )
    .sort(
      (a, b) => (a.updatedAt || 0) - (b.updatedAt || 0) || (a.messageId < b.messageId ? -1 : 1),
    );
  const out = mine.slice(0, Math.max(0, Number(limit) || 0));
  for (const m of out) {
    m.receiptSentAt = now;
    messages[m.messageId] = m;
  }
  return out.map((m) => ({ messageId: m.messageId, target: m.device, receipt: m.receipt }));
}

/**
 * 收单：加密正文、按 dedupe_id 覆盖或新增、按每设备上限挤位。
 *
 * 返回 `{action, message, evicted, droppedFields}`（action 是**这次入队做了什么**，与投递状态无关）：
 * - `new`       新增一条
 * - `refreshed` 同 dedupe_id 且仍在"可覆盖"那一态 ⇒ 换一份新正文，不新增记录
 * - `duplicate` 同 dedupe_id 但已经发出去了 ⇒ 判重，不覆盖（否则同一条通知提醒两次）
 * `evicted` 是被上限挤掉的条目（每条都带 `dropped` 回执，调用方要把它回给发送端）。
 */
function enqueue(contract, messages, input, now, envKey) {
  const device = String(input.device || '');
  if (!device) throw new Error('消息必须归属一台设备（device）才能排队');
  const dedupeId =
    input.dedupeId === undefined || input.dedupeId === null ? '' : String(input.dedupeId);
  const refreshWhile = contract.privacy.dedupeRefreshWhile;

  if (dedupeId) {
    const digest = dedupeDigest(dedupeId);
    const existing = Object.values(messages).find(
      (m) =>
        m.device === device &&
        m.dedupeIdDigest === digest &&
        !delivery.isTerminal(contract, m.state),
    );
    if (existing) {
      if (existing.state !== refreshWhile) {
        return {
          action: 'duplicate',
          message: existing,
          evicted: [],
          droppedFields: [],
          evictionBlocked: 0,
        };
      }
      const { node, dropped } = pickStoredFields(contract, input);
      Object.assign(existing, node);
      existing.body = sealContent(contract, envKey, input.title, input.body);
      existing.queuedAt = now;
      existing.updatedAt = now;
      messages[existing.messageId] = existing;
      return {
        action: 'refreshed',
        message: existing,
        evicted: [],
        droppedFields: dropped,
        evictionBlocked: 0,
      };
    }
  }

  const { node, dropped } = pickStoredFields(contract, input);
  const message = {
    ...node,
    // 不接受调用方给的 id：那等于让对端决定主键（覆盖别人的消息）。
    // 前缀 `m_` 不是装饰 —— 落盘闸门按"值长得像不像口令"扫，裸 UUID 去掉连字符正好
    // 等于端点口令的 32 位，会被自己的闸门拦下（这条是被测试逮到的）。
    messageId: 'm_' + crypto.randomBytes(12).toString('hex'),
    device,
    // 没有 dedupe_id 就**不写这个键**，而不是写一个空串：落盘那道闸门要求任何 `*Digest` 都是
    // 64 位十六进制摘要，空串过不去 ⇒ "不带 dedupe_id 的消息根本存不进来"。
    // 这个缺陷是 #126 接上 HTTP 才现形的：此前的用例每条都带了 dedupeId，于是 161 例全绿
    // 却一条也没测到最常见的形状。
    ...(dedupeId ? { dedupeIdDigest: dedupeDigest(dedupeId) } : {}),
    state: contract.delivery.initialState,
    attempts: 0,
    queuedAt: now,
    updatedAt: now,
    // 空白时间线，不是一条"已排队"的留痕：留痕记的是**状态机走过的那一步**，
    // 而刚入队的这条什么都没走过（"排队中"这件事由 `state` + `queuedAt` 说，不必再记一遍）。
    // 反过来，早于这一片的旧行**没有这个键** ⇒ 读口给出 null，视图就能说清"这条没有留痕"
    // 与"这条留痕是空的"是两件事。
    trail: [],
    trailDropped: 0,
    body: sealContent(contract, envKey, input.title, input.body),
  };

  messages[message.messageId] = message;
  const { evicted, blocked } = evictOverflow(contract, messages, device, now);
  return { action: 'new', message, evicted, droppedFields: dropped, evictionBlocked: blocked };
}

/// 每设备 pending 上限：**丢最旧**，每条都走一遍状态机（于是它也按契约释放正文）。
/// 挤位不是"删一行"，是一次 `evicted` 事件 —— 差别就在于被挤的那条会留下 dropped 回执。
///
/// ⚠ 候选**只有"还没发出去的"那一档**（契约 `delivery.initialState`），不是"所有可投递的"：
///   `waiting_online` 遇 `evicted` 在迁移表里是 ignored（已经在飞的那条等它的 ack），
///   老实现把两类混在一起挑，于是最旧那条往往正是 in-flight 的 ⇒ 三件坏事同时发生：
///   ① 它照样被 push 进 `evicted` 并回一条 `dropped` 回执 —— 发送端被告知"已丢"，
///      而那条其实还挂在表里等着补发，之后同一个 `message_id` 又能收到一条 `delivered`
///      （一次谎报与一次静默丢，在"不静默丢"这条不变量上是同一个反面）；
///   ② 这一次 ignored 照样扣掉一个挤位预算 ⇒ 上限根本没腾出来，表可以长期超 `pendingPerDeviceMax`；
///   ③ 挤位看起来"成功"（evicted 非空），谁都不会去查。
///   代价要说明白：这样一来上限**管不住**堆了几百条 `waiting_online` 的设备（那些只能等自己的
///   ack 或 `ttl_elapsed`）。`evictionBlocked` 就是把这件事留在响应里而不是留在猜里。
function evictOverflow(contract, messages, device, now) {
  const max = contract.retention.pendingPerDeviceMax;
  const receipts = delivery.evictionReceipts(contract);
  const initial = delivery.initialState(contract);
  const evicted = [];
  let over = pendingCountFor(contract, messages, device) - max;
  while (over > 0) {
    const oldest = Object.values(messages)
      .filter((m) => m.device === device && m.state === initial)
      .sort((a, b) => a.queuedAt - b.queuedAt || (a.messageId < b.messageId ? -1 : 1))[0];
    if (!oldest) break;
    const step = delivery.advance(contract, {
      state: oldest.state,
      event: 'evicted',
      attempts: oldest.attempts,
    });
    // 只挤得动"真的动了"的那一条：ignored 一步既不删行也不腾地方，扣预算就是装样子。
    // ⚠ 这一行今日**不可单独观察**（候选已被上面那道初态筛限定，`evicted` 对初态永远不 ignored）；
    //    反证 TD2 因此红不了，按假绿登记 —— 它防的是将来往迁移表加一条 `waiting_online → dropped`
    //    之类的边（那时候选与迁移会各自变化），属纵深防御，不是没用。
    if (step.ignored) break;
    applyStep(contract, messages, oldest, step, now);
    evicted.push({ messageId: oldest.messageId, receipt: step.receipt || receipts[0] });
    over -= 1;
  }
  // 留在表里的那些"可投递但挤不动"的（在飞 / 等对端上线），按定义就是没腾出来的额度。
  const blocked = pendingCountFor(contract, messages, device) - max;
  return { evicted, blocked: blocked > 0 ? blocked : 0 };
}

/// 状态机推进的唯一入口（ack、超时、到期都走这里）。
function advanceMessage(contract, messages, messageId, event, options) {
  const message = messages[messageId];
  if (!message) throw new Error(`没有这条消息：${messageId}`);
  const opts = options || {};
  const step = delivery.advance(contract, {
    state: message.state,
    event,
    attempts: message.attempts,
    hasBackupChannel: opts.hasBackupChannel === true,
  });
  if (step.ignored) {
    // 迟到的 ack / 重复的事件：什么都不动（连 updatedAt 都不动，否则审计时间线会被噪声填满）
    return { step, message };
  }
  applyStep(contract, messages, message, step, opts.now || Date.now());
  return { step, message };
}

/// poll 取货：按排队顺序把可投递的条目交给设备。
///
/// "该不该把这条交出去"不靠比较状态名，靠**推进结果**：dispatch / peer_online 成功时
/// 尝试数一定 +1（见 delivery 的迁移语义），所以"尝试数变了没有"就是"发出去了没有"。
function dispatchForDevice(contract, messages, device, now) {
  const taken = [];
  const skipped = [];
  const initial = contract.delivery.initialState;
  const candidates = Object.values(messages)
    .filter((m) => m.device === device && isPollable(contract, m.state))
    .sort((a, b) => a.queuedAt - b.queuedAt || (a.messageId < b.messageId ? -1 : 1));
  for (const message of candidates) {
    if (!message.body) {
      // 可投递的状态却没有正文 = 不变量被破坏（比如某处把正文提前删了）。
      // **在推进之前**就抛：否则状态已经改了一半，而调用方因为异常不会落盘。
      throw new Error(
        `消息 ${message.messageId} 处于可投递状态却没有正文（不变量被破坏，拒绝下发空内容）`,
      );
    }
    const event = message.state === initial ? 'dispatch' : 'peer_online';
    const before = message.attempts;
    const step = delivery.advance(contract, {
      state: message.state,
      event,
      attempts: message.attempts,
    });
    applyStep(contract, messages, message, step, now);
    if (step.ignored || step.attempts === before) {
      skipped.push({ messageId: message.messageId, reason: step.ignored || 'not-dispatched' });
      continue;
    }
    taken.push({ messageId: message.messageId, type: message.type, item: message.item });
  }
  return { taken, skipped };
}

/// 到期扫描：非终态且超过 maxRetentionDays 的全部走一遍 `ttl_elapsed`。
/// 由路由侧在 poll 时顺手跑（服务端不主动探测设备），所以它必须是幂等的。
function expireDueMessages(contract, messages, now) {
  const expired = [];
  for (const message of Object.values(messages)) {
    if (delivery.isTerminal(contract, message.state)) continue;
    if (!delivery.isExpired(contract, message.queuedAt, now)) continue;
    const step = delivery.advance(contract, {
      state: message.state,
      event: 'ttl_elapsed',
      attempts: message.attempts,
    });
    applyStep(contract, messages, message, step, now);
    if (!step.ignored) expired.push({ messageId: message.messageId, receipt: step.receipt });
  }
  return { expired };
}

module.exports = {
  MESSAGE_FILE,
  advanceMessage,
  evictOverflow,
  dedupeDigest,
  decryptBodyFor: openContent,
  dispatchForDevice,
  enqueue,
  expireDueMessages,
  loadMessages,
  pendingCountFor,
  publicMessage,
  receiptsForSender,
  saveMessages,
};
