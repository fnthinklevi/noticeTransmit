// 异常突增告警（#130-A4）：把"有人正在被拦住"说出来，而不是等运维去翻 access log。
//
// 为什么还需要这一层：`limits` 那三档拦下之后什么都不留 —— 计数器在内存里，一次 429 之后
// 没有任何一处能回答"是谁、受哪一档管、从什么时候开始的"。现场表现就是"我朋友的推送进不来了"，
// 而 #140 已经实测到反代之后按 IP 的桶本来就不可信，只翻日志连"是不是同一个源"都对不上。
//
// 四条判据先写在头上，它们就是这段代码长成这个形状的原因：
// ⚠ **四个数只从契约 `alerts` 段读**（与 ratelimit.js / senderquota.js 同规矩）：A1 那次实现
//    绕开契约改用环境变量，于是留下两份真值，而调 env 的人照着错的日志只会更糟。
// ⚠ **不落盘**（契约 `alerts.persistToDisk=false`）：公网面上的每一次写盘都是一个"一个请求换
//    一次磁盘写"的放大器 —— 那正是 T29-B 把拒收计数只留内存的理由。告警的用途是"现在去看一眼"，
//    不是审计账本；账本归 T53，那里丢一条才是真事故。重启丢告警是可接受的，这条取舍写进契约。
// ⚠ **有界**：条目上限取 `alerts.maxActiveAlerts`。告警的主体来自外部输入（设备地址码、对端 IP），
//    没有上限就等于在公网上挂一段无界内存，而那正是这批限流要防的东西。到上限淘汰最旧的一条。
// ⚠ **冷却合并**：同一 (主体种类, 主体, 端点种类, 窗口, 结论) 在 `cooldownSeconds` 内只更新
//    既有条目、不新增、不再打日志。没有这条，告警的输出速率与请求速率成正比 ⇒ 告警本身成为
//    第二种洪水，而且它挤满内存环时会把真正的异常从最旧端淘汰掉 —— 等于洪水替攻击者清场。
//
// near（接近额度）与 denied（已经拒了）两种结论：阈值必须严格小于 1，等于 1 时 near 只是
// denied 的另一种写法，那不如只看 429。
//
// ⚠ observe 的 `subject` 只许是**已经公开、或运维必须拿来定位**的标识（设备地址码、对端 IP），
//   不许是任何口令、摘要或正文。类型上防不住，所以这里写明，并由用例断言管理面响应只有白名单键。
// ⚠ 按 IP 的那批主体，在反代之后拿到的是代理（CF）的地址 —— 那是 #140 的问题，不是本层的缺陷；
//   告警列表里成片的 `ip|172.x` 就是它的样子。

'use strict';

const { loadContract, assertSupported, shapeError } = require('./contract');

const SECOND_MS = 1000;

/// 实现真的会产出的主体种类。契约必须覆盖它：少一个 ⇒ **启动就抛**，而不是运行到那一类
/// 请求被拦时才事后发现"这类告警从来没有出现过"。契约里多出来的种类属于"没有生产者的摆设"，
/// 由 Dart `validate()` 那条交叉判据管（`alerts.subjectKinds` ↔ `limits` 的三档 principal）。
const REQUIRED_SUBJECT_KINDS = Object.freeze(['device', 'ip']);

/// 层 1 那个"整个面按 IP 的总量闸门"没有对应的 `clientEvents` 名字，所以既不许伪装成某个
/// 端点种类，也不许在日志里省掉 —— 否则"洪水"与"某个端点被玩坏"在告警里长成同一个样子。
const FACE_KIND = 'face';

