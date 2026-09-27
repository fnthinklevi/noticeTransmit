import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

/// 通知引擎三族设置页（电量 / 温度 / 设备状态）共用的版式。
///
/// 为什么抽出来：这套"顶部大读数 + 分组标题 + 卡片分组 + 开关行 + 说明条目"只有电量页有，
/// 温度页是一屏裸列表、设备状态页是两行说明加卡片 —— 三页看着像三个产品。维护者要求统一
/// 以电量页为准（1.5.76 之后的样式反馈）。留在三处各写一份，改一处字号就会永久漂成三种。
///
/// 这里只放**版式**：读数从哪来、点下去调哪个服务，一概留在各页。
class EngineReadoutHeader extends StatelessWidget {
  const EngineReadoutHeader({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.caption,
    this.detail,
  });

  final IconData icon;
  final Color iconColor;

  /// 大号读数（如 `80%` / `41.3℃` / `62%`）。
  /// ⚠ 读不到时由调用方传"这台设备读不到"那类文案 —— 画一个 0 或留空白，
  ///   用户会读成"真的是 0"（快照页同一口径，见 `unreadableField`）。
  final String value;

  /// 这个数是谁的（"充电中" / "电池温度" / "屏幕亮度"）。
  final String caption;

  /// 可选第二行（设备状态页放网络）。没有就不占位，保持与电量页同高。
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Icon(icon, size: 80, color: iconColor),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w300,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: TextStyle(
              fontSize: 15,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                detail!,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.tertiaryLabel(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 一个分区：标题 + 卡片。[divided] 为真时在相邻条目之间插分隔线
/// （规则列表用 `divided: true`，单条开关用默认的 `false`）。
class EngineSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool divided;
  const EngineSection({
    super.key,
    required this.title,
    required this.children,
    this.divided = false,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && divided) rows.add(EngineDivider(context: context));
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ),
        // 分组卡本身是 Material：ListTile / InkWell 的水波纹只画在**最近的不透明
        // Material** 上，卡底色放在外层 Container 的 BoxDecoration 里就会把波纹压到背景之下
        // （本仓库在设备状态页与 CardActionSheet 上各撞过一次，别再让第三页踩）。
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: AppColors.cardBg(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ),
      ],
    );
  }
}

class EngineDivider extends StatelessWidget {
  final BuildContext context;
  const EngineDivider({super.key, required this.context});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: AppColors.separator(context),
      ),
    );
  }
}

/// 分区里的开关行（三族的"提醒总开关"都是这一种形状）。
class EngineSwitchRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? trailing;
  final BuildContext context;
  const EngineSwitchRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.context,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ],
            ),
          ),
          trailing ?? const SizedBox.shrink(),
          CupertinoSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 说明区的一条（小圆点 + 文本）。
class EngineNoteRow extends StatelessWidget {
  final String text;
  final BuildContext context;
  const EngineNoteRow({super.key, required this.text, required this.context});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: AppColors.tertiaryLabel(this.context),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppColors.secondaryLabel(this.context),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

/// 网络类型的口语名。**从快照页搬过来共用**：同一份枚举在两页各翻译一次，
/// 迟早会出现"快照页说 VPN、告警页说其他"这种互相打脸。
///
/// 未知枚举原样显示：宁可看见生词，也不要把它翻译成"其他"再让人以为已经归类。
String? engineNetworkLabel(String? type, AppLocalizations l10n) =>
    switch (type) {
      'wifi' => l10n.netWifi,
      'cellular' => l10n.netCellular,
      'vpn' => l10n.netVpn,
      'ethernet' => l10n.netEthernet,
      'none' => l10n.netNone,
      'other' || null => type == null ? null : l10n.netOther,
      _ => type,
    };
