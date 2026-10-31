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
/// 3. **词表外**：**承认没写过**（T201 更正）。原口径是「原样返回」——那一半被 2026-10-26
///    维护者拍板换掉：现在返回「这条我们还没写过说明（原文：`<code>`）」。
///    「不许编」那半句保留：它同样不替本机造原因，只是把「英文裸码糊在屏上」换成
///    「这句我们没写过 + 原始码」。**这是对 T144 那条裁定的显式翻案**，所以写在这里，
///    不留成一次看不见的改动。
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
  // T201 ③：词表外不再裸打印 —— 那句「没写过」本身就是事实，原文照带，不猜原因。
  return l10n.remoteReasonUnknownCode(inner);
}

/// 这个词典认不认得这枚理由（T201 ③ 的诊断读数用）。
///
/// 与 [remoteReasonText] 共用同一张三档表：不另写一份"什么算认得"的判据。
bool remoteReasonIsKnown(String reason) {
  final inner = reason.startsWith('item:')
      ? reason.substring('item:'.length)
      : reason;
  if (_exact.containsKey(inner)) return true;
  final at = inner.indexOf(':');
  if (at > 0) {
    final family = inner.substring(0, at);
    if (_families.containsKey(family) || family == 'auth') return true;
  }
  return false;
}

/// 报错说明弹层的正文（T201 ④⑤）：**从同一张表生成**，不另抄一份说明。
///
/// 它给两张远程执行页与发送后的当场结论共用：用户读到「bad-keyword:xxx」时，
/// 点这一枚问号能查到这一族在说什么，而不是只有一枚英文码。
///
/// [missCount] 是**屏幕上这一屏**里词表外的那些（T201 ③）。它由调用点从当场那几行
/// 现算，不在这里再数一遍：这里数不到"用户看见的是哪几行"，而把读数写成恒有的
/// 一句会造出一个不存在的缺口。0 = 一句不加（这一屏没有漏词条，就不许宣称有）。
String remoteReasonHelpBody(AppLocalizations l10n, {int missCount = 0}) {
  final lines = <String>[l10n.remoteReasonHelpIntro];
  for (final entry in _exact.entries) {
    lines.add('· ${entry.key}：${entry.value(l10n)}');
  }
  lines.add(l10n.remoteReasonHelpFamilyNote);
  if (missCount > 0) lines.add(l10n.remoteReasonMissSeen(missCount));
  return lines.join('\n');
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
  // T200：发起端重启后「这一轮没拿到回执」只说明状态未知，与送达清扫那枚同词同源
  // （`delivery_status.dart` 的 `deliveryNoReceiptReason`）。
  'no-receipt': (l) => l.remoteReasonNoReceipt,
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
  // ── T201：发起端与包侧真会落到 reason 那一格的码 ────────────────────
  // 11 枚 `FnthinkSendStatus` 名称（`send_kernel.dart`；发送页在 reason 缺失时用它）
  'accepted': (l) => l.remoteReasonSendAccepted,
  'rejectedUnsigned': (l) => l.remoteReasonSendRejectedUnsigned,
  'rejectedCapability': (l) => l.remoteReasonSendRejectedCapability,
  'replayed': (l) => l.remoteReasonSendReplayed,
  'needsCalibration': (l) => l.remoteReasonSendNeedsCalibration,
  'rateLimited': (l) => l.remoteReasonSendRateLimited,
  'transportError': (l) => l.remoteReasonSendTransportError,
  'signingUnavailable': (l) => l.remoteReasonSendSigningUnavailable,
  'preconditionFailed': (l) => l.remoteReasonSendPreconditionFailed,
  'badInput': (l) => l.remoteReasonSendBadInput,
  'unparseable': (l) => l.remoteReasonSendUnparseable,
  // 发送内核自己造的那几枚整串理由（`_lastReason = '…'`）
  'ts-expired-needs-calibration': (l) => l.remoteReasonTsExpired,
  'nonce-replayed': (l) => l.remoteReasonNonceReplayed,
  'unsigned-or-unknown': (l) => l.remoteReasonUnsignedOrUnknown,
  'accepted-without-message-id': (l) => l.remoteReasonAcceptedWithoutId,
  // 原生通道失败码（`WebhookResponseParser.DeliveryStatus`）
  'BIZ_FAIL': (l) => l.remoteReasonBizFail,
  'HTTP_FAIL': (l) => l.remoteReasonHttpFail,
  'NETWORK_FAIL': (l) => l.remoteReasonNetworkFail,
  'RATE_LIMITED': (l) => l.remoteReasonRateLimitedNative,
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
  // ── T201：发送内核的 `<族>:<细节>` 那几族 ─────────────────────────────
  'signing': (l, t) => l.remoteReasonSigningFailed(t),
  'transport': (l, t) => l.remoteReasonTransportFailed(t),
  'rate-limited': (l, t) => l.remoteReasonRateLimitFamily(t),
  'capability': (l, t) => l.remoteReasonCapabilityFamily(t),
  'unexpected-status': (l, t) => l.remoteReasonUnexpectedStatus(t),
};

/// 两张键集，**只给守卫用**（双向差集要拿表与源码对；表本身不对外可写）。
Set<String> get remoteReasonExactKeys => _exact.keys.toSet();

/// 前缀族名集合（同上调；`item:` 是包装、不算一族，故不在这里）。
Set<String> get remoteReasonFamilyNames => _families.keys.toSet();