/// 从契约取告警的四个数。**取不到就抛**，不许缺省成"不告警"：一份读不出数字的契约表，
/// 正确行为是启动失败并被横幅说破原因，不是悄悄变成一台什么都不报告的哑服务器。
function alertsFromContract(contract) {
  const src = contract && contract.alerts;
  if (!src || typeof src !== 'object') {
    throw shapeError('契约缺 alerts 段：告警的四个数没有第二个来源，读不到就该启动失败');
  }
  const ratio = Number(src.nearQuotaRatio);
  if (!(ratio > 0 && ratio < 1)) {
    throw shapeError(
      `alerts.nearQuotaRatio 必须在 (0,1) 开区间（实际 ${src.nearQuotaRatio}）：` +
        '等于 1 时 near 只是 denied 的另一种写法，而 near 存在的全部意义是"还没拒就已经不对劲"',
    );
  }
  const cooldownSeconds = Number(src.cooldownSeconds);
  if (!(cooldownSeconds > 0)) {
    throw shapeError(
      `alerts.cooldownSeconds 必须是正数（实际 ${src.cooldownSeconds}）：` +
        '没有冷却，告警的输出速率就与请求速率成正比，它自己变成第二种洪水',
    );
  }
  const maxActiveAlerts = Number(src.maxActiveAlerts);
  if (!Number.isInteger(maxActiveAlerts) || maxActiveAlerts <= 0) {
    throw shapeError(
      `alerts.maxActiveAlerts 必须是正整数（实际 ${src.maxActiveAlerts}）：` +
        '主体来自外部输入，没有上限等于把一段无界内存挂在公网上',
    );
  }
  if (src.persistToDisk !== false) {
    throw shapeError(
      'alerts.persistToDisk 只能是 false：公网面上的每次写盘都是一个请求换一次磁盘写的放大器' +
        '（T29-B 的拒收计数同此）。真要落盘就同时把写限频与上限写进这一段，再改这里',
    );
  }
  const kinds = Array.isArray(src.subjectKinds) ? src.subjectKinds.map(String) : null;
  if (!kinds || !kinds.length) {
    throw shapeError('alerts.subjectKinds 必须是非空数组：不知道"按谁计"的告警无法定位到人');
  }
  const missing = REQUIRED_SUBJECT_KINDS.filter((k) => !kinds.includes(k));
  if (missing.length) {
    throw shapeError(
      `alerts.subjectKinds 缺 ${missing.join('、')}：实现会产出这几类主体，` +
        '名单里没有它们时那些告警会被丢掉 —— 一份"看起来什么都管"的告警系统最坏的地方是它不吭声',
    );
  }
  return {
    nearQuotaRatio: ratio,
    cooldownMs: cooldownSeconds * SECOND_MS,
    maxActiveAlerts,
    subjectKinds: new Set(kinds),
  };
}

/// 一条告警的公开形状（管理面响应与日志都用它）。新加键就等于往公网侧多端出去一个字段，
/// 所以这里显式挑字段，不 spread 内部条目。
function publicShape(entry) {
  return {
    subjectKind: entry.subjectKind,
    subject: entry.subject,
    kind: entry.kind,
    window: entry.window,
    outcome: entry.outcome,
    count: entry.count,
    limit: entry.limit,
    times: entry.times,
    firstAt: entry.firstAt,
    lastAt: entry.lastAt,
  };
}

