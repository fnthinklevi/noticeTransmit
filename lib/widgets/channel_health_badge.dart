import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/active_channels.dart';
import '../services/channel_health_store.dart';
import '../theme/app_colors.dart';

/// 「多久之前」的**分档**口径（T115 立的那一条：不足 1 小时说分钟，否则说小时）。
///
/// 为什么单列出来：这一把尺原来只有健康度在用，而 T110 的配对两面（「我发起给谁、多久之前」/
/// 「谁在请求配对你、多久之前」）也要说同一件事。两处各写一份 `<1h ? 分 : 时` 的下场就是
/// T115 记下过的那类缺陷 —— 同一条记录，首页说 3 天前、状态页说 72 小时前。
/// 措辞各归各的主语（健康度那句是"探测"，配对那句是"发起"），所以这里收的是**时长**，
/// 由调用方挑自己的那个词。
///
/// `atMs` 为 null 或 `<= 0` ⇒ null：拿不出时刻就说"不知道"，**不许**糊成"0 分钟前"。
({bool inHours, int value})? fnthinkAgoBucket(int? atMs) {
  if (atMs == null || atMs <= 0) return null;
  // `atMs` 可能来自落盘数据或服务端：设备改过时钟就可能回来一个未来时刻，负数会被
  // 说成"-3 分钟前"，所以先夹到 0（同一句"不知道"的方向）。
  final ago = math.max(0, DateTime.now().millisecondsSinceEpoch - atMs);
  if (ago < 60 * 60 * 1000) {
    return (inHours: false, value: ago ~/ (60 * 1000));
  }
  return (inHours: true, value: ago ~/ (60 * 60 * 1000));
}

/// 配对那两张表上的「多久之前」（T110）。拿不出时刻就返回 null —— 调用方那一行
/// 要么不说时间，要么走 [fnthinkFormatTime] 那个 '—'，两种都不许造出一个时刻。
String? fnthinkAgoLabel(AppLocalizations l10n, int? atMs) {
  final bucket = fnthinkAgoBucket(atMs);
  if (bucket == null) return null;
  return bucket.inHours
      ? l10n.agoHours(bucket.value)
      : l10n.agoMinutes(bucket.value);
}

/// 「上一次探测是多久以前」这句话的**唯一**格式化处（T115）。
///
/// 为什么必须有作者：决定一把"过期"从 `unknown` 里拆出来之后，这一句从"徽标的补充说明"
/// 变成了**结论的一部分** —— 凡是画过期结论的地方都必须带上它（只说正常不带上次时间，
/// 就是那句禁令禁的谎）。各处再抄一份「<1 小时用分钟、否则用小时」的分支，就会出现
/// "首页说 3 天前、状态页说 72 小时前"，而那是同一条记录。
///
/// 拿不出时间（没记录，或 `probedAt <= 0` —— email 旧缓存搬进来的那种"有结果没时间"）
/// 就返回 null：**调用方不许**把 null 糊成"0 分钟前"，那正好造出一句假话。
String? channelHealthAgoLabel(AppLocalizations l10n, int? probedAt) {
  final span = fnthinkAgoBucket(probedAt);
  if (span == null) return null;
  return span.inHours
      ? l10n.healthProbedHours(span.value)
      : l10n.healthProbedMinutes(span.value);
}

/// 通道卡上的健康徽标：✓ 可达（含耗时）/ ✗ 不可达 / 上次的正常结论 + 多久之前 / ? 状态未知。
///
/// 此前这里是**两份抄本**（自建应用页与 webhook 页各一份），并且都只看 `reachable`
/// 一个布尔 ⇒ 一条六个月前的成功照样画绿勾。判定统一走 [channelHealthStateForDisplay]
/// （显示侧那一条，带"过期必须说得出时间"的契约），本组件只负责显示形状。
///
/// 没有探测记录时画 `SizedBox.shrink()`：从没测过就什么都不断言（T01 的口径）。
class ChannelHealthBadge extends StatelessWidget {
  const ChannelHealthBadge({super.key, required this.health, this.absentText});

  final ChannelHealth? health;

  /// 「此刻没有记录」要不要在屏幕上说一句话（T103）。
  ///
  /// 默认 null = **不吭声**：另外三族有非侵入探针（只换 token、只握手），过一轮就有记录，
  /// 从没探过只是"还没来得及"，不该在行上立个牌子。
  ///
  /// 幻念通道那一族是例外，但例外的**理由换过两次**（T106 片①b 格2 之后）：它现在两条路都有了
  /// —— 设备档走签名探针（`POST /probe`），端点档走干跑（`POST /p/<id>/probe` + Bearer 口令），
  /// 两条都一条都不投。可**第三方 webhook 目标**（NAS 自己的口、Slack 那种）协议里根本没有
  /// "问一句收不收得进"这一发，硬探就等于真推一条。所以那一族出现空白行时，
  /// "这条测过、结果是没通"与"这条没法测"仍是两件事，必须由调用方把话说出来，
  /// 而不是让行保持空白。
  final String? absentText;

  @override
  Widget build(BuildContext context) {
    final h = health;
    if (h == null) {
      final absent = absentText;
      if (absent == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.help_outline,
              size: 14,
              color: AppColors.tertiaryLabel(context),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                absent,
                key: const ValueKey('channel-health-absent'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.tertiaryLabel(context),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final l10n = AppLocalizations.of(context);
    final agoText = channelHealthAgoLabel(l10n, h.probedAt);
    final (icon, text, color) = switch (channelHealthStateForDisplay(h)) {
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
      // 上次是通的，但那已经过了时效：敢说"正常"是因为旁边就写着"上次探测于 X 前"。
      // ⚠ 刻意**不**复述耗时 —— 那是上一次那一发量到的数，它现在多快我们并不知道。
      // 也不涂灰：涂灰是"不知道"，而这里知道的是"上次通、结论旧"。
      ChannelHealthState.stale => (
        Icons.check_circle_outline,
        l10n.statusOk,
        AppColors.green,
      ),
      ChannelHealthState.unknown => (
        Icons.help_outline,
        l10n.statusUnknown,
        AppColors.tertiaryLabel(context),
      ),
    };
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
          // 时间那一句可以没有（`probedAt <= 0`：旧 `email_test_results` 搬进来的那种
          // "有结论没时间"）—— 没有就不画，绝不糊成"0 分钟前探测"。
          // ⚠ 而过期那一档恰恰**必须**有它：缺时间时 `channelHealthStateForDisplay` 已经把
          // 这一格退回成"未知"了，所以这里不可能画出"正常"却不带时间的那副样子。
          if (agoText != null) ...[
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
        ],
      ),
    );
  }
}
