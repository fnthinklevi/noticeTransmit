import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../services/app_channel_service.dart';
import '../services/channel_descriptor_service.dart';
import '../services/channel_display.dart';
import '../services/channel_health_store.dart';
import '../theme/app_colors.dart';
import '../widgets/card_action_sheet.dart';
import '../widgets/channel_form_renderer.dart';
import '../widgets/channel_health_badge.dart';
import '../widgets/channel_visuals.dart';
import '../widgets/ios_dialog_actions.dart';
import 'app_channel_settings_page.dart';

/// 自建应用通道**列表页**（T07：三族通道统一成「列表页 → 单通道详情页」）。
///
/// 这一页只负责"有哪些通道、各自什么状态"，编辑交给 [AppChannelSettingsPage] 的
/// 单通道形态。以前两件事混在一张全列表编辑页上，代价是实测到的两个缺陷：
/// ① 从列表点任何一条都打开同一个平铺页（`initialIndex` 参数传了但从没被读）；
/// ② 平铺页保存时**整表重写**，所以"只想改一条"这件事没有安全的路径。
/// 启停/复制/删除这类只动一条的操作留在本页，经服务层的单条写入落库。
class AppChannelListPage extends StatefulWidget {
  const AppChannelListPage({super.key});

  @override
  State<AppChannelListPage> createState() => _AppChannelListPageState();
}

class _AppChannelListPageState extends State<AppChannelListPage> {
  late final AppChannelService _service;
  late final ChannelHealthStore _health;
  late final ChannelDescriptorService _descriptors;
  List<Map<String, dynamic>> _channels = [];

  @override
  void initState() {
    super.initState();
    _service = GetIt.instance<AppChannelService>();
    _health = GetIt.instance<ChannelHealthStore>();
    _descriptors = GetIt.instance<ChannelDescriptorService>();
    // FAB 的类型弹层读 _descriptors.appChannels：splash 那次没拉到（原生未就绪 /
    // 老 App 配新原生）时这里补一次。load() 幂等，已就绪时是空操作。
    _descriptors.load().then((_) {
      if (mounted) setState(() {});
    });
    _refresh();
  }

  /// 重新读库（DB + 原生同步）。返回后重建，保证从详情页回来看到的是落库结果。
  Future<void> _refresh() async {
    await _service.loadChannels();
    if (!mounted) return;
    setState(() => _channels = _service.channels);
    await _health.load();
    if (mounted) setState(() {});
  }

