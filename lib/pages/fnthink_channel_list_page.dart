import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../models/fnthink_channel.dart';
import '../services/channel_display.dart';
import '../services/channel_health_store.dart';
import '../services/fnthink_channel_service.dart';
import '../theme/app_colors.dart';
import '../widgets/card_action_sheet.dart';
import '../widgets/channel_health_badge.dart';
import '../widgets/channel_visuals.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/pull_to_refresh_list.dart';
import 'fnthink_channel_settings_page.dart';
import 'fnthink_settings_page.dart';

/// 幻念通道**列表页** —— 与 webhook／自建应用／邮件三族同一形状（维护者 2026-10-06 定：
/// 「更多」页推送通道分组里这一格要和组内的 webhook 一致，点进来就是通道列表，
/// 新建／样式／健康度都走既有抽象通道，各种设置挪到设置页去）。
///
/// 形状对齐 webhook 那一族：FAB 新增、行＝图标＋名称＋种类＋目标＋健康度徽标＋启停开关、
/// 长按＝修改／复制／启停／删除、删除走单一咽喉、下拉刷新、底部说明卡。
///
/// ⚠ 两处**故意不一致**，都是被事实逼的，不是偷懒：
/// 1. **下拉刷新不重探**。另外三族的下拉是「现在就把这一族重探一遍」（原生有只换 token、
///    只握手这类非侵入探针）。幻念通道没有这种东西 —— 它的"能不能送到"只能真的往那台
///    发一条。所以下拉在这里只重读库与健康缓存，不去伪造一个会骚扰人的探测。
/// 2. 因此这一族的徽标记的是**最近一次「测试」那一条通道**的结果（详情页那一发），
///    不是"最近一次自动探测"。从没测过的行显示"没测过"，这是真话。
///
/// `_rows == null` 与 `_rows.isEmpty` 分开：读不到和真的没有，是两句不同的话
/// （画成「还没有通道」时，界面就在替库说它没说过的事）。
class FnthinkChannelListPage extends StatefulWidget {
  const FnthinkChannelListPage({
    super.key,
    this.service,
    this.health,
    this.probe,
  });

  final FnthinkChannelStore? service;

  final ChannelHealthStore? health;

  /// 详情页那枚「测试这条通道」要的两件（#271）。这一页只**转交**，不用它：
  /// 没接（测试／别处构造）时详情页就不画那一枚 —— 点了没反应的按钮比没有更糟。
  final FnthinkChannelProbeDeps? probe;

  @override
  State<FnthinkChannelListPage> createState() => _FnthinkChannelListPageState();
}

class _FnthinkChannelListPageState extends State<FnthinkChannelListPage> {
  late final FnthinkChannelStore _service;

  /// 健康度按 `(family='fnthink', id=通道 id)` 记。
  ///
  /// ⚠ 同一个 family 下现在有两种主语：服务器卡用的是 **id=host**（这台对这个中转服务器
  /// 最近一次发出去怎样），这一页用的是 **id=通道 id**（这一条通道最近一次测过怎样）。
  /// 两者不会撞键（host 不是 `fc_…` 形状），但这是"一个命名空间两个含义"，
  /// 把幻念并入通道状态页之前必须先分开 —— 已登记在 roadmap。
  late final ChannelHealthStore _health;

