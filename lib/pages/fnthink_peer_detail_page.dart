import 'package:flutter/material.dart';
import 'package:fnthink_push/fnthink_push.dart';

import '../l10n/app_localizations.dart';
import '../models/fnthink_peer.dart';
import '../services/fnthink_peer_grant_display.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../theme/app_colors.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/fnthink_grant_editor.dart';
import '../widgets/help_note_button.dart';
import '../widgets/primary_action_button.dart';

/// 设备详情（T174）—— 一对已配对设备之间那一页。
///
/// 维护者反馈⑥要的是「正常配对，后续按设备设权限」：配对那一下只回答"同不同意"，
/// 逐项授权搬到这里，按主题分组、默认最小授权、高级项收起。
///
/// 这一页只改**「对方 → 这台」**这一向：签名者是自己，服务端写的是
/// `devices[本机].grantsBy[对端]`，与 pairConfirm 当初写的是同一行。
/// 反方向（这机能在那台做什么）住在对端那一行上，只有对端自己能改 —— 契约
/// `revocableBy` 与 `pairing.revokeDirection` 都是同一条红线。
class FnthinkPeerDetailPage extends StatefulWidget {
  const FnthinkPeerDetailPage({
    super.key,
    required this.contract,
    required this.peer,
    required this.coordinator,
    this.onSaved,
  });

  final FnthinkContract contract;
  final FnthinkPeer peer;
  final FnthinkReceiveCoordinator coordinator;

  /// 保存成功之后通知上一层重读名单（设备详情不自己开第二份名单账）。
  final VoidCallback? onSaved;

  @override
  State<FnthinkPeerDetailPage> createState() => _FnthinkPeerDetailPageState();
}

class _FnthinkPeerDetailPageState extends State<FnthinkPeerDetailPage> {
  /// 服务端当前认的那份清单（保存成功后换成服务端回的那份）。
  late List<String> _saved;

  /// 编辑器里此刻勾上的那份。保存之前两者不同 ⇒ 有改动。
  Set<String> _draft = const <String>{};

  bool _busy = false;
  String? _outcome;
  bool _outcomeOk = false;

  @override
  void initState() {
    super.initState();
    _saved = List<String>.of(widget.peer.items)..sort();
    _draft = Set<String>.of(_saved);
  }

  bool get _dirty {
    final current = _draft.toList()..sort();
    if (current.length != _saved.length) return true;
    for (var i = 0; i < current.length; i++) {
      if (current[i] != _saved[i]) return true;
    }
    return false;
  }

  Future<void> _save() async {
    if (_busy || !_dirty) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _outcome = null;
    });
    final items = _draft.toList()..sort();
    final change = await widget.coordinator.updatePeerGrant(
      widget.peer,
      items: items,
    );
    if (!mounted) return;
    if (change.ok) {
      final applied = change.result.items!;
      setState(() {
        _busy = false;
        _saved = List<String>.of(applied)..sort();
        _draft = Set<String>.of(_saved);
        _outcomeOk = true;
        _outcome = l10n.fnthinkPeerGrantSaved;
      });
      widget.onSaved?.call();
      return;
    }
    setState(() {
      _busy = false;
      _outcomeOk = false;
      _outcome = fnthinkPeerGrantOutcomeText(l10n, change);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.fnthinkPeerDetailTitle)),
      backgroundColor: AppColors.bgColor(context),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          FnthinkCard(
            title: widget.peer.whoLabel,
            children: [
              FnthinkNote(
                keyName: 'fnthink-peer-detail-line',
                text: l10n.fnthinkPeerLine(
                  widget.peer.level,
                  fnthinkFormatTime(widget.peer.grantedAt),
                ),
              ),
              FnthinkNote(
                keyName: 'fnthink-peer-detail-level-note',
                text: l10n.fnthinkPeerGrantLevelNote(widget.peer.level),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FnthinkCard(
            title: l10n.fnthinkPeerPermissions,
            children: [
              FnthinkNote(
                keyName: 'fnthink-peer-permissions-short',
                text: l10n.fnthinkPeerPermissionsShort,
              ),
              HelpNoteRow(
                noteKey: 'fnthink-peer-permissions-help',
                helpKey: 'fnthink-peer-permissions-help-help',
                text: l10n.fnthinkPeerPermissionsShort,
                helpTitle: l10n.fnthinkPeerPermissions,
                helpBody: l10n.fnthinkPeerPermissionsHelp,
              ),
              FnthinkGrantEditor(
                // 保存成功后用新的基线重建编辑器：参数草稿要从服务端回的那份重新预填。
                key: ValueKey(
                  'fnthink-grant-editor-${widget.peer.peerAddress}-${_saved.join('|')}',
                ),
                contract: widget.contract,
                initialItems: _saved,
                busy: _busy,
                onChanged: (next) => setState(() => _draft = next),
              ),
              if (_outcome != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    _outcome!,
                    key: const ValueKey('fnthink-peer-grant-outcome'),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: _outcomeOk
                          ? AppColors.secondaryLabel(context)
                          : AppColors.orange,
                    ),
                  ),
                ),
              PrimaryActionButton(
                key: const ValueKey('fnthink-peer-grant-save'),
                label: _dirty
                    ? l10n.fnthinkPeerGrantSave
                    : l10n.fnthinkPeerGrantNoChange,
                onPressed: _busy || !_dirty ? null : _save,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
