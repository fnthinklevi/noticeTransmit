import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../widgets/ios_dialog_actions.dart';
import 'fnthink_settings.dart';

/// 撤销「通知内容经服务器中转」的同意 —— **两处入口共用的唯一一个实现**（T119）。
///
/// 为什么必须收成一处：这一发写的（_more precisely：清的_）是同一枚 prefs 键，而它今天有两个
/// 落点（「接收推送」那一页与「幻念推送设置」那一页）。两处各写一遍撤销的话，"设置页撤销了
/// 而接收页还显示已同意"就是迟早的事 —— 那正是本仓在同意那一侧立 `grantRelayConsent`
/// 唯一作者时反对过的同一个形状。
///
/// 三条写在这里的口径：
///  - **二次确认才办，取消 ⇒ 一个字节都不写**（与同意那一发对称：同意是一次显式动作，
///    撤销也是一次 —— 它会让正在收的东西停掉）。
///  - 弹层那句**只说今天真的会停的**与**不会丢的**。⚠ 这条口径在 T118 落地时**改过一次内容**：
///    清单（端点建/换/撤、发起与批准配对、通道创建/启用与「发一条」、会带正文的那一发测试）
///    经维护者 2026-10-09 拍定并落进 `requireFnthinkRelayConsent`（见 `pages/fnthink_consent_gate.dart`），
///    所以那句话跟着补全了 —— 它此前只能写"收取与远程控制"两项，是因为清单还没拍、不许替未定的事作保。
///  - 返回 `true` 只表示"用户确认并已清掉那一枚键"；调用方自己要重读状态刷新界面，
///    这里不替页面 setState（那会把"哪一屏在什么时候重读"的口径搬到服务层去）。
Future<bool> confirmAndRevokeRelayConsent({
  required BuildContext context,
  required FnthinkSettings? settings,
}) async {
  final target = settings;
  if (target == null) return false;
  final l10n = AppLocalizations.of(context);
  final ok = await IosDialogActions.askConfirm(
    context,
    title: l10n.fnthinkConsentRevokeTitle,
    message: l10n.fnthinkConsentRevokeMsg,
    confirmText: l10n.fnthinkConsentRevoke,
  );
  if (!ok) return false;
  await target.revokeRelayConsent();
  return true;
}