  List<FnthinkChannel>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? FnthinkChannelService();
    _health = widget.health ?? GetIt.instance<ChannelHealthStore>();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final rows = await _service.list();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _error = null;
      });
    } catch (e) {
      // 读不到就说读不到。画成「还没有通道」时，界面就在替库说它没说过的事。
      if (!mounted) return;
      setState(() {
        _rows = null;
        _error = '$e';
      });
      return;
    }
    // 健康缓存放在列表**之后**：徽标是这一页最锦上添花的一层，
    // 让它去挡列表，表现就成了"prefs 读不出 ⇒ 整页什么都没有"。
    await _health.load();
    if (!mounted) return;
    setState(() {});
  }

  /// 详情页回来一律以库里的内容为准（与另外三族同一口径）。
  Future<void> _openDetail({FnthinkChannel? channel}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FnthinkChannelSettingsPage(
          channel: channel,
          service: widget.service,
          probe: widget.probe,
        ),
      ),
    );
    if (!mounted) return;
    await _reload();
  }

  /// 设置住在设置页，不跟通道混在一张列表里（维护者 2026-10-06：「设置放在设置页」）。
  ///
  /// 走 Cupertino 转场而不是 `MaterialPageRoute`：那一本「Material 路由站点」台账
  /// 只许变薄，这一页已有的那一枚是详情页留下的，不能再往这里加第二枚。
  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(builder: (_) => const FnthinkSettingsPage()),
    );
    if (!mounted) return;
    await _reload();
  }

  /// 删除通道的**单一咽喉**（与 T06 那条契约同一个形状）：确认 → 落库 → 清健康缓存。
  Future<void> _delete(FnthinkChannel channel) async {
    final l10n = AppLocalizations.of(context);
    final ok = await IosDialogActions.askConfirm(
      context,
      title: l10n.fnthinkChannelDeleteAskTitle,
      message: l10n.fnthinkChannelDeleteAskMsg(channel.name),
      confirmText: l10n.confirm,
    );
    if (!ok || !mounted) return;
    await _service.delete(channel.id);
    // 缓存一起清：留着它，日后 id 复用（例如从旧备份恢复）时徽标会复活成上一条通道的状态。
    await _health.remove(kFnthinkChannelSlug, channel.id);
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.fnthinkChannelDeleted)));
  }

  Future<void> _setEnabled(FnthinkChannel channel, bool enabled) async {
    try {
      await _service.save(channel.copyWith(enabled: enabled));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
    if (!mounted) return;
    await _reload();
  }

  /// 复制一条：**当场另发新 id**。沿用原 id 的两条通道会互相顶掉健康徽标与送达归属
  /// （T05 的不变量，`card_action_sheet_contract` 守着）。复制出的新行不带健康记录。
  Future<void> _duplicate(FnthinkChannel channel) async {
    final l10n = AppLocalizations.of(context);
    try {
      await _service.create(
        id: 'fc_${DateTime.now().millisecondsSinceEpoch}',
        name: l10n.copyOfName(channel.name),
        target: channel.target,
        targetKind: channel.targetKind,
        role: channel.role,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
    if (!mounted) return;
    await _reload();
  }

  String _kindLabel(AppLocalizations l10n, FnthinkChannel channel) =>
      channel.targetKind == FnthinkChannelTarget.webhook
      ? l10n.fnthinkChannelTargetKindWebhook
      : l10n.fnthinkChannelTargetKindDevice;

  /// 目标那一行：webhook 只显示 host（整条地址在行里放不下，也不该把 token 留在屏上），
  /// 设备那一支显示地址码 —— 它是这条通道"是谁"的身份，不是可省略的传输细节。
  String _targetLabel(FnthinkChannel channel) =>
      channel.targetKind == FnthinkChannelTarget.webhook
      ? channelTargetLabel(channel.target)
      : channel.target;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = _rows;
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text(l10n.fnthinkPushChannel),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('fnthink-channel-settings'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.fnthinkChannelSettingsEntry,
            onPressed: _openSettings,
          ),
        ],
      ),
      body: PullToRefreshList(
        onRefresh: _reload,
        padding: const EdgeInsets.only(bottom: 88),
        emptyChild: rows != null && rows.isEmpty && _error == null
            ? _emptyView(l10n)
            : null,
        children: [
          if (_error != null)
            Padding(
              // key 与另两族同一口径：「读不到」与「还没有」必须是两个可被用例点名的东西。
              key: const ValueKey('fnthink-channel-error'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                _error!,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
          ...?rows?.map((channel) => _buildTile(l10n, channel)),
          const SizedBox(height: 12),
          _buildNotes(context),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.addChannel,
        onPressed: _openDetail,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildTile(AppLocalizations l10n, FnthinkChannel channel) {
    final enabled = channel.enabled;
    return Card(
      // key 挂在**通道 id** 上：列表顺序会变（复制／删除），按下标挂 key 会让控件状态错位。
      key: ValueKey('fnthink-channel-row-${channel.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: AppColors.cardBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.separator(context), width: 0.5),
      ),
      child: ListTile(
        leading: Icon(
          channelVisual(kFnthinkChannelSlug).icon,
          color: enabled
              ? channelVisual(kFnthinkChannelSlug).color
              : AppColors.secondaryLabel(context),
        ),
        title: Text(
          channel.name.isEmpty ? _kindLabel(l10n, channel) : channel.name,
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
              _kindLabel(l10n, channel),
              style: TextStyle(
                fontSize: 13,
                color: AppColors.secondaryLabel(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _targetLabel(channel),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.tertiaryLabel(context),
              ),
            ),
            ChannelHealthBadge(
              health: _health.of(kFnthinkChannelSlug, channel.id),
            ),
          ],
        ),
        trailing: CupertinoSwitch(
          value: enabled,
          activeTrackColor: AppColors.purple,
          onChanged: (v) => _setEnabled(channel, v),
        ),
        onTap: () => _openDetail(channel: channel),
        onLongPress: () => _showChannelActions(l10n, channel),
      ),
    );
  }

  Future<void> _showChannelActions(
    AppLocalizations l10n,
    FnthinkChannel channel,
  ) async {
    final enabled = channel.enabled;
    await CardActionSheet.show(
      context,
      title: channel.name.isEmpty ? _kindLabel(l10n, channel) : channel.name,
      actions: [
        CardAction(
          icon: Icons.settings_outlined,
          label: l10n.edit,
          onTap: () => _openDetail(channel: channel),
        ),
        CardAction(
          icon: Icons.copy,
          label: l10n.duplicate,
          onTap: () => _duplicate(channel),
        ),
        CardAction(
          icon: enabled ? Icons.toggle_off : Icons.toggle_on,
          label: enabled ? l10n.turnOff : l10n.turnOn,
          iconColor: enabled ? AppColors.orange : AppColors.green,
          onTap: () => _setEnabled(channel, !enabled),
        ),
        CardAction(
          icon: Icons.delete_outline,
          label: l10n.delete,
          danger: true,
          onTap: () => _delete(channel),
        ),
      ],
    );
  }

  /// 空态也在下拉壳里：没有「上面还有内容」可滚，但重读仍然成立。
  Widget _emptyView(AppLocalizations l10n) => Center(
    key: const ValueKey('fnthink-channel-empty'),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.inbox, size: 48, color: AppColors.secondaryLabel(context)),
        const SizedBox(height: 12),
        Text(
          l10n.fnthinkChannelEmpty,
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
  );

  /// 这一族的行为说明：讲"这一族怎么用"，不是某一条通道的属性，所以留在列表页。
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
          _DescRow(text: l10n.fnthinkChannelDesc, context: context),
          const SizedBox(height: 8),
          _DescRow(text: l10n.fnthinkChannelNote, context: context),
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
