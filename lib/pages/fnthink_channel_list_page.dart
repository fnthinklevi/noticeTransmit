import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/fnthink_channel.dart';
import '../services/fnthink_channel_service.dart';
import '../theme/app_colors.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/ios_dialog_actions.dart';
import 'fnthink_channel_settings_page.dart';

/// 幻念通道的列表（T94 片3）。
///
/// 一条通道 = 一个转发目标（勾选过的设备 / 一个 webhook 地址）。为什么单独一张列表而不是
/// 在幻念推送页里加一格：维护者要的是「可建多条」，而多条的列表页与详情页是另外三族
/// 已经验证过的形状 —— 在这里另发明一个，两套交互就会同时留在应用里。
class FnthinkChannelListPage extends StatefulWidget {
  const FnthinkChannelListPage({super.key, this.service});

  final FnthinkChannelStore? service;

  @override
  State<FnthinkChannelListPage> createState() => _FnthinkChannelListPageState();
}

class _FnthinkChannelListPageState extends State<FnthinkChannelListPage> {
  late final FnthinkChannelStore _service;

  /// null = 还没读（不等于空）；`[]` = 真的还没有。
  List<FnthinkChannel>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? FnthinkChannelService();
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
      // 读不到就说读不到。画成「还没有通道」时，界面就在替库说它没有说过的话。
      if (!mounted) return;
      setState(() {
        _rows = null;
        _error = '$e';
      });
    }
  }

  Future<void> _openDetail({FnthinkChannel? channel}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FnthinkChannelSettingsPage(
          channel: channel,
          service: widget.service,
        ),
      ),
    );
    await _reload();
  }

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
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.fnthinkChannelDeleted)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.fnthinkChannelTitle)),
      backgroundColor: AppColors.bgColor(context),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          FnthinkNote(
            keyName: 'fnthink-channel-desc',
            text: l10n.fnthinkChannelDesc,
          ),
          const SizedBox(height: 12),
          if (_error != null)
            FnthinkNote(keyName: 'fnthink-channel-error', text: _error!)
          else if (rows == null)
            const SizedBox.shrink()
          else if (rows.isEmpty)
            FnthinkNote(
              keyName: 'fnthink-channel-empty',
              text: l10n.fnthinkChannelEmpty,
            )
          else
            for (final channel in rows) ...[
              _ChannelRow(
                channel: channel,
                l10n: l10n,
                onOpen: () => _openDetail(channel: channel),
                onDelete: () => _delete(channel),
              ),
              const SizedBox(height: 12),
            ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton.filled(
              key: const ValueKey('fnthink-channel-add'),
              onPressed: _openDetail,
              child: Text(l10n.fnthinkChannelAdd),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.l10n,
    required this.onOpen,
    required this.onDelete,
  });

  final FnthinkChannel channel;
  final AppLocalizations l10n;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  String get _kindLabel => channel.targetKind == FnthinkChannelTarget.webhook
      ? l10n.fnthinkChannelTargetKindWebhook
      : l10n.fnthinkChannelTargetKindDevice;

  @override
  Widget build(BuildContext context) {
    return FnthinkCard(
      title: channel.name,
      children: [
        FnthinkStatusRow(
          keyName: 'fnthink-channel-${channel.id}-status',
          dot: channel.enabled,
          text: channel.enabled ? l10n.fnthinkChannelEnabled : '—',
        ),
        FnthinkNote(
          keyName: 'fnthink-channel-${channel.id}-target',
          text: '$_kindLabel · ${channel.target}',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: CupertinoButton(
            key: ValueKey('fnthink-channel-${channel.id}-open'),
            onPressed: onOpen,
            child: Text(l10n.edit),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: CupertinoButton(
            key: ValueKey('fnthink-channel-${channel.id}-delete'),
            onPressed: onDelete,
            child: Text(l10n.fnthinkChannelDelete),
          ),
        ),
      ],
    );
  }
}
