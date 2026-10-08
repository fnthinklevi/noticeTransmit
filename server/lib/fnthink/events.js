// 设备自己签的事件（T32 的 poll、T35 的 ack、#131 的 register，下一片加 pair）：
// 契约 clientEvents 段的执行处。种类不写死在这里 —— 名单、钥匙来源、作用范围三件事全从契约读，
// 本文件只保证"没实现分支就抛"，不保证"多加一种事件时代码已经跟上"（那是这里要红，不是要静默）。
//
// 为什么不塞进 verify.js：verify.js 判的是「一条消息能不能收」，这里判的是「一台设备能不能问
// 它自己该问的事」。两者**共用身份段与重放段**（从 verify.js 引过来），不共用中间那层裁决 ——
// 消息要过 capabilities 的 type 词表，而事件按契约必须**不**在那张表里，所以接进
// acceptIncoming 只会让两条路互相判红。
//
// 与 acceptIncoming 同样的顺序纪律：身份之内一律同形（不透露这台设备存不存在），
// 身份证明之后才分辨 410 过期 / 409 重复 / 403 这个事件本身不合法。
// ⚠ 事件类型检查排在时间/重放**之前**：拿错接口的签名应该先被「事件不对」挡下，
//   而不是顺手消耗掉一个 nonce —— 那会让客户端一次正常的重试变成一次「重复」。

'use strict';

const { statusCode, isReceipt, resolvePath, selfOnlyRules } = require('./contract');
const {
  rememberReject,
  rejectKeyFor,
  assertPublicKey,
  verifyPairingCode,
} = require('./devicestore');
const {
  canonicalBytes,
  verifyIdentity,
  verifySignature,
  checkFresh,
  intakeGrantFor,
} = require('./verify');
const { levelRank } = require('./capabilities');
const {
  alphabetFromContract,
  credentialDigest,
  isValidAddressCode,
  isValidPairingCode,
  normalize,
} = require('./credentials');

/// 身份证明之后的拒绝：状态码照实给，`reason` 只进留痕、绝不进响应体。
function deniedWith(contract, state, input, status, reason) {
  const rejects = state.rejects || (state.rejects = {});
  rememberReject(
    rejects,
    rejectKeyFor(contract, input.senderAddress),
    input.now,
    'event:' + reason,
  );
  return { ok: false, status, reason };
}

function denied(contract, state, input, reason) {
  return deniedWith(contract, state, input, statusCode(contract, 'forbidden'), reason);
}

/// ack / pairArm / pair 都把载荷放进**被签的** `body`（canonicalOrder 只有那六个字段，
/// 不为某一种事件加一位 —— 加一位等于换协议）。键集必须与契约声明的那份逐字相同：
/// 少一个键读不到，多一个键就是对方往签名载荷里塞料的口子。
/// 返回 `{reason}` 或 `{payload}`，不自己造拒绝对象 —— 三处的状态码不同，
/// 在这里合成一个"通用拒绝"就等于把那个差异抹掉（而差异正是路由选状态码的依据）。
function readPayload(spec, body, kind) {
  const malformed = `malformed-${kind}`;
  let payload;
  try {
    payload = JSON.parse(String(body));
  } catch (e) {
    return { reason: malformed };
  }
  if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) {
    return { reason: malformed };
  }
  const want = (spec.fields || []).slice().sort().join('|');
  const got = Object.keys(payload).sort().join('|');
  if (got !== want) return { reason: `${kind}-fields:期望 [${want}] 实到 [${got}]` };
  return { payload };
}

/// 「这一步能作用于谁」——按契约 `clientEvents.selfOnlyRules` 的名单分派。
/// authorizeClientEvent 与 authorizeRegister **共用这一个函数**：后者原先自己写了一遍
/// `spec.targetMustEqualSender === true`，那就是第二份判据，契约加第三条规则时它不报错，
/// 只会让 register 永远判不到新规则（与第一片修掉的「判据里硬写 poll/ack」同一类瞎）。
/// 返回 null 表示放行；否则返回一个只进 state.rejects 的 reason（对外形状由路由按状态码决定）。
function selfOnlyReason(contract, spec, sender, fields) {
  const declared = selfOnlyRules(contract).filter((rule) => spec[rule] === true);
  // 「恰好一条」：0 条 = 这种事件能作用于任何人；2 条 = 按 OR 判时比一条**更宽**，不是更严。
  // 这里必须抛，而不是挑一条"看起来合适"的：契约被改成这样时，选一条就是替契约选了一次权限。
  if (declared.length !== 1) {
    throw new Error(
      `事件必须声明 clientEvents.selfOnlyRules 里恰好一条为 true，` +
        `可取 [${selfOnlyRules(contract).join(' / ')}]，实为 [${declared.join(' / ')}]`,
    );
  }
  // 比较前先归一化：签名覆盖的是客户端写下的原始串，而大小写与连字符不是两种权限。
  // normalize 只做转大写与去空格/连字符（不删字母表外的字符，那种输入直接得 null），
  // 所以归一化后的相等关系与原串一致。
  const target = normalize(
    alphabetFromContract(contract),
    String(fields.target === undefined ? '' : fields.target),
  );
  switch (declared[0]) {
    case 'targetMustEqualSender':
    // ack 那一条有两半：这一半（target 必须是本机）在这里判，另一半（那条消息确实下发给我）
    // 要拿消息表来查，在路由判。两种规则在这里的判法相同，但**契约上必须各写各的**：
    // 把 ack 写成 targetMustEqualSender，读代码的人就看不到"还要查归属"那半条。
    case 'onlyForOwnMessages':
      return target === sender ? null : 'target-not-self';
    case 'mustContainCounterpartAddress':
      // 唯一一个「关于别人」的合法形状：对方得是个合法地址码，而且**不能是自己**。
      // 后一半不是洁癖：允许 target 等于自己，一台设备就能自己跟自己配对，把登记时那一档
      // 默认级别往上调，而全程没有落在任何人的屏幕上 —— 那正是配对红线要防的形状。
      if (target === null || !isValidAddressCode(contract, target)) {
        return 'counterpart-address-code';
      }
      return target === sender ? 'counterpart-is-self' : null;
    default:
      // 名单里出现本文件不认识的规则名：**必须抛**。咽成"当成关于本机"或直接放行，
      // 都是替契约猜意思，而这里猜错的代价是权限。
      throw new Error(
        `events.js 没有实现作用范围规则「${declared[0]}」（契约声明了它，代码判不了它）`,
      );
  }
}

