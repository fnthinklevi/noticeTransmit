import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;

import '../theme/app_colors.dart';
import 'ios_dialog_actions.dart';

/// 一枚**带圈问号**：点开讲这一格/这一页的长说明。
///
/// 为什么要有它（维护者 2026-10-06 定的两条口径之一）：页面里不许成段堆小字说明
/// （"像论文、没有设计感"）。提醒文字只有两种去处 —— 页面底部的无序列表，或者这一枚
/// 问号点开弹窗。弹窗走仓库已有的 [IosDialogActions.showExplainer]，**不新造弹层形状**
/// （T90 那本「Material 弹层」台账只许变薄）。
///
/// ⚠ 用它的时候正文**不删**：长文原样搬进弹窗，界面上只留一行短说。
/// 这样 ARB 键数不变（不会触发死词条棘轮），而该讲清的事一句没少 ——
/// 只是不再占正文位置。
class HelpNoteButton extends StatelessWidget {
  const HelpNoteButton({
    super.key,
    required this.keyName,
    required this.title,
    required this.body,
  });

  /// ValueKey 的名字部分。用例与发版闸门都按 `ValueKey(keyName)` 点这一枚。
  final String keyName;

  /// 弹窗标题（这一格在管什么）。
  final String title;

  /// 弹窗正文 —— 就是原来那句长说明，原样搬进来。
  final String body;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      key: ValueKey(keyName),
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () => IosDialogActions.showExplainer<void>(
        context,
        title: title,
        body: Text(body),
      ),
      child: Icon(
        Icons.help_outline,
        size: 18,
        color: AppColors.secondaryLabel(context),
      ),
    );
  }
}

/// 一行短说 ＋ 句尾那枚问号：把「页面里那段长说明」压成这一种的现成形状。
///
/// 正文（[helpBody]）就是原来那句长说明，原样搬进弹窗 —— 删掉的只是它在正文里占的位置。
class HelpNoteRow extends StatelessWidget {
  const HelpNoteRow({
    super.key,
    required this.noteKey,
    required this.helpKey,
    required this.text,
    required this.helpTitle,
    required this.helpBody,
  });

  /// 短说那一行的 ValueKey 名（沿用原来那条说明的 key，用例不必跟着改）。
  final String noteKey;
  final String helpKey;
  final String text;
  final String helpTitle;
  final String helpBody;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              text,
              key: ValueKey(noteKey),
              style: TextStyle(
                fontSize: 13,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ),
          const SizedBox(width: 6),
          HelpNoteButton(keyName: helpKey, title: helpTitle, body: helpBody),
        ],
      ),
    );
  }
}
