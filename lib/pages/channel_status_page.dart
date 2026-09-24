import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../services/active_channels.dart';
import '../services/channel_display.dart';
import '../services/channel_health_store.dart';
import '../theme/app_colors.dart';

/// 通道状态页（T10）：首页「当前推送通道」那点进来，按三族分组列出**已启用**的通道，
/// 每行给「通道名 · 类型 · 关键链接 · 最近一次探测」，点一行直接进那条通道的配置页。
///
/// 为什么单独一页而不是就在家常的首页卡里铺开：首页那张卡只放得下"几条、大致怎样"，
/// 而要看某条通道的地址与健康度明细、以及下一步的主备设置（T11），都需要一个落点。
///
/// ⚠ 数据只在 build 时现取（[collectActiveChannels]）：判据与首页同源，两处不会出现
/// 「首页三条、这里两条」。从配置页返回后主动 `setState` 重取一次。
class ChannelStatusPage extends StatefulWidget {
  /// 打开某一族的配置页。用回调而不是页面自己 push：三个配置页都需要"先加载再进页"
  /// （email 要 `loadChannels()`、webhook 要带通道列表），那套逻辑已经在家常的
  /// `MainPage` 里了，不在这里复制第二份。
  final Future<void> Function(String family) onOpenChannel;

  const ChannelStatusPage({super.key, required this.onOpenChannel});

  @override
  State<ChannelStatusPage> createState() => _ChannelStatusPageState();
}

class _ChannelStatusPageState extends State<ChannelStatusPage> {
  /// 首次进入提示（只弹一次，落 prefs）。键名与 `rule_engine_guide_seen` 同一套写法。
  bool _showGuide = false;

  /// 分组的固定顺序（首页卡是按"应用→webhook→邮件"的观感排的，这里按族的常用度排）。
  static const _familyOrder = ['webhook', 'email', 'app'];

  @override
  void initState() {
    super.initState();
    _checkFirstTime();
  }

  Future<void> _checkFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('channel_status_guide_seen') ?? false) return;
    await prefs.setBool('channel_status_guide_seen', true);
    if (mounted) setState(() => _showGuide = true);
  }

  Future<void> _open(String family) async {
    await widget.onOpenChannel(family);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final channels = collectActiveChannels();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.channelStatusTitle)),
      body: channels.isEmpty
          ? Center(
              child: Text(
                l10n.noChannels,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.tertiaryLabel(context),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (_showGuide) _guideCard(context, l10n),
                for (final family in _familyOrder)
                  ..._familySection(context, l10n, family, [
                    ...channels.where((c) => c.family == family),
                  ]),
              ],
            ),
    );
  }

  Widget _guideCard(BuildContext context, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.channelStatusGuide,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.primaryLabel(context),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => setState(() => _showGuide = false),
          ),
        ],
      ),
    );
  }

  List<Widget> _familySection(
    BuildContext context,
    AppLocalizations l10n,
    String family,
    List<ActiveChannel> items,
  ) {
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(
          channelFamilyName(family),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.secondaryLabel(context),
          ),
        ),
      ),
      ...items.map((c) => _row(context, l10n, c)),
    ];
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    ActiveChannel channel,
  ) {
    final state = channel.healthState;
    final color = switch (state) {
      ChannelHealthState.ok => AppColors.green,
      ChannelHealthState.error => AppColors.red,
      ChannelHealthState.unknown => AppColors.tertiaryLabel(context),
    };
    final statusText = switch (state) {
      ChannelHealthState.ok => l10n.statusOk,
      ChannelHealthState.error => l10n.statusError,
      ChannelHealthState.unknown => l10n.statusUnknown,
    };
    final name = channel.configName.trim();
    final details = [
      if (name.isNotEmpty && name != channel.displayName) channel.displayName,
      if (channel.target.isNotEmpty) channel.target,
      _probeAge(l10n, channel.health),
    ].where((s) => s.isNotEmpty).join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.cardBg(context),
      child: ListTile(
        // 稳定锚点：集成测试与守卫按 family+id 找行，不靠文案
        key: ValueKey('channel-status-${channel.family}-${channel.id}'),
        onTap: () => _open(channel.family),
        leading: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        title: Text(
          name.isNotEmpty ? name : channel.displayName,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.primaryLabel(context),
          ),
        ),
        subtitle: Text(
          details,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.secondaryLabel(context),
          ),
        ),
        trailing: Text(
          statusText,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ),
    );
  }

  /// 「n 分钟前探测 / n 小时前探测」。`probedAt == 0` 是从旧的
  /// `email_test_results` 搬进来的条目（没有时间戳），只能说"从未探测"。
  String _probeAge(AppLocalizations l10n, ChannelHealth? health) {
    if (health == null || health.probedAt == 0) {
      return l10n.channelStatusNeverProbed;
    }
    final ago = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(health.probedAt))
        .inMilliseconds;
    if (ago < 60 * 60 * 1000) {
      return l10n.healthProbedMinutes(ago ~/ (60 * 1000));
    }
    return l10n.healthProbedHours(ago ~/ (60 * 60 * 1000));
  }
}
