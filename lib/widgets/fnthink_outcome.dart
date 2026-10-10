/// 幻念这一族「这一步做成了没有」的**当场**出口（T126 片1）。
///
/// ## 为什么要有它
/// 配对链上每一发的结论此前只落在格子里那枚 12px 灰小字上（`FnthinkNote`）。维护者
/// 2026-10-10 的读感是「刚才你显示的密钥失效、发送成功之类的，很不起眼」—— 而这几条
/// 恰恰是**只有当场有用**的信息：等对面答复要过一轮收取，用户早就滚去看别的了。
///
/// ## 它不替换那枚小字，只补"当场"这一发
/// 小字那一格**留着**：它是事后翻回去看的地方（`fnthink_peers_page.dart` 里那句
/// 「答过一条之后要留着」的纪律仍然成立）。这一发补的是"答完那一下屏幕上要有东西"。
///
/// ## ⚠ 措辞不在这里造
/// 标题只有两档（做成了／没做成），而且**不分辨原因** —— 那一句原话由各页现有的唯一作者给
/// （`_pairAnswerText`、`fnthinkPairSubmitText`）。在这里再按 reason 翻一遍，就长出第二个
/// 词表：内核加一种 reason 时，这一处不会红，而它会开始说"未知"。
///
/// ## ⚠ 两档而不是三档
/// 「还在等对面答复」在用户这一侧就是**这一发做成了**（`ok:true`）：等答复是后续状态，
/// 不是失败。做成第三档会诱导用户重发那一发，而重发会换掉 `requestId`。
library;

import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import 'ios_dialog_actions.dart';

/// 弹一次结论。[detail] 必须是那一页现有那句结论的**原话**，不许在这里另拼。
Future<void> showFnthinkOutcome(
  BuildContext context, {
  required bool ok,
  required String detail,
}) {
  final l10n = AppLocalizations.of(context);
  return IosDialogActions.showInfo(
    context,
    title: ok ? l10n.fnthinkOutcomeDone : l10n.fnthinkOutcomeFailed,
    message: detail,
  );
}
