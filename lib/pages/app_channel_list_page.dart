import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../services/app_channel_service.dart';
import '../theme/app_colors.dart';
import '../widgets/channel_visuals.dart';
import 'app_channel_settings_page.dart';

/// 自建应用通道列表页（分层展示：总设置页仅显示通道名称、类型、连接状态）。
///
/// 点击通道进入 [AppChannelSettingsPage] 编辑详细配置（参考邮件通道交互模式）。
class AppChannelListPage extends StatefulWidget {
  const AppChannelListPage({super.key});

  @override
  State<AppChannelListPage> createState() => _AppChannelListPageState();
}

class _AppChannelListPageState extends State<AppChannelListPage> {
  late AppChannelService _service;
  List<Map<String, dynamic>> _channels = [];

  @override
  void initState() {
    super.initState();
    _service = GetIt.instance<AppChannelService>();
    _refresh();
  }

  Future<void> _refresh() async {
    await _service.loadChannels();
    if (mounted) setState(() => _channels = _service.channels);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(title: Text(l10n.appChannelTitle)),
      body: _channels.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.apps_outlined,
                    size: 48,
                    color: AppColors.secondaryLabel(context),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.appChannelTitle,
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.clickToAdd,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.tertiaryLabel(context),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: _channels.length,
              itemBuilder: (context, index) => _buildChannelTile(index),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openDetail,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildChannelTile(int index) {
    final l10n = AppLocalizations.of(context);
    final c = _channels[index];
    final name = c['name']?.toString() ?? '';
    final appType = c['appType']?.toString() ?? '';
    final enabled = c['enabled'] == true;
    // 类型标签与图标按 key 查**通道视觉表**（与设置页、webhook 页同一份）。
    // ⚠ 不能写成「不是 feishu_app 就是 wecom_app」这种三元兜底：原生新增应用通道
    // 而本页没跟上时，会把没配好的通道标成企业微信应用，用户照着企微的引导去填飞书凭据。
    final known = hasChannelVisual(appType);
    final typeLabel = known
        ? channelDisplayNameFor(l10n, appType)
        : l10n.unknown;
    final typeIcon = known ? channelVisual(appType).icon : Icons.help_outline;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: AppColors.cardBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.separator(context), width: 0.5),
      ),
      child: ListTile(
        leading: Icon(
          typeIcon,
          color: enabled ? AppColors.blue : AppColors.secondaryLabel(context),
        ),
        title: Text(
          name.isNotEmpty ? name : typeLabel,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: enabled
                ? AppColors.primaryLabel(context)
                : AppColors.secondaryLabel(context),
          ),
        ),
        subtitle: Text(
          typeLabel,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.secondaryLabel(context),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 连接状态圆点
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: enabled
                    ? AppColors.green
                    : AppColors.secondaryLabel(context),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              enabled ? l10n.channelStateEnabled : l10n.channelStateDisabled,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondaryLabel(context),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.secondaryLabel(context),
            ),
          ],
        ),
        onTap: _openDetail,
      ),
    );
  }

  Future<void> _openDetail() async {
    // 导航到现有编辑页（该页管理所有通道的完整配置，没有单通道形态：
    // 传 index 也无从"聚焦"，此前那个 initialIndex 参数从未被读取，已删）
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AppChannelSettingsPage()),
    );
    // 返回后刷新列表
    _refresh();
  }
}
