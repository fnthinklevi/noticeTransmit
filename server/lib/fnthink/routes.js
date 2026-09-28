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
// ⚠ **公网面的开口从这个文件起分成两层**：`/message`、`/poll`、`/ack` 只接受**已在设备表里**的
//    签名者，而 `/register`、`/pair-arm`、`/pair` 这三条把口子开到了"还没有配对关系"的那一侧。
//    其中 `/register` 是全协议唯一一类**提交者还没有身份**的写入面（它自带公钥，证明的是私钥持有），
//    所以它多带了三道别处没有的闸门：按 IP 的独立额度（在 app.js 那层）、
//    设备表上限（契约 `limits.devicesMax`，到顶只拒新的、绝不覆盖已有记录）、
//    以及"公钥形状不对"与"签名不对"同形（否则这条入口就是一台枚举器）。
// ⚠ **配对在这里只到"待确认"为止**：`/pair` 成功 = 表里多一条 pending 请求，A 下一次 poll 能看见它。
//    服务端从不把任何设备写进任何人的白名单（契约 `pairing.autoApprove=false`），
//    确认那一步要 A 自己签一条 pairConfirm —— 那是第三片，没有它之前配不上对是**预期行为**，不是坏了。

'use strict';

const express = require('express');

const { asyncHandler } = require('../middleware');
const {
  loadContract,
  assertSupported,
  statusCode,
  canonicalOrder,
  shapeError,
} = require('./contract');
const { alphabetFromContract, normalize } = require('./credentials');
const { acceptIncoming } = require('./verify');
const { createSenderQuota } = require('./senderquota');
const {
  authorizeClientEvent,
  authorizeRegister,
  authorizePairArm,
  authorizePair,
  authorizePairConfirm,
} = require('./events');
const {
  DEVICE_CAP_CODE,
  DEVICE_KEY_SWAP_CODE,
  armPairingCode,
  loadDevices,
  loadEndpoints,
  recordEndpointCall,
  loadNonces,
  registerDevice,
  saveNonces,
  touchDevice,
} = require('./devicestore');
const {
  createRequest,
  decideRequest,
  initialStatus,
  loadRequests,
  pendingFor,
  pollKey,
  requestSpec,
} = require('./pairstore');
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
const { createEndpointIngress, readIngress } = require('./endpointintake');

const contract = assertSupported(loadContract());
const router = express.Router();
// 按**已证明的发送方地址**计的配额（#130-A2）：计额点只能在验签之后 ——
// 请求体里那个 sender 在验签之前只是字符串，按它计额的后果是 DoS 转移（攻击者拿别人的地址
// 把受害者顶到 429）。所以它出现在下面每条路由的 `auth.ok` 之后、业务副作用之前。
// 数字与名单全部来自契约（经 ratelimit.windowsFor），这里不写第二个数。
const rejectIfOverQuota = createSenderQuota();

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

/// poll 每条消息回哪些字段：名单取自契约 `clientEvents.poll.messageFields`。
///
/// 为什么按名单投影而不是写一个对象字面量：设备侧的收件表（T47）与这条响应之间只有这一份
/// 共同出处。`sender` 就是这么补进来的 —— 此前的字面量只回 messageId/type/item/title/body，
/// 于是"列设计到一半发现无处取发件人"。名单留在代码里，下一次缺口仍是同样的现形方式。
/// ⚠ 校验放在**装载时**而不是请求里：名单与这台实现对不上，属契约内容不达标（SHAPE），
///   按 #130-A4 定的口径只该降级幻念推送那一段并让启动横幅说破原因；放到请求里就变成
///   "第一条带货的 poll 冒 500"，而投影不出来的那一列本来会**静默地空着**。
const POLL_PROJECTABLE = ['messageId', 'type', 'item', 'title', 'body', 'sender'];

