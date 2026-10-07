import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

/// 复制一段东西并当场说一句"已复制"（T97 片B：两张幻念页共用这一枚装配点）。
///
/// 为什么要有它：`_copy` 原来各页写一份，于是"把一张页搬成两张"就顺手"多出一处轻提示"——
/// 而 SnackBar 这一族在 Cupertino 下还没有定过换法（T90 补册那本账记的就是它），
/// 多一处就多一处没人认领的。收成一处，换法定下来的那天只有一处要改。
///
/// ⚠ 页面别再自己拼 `Clipboard.setData` + `showSnackBar`：那本台账按**文件**计枚数，
///   多一个文件就要多登记一格，而每一格都是一笔将来要还的形状债。
Future<void> fnthinkCopyNotice(BuildContext context, String text) async {
  final l10n = AppLocalizations.of(context);
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(l10n.fnthinkCopied),
      duration: const Duration(seconds: 1),
    ),
  );
}

/// 名单/端点那些行上的时刻（`grantedAt`、轮换宽限期都是毫秒）。
///
/// 0/负数 ⇒ '—'：显示 1970-01-01 会把"这一行没有时间"伪装成"很久以前同意过"。
///
/// 为什么提到共享件：T94 把它搬成独立页之后，**两页都在显示同一个时刻**
/// （绑定名单那一列、端点换口令那把的宽限期）。各留一份就是同一个格式的两个作者 ——
/// 改了一处，另一页就会显示另一个日子，而两页都在同一次使用里被人对照着看。
String fnthinkFormatTime(int ms) {
  if (ms <= 0) return '—';
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// 幻念那几页共用的四个小片段（T94 片1 从 `fnthink_settings_page.dart` 抽出来的）。
///
/// 为什么要抽成公共件：幻念推送分两块之后（推送引擎那侧收渠道·绑定·发起·接收·远程，
/// 更多页那处只留渠道信息），「一张卡 + 几行原话」这个版式被两个页面同时用 ——
/// 留在页面里当私有类就得抄第二份，而抄出来的第二份改一处就会与第一份慢慢分叉
/// （本仓为同一件事的两个实现付过太多代价）。
///
/// `keyName` 一律落到 `ValueKey` 上：这些行的断言全靠 key 找
/// （"配好了没有"、"那句话是不是原话"这类判据不能靠文案找，文案会漂）。
class FnthinkCard extends StatelessWidget {
  const FnthinkCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryLabel(context),
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// 运行状态那一行：圆点 + 一句话。点亮的颜色**只**跟着 `dot`。
class FnthinkStatusRow extends StatelessWidget {
  const FnthinkStatusRow({
    super.key,
    required this.keyName,
    required this.dot,
    required this.text,
  });

  final String keyName;
  final bool dot;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            key: ValueKey('$keyName-dot'),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dot ? AppColors.green : AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              key: ValueKey(keyName),
              style: TextStyle(
                fontSize: 13,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一段小标题（组内几行的名目）。
class FnthinkRowLabel extends StatelessWidget {
  const FnthinkRowLabel({
    super.key,
    required this.label,
    required this.keyName,
  });

  final String label;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        key: ValueKey(keyName),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.secondaryLabel(context),
        ),
      ),
    );
  }
}

/// 那些"原话贴出来"的行（启停原因、上一轮的账、校验失败）。
class FnthinkNote extends StatelessWidget {
  const FnthinkNote({super.key, required this.keyName, required this.text});

  final String keyName;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        key: ValueKey(keyName),
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: AppColors.secondaryLabel(context),
        ),
      ),
    );
  }
}
