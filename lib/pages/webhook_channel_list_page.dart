import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../services/channel_config_codec.dart';
import '../services/channel_descriptor_service.dart';
import '../services/channel_display.dart';
import '../services/channel_health_store.dart';
import '../services/platform_channel.dart';
import '../services/webhook_service.dart';
import '../theme/app_colors.dart';
import '../widgets/card_action_sheet.dart';
import '../widgets/channel_health_badge.dart';
import '../widgets/channel_visuals.dart';
import '../widgets/ios_dialog_actions.dart';
import 'webhook_settings_page.dart';

/// Webhook 通道**列表页**（T07-B：三族通道统一成「列表页 → 单通道详情页」）。
///
/// 这一页只回答"有哪些通道、各自什么状态"，编辑交给 [WebhookSettingsPage] 的单通道形态。
/// 以前两件事混在一张全列表平铺页上，代价是实测到的三类缺陷：
/// ① 九条并行列表按下标寻址，删一行要九处同步收缩，漏一处就"行串台"；
/// ② 保存走"整表 pop 给调用方再整表重写"，所以"只想改一条"没有安全路径；
/// ③ 进页后台探测读的是**构造期快照**，探测结果会写到已经被删掉的通道上。
/// 启停 / 复制 / 删除都只动一条，经服务层的单条写入落库；探测读实时列表。
class WebhookChannelListPage extends StatefulWidget {
  const WebhookChannelListPage({super.key});

  @override
  State<WebhookChannelListPage> createState() => _WebhookChannelListPageState();
}

class _WebhookChannelListPageState extends State<WebhookChannelListPage> {
  static const _channel = AppChannels.notification;

