import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fnthink_push/fnthink_push.dart';

import '../l10n/app_localizations.dart';
import '../models/fnthink_remote_execution_record.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_remote_action_labels.dart';
import '../services/fnthink_remote_execution.dart';
import '../services/fnthink_remote_outcome_words.dart';
import '../theme/app_colors.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/help_note_button.dart';
import '../widgets/history_row_tile.dart';
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
    this.executionEvents,
  });

  /// 三种"没有记录"必须分开（与推送历史同一纪律）：null = 还不知道（还没读或读失败），
  /// 空表 = 真的一个都没有。前者显示成后者就是一句假话，而这一格的意义恰恰是"发生过什么"。
  final Future<List<FnthinkRemoteExecutionRecord>?> Function(String? direction)
  loadRecords;

  /// 用户自己删掉一条（撤回发出的那条）。回 false = 本来就没有这一行。
  final Future<bool> Function(String execId) removeRecord;

  final Future<FnthinkContract> Function() contractOf;

  /// 执行链那一步的事件源（`RemoteCommandRunner` 本身是 `ChangeNotifier`）。
  ///
  /// ⚠ **惰性**（一个函数，而不是一个实例）：runner 的注册闭包里读
  /// `getIt<FnthinkContractLoader>().cached!`，在装配 deps 的那一刻就去取它，
  /// 契约还没读到就会崩 —— 而这一页可能正是冷启动后第一个被打开的页面。
  /// 现在只有页面真的挂载了才取那一个实例（同一句话见 `main_page._drainLocalRemoteCommands`）。
  ///
  /// ⚠ 它补的是**「开着这一页时执行完成，列表不动」**那一半：延时窗口到点、执行成功、
  /// 被拒、撤销，每一步都会 `notifyListeners()`，而这一页以前只在 `initState` 读一次。
  /// 回前台那一发（[WidgetsBindingObserver]）补不了这一半 —— 用户就停在页面上，没有离开也没有回来。
  final Listenable? Function()? executionEvents;
}

