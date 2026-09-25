import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/active_channels.dart';
import '../services/channel_health_store.dart';
import '../theme/app_colors.dart';

/// 通道卡上的健康徽标：✓ 可达（含耗时）/ ✗ 不可达 / ? 状态未知 + 距上次探测多久。
///
/// 此前这里是**两份抄本**（自建应用页与 webhook 页各一份），并且都只看 `reachable`
/// 一个布尔 ⇒ 一条六个月前的成功照样画绿勾，而首页与通道状态页按三态判（过期算
/// unknown）——"设置页说正常、首页说未知"的互相打脸就是这么来的。三态判定统一走
/// [channelHealthState]，本组件只负责显示形状。
///
/// 没有探测记录时画 `SizedBox.shrink()`：从没测过就什么都不断言（T01 的口径）。
class ChannelHealthBadge extends StatelessWidget {
  const ChannelHealthBadge({super.key, required this.health});

  final ChannelHealth? health;

  @override
  Widget build(BuildContext context) {
    final h = health;
    if (h == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final (icon, text, color) = switch (channelHealthState(h)) {
      ChannelHealthState.ok => (
        Icons.check_circle,
        l10n.healthReachable(h.latencyMs),
        AppColors.green,
      ),
      ChannelHealthState.error => (
        Icons.cancel,
        l10n.healthUnreachable,
        AppColors.red,
      ),
      // 有记录但已过期：不替用户宣称"正常"，也不吓人地报故障
      ChannelHealthState.unknown => (
        Icons.help_outline,
        l10n.statusUnknown,
        AppColors.tertiaryLabel(context),
      ),
    };
    final ago = DateTime.now().millisecondsSinceEpoch - h.probedAt;
    final agoText = ago < 60 * 60 * 1000
        ? l10n.healthProbedMinutes(ago ~/ (60 * 1000))
        : l10n.healthProbedHours(ago ~/ (60 * 1000));
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      // ⚠ 两段文字都必须是 Flexible：这条徽标挂在列表行副标题里，可用宽度只有 ~170dp，
      // 而"连通 · 42 ms" + "0 分钟前探测"加起来更宽 —— 不换行也不收缩就会
      // `RenderFlex overflowed by 43 pixels`（T07-B 模拟器闸门实测出来的，手机宽度才现形，
      // 桌面尺寸的 widget 测试看不见）。flex: loose ⇒ 放得下时按自然宽度，放不下才缩略。
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              agoText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
