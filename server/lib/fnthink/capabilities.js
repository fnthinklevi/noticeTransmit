// 能力清单（T30）服务端这一半：一条已经证明身份的消息，这台设备准不准它做。
//
// 与 Dart 的 packages/fnthink_push/lib/src/capabilities.dart 是同一套规则的两份实现，
// 两者都只从契约 `capabilities` 段读数值，且**同一份向量**（protocol/fnthink-vectors-v1.json
// 的 capabilities 组）各断言一遍。它必须一致的理由很实在：不一致时不会报错，
// 只会变成"设备自己觉得只给了 L1，服务端却按 L2 收"。

'use strict';

const { resolvePath } = require('./contract');

/// 级别序：**直接取契约 `capabilities.levels` 里的位置**（validate 保证它按权限升序）。
/// 不写 `case 'L1': return 1` 那种表：那是在服务端存第二份档位表，契约加一档时
/// 它不报错，只会让比较结果静默错位。不在词表里 ⇒ -1（任何真实档位都比它大 ⇒ 判不过）。
function levelRank(levels, level) {
  return levels.indexOf(level);
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
///   所以 intake 遇到 L3 放行时会带 `requiresApplyConfirm: true`，交给设备在 apply 那一段判。
/// - `apply`（设备落地之前）：四条全判，其中确认取自**本机**那一次用户动作。
///
/// ⚠⚠ **apply 段今天没有任何调用方**（如实登记，2026-10-05）：确认那道闸的形式
///   已改成「延时窗口内未撤销」（契约 `l3.confirmForm = cancelableDelay`，2026-10-04 定），
///   而窗口在**设备侧**走（`RemoteCommandRunner` 到点那一刻自己判）。
///   服务端**不该**再有 apply 段的调用方 —— 拿请求里那个自称的标志当确认，
///   等于让发送方替接收方点头（T30 那条红线）。这一段留着不删，是那三判的完整形状；
///   若哪天确认又回到服务端，必须重新接线并补用例。
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
    return { allowed: false, reason: `unknown-type:${input.type}`, requiresApplyConfirm: false };
  const grant = input.grant || { maxLevel: defaults.maxLevel, items: [] };
  if (levelRank(levels, need) > levelRank(levels, grant.maxLevel)) {
    return { allowed: false, reason: `level:${need}`, requiresApplyConfirm: false };
  }
  if (levelRank(levels, need) >= levelRank(levels, capabilities.itemRequiredFromLevel)) {
    const item = input.item === undefined || input.item === null ? '' : String(input.item);
    if (item === '') return { allowed: false, reason: 'missing-item', requiresApplyConfirm: false };
    if (!(grant.items || []).includes(item)) {
      return { allowed: false, reason: `item:${item}`, requiresApplyConfirm: false };
    }
  }
  const topLevel = levels.length ? levels[levels.length - 1] : '';
  const l3 = capabilities.l3 || {};
  const needsConfirm = need === topLevel && l3.confirmEveryTime === true;
  if (!needsConfirm) return { allowed: true, reason: null, requiresApplyConfirm: false };
  if (input.stage === 'intake') {
    // 收单这段判不了确认，也不许用请求里那个自称的标志替设备判 —— 交给 apply。
    return { allowed: true, reason: null, requiresApplyConfirm: true };
  }
  if (!input.confirmedThisTime) {
    return { allowed: false, reason: 'confirm-required', requiresApplyConfirm: true };
  }
  return { allowed: true, reason: null, requiresApplyConfirm: true };
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

/// 配对同意那一屏能勾的**取值域**（T134 片2）：从契约 `pairConfirm.itemsVocabularyFrom`
/// 指过去的那几张表现取，服务端不存第二份清单。
///
/// 两种形状都认，而且必须两种都认：`l2.actions` 是名单（值就是 item），`l3.settings`
/// 是键控表（**键名**才是 item，值里装的是怎么执行）。只读名单的那份写法会把 `l3.settings`
/// 读成"一张空表"，于是所有 L3 勾选一律算词表外 —— 而界面上那看起来就像"用户没勾"。
///
/// 抛而不回落成空表：`itemsVocabularyFrom` 写错路径时，空表意味着"任何勾选都不合法"，
/// 那与"这个词表还没定义"是两件事，前者会被读成用户在乱勾。
function confirmItemVocabulary(contract) {
  const spec = (contract.clientEvents || {}).pairConfirm || {};
  const paths = spec.itemsVocabularyFrom;
  if (!Array.isArray(paths) || paths.length === 0) {
    throw new Error(
      'pairConfirm.itemsVocabularyFrom 必须是非空名单：有 items 这一枚键却没有取值域，' +
        '服务端只剩"收下并忽略"这一种写法',
    );
  }
  const out = [];
  for (const path of paths) {
    const node = resolvePath(contract, path);
    const entries = Array.isArray(node)
      ? node
      : node && typeof node === 'object'
        ? Object.keys(node)
        : null;
    if (!entries || entries.length === 0) {
      throw new Error(
        `pairConfirm.itemsVocabularyFrom 指向的 ${JSON.stringify(path)} 既不是非空名单也不是非空键控表`,
      );
    }
    for (const entry of entries) {
      const value = String(entry).trim();
      if (value !== '' && out.indexOf(value) < 0) out.push(value);
    }
  }
  return out.sort();
}

/// 整串里把「动作名」与「参数」分开的那一枚字符（T134 片4，契约声明，服务端不写死斜杠）。
///
/// 与设备侧 `contract.grantItemBase / grantItemArgument` 同一把刀：**两端切出来的名字必须逐字相同**，
/// 否则 A 那边勾的是一格、B 那边查表查的是另一格，而两边的比对标的都是整串 —— 那种错位看不见。
function grantItemSeparator(contract) {
  const spec = ((contract.clientEvents || {}).pairConfirm || {}).itemGrammar || {};
  const value = spec.argumentSeparator;
  if (typeof value !== 'string' || Array.from(value).length !== 1) {
    throw new Error(
      'pairConfirm.itemGrammar.argumentSeparator 必须是单个字符（实得 ' +
        JSON.stringify(value) +
        '）：勾选项的整串靠它切，切不开就没有"哪一项"可查',
    );
  }
  return value;
}

/// 把那一枚 item 切成 `{ base, argument, hasSeparator }`。
///
/// ⚠ `hasSeparator` 与"参数是不是空串"是两件事：`listener:start/` 的参数段是空串，
///   只按空串判就成了"没带参数"⇒ 那一格被当成合法写进授权表，而线上从来发不出带尾斜杠的串。
///   设备侧 `grantItemProblem` 判的是同一件（那几条形状用例钉着），两份必须一起改。
function grantItemSplit(contract, value) {
  const separator = grantItemSeparator(contract);
  const at = value.indexOf(separator);
  return at < 0
    ? { base: value, argument: '', hasSeparator: false }
    : { base: value.slice(0, at), argument: value.slice(at + 1), hasSeparator: true };
}

/// 这一项**要不要**参数、要的是哪一种形状（读契约那两张表，服务端不存第二份）。
///
/// 两处说法不一致就抛：`requiresArgumentFrom` 说"要参数"而 `l2.reports` 没给 `argumentKind`，
/// 这一项的整串就没有作者 —— 服务端只剩"照着猜一种拼法"，而猜的方向不可控（猜宽了等于
/// 把"勾一条通道"读成"勾任意一条"）。抛出去由调用处按 400 那一档回，不静默收下。
function grantItemKind(contract, base) {
  const caps = contract.capabilities || {};
  const l2 = caps.l2 || {};
  const l3 = caps.l3 || {};
  const reports = l2.reports || {};
  const settings = l3.settings || {};
  const needsList = Array.isArray(l2.requiresArgumentFrom) ? l2.requiresArgumentFrom : [];
  // ⚠ 用 `Object.prototype.hasOwnProperty` 而不是 `in`：`settings` 是从 JSON 解析出来的对象，
  //   `in` 会把原型上的名字（`__proto__`、`toString`…）当成设置项 —— #130-A 那批治过的同一族。
  if (Object.prototype.hasOwnProperty.call(settings, base)) {
    if (needsList.includes(base)) {
      throw new Error(
        `${base} 既在 capabilities.l3.settings 里、又被列进 l2.requiresArgumentFrom：` +
          '一处说它是设置项、一处说它是动作，两端会各按一种读法拼串',
      );
    }
    const isToggle = settings[base] && settings[base].mode === 'toggle';
    return {
      // `grant` 型那几项没有"设成哪一档"这一说（它只能请用户去系统里开）。
      needsArgument: isToggle && l3.itemMayCarryTarget === true,
      kind: isToggle ? 'toggle' : null,
    };
  }
  const declared = reports[base] ? reports[base].argumentKind : undefined;
  const kind = declared === undefined || declared === null || declared === 'none' ? null : declared;
  if (kind !== null && !['count', 'keyword', 'channelTarget'].includes(kind)) {
    throw new Error(
      `l2.reports.${base}.argumentKind=${JSON.stringify(declared)} 本机读不出形状：只剩猜一种拼法`,
    );
  }
  const needs = needsList.includes(base);
  if (needs !== (kind !== null)) {
    throw new Error(
      `${base} 在两处说法不一致：requiresArgumentFrom ${needs ? '列了' : '没列'}，` +
        `l2.reports 的 argumentKind 却是 ${JSON.stringify(declared ?? null)}`,
    );
  }
  return { needsArgument: needs, kind };
}

/// 参数成不成形（四类形状各一条判据，**不许合成一条"长度对不对"**）。
/// 理由串与设备侧逐字同一批前缀（`reportArgumentProblem` / `rejectChannelTarget` /
/// `grantItemProblem`）：两端各写一份迟早漂，而漂的表现是"A 看到的拒因与 B 记下的不是一句话"。
function grantItemShapeProblem(contract, base, kind, argument) {
  const caps = contract.capabilities || {};
  const l2 = caps.l2 || {};
  const spec = (l2.reports || {})[base] || {};
  if (kind === 'count') {
    const trimmed = argument.trim();
    const count = /^-?\d+$/.test(trimmed) ? Number(trimmed) : null;
    const min = spec.minItems;
    const max = spec.maxItems;
    // 契约没声明上下界 ⇒ 一律不认（fail-closed：没有上界的那一条是一条没人核对过的路）。
    if (count === null || typeof min !== 'number' || typeof max !== 'number') {
      return `bad-report-count:${trimmed}`;
    }
    if (count < min || count > max) return `bad-report-count:${trimmed}`;
    return null;
  }
  if (kind === 'keyword') {
    const trimmed = argument.trim();
    const min = spec.minChars;
    const max = spec.maxChars;
    if (
      typeof min !== 'number' ||
      typeof max !== 'number' ||
      trimmed.length < min ||
      trimmed.length > max
    ) {
      return `bad-keyword:${trimmed}`;
    }
    // 控制字符（含 NUL 与 DEL）：一句话在对面读起来会断成两截，而 item 是整串比对的键。
    for (let i = 0; i < trimmed.length; i += 1) {
      const code = trimmed.charCodeAt(i);
      if (code < 0x20 || code === 0x7f) return `bad-keyword:${trimmed}`;
    }
    return null;
  }
  if (kind === 'channelTarget') {
    const shape = l2.channelTargetShape || {};
    const separator = shape.segmentSeparator;
    const words = Array.isArray(shape.targetWords) ? shape.targetWords : [];
    const families = Array.isArray(shape.families) ? shape.families : [];
    if (
      typeof separator !== 'string' ||
      Array.from(separator).length !== 1 ||
      families.length === 0 ||
      words.length !== 2 ||
      !(typeof shape.segments === 'number' && shape.segments >= 2)
    ) {
      // 形状声明本身残缺：**不能**"当没参数收下"，那是把一格没人核对过的串签出去。
      return `bad-channel-argument:${argument}`;
    }
    const parts = argument.split(separator);
    // ⚠ `!== segments` 而不是 `< segments`：多一段也要拒（静默取前三段的话，
    //   对面拼错一个字符就变成另一条指令）。
    if (parts.length !== shape.segments) return `bad-channel-argument:${argument}`;
    const family = parts[0];
    const id = parts[1];
    const wanted = parts[parts.length - 1];
    if (family === '' || id.trim() === '') return `bad-channel-argument:${argument}`;
    if (!families.includes(family)) return `bad-channel-argument:${argument}`;
    // 两个目标词按**位置**读（第一个 = 设成开着）：与设备侧同一约定，由 contract.validate() 钉。
    if (wanted !== words[0] && wanted !== words[1]) {
      return `bad-channel-argument:${argument}`;
    }
    return null;
  }
  if (kind === 'toggle') {
    const words = (caps.l3 || {}).itemTargetWords || [];
    if (Array.isArray(words) && words.includes(argument)) return null;
    return `unknown-target-word:${argument}`;
  }
  return `bad-argument-kind:${base}`;
}

/// 裸名字被判不过时那一句（形状从契约读：`bareNameRejected` 尾部那个 `X` 换成具体名字）。
function grantItemBareRejected(contract, base) {
  const spec = ((contract.clientEvents || {}).pairConfirm || {}).itemGrammar || {};
  const template = spec.bareNameRejected;
  if (typeof template !== 'string' || !template.endsWith(':X')) {
    throw new Error(
      'pairConfirm.itemGrammar.bareNameRejected 必须是「词:X」形状（实得 ' +
        JSON.stringify(template) +
        '）：尾部那个 X 才是实现换名字的位置',
    );
  }
  return template.replace(':X', `:${base}`);
}

/// 把答复载荷里那一枚 `items` 读成"可以写进授权表的清单"（T134 片2；形状自片4 起是整串）。
///
/// 拒的理由**不许合并**（与设备侧 `grantItemProblem` 逐字同一批前缀）：
///   items-not-array / item-not-string / item-empty / unknown-item:<名>
///   / 契约那句 item-argument-required:<名> / unexpected-argument:<名> / 各形状自己的理由
/// 返回 `{reason}` 或 `{items}`，不自己造拒绝对象（状态码由调用处按契约那枚旋钮挑）。
///
/// ⚠ **写进表里的是整串**（向量 `c-action-item-not-granted` 那条 note 说的就是"没有通配"）：
///   片4 之前勾的是**名字**，而线上发的是 `<名>/<参数>` ⇒ 那一格永远判不过，界面上却写着"已授权"。
///   现在勾的就是那一整串，两端同一形状，"勾了却用不上"从源头关掉；代价是**裸名字不再是合法勾选项**
///   （兼容范围与发版次序写在契约 `itemGrammar` 那一段里）。
function normalizeConfirmItems(contract, raw) {
  if (!Array.isArray(raw)) return { reason: 'items-not-array' };
  const vocabulary = confirmItemVocabulary(contract);
  const out = [];
  for (const entry of raw) {
    if (typeof entry !== 'string') return { reason: 'item-not-string' };
    const value = entry.trim();
    if (value === '') return { reason: 'item-empty' };
    const { base, argument, hasSeparator } = grantItemSplit(contract, value);
    if (vocabulary.indexOf(base) < 0) return { reason: `unknown-item:${base}` };
    const { needsArgument, kind } = grantItemKind(contract, base);
    if (!needsArgument) {
      if (hasSeparator) return { reason: `unexpected-argument:${base}` };
    } else {
      if (argument === '') return { reason: grantItemBareRejected(contract, base) };
      const problem = grantItemShapeProblem(contract, base, kind, argument);
      if (problem) return { reason: problem };
    }
    // 重复项**静默去重**而不是拒：一次重试、一份把同一项列了两遍的清单，落进表里都该是同一件事；
    // 拒掉它的表现是"用户点了同意而界面只回一句与口令错同形的话"。
    if (out.indexOf(value) < 0) out.push(value);
  }
  return { items: out.sort() };
}

module.exports = {
  confirmItemVocabulary,
  decideCapability,
  endpointGrant,
  grantItemBareRejected,
  grantItemKind,
  grantItemSeparator,
  grantItemShapeProblem,
  grantItemSplit,
  grantFromNode,
  // 档位比较开给配对（#131）：级别顺序的出处只能有一个（capabilities.levels 的位置）。
  // 各写一份 rank 表，改档位顺序时只会红一边 —— T30-A 就是为了删掉 pairing.dart 里那份私有表。
  levelRank,
  normalizeConfirmItems,
};
