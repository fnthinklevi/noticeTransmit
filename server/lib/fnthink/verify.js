// 幻念推送消息级验签（T29-B）· 服务端这一半。
//
// 三条决定写法的规则，都来自契约，不在这里重述数值：
//  ① **公钥只从设备表取，绝不信请求里自带的公钥** —— 否则任何人都能用自己造的钥匙签一条，
//     然后声称自己是任意一个地址码；
//  ② **先验签、再看时间、最后查重放**：顺序决定哪些失败可以对外说清楚。
//     "设备不存在"与"签名不对"必须同一个形状（否则这接口是个地址码枚举器），
//     而验签通过之后，`410 已过期`/`409 重复` 可以照实返回 —— 那时对方身份已被证明；
//  ③ 规范化字节由**服务端按契约重算**，不接受客户端算好的串：契约顺序的意义就在这儿。
//
// 没有 HTTP 路由是故意的（roadmap §4 第 7 条：公网面只开一次，与 T28-B 一起评审）。

'use strict';

const crypto = require('crypto');

const { statusCode } = require('./contract');
const { normalize, alphabetFromContract } = require('./credentials');
const { decideCapability, grantFromNode } = require('./capabilities');
const { peerGrant } = require('./devicestore');
const {
  rememberNonce,
  rememberReject,
  rejectKeyFor,
  seenNonce,
  saveNonces,
} = require('./devicestore');

/// 裸 32 字节 base64 → KeyObject。DER 头来自契约（Kotlin 那份由跨语言守卫对表）。
function publicKeyFromRaw(contract, publicKeyB64) {
  const encoding = (contract.signature || {}).publicKeyEncoding || {};
  const prefix = Buffer.from(String(encoding.spkiPrefixHex || ''), 'hex');
  const rawLength = Number(encoding.rawLength || 0);
  if (prefix.length !== 12 || rawLength !== 32) {
    throw new Error('契约的 publicKeyEncoding 不完整（需要 12 字节 spkiPrefixHex + rawLength=32）');
  }
  const raw = Buffer.from(String(publicKeyB64 || ''), 'base64');
  if (raw.length !== rawLength) {
    throw new Error(`公钥解出 ${raw.length} 字节，应为 ${rawLength}`);
  }
  return crypto.createPublicKey({
    key: Buffer.concat([prefix, raw]),
    format: 'der',
    type: 'spki',
  });
}

/// 按契约顺序 + 契约分隔符拼出待签字节（与 Dart 的 CanonicalMessage.bytes 同一套规则）。
function canonicalBytes(contract, fields) {
  const order = (contract.signature || {}).canonicalOrder || [];
  const separator = String((contract.signature || {} || {}).separator || '');
  if (order.length === 0 || separator === '') {
    throw new Error('契约缺 signature.canonicalOrder 或 separator');
  }
  const parts = order.map((key) => {
    if (fields[key] === undefined || fields[key] === null) {
      throw new Error(
        `签名字段 "${key}" 缺失（不补空串：那会让"没填"与"填了空值"签出同一个字节串）`,
      );
    }
    const text = String(fields[key]);
    if (text.indexOf(separator) >= 0) {
      throw new Error(`签名字段 "${key}" 的值含分隔符，拼接边界会歧义`);
    }
    return text;
  });
  return Buffer.from(parts.join(separator), 'utf8');
}

/// 只做密码学判断，不碰设备表（调用方负责"公钥从哪来"）。
function verifySignature(contract, publicKeyB64, canonical, signatureB64) {
  try {
    return crypto.verify(
      null,
      canonical,
      publicKeyFromRaw(contract, publicKeyB64),
      Buffer.from(String(signatureB64 || ''), 'base64'),
    );
  } catch (e) {
    return false; // 钥匙形状不对与验签失败同形：都不该被分辨
  }
}

