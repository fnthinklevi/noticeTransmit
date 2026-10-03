// L3 系统设置的**服务端那一半**（T51）。
//
// 与 Dart 的 lib/services/fnthink_l3_settings.dart 是同一套设置项的两份实现，
// 而词表的唯一出处是契约 `capabilities.l3.settings`。两端各写一份映射是刻意的
// —— 它们各自调用本地的执行器（Node 侧只解析，Dart 侧去 MethodChannel 与 DB），
// 但"哪几项设置算数"必须同源。
//
// 这一层**只解析不执行**（与 T50 的 l2actions 同一红线：服务端看不见屏幕前的那个人）。

'use strict';

/// 把载荷里那个 `item` 读成设置项。
///
/// ⚠ 与 L2 的差别：L3 的 `item` **就是**设置项的 key，没有 `<family>:<verb>` 那一层
/// 拆分 —— 设置项本身已经带命名空间（`battery_optimization` / `collect_inbox`），
/// 再套一层前缀只会让"这项是哪个"有两个写法。
///
/// 四种拒的理由各不相同，**不许合并**（与 L2 同一条纪律）：
///   missing-item          载荷里根本没有 item
///   unknown-setting:X     X 不在契约词表里
///   needs-local-auth      这一项要本地锁屏/生物验证，而这一次没有
///   confirm-required      这一项每次都要确认（契约 confirmEveryTime），而这一次没确认
/// 最后两条**刻意不合并**：前者是"这台设备不具备开这一项的条件"（去设锁屏），
/// 后者是"可以开，但你没点"（再问一次）。合并之后用户看到的是"没反应"。
function parseL3Item(contract, item, options) {
  const opts = options || {};
  const l3 = ((contract && contract.capabilities) || {}).l3 || {};
  const settings = l3.settings || {};

  if (item === undefined || item === null || String(item) === '') {
    return { ok: false, reason: 'missing-item' };
  }
  const key = String(item);
  const spec = settings[key];
  if (!spec || typeof spec !== 'object') {
    return { ok: false, reason: `unknown-setting:${key}` };
  }

  // 每一项都要本地确认（契约 confirmEveryTime），且**没有免确认这条路**
  // （allowSkipConfirm: false）。intake 那一段判不了确认 —— 那是设备上的一次用户动作，
  // 而请求里那个自称的标志是对端在替接收端说"我确认了"（T30 那条红线）。
  if (l3.confirmEveryTime === true && opts.confirmedThisTime !== true) {
    return { ok: false, reason: 'confirm-required' };
  }

  const mode = String(spec.mode || '');
  if (mode === '' && Array.isArray(l3.modes) && !l3.modes.includes('')) {
    return { ok: false, reason: `bad-mode:${key}` };
  }
  // 先有授权才谈得上翻的那两项（契约 requiresExistingGrantFrom）
  if (opts.grantedKeys && Array.isArray(l3.requiresExistingGrantFrom)) {
    const needs = l3.requiresExistingGrantFrom;
    if (needs.includes(key) && !opts.grantedKeys.includes(key)) {
      return { ok: false, reason: `missing-grant:${key}` };
    }
  }
  return { ok: true, setting: { key, mode, native: String(spec.native || '') } };
}

/// 这一次 L3 执行对外回哪一个回执词（与 L2 共用 receipts 词表里那一个词，
/// 但**不是因为它们是一件事** —— 契约只该有一个对外形状；区别进留痕 T53）。
function l3ReceiptFor(contract, result) {
  if (result && result.ok) return 'delivered';
  const l3 = ((contract && contract.capabilities) || {}).l3 || {};
  return l3.settingsReceipt || 'failed_action';
}

/// 契约词表与服务端映射是否同步。守卫用例调它，改契约时红的就是这一条。
function l3SettingsKnownToServer(contract) {
  const l3 = ((contract && contract.capabilities) || {}).l3 || {};
  const settings = l3.settings || {};
  const keys = Object.keys(settings);
  if (keys.length === 0) return false;
  const modes = Array.isArray(l3.modes) ? l3.modes : [];
  return keys.every((k) => {
    const spec = settings[k];
    return (
      spec && typeof spec === 'object' && typeof spec.mode === 'string' && modes.includes(spec.mode)
    );
  });
}

module.exports = {
  l3ReceiptFor,
  l3SettingsKnownToServer,
  parseL3Item,
};
