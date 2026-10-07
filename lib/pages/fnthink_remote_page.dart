import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../models/fnthink_peer.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_peer_service.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../services/fnthink_remote_gate.dart';
import '../services/fnthink_remote_settings.dart';
import '../services/fnthink_settings.dart';
import '../theme/app_colors.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/help_note_button.dart';
import 'remote_credential_settings_page.dart';
import 'remote_history_page.dart';
import 'remote_send_page.dart';

/// 远程控制页要用到的那一小包依赖。
///
/// 它原来是接收页 `FnthinkReceiveDeps` 里的两件（`contracts`／`coordinator` 与"供远程发送挑收件人"
/// 的 `loadPeers`）—— T97 片C 把那一格搬成独立页时**只搬走它用得着的**，接收页不再背着
/// "这一格要推的那个页需要"的依赖（那正是当初把它塞进接收页的理由）。
class FnthinkRemoteDeps {
  FnthinkRemoteDeps({
    required this.contracts,
    required this.coordinator,
    required this.loadPeers,
    required this.gate,
  });

  factory FnthinkRemoteDeps.fromLocator() => FnthinkRemoteDeps(
    contracts: GetIt.instance<FnthinkContractLoader>(),
    coordinator: GetIt.instance<FnthinkReceiveCoordinator>(),
    // 名单**只**从协调者那条读咽喉取（与接收页同一条纪律）：另开一条读库的路就会有两个排序口径。
    loadPeers: GetIt.instance<FnthinkPeerService>().list,
    gate: () async {
      final contract = GetIt.instance<FnthinkContractLoader>().cached;
      // 契约还没读到 ⇒ **还不知道**（`null`）。这里绝不按"全都没开"猜：那会把 hub 那一行
      // 在启动瞬间画成灰的，用户读到的是"你不能用"，而事实只是"还没读到契约"。
      if (contract == null) return null;
      final settings = FnthinkSettings(contract: contract);
      return fnthinkRemoteGate(
        receiveEnabled: await settings.receiveEnabled,
        consented: await settings.hasRelayConsent(),
        remoteEnabled: await GetIt.instance<FnthinkRemoteSettings>().enabled,
      );
    },
  );

  final FnthinkContractLoader contracts;
  final FnthinkReceiveCoordinator coordinator;

  /// 名单读口（「发一条」挑收件人用）。
  final Future<List<FnthinkPeer>> Function() loadPeers;

  /// 前置三选一（T97 片C）：`null` = **还不知道**（契约没读到）。
  /// 判定本身在 `services/fnthink_remote_gate.dart` —— hub 那一行与这一页共用同一份。
  final Future<FnthinkRemoteGate?> Function() gate;
}

/// 「远程控制」独立页（T97 片C）：凭据与窗口 / 发一条 / 历史三行。
///
/// 为什么从接收页搬出来：这一页答的是「**别人能不能指挥我这台做事**」，
/// 而接收页答的是「**这台收不收别人的东西**」。两件事的代价完全不同 ——
/// 混在一页里，关掉接收的人会以为远程执行也一起关了（反过来更糟：以为只关了收信，
/// 其实还留着一条"谁拿到凭据谁能改我这台"的路）。
///
/// ⚠ 前置判定（接收已开 / 已过同意门 / 远程执行开关）**不在这里**，在 hub 那一行上：
/// 进不来的人不该先进来再看一句"你其实不能进"。判定见 `services/fnthink_remote_gate.dart`。
class FnthinkRemotePage extends StatefulWidget {
  const FnthinkRemotePage({super.key, required this.deps});

  final FnthinkRemoteDeps deps;

  @override
  State<FnthinkRemotePage> createState() => _FnthinkRemotePageState();
}

class _FnthinkRemotePageState extends State<FnthinkRemotePage> {
  Future<void> _openRemoteCredentialSettings() async {
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => const RemoteCredentialSettingsPage(),
      ),
    );
  }

  Future<void> _openRemoteSend() async {
    final coordinator = widget.deps.coordinator;
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => RemoteSendPage(
          // 名单**只**从协调者那条读咽喉取，不另开一条读库的路 —— 两处各读一次就会有两个排序口径。
          deps: RemoteSendDeps(
            loadPeers: widget.deps.loadPeers,
            send:
                ({
                  required String peer,
                  required String title,
                  required String text,
                }) => coordinator.sendNotice(
                  peer: peer,
                  title: title,
                  text: text,
                ),
            contractOf: () async => widget.deps.contracts.load(),
          ),
        ),
      ),
    );
  }

  Future<void> _openRemoteHistory() async {
    final coordinator = widget.deps.coordinator;
    final loader = coordinator.loadRemoteExecutions;
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => RemoteHistoryPage(
          deps: RemoteHistoryDeps(
            loadRecords: (direction) async => await loader?.call(direction),
            removeRecord: (id) async =>
                await coordinator.forgetRemoteExecution?.call(id) ?? false,
            contractOf: () => widget.deps.contracts.load(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text(
          l10n.fnthinkRemoteTitle,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [_buildRemoteExecCard(l10n)],
      ),
    );
  }

  Widget _buildRemoteExecCard(AppLocalizations l10n) {
    return FnthinkCard(
      title: l10n.remoteExecSection,
      children: [
        HelpNoteRow(
          noteKey: 'fnthink-remote-exec-why',
          helpKey: 'fnthink-remote-exec-why-help',
          text: l10n.remoteExecShort,
          helpTitle: l10n.remoteExecWhyTitle,
          // 长文不删：渠道 + 凭据那两个决定因素、以及"默认关、升级不替你打开"都在弹窗里。
          helpBody: l10n.remoteExecWhy,
        ),
        // 三行都是「进一页」⇒ 形状①（§1 定稿），装配点与 hub 那三行同一件。
        FnthinkEntryRow(
          key: const ValueKey('fnthink-remote-exec-settings'),
          icon: Icons.tune,
          iconColor: AppColors.blue,
          title: l10n.remoteExecOpenSettings,
          onTap: _openRemoteCredentialSettings,
        ),
        FnthinkEntryRow(
          key: const ValueKey('fnthink-remote-exec-send'),
          icon: Icons.send_rounded,
          iconColor: AppColors.green,
          title: l10n.remoteExecSendPage,
          onTap: _openRemoteSend,
        ),
        FnthinkEntryRow(
          key: const ValueKey('fnthink-remote-exec-history'),
          icon: Icons.history,
          iconColor: AppColors.purple,
          title: l10n.remoteExecHistory,
          onTap: _openRemoteHistory,
        ),
      ],
    );
  }
}