/// 「被投那台允许这台投吗、能投到哪一档」——**收单与探针共用这一处**（T106 片①）。
///
/// 返回 `null` = 这条关系不存在（目标没登记、或本机不在它的名单里；两者刻意同形，
/// 见 acceptIncoming 里那段注释）；否则返回 `capabilities.decideCapability` 的裁决。
///
/// 为什么必须只有这一处：非侵入探针的全部价值就是「它说的与真发那条一致」。两处各判一次，
/// 下场是「探针说通、真发被拒」—— 而用户拿着绿徽标去查为什么收不到。
function intakeGrantFor(contract, state, targetKey, senderCode, { type, item }) {
  const target = targetKey === null ? undefined : state.devices[targetKey];
  // 档位与逐条清单读的是**这一段关系**（A 给 B 的那一份），不是 B 自己的记录：
  // 一份授权两个读处就会分叉，所以发送方记录上那份 grant 已经退役（见 devicestore）。
  const peer = target ? peerGrant(contract, target, senderCode) : null;
  if (!peer) return null;
  // 收单这一段判不了"每次本地确认"：那是设备上的一次用户动作。
  // ⚠ 这里**故意不读**请求里的 `confirmedThisTime` —— 从请求里取那个值，
  // 等于让发送方替接收方点"我确认了"，而 L3 那条红线写的正是"不许远端悄悄执行本地动作"。
  return decideCapability(contract, {
    stage: 'intake',
    grant: grantFromNode(contract, peer),
    type,
    item,
  });
}

/// 一次入站消息的完整裁决。`now` 由调用方注入（服务端时间，且测试要能把时钟拧动）。
///
/// ⚠ 身份段与重放段是**从这里抽出去共用的**（`verifyIdentity` / `checkFresh`），因为
/// poll 与 ack 是同一把钥匙签的另两类事件（契约 `clientEvents`）。留在两处各写一遍的话，
/// 下一批改动的表现是"消息入口加了状态白名单，poll 入口没加" —— 吊销了的设备仍能从
/// poll 里读走自己的队列，而那不会有任何一条用例报错。
function acceptIncoming(contract, state, input) {
  const id = verifyIdentity(contract, state, input);
  if (id.outcome) return id.outcome;
  // `device`（发送方自己那一行）在这里**不再参与授权**：过去那行上的 grant 是收单唯一的依据，
  // 于是登记本身就是许可。现在授权读的是被投那台的 grantsBy（见下面那段配对关系）。
  const { sender, canonical } = id;

  // ── 以下是"身份已被证明"的区域，可以照实说（T27/T28 那条同形规则到此为止）──
  const denied = (receipt, reason) =>
    counted(
      contract,
      state,
      input,
      { ok: false, status: statusCode(contract, 'forbidden'), receipt },
      reason,
    );
  // 授权判定要用的 item 必须**出现在已签字节里**：签名覆盖的是 body，
  // 从一个没签过的字段里读"要执行哪个动作"，等于给中间人（或给服务端自己的一次误接）
  // 留一个"借一条已签通知触发一个没签过的动作"的口子。
  const item = typeof input.item === 'string' ? input.item : '';
  if (item !== '' && canonical.toString('utf8').indexOf(item) < 0) {
    return denied('rejected_capability', 'unsigned-item');
  }
  // ── 配对关系（#131 第三片）：被投那台允许这台发送方吗 ──
  // 判在 **target 的 grantsBy** 上（契约 pairing.relationshipStoredOn / enforcedAt）。
  // 旧版没有这一段：收单读的是发送方自己那一行的 grant ⇒ "谁登记过就能给任何人投"，
  // 而 A 侧只能靠 poll 拿到什么才决定显示什么，没有第二次拦截的机会。
  const enforcedAt = String((contract.pairing || {}).enforcedAt || '');
  if (enforcedAt !== 'server-intake') {
    // 不"照旧放行"：契约声明了一条本实现不会执行的闸，必须红，不能静默按另一条路走。
    throw new Error(
      `pairing.enforcedAt=${JSON.stringify(enforcedAt)}：本实现只在服务端收单这一处判配对关系`,
    );
  }
  const targetKey = normalize(alphabetFromContract(contract), String(input.fields.target));
  // 「目标设备不存在」与「存在但没配过对」**同形同码**：分辨它们就等于把地址码表递出去
  //（地址码本来就是要印在二维码上给人抄的公开标识，而登记一把密钥只要几微秒）。
  const cap = intakeGrantFor(contract, state, targetKey, sender, {
    type: String(input.fields.type),
    item,
  });
  if (!cap) return denied('rejected_capability', 'not-paired');
  if (!cap.allowed) return denied('rejected_capability', 'capability:' + cap.reason);

  const fresh = checkFresh(contract, state, input, sender);
  if (fresh.outcome) return fresh.outcome;
  return { ok: true, status: statusCode(contract, 'queued'), receipt: 'queued' };
}

