import 'package:flutter/cupertino.dart';
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

/// 形状① 的**行内次要动作**（T100 判据② 第一刀）：一枚蓝字小按钮，对"行里那个值"做点什么
/// （复制、重置）。
///
/// 它**不是**主操作（那走 `PrimaryActionButton`，一页最多一枚），也**不是**"进一页的行"
/// （那走 `FnthinkEntryRow`）。§1 把这一族的合法形状收成三种之后，"复制这个口令"这类动作
/// 一直没归属 —— 于是三处各写一枚裸 `TextButton`，字号、左右留白、禁用态各是各的。
///
/// `onPressed` 传 null = 此刻不可用（例如手上还没有那段东西）：**置灰，不是藏起来** ——
/// 藏起来用户会以为这一页没有这个功能。
///
/// T108：颜色按**功能语义**分，不按"这看起来是个链接"分 —— 关掉一把端点与复制它的 id
/// 不是同一类决定，画成同一个蓝就是把"不可逆"藏在"可逆"旁边。
enum FnthinkActionTone {
  /// 往前走一步（批准、发一条、建一个、改地址）：主色。
  action,

  /// 可逆、看一眼动一下（复制、读一次、恢复默认）：中性字色。
  neutral,

  /// 会让某个东西从此不可用（关掉、撤销、换掉口令、拒绝）：红。
  destructive,
}