/// 顶层禁带字段（register / pairArm / pair 共用）：带私钥来的包，
/// 连"是谁"都不必回答就该被丢掉 —— 所以它排在身份与形状之前。
function bannedTopLevel(spec, input) {
  return (spec.mayNotCarry || []).filter((f) => Object.prototype.hasOwnProperty.call(input, f));
}

/**
 * 一次设备事件的裁决。`kind` 只认契约 clientEvents 里声明过的那几种。
 *
 * 返回：
 *  - 失败 `{ok:false, status, reason}`（reason 仅内部留痕，对外形状由路由按 status 决定）
 *  - poll   `{ok:true, kind:'poll', sender, serverTime}`
 *  - ack    `{ok:true, kind:'ack', sender, messageId, result}`
 *  - probe  `{ok:true, kind:'probe', sender, peer, ready}`（T106：非浸入探针，只查关系不投递；
 *           `ready` 由 `verify.intakeGrantFor` 算出，与真发那一条同一处判定）
 *
 * ⚠ 这里**不查消息表**：ack 那句「只能 ack 下发给自己的那一条」要有 messageId 的归属才判得了，
 * 那是路由侧拿着表来做的事；本文件只判事件自身的形状与签名。契约那一条的前半段
 * （target 必须是本机）在这里判，后半段在路由判 —— 注释写清，免得后来人以为这里已经判全了。
 */
function authorizeClientEvent(contract, state, input, kind) {
  const spec = (contract.clientEvents || {})[kind];
  if (!spec) {
    throw new Error(`契约没有 clientEvents.${kind} 段（不补默认值：补了等于在代码里发明一种事件）`);
  }

  const id = verifyIdentity(contract, state, input);
  if (id.outcome) return id.outcome;
  const fields = input.fields || {};

  if (String(fields.type) !== spec.messageType) {
    return denied(contract, state, input, 'wrong-event-type:' + String(fields.type));
  }
  // 「只能关于自己」的三种写法在这里统一分派（见 selfOnlyReason 那段）。
  const blocked = selfOnlyReason(contract, spec, id.sender, fields);
  if (blocked) return denied(contract, state, input, blocked);

  const fresh = checkFresh(contract, state, input, id.sender);
  if (fresh.outcome) return fresh.outcome;

  if (kind === 'poll') {
    return { ok: true, kind: 'poll', sender: id.sender, serverTime: input.now };
  }
  if (kind === 'ack') {
    if (spec.resultMustBeReceipt !== true) {
      throw new Error(
        '契约 clientEvents.ack.resultMustBeReceipt 必须为 true，否则 result 是个自由字符串',
      );
    }
    let payload;
    const read = readPayload(spec, fields.body, 'ack');
    if (read.reason) return denied(contract, state, input, read.reason);
    payload = read.payload;
    if (!isReceipt(contract, payload.result)) {
      return denied(contract, state, input, 'unknown-result:' + String(payload.result));
    }
    return {
      ok: true,
      kind: 'ack',
      sender: id.sender,
      messageId: String(payload.messageId),
      result: String(payload.result),
    };
  }
  if (kind === 'probe') {
    // 探针答的是"这条链在服务端立不立得住"。链的档位随消息类型走，所以查哪个类型必须由契约说
    //（写在实现里就是第二份真值：改契约那一行不报错，只会让探针验着另一种类型的档位）。
    const checkedType = typeof spec.checksType === 'string' ? spec.checksType : '';
    if (checkedType === '') {
      throw new Error(
        '契约 clientEvents.probe 缺 checksType：不声明就只能在实现里挑一个消息类型来判档位',
      );
    }
    const read = readPayload(spec, fields.body, 'probe');
    if (read.reason) return denied(contract, state, input, read.reason);
    const peer = normalize(
      alphabetFromContract(contract),
      String(read.payload.peer === undefined ? '' : read.payload.peer),
    );
    if (peer === null || !isValidAddressCode(contract, peer)) {
      return denied(contract, state, input, 'peer-address-code');
    }
    // ⚠ 判定复用收单那一处（verify.intakeGrantFor）：这里**不许**自己再写一遍关系判定 ——
    //   探针的全部价值就是"它说的与真发那条一致"，两处各判一次就是绿徽标配一条发不出去的通知。
    // item 传空串：这一族今天只有通知这一种活，而通知不带逐条清单（L1 不看 item）。
    const cap = intakeGrantFor(contract, state, peer, id.sender, {
      type: checkedType,
      item: '',
    });
    return { ok: true, kind: 'probe', sender: id.sender, peer, ready: !!(cap && cap.allowed) };
  }
  // 契约加了新的事件种类而这里没实现：**必须抛**，不能 fall through 到"当成 poll 放行"。
  // 需要专用入口的那几种（自带公钥 / 要查表）在各自的文件级函数里判，不在这里。
  throw new Error(
    `events.js 没有实现事件类型 "${kind}"（契约声明了它，代码没判它；` +
      '自带公钥或要查表的种类走 authorizeRegister / authorizePairArm / authorizePair）',
  );
}