  late final WebhookService _service;
  late final ChannelHealthStore _health;
  late final ChannelDescriptorService _descriptors;
  List<Map<String, dynamic>> _channels = [];
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _service = GetIt.instance<WebhookService>();
    _health = GetIt.instance<ChannelHealthStore>();
    _descriptors = GetIt.instance<ChannelDescriptorService>();
    // 类型标签与图标按描述符渲染；splash 那次没拉到时补取一次（load() 幂等）
    _descriptors.load().then((_) {
      if (mounted) setState(() {});
    });
    _refresh();
  }

  /// 重新读库（DB + 原生同步）。从详情页回来一律以库里的内容为准 ——
  /// 详情页要么已经落库，要么被用户放弃，两种情况都不该保留页面上的中间态。
  Future<void> _refresh() async {
    await _service.loadChannels();
    if (!mounted) return;
    setState(() => _channels = _service.channels);
    await _health.load();
    if (!mounted) return;
    setState(() {});
    _probeStaleChannels();
  }

  String _idOf(Map<String, dynamic> c) =>
      ChannelConfigCodec.nullableText(c['id']) ?? '';

  String _slugOf(Map<String, dynamic> c) =>
      ChannelConfigCodec.nullableText(c['channelType']) ??
      ChannelConfigCodec.nullableText(c['type']) ??
      'generic';

  /// 启用通道超过 [ChannelHealthStore.staleness] 未探测 → 后台逐个探测并写回单点。
  ///
  /// ⚠ 读的是 `_channels`（服务里的实时列表），不是构造时传进来的快照：
  /// 平铺页时代这件事发生在 initState，用户在页面上删过一行之后，探测循环还在
  /// 按那份不收缩的旧列表跑 ⇒ 结论写到已删除的 id 上，还会把过期徽标算回单点。
  Future<void> _probeStaleChannels() async {
    if (_probing) return;
    final now = DateTime.now();
    final stale = _channels.where((c) {
      if (c['enabled'] != true) return false;
      final id = _idOf(c);
      if (id.isEmpty) return false;
      return ChannelHealthStore.needsProbe(_health.of('webhook', id), now: now);
    }).toList();
    if (stale.isEmpty) return;
    _probing = true;
    for (final c in stale) {
      final id = _idOf(c);
      final url = c['url']?.toString() ?? '';
      if (url.isEmpty) continue;
      final watch = Stopwatch()..start();
      try {
        final r = await _channel.invokeMethod('probeChannelHealth', {
          'url': url,
        });
        await _health.record(
          'webhook',
          id,
          reachable: r['reachable'] as bool? ?? false,
          latencyMs:
              (r['latencyMs'] as num?)?.toInt() ?? watch.elapsedMilliseconds,
          httpCode: (r['httpCode'] as num?)?.toInt(),
        );
        if (mounted) setState(() {});
      } catch (_) {
        // 探测本身失败不写「不可达」：那会把徽标钉成红，比"这次没探到"更误导
      }
    }
    _probing = false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(title: Text(l10n.webhookSettingsTitle)),
      body: _channels.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.link,
                    size: 48,
                    color: AppColors.secondaryLabel(context),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.noWebhookChannels,
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
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                ...List.generate(_channels.length, (i) => _buildTile(i)),
                const SizedBox(height: 12),
                _buildNotes(context),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.addChannel,
        onPressed: () => _openDetail(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildTile(int index) {
    final l10n = AppLocalizations.of(context);
    final c = _channels[index];
    final id = _idOf(c);
    final name = c['name']?.toString().trim() ?? '';
    final slug = _slugOf(c);
    final enabled = c['enabled'] == true;
    final typeLabel = _typeLabel(l10n, slug);
    final host = channelTargetLabel(c['url']?.toString() ?? '');

    return Card(
      // key 挂在**通道 id** 上：列表顺序会变（复制/删除），按下标挂 key 会让控件状态错位
      // —— 这一族此前正是"下标寻址九条并行列表"出的问题。
      key: ValueKey('webhook-channel-row-$id'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: AppColors.cardBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.separator(context), width: 0.5),
      ),
      child: ListTile(
        leading: Icon(
          channelVisual(slug).icon,
          color: enabled
              ? channelVisual(slug).color
              : AppColors.secondaryLabel(context),
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
              host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.tertiaryLabel(context),
              ),
            ),
            ChannelHealthBadge(health: _health.of('webhook', id)),
          ],
        ),
        trailing: CupertinoSwitch(
          value: enabled,
          activeTrackColor: AppColors.blue,
          onChanged: (v) => _setEnabled(index, v),
        ),
        onTap: () => _openDetail(channelId: id),
        onLongPress: () => _showChannelActions(index),
      ),
    );
  }

  /// 类型名：描述符的 labelKey 优先，Dart slug 表兜底，最后原样显示 slug。
  String _typeLabel(AppLocalizations l10n, String slug) {
    final descriptor = _descriptors.byKey(slug);
    return descriptor == null
        ? channelDisplayNameFor(l10n, slug)
        : channelNameOf(l10n, descriptor);
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
      title: name.isEmpty ? _typeLabel(l10n, _slugOf(c)) : name,
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

  Future<void> _openDetail({String? channelId}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebhookSettingsPage(channelId: channelId),
      ),
    );
    if (!mounted) return;
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

  /// 复制一条通道：**当场另发新 id**（`wh_<时间戳>`）。沿用原 id 的两条通道会互相
  /// 顶掉健康徽标与送达归属（T05 的不变量，源码守卫 `card_action_sheet_contract` 钉着）。
  /// 复制出的新行不带健康记录：它本来就没测过，顶着一枚绿勾比顶着空白更糟。
  Future<void> _duplicateChannel(int index) async {
    final l10n = AppLocalizations.of(context);
    final src = _channels[index];
    final name = src['name']?.toString().trim() ?? '';
    await _service.saveChannel({
      ...src,
      'id': 'wh_${DateTime.now().millisecondsSinceEpoch}',
      'name': name.isEmpty ? '' : l10n.copyOfName(name),
    });
    if (!mounted) return;
    setState(() => _channels = _service.channels);
  }

  /// 删除通道的**单一咽喉**（T06）：确认 → 落库 → 清健康缓存三步都在这里，
  /// 所以长按菜单以及以后可能的新入口都绕不过去。
  Future<void> _confirmDeleteChannel(int index) async {
    final l10n = AppLocalizations.of(context);
    final c = _channels[index];
    final id = _idOf(c);
    final name = c['name']?.toString().trim() ?? '';
    final confirmed = await IosDialogActions.askConfirm(
      context,
      title: l10n.confirmDelete,
      message: l10n.deleteChannelConfirm(
        name.isEmpty ? _typeLabel(l10n, _slugOf(c)) : name,
      ),
      confirmText: l10n.delete,
    );
    if (!confirmed || !mounted) return;
    final removed = await _service.deleteChannel(id);
    if (!removed) return;
    // 缓存一起清：留着它，日后 id 复用（例如从旧备份恢复）时徽标会复活成上一条通道的状态。
    await _health.remove('webhook', id);
    if (!mounted) return;
    setState(() => _channels = _service.channels);
  }

  /// 这一族的行为说明（原来挂在平铺页底部）：讲的是"这一族怎么用"，
  /// 不是某一条通道的属性，所以留在列表页。
  Widget _buildNotes(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.notes,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(height: 8),
          _DescRow(text: l10n.webhookDesc1, context: context),
          const SizedBox(height: 8),
          _DescRow(text: l10n.webhookDesc2, context: context),
          const SizedBox(height: 8),
          _DescRow(text: l10n.webhookDesc3, context: context),
        ],
      ),
    );
  }
}

class _DescRow extends StatelessWidget {
  final String text;
  final BuildContext context;
  const _DescRow({required this.text, required this.context});

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