function pollMessageFields(c) {
  const declared =
    c.clientEvents && c.clientEvents.poll ? c.clientEvents.poll.messageFields : undefined;
  if (!Array.isArray(declared) || declared.length === 0) {
    throw shapeError('契约缺 clientEvents.poll.messageFields：poll 回哪些字段必须有共同出处');
  }
  const bogus = declared.filter((f) => !POLL_PROJECTABLE.includes(f));
  if (bogus.length > 0) {
    throw shapeError(
      `clientEvents.poll.messageFields 里的「${bogus.join('」「')}」投影不出来` +
        `（可投影面只有 ${POLL_PROJECTABLE.join(', ')}：消息表的身份列 + 密信封里的 title/body）`,
    );
  }
  return declared;
}

const POLL_FIELDS = pollMessageFields(contract);

function projectForPoll(record, content) {
  const source = {
    messageId: record.messageId,
    type: record.type,
    item: record.item || '',
    sender: record.sender || '',
    title: content.title,
    body: content.body,
  };
  const out = {};
  for (const field of POLL_FIELDS) out[field] = source[field];
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

/// 身份还没被证明那一段的对外回执**取自契约**（`signature.onFailure.receipt`）：
/// 本文件不写 receipt 字面量，与"状态码一律从契约读"是同一条纪律。
const unsignedReceipt = String(((contract.signature || {}).onFailure || {}).receipt);

/// register 的入参：`fields` 里仍是契约那六个键，顶层多带的是 publicKey 与 name ——
/// 只有"自带公钥"的那一种事件才有这两个键，所以它单独一个构造函数，不塞进 eventInput 里
/// 让 poll/ack 也顺手带上（那两个会一路同形地把别人的公钥当成发送者的）。
function registerInput(body, now) {
  return Object.assign({}, eventInput(body, now), {
    publicKey: text(body.publicKey),
    name: text(body.name),
  });
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
    if (rejectIfOverQuota(res, 'message', sender)) return;
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

    if (rejectIfOverQuota(res, 'poll', auth.sender)) return;
    touchDevice(contract, state.devices, auth.sender, now);
    const messages = loadMessages();
    // 到期扫描放在取货之前：过期的那条不该再被当成"待投"下发（正文也按契约已释放）。
    expireDueMessages(contract, messages, now);
    const dispatched = dispatchForDevice(contract, messages, auth.sender, now);

    const out = [];
    for (const taken of dispatched.taken) {
      const record = messages[taken.messageId];
      const content = decryptBodyFor(contract, process.env.ENCRYPTION_KEY, record.body);
      out.push(projectForPoll(record, content));
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
      // 配对请求走的是另一张表（它不是消息：没有正文、不过 type 词表），
      // 但它的可见性与消息一样只有一条路 —— 设备来取。键名取自契约 pairRequest.pollKey，
      // 少这一行的表现是"请求躺在表里，A 屏幕上永远显示等待配对"。
      [pollKey(contract)]: pendingFor(contract, loadRequests(), auth.sender, now),
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

    if (rejectIfOverQuota(res, 'ack', auth.sender)) return;
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

/// 契约声明「这一步不许带」的字段（privateKey / endpointSecret 这类顶层形态）。
/// 只判"带没带"：值一概不读、不转存、不回显。
/// ⚠ 为什么必须在**路由**这里也判一次：裁决层（events.js）拿到的 input 是本文件组装出来的，
///   没抄进来的键它永远看不见 —— 那一层的 mayNotCarry 只保护直接调用方，HTTP 上是空转的
///   （这条是本片用例抓出来的：带私钥来的包曾经回了 200）。
///   两处读同一份契约名单不是第二份真值，是同一个规矩的两个执行点。
function carriesForbidden(body, spec) {
  return (spec.mayNotCarry || []).filter((f) => Object.prototype.hasOwnProperty.call(body, f));
}

// ── POST /register：设备自登记（#131 第一片那个函数在这里第一次有调用方）──
// 唯一一类"表里还没有他"的事件：公钥随请求来、签名证明的是私钥持有。
// ⚠ 三条闸门都在下面：上限只拒新的（绝不覆盖已有记录）、形状不对与签名不对同形、
//    按 IP 的独立额度在 app.js 那一层（本文件不重复判，判两遍就会出现两份额度表）。
router.post(
  '/register',
  asyncHandler(async (req, res) => {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const now = Date.now();
    const state = freshState();

    // 带着不该带的秘密来的包，连"是谁"都不必回答就丢掉，且回的是与"没签上"同一句话
    //（否则这条入口多了一种可分辨的失败形状）。
    if (carriesForbidden(body, contract.clientEvents.register).length) {
      return sendFailure(res, statusCode(contract, 'forbidden'), unsignedReceipt);
    }
    const auth = authorizeRegister(contract, state, registerInput(body, now));
    if (!auth.ok) {
      // 这一段的失败全在身份证明之前 ⇒ 对外只有那一枚契约规定的"没签上"回执。
      return sendFailure(res, auth.status, auth.receipt || unsignedReceipt);
    }
    let record;
    try {
      record = registerDevice(
        contract,
        state.devices,
        { addressCode: auth.addressCode, publicKey: auth.publicKey, name: auth.name },
        now,
      );
    } catch (e) {
      const code = e && e.code;
      // 只有"实例满了"这一种可以说出去（429 不透露任何身份信息，且本来就带 Retry-After）。
      if (code === DEVICE_CAP_CODE) {
        return res.status(statusCode(contract, 'rateLimited')).json({});
      }
      // 换公钥：业务拒绝，但**必须与"签名不对"逐字节同形**。
      // 让它们冒成 500 的话，errorMiddleware 的日志与（development 下的）正文里就带着地址码，
      // /register 从此是一台"哪些地址码已绑过钥匙"的枚举器 —— 见 devicestore 那三枚 code。
      if (code === DEVICE_KEY_SWAP_CODE) {
        return sendFailure(res, statusCode(contract, 'forbidden'), unsignedReceipt);
      }
      // 其余异常一律继续往上抛：把代码 bug 咽成一次 4xx，
      // 就是 app.js 那次 503 降级同样的错法（缺陷伪装成部署问题）。
      throw e;
    }
    // 不回显公钥（它本来就是设备自己带来的），也不回显任何摘要：
    // 设备要确认的是"我这行记上了、档位是多少"，别的它无从核对也不需要核对。
    res.status(200).json({
      // 登记**不给任何授权**，所以这里没有 level 可回（第三片把 grant 从发送方记录上撤了）：
      // 回一个空的 grantsBy 长度，让设备知道"你得先被谁配对"，而不是误以为已经能发。
      addressCode: auth.addressCode,
      name: record.name,
      peersGrantingMe: Object.keys(record.grantsBy || {}).length,
      serverTime: now,
    });
  }),
);

// ── POST /pair-arm：A 把自己那枚一次性配对口令挂上服务端（只存摘要）──
router.post(
  '/pair-arm',
  asyncHandler(async (req, res) => {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const now = Date.now();
    const state = freshState();

    if (carriesForbidden(body, contract.clientEvents.pairArm).length) {
      return sendFailure(res, statusCode(contract, 'forbidden'), unsignedReceipt);
    }
    const auth = authorizePairArm(contract, state, eventInput(body, now));
    if (!auth.ok) {
      const failure = eventFailure(auth);
      return sendFailure(res, failure.status, failure.receipt);
    }
    if (rejectIfOverQuota(res, 'pairArm', auth.addressCode)) return;
    const pairing = armPairingCode(
      contract,
      state.devices,
      auth.addressCode,
      auth.pairingCode,
      now,
    );
    // 回的是过期时间与"已消耗=null"这类元信息，**口令与摘要都不回显**：
    // A 自己生成的那串它已经知道了，复述一遍只是多一次泄露机会。
    res.status(200).json({
      armed: true,
      expiresAt: pairing.expiresAt,
      ttlSeconds: Math.round((pairing.expiresAt - now) / 1000),
      serverTime: now,
    });
  }),
);

// ── POST /pair：B 带着 A 的口令来握手 ⇒ 表里多一条**待 A 确认**的请求 ──
// ⚠ 这一步不授权任何东西：`pairing.autoApprove=false`，白名单只能由 A 自己的确认签名进来（第三片）。
router.post(
  '/pair',
  asyncHandler(async (req, res) => {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const now = Date.now();
    const state = freshState();

    if (carriesForbidden(body, contract.clientEvents.pair).length) {
      return sendFailure(res, statusCode(contract, 'forbidden'), unsignedReceipt);
    }
    const auth = authorizePair(contract, state, eventInput(body, now));
    if (!auth.ok) {
      const failure = eventFailure(auth);
      return sendFailure(res, failure.status, failure.receipt);
    }
    if (rejectIfOverQuota(res, 'pair', auth.requester)) return;
    const requests = loadRequests();
    const created = createRequest(contract, requests, auth, now);
    if (!created.ok) {
      // 容量类拒绝：与"这条请求没通过判据"是两个世界，但对外仍只有同一句话
      //（配对不许成为"哪些地址码挂着口令"的探针）。状态码取契约，别写 429 字面量。
      return res.status(statusCode(contract, 'rateLimited')).json({});
    }
    res.status(statusCode(contract, 'queued')).json({
      requestId: created.request.id,
      // 状态名取自契约那张表，路由里不出现 'pending' 字面量：
      // 哪天初始态改名，写死的那份不会报错，只会让设备侧读到一个不认识的状态。
      status: initialStatus(contract, requestSpec(contract)),
      expiresAt: created.request.expiresAt,
      serverTime: now,
    });
  }),
);

// ── POST /pair-confirm：A 处理自己的一条配对请求（唯一一次授权写入）──
// 这一条是 #131 的收口：前两片只证明"B 知道那枚口令"并挂起请求，授权一直是空的。
// ⚠ 授权写在**被投那台**的 grantsBy 上（契约 pairing.relationshipStoredOn）；
//   归属与"只能处理一次"由 pairstore 拿着两张表判，本文件只串顺序。
router.post(
  '/pair-confirm',
  asyncHandler(async (req, res) => {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const now = Date.now();
    const state = freshState();

    if (carriesForbidden(body, contract.clientEvents.pairConfirm).length) {
      return sendFailure(res, statusCode(contract, 'forbidden'), unsignedReceipt);
    }
    const auth = authorizePairConfirm(contract, state, eventInput(body, now));
    if (!auth.ok) {
      const failure = eventFailure(auth);
      return sendFailure(res, failure.status, failure.receipt);
    }
    if (rejectIfOverQuota(res, 'pairConfirm', auth.target)) return;
    const requests = loadRequests();
    const decided = decideRequest(contract, requests, state.devices, auth, now);
    if (!decided.ok) {
      // 三种走法（没这条 / 不是你的 / 已处理过）对外同一句话：
      // 一个能被分辨的 requestId 就等于把"谁的配对请求还在等"这件事说出去了。
      return sendFailure(res, statusCode(contract, 'forbidden'), 'rejected_capability');
    }
    res.status(200).json({
      requestId: decided.request.id,
      status: decided.request.status,
      // 同意才有的东西；拒绝时是 null —— 让设备能分清"我刚才划掉了"与"我刚才同意了"。
      grantedLevel: decided.grant ? decided.grant.maxLevel : null,
      serverTime: now,
    });
  }),
);

// ── 端点收单（T39 + T40 + T41）：口令鉴权的那两条入口 ─────────────────
//
// 与上面那七条签名路由的根本差别：这里的发送方不是设备，是一把共享长期口令（服务端只有摘要）。
// 所以它不产 nonce 台账、不走 acceptIncoming，而是自己一条裁决链（endpointintake.decideIngress）；
// 但**裁完就共用同一个状态机**（enqueue）—— 排队、补发、到期删正文那些事不该有两套实现。
//
// ⚠ 装配在**模块顶层**读契约是安全的、也是刻意的：本文件被 lib/app.js 那段 try require 进来，
//   契约不达标时抛的是可降级的 SHAPE ⇒ 启动日志当场说破原因，而不是等第一条请求才冒 500
//   （A5 那次实测踩过：新模块在顶层读契约本身没问题，怕的是它在 try 之外）。
const endpointIngress = createEndpointIngress(contract);

/// POST 形态的口令在 Authorization: Bearer 里。两种形态都不许把口令放进 query ——
/// URL 的 query 会被 access log、浏览器历史与中间代理各留一份副本，而脱敏规则只管路径段。
function bearerSecret(req) {
  const raw = String(
    req.headers && req.headers.authorization ? req.headers.authorization : '',
  ).trim();
  const match = /^Bearer\s+(\S+)$/i.exec(raw);
  return match ? match[1] : '';
}

function handleEndpointIngress(req, res, endpointId, secret, method) {
  const now = Date.now();
  const ip = req.ip || 'unknown';
  const message = readIngress(contract, req.query, req.body);
  const endpoints = loadEndpoints();
  const secure =
    req.secure === true || String(req.headers['x-forwarded-proto'] || '').toLowerCase() === 'https';
  const verdict = endpointIngress.decide({
    endpoints,
    endpointId,
    secret,
    message,
    secure,
    ip,
    method,
    now,
  });
  if (!verdict.ok) {
    if (verdict.logEndpointId) {
      recordEndpointCall(
        contract,
        endpoints,
        verdict.logEndpointId,
        { at: now, ip, outcome: verdict.logOutcome },
        now,
        endpointIngress.state.endpointCfg,
      );
    }
    if (verdict.retryAfter) res.set('Retry-After', String(verdict.retryAfter));
    // 失败响应最多一个 receipt（能力被拒那种"对方必须知道该改什么"的），其余空 body：
    // 这一面同时开着"这把口令对不对"的探测面，能少说一个字就少说一个字。
    return res.status(verdict.status).json(verdict.receipt ? { receipt: verdict.receipt } : {});
  }
  const messages = loadMessages();
  // ⚠ sender 用一个**明显不是设备地址**的形状：端点没有取货通道，这条 202 就是它的回执。
  //   填一个地址码形状会怎样？receiptsForSender 会往一个不存在的人身上堆回执，
  //   而那堆东西永远不会被取走，也没有任何 poll 能看见 —— 存储被无声占着。
  const result = enqueue(
    contract,
    messages,
    {
      sender: `endpoint:${verdict.endpointId}`,
      device: verdict.target,
      type: 'notice',
      item: '',
      title: message.title,
      body: message.body,
      dedupeId: message.dedupeId,
    },
    now,
    process.env.ENCRYPTION_KEY,
  );
  saveMessages(messages);
  // 调用日志只在**认出了端点**时记（随机 id 不该能凭空造出条目），且只记元数据：
  // 正文与标题一个字节都不进日志（契约 endpoint.callLog.fields 钉着这一点）。
  recordEndpointCall(
    contract,
    endpoints,
    verdict.logEndpointId,
    {
      at: now,
      ip,
      outcome: result.action === 'duplicate' ? 'duplicate' : 'queued',
    },
    now,
    endpointIngress.state.endpointCfg,
  );
  return res.status(verdict.status).json({
    messageId: result.message.messageId,
    action: result.action,
    evicted: result.evicted.map((e) => e.messageId),
  });
}

router.get(
  '/p/:endpointId/:secret',
  asyncHandler(async (req, res) =>
    handleEndpointIngress(req, res, req.params.endpointId, req.params.secret, 'GET'),
  ),
);

router.post(
  '/p/:endpointId/:secret',
  asyncHandler(async (req, res) =>
    handleEndpointIngress(req, res, req.params.endpointId, req.params.secret, 'POST'),
  ),
);

router.post(
  '/p/:endpointId',
  asyncHandler(async (req, res) =>
    handleEndpointIngress(req, res, req.params.endpointId, bearerSecret(req), 'POST'),
  ),
);

module.exports = { router, contract };