/**
 * 设备自登记（契约 `clientEvents.register`）：唯一一类"表里还没有他"的事件。
 *
 * 与 poll/ack 唯一的区别是**用哪把钥匙验签**，而这件事由契约的 `verifyAgainst` 说，
 * 不由这里写死（写死的下一种事件类型会默认落到"查表"那条分支上，然后静默拒绝所有新设备）。
 * 用请求自带的公钥验，证明的是「提交者持有这把私钥」，不是「他是白名单里的谁」——
 * 此刻还没有任何名单。地址码由设备自己生成（`identity.generator=csprng`，不从公钥推导），
 * 所以这里不校验两者的绑定关系；真正的绑定发生在第二次同码登记时：
 * `devicestore.registerDevice` 遇到"同一地址码换公钥"必须抛，而不是覆盖。
 */
function authorizeRegister(contract, state, input) {
  const spec = (contract.clientEvents || {}).register;
  if (!spec) {
    throw new Error('契约没有 clientEvents.register（不补默认值：补了就等于在代码里发明一种事件）');
  }
  // 契约说这把钥匙从哪来，这里就照它做；对不上直接抛，而不是「照旧走一遍」——
  // 静默按另一条路验，等于契约那行变成了注释，而这一步的强度完全取决于用哪把钥匙。
  if (spec.verifyAgainst !== 'presented-public-key') {
    throw new Error(
      `clientEvents.register.verifyAgainst = ${spec.verifyAgainst}：自登记时表里还没有这个设备，` +
        '只能按请求自带的公钥验（私钥持有证明）。要改成查表验，先想清新设备怎么进来。',
    );
  }
  const fields = input.fields || {};
  const forbidden = (reason) => {
    const rejects = state.rejects || (state.rejects = {});
    rememberReject(
      rejects,
      rejectKeyFor(contract, input.senderAddress),
      input.now,
      `register:${reason}`,
    );
    return { ok: false, status: statusCode(contract, 'forbidden'), reason };
  };

  // 禁带字段先判：带私钥来的包，连"是谁"都不必回答就该被丢掉。
  const banned = bannedTopLevel(spec, input);
  if (banned.length) return forbidden(`carries-secret:${banned.join(',')}`);

  const sender = normalize(alphabetFromContract(contract), input.senderAddress || '');
  if (sender === null) return forbidden('address-code');
  if (String(fields.type) !== spec.messageType) {
    return forbidden(`wrong-event-type:${String(fields.type)}`);
  }
  // 与 poll/ack 走同一个分派函数：这里原先自己写了一遍 targetMustEqualSender，
  // 那是第二份判据（契约加第三条规则时它不报错，只是永远判不到）。
  const notSelf = selfOnlyReason(contract, spec, sender, fields);
  if (notSelf) return forbidden(notSelf);
  const publicKey = typeof input.publicKey === 'string' ? input.publicKey : '';
  let canonical;
  try {
    canonical = canonicalBytes(contract, fields);
    assertPublicKey(publicKey);
    if (!verifySignature(contract, publicKey, canonical, input.signature)) {
      return forbidden('signature');
    }
  } catch (e) {
    // 公钥形状不对与签名不对同形：都不该被分辨（分辨 = 一台服务器在替人枚举"哪种钥匙存在"）
    return forbidden('key-or-signature');
  }

  const fresh = checkFresh(contract, state, input, sender);
  if (fresh.outcome) return fresh.outcome;

  const name = typeof input.name === 'string' ? input.name.slice(0, 60) : '';
  return { ok: true, kind: 'register', addressCode: sender, publicKey, name };
}

/**
 * A 挂出口令（契约 `clientEvents.pairArm`）：把 A 自己刚生成的那枚一次性配对口令交给服务端，
 * 服务端只存它的摘要。`devicestore.armPairingCode` 从 T27 起就在等这个调用方。
 *
 * 这一步的签名者**已经在设备表里**（A 必须先 /register），所以钥匙从表里取，
 * 与 register 那一步正好相反；口令在这里不证明身份，它证明的是"屏幕上那串是我挂的"
 * —— 而它被放在**被签的** body 里，就是为了中间人换不了它。
 */