function createAnomalyTracker(options = {}) {
  const contract = assertSupported(options.contract || loadContract());
  const alerts = options.alerts || alertsFromContract(contract);
  const emit = options.log === undefined ? (line) => console.warn(line) : options.log;
  /** 键 → 条目。Map 的插入序就是"从旧到新"，淘汰时直接取第一个。 */
  const entries = new Map();

  /// 这一档的"接近额度"线：额度的这个比例之上就记 near（只算一次，跨过那一刻）。
  function nearThreshold(limit) {
    return Math.ceil(limit * alerts.nearQuotaRatio);
  }

  function logLine(entry) {
    return (
      `[fnthink:alert] ${entry.outcome} ${entry.subjectKind}:${entry.subject} ` +
      `端点=${entry.kind} 窗口=${entry.window} 计数=${entry.count}/${entry.limit} ` +
      `累计=${entry.times} 首次=${new Date(entry.firstAt).toISOString()}`
    );
  }

  /// 观察一发计数。返回 null = 这一发没什么可说的；否则返回它落进的那条告警记录。
  /// 事件形状：{ subjectKind, subject, kind, window, count, limit, denied, at }
  /// ⚠ 调用方给的是**已经记完账的 count 与该窗口的 limit**，比例与结论在这里判 ——
  ///   两处各判一次就会有两份"接近额度"的定义，那是 A1 那份"两份真值"的同一个错误。
  function observe(event) {
    const limit = Number(event && event.limit);
    const count = Number(event && event.count);
    // 没有额度就没有"比例"这个概念（层 3 的轮询日档 perDay=null 就是这个形状）：直接不记，
    // 而不是拿 Infinity 去比 —— 后者会让"这一档故意不设上限"在告警里长成"永远不会 near"。
    if (!Number.isFinite(limit) || limit <= 0 || !Number.isFinite(count)) return null;
    const outcome = event.denied ? 'denied' : count >= nearThreshold(limit) ? 'near' : null;
    if (!outcome) return null;

    const subjectKind = String(event.subjectKind);
    if (!alerts.subjectKinds.has(subjectKind)) {
      // 走到这里说明代码与契约的名单不同步（构造期已经查过 REQUIRED，所以这确实是新情况）。
      // 让它抛：本仓已经实测过一次"代码 bug 被咽成部署问题"（app.js 漏 require 冒成 503），
      // 而"该有一条告警却没有"比一次 500 更难查。
      throw new Error(
        `告警主体种类 ${subjectKind} 不在 alerts.subjectKinds 里 ⇒ 这条告警会被丢掉（实现与契约不同步）`,
      );
    }
    const subject = String(event.subject);
    const kind = String(event.kind);
    const windowName = String(event.window);
    const now = event.at || Date.now();
    const key = `${subjectKind}|${subject}|${kind}|${windowName}|${outcome}`;

    const hit = entries.get(key);
    if (hit) {
      hit.times += 1;
      hit.lastAt = now;
      hit.count = count;
      hit.limit = limit;
      // 冷却只管"再说一次"的间隔，总数照加：一条被反复触发的告警在列表里应该显示出次数，
      // 否则运维看到的是一条看不出规模的一行。
      if (now - hit.loggedAt >= alerts.cooldownMs) {
        hit.loggedAt = now;
        emit(logLine(hit));
      }
      return hit;
    }

    if (entries.size >= alerts.maxActiveAlerts) {
      const oldest = entries.keys().next().value;
      entries.delete(oldest);
    }
    const entry = {
      subjectKind,
      subject,
      kind,
      window: windowName,
      outcome,
      count,
      limit,
      times: 1,
      firstAt: now,
      lastAt: now,
      loggedAt: now,
    };
    entries.set(key, entry);
    emit(logLine(entry));
    return entry;
  }

  /// 最近优先的告警列表（内部条目 → 公开形状）。
  function recent() {
    return [...entries.values()].sort((a, b) => b.lastAt - a.lastAt).map(publicShape);
  }

  const tracker = { observe, recent, nearThreshold };
  tracker.alerts = alerts;
  tracker.size = () => entries.size;
  return tracker;
}

/// 进程内单例：限流器（按 IP）、按发送方配额（按设备地址）与管理面读取方要看到同一份计数。
/// 走 require 缓存而不是层层传参 —— routes.js 的配额是模块级创建的，拿不到 req.app。
let shared = null;
function sharedTracker() {
  if (!shared) shared = createAnomalyTracker();
  return shared;
}

/// 仅测试用：清空单例。它不丢任何持久数据（这一段刻意不落盘），丢的是告警列表，
/// 而那正是"重启可接受"的那一类。
function resetSharedTracker() {
  shared = null;
}

module.exports = {
  alertsFromContract,
  createAnomalyTracker,
  sharedTracker,
  resetSharedTracker,
  publicShape,
  REQUIRED_SUBJECT_KINDS,
  FACE_KIND,
};
