// 幻念推送的 HTTP 入口（#126）：本项目**第一个面向公网的写入面**。
//
// 这个文件刻意只做四件事，判据一律不掺进来：
//  ① 把请求体里**契约承认的字段**挑出来（多余的键一概不看，也不回显）；
//  ② 把裁决交给已有的纯函数（`verify.acceptIncoming` / `events.authorizeClientEvent` /
//     `messagestore.*`），它们各自带着自己的双端向量与用例；
//  ③ 状态码一律取自契约 `statusCodes`（本文件不出现 4xx 字面量，有源码守卫钉住）；
//  ④ 失败响应**只带一个 receipt 字段**：`reason` 只进内存留痕，绝不出现在响应里
//     —— 否则这三个入口合起来就是一台"哪些地址码存在 / 哪一步没过"的探针。
//
// 三条要写在文件头上的取舍：
// ⚠ **ENCRYPTION_KEY 缺失 ⇒ 收单 500**：不退回明文、也不"先收下回头再补"
//    （契约 `retention.bodyAtRest.refuseWithoutKey=true`；本仓 TOTP 那条"没密钥就存明文"的取舍不外溢）。
// ⚠ 这几个端点豁免 IP 封锁（豁免表在 `store.ipBlockExempt`，与 `/api/version` 同一处）：
//    封锁按 IP 记账，NAT / 反代后的共享出口会让一次误封把一整片设备集体失联，
//    而这里的凭证本来是签名与短期配对口令，不靠封 IP 保护。
// ⚠ **还没有 `/pair`**：握手签名的**被签内容**在契约里没定义。我不在路由里发明它 ——
//    那要先改契约（roadmap #131），所以公网面目前只开到"已配对的设备/发送方"这一层。

'use strict';

const express = require('express');

const { asyncHandler } = require('../middleware');
const { loadContract, assertSupported, statusCode, canonicalOrder } = require('./contract');
const { alphabetFromContract, normalize } = require('./credentials');
const { acceptIncoming } = require('./verify');
const { authorizeClientEvent } = require('./events');
const { loadDevices, loadNonces, saveNonces, touchDevice } = require('./devicestore');
const {
  advanceMessage,
  decryptBodyFor,
  dispatchForDevice,
  enqueue,
  expireDueMessages,
  loadMessages,
  pendingCountFor,
  receiptsForSender,
  saveMessages,
} = require('./messagestore');

const contract = assertSupported(loadContract());
const router = express.Router();

/// 只取契约 `signature.canonicalOrder` 承认的那几个键。
/// 少一个键 ⇒ 下游 `canonicalBytes` 抛（"没填"与"填了空值"必须签出不同的字节）；
/// 多给的键一概丢弃，既不参与判决也不回显。
function signedFields(raw) {
  const source = raw && typeof raw === 'object' ? raw : {};
  const out = {};
  for (const key of canonicalOrder(contract)) {
    if (Object.prototype.hasOwnProperty.call(source, key)) out[key] = source[key];
  }
  return out;
}

/// 一次请求的裁决现场。nonce 由 `checkFresh` 自己落盘 ——
/// 只在内存里记一遍，等于每次重启就重开一次重放窗口。
function freshState() {
  const devices = loadDevices();
  const nonces = loadNonces();
  return { devices, nonces, persist: () => saveNonces(nonces) };
}

function text(value) {
  return typeof value === 'string' ? value : '';
}

function sendFailure(res, status, receipt) {
  res.status(status).json({ receipt });
}

/// 事件层（events.js）的失败：`expired` / `duplicate` 自带 receipt；形状类的
/// （wrong-event-type / target-not-self / ack-fields / malformed-ack / unknown-result）
/// 统一回 `rejected_capability` —— 它是契约词表里"这件事你不被允许这么办"的那一个，
/// 而具体哪一步没过只进 state.rejects。
function eventFailure(outcome) {
  return { status: outcome.status, receipt: outcome.receipt || 'rejected_capability' };
}

function eventInput(body, now) {
  return {
    senderAddress: text(body.sender),
    fields: signedFields(body.fields),
    signature: text(body.signature),
    now,
  };
}