function authorizePairArm(contract, state, input) {
  const spec = (contract.clientEvents || {}).pairArm;
  if (!spec) {
    throw new Error('契约没有 clientEvents.pairArm（不补默认值：补了等于在代码里发明一种事件）');
  }
  const banned = bannedTopLevel(spec, input);
  const id = verifyIdentity(contract, state, input);
  if (id.outcome) return id.outcome;
  const fields = input.fields || {};
  const fail = (reason) => denied(contract, state, input, reason);
  // 带秘密来的包连"是谁"都不必回答：与 authorizeRegister 同一条顺序纪律。
  if (banned.length) return fail(`carries-secret:${banned.join(',')}`);
  if (String(fields.type) !== spec.messageType) {
    return fail('wrong-event-type:' + String(fields.type));
  }
  const blocked = selfOnlyReason(contract, spec, id.sender, fields);
  if (blocked) return fail(blocked);

  const read = readPayload(spec, fields.body, 'pairArm');
  if (read.reason) return fail(read.reason);
  const pairingCode = String(
    read.payload.pairingCode === undefined ? '' : read.payload.pairingCode,
  );
  // 形状不对**不**在这里单独分辨：口令是一枚秘密，"这枚口令形状不对"与"口令不对"
  // 在网络上是同一句话（pairing.failureMessageShape），本层连 reason 都只进留痕。
  if (!isValidPairingCode(contract, pairingCode)) return fail('pairing-code');

  const fresh = checkFresh(contract, state, input, id.sender);
  if (fresh.outcome) return fresh.outcome;
  return { ok: true, kind: 'pairArm', addressCode: id.sender, pairingCode };
}

/**
 * B 带着 A 的口令来配对（契约 `clientEvents.pair`）：全协议唯一一个「关于别人」的签名。
 *
 * 顺序与 poll/ack 一致（身份 → 种类 → 作用范围 → 形状 → 档位 → 时间/重放），
 * ⚠ 而**消耗口令排在最后**：把它放到时间/重放之前，一次重放就会白烧掉一枚还有效的口令，
 * 而 A 屏幕上那张二维码还没被人扫就用不了了 —— 那副样子与"配对失败"完全一样，查不出来。
 *
 * 成功之后这里**什么都不授权**：授权只能由 A 自己的确认签名带进来（第三片）。
 * 本函数只回答"这一趟握手成不成立"，把成不成立交给路由去落一条待确认请求。
 */
function authorizePair(contract, state, input) {
  const spec = (contract.clientEvents || {}).pair;
  if (!spec) {
    throw new Error('契约没有 clientEvents.pair（不补默认值：补了等于在代码里发明一种事件）');
  }
  const banned = bannedTopLevel(spec, input);
  const id = verifyIdentity(contract, state, input);
  if (id.outcome) return id.outcome;
  const fields = input.fields || {};
  const fail = (reason) => denied(contract, state, input, reason);
  if (banned.length) return fail(`carries-secret:${banned.join(',')}`);
  if (String(fields.type) !== spec.messageType) {
    return fail('wrong-event-type:' + String(fields.type));
  }
  // counterpart 那条规则（target 必须是**别人**的合法地址码）由同一个分派函数判 ——
  // 这一种事件的存在就是那条规则被加进契约的理由，这里不另写一遍。
  const blocked = selfOnlyReason(contract, spec, id.sender, fields);
  if (blocked) return fail(blocked);
  const target = normalize(alphabetFromContract(contract), String(fields.target));

  const read = readPayload(spec, fields.body, 'pair');
  if (read.reason) return fail(read.reason);
  const pairingCode = String(
    read.payload.pairingCode === undefined ? '' : read.payload.pairingCode,
  );
  const level = String(read.payload.level === undefined ? '' : read.payload.level);
  const levels = (contract.capabilities || {}).levels || [];
  if (!levels.includes(level)) return fail(`level:${level}`);
  // 免本地确认的档位上限从契约引用（pairing.maxRequestableLevelFromPairing）：
  // 在这里再写一个 'L2'，改契约那一处时这行不会报错，而它错的一侧正是"L3 免确认"那道门。
  const ceiling = resolvePath(contract, spec.levelCeilingFrom);
  if (!levels.includes(ceiling)) {
    throw new Error(
      `clientEvents.pair.levelCeilingFrom=${JSON.stringify(spec.levelCeilingFrom)} ` +
        `取到的「${ceiling}」不是 capabilities.levels 里的一档`,
    );
  }
  if (levelRank(levels, level) > levelRank(levels, ceiling)) {
    return fail(`level-too-high:${level}>${ceiling}`);
  }
  if (!isValidPairingCode(contract, pairingCode)) return fail('pairing-code');

  const fresh = checkFresh(contract, state, input, id.sender);
  if (fresh.outcome) return fresh.outcome;

  // 消耗口令排在全部判据之后（见上面那段 ⚠）。四种失败（没这台设备 / 没挂口令 /
  // 口令错 / 已过期或已消耗）在 devicestore 里塌成同一个形状，这里原样传出去：
  // 地址码是可分享的公开标识，能分辨就是把它变成枚举器。
  const code = verifyPairingCode(contract, state.devices, target, pairingCode, input.now);
  if (!code.ok) {
    return { ok: false, status: code.status, reason: 'pairing-code-unverified' };
  }
  return {
    ok: true,
    kind: 'pair',
    target,
    requester: id.sender,
    requesterPublicKey: id.device.publicKey,
    level,
    // 落盘的是摘要：那 20 位被抄过、印在二维码里、可能被拍过照，而这张表会跟着备份走。
    codeDigest: credentialDigest(contract, 'pairingCode', pairingCode),
  };
}

