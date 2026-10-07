import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fnthink_push/fnthink_push.dart';

import '../l10n/app_localizations.dart';
import '../models/fnthink_remote_execution_record.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_remote_execution.dart';
import '../theme/app_colors.dart';
import '../widgets/ios_dialog_actions.dart';

/// 远程执行历史（片3b-2；维护者 2026-10-03：参照首页的推送历史实现，**区分收指令和发指令**）。
///
/// ## 为什么是「参照」而不是「共用」
/// 推送历史那张表（`notifications` + `fnthink_messages`）回答的是"消息到了没有"，
/// 这一张回答的是"这条指令执行到哪一步了" —— 两者合成一张表的后果是
/// 「一条还没执行的消息」与「一条执行了一半的消息」在界面上长得一样，
/// 而它们的下一步动作完全不同（等 vs 去查为什么没成）。
/// 共用的只有**形状**：三档方向筛选（收 / 发 / 全部）+ 每行一句结论 + 底部一句边界。
class RemoteHistoryPage extends StatefulWidget {
  const RemoteHistoryPage({super.key, this.deps});

  final RemoteHistoryDeps? deps;

  @override
  State<RemoteHistoryPage> createState() => _RemoteHistoryPageState();
}

class RemoteHistoryDeps {
  const RemoteHistoryDeps({
    required this.loadRecords,
    required this.removeRecord,
    required this.contractOf,
  });

  /// 三种"没有记录"必须分开（与推送历史同一纪律）：null = 还不知道（还没读或读失败），
  /// 空表 = 真的一个都没有。前者显示成后者就是一句假话，而这一格的意义恰恰是"发生过什么"。
  final Future<List<FnthinkRemoteExecutionRecord>?> Function(String? direction)
  loadRecords;

  /// 用户自己删掉一条（撤回发出的那条）。回 false = 本来就没有这一行。
  final Future<bool> Function(String execId) removeRecord;

  final Future<FnthinkContract> Function() contractOf;
}

class _RemoteHistoryPageState extends State<RemoteHistoryPage> {
  /// null = 「全部」这一档（**不是**"还没读"—— 读没读过是 [rows] 那件事）。
  String? _direction = kFnthinkRemoteDirectionIn;

