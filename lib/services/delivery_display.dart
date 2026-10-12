import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

/// 送达状态那一格的**词表→人话**唯一作者（T150 片1）。
///
/// 病灶不是措辞，是 `default:`：此前它是那张表上最后一句「发送中」。于是任何一个
/// 对不上号的状态串 —— 词表外的新值、写坏的旧值、将来加的一档 —— 都会被界面替本机
/// 说成「这条正在发」。与维护者 T150 第 6 条同一类：暂停中的记录一路停在 `pending`，
/// 界面就一直报「发送中」，而那台设备根本没把这条交给任何发送器。
///
/// ⚠ 「发送中」只许在**真的在途**时说（`pending` 那一档，见下面那条注释）；
/// ⚠ 认不出的也不许一律说「已暂停」—— 那会把正在重推的那几条说成没发（同一个错的反方向）。
/// 两头的错共用同一个解：**说不认得**。这与 T01（首页不许恒绿）、T115（未知不是红灯也不是绿灯）
/// 是同一条纪律换了个位置。
String deliveryStatusText(AppLocalizations l10n, String status) {
  switch (status) {
    case 'success':
      return l10n.deliverySuccess;
    case 'failed':
      return l10n.deliveryFailed;
    case 'intercepted':
      return l10n.deliveryIntercepted;
    case 'paused':
      // T138 ③：「已暂停」只说用户动了开关，没说**这条的下场** —— 那一格要回答
      // 的是"这条发出去没有"：暂停期间根本没发。与 failure 同一档的措辞密度。
      return l10n.deliveryPausedNotSent;
    case 'pending':
      // 这一句现在只有一个来源：入库瞬间写下的初值，且**只有还会被人来回执的键**才该被写进去
      // （见 `deliveryKeysOfActiveChannels` 把 `role=none` 筛掉那一条）。
      // 初值与"在途"因此是同一件事 —— 以前不是：不参与推送的通道也领了一个 `pending`，
      // 而没有任何回执会来推离它，这一格就永远替本机说了一句「发送中」。
      return l10n.deliveryPending;
    default:
      return l10n.deliveryUnknown;
  }
}

/// 同一张表的**点色与字色**（与 [deliveryStatusText] 同一次判定，不许两处各判一遍）。
///
/// ⚠ 这一位的 `default:` 以前是蓝（在途那一档的颜色）：状态词认不出时，界面一边写着
/// 「发送中」一边画着在途的蓝点，两句谎互相壮胆。未知就该是未知的那副脸色。
Color deliveryStatusColor(BuildContext context, String status) {
  return switch (status) {
    'success' => AppColors.green,
    'failed' => AppColors.red,
    'intercepted' => AppColors.orange,
    'paused' => AppColors.orange,
    'pending' => AppColors.blue,
    _ => AppColors.systemGray(context),
  };
}