/**
 * A 处理一条关于自己的配对请求（契约 `clientEvents.pairConfirm`）—— 整条链上唯一一次
 * "A 亲手把 B 写进自己的白名单"，也因此是全协议第二类「关于别人」的签名。
 *
 * 与 pair 一样走 counterpart 那条作用范围规则：target 必须是**别人**的合法地址码。
 * 少这一半（允许等于自己）就等于 A 可以自己确认自己给到自己，而那是唯一一条能写授权的入口。
 *
 * ⚠ 这里只判事件本身；**请求归属与"只能处理一次"要拿着两张表才能判**（pairstore.decideRequest），
 * 与 ack 的"只能 ack 下发给自己的那一条"是同一类分工，别以为这里已经判全了。
 */
function authorizePairConfirm(contract, state, input) {
  const spec = (contract.clientEvents || {}).pairConfirm;
  if (!spec) {
    throw new Error(
      '契约没有 clientEvents.pairConfirm（不补默认值：补了等于在代码里发明一种事件）',
    );
  }
  const banned = bannedTopLevel(spec, input);
  const id = verifyIdentity(contract, state, input);
  if (id.outcome) return id.outcome;
  const fields = input.fields || {};
  const fail = (reason) => denied(contract, state, input, reason);
  if (banned.length) return fail(`carries-secret:${banned.join(',')}`);
  if (String(fields.type) !== spec.messageType) {
    return fail('wrong-event-type:' + String(fields.type));
  }
  const blocked = selfOnlyReason(contract, spec, id.sender, fields);
  if (blocked) return fail(blocked);

  const read = readPayload(spec, fields.body, 'pairConfirm');
  if (read.reason) return fail(read.reason);
  const requestId = String(read.payload.requestId === undefined ? '' : read.payload.requestId);
  const decision = String(read.payload.decision === undefined ? '' : read.payload.decision);
  const level = String(read.payload.level === undefined ? '' : read.payload.level);
  const decisions = spec.decisions || [];
  if (!decisions.includes(decision)) {
    return fail(`unknown-decision:${decision}`);
  }
  const levels = (contract.capabilities || {}).levels || [];
  if (!levels.includes(level)) return fail(`level:${level}`);
  const ceiling = resolvePath(contract, spec.levelCeilingFrom);
  if (!levels.includes(ceiling)) {
    throw new Error(
      `clientEvents.pairConfirm.levelCeilingFrom=${JSON.stringify(spec.levelCeilingFrom)} ` +
        `取到的「${ceiling}」不是 capabilities.levels 里的一档`,
    );
  }
  // 确认时能给的上限与请求时是同一道闸：服务端看不见锁屏与生物认证，所以 L3 不许从这里进来
  //（与 T30 那次同一条红线：不许拿"请求里自称已确认"当本地认证）。
  if (levelRank(levels, level) > levelRank(levels, ceiling)) {
    return fail(`level-too-high:${level}>${ceiling}`);
  }

  const fresh = checkFresh(contract, state, input, id.sender);
  if (fresh.outcome) return fresh.outcome;
  return {
    ok: true,
    kind: 'pairConfirm',
    // A 是自己（请求的收件人）；B 是签名里那个"别人"的地址码（请求的发起人）。
    target: id.sender,
    requester: normalize(alphabetFromContract(contract), String(fields.target)),
    requestId,
    decision,
    level,
  };
}

/**
 * A 亲手把 B 从自己的白名单里划掉（契约 `clientEvents.pairRevoke`）—— 与 pairConfirm 对称的那一发：
 * 那边第一次往 `grantsBy` 里写，这一发第一次删。
 *
 * 四条判据各有一个"写反了会怎样"：
 *  ① `target` 是**对端**（`selfOnlyReason` 那一支已判过：必须是合法地址码且不许等于自己）。
 *     写成本机地址就是替别人撤销他自己的授权，而换来的拒信与"口令错"同形，看不出是这一步错了；
 *  ② 载荷里的 `peerAddress` **必须等于签名里的 `target`**。同一件事有两个来源时，"哪个算数"
 *     必须有一句明话：算数的是签名，载荷那一份只是客户端自证（不一致 = 客户端有 bug 或路上被人动过）；
 *  ③ 撤销只停投递、**不删历史**（与 `revocation.dataNeverDeletedByRevoke` 同一条），所以这里
 *     不碰 messagestore、也不动设备记录 —— 那些各有各的入口；
 *  ④ 撤销是**幂等**的：目标状态是「B 不在 A 的名单里」，本来就不在 ⇒ 目标已达成，走同一条成功路径
 *     并回 `revoked:false`。回 403/404 的表现很具体：客户端把「服务器那边本来没有」当成一次失败，
 *     于是本机那一行留着不删 —— 两边各说一段。⚠ 这里**不需要**防试探：查询主键永远是签名者自己的
 *     `grantsBy`，A 问得出的只有 A 自己的关系（与 pairConfirm 那「三种走法同一句话」不同，
 *     那边要防的是替你答复了你收到的请求）。
 */
