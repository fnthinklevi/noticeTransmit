import 'package:flutter/material.dart';
import 'package:fnthink_push/fnthink_push.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

/// 「发一条」那一格的输入弹层（§4-10 片2b）与发送结论文案（T48 收尾）。
///
/// 为什么单独一个文件：**两个入口共用同一发**——幻念推送页名单行上的「发一条」，以及历史页
/// 收件详情里的「回复 / 重发」。发送结论那 11 档状态各有各的原话，抄第二份的下场是
/// "同一个状态在两个页面说两句话"，而那正是这条链路最容易被读歪的地方（用户看哪一句取决于
/// 他当时在哪一页）。
///
/// controller 与生命周期归弹层自己（与 `_HostDialog` 同一条理由：调用方在 `await` 返回时
/// dispose 会打在还在做退场动画的 TextField 上）。
///
/// 为什么**这里**就拦空正文：空正文发出去，那边只会收到一句空话，而回执照样是"送达"——
/// 那正是"不静默丢、也不无谓留"那条不变量不想看到的形状（内容没丢，但这一发本就不该发生）。
/// 只在弹层里用「发送」按钮的可用性表达，调用方不再判一次：两处判同一件事，早晚一处改了另一处没改。
Future<({String title, String text})?> showFnthinkSendDialog({
  required BuildContext context,
  required String peerAddress,
  String initialTitle = '',
  String initialBody = '',
}) {
  return showDialog<({String title, String text})>(
    context: context,
    builder: (context) => _FnthinkSendDialog(
      peerAddress: peerAddress,
      initialTitle: initialTitle,
      initialBody: initialBody,
    ),
  );
}

class _FnthinkSendDialog extends StatefulWidget {
  const _FnthinkSendDialog({
    required this.peerAddress,
    required this.initialTitle,
    required this.initialBody,
  });

  final String peerAddress;
  final String initialTitle;
  final String initialBody;

  @override
  State<_FnthinkSendDialog> createState() => _FnthinkSendDialogState();
}

class _FnthinkSendDialogState extends State<_FnthinkSendDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.initialTitle,
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.initialBody,
  );

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: AppColors.cardBg(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(l10n.fnthinkSendSheetTitle(widget.peerAddress)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('fnthink-send-title'),
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: l10n.fnthinkSendTitleHint),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('fnthink-send-body'),
            controller: _body,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: l10n.fnthinkSendBodyHint),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.fnthinkSendEnvelopeNote,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(height: 6),
          // 与上面那句一起说，而不是等发完再补：这两句讲的是"这一路与端点那一路哪里不一样"，
          // 用户是在填内容时才需要知道它 —— 发完之后再告诉他，他已经点过发送了。
          Text(
            l10n.fnthinkSendBoundary,
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
          key: const ValueKey('fnthink-send-submit'),
          onPressed: _body.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, (
                  title: _title.text,
                  text: _body.text,
                )),
          child: Text(
            _body.text.trim().isEmpty
                ? l10n.fnthinkSendEmptyBody
                : l10n.fnthinkSendSubmit,
          ),
        ),
      ],
    );
  }
}

/// 发送结论那一句的原话。**全仓唯一一处**（幻念推送页与历史页收件详情共用）：
/// 每一档状态说的都是"用户下一步做什么"——折叠成一句"发送失败"就是让他去点第二下。
String fnthinkSendResultText(AppLocalizations l10n, FnthinkSendResult result) {
  final base = switch (result.status) {
    FnthinkSendStatus.accepted => l10n.fnthinkSendSent(result.messageId ?? ''),
    FnthinkSendStatus.rejectedUnsigned => l10n.fnthinkSendRejectedUnsigned,
    FnthinkSendStatus.rejectedCapability => l10n.fnthinkSendRejectedCapability,
    FnthinkSendStatus.replayed => l10n.fnthinkSendReplayed,
    FnthinkSendStatus.needsCalibration => l10n.fnthinkSendNeedsCalibration,
    FnthinkSendStatus.rateLimited => l10n.fnthinkSendRateLimited(
      result.retryAfterSeconds ?? 0,
    ),
    FnthinkSendStatus.transportError => l10n.fnthinkSendTransportError,
    FnthinkSendStatus.signingUnavailable => l10n.fnthinkSendSigningUnavailable,
    FnthinkSendStatus.preconditionFailed => l10n.fnthinkSendPrecondition(
      result.reason ?? '',
    ),
    FnthinkSendStatus.badInput => l10n.fnthinkSendBadInput,
    FnthinkSendStatus.unparseable => l10n.fnthinkSendUnparseable,
  };
  // 挤位那句话只在真挤掉过东西时才出现。发送端是唯一能看见这件事的地方 ——
  // 服务端那边各条已写了 dropped 回执，但那要等下一次 poll 才看得见。
  if (result.status == FnthinkSendStatus.accepted &&
      result.evicted.isNotEmpty) {
    return '$base ${l10n.fnthinkSendEvicted(result.evicted.length)}';
  }
  return base;
}