// ── POST /message：投递收单（发送方签名的一条消息）──
router.post(
  '/message',
  asyncHandler(async (req, res) => {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const now = Date.now();
    const fields = signedFields(body.fields);
    const state = freshState();

    const outcome = acceptIncoming(contract, state, {
      senderAddress: text(body.sender),
      fields,
      signature: text(body.signature),
      item: text(body.item),
      now,
    });
    if (!outcome.ok) return sendFailure(res, outcome.status, outcome.receipt);

    const sender = normalize(alphabetFromContract(contract), text(body.sender));
    // title 只在**出现在已签字节里**时才收下（与 item 同一条规则）。标题是屏幕上最显眼的一行，
    // 未签名的标题等于给中间人一次"借真消息挂假标题"的机会。
    const signedText = canonicalOrder(contract)
      .map((key) => String(fields[key] === undefined ? '' : fields[key]))
      .join(String(contract.signature.separator));
    const claimedTitle = text(body.title);
    const title =
      claimedTitle !== '' &&
      signedText.split(String(contract.signature.separator)).includes(claimedTitle)
        ? claimedTitle
        : '';

    const messages = loadMessages();
    const result = enqueue(
      contract,
      messages,
      {
        sender,
        device: String(fields.target === undefined ? '' : fields.target),
        type: String(fields.type === undefined ? '' : fields.type),
        item: text(body.item),
        title,
        body: String(fields.body === undefined ? '' : fields.body),
        dedupeId: body.dedupeId,
      },
      now,
      process.env.ENCRYPTION_KEY,
    );
    saveMessages(messages);

    res.status(outcome.status).json({
      receipt: outcome.receipt,
      messageId: result.message.messageId,
      action: result.action,
      // 被每设备上限挤掉的那些，各自的 dropped 回执已经写在它们自己的记录里 ⇒
      // 发送方下一次 poll 会拿到。这里只报"发生了挤位"这个事实，不另造一条通道。
      evicted: result.evicted.map((e) => e.messageId),
    });
  }),
);

// ── POST /poll：设备取货（poll 即心跳，契约 presence.heartbeatSource）──
router.post(
  '/poll',
  asyncHandler(async (req, res) => {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const now = Date.now();
    const state = freshState();

    const auth = authorizeClientEvent(contract, state, eventInput(body, now), 'poll');
    if (!auth.ok) {
      const failure = eventFailure(auth);
      return sendFailure(res, failure.status, failure.receipt);
    }

    touchDevice(contract, state.devices, auth.sender, now);
    const messages = loadMessages();
    // 到期扫描放在取货之前：过期的那条不该再被当成"待投"下发（正文也按契约已释放）。
    expireDueMessages(contract, messages, now);
    const dispatched = dispatchForDevice(contract, messages, auth.sender, now);

    const out = [];
    for (const taken of dispatched.taken) {
      const record = messages[taken.messageId];
      const content = decryptBodyFor(contract, process.env.ENCRYPTION_KEY, record.body);
      out.push({
        messageId: record.messageId,
        type: record.type,
        item: record.item || '',
        title: content.title,
        body: content.body,
      });
    }
    const receipts = receiptsForSender(
      contract,
      messages,
      auth.sender,
      now,
      contract.clientEvents.poll.maxBatchPerPoll,
    );
    saveMessages(messages);

    res.status(200).json({
      messages: out,
      receipts,
      pending: pendingCountFor(contract, messages, auth.sender),
      // T29 的「ts 以服务端时间判定」到这里才有承载处：设备用它算自己的时钟偏移，
      // 之后签出去的 ts 才是服务端认的那个时间。
      serverTime: now,
    });
  }),
);

// ── POST /ack：设备回执（契约 delivery.ackIsOnlyProof：这是唯一的送达依据）──
router.post(
  '/ack',
  asyncHandler(async (req, res) => {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const now = Date.now();
    const state = freshState();

    const auth = authorizeClientEvent(contract, state, eventInput(body, now), 'ack');
    if (!auth.ok) {
      const failure = eventFailure(auth);
      return sendFailure(res, failure.status, failure.receipt);
    }

    const messages = loadMessages();
    // `clientEvents.ack.onlyForOwnMessages` 分两半：前半段（target 必须是本机）在 events.js，
    // 后半段（那条消息确实下发给我）要拿表来查。这里必须用 hasOwnProperty ——
    // 表是普通对象，`messages['__proto__']` 会取到 Object.prototype 那个真值。
    // ⚠ 反证 H1 量出来的事实：这一条**今天单独不可观察** —— 后面那个 `device === sender`
    //   已经把原型键挡在外面（Object.prototype.device 是 undefined）。留着它是纵深防御：
    //   归属判断哪天被改成"只看存在性"，这里不会静默变宽。与 MACHINE_OWNED 那处同一类。
    // 于是"这条存在且属于我"被判成通过（本仓在会话表上栽过同一类，见 store.js 那段注释）。
    const owned =
      Object.prototype.hasOwnProperty.call(messages, auth.messageId) &&
      messages[auth.messageId].device === auth.sender;
    if (!owned) return sendFailure(res, statusCode(contract, 'forbidden'), 'rejected_capability');

    const event = contract.clientEvents.ack.resultToEvent[auth.result];
    if (!event) return sendFailure(res, statusCode(contract, 'forbidden'), 'rejected_capability');

    const { step } = advanceMessage(contract, messages, auth.messageId, event, { now });
    saveMessages(messages);
    res.status(200).json({ receipt: step.receipt || null, state: step.state });
  }),
);

module.exports = { router, contract };