function authorizePairRevoke(contract, state, input) {
  const spec = (contract.clientEvents || {}).pairRevoke;
  if (!spec) {
    throw new Error('契约没有 clientEvents.pairRevoke（不补默认值：补了等于在代码里发明一种事件）');
  }
  const banned = bannedTopLevel(spec, input);
  const id = verifyIdentity(contract, state, input);
  if (id.outcome) return id.outcome;
  const fields = input.fields || {};
  const fail = (reason) => denied(contract, state, input, reason);
  // 带秘密来的包连"是谁"都不必回答：与 register / pairArm 同一条顺序纪律。
  if (banned.length) return fail(`carries-secret:${banned.join(',')}`);
  if (String(fields.type) !== spec.messageType) {
    return fail('wrong-event-type:' + String(fields.type));
  }
  const blocked = selfOnlyReason(contract, spec, id.sender, fields);
  if (blocked) return fail(blocked);

  const read = readPayload(spec, fields.body, 'pairRevoke');
  if (read.reason) return fail(read.reason);
  const alphabet = alphabetFromContract(contract);
  const target = normalize(alphabet, String(fields.target === undefined ? '' : fields.target));
  const peer = normalize(
    alphabet,
    String(read.payload.peerAddress === undefined ? '' : read.payload.peerAddress),
  );
  if (peer === null || peer !== target) return fail('peer-target-mismatch');

  const fresh = checkFresh(contract, state, input, id.sender);
  if (fresh.outcome) return fresh.outcome;
  return { ok: true, kind: 'pairRevoke', addressCode: id.sender, peerCode: target };
}

/**
 * 接收端给自己建一个接入端点（契约 `clientEvents.endpointCreate`，T42 那一格的服务端那一半）。
 *
 * 判序与 pairArm 同一条（禁带字段 → 验身份 → 事件种类 → self-only → 载荷键名 → 时间/重放），
 * 三条这一发特有的口径写在这里而不是路由里：
 *  ① **self-only**（`targetMustEqualSender`）：建的是自己的端点。放开这条，任何登记过的设备
 *    都能替别人建一个入口，而且**拿到那条入口的明文口令** —— 拿着它就可以冒充那台设备。
 *    这一发与 pairConfirm/pairRevoke 相反，走的是 selfOnlyRules 的第一条而不是第三条。
 *  ② **口令不许设备自带**：载荷键名单里就没有 `secret`（只有 `name`）。自带等于把"选一把
 *    多强的口令"交给最不方便负责它的一端 —— 有人抄一把复用过的口令进来，泄露的是这台实例，
 *    而服务端只会照单收下。口令一律由 `devicestore.createEndpoint` 生成、只落摘要。
 *  ③ 这里**看不到任何口令**，所以留痕里也不可能带出它：`name` 是唯一进内部的东西，
 *    而它是用户自己起的外号（管理面那列本来就给人看的）。
 *
 * 这一发被砸过什么（报告在本地 `outputs/_endpnt.report.txt`，按约定不入库；W1–W6 全 named+restored）：
 *  - **W1** 契约把 `targetMustEqualSender` 关掉 ⇒ 红在「替别人建 ⇒ 拒」（连带 6 条一起红：
 *    self-only 一关，签名者自己的地址码也不再被认，正常的建入口全被拒）；
 *  - **W4** 摘掉载荷键名单（`readPayload` 换成一个空名单）⇒ 红在「口令不许设备自带」与
 *    「owner 只能从签名来」—— 那两条判据其实是同一道闸的两个键；
 *  - **W6** 路由那道 `carriesForbidden` 摘掉 ⇒ 红在「顶层带 privateKey ⇒ 与'是谁都没答出来'同形」：
 *    事件层那道仍然拦，但对外那个词从 `rejected_unsigned` 变成 `rejected_capability`。
 *    ⚠ 这一条证的是"哪一层给出那个词"，两道闸各有一处写着，别把它们并成一条断言。
 */