  String _idOf(Map<String, dynamic> c) => c['id']?.toString() ?? '';

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
                    l10n.noAppChannels,
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
        tooltip: l10n.addChannel,
        onPressed: _addChannel,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildChannelTile(int index) {
    final l10n = AppLocalizations.of(context);
    final c = _channels[index];
    final id = _idOf(c);
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
      // key 挂在**通道 id** 上：列表顺序会变（复制/删除），按下标挂 key 会让
      // 控件状态跟着错位（本仓库在 webhook 页踩过同一类）。
      key: ValueKey('app-channel-row-$id'),
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              typeLabel,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.secondaryLabel(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              channelTargetLabel(c['baseUrl']?.toString() ?? ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.tertiaryLabel(context),
              ),
            ),
            ChannelHealthBadge(health: _health.of('app', id)),
          ],
        ),
        trailing: CupertinoSwitch(
          value: enabled,
          activeTrackColor: AppColors.blue,
          onChanged: (v) => _setEnabled(index, v),
        ),
        onTap: () => _openDetail(channelId: id),
        // T05 的长按动作表在这一族落到列表行上（详情页里"修改"不再是空动作）
        onLongPress: () => _showChannelActions(index),
      ),
    );
  }

  /// 行上的动作表。**这一族的「修改」到这里才成立**：以前卡片本身就是编辑表单，
  /// 长按再"跳到编辑态"是空动作（T05 的偏离记录），拆成列表 + 详情后它是第一条。
  Future<void> _showChannelActions(int index) async {
    final l10n = AppLocalizations.of(context);
    final c = _channels[index];
    final id = _idOf(c);
    final name = c['name']?.toString().trim() ?? '';
    final enabled = c['enabled'] == true;
    await CardActionSheet.show(
      context,
      title: name.isEmpty
          ? channelDisplayNameFor(l10n, c['appType']?.toString() ?? '')
          : name,
      actions: [
        CardAction(
          icon: Icons.settings_outlined,
          label: l10n.edit,
          onTap: () => _openDetail(channelId: id),
        ),
        CardAction(
          icon: Icons.copy,
          label: l10n.duplicate,
          onTap: () => _duplicateChannel(index),
        ),
        CardAction(
          icon: enabled ? Icons.toggle_off : Icons.toggle_on,
          label: enabled ? l10n.turnOff : l10n.turnOn,
          iconColor: enabled ? AppColors.orange : AppColors.green,
          onTap: () => _setEnabled(index, !enabled),
        ),
        CardAction(
          icon: Icons.delete_outline,
          label: l10n.delete,
          danger: true,
          onTap: () => _confirmDeleteChannel(index),
        ),
      ],
    );
  }

  Future<void> _addChannel() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showChannelPickerSheet(
      context,
      descriptors: _descriptors.appChannels,
      title: l10n.selectChannelType,
    );
    if (picked == null || !mounted) return;
    await _openDetail(newAppType: picked);
  }

  Future<void> _openDetail({String? channelId, String? newAppType}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppChannelSettingsPage(
          channelId: channelId,
          newAppType: newAppType,
        ),
      ),
    );
    if (!mounted) return;
    // 返回后一律以库里的内容为准：详情页要么已经落库，要么被用户放弃 —— 两种情况
    // 都不该保留页面上的中间态（以前平铺页"改了没点保存就返回"会静默丢编辑）。
    await _refresh();
  }

  Future<void> _setEnabled(int index, bool enabled) async {
    final c = _channels[index];
    final id = _idOf(c);
    if (id.isEmpty) return;
    setState(() => c['enabled'] = enabled);
    await _service.setEnabled(id, enabled);
    if (mounted) setState(() => _channels = _service.channels);
  }

  /// 复制一条通道：**当场另发新 id**（`app_<时间戳>`）。沿用原 id 的两条通道会互相
  /// 顶掉健康徽标与送达归属（T05 的不变量，源码守卫 `card_action_sheet_contract` 也钉着）。
  Future<void> _duplicateChannel(int index) async {
    final l10n = AppLocalizations.of(context);
    final src = _channels[index];
    final name = src['name']?.toString().trim() ?? '';
    await _service.saveChannel({
      ...src,
      'id': 'app_${DateTime.now().millisecondsSinceEpoch}',
      'name': name.isEmpty ? '' : l10n.copyOfName(name),
    });
    if (!mounted) return;
    setState(() => _channels = _service.channels);
  }

  /// 删除通道的**单一咽喉**（T06）：确认 → 落库 → 清健康缓存，三步都在这里，
  /// 所以卡片红叉、长按菜单以及以后可能的新入口都绕不过去。
  Future<void> _confirmDeleteChannel(int index) async {
    final l10n = AppLocalizations.of(context);
    final c = _channels[index];
    final id = _idOf(c);
    final name = c['name']?.toString().trim() ?? '';
    final confirmed = await IosDialogActions.askConfirm(
      context,
      title: l10n.confirmDelete,
      message: l10n.deleteChannelConfirm(
        name.isEmpty
            ? channelDisplayNameFor(l10n, c['appType']?.toString() ?? '')
            : name,
      ),
      confirmText: l10n.delete,
    );
    if (!confirmed || !mounted) return;
    final removed = await _service.deleteChannel(id);
    if (!removed) return;
    // 缓存一起清：留着它，日后 id 复用（例如从旧备份恢复）时徽标会复活成上一条通道的状态。
    await _health.remove('app', id);
    if (!mounted) return;
    setState(() => _channels = _service.channels);
  }
}
