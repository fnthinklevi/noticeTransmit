import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 历史记录那一行的**通用件**（T148，维护者 2026-10-12 第 3 条：
/// 「抽象当前软件首页历史记录的格式，后面其他模块要新增历史记录页了，都按推送历史的样式和内容来」）。
///
/// ## 基座是谁
/// 不是新设计的形状，是 `history_page.dart` 里那条**转发行**的形状照抄出来的：
/// 36×36 首字母盒 → 标题行（前置徽标 + 单行省略的标题 + 右对齐时间）→ 正文一行 → 来源一行
/// → 状态一枚（圆点 + 9px 词）→ 页面自己往下挂的行（通道 chip、结果/理由、动作）。
///
/// ## 为什么值得抽
/// 维护者点名的不是"难看"，是**同一类事实四页各长一遍**后彼此漂移：
/// 八处差异（roadmap T148 行里那份清单）里最伤的两条是
/// ②「时间列不一致 —— 远程执行那页根本没时间」与
/// ③「状态三套画法，其中一套用字符串拼在正文里、并且拿 `default:` 兜底」。
/// 这两条都住在本件里，所以修一次四页都改到。
///
/// ## 边界（不许塞进来的东西）
/// 通道 chip、重推按钮、批量勾选这些**推送特有**的行内容一律由调用方经 [lines] 挂进来：
/// 通用件不认得"通道"，正如它不该认得"远程执行"。反过来，页面也不许再自己拼一份行
/// （字号、行距、圆角、状态画法一旦各写一份，就是 T148 清单上的那八条重新长出来）。
class HistoryRowTile extends StatelessWidget {
  const HistoryRowTile({
    super.key,
    required this.keyNamespace,
    required this.identity,
    required this.title,
    this.time,
    this.subtitle,
    this.source,
    this.badges = const <Widget>[],
    this.leadingLabel,
    this.leadingColor,
    this.status,
    this.statusColor,
    this.statusMessage,
    this.lines = const <Widget>[],
    this.onTap,
    this.onLongPress,
    this.corner = HistoryRowCorner.middle,
  });

  /// key 的命名空间（`'remote-history'`、`'history'`…）。
  ///
  /// 统一的是**形状**，不是各页的 key 字符串：闸门与用例按 key 定位（"改文案就瞎"那颗），
  /// 把四页的 key 合成一个前缀会让既有证据全数失效，而那不是本片要付的代价。
  final String keyNamespace;

  /// 这一行讲的是哪一条（id / messageId / execId —— 主语由页面定，组件只加前缀）。
  final String identity;

  final String title;

  /// 右对齐那一格。**null = 不画**（不许画一个空串占位：那读起来像"这条没有时间"，
  /// 而真话通常是"这一页还没把时间接进来"）。
  final String? time;

  /// 标题下面那行正文摘要（**单行**、省略号）。
  ///
  /// 这一格是基座那页（转发行）本来就有的形状：内容空就不画。
  /// 不许借它塞状态词 —— 状态走 [status]，画法唯一。
  final String? subtitle;

  /// 第三行小字：谁发的 / 发给谁 / 哪台。
  final String? source;

  /// 标题前的徽标（优先级、未读点……）。
  final List<Widget> badges;

  /// 首字母盒（`null` 就不画盒子，标题自然左移）。
  final String? leadingLabel;
  final Color? leadingColor;

  /// 状态：词 + 色，画法唯一（圆点 + 9px 词）。
  ///
  /// ⚠ 词**必须由调用方那张词表的唯一作者给**（推送侧 `deliveryStatusText`、
  ///   远程执行侧 `_stateText`）。本件只负责"怎么画"，不认识任何状态词 ——
  ///   在组件里再写一遍 switch 就是第五套画法。
  final String? status;
  final Color? statusColor;

  /// 状态下面那句"状态原话"（失败原因／拦截理由）。两行、可折行：
  /// 截成一行的话 `HTTP 502 …` 与 `SMTP connect timeout` 长得一样，等于没写。
  final String? statusMessage;

  /// 页面自己挂的行（通道 chip、动作、副标题）。
  final List<Widget> lines;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 圆角：整组卡片是连着的，首尾各留 12，中间不留 —— 这个口径以前只在转发行里有一份。
  final HistoryRowCorner corner;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Row(
        children: [
          for (final b in badges) ...[b, const SizedBox(width: 6)],
          Expanded(
            child: Text(
              title,
              key: ValueKey('$keyNamespace-title-$identity'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.primaryLabel(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (time != null && time!.isNotEmpty)
            Text(
              time!,
              key: ValueKey('$keyNamespace-time-$identity'),
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondaryLabel(context),
              ),
            ),
        ],
      ),
      if (subtitle != null && subtitle!.isNotEmpty) ...[
        const SizedBox(height: 3),
        Text(
          subtitle!,
          key: ValueKey('$keyNamespace-subtitle-$identity'),
          style: TextStyle(
            fontSize: 13,
            color: AppColors.secondaryLabel(context),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
      if (source != null && source!.isNotEmpty) ...[
        const SizedBox(height: 3),
        Text(
          source!,
          key: ValueKey('$keyNamespace-source-$identity'),
          style: TextStyle(
            fontSize: 11,
            color: AppColors.secondaryLabel(context),
          ),
        ),
      ],
      if (status != null && status!.isNotEmpty) ...[
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: ValueKey('$keyNamespace-status-dot-$identity'),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                status!,
                key: ValueKey('$keyNamespace-status-$identity'),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
      ],
      if (statusMessage != null && statusMessage!.isNotEmpty) ...[
        const SizedBox(height: 1),
        Text(
          statusMessage!,
          key: ValueKey('$keyNamespace-status-message-$identity'),
          style: TextStyle(fontSize: 10, color: statusColor),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
      for (final l in lines) ...[const SizedBox(height: 4), l],
    ];

    return InkWell(
      key: ValueKey('$keyNamespace-row-$identity'),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(corner.topLeft ? 12 : 0),
            topRight: Radius.circular(corner.topRight ? 12 : 0),
            bottomLeft: Radius.circular(corner.bottomLeft ? 12 : 0),
            bottomRight: Radius.circular(corner.bottomRight ? 12 : 0),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (leadingLabel != null && leadingColor != null) ...[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: leadingColor!.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    leadingLabel!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: leadingColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一行在整组卡片里的位置（决定哪两个角要圆）。
enum HistoryRowCorner {
  only(true, true, true, true),
  first(true, true, false, false),
  middle(false, false, false, false),
  last(false, false, true, true);

  const HistoryRowCorner(
    this.topLeft,
    this.topRight,
    this.bottomLeft,
    this.bottomRight,
  );

  final bool topLeft;
  final bool topRight;
  final bool bottomLeft;
  final bool bottomRight;
}

/// 历史行的时间那一格 —— **唯一作者**（T148 差异②）。
///
/// 此前 `history_page` 与 `device_snapshot_page` 各写一份 `MM-dd HH:mm`（形状恰好一样），
/// 而远程执行那一页**根本没有时间**：不是漏了一列，是那一页没有可借的那一支笔。
/// 0 与 null 都回空串（调用方据此**不画那一格**，别画一个 1970）。
String historyRowTime(int? ms) {
  if (ms == null || ms == 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}