function authorizeEndpointCreate(contract, state, input) {
  const spec = (contract.clientEvents || {}).endpointCreate;
  if (!spec) {
    throw new Error(
      '契约没有 clientEvents.endpointCreate（不补默认值：补了等于在代码里发明一种事件）',
    );
  }
  const banned = bannedTopLevel(spec, input);
  const id = verifyIdentity(contract, state, input);
  if (id.outcome) return id.outcome;
  const fields = input.fields || {};
  const fail = (reason) => denied(contract, state, input, reason);
  if (banned.length) return fail(`carries-secret:${banned.join(',')}`);
  if (String(fields.type) !== spec.messageType) {
    return fail('wrong-event-type:' + String(fields.type));
  }
  const blocked = selfOnlyReason(contract, spec, id.sender, fields);
  if (blocked) return fail(blocked);

  const read = readPayload(spec, fields.body, 'endpointCreate');
  if (read.reason) return fail(read.reason);
  const name = String(read.payload.name === undefined ? '' : read.payload.name);

  const fresh = checkFresh(contract, state, input, id.sender);
  if (fresh.outcome) return fresh.outcome;
  return { ok: true, kind: 'endpointCreate', addressCode: id.sender, name };
}

/**
 * 接收端看自己有哪些接入端点（契约 `clientEvents.endpointList`，T42「我的端点」那一格的读口）。
 *
 * 它是这一发族里最窄的一条：不改变任何东西、载荷为空（`fields: []` ⇒ 带键就拒）、
 * 结果按**签名者**过滤。三条各有一个"写反了会怎样"：
 *  ① self-only：`target` 必须是本机。写成别人的地址码 + 不过滤，就是"替别人列他的入口"；
 *  ② 载荷为空这件事由键名单判，而不是"看一眼 body 是不是空串"：以后有人给这一发加一个
 *    可选参数（最典型的是"连调用日志一起给"），那就是一条新读口悄悄上线，而契约没说；
 *  ③ 这里**不投影也不裁剪**字段 —— 投影只有一个出处（`devicestore.endpointSummary`）。
 *    本函数若顺手 `pick` 一遍，就有了第二份"哪些字段可以端出去"的名单，而两份名单的差别
 *    永远出现在最糟的那一侧：加了列的那份在存储层，忘了改的那份在出口。
 * 反证：Y6 摘掉载荷键名单 ⇒ 红在「这一发的载荷必须为空」；Y7 契约里把
 * `targetMustEqualSender` 关掉 ⇒ 红 6 条（可达集合整个变了，这一发从此能替别人列入口）。
 */
function authorizeEndpointList(contract, state, input) {
  const spec = (contract.clientEvents || {}).endpointList;
  if (!spec) {
    throw new Error(
      '契约没有 clientEvents.endpointList（不补默认值：补了等于在代码里发明一种事件）',
    );
  }
  const banned = bannedTopLevel(spec, input);
  const id = verifyIdentity(contract, state, input);
  if (id.outcome) return id.outcome;
  const fields = input.fields || {};
  const fail = (reason) => denied(contract, state, input, reason);
  if (banned.length) return fail(`carries-secret:${banned.join(',')}`);
  if (String(fields.type) !== spec.messageType) {
    return fail('wrong-event-type:' + String(fields.type));
  }
  const blocked = selfOnlyReason(contract, spec, id.sender, fields);
  if (blocked) return fail(blocked);

  const read = readPayload(spec, fields.body, 'endpointList');
  if (read.reason) return fail(read.reason);

  const fresh = checkFresh(contract, state, input, id.sender);
  if (fresh.outcome) return fresh.outcome;
  return { ok: true, kind: 'endpointList', addressCode: id.sender };
}

/**
 * 接收端关掉自己名下一条接入端点（契约 `clientEvents.endpointRevoke`）。
 *
 * 判序与这一族其余几条同一条（禁带字段 → 验身份 → 事件种类 → self-only → 载荷键名 → 时间/重放），
 * 两条是这一发特有的：
 *  ① **它改变的是"别人还能不能往这台设备推"** —— 所以 self-only 只完成一半：`target` 是签名者自己，
 *    而真正被关的那一把由载荷里的 `endpointId` 指名。**owner 那道核查不在这里，也不该在这里**：
 *    裁决层看不到端点表（`state` 是设备台账与 nonce 台账），把它伸进来就会有第二份"谁拥有什么"的账。
 *    核查在路由那一处，紧跟在读表之后 —— 见 `routes.js` 的 `/endpoint-revoke`。
 *  ② 载荷只有一个键、且**不许带口令**：`secret` / `endpointSecret` 都在 `mayNotCarry` 上。
 *    带口令来"证明你有这把入口"是最想当然的一种写法，而这一发要证明的是**你签过名**，
 *    顺便把要关的那一把的 id 说出来 —— id 不是秘密，口令才是。
 *
 * 「不存在」与「不是你的」必须在**出口同形**（同一句 403、同一个 receipt）。这一条判据今天
 * 在本函数里看不到，所以它的反证落在路由那一边（`outputs/_eprv.report.txt`，RV1/RV2 点名那条用例）。
 * 本函数自己的三道，各有一条砸上去（同一份报告，全部 named+restored）：
 *  - **RV5** 契约给 `fields` 加第二个键（`secret`）⇒ 红在「载荷名单只认 endpointId：多带一个键就拒」。
 *    ⚠ 这一刀是从**契约**那侧落的：实现里改 `readPayload` 的调用参数不会红（它照着 spec 判），
 *    所以能砸动的只有 spec 本身 —— 这正是"名单在契约、判据在实现"这套分工的代价与收益。
 *  - **RV6** 契约关掉 `targetMustEqualSender` ⇒ 红 8 条（含「target 写成别人 ⇒ 拒」；可达集合整个变了，
 *    所以连带红了一片，按 loose 记）。
 *  - **RV7** 契约清空 `mayNotCarry` ⇒ 红在「顶层带 privateKey ⇒ 与"是谁都没答出来"同形」。
 */
