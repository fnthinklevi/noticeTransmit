import '../l10n/app_localizations.dart';

/// 远程执行历史里「理由」那一格的人话 —— **唯一作者**（T144 片2，维护者 2026-10-12 裁定 3）。
///
/// ## 为什么是一张表而不是页面里的一句翻译
/// 判定层（`RemoteCommandRecognizer.judge`）、状态机与两侧执行器各自造 reason 串，
/// 最后落进同一列。在页面里翻一半 ⇒ 屏上同时出现"人话"与"机器词"，而用户分不清哪句是系统的结论、
/// 哪句是没翻译的原始码 —— 这比全不翻更坏（roadmap 那一行原话）。
///
/// ## 三档口径（一次定死，不许后来人各挑一档）
/// 1. **整串封闭词**：查 [_exact]。整串而不是前缀 —— `listener:start` 与 `listener:stop` 说的是
///    "这条动作没做成"，与 `fnthink_remote_action_labels` 那张"动作名"贴纸**同形不同义**，
///    按前缀判会把失败码翻译成动作名。
/// 2. **前缀族**：`<族>:<尾串>`。族进表，尾串**原样带出**。尾串不在这里二次翻：动作名与 L3 项名的
///    人话已有各自作者，在这一格再翻一次就是第二个作者（改了那边、这边静默失配）。
/// 3. **词表外**：原样返回。**不许编** —— 替本机造一句没做过的原因是这一族最坏的形状。
///    唯一例外是 `auth:` 认不出的子词（那一族只有三枚，多出来一枚一定是新加的凭据方式，
///    此时"没有更多原因可读"是事实，而那三枚本身在 [_exact] 里）。
///
/// ⚠ `item:` 是个**包装**（判定层把"这一项的问题"统一挂在这个前缀下），先剥掉再走上面三档。
String remoteReasonText(String reason, AppLocalizations l10n) {
  final inner = reason.startsWith('item:')
      ? reason.substring('item:'.length)
      : reason;
  final exact = _exact[inner];
  if (exact != null) return exact(l10n);

  final at = inner.indexOf(':');
  if (at > 0) {
    final family = inner.substring(0, at);
    final tail = inner.substring(at + 1);
    final text = _families[family];
    if (text != null) return text(l10n, tail);
    if (family == 'auth') return l10n.remoteReasonUnknown(tail);
  }
  return inner;
}

/// 整串封闭词。每一枚都必须真的被源码造出来，且源码造的每一枚都在这里 ——
/// 守卫 `test/architecture/remote_reason_words_guard_test.dart` 按双向差集钉。
final Map<String, String Function(AppLocalizations)> _exact = {
  'switch-off': (l) => l.remoteReasonSwitchOff,
  'local-trigger-off': (l) => l.remoteReasonLocalTriggerOff,
  'app-not-allowed': (l) => l.remoteReasonAppNotAllowed,
  'missing-item': (l) => l.remoteReasonMissingItem,
  'confirm-required': (l) => l.remoteReasonConfirmRequired,
  'auth:wrong': (l) => l.remoteReasonAuthWrong,
  'auth:missing-required': (l) => l.remoteReasonAuthMissing,
  'auth:unsupported-mode': (l) => l.remoteReasonAuthMode,
  'terminal-state': (l) => l.remoteReasonTerminalState,
  'illegal-move': (l) => l.remoteReasonIllegalMove,
  'interrupted': (l) => l.remoteReasonInterrupted,
  'cancelled-by-user': (l) => l.remoteReasonCancelledByUser,
  'cancelled-from-status-bar': (l) => l.remoteReasonCancelledStatusBar,
  'report-not-sent': (l) => l.remoteReasonReportNotSent,
  'report-failed': (l) => l.remoteReasonReportFailed,
  'sms-search-failed': (l) => l.remoteReasonSmsFailed,
  'calls-search-failed': (l) => l.remoteReasonCallsFailed,
  'location-failed': (l) => l.remoteReasonLocationFailed,
  'camera-snap-failed': (l) => l.remoteReasonCameraFailed,
  'contacts-search-failed': (l) => l.remoteReasonContactsFailed,
  'device-state-push-refused': (l) => l.remoteReasonDeviceStateRefused,
  'alert-ring-refused': (l) => l.remoteReasonAlertRefused,
  'listener:start': (l) => l.remoteReasonListenerStart,
  'listener:stop': (l) => l.remoteReasonListenerStop,
};

/// 前缀族：族名 →（尾串原样带出）。
final Map<String, String Function(AppLocalizations, String)> _families = {
  'source-not-allowed': (l, t) => l.remoteReasonSourceNotAllowed(t),
  'not-granted': (l, t) => l.remoteReasonNotGranted(t),
  'missing-grant': (l, t) => l.remoteReasonMissingGrant(t),
  'unknown-action': (l, t) => l.remoteReasonUnknownAction(t),
  'unknown-setting': (l, t) => l.remoteReasonUnknownSetting(t),
  'unknown-item': (l, t) => l.remoteReasonUnknownItem(t),
  'unknown-ceiling': (l, t) => l.remoteReasonUnknownCeiling(t),
  'level': (l, t) => l.remoteReasonLevel(t),
  'unmapped-action': (l, t) => l.remoteReasonUnmappedAction(t),
  'not-applied': (l, t) => l.remoteReasonNotApplied(t),
  // 参数形状那一族（`fnthink_l2_actions.dart` 与 `fnthink_grant_items.dart` 的拒绝码）。
  // 尾巴是**动作名或那一段参数** ⇒ 原样带出，别在这一格再翻一次动作名（那是第二个作者）。
  // 这一族是守卫 ①（双向差集）量出来的，不是手抄的：少了任何一枚，那一格就落成机器词。
  'bad-argument-kind': (l, t) => l.remoteReasonBadArgumentKind(t),
  'bad-channel-argument': (l, t) => l.remoteReasonBadChannelArgument(t),
  'bad-keyword': (l, t) => l.remoteReasonBadKeyword(t),
  'bad-report-count': (l, t) => l.remoteReasonBadReportCount(t),
  'missing-argument': (l, t) => l.remoteReasonMissingArgument(t),
  'no-such-channel': (l, t) => l.remoteReasonNoSuchChannel(t),
  'unexpected-argument': (l, t) => l.remoteReasonUnexpectedArgument(t),
  'unknown-target-word': (l, t) => l.remoteReasonUnknownTargetWord(t),
  // 形状最松的一族：尾巴可能是动作名、可能是异常文本 ⇒ 只说"抛了异常"，不替它挑原因。
  'threw': (l, t) => l.remoteReasonThrew(t),
};

/// 两张键集，**只给守卫用**（双向差集要拿表与源码对；表本身不对外可写）。
Set<String> get remoteReasonExactKeys => _exact.keys.toSet();

/// 前缀族名集合（同上调；`item:` 是包装、不算一族，故不在这里）。
Set<String> get remoteReasonFamilyNames => _families.keys.toSet();