/// 身份段：地址码形状 → 设备表 → 状态白名单 → 验签。
/// 这四种失败对外**逐字节同形**（否则本接口就成了"哪些地址码有效"的枚举器），
/// 内部仍留 reason 供"有 N 次冒充你的尝试"那类展示用。
function verifyIdentity(contract, state, input) {
  // 留痕与对外形状是两件事：`reason` 只进 state.rejects，**绝不出现在响应里**，
  // 所以"未知设备"和"签名不对"在服务端内部可分辨（将来显示"有 N 次冒充你的尝试"），
  // 在网络上看仍是同一个包。
  // 每次现造一个对象：同形那条判据要真的比"两份各自造出来的东西"，
  // 复用同一个实例会让断言在"其实两条走法形状不同"被改坏的那一天也照样绿。
  const forbidden = (reason) =>
    counted(
      contract,
      state,
      input,
      { ok: false, status: statusCode(contract, 'forbidden'), receipt: 'rejected_unsigned' },
      reason,
    );
  const sender = normalize(alphabetFromContract(contract), input.senderAddress || '');
  const device = sender === null ? undefined : state.devices[sender];

  let canonical;
  try {
    canonical = canonicalBytes(contract, input.fields || {});
  } catch (e) {
    // 客户端算的串我们不用；字段不齐是它的错，但**先不透露设备存不存在**，所以同形返回
    return { outcome: forbidden('fields') };
  }

  // ⚠ 判定问的是"这台设备的状态在不在**允许投递**那张表里"，不是"它是不是 frozen"：
  // 后者是黑名单，将来契约新增一个状态（如 awaitingRepair）会静默地"没被枚举到 = 继续投递"。
  const allowedStatuses = (contract.revocation || {}).deliveryAllowedStatuses || [];
  if (!device) return { outcome: forbidden('unknown_device') };
  if (!allowedStatuses.includes(device.status))
    return { outcome: forbidden('status:' + device.status) };
  if (!verifySignature(contract, device.publicKey, canonical, input.signature)) {
    return { outcome: forbidden('signature') };
  }
  return { sender, device, canonical };
}

/// 时间容差与重放，**必须排在身份之后**：顺序决定哪些失败可以对外说清楚。
/// 去重表要落盘 —— 只在内存里记一遍，等于每次重启就重开一次重放窗口。
function checkFresh(contract, state, input, senderKey) {
  const skew = Number((contract.signature || {}).maxSkewSeconds || 0);
  const ts = Number(input.fields.ts);
  if (!Number.isFinite(ts) || Math.abs(input.now - ts * 1000) > skew * 1000) {
    return {
      outcome: counted(
        contract,
        state,
        input,
        { ok: false, status: statusCode(contract, 'expired'), receipt: 'expired' },
        'expired',
      ),
    };
  }
  const nonceKey = `${senderKey}|${input.fields.nonce}`;
  if (seenNonce(state.nonces, nonceKey, input.now)) {
    return {
      outcome: counted(
        contract,
        state,
        input,
        { ok: false, status: statusCode(contract, 'duplicate'), receipt: 'duplicate' },
        'duplicate',
      ),
    };
  }
  rememberNonce(
    state.nonces,
    nonceKey,
    input.now,
    Number((contract.signature || {}).nonceDedupeSeconds || 0),
  );
  // 传了 saveNonces 却不落盘 = "记住了"和"重启还记得"是两件事，这里把后者也接上。
  if (typeof state.persist === 'function') state.persist();
  else saveNonces(state.nonces);
  return { ok: true };
}

/// 拒收都要计一次数（任务书"失败即丢并计数"那条）。只写内存，理由见 devicestore 那段注释。
function counted(contract, state, input, outcome, reason) {
  const rejects = state.rejects || (state.rejects = {});
  rememberReject(rejects, rejectKeyFor(contract, input.senderAddress), input.now, reason);
  return outcome;
}

module.exports = {
  publicKeyFromRaw,
  canonicalBytes,
  verifySignature,
  acceptIncoming,
  // 给 clientEvents（poll / ack / probe）共用的两段：身份段与重放段。
  // ⚠ 它们不是"对外可随便拼的半个裁决"：路由侧只许按 events.js 里那个顺序用，
  //   顺序本身是判据（身份之前同形、之后照实说）。
  verifyIdentity,
  checkFresh,
  // 收单那道授权判定本身也抽出来共用：探针（T106）问的正是同一件事。
  intakeGrantFor,
};