  List<FnthinkRemoteExecutionRecord>? _rows;
  FnthinkContract? _contract;
  String? _error;
  String? _note;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final deps = widget.deps;
    FnthinkContract? contract;
    if (deps != null) {
      try {
        contract = await deps.contractOf();
      } on FnthinkContractUnavailable {
        contract = null;
      }
    }
    List<FnthinkRemoteExecutionRecord>? rows;
    String? error;
    try {
      rows = await deps?.loadRecords(_direction);
    } catch (e) {
      error = '$e';
      rows = null;
    }
    if (!mounted) return;
    setState(() {
      _contract = contract;
      _rows = rows;
      _error = error;
    });
  }

  Future<void> _switchDirection(String? direction) async {
    setState(() {
      _direction = direction;
      _rows = null;
      _note = null;
    });
    await _load();
  }

  Future<void> _cancel(FnthinkRemoteExecutionRecord row) async {
    final deps = widget.deps;
    final contract = _contract;
    if (deps == null || contract == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    // 迁移判据只有一处：不在允许表里的那一跳由内核拒，界面不自己写一份规则。
    final move = advanceRemoteExecution(
      contract,
      row.state,
      RemoteExecutionStates.cancelled,
    );
    if (move is RemoteExecutionRefused) {
      // ⚠ 已终态的那一条不给这一下按钮（见下），而这里仍要判一次 ——
      //   列表读回来的那一瞬间到用户点下去之间状态可能已经变了。
      setState(() => _note = move.reason);
      return;
    }
    final ok = await IosDialogActions.askConfirm(
      context,
      title: l10n.remoteHistoryCancel,
      message: l10n.remoteHistoryCancelNote,
      confirmText: l10n.confirm,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    await deps.removeRecord(row.execId);
    await _load();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _note = l10n.remoteHistoryRemoved;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text(
          l10n.remoteExecHistory,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                _DirectionChip(
                  keyName: 'remote-history-dir-in',
                  label: l10n.remoteHistoryIn,
                  active: _direction == kFnthinkRemoteDirectionIn,
                  onTap: _busy
                      ? null
                      : () => _switchDirection(kFnthinkRemoteDirectionIn),
                ),
                const SizedBox(width: 8),
                _DirectionChip(
                  keyName: 'remote-history-dir-out',
                  label: l10n.remoteHistoryOut,
                  active: _direction == kFnthinkRemoteDirectionOut,
                  onTap: _busy
                      ? null
                      : () => _switchDirection(kFnthinkRemoteDirectionOut),
                ),
                const SizedBox(width: 8),
                _DirectionChip(
                  keyName: 'remote-history-dir-all',
                  label: l10n.remoteHistoryAll,
                  active: _direction == null,
                  onTap: _busy ? null : () => _switchDirection(null),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: _body(l10n),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _body(AppLocalizations l10n) {
    final rows = _rows;
    if (_error != null) {
      return [_Note(keyName: 'remote-history-error', text: _error!)];
    }
    if (rows == null) {
      return [_Note(keyName: 'remote-history-pending', text: l10n.unknown)];
    }
    if (rows.isEmpty) {
      return [
        _Note(keyName: 'remote-history-empty', text: l10n.remoteHistoryEmpty),
        if (_note != null) _Note(keyName: 'remote-history-note', text: _note!),
        _Note(
          keyName: 'remote-history-boundary',
          text: '• ${l10n.remoteHistoryBoundary}',
        ),
      ];
    }
    return [
      // ⚠ 结论**留在页面上**而不是弹个 toast：用户回头再看一次才能确认"删掉了"，
      //   而这一格记的是"发生过什么"，一次性的提示等于没记。
      if (_note != null) _Note(keyName: 'remote-history-note', text: _note!),
      for (final row in rows) _row(l10n, row),
      _Note(
        keyName: 'remote-history-boundary',
        text: '• ${l10n.remoteHistoryBoundary}',
      ),
    ];
  }

  Widget _row(AppLocalizations l10n, FnthinkRemoteExecutionRecord row) {
    final state = _stateText(l10n, row);
    final peer = row.peerAddress.isEmpty
        ? l10n.remoteHistoryLocalTrigger
        : (row.incoming
              ? l10n.remoteHistoryFromPeer(row.peerAddress)
              : l10n.remoteHistoryToPeer(row.peerAddress));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Note(
          keyName: 'remote-history-row-${row.execId}',
          text: '${row.level} · ${row.item} · $peer · $state',
        ),
        // ⚠ 已终态的那一行**不给**这一下：它在界面上会是一个点了没反应的按钮，
        //   而"点了没反应"正是这一格要防的那种形状。
        if (row.unsettled)
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton(
              key: ValueKey('remote-history-cancel-${row.execId}'),
              onPressed: _busy ? null : () => _cancel(row),
              child: Text(l10n.remoteHistoryCancel),
            ),
          ),
      ],
    );
  }

  /// 状态词那一格。**存量出现词表外的状态时显示"不认得"**，不当它等于某个已知状态 ——
  /// 那是这一格最容易犯的一个错：把"读不出来"说成"执行完毕"。
  String _stateText(AppLocalizations l10n, FnthinkRemoteExecutionRecord row) {
    final contract = _contract;
    if (contract != null &&
        !contract.remoteExecutionStates.contains(row.state)) {
      return l10n.remoteHistoryStateUnknown(row.state);
    }
    return switch (row.state) {
      RemoteExecutionStates.pending => l10n.remoteHistoryPending,
      RemoteExecutionStates.executing => l10n.remoteHistoryExecuting,
      RemoteExecutionStates.done => l10n.remoteHistoryDone,
      RemoteExecutionStates.failed => l10n.remoteHistoryFailed,
      RemoteExecutionStates.cancelled => l10n.remoteHistoryCancelled,
      _ => l10n.remoteHistoryStateUnknown(row.state),
    };
  }
}

class _DirectionChip extends StatelessWidget {
  const _DirectionChip({
    required this.keyName,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String keyName;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      key: ValueKey(keyName),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      onPressed: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: active
              ? AppColors.primaryLabel(context)
              : AppColors.secondaryLabel(context),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.keyName, required this.text});

  final String keyName;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        key: ValueKey(keyName),
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: AppColors.secondaryLabel(context),
        ),
      ),
    );
  }
}