class _RemoteHistoryPageState extends State<RemoteHistoryPage>
    with WidgetsBindingObserver {
  /// null = 「全部」这一档（**不是**"还没读"—— 读没读过是 [rows] 那件事）。
  String? _direction = kFnthinkRemoteDirectionIn;

  List<FnthinkRemoteExecutionRecord>? _rows;
  FnthinkContract? _contract;
  String? _error;
  String? _note;
  bool _busy = false;

  /// 执行链那一步的事件源（来自 [RemoteHistoryDeps.executionEvents]，只取一次）。
  Listenable? _events;

  /// 一次读还没落回来时又来了事件：记一笔"欠一次重取"，读完补上。
  /// 不这么判的话，"执行完成"那一条会连着点出好几次 DB 往返（窗口开始、迁 executing、
  /// 终态、清横幅，每一步都 notify），而那几次读出来的可能是同一份。
  bool _loading = false;
  bool _reloadWanted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _events = widget.deps?.executionEvents?.call();
    _events?.addListener(_onExecutionEvent);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _events?.removeListener(_onExecutionEvent);
    super.dispose();
  }

  /// 回前台重取：这一页说的是"这台设备做过什么"，而用户去系统设置里改完授权、
  /// 或从状态栏撤了那一条再回来时，屏幕上还停在他离开那一刻的读数（同一族缺陷
  /// 在权限页 T140 片2 已经踩过一次）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  void _onExecutionEvent() => unawaited(_load());

  Future<void> _load() async {
    if (_loading) {
      _reloadWanted = true;
      return;
    }
    _loading = true;
    final deps = widget.deps;
    // 每一轮重取都从"这一次要读的是最新的"起步：读完若期间又来了事件，末尾补一次。
    _reloadWanted = false;
    try {
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
      if (mounted) {
        setState(() {
          _contract = contract;
          _rows = rows;
          _error = error;
        });
      }
    } finally {
      _loading = false;
      if (_reloadWanted) {
        _reloadWanted = false;
        unawaited(_load());
      }
    }
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
                FnthinkChoiceChip(
                  keyName: 'remote-history-dir-in',
                  label: l10n.remoteHistoryIn,
                  selected: _direction == kFnthinkRemoteDirectionIn,
                  onTap: _busy
                      ? null
                      : () => _switchDirection(kFnthinkRemoteDirectionIn),
                ),
                const SizedBox(width: 8),
                FnthinkChoiceChip(
                  keyName: 'remote-history-dir-out',
                  label: l10n.remoteHistoryOut,
                  selected: _direction == kFnthinkRemoteDirectionOut,
                  onTap: _busy
                      ? null
                      : () => _switchDirection(kFnthinkRemoteDirectionOut),
                ),
                const SizedBox(width: 8),
                FnthinkChoiceChip(
                  keyName: 'remote-history-dir-all',
                  label: l10n.remoteHistoryAll,
                  selected: _direction == null,
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
      return [FnthinkNote(keyName: 'remote-history-error', text: _error!)];
    }
    if (rows == null) {
      return [
        FnthinkNote(keyName: 'remote-history-pending', text: l10n.unknown),
      ];
    }
    if (rows.isEmpty) {
      return [
        FnthinkNote(
          keyName: 'remote-history-empty',
          text: l10n.remoteHistoryEmpty,
        ),
        if (_note != null)
          FnthinkNote(keyName: 'remote-history-note', text: _note!),
        HelpNoteRow(
          noteKey: 'remote-history-boundary',
          helpKey: 'remote-history-boundary-help',
          text: l10n.remoteHistoryBoundaryShort,
          helpTitle: l10n.remoteExecHistory,
          helpBody: l10n.remoteHistoryBoundary,
        ),
      ];
    }
    return [
      // ⚠ 结论**留在页面上**而不是弹个 toast：用户回头再看一次才能确认"删掉了"，
      //   而这一格记的是"发生过什么"，一次性的提示等于没记。
      if (_note != null)
        FnthinkNote(keyName: 'remote-history-note', text: _note!),
      for (final row in rows) _row(l10n, row),
      // T149 片1：那句边界不再摊在页尾 —— 收成一行短说 + 问号（维护者 2026-10-12 第 4 条
      // 把 T90 的"两种去处"收窄成一处：长说明只进右上问号弹层）。**正文没删**，只是挪了位置。
      HelpNoteRow(
        noteKey: 'remote-history-boundary',
        helpKey: 'remote-history-boundary-help',
        text: l10n.remoteHistoryBoundaryShort,
        helpTitle: l10n.remoteExecHistory,
        helpBody: l10n.remoteHistoryBoundary,
      ),
    ];
  }

  Widget _row(AppLocalizations l10n, FnthinkRemoteExecutionRecord row) {
    final peer = row.peerAddress.isEmpty
        ? l10n.remoteHistoryLocalTrigger
        : (row.incoming
              ? l10n.remoteHistoryFromPeer(row.peerAddress)
              : l10n.remoteHistoryToPeer(row.peerAddress));
    // T148 片1：这一行改走通用件（基座＝首页那张推送历史的转发行）。
    // 以前它是一句拼出来的散文（`L2 · item · 来源 · 状态`）——八处差异里的三条都在这句里：
    // 没有时间、状态不是"画"出来的而是拼在正文里的、key 的主语与别的页不成体系。
    return HistoryRowTile(
      keyNamespace: 'remote-history',
      identity: row.execId,
      // T146 片2：名走那张人话表（唯一作者 = `fnthink_remote_action_labels`），参数自己占一格。
      // 以前这里直出契约名（`L3 · monitoring`），而 `argument` 那一列**根本没上屏** ——
      // 于是"这台把对面的总开关开了还是关了"在界面上读不出来（它就是那「名与参数挤一串」的另一半）。
      // ⚠ 没配人话的项由那张表**原样回契约名**（看得见的缺），页面不替它编一句。
      title: row.item.isEmpty
          ? row.level
          : '${row.level} · ${fnthinkRemoteActionLabel(l10n, row.item)}',
      subtitle: row.argument.isEmpty
          ? null
          : l10n.remoteHistoryArgument(row.argument),
      time: historyRowTime(row.createdAt),
      source: peer,
      status: _stateText(l10n, row),
      statusColor: _stateColor(row.state),
      lines: [
        // 裁定 3（2026-10-12）：**状态之外还要有结果与理由**。这两格是"有就说、没有就不说"：
        //   空串在这一层是真的"没有"（`pending` 的那一条还没结果、放行执行成功的那一条没理由），
        //   把它渲染成"理由："那种空句子，就是让界面替本机编一句话。
        // ⚠ 理由与结果**原样显示**（`switch-off`／`auth:wrong`／`missing-grant:…` 这些是判定层的词）：
        //   翻成人话要一张具名词表 + 双向差集守卫（与 `fnthink_remote_action_labels` 同式），
        //   那是 T144 片2；在这里半翻会长出第二个词表，而"半翻"的表现是有些词翻了、有些没翻。
        // ⚠ 走通用件的 `lines` 而不是 `statusMessage`：那一格画的是**状态的原话**（一行、两行封顶），
        //   而结果与理由要各留自己的 key 与整句措辞，用户要能分别长按不到、复制得到。
        if (row.result.isNotEmpty)
          FnthinkNote(
            keyName: 'remote-history-result-${row.execId}',
            // T144 片2 格①：这一格是**本机做成了哪一步**，词表唯一作者在那张封闭表上
            // （词表外的读数原样显示 —— 不拿"已完成"盖住一个读不出来的东西）。
            text: l10n.remoteHistoryResult(
              fnthinkRemoteOutcomeText(l10n, row.result),
            ),
          ),
        if (row.reason.isNotEmpty)
          FnthinkNote(
            keyName: 'remote-history-reason-${row.execId}',
            text: l10n.remoteHistoryReason(row.reason),
          ),
        // ⚠ 已终态的那一行**不给**这一下：它在界面上会是一个点了没反应的按钮，
        //   而"点了没反应"正是这一格要防的那种形状。
        // ⚠ **发起端那一行也不给**（T143 片1 带出来的新形状）：out 的 `pending` 说的是
        //   "我已经交出去了、还没收到对面的回执"，本机手里没有窗口、也没有可撤的东西 ——
        //   给这一下等于把一条已经上路的东西标成"我收回了"，而对面照不照做没人知道。
        if (row.unsettled && row.incoming)
          Align(
            alignment: Alignment.centerLeft,
            // T148 片11（差异⑧ 在 remote 这一页的那一格）：这一枚以前是页面自搭的
            // `CupertinoButton` —— 字号、上下留白、禁用色都由页面挑，而同一件事
            // （对这一行做一次动作）在名单页／端点页／收件详情早就是 `FnthinkInlineAction`。
            // ⚠ tone 取**缺省的 action（蓝）**，不是 destructive：红那一档在这套件上是
            //   "吊销一项长期存在的东西"（名单页那枚撤销＝断掉配对关系），而这一枚只是撤回
            //   一条还在窗口里的指令；画红会把"取消一次动作"说成"销毁一条记录"。
            //   换件的同时颜色一字没变 —— 这一片统一的是形状，不是配色。
            child: FnthinkInlineAction(
              key: ValueKey('remote-history-cancel-${row.execId}'),
              label: l10n.remoteHistoryCancel,
              onPressed: _busy ? null : () => _cancel(row),
            ),
          ),
      ],
    );
  }

  /// 状态那枚点的颜色。与 [_stateText] 住在同一页、同一个作者：
  /// 词与色分开两处写，改一处就会"绿色的不认得"这类对不上号的读数。
  Color _stateColor(String state) => switch (state) {
    RemoteExecutionStates.done => AppColors.green,
    RemoteExecutionStates.failed => AppColors.red,
    RemoteExecutionStates.cancelled => AppColors.orange,
    RemoteExecutionStates.executing => AppColors.blue,
    RemoteExecutionStates.pending => AppColors.blue,
    _ => AppColors.systemGray(context),
  };

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

// （T148 片12）这一页原来在这里私有地搭了一枚 `_DirectionChip`：13px、`CupertinoButton`、
// 选中态**只有字重与字色差**（无底色无边框）。同一件事——「一排可选项里的一枚」——在幻念那几张
// 页早就有公共件 `FnthinkChoiceChip`（13px + 选中描边与底色 + 忙时置灰）。
// ⚠ 这不只是"两处各搭各的迟早不一样"：只有字重差的那一枚，**用户在屏上读不出自己选上了没有**
//   （发送页那三排在 T108 片② 就是同一个病，那边当场修）。换件之后方向条多了描边与底色 ——
//   视觉变强是这一片要的效果，不是回归；键名 `remote-history-dir-in/out/all` 逐字没动。

// （T100 片5）这一页原来在这里抄了一枚私有 `_Note`：padding、12px、height 1.4、
// secondaryLabel 四个值与公共件 `FnthinkNote` 逐字相同 —— 小字说明那一族从此只有一个作者。
