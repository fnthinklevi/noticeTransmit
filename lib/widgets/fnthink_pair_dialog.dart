import 'package:flutter/material.dart';
import 'package:fnthink_push/fnthink_push.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

/// 「配对另一台设备」那一格的输入弹层与提交结论（#176 片3，T28-B 的 B 侧）。
///
/// 为什么是弹层而不是页面里三格常驻输入框：这一发要输入的**口令是一次性的**。摆在那儿
/// 就总要有人决定"它什么时候清掉"，而最容易写的两种实现（存进 state 方便回填、存进 prefs
/// 方便重来）都把"这一把只出现一次"变成了"这把长期可见"。弹层关掉就是它消失的时候。
///
/// controller 归弹层自己（与 `_HostDialog`、`showFnthinkSendDialog` 同一条理由）：调用方在
/// `await showDialog` 返回的那一刻 dispose 会打在还在跑退场动画的 TextField 上，而那种崩
/// 只在"真点过一次"时现形。
///
/// 三条红线，各对应一次会在用户那侧静默发生的失真：
///  ① **提交 ≠ 配上**：服务端 `pairing.autoApprove=false`，这一发只让对面那台多出一条待确认。
///     结论那句由 [fnthinkPairSubmitText] 唯一作者写成"已提交，等对方确认"，不许出现"配对成功"；
///  ② **档位只列契约够得着的那几档**（[FnthinkContract.pairRequestableLevels]）。弹层里不写
///     任何一个 `L1`/`L2`/`L3` 字面量：请求超档在服务端是整条拒（`level-too-high`）而不是压到封顶，
///     把 L3 摆出来等于让用户点一句必被拒的话，而拒信与"口令错"同形；
///  ③ **这一发不许留下口令的副本**：不落 prefs、不进表、不进日志，也不拼进任何异常文本。
typedef FnthinkPairInput = ({String target, String code, String level});

/// 打开输入弹层。返回 null = 用户取消 ⇒ 调用方一个字节都不该发出去。
Future<FnthinkPairInput?> showFnthinkPairDialog({
  required BuildContext context,
  required FnthinkContract contract,
}) {
  return showDialog<FnthinkPairInput>(
    context: context,
    builder: (context) => _FnthinkPairDialog(contract: contract),
  );
}

class _FnthinkPairDialog extends StatefulWidget {
  const _FnthinkPairDialog({required this.contract});

  final FnthinkContract contract;

  @override
  State<_FnthinkPairDialog> createState() => _FnthinkPairDialogState();
}

class _FnthinkPairDialogState extends State<_FnthinkPairDialog> {
  final TextEditingController _target = TextEditingController();
  final TextEditingController _code = TextEditingController();

  /// 选中那一档。初值取契约名单里的**最低**一档（`capabilities.levels` 按权限升序，
  /// 所以第一项就是 `grantDefaults` 那一档）：要对方给更高的授权得由用户自己往上点，
  /// 而不是界面替他挑一个"通常够用"的。
  late String _level = widget.contract.pairRequestableLevels.first;

  @override
  void dispose() {
    _target.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _ready =>
      _target.text.trim().isNotEmpty && _code.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final levels = widget.contract.pairRequestableLevels;
    return AlertDialog(
      backgroundColor: AppColors.cardBg(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(l10n.fnthinkPairPeerTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('fnthink-pair-peer-target'),
            controller: _target,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: l10n.fnthinkPairPeerTargetHint,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('fnthink-pair-peer-code'),
            controller: _code,
            autocorrect: false,
            decoration: InputDecoration(hintText: l10n.fnthinkPairPeerCodeHint),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.fnthinkPairPeerCodeNote,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                for (final level in levels)
                  ChoiceChip(
                    key: ValueKey('fnthink-pair-peer-level-$level'),
                    label: Text(level),
                    selected: _level == level,
                    onSelected: (_) => setState(() => _level = level),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // 为什么这里没有更高的那一档：它不是"还没加载出来"，也不是"本机坏了"。
          // 少这句时用户的下一步动作是翻设置或重挂口令，而真答案是"那台设备要本地确认"。
          Text(
            l10n.fnthinkPairPeerLevelNote(levels.last),
            style: TextStyle(
              fontSize: 12,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const ValueKey('fnthink-pair-peer-submit'),
          // 少填一样 ⇒ 不发：这一发带走一次性的口令，半填的提交换回的只会是"口令错"，
          // 而那枚口令本来能配成。判据只有这一处（调用方不再判一次空）。
          onPressed: !_ready
              ? null
              : () => Navigator.pop(context, (
                  target: _target.text.trim(),
                  code: _code.text.trim(),
                  level: _level,
                )),
          child: Text(
            _ready
                ? l10n.fnthinkPairPeerSubmit
                : l10n.fnthinkPairPeerIncomplete,
          ),
        ),
      ],
    );
  }
}

/// 提交那一发的结论。**全仓唯一一处**作者（与 [fnthinkSendResultText] 同一条纪律）：
/// 每一档说的都是"用户下一步做什么"，折叠成一句"配对失败"就是让他去点第二下 ——
/// 而那一发里带走的是一次性口令，点第二下的代价是那枚口令已经没了。
///
/// ⚠ `ok` 用的是 [FnthinkPairResult.ok]（状态 ok **且** 拿到 requestId **且** 那个状态词在契约
/// 名单里）：200 而说不出这条请求，就是服务器没记下它，此时"已提交"是假话。
/// ⚠ 前置失败那几句（没同意中转 / 签不出来）各自成句，不与"服务器拒了"混：那两种情况下
/// 一个字节都没离机，让用户去查网络会得到一句永远不成立的解释。
String fnthinkPairSubmitText(AppLocalizations l10n, FnthinkPairResult result) {
  if (result.ok) {
    return l10n.fnthinkPairPeerSubmitted(
      result.requestId ?? '',
      result.requestStatus ?? '',
    );
  }
  final reason = result.reason ?? 'no-answer';
  if (reason == 'not-consented') return l10n.fnthinkPairPeerNotConsented;
  if (reason == 'signing-unavailable') return l10n.fnthinkPairPeerNoSignature;
  return switch (result.status) {
    FnthinkPollStatus.transportError => l10n.fnthinkPairPeerTransportError,
    FnthinkPollStatus.rejectedUnsigned => l10n.fnthinkPairPeerUnsigned,
    FnthinkPollStatus.rateLimited => l10n.fnthinkPairPeerRateLimited,
    FnthinkPollStatus.replayed => l10n.fnthinkPairPeerReplayed,
    FnthinkPollStatus.needsCalibration => l10n.fnthinkPairPeerNeedsCalibration,
    _ => l10n.fnthinkPairPeerFailed(reason),
  };
}