function authorizeEndpointRevoke(contract, state, input) {
  const spec = (contract.clientEvents || {}).endpointRevoke;
  if (!spec) {
    throw new Error(
      '契约没有 clientEvents.endpointRevoke（不补默认值：补了等于在代码里发明一种事件）',
    );
  }
  const banned = bannedTopLevel(spec, input);
  const id = verifyIdentity(contract, state, input);
  if (id.outcome) return id.outcome;
  const fields = input.fields || {};
  const fail = (reason) => denied(contract, state, input, reason);
  if (banned.length) return fail(`carries-secret:${banned.join(',')}`);
  if (String(fields.type) !== spec.messageType) {
    return fail('wrong-event-type:' + String(fields.type));
  }
  const blocked = selfOnlyReason(contract, spec, id.sender, fields);
  if (blocked) return fail(blocked);

  const read = readPayload(spec, fields.body, 'endpointRevoke');
  if (read.reason) return fail(read.reason);
  const endpointId = String(read.payload.endpointId === undefined ? '' : read.payload.endpointId);
  if (!endpointId) return fail('endpoint-id-missing');

  const fresh = checkFresh(contract, state, input, id.sender);
  if (fresh.outcome) return fresh.outcome;
  return { ok: true, kind: 'endpointRevoke', addressCode: id.sender, endpointId };
}

/**
 * 接收端换一把入口的长期口令（契约 `clientEvents.endpointRotate`）。
 *
 * 判序与本族其余几条同一条（禁带字段 → 验身份 → 事件种类 → self-only → 载荷键名 → 时间/重放），
 * 载荷形状也与吊销**逐字相同**（只有 `endpointId`）—— 这是刻意的：两件事都是"动我自己名下
 * 那一条入口"，多一个可选参数（比如"旧的那把立刻失效"）就会把宽限期这个安全属性变成
 * 客户端可以随口关掉的东西。所以：
 *  ① 宽限期不由这一发决定，只由契约 `endpoint.rotation.graceSeconds` 决定；
 *  ② 旧口令还能用到什么时候，由**响应**里的 `rotatingUntil` 说（裁决层不看端点表，判不了）；
 *  ③ owner 那道核查同 revoke 一样在路由里，这里不伸手动表。
 * 唯一比 revoke 多出来的红线：这一发的响应里**带一把新的明文口令**，而它是协议里唯一一处
 * "换了之后还要再给一次明文"。所以留痕里不许出现它（`denied()` 只记 reason，不记响应），
 * 而 `mayNotCarry` 仍然禁着 `endpointSecret` —— 设备可以把**新**口令从响应里读走，
 * 不可以把任何口令**送进来**。
 * 反证（同一份报告 `outputs/_erot.report.txt`）：**RB6** 契约给 `fields` 加第二个键
 * （`graceSeconds`）⇒ 红在「宽限期不许由客户端改」；**RB7** 契约关掉 `targetMustEqualSender`
 * ⇒ 红 7 条（loose）；**RB8** 契约不声明这条路径 ⇒ 红在装配守卫「声明 == 挂载」。
 * 三刀都从**契约**那侧落：本函数只照着 spec 判，实现里没有可砸的字面量 —— 这正是
 * "名单在契约、判据在实现"这套分工的代价与收益。
 */
function authorizeEndpointRotate(contract, state, input) {
  const spec = (contract.clientEvents || {}).endpointRotate;
  if (!spec) {
    throw new Error(
      '契约没有 clientEvents.endpointRotate（不补默认值：补了等于在代码里发明一种事件）',
    );
  }
  const banned = bannedTopLevel(spec, input);
  const id = verifyIdentity(contract, state, input);
  if (id.outcome) return id.outcome;
  const fields = input.fields || {};
  const fail = (reason) => denied(contract, state, input, reason);
  if (banned.length) return fail(`carries-secret:${banned.join(',')}`);
  if (String(fields.type) !== spec.messageType) {
    return fail('wrong-event-type:' + String(fields.type));
  }
  const blocked = selfOnlyReason(contract, spec, id.sender, fields);
  if (blocked) return fail(blocked);

  const read = readPayload(spec, fields.body, 'endpointRotate');
  if (read.reason) return fail(read.reason);
  const endpointId = String(read.payload.endpointId === undefined ? '' : read.payload.endpointId);
  if (!endpointId) return fail('endpoint-id-missing');

  const fresh = checkFresh(contract, state, input, id.sender);
  if (fresh.outcome) return fresh.outcome;
  return { ok: true, kind: 'endpointRotate', addressCode: id.sender, endpointId };
}

module.exports = {
  authorizeClientEvent,
  authorizeRegister,
  authorizePairArm,
  authorizePair,
  authorizePairConfirm,
  authorizePairRevoke,
  authorizeEndpointCreate,
  authorizeEndpointList,
  authorizeEndpointRevoke,
  authorizeEndpointRotate,
};