class FnthinkInlineAction extends StatelessWidget {
  const FnthinkInlineAction({
    required this.label,
    required this.onPressed,
    this.tone = FnthinkActionTone.action,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final FnthinkActionTone tone;

  /// 语义 → 颜色的**唯一作者**：页面不许自己挑蓝/红（一处自挑一次，下一处就漏一次）。
  /// 用例也读这一枚，不另抄一份颜色表。
  static Color colorOf(
    BuildContext context,
    FnthinkActionTone tone,
    bool enabled,
  ) {
    if (!enabled) return AppColors.tertiaryLabel(context);
    switch (tone) {
      case FnthinkActionTone.destructive:
        return AppColors.systemRed(context);
      case FnthinkActionTone.neutral:
        return AppColors.secondaryLabel(context);
      case FnthinkActionTone.action:
        return AppColors.systemBlue(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      onPressed: onPressed,
      // 行内动作不该把行撑高：上下留 2 而不是 CupertinoButton 默认那一大圈。
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      minimumSize: Size.zero,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          color: colorOf(context, tone, onPressed != null),
        ),
      ),
    );
  }
}

/// 实心（填充）动作那一档：按内容宽度、可带图标、可置灰（T148 片15）。
///
/// 为什么不复用 `PrimaryActionButton` 再给它补一个图标槽（那正是片8 留在账面上的原路）：
/// 那一件是**一页一枚的全宽主操作**（`width: double.infinity`），而这两枚都不是 ——
/// 行内那枚贴在 10px 的通道 chip 旁边，底栏那枚与「取消」共用一行。给全宽件加参数要同批
/// 核它 9 个既有调用点的形状一致性；丢图标是拿可读性换账面整齐。两条都比新开一件贵，
/// 所以钉成两件并互相划界：这一件不许长成全宽，那一件不许长出图标槽（`ui_style_guards` 两条）。
///
/// `onPressed` 传 null = **置灰留着**，不藏起来（藏掉之后用户读到的是"这里没这个功能"），
/// 与 [FnthinkInlineAction] 同一语义。
///
/// `compact` 的两档尺寸各自来自一处实测（行内 11px／radius 6 · 底栏 15px／radius 10）：
/// 行内那一档必须用 compact —— 常规档会把刚在片1〜3 统一过的行高顶起来。
class FnthinkFilledAction extends StatelessWidget {
  const FnthinkFilledAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.compact = false,
    super.key,
  });

  final String label;

  /// null = 此刻做不了（还没勾选、前置没开）：画成灰的，不是不画。
  final VoidCallback? onPressed;

  /// 留空 = 纯文字实心钮。「把这 N 条再发一次」这类动作有一半信息量在图标上。
  final IconData? icon;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final foreground = onPressed == null
        ? AppColors.tertiaryLabel(context)
        : Colors.white;
    return CupertinoButton(
      onPressed: onPressed,
      // 留白在这层定：交给 CupertinoButton 的默认 padding，"按内容宽"这件事会在下一张页重商量一遍。
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 16,
          vertical: compact ? 4 : 10,
        ),
        decoration: BoxDecoration(
          color: onPressed == null
              ? AppColors.separator(context)
              : AppColors.blue,
          borderRadius: BorderRadius.circular(compact ? 6 : 10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: compact ? 11 : 18, color: foreground),
              SizedBox(width: compact ? 3 : 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: compact ? 11 : 15,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 行内那一枚**不可点**的状态标记（T148 片16 的唯一作者）。
///
/// 这一族此前有三份各自长法：`history_page._tagBadge`（10px／radius 4／w600／无描边）、
/// 通道 chip 的壳（10px／radius 3／normal／淡底 0.12，里面再抄一份 9px 次级字与 6px 圆点）、
/// `channel_status_page._RoleBadge`（11px／radius 4／**带描边**）。留着的钱不是"丑"，是
/// **下一枚徽标又会从这三份里挑一份抄**，而私有的 `_RoleBadge` 那种壳连"别变多"都没人管
/// （全族扫描那把尺当时只认名以 `Chip` 结尾的类）。
///
/// 三档按**主语**分，不按参数自由配 —— 这是这一片要你点头的那件事的落地：
/// - [FnthinkMarkRole.attribute]：「这一条有什么额外要标的」（高优／备用）；
/// - [FnthinkMarkRole.channel]：「这一条走了哪条通道」，可挂 [submarks]（次级字与状态圆点）；
/// - [FnthinkMarkRole.tier]：「这一项处在哪一档」（主／备／未设置／不参与）。
/// ⚠ **描边只给 tier 档**：另两档是附注，画上线等于在说"这是一个可对照的档位"，而它不是；
///   反过来 tier 档去掉描边，"主"与"未设置"就只剩颜色差 —— 那是 T108 片② 与本仓片12 各量过一次的病
///   （只有颜色差 ⇒ 读不出这一项到底在哪一档）。
///
/// ⚠ 这一枚**没有 `onTap`，也不该加**：它是读数不是入口（片14 那条族规矩：同一行里"能点的那一枚"
///   与"只是状态的标记"不许互换形状）。要动作走 [FnthinkInlineAction]／[FnthinkFilledAction]。
enum FnthinkMarkRole { attribute, channel, tier }

/// 徽标里那句**次级字**（「备用」这种附注、或「成功／失败／发送中」这种状态读数）。
///
/// 两个构造子按"有没有圆点"分，而不是给个布尔让人乱配：带点的那一枚是状态读数，
/// 今天就是 w500（它要回答"这条发出去没有"，弱化它等于把失败说轻）；不带点的是附注。
class FnthinkSubMark {
  const FnthinkSubMark.text(this.label, this.color) : dotColor = null;

  const FnthinkSubMark.dot(this.label, Color markColor)
    : dotColor = markColor,
      color = markColor;

  final String label;
  final Color color;

  /// 非 null ⇒ 前面画一枚实心圆点（这一枚取 w500）。
  final Color? dotColor;
}

class FnthinkStatusMark extends StatelessWidget {
  const FnthinkStatusMark({
    required this.role,
    required this.label,
    required this.color,
    this.submarks = const <FnthinkSubMark>[],
    this.filled = true,
    super.key,
  });

  final FnthinkMarkRole role;
  final String label;

  /// 这一枚的主色（attribute／channel 档用它上色；tier 档实心时用它描边）。
  final Color color;

  final List<FnthinkSubMark> submarks;

  /// 只给 [FnthinkMarkRole.tier] 用：false ＝ 透明底 + 分隔线描边（「备／未设置／不参与」这些
  /// 没被选中的档位，今天就是不上色的）。另两档忽略它。
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final double hPad;
    final double vPad;
    final double radius;
    final double fontSize;
    final FontWeight weight;
    switch (role) {
      case FnthinkMarkRole.attribute:
        hPad = 4;
        vPad = 1;
        radius = 4;
        fontSize = 10;
        weight = FontWeight.w600;
      case FnthinkMarkRole.channel:
        hPad = 5;
        vPad = 1;
        radius = 3;
        fontSize = 10;
        weight = FontWeight.normal;
      case FnthinkMarkRole.tier:
        hPad = 6;
        vPad = 2;
        radius = 4;
        fontSize = 11;
        weight = FontWeight.normal;
    }
    // 描边只在这一档出现（第二道判据钉的就是这一位）。
    final bool bordered = role == FnthinkMarkRole.tier;
    final Color foreground = bordered && !filled
        ? AppColors.secondaryLabel(context)
        : color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: bordered
            ? filled
                  ? color.withValues(alpha: 0.14)
                  : Colors.transparent
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(radius),
        border: bordered
            ? Border.all(color: filled ? color : AppColors.separator(context))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              height: bordered ? 1.2 : null,
              fontWeight: weight,
              color: foreground,
            ),
          ),
          for (final sub in submarks) ...[
            const SizedBox(width: 3),
            if (sub.dotColor != null) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: sub.dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 2),
            ],
            Text(
              sub.label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: sub.dotColor == null
                    ? FontWeight.normal
                    : FontWeight.w500,
                color: sub.color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 形状①「行」的**唯一装配点**（T100 片2）：整行可点 · 左图标块 · 标题（＋可选一句副标题）· 右箭头。
///
/// 为什么收成一件而不是各页各搭：§1 把这一族合法形状定成三种（行／弹层里的动作行／主操作填充），
/// 而"进一页"这一类当时并存两份抄本 —— 通知引擎 hub 那三行自己搭 `InkWell`＋`MaterialPageRoute`，
/// 接收页远程执行那三行是裸 `TextButton`（蓝字无框）。两张页会被连着看（引擎 → 接收 → 那三行），
/// 两份各自长下去，同一件事就是两种形状、两种点法、两种转场。
///
/// `onTap` 允许 null：那一行灰掉、点不动（接收页在 `_busy` 时就是这个状态）。换件时必须把这个
/// 语义一起搬过来 —— 旧写法靠 `TextButton(onPressed: null)`，漏了它就会在忙的时候还能点进去。
///
/// `subtitle` 可空：有的行确实只有一句话可说。这一格留空是版式，不是"忘了写"。
class FnthinkEntryRow extends StatelessWidget {
  const FnthinkEntryRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
    this.subtitle,
    super.key,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      onPressed: onTap,
      // 行距在这层定，不交给 CupertinoButton：默认 padding 会让每行高度随内容长短变，
      // 而"同页对齐"判的就是同一张页上几行的高度一致。
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryLabel(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.tertiaryLabel(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一排**可选项**里的一枚（T108 片②：从发送页那四枚各搭一遍的 `CupertinoButton` 抬上来）。
///
/// 形状是原 `_TierButton`：选中＝蓝底描边＋加粗；不可用＝置灰但**留着**（藏起来用户会以为
/// 这一档压根不存在）。抬上来之前，「选一台设备／选一档能力／选一个动作」那三排是裸文字，
/// 选中态只有一点点字重差 —— 于是"我到底选上没有"这件事在屏上读不出来，而它正是
/// 「点了没反应」那类误报的来源（维护者 2026-10-08 第 2 条要的就是这个）。
class FnthinkChoiceChip extends StatelessWidget {
  const FnthinkChoiceChip({
    required this.keyName,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String keyName;
  final String label;
  final bool selected;

  /// null = 此刻挑不动（正在忙／前置没开）：置灰，不是藏起来。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final blue = AppColors.systemBlue(context);
    return CupertinoButton(
      key: ValueKey(keyName),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? blue.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? blue : AppColors.separator(context),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: onTap == null
                ? AppColors.tertiaryLabel(context)
                : selected
                ? blue
                : AppColors.primaryLabel(context),
          ),
        ),
      ),
    );
  }
}

/// 「点开再挑」那一类字段行（T108 片②：原通道设置页的私有 `_FieldButton`）。
///
/// 与 [FnthinkEntryRow] 不是一件东西：行是"进另一张页"，这一枚是**就地改一个值**
/// （输入底色 + 行首图标 + 当前值 + 右箭头，与 webhook 那一族的类型选择框同形）。
/// 仍是 `CupertinoButton`：禁用态要用例点得中，而用例认的是这一件。
class FnthinkFieldTile extends StatelessWidget {
  const FnthinkFieldTile({
    required this.keyName,
    required this.icon,
    required this.value,
    required this.onTap,
    super.key,
  });

  final String keyName;
  final IconData icon;
  final String value;

  /// null = 此刻挑不动：**置灰，不是藏起来**。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dim = onTap == null;
    return CupertinoButton(
      key: ValueKey(keyName),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.inputBg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.separator(context)),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: dim ? AppColors.tertiaryLabel(context) : AppColors.blue,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                key: ValueKey('$keyName-value'),
                style: TextStyle(
                  fontSize: 14,
                  color: dim
                      ? AppColors.tertiaryLabel(context)
                      : AppColors.primaryLabel(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.tertiaryLabel(context),
            ),
          ],
        ),
      ),
    );
  }
}
