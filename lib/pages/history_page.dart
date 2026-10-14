import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../services/archive_worker.dart' show kArchiveDirModeKey;
import '../services/channel_display.dart';
import '../services/delivery_display.dart';
import '../services/filter_service.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_inbox_service.dart';
import '../services/fnthink_peer_service.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../services/notification_service.dart';
import '../services/platform_channel.dart';
import '../theme/app_colors.dart';
import '../database/database_helper.dart';
import '../models/notification_record.dart';
import '../models/delivery_status.dart';
import '../models/fnthink_inbox_message.dart';
import '../models/fnthink_peer.dart';
import '../widgets/card_action_sheet.dart';
import '../services/fnthink_remote_out_record.dart';
import '../widgets/history_row_tile.dart';
import '../widgets/fnthink_card.dart'
    show
        FnthinkActionTone,
        FnthinkChoiceChip,
        FnthinkInlineAction,
        FnthinkRowLabel;
import '../widgets/primary_action_button.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/ios_option_picker.dart';
import '../widgets/ios_progress_dialog.dart';
import '../widgets/app_text_selection_menu.dart';
import '../widgets/ios_input_dialog.dart';
import '../services/repush_eligibility.dart';
import '../services/history_channel_chips.dart';
import '../services/history_paging.dart';
import 'fnthink_send_page.dart';

/// 转发那本账的一页读口（T133 量级①）：一页 = `(精筛后记录, 粗筛是否未取尽, 本页粗筛行数)`。
///
/// `hasMore` 以**粗筛**行数为准（"这一页精筛后为 0 条"不等于后面没有了）；
/// 翻页 offset 必须按第三位（粗筛行数）累加，按精筛后条数累加会把游标往回拨。
/// 生产走 `NotificationService.searchRecords`；测试注入内存替身 ——
/// 与 `inboxLoader` 同一条理由（widget 测试不开 sqlite）。
typedef ForwardedPageLoader =
    Future<(List<NotificationRecord>, bool, int)> Function({
      String? keyword,
      int? startTime,
      int? endTime,
      String? appName,
      String? packageName,
      String? deliveryFilter,
      required int limit,
      required int offset,
    });

class HistoryPage extends StatefulWidget {
  /// 转发那一档的分页读口（T133 量级①）。null = 生产默认（`NotificationService.searchRecords`）。
  ///
  /// ⚠ 它取代了旧的 `records:` 构造参数：那一份是"内存全量镜像"的读法，镜像
  /// 随本片退役 —— 两条读路（无筛选/有筛选）都走这一口，历史从此**不设上限、
  /// 由分页取数循环驮着**，不再有"哪一条因为不在内存里就看不见/重推不了"的档。
  final ForwardedPageLoader? forwardedLoader;

  /// 转发那本账的总条数（无筛选时的标题数与「清除全部」确认框用）。
  /// null = 生产默认（`NotificationService.getTotalCount`）。
  final Future<int> Function()? forwardedCountLoader;

  final Future<void> Function() onClear;
  final Future<Map<String, dynamic>> Function() onExport;
  final Future<int> Function() onClearToday;
  final Future<int> Function(int n) onClearLastN;
  // 历史记录"现在推送"：暂停状态下未实际发送的消息可手动补推
  final Future<void> Function(NotificationRecord record)? onPushNow;

  /// 收件（幻念）那一档的数据来源。默认走 `FnthinkInboxService`，测试注入内存列表 ——
  /// 让 widget 测试**不必去开 sqlite**：那条路在 flutter_test 绑定下要向平台通道要真实库路径，
  /// 桩答 null 就永远等不到（实测整份用例卡死在 00:00，与页面逻辑无关）。
  final Future<List<FnthinkInboxMessage>> Function()? inboxLoader;

  /// 标已读的那一斧子。同上：默认走收件服务，测试注入替身。
  final Future<bool> Function(String messageId)? inboxMarkRead;

  /// 「我发过的」那一档的数据来源（T43）。默认走 `FnthinkInboxService.listSent`，
  /// 测试注入内存列表 —— 与 `inboxLoader` 同一条理由（不开真库）。
  final Future<List<FnthinkInboxMessage>> Function()? sentLoader;

  /// 「回复 / 重发」要找的那台：这条收件的发送方**还在不在本机名单里**。默认走名单读咽喉
  /// （`FnthinkPeerService.list`，只此一个读口），测试注入替身 —— 与 `inboxLoader` 同一条理由。
  final Future<FnthinkPeer?> Function(String peerAddress)? inboxFindPeer;

  /// 「回复 / 重发」真正发出去的那一发。默认走协调者（与幻念推送页名单行上那一下**同一个函数**），
  /// 于是状态码、结论文案、签不出来那几道闸两处完全同源。测试注入替身，不让这一页的用例碰网络。
  ///
  /// 参数是**地址码**而不是整行记录（T98 片④）：共用那张发送页交出的是"发给哪一台"的地址，
  /// 而协调者那一发要的也只是地址 —— 替它拼一个空壳 `FnthinkPeer` 等于让界面造一条库里没有的行。
  final Future<FnthinkSendResult> Function({
    required String peer,
    required String title,
    required String text,
  })?
  inboxSendTo;

  /// 名单读口（T98 片④）：共用那张发送页要把"还能发给谁"摊开给人换目标，
  /// 所以它要的是名单**全集**，不是 `inboxFindPeer` 那一条。与那一格同一个读口、
  /// 同一条注入优先的理由。
  final Future<List<FnthinkPeer>> Function()? inboxListPeers;

  /// 详情弹层里那本「送达记录」的读口（`webhook_delivery_log` 按这条记录查）。
  /// 默认走真库，测试注入替身 —— 与 `inboxLoader` 同一条理由：真库读口在 flutter_test 绑定下
  /// 要向平台通道要数据库路径，桩答 null 就**永远等不到**（实测弹层根本起不来）。
  /// ⚠ 这一格不只是为了测试：它是差异⑤（可点与长按语义）里"点行通向哪"那一格
  ///   唯一能在页面级证明的入口 —— 读口没有缝，那一格就只能靠注释说。
  final Future<List<Map<String, dynamic>>> Function(String notificationId)?
  deliveryLogsLoader;

  /// 打开时停在哪一档。首页那张「幻念收件」卡靠它把人**直接放到收件档**：
  /// 这一档是数据源切换而不是筛选条件，进来还要再手动切一次的话，"原来还有第二个抽屉"这件事
  /// 就藏在一次不显眼的点击里了。其余入口（推送历史卡）留默认值 'forwarded'。
  final String initialDirection;

  /// 点通知跳进来时要在**读完那张表之后自动展开**的那一条（T83）。
  ///
  /// null = 没人指定（普通进入），页面停在列表上不动。
  /// ⚠ 指了但表里没有（那条已被保留策略裁掉、或系统重放了一条老通知）⇒ 页面要**明说**这一点，
  /// 不许悄悄停在列表 —— 用户盯着列表却什么都没发生，只会读成"App 坏了"。
  final String? focusMessageId;

  const HistoryPage({
    super.key,
    this.forwardedLoader,
    this.forwardedCountLoader,
    required this.onClear,
    required this.onExport,
    required this.onClearToday,
    required this.onClearLastN,
    this.onPushNow,
    this.inboxLoader,
    this.sentLoader,
    this.inboxMarkRead,
    this.inboxFindPeer,
    this.inboxSendTo,
    this.inboxListPeers,
    this.deliveryLogsLoader,
    this.initialDirection = 'forwarded',
    this.focusMessageId,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // ── P1 全量历史搜索/筛选 ──
  // 时间范围（按日）：null 表示未启用时间段筛选；start 含当日 0 点，end 含当日
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  String _filterAppName = '';
  String _filterPackageName = '';
  // 送达状态筛选：档名即口径（三个 id 在 `models/delivery_status.dart` 那一张表上）
  String _filterDelivery = deliveryFilterAll;
  // 转发那本账的分页读数（T133 量级①）。null = 还没读过头一页（无筛选时也走这里：
  // "无筛选"只是一次不带参数的查询，不是另一条读路 —— 内存镜像那条路已随本片退役）。
  List<NotificationRecord>? _searchResults;

  /// 粗筛选页游标：本会话已经扫过多少行**粗筛**结果。翻页 offset 按它累加 ——
  /// 按精筛后的条数累加会在"粗筛宽、精筛窄"时把游标往回拨（每页只前进筛中的那几条），
  /// 既漏翻又把同一段重复扫一遍。
  int _coarseOffset = 0;

  /// 转发那本账的总条数（无筛选标题与「清除全部」确认框用；读口注入，见构造函数）。
  int? _forwardedTotal;

  /// 原生离线缓存溢出过的条数（#94-A）。>0 时页顶提示一次，关掉即清 ——
  /// 原生在交付时就清零了，所以它天然只报一次，不需要"已读"状态。
  int _offlineDrops = 0;
  bool _hasMore = false;
  bool _loadingMore = false;
  Timer? _debounce;
  final ScrollController _scrollController = ScrollController();
  // 与幻念两档、远程执行那一档同一个数（T148 差异⑦）：三档都在同一个历史页面上，
  // 往下滚能看到的深度不该各不相同。
  static const int _pageSize = kHistoryPageSize;

  /// F4：右上角「⋯」动作弹层——收纳低频操作（批量补推/导出/归档路径/清空），
  /// 解决 AppBar 图标过多的问题；样式与长按屏蔽菜单一致（iOS 底部弹层）。
  void _showMoreActionsSheet() {
    final l10n = AppLocalizations.of(context);
    // T133 量级①：有没有可操作的东西看分页读数（头一页还没回来时先不给点，
    // 与"列表还在加载"同一形状，而不是假装里面是空的）。
    final canAct = _searchResults?.isNotEmpty ?? false;
    showModalBottomSheet(
      context: context,
      // 颜色与圆角交给 sheet 自己的 Material：以前涂在中间层 Container 的
      // BoxDecoration 上，会把 ListTile 的水波纹盖掉（Flutter 直接抛断言，
      // 6.7 模拟器闸门实测到 4 次）。
      backgroundColor: AppColors.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.separator(sheetContext),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.replay, color: AppColors.blue),
                title: Text(
                  l10n.batchPushEntry,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryLabel(sheetContext),
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _enterBatchMode();
                },
              ),
              ListTile(
                leading: const Icon(Icons.ios_share, color: AppColors.blue),
                title: Text(
                  l10n.exportJson,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: canAct
                        ? AppColors.primaryLabel(sheetContext)
                        : AppColors.secondaryLabel(sheetContext),
                  ),
                ),
                enabled: canAct,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handleExport();
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.folder_open,
                  color: AppColors.secondaryLabel(sheetContext),
                ),
                title: Text(
                  l10n.autoSavePath,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryLabel(sheetContext),
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showArchivePathDialog();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.cleaning_services_outlined,
                  color: AppColors.red,
                ),
                title: Text(
                  l10n.clearRecords,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: canAct
                        ? AppColors.primaryLabel(sheetContext)
                        : AppColors.secondaryLabel(sheetContext),
                  ),
                ),
                enabled: canAct,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showClearOptions();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── F2 批量补推 ──
  bool _batchMode = false;
  final Set<String> _batchSelected = {};

  /// T133 片2：哪些记录的通道 chip 被展开了。
  ///
  /// 这是**界面状态**而不是事实，所以它住在页面里而不是那个排法文件里 ——
  /// 后者只回答"该露哪几枚"，不该知道"这一行此刻被谁点开过"。
  final Set<String> _expandedChipRows = {};

  /// 当前展示的记录（统一走分页读数；null = 头一页还没回来）
  List<NotificationRecord> get _displayedRecords => _searchResults ?? const [];

  /// 可补推池：当前展示列表里**可以再发一次**的那些（判据见 `repush_eligibility.dart`）。
  ///
  /// ⚠ 它与搜索精筛的「失败」**不是同一个集合**：筛的是"送达了吗"（含被拦截的），
  /// 这里问的是"可以再发一次吗"（用户自己拦下的不算）。T133 之前两者共用一个
  /// `hasFailedChannel`，界面上就表现为"筛得出、选不中"。
  List<NotificationRecord> get _batchPool => _displayedRecords
      .where((r) => recordNeedsRepush(r.deliveryStatus))
      .toList();

  void _enterBatchMode() {
    final l10n = AppLocalizations.of(context);
    final pool = _batchPool;
    if (pool.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.batchPushNothingToResend)));
      return;
    }
    setState(() {
      _batchMode = true;
      // 默认全选当前列表里可再发的那些，用户可再取消
      _batchSelected
        ..clear()
        ..addAll(pool.map((r) => r.id));
    });
  }

  void _exitBatchMode() {
    setState(() {
      _batchMode = false;
      _batchSelected.clear();
    });
  }

  void _toggleBatchSelect(NotificationRecord record) {
    if (!recordNeedsRepush(record.deliveryStatus)) return; // 没有可再发的通道：不可选
    setState(() {
      if (_batchSelected.contains(record.id)) {
        _batchSelected.remove(record.id);
      } else {
        _batchSelected.add(record.id);
      }
    });
  }

  void _selectAllRepushable() {
    setState(() {
      _batchSelected
        ..clear()
        ..addAll(_batchPool.map((r) => r.id));
    });
  }

  /// 批量补推：二次确认 → 逐条顺序提交（带进度）→ 汇总反馈
  Future<void> _runBatchPush() async {
    final l10n = AppLocalizations.of(context);
    final targets = _displayedRecords
        .where((r) => _batchSelected.contains(r.id))
        .toList();
    if (targets.isEmpty) return;
    if (widget.onPushNow == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.batchPushUnsupported)));
      return;
    }
    // T90 片13：确认那一发换成唯一装配点（外壳与钮的形状从此只有一份作者）。
    // 点外面 = 没答 = 不推（`barrierDismissible: true` 照旧的 Material 默认保留）。
    final confirmed = await IosDialogActions.askConfirm(
      context,
      title: l10n.batchPushConfirmTitle,
      message: l10n.batchPushConfirmMsg(targets.length),
      confirmText: l10n.confirm,
      cancelText: l10n.cancel,
      destructive: false,
      barrierDismissible: true,
    );
    if (!confirmed || !mounted) return;

    final progress = ValueNotifier<int>(0);
    // T90 片17：这枚进度框换进共享外壳 `IosProgressDialog`。
    // ⚠ 两件必须原样保留的东西：**没有标题**（批量补推没有标题那一行）与 **barrierDismissible: false**
    //   （补推到一半被点掉，下一幕是"用户以为推完了"）。
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ValueListenableBuilder<int>(
        valueListenable: progress,
        builder: (_, done, _) => IosProgressDialog(
          progress: targets.isEmpty ? 0 : done / targets.length,
          message: l10n.batchPushRunning(done, targets.length),
        ),
      ),
    );

    var submitted = 0;
    for (final record in targets) {
      try {
        await widget.onPushNow!(record);
        submitted++;
      } catch (e) {
        debugPrint('批量补推失败（${record.id}）: $e');
      }
      progress.value = submitted;
    }
    progress.dispose();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    setState(() {
      _batchMode = false;
      _batchSelected.clear();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.batchPushDone(submitted))));
  }

  @override
  void initState() {
    super.initState();
    _direction = widget.initialDirection;
    // 点通知跳进来时带上的那一条（T83）。抄进 State 而不是每次读 widget：
    // 它是一次**待兑现的意图**，兑现过就要能清空，而 widget 的字段是不变的。
    _pendingFocusMessageId = widget.focusMessageId;
    _scrollController.addListener(_onScroll);
    // 取一次溢出计数：loadRecords() 在 app 启动时已经跑过 drainOfflineCache
    _offlineDrops = GetIt.instance<NotificationService>().pendingOfflineDrops;
    // 一进来就停在幻念那一族 ⇒ 那一档的数据得当场取。平时它是"切过去才读"的，
    // 而首页那张未读卡进来时并没有一次"切"可以等。**两档都要认**（收件 / 发出）：
    // 只认收件的话，预置到发出档时那一格会永远停在加载圈上。
    if (_direction == 'received' || _direction == 'sent') {
      _inboxDirection = _direction == 'sent'
          ? kFnthinkDirectionOut
          : kFnthinkDirectionIn;
      // 点通知跳进来（T83）：详情只能在那张表**读完之后**才展开得了 ——
      // 列表还没到手，"要展开的那一行"根本无从找起。
      unawaited(_loadInbox().then((_) => _applyPendingFocus()));
    }
    if (_direction == 'all') {
      // 预置到全部档（T84）：读法与"切过去"完全同一条，不另写一份。
      // ⚠ 这一档**不兑现** focusMessageId：通知只可能由收件那一档产生，跳转的落点也是收件档
      //   （见 `main_page_actions.dart` 那两路）。在这里兑现就是让"全部"猜一次那一条属于哪本账。
      unawaited(_loadAll());
    }
    if (_direction == 'forwarded') {
      // T133 量级①：转发那本账的第一页当场取 —— 内存镜像退役后，它不再有
      // "启动时就已经在内存里"可以吃，进来就要自己拉。
      unawaited(_loadSearch(reset: true));
      unawaited(_refreshTotal());
    }
  }

  /// 把「进来就该展开的那一条」兑现**一次**（T83）。
  ///
  /// 三条各钉一个"不这么做会怎样"：
  ///  ① 只兑现一次（先清再弹）：不然用户在弹层上按返回之后，任何一次 rebuild 都会把它再推出来，
  ///     表现是"这一条详情关不掉"；
  ///  ② 表里没有 ⇒ **明说**"这一条已经不在这里了"：悄悄停在列表等于让用户盯着屏幕等一件
  ///     不会发生的事，而他刚刚明明点了一条通知；
  ///  ③ 不许猜一条：找不到就是找不到，展开别的行比什么都不做更糟。
  void _applyPendingFocus() {
    final messageId = _pendingFocusMessageId;
    if (messageId == null) return;
    _pendingFocusMessageId = null;
    if (!_inboxLoaded) return; // 读表期间被切了档：那一档不是这条的账本，不兑现
    final matched = _inbox.where((m) => m.messageId == messageId).toList();
    if (matched.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).fnthinkMessageGoneFromHistory,
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    unawaited(
      _showInboxDetail(
        matched.first,
        outgoing: _inboxDirection == kFnthinkDirectionOut,
      ),
    );
  }

  /// 离线缓存溢出提示条（#94-A）。
  ///
  /// 它**不是**一条历史记录：不进列表、不进送达统计、不参与导出 —— 那些地方都有"按记录算"的
  /// 口径，混进一条没有通道的假记录会让统计悄悄错掉。
  Widget _buildOfflineDropNotice(BuildContext context, AppLocalizations l10n) {
    return Container(
      key: const ValueKey<String>('history-offline-dropped'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppColors.inputBg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.systemOrange(context).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.priority_high,
            size: 18,
            color: AppColors.systemOrange(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.offlineCacheDropped(_offlineDrops),
              style: TextStyle(
                fontSize: 13,
                color: AppColors.primaryLabel(context),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: l10n.close,
            onPressed: () {
              GetIt.instance<NotificationService>().ackOfflineDrops();
              setState(() => _offlineDrops = 0);
            },
          ),
        ],
      ),
    );
  }

  // ── P1 全量历史搜索/筛选逻辑 ──

  bool get _hasActiveFilter =>
      _searchQuery.isNotEmpty ||
      _rangeStart != null ||
      _filterAppName.isNotEmpty ||
      _filterPackageName.isNotEmpty ||
      _filterDelivery != deliveryFilterAll;

  /// 查询起始毫秒（含）：起始日 0 点
  int? get _startTimeMs => _rangeStart == null
      ? null
      : DateTime(
          _rangeStart!.year,
          _rangeStart!.month,
          _rangeStart!.day,
        ).millisecondsSinceEpoch;

  /// 查询结束毫秒（不含）：结束日次日 0 点（当日整天包含在内）
  int? get _endTimeMs => _rangeEnd == null
      ? null
      : DateTime(
          _rangeEnd!.year,
          _rangeEnd!.month,
          _rangeEnd!.day + 1,
        ).millisecondsSinceEpoch;

  /// 滚动触底自动加载下一页
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 240 &&
        _hasMore &&
        !_loadingMore &&
        _searchResults != null) {
      _loadSearch(reset: false);
    }
  }

  /// 触发搜索（T133 量级①：无筛选也走同一条分页读路，"无筛选"只是一次不带参数的查询）。
  /// 关键字输入带 300ms 防抖；面板应用时 immediate 立即查询。
  void _refreshSearch({bool immediate = false}) {
    _debounce?.cancel();
    if (immediate) {
      _loadSearch(reset: true);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _loadSearch(reset: true);
    });
  }

  /// 转发那本账的总条数（无筛选标题与清除确认框）。读失败不猜，留 null 让界面说"读不出"。
  Future<void> _refreshTotal() async {
    try {
      final total =
          await (widget.forwardedCountLoader ??
              () => GetIt.instance<NotificationService>().getTotalCount())();
      if (!mounted) return;
      setState(() => _forwardedTotal = total);
    } catch (e) {
      debugPrint('历史总数读取失败: $e');
    }
  }

  /// 生产默认读口（`forwardedLoader` 为 null 时）：`NotificationService.searchRecords`。
  ForwardedPageLoader get _defaultForwardedLoader =>
      ({
        String? keyword,
        int? startTime,
        int? endTime,
        String? appName,
        String? packageName,
        String? deliveryFilter,
        required int limit,
        required int offset,
      }) {
        return GetIt.instance<NotificationService>().searchRecords(
          keyword: keyword,
          startTime: startTime,
          endTime: endTime,
          appName: appName,
          packageName: packageName,
          deliveryFilter: deliveryFilter,
          limit: limit,
          offset: offset,
        );
      };

  /// 取数循环（T133 量级①）：按 `_pageSize` 一页一页往回要，**凑满一屏才撒手** ——
  /// 粗筛宽、精筛窄，某一页精筛后剩 0 条不等于后面没有了，所以空页不许停手；
  /// 「没有更多了」只能由粗筛取尽（`hasMore == false`）来说。
  /// 游标按**粗筛行数**累加（见 [_coarseOffset]），终止性由它保证：hasMore 为真时
  /// 每轮至少前进一页粗筛行，游标单调递增直到取尽。
  Future<void> _loadSearch({required bool reset}) async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    final load = widget.forwardedLoader ?? _defaultForwardedLoader;
    try {
      final loaded = reset
          ? <NotificationRecord>[]
          : List<NotificationRecord>.of(_searchResults ?? const []);
      var coarse = reset ? 0 : _coarseOffset;
      final want = loaded.length + _pageSize;
      var hasMore = false;
      do {
        final (page, more, coarseRows) = await load(
          keyword: _searchQuery.isEmpty ? null : _searchQuery,
          startTime: _startTimeMs,
          endTime: _endTimeMs,
          appName: _filterAppName.isEmpty ? null : _filterAppName,
          packageName: _filterPackageName.isEmpty ? null : _filterPackageName,
          deliveryFilter: _filterDelivery == deliveryFilterAll
              ? null
              : _filterDelivery,
          limit: _pageSize,
          offset: coarse,
        );
        loaded.addAll(page);
        coarse += coarseRows;
        hasMore = more;
      } while (hasMore && loaded.length < want);
      if (!mounted) return;
      setState(() {
        _searchResults = loaded;
        _coarseOffset = coarse;
        _hasMore = hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('历史搜索失败: $e');
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _clearAllFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _rangeStart = null;
      _rangeEnd = null;
      _filterAppName = '';
      _filterPackageName = '';
      _filterDelivery = deliveryFilterAll;
      // 置回"还没读"，随后当场补第一页 —— T133 量级① 之后没有筛选态/常规态两条路，
      // 清掉筛选 = 回到"不带参数的查询"，不能停在一份带着旧筛选结果的列表上。
      _searchResults = null;
      _coarseOffset = 0;
      _hasMore = false;
    });
    unawaited(_loadSearch(reset: true));
    unawaited(_refreshTotal());
  }

  /// 时间范围摘要（筛选条显示用），如 09-01 ~ 09-07 或单日 2026-09-08
  String get _rangeSummary {
    if (_rangeStart == null) return '';
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (_rangeEnd == null) return fmt(_rangeStart!);
    return '${fmt(_rangeStart!)} ~ ${fmt(_rangeEnd!)}';
  }

  /// 时间那一格的格式化在 `widgets/history_row_tile.dart`（T148：那一列此前每页一份笔）。
  /// 这里只留"输入可能是 String"这一层（DB 里存的形态两种都有）。
  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    final ms = timestamp is int
        ? timestamp
        : int.tryParse(timestamp.toString()) ?? 0;
    return historyRowTime(ms);
  }

  Color _getTypeColor(String? type) {
    switch (type) {
      case 'sms':
        return const Color(0xFFFF9500);
      case 'call_incoming':
      case 'call_answered':
      case 'call_ended':
        return AppColors.green;
      case 'wechat':
        return const Color(0xFF07C160);
      case 'qq':
        return const Color(0xFF12B7F5);
      case 'alipay':
        return const Color(0xFF1677FF);
      case 'system':
        return const Color(0xFF8E8E93);
      case 'battery_charging':
      case 'battery_full':
      case 'battery_low_30':
      case 'battery_low_20':
        return AppColors.blue;
      default:
        return const Color(0xFF5856D6);
    }
  }

  bool _isKnownType(String? type) {
    const knownTypes = {
      'sms',
      'call_incoming',
      'call_answered',
      'call_ended',
      'wechat',
      'qq',
      'alipay',
      'system',
      'battery_charging',
      'battery_full',
      'battery_low_30',
      'battery_low_20',
      'test',
    };
    return knownTypes.contains(type);
  }

  Color _getAppColor(String appName) {
    if (appName.isEmpty) return AppColors.indigo;
    final hash = appName.hashCode;
    return AppColors.avatarPalette[hash.abs() % AppColors.avatarPalette.length];
  }

  Color _getChannelColor(String channel) {
    // channel 是送达键（chan:<slug>），早期记录也可能是本地化显示名——channelKey
    // 两种都认，因此品牌色不再依赖"显示名里含品牌词"这种字符串巧合。
    switch (channelKey(channel)) {
      case 'wechat_work':
      case 'wecom_app':
        return const Color(0xFF2BAA3E);
      case 'feishu':
      case 'feishu_app':
        return const Color(0xFF3370FF);
      case 'dingtalk':
        return const Color(0xFF0089FF);
      case 'email':
        return AppColors.orange;
      default:
        return Colors.grey;
    }
  }

  /// 那一串通道 chip（T133 片2）：**排法与折法走唯一作者** `history_channel_chips.dart`，
  /// 页面这里只交出"这一行此刻展开没有"那一份界面状态。
  ///
  /// ⚠ 这一串里只有末尾那一枚**能点**（展开/收起），其余是状态标记 —— 状态标记不许长出 `onTap`：
  ///   给一枚"通道名 + 送达状态"的标记加点击，等于在同一行里再造一个入口，而那两件事
  ///   （看这一条的完整信息、看这一条走了哪几条通道）行上早就有各自的出口（点行出详情、长按出菜单）。
  ///   钉这一维的是 `test/architecture/history_chip_family_test.dart`。
  ///
  /// 折叠那一枚在 T148 片14 之前是 `GestureDetector` + 同行 chip 那身外衣，注释原话写着
  /// 「它跟别的 chip 一样大、一样是状态标记而不是动作」—— **那句是不实陈述**（它有 `onTap`，
  /// 它一直是动作）；正因如此它才伪装成标记、在屏上读不出点得动。⇒ 现已归 `FnthinkInlineAction`。
  Widget _buildChannelChipWrap(
    NotificationRecord record,
    List<String> rows,
    AppLocalizations l10n,
  ) {
    final ordered = orderChannelsByAttention(rows, record.deliveryStatus);
    final expanded = _expandedChipRows.contains(record.id);
    final shown = visibleChannelChips(ordered, expanded: expanded);
    // 有没有可折的，按**全集**判：展开态 `shown == ordered`，此时 folded 计数是 0，
    // 但那一枚「收起」还得留在原位 —— 用 shown 判就会长出"展开之后收不回去"。
    final foldable = foldedChannelChipCount(ordered) > 0;
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        for (final c in shown) _buildChannelChipFor(record, c, l10n),
        if (foldable)
          _buildChipFoldToggle(
            record,
            hiddenCount: ordered.length - shown.length,
            expanded: expanded,
            l10n: l10n,
          ),
      ],
    );
  }

  Widget _buildChannelChipFor(
    NotificationRecord record,
    String channel,
    AppLocalizations l10n,
  ) {
    final statusInfo = record.deliveryStatus[channel];
    return _buildChannelChip(
      channel,
      _getChannelColor(channel),
      statusInfo is Map ? (statusInfo['status']?.toString() ?? '') : '',
      statusInfo is Map ? (statusInfo['message']?.toString() ?? '') : '',
      l10n,
      viaBackup: statusInfo is Map && statusInfo['viaBackup'] == true,
    );
  }

  Widget _buildChipFoldToggle(
    NotificationRecord record, {
    required int hiddenCount,
    required bool expanded,
    required AppLocalizations l10n,
  }) {
    return FnthinkInlineAction(
      // ⚠ key 字符串逐字没动（`history-chip-fold-<id>`）：名字里那个 "chip" 是这段历史的化石 ——
      //   它一直是**动作**（点了改这一行的显示范围），只是穿着同行 chip 那身 10px/radius 3 的外衣，
      //   代价是用户在屏上读不出它点得动（与 T108 片②、片12 量到的是同一个病）。
      //   改名＝作废按 key 定位的页面级用例，那不是统一。
      key: ValueKey('history-chip-fold-${record.id}'),
      // 中性档：这一枚只展开/收起同一行的通道清单，不动任何一条记录的状态。
      tone: FnthinkActionTone.neutral,
      label: expanded
          ? l10n.historyChipsCollapse
          : l10n.historyChipsMore(hiddenCount),
      onPressed: () => setState(() {
        if (!_expandedChipRows.remove(record.id)) {
          _expandedChipRows.add(record.id);
        }
      }),
    );
  }

  /// 渠道 chip + 送达状态小圆点与文字（成功/失败/发送中；无状态记录仅显示渠道名）
  /// 失败时在 chip 下方内联显示失败原因
  ///
  /// [channel] 传送达键（`chan:<slug>`）：界面显示名在此统一换算，调用方不必再
  /// 关心"这条是键还是名字"。
  ///
  /// [viaBackup]：该通道是主备路由（T12）降级后选中的备用通道 → chip 上追加「备用」。
  /// 备用通道通常是用户平时不盯的那条（邮件、另一个群），不标出来就等于"消息悄悄换了
  /// 出口"，与"不静默丢失"冲突；但也不额外弹提示 —— 这只是一次降级投递，不是错误。
  Widget _buildChannelChip(
    String channel,
    Color chipColor,
    String status,
    String message,
    AppLocalizations l10n, {
    bool viaBackup = false,
  }) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            channelTypeDisplayName(channel),
            style: TextStyle(fontSize: 10, color: chipColor),
          ),
          if (viaBackup) ...[
            const SizedBox(width: 3),
            Text(
              l10n.deliveryViaBackupTag,
              style: const TextStyle(fontSize: 9, color: AppColors.orange),
            ),
          ],
          if (status.isNotEmpty) ...[
            const SizedBox(width: 3),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: deliveryStatusColor(context, status),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              deliveryStatusText(l10n, status),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: deliveryStatusColor(context, status),
              ),
            ),
          ],
        ],
      ),
    );
    // 推送失败/被拦截：原因内联显示在 chip 下方（长按 chip 仍可查看完整信息）。
    // 拦截原因由原生生成，如"黑名单（命中: xxx）"/"应用过滤"
    // ⚠ 两行、可折行：这一句是**状态原话**（不是成段说明文字），截成一行的话
    //   "HTTP 502 …"与"SMTP connect timeout"就长得一样，等于没写。
    if ((status == 'failed' || status == 'intercepted') && message.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          chip,
          const SizedBox(height: 1),
          Text(
            message,
            style: TextStyle(
              fontSize: 10,
              color: deliveryStatusColor(context, status),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }
    if (message.isEmpty) return chip;
    return Tooltip(message: message, child: chip);
  }

  /// 「现在推送」小按钮：iOS 风格圆角蓝底，手动补推这一条里那些**可以再发一次**的通道。
  ///
  /// ⚠ 带 `ValueKey('history-push-now-<记录 id>')`：闸门与用例按 key 点，不按文案 ——
  /// 这一枚在每一行都长一个样，`find.text(pushNow)` 在多行列表里必然抓到多枚。
  Widget _buildPushNowButton(NotificationRecord record, AppLocalizations l10n) {
    return GestureDetector(
      key: ValueKey('history-push-now-${record.id}'),
      onTap: () => widget.onPushNow!(record),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.blue,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.send, size: 11, color: Colors.white),
            const SizedBox(width: 3),
            Text(
              l10n.pushNow,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 状态那一格（词表→人话、词表→颜色）住 `services/delivery_display.dart`，
  /// 是**唯一作者**（T150 片1）：这一页以前自己拿 `default:` 兜底成「发送中」，
  /// 于是任何对不上号的状态串都会被界面替本机说一句"这条正在发"。

  /// 标题前那枚文字徽标（优先级 0=低 / 2=高、幻念那一条走了备用路由……）。
  ///
  /// 形状只有一份，词由调用方给 —— T148 片3 把收件行的「备用」也接进来时，
  /// 它和「高优」是同一格事实（这条有什么额外要标的），不是两种控件。
  Widget _tagBadge(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _getTypeLabel(AppLocalizations l10n, String? type) {
    switch (type) {
      case 'sms':
        return l10n.recordTypeSms;
      case 'call_incoming':
        return l10n.recordTypeCallIncoming;
      case 'call_answered':
        return l10n.recordTypeCallAnswered;
      case 'call_ended':
        return l10n.recordTypeCallEnded;
      case 'wechat':
        return l10n.recordTypeWechat;
      case 'qq':
        return l10n.recordTypeQq;
      case 'alipay':
        return l10n.recordTypeAlipay;
      case 'system':
        return l10n.recordTypeSystem;
      case 'test':
        return l10n.recordTypeTest;
      case 'battery_charging':
        return l10n.recordTypeCharging;
      case 'battery_full':
        return l10n.recordTypeFull;
      case 'battery_low_30':
        return l10n.recordTypeLow30;
      case 'battery_low_20':
        return l10n.recordTypeLow20;
      default:
        return l10n.recordTypeNotification;
    }
  }

  // ── P1 筛选面板 ──

  bool _sameDay(DateTime? a, DateTime? b) =>
      a != null &&
      b != null &&
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day;

  /// 「一排可选项里的一枚」在这一页的唯一装配点：形状由公共件 `FnthinkChoiceChip` 说了算。
  ///
  /// ⚠ 这一枚**只做转发**，不是壳：函数体里不许再出现 `GestureDetector`／`Container`／`BoxDecoration`
  /// （守卫钉这一条）。留装配点而不是逐处展开的理由：这一页有 13 枚，展开会把同一件事写在 13 个位置，
  /// 而「这一族的字号/圆角/描边只有一个作者」正是 T100 立起来的那条判据。
  /// ⚠ [keyName] **必填、不给默认值**：这一页「转发」两个字在全部档里会出现三次（档位芯片、段标题、
  ///   行首来源标识），按文本点会点错一个；抓手缺失时新加一枚会当场编译不过，而不是「用例莫名其妙地红」。
  Widget _filterChip(
    String label,
    bool selected,
    VoidCallback onTap, {
    required String keyName,
  }) {
    return FnthinkChoiceChip(
      keyName: keyName,
      label: label,
      selected: selected,
      onTap: onTap,
    );
  }

  /// P1 筛选面板（iOS 风格底部弹层）：时间段/日、应用名、包名、送达状态。
  /// 面板内为局部草稿，「应用筛选」后生效；下拉关闭不保存。
  Future<void> _showFilterPanel() async {
    final l10n = AppLocalizations.of(context);
    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);
    final yesterday0 = today0.subtract(const Duration(days: 1));
    DateTime? start = _rangeStart;
    DateTime? end = _rangeEnd;
    final appNameCtrl = TextEditingController(text: _filterAppName);
    final pkgCtrl = TextEditingController(text: _filterPackageName);
    var delivery = _filterDelivery;

    Widget timeChips(void Function(void Function()) setSheet) {
      final is7 =
          start != null &&
          end != null &&
          _sameDay(start, today0.subtract(const Duration(days: 6))) &&
          _sameDay(end, today0);
      final is30 =
          start != null &&
          end != null &&
          _sameDay(start, today0.subtract(const Duration(days: 29))) &&
          _sameDay(end, today0);
      final isCustom =
          start != null &&
          !_sameDay(start, today0) &&
          !_sameDay(start, yesterday0) &&
          !is7 &&
          !is30;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _filterChip(
            keyName: 'history-filter-time-all',
            l10n.filterTimeAll,
            start == null,
            () => setSheet(() {
              start = null;
              end = null;
            }),
          ),
          _filterChip(
            keyName: 'history-filter-time-today',
            l10n.filterToday,
            _sameDay(start, today0) && _sameDay(end, today0),
            () => setSheet(() {
              start = today0;
              end = today0;
            }),
          ),
          _filterChip(
            keyName: 'history-filter-time-yesterday',
            l10n.filterYesterday,
            _sameDay(start, yesterday0) && _sameDay(end, yesterday0),
            () => setSheet(() {
              start = yesterday0;
              end = yesterday0;
            }),
          ),
          _filterChip(
            keyName: 'history-filter-time-7d',
            l10n.filterLast7Days,
            is7,
            () => setSheet(() {
              start = today0.subtract(const Duration(days: 6));
              end = today0;
            }),
          ),
          _filterChip(
            keyName: 'history-filter-time-30d',
            l10n.filterLast30Days,
            is30,
            () => setSheet(() {
              start = today0.subtract(const Duration(days: 29));
              end = today0;
            }),
          ),
          _filterChip(
            keyName: 'history-filter-time-custom',
            l10n.filterCustomRange,
            isCustom,
            () async {
              // 用页面 context 打开日期选择器（面板 builder 内的 sheetContext
              // 不在 timeChips 闭包作用域内）
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: today0.add(const Duration(days: 1)),
                initialDateRange: (start != null && end != null)
                    ? DateTimeRange(start: start!, end: end!)
                    : null,
              );
              if (picked != null) {
                setSheet(() {
                  start = picked.start;
                  end = picked.end;
                });
              }
            },
          ),
        ],
      );
    }

    Widget deliveryChips(void Function(void Function()) setSheet) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _filterChip(
            keyName: 'history-filter-delivery-all',
            l10n.deliveryAll,
            delivery == deliveryFilterAll,
            () => setSheet(() => delivery = deliveryFilterAll),
          ),
          // ⚠ 这两枚的**档名就是说的那句话**：这一档回答"送达了吗"，
          //   而"可以再发一次吗"是另一位作者（`repush_eligibility.dart`）。
          //   原先这一档叫「仅失败」却认三种状态 —— 名字与口径不符，
          //   "筛得出、选不中"那类自相矛盾就是这么长出来的。
          _filterChip(
            keyName: 'history-filter-delivery-delivered',
            l10n.deliveryDeliveredOnly,
            delivery == deliveryFilterDelivered,
            () => setSheet(() => delivery = deliveryFilterDelivered),
          ),
          _filterChip(
            keyName: 'history-filter-delivery-not-delivered',
            l10n.deliveryNotDeliveredOnly,
            delivery == deliveryFilterNotDelivered,
            () => setSheet(() => delivery = deliveryFilterNotDelivered),
          ),
        ],
      );
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.separator(sheetContext),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.filterTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryLabel(sheetContext),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  l10n.filterDateRange,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(sheetContext),
                  ),
                ),
                const SizedBox(height: 8),
                timeChips(setSheet),
                if (start != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _sameDay(start, end)
                        ? '${start!.year}-${start!.month.toString().padLeft(2, '0')}-${start!.day.toString().padLeft(2, '0')}'
                        : '${start!.year}-${start!.month.toString().padLeft(2, '0')}-${start!.day.toString().padLeft(2, '0')}'
                              ' ~ ${end!.year}-${end!.month.toString().padLeft(2, '0')}-${end!.day.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.secondaryLabel(sheetContext),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  contextMenuBuilder: AppTextSelectionMenu.editableText,
                  controller: appNameCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.filterAppName,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.primaryLabel(sheetContext),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  contextMenuBuilder: AppTextSelectionMenu.editableText,
                  controller: pkgCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.filterPackageName,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.primaryLabel(sheetContext),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.filterDeliveryStatus,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(sheetContext),
                  ),
                ),
                const SizedBox(height: 8),
                deliveryChips(setSheet),
                const SizedBox(height: 16),
                // T148 差异⑧：这一对「一实一虚」照通道设置页页脚那一对同形
                // （`Expanded(SecondaryActionButton) + 10 + Expanded(PrimaryActionButton)`）。
                // 原来是裸 `TextButton` + `ElevatedButton`（配色与圆角在这一格里自挑一份），
                // 而同一件事（同一张弹层里"办掉它"与"不办只清一下"）在别处已经是公共件那两种形状。
                Row(
                  children: [
                    Expanded(
                      child: SecondaryActionButton(
                        keyName: 'history-filter-reset',
                        label: l10n.filterReset,
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _clearAllFilters();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PrimaryActionButton(
                        key: const ValueKey('history-filter-apply'),
                        label: l10n.filterApply,
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          if (!mounted) return;
                          setState(() {
                            _rangeStart = start;
                            _rangeEnd = end;
                            _filterAppName = appNameCtrl.text.trim();
                            _filterPackageName = pkgCtrl.text.trim();
                            _filterDelivery = delivery;
                          });
                          _refreshSearch(immediate: true);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// P1：自动保存路径设置（iOS 风格弹窗）：查看当前归档目录、
  /// 选择自定义文件夹（SAF，原生持久化授权）或恢复默认应用专属目录
  Future<void> _showArchivePathDialog() async {
    final l10n = AppLocalizations.of(context);
    String? saved;
    try {
      saved = await AppChannels.notification.invokeMethod<String>(
        'getArchiveDirectory',
      );
    } catch (_) {}
    if (!mounted) return;

    // T90 片24：这一枚收进 `showIosOptionPicker` —— 形状与那一族一致
    //（标题 + 若干行 + 选中回一个值），且「恢复默认」那一行旧形状本就是
    // 置灰的（`saved == null` 时 `onTap: null`）。
    // ⚠ ⚠ **「恢复默认」的置灰为何不能省**：`IosPickerOption` 的行是 `CupertinoButton`，
    // 它没有 `enabled` 这个口 ⇒ 会变成「点得动但不走 `onPressed`」的行。
    // 而它的动作是**不可撤销的写盘**（清掉自定义目录），按下去时应该**没变化**，
    // 但用户会看到弹层关掉一张库里的掉发就没了 ⇒ 这是真置灰混成了一个假作。
    // ⇒ 接 `IosPickerOption` 时把 `onTap` 空的那一档整档**拿掉**（不列出来），而不是列出一个按不动的。
    // 口径差异如此（当录下简单地说是「旧形状置灰」、新形状是「不在列单里」）已写在这里，
    // 不让后人当成意外变化。
    final action = await showIosOptionPicker<String>(
      context,
      title: l10n.autoSavePath,
      selectedValue: null,
      // 「现在存到哪儿了」那一行（旧形状在 content 的最上面）。
      // ⇒ 它是这枚弹层要回答的问题本身，不是某一档的说明（那个口是
      // `IosPickerOption.description`，已经被片23 那枚占了）。换件时把它丢掉就是旧形状的硬依赖
      // 不见了 —— `_prettyTreeUri` 会立即变成未引用函数，analyze 会报（第一版确实报了）。
      header: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.autoSavePathDesc,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            saved == null
                ? l10n.archivePathDefault
                : _prettyTreeUri(l10n, saved),
            style: TextStyle(
              fontSize: 13,
              color: AppColors.primaryLabel(context),
            ),
          ),
        ],
      ),
      options: [
        IosPickerOption<String>(
          value: 'pick',
          icon: Icons.folder_open,
          label: l10n.chooseFolder,
        ),
        if (saved != null)
          IosPickerOption<String>(
            value: 'reset',
            icon: Icons.restore,
            label: l10n.resetToDefault,
          ),
      ],
    );

    if (action == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    if (action == 'pick') {
      try {
        final uri = await AppChannels.notification.invokeMethod<String>(
          'pickArchiveDirectory',
        );
        if (!mounted) return;
        if (uri != null) {
          await prefs.setString(kArchiveDirModeKey, 'custom');
          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(l10n.archivePathUpdated),
                duration: const Duration(seconds: 2),
              ),
            );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    } else if (action == 'reset') {
      try {
        await AppChannels.notification.invokeMethod('clearArchiveDirectory');
      } catch (_) {}
      await prefs.setString(kArchiveDirModeKey, 'default');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.archivePathReset),
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  /// SAF treeUri 转可读路径（content://.../tree/primary%3ADownload%2Fxxx/... → Download/xxx）
  String _prettyTreeUri(AppLocalizations l10n, String uri) {
    try {
      final idx = uri.indexOf('/tree/');
      if (idx >= 0) {
        var part = uri.substring(idx + 6);
        final slash = part.indexOf('/');
        if (slash >= 0) part = part.substring(0, slash);
        part = Uri.decodeComponent(part).replaceFirst(':', '/');
        return part.startsWith('/') ? l10n.storageRootPath(part) : part;
      }
    } catch (_) {}
    return uri;
  }

  Future<void> _handleExport() async {
    final l10n = AppLocalizations.of(context);
    try {
      final result = await widget.onExport();
      if (!mounted) return;
      final message = result['message']?.toString() ?? '';
      if (message.isEmpty || message == l10n.exportCancelled) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 送达日志查询/展示用
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // ── 快捷屏蔽（长按记录菜单与详情页按钮共用）──

  FilterService get _filterService => GetIt.instance<FilterService>();

  /// 收件的读写一律从这一层走。页面上那句 `_dbHelper.loadFnthinkInbox(...)` 更短，代价是
  /// **排序口径与「标已读命中没有」各长一份** —— 首页入口卡的未读数与这里的行数迟早对不上。
  /// 写成 getter 而不是字段：注入替身的 widget 测试从不注册它，解析只能发生在默认分支上。
  FnthinkInboxService get _inboxService =>
      GetIt.instance<FnthinkInboxService>();

  /// 名单与发送都是**注入优先、生产默认取 DI 那一份**：页面自己不许拼 HTTP、也不许直连
  /// `fnthink_peers`（名单只有一个读口，两本账的表现是"名单里删了那一行，这里还能回复"）。
  Future<FnthinkPeer?> _findPeerInRoster(String address) async {
    final rows = await GetIt.instance<FnthinkPeerService>().list();
    for (final peer in rows) {
      if (peer.peerAddress == address) return peer;
    }
    return null;
  }

  Future<FnthinkSendResult> _sendViaCoordinator({
    required String peer,
    required String title,
    required String text,
  }) => GetIt.instance<FnthinkReceiveCoordinator>().sendNotice(
    peer: peer,
    title: title,
    text: text,
  );

  /// 名单全集的默认读口 —— 与上面 `_findPeerInRoster` 走的是**同一个** `FnthinkPeerService.list`，
  /// 不是第二个读口（同一条纪律：两本账的表现是"名单里删了那一行，这里还能看见它"）。
  Future<List<FnthinkPeer>> _listRoster() =>
      GetIt.instance<FnthinkPeerService>().list();

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// 屏蔽该应用：按当前过滤模式分流。
  /// - allow（白名单）模式：仅选中应用会被推送 → 应用在名单中则移出即屏蔽；
  ///   不在名单中说明本就不推送，提示无需操作。
  /// - block（黑名单）模式：应用加入屏蔽名单；已在名单中提示无需操作。
  /// 返回后由调用方刷新列表显示。
  /// 本应用自身的通知（电量提醒/测试推送等）不经过应用过滤与黑白名单，
  /// 由电量规则与内置逻辑直接控制——「屏蔽该应用」对其无效，需特判提示。
  static const _selfPackage = 'com.fnthink.notice';

  Future<void> _blockApp(NotificationRecord record) async {
    final l10n = AppLocalizations.of(context);
    final pkg = record.packageName;
    final app = record.appName.isNotEmpty ? record.appName : pkg;
    if (pkg.isEmpty) {
      _showToast(l10n.historyBlockNoAppName);
      return;
    }
    // 本应用自身通知：不受应用过滤/黑白名单影响，屏蔽无效
    if (pkg == _selfPackage) {
      _showToast(l10n.historyBlockAppSelfToast);
      return;
    }
    final filterService = _filterService;
    if (filterService.appFilterMode == 'allow') {
      // allow 模式 + 名单为空 = 全部推送（FilterEngine 语义）。此模式下
      // 「从白名单移除」无法实现屏蔽（名单从空到空），必须切换为黑名单模式：
      // 其余应用在 block 模式下照常推送（与全推行为一致），仅目标应用被屏蔽。
      if (filterService.enabledPackages.isEmpty) {
        await filterService.saveAppFilter('block', [pkg]);
        _showToast(l10n.historyBlockAppSwitchedToBlock(app));
        if (mounted) setState(() {});
        return;
      }
      if (!filterService.enabledPackages.contains(pkg)) {
        // 应用过滤已拦截：此处仍执行一次幂等写回（remaining == 当前名单），
        // 把屏蔽意图显式固化到配置（消除「点了但什么都没发生」的观感）；
        // 白名单关键词命中仍会推送——toast 明确告知例外，由用户决定是否删除关键词。
        final remaining = filterService.enabledPackages
            .where((p) => p != pkg)
            .toList();
        await filterService.saveAppFilter('allow', remaining);
        _showToast(l10n.historyBlockAppWhitelistNote);
        if (mounted) setState(() {});
        return;
      }
      final remaining = filterService.enabledPackages
          .where((p) => p != pkg)
          .toList();
      await filterService.saveAppFilter('allow', remaining);
      _showToast(l10n.historyBlockAppRemoved(app));
    } else {
      if (filterService.enabledPackages.contains(pkg)) {
        _showToast(l10n.historyBlockAppAlreadyBlocked(app));
        return;
      }
      await filterService.saveAppFilter('block', [
        ...filterService.enabledPackages,
        pkg,
      ]);
      _showToast(l10n.historyBlockAppAdded(app));
    }
    if (mounted) setState(() {});
  }

  /// 屏蔽含本通知内容的通知：弹窗预填通知全文（正文为空时用标题），
  /// 可编辑后加入黑名单关键词（黑名单匹配为「标题/内容包含关键词」）。
  Future<void> _blockContent(NotificationRecord record) async {
    final l10n = AppLocalizations.of(context);
    final initialText = record.content.isNotEmpty
        ? record.content
        : record.title;
    if (initialText.isEmpty) {
      _showToast(l10n.historyBlockNoText);
      return;
    }
    // T90 片8：走单字段输入弹层的唯一装配点。这一格是三行输入、提示写在框**下面**，
    // 且换件之前就是 trim 过再落库的 ⇒ trim: true 显式写出来（组件默认不 trim，
    // 因为口令那两格的首尾空格是口令本身）。
    final keyword = await showIosInputDialog(
      context,
      title: l10n.historyBlockContentDialogTitle,
      initialText: initialText,
      maxLines: 3,
      supportingText: l10n.historyBlockContentEditHint,
      trim: true,
    );
    if (keyword == null || keyword.isEmpty) return;
    final filterService = _filterService;
    if (filterService.blacklistKeywords.contains(keyword)) {
      _showToast(l10n.historyBlockContentDuplicate);
      return;
    }
    await filterService.saveBlacklistKeywords([
      ...filterService.blacklistKeywords,
      keyword,
    ]);
    _showToast(l10n.historyBlockContentSuccess);
    if (mounted) setState(() {});
  }

  /// 长按记录弹出操作菜单（屏蔽应用 / 屏蔽内容）。
  /// 打开前强制刷新过滤配置：FilterService 内存态可能尚未加载（冷启动直进历史页），
  /// 以空名单误判「全推模式 / 不在范围」是本菜单第一版的核心缺陷。
  Future<void> _showRecordActionsSheet(NotificationRecord record) async {
    final l10n = AppLocalizations.of(context);
    await _filterService.loadSettings();
    if (!mounted) return;
    final isAllowMode = _filterService.appFilterMode == 'allow';
    final inList = _filterService.enabledPackages.contains(record.packageName);
    // 与 FilterEngine 的实际行为对齐：
    // - allow 模式 + 名单为空 = 推送全部应用（此时任何应用都在推送范围内）；
    // - allow 模式 + 名单非空 = 仅名单内应用推送；
    // - block 模式 = 名单内应用被屏蔽，其余推送。
    final allowPushesAll =
        isAllowMode && _filterService.enabledPackages.isEmpty;
    // 副标题动态说明当前模式下将执行的动作（或已屏蔽状态）。
    // 特判：本应用自身通知由电量规则控制，应用屏蔽不适用。
    // 其余情况菜单项始终可点、始终执行（幂等）——白名单例外在点击后以
    // toast 提示，而不是用「无需操作」把用户挡回去（真机反馈：误导）。
    final blockAppDesc = record.packageName == _selfPackage
        ? l10n.historyActionBlockAppDescSelf
        : isAllowMode
        ? (allowPushesAll
              ? l10n.historyActionBlockAppDescAllowAll
              : (inList
                    ? l10n.historyActionBlockAppDescAllow
                    : l10n.historyActionBlockAppDescAlreadyExcluded))
        : (inList
              ? l10n.historyActionBlockAppDescAlreadyBlocked
              : l10n.historyActionBlockAppDescBlock);
    final textPreview = record.content.isNotEmpty
        ? record.content
        : record.title;

    await CardActionSheet.show(
      context,
      actions: [
        CardAction(
          icon: Icons.block,
          iconColor: AppColors.red,
          label: l10n.historyActionBlockApp,
          description: blockAppDesc,
          onTap: () => _blockApp(record),
        ),
        CardAction(
          icon: Icons.playlist_remove,
          iconColor: AppColors.orange,
          label: l10n.historyActionBlockContent,
          description: textPreview,
          onTap: () => _blockContent(record),
        ),
      ],
    );
  }

  // ── T48 收件档（表 `fnthink_messages`，别人推给本机的消息）──
  //
  // ⚠ "方向"是**数据源切换**，不是又一个筛选条件：转发记录与收件行来自两张表、分页口径不同，
  //   拼进同一条时间线会出现"翻页时同一条出现两次、或整条一次都不出现"。所以整档换列表。
  // late 而非写死默认值：进来停在哪一档由 widget.initialDirection 定（首页那张未读卡要它=收件）。
  late String _direction;
  List<FnthinkInboxMessage> _inbox = const [];
  bool _inboxLoaded = false;

  /// 「进来就要展开的那一条」还欠着的那一次兑现（T83，只在**这一次进入**里有效）。
  /// 兑现一次就清空（见 [_applyPendingFocus]）；把它落盘则会变成"下次冷启动还跳去三天前那条通知"。
  String? _pendingFocusMessageId;

  /// 幻念那一族当前挂在哪一档：`kFnthinkDirectionIn`（收件）或 `kFnthinkDirectionOut`（发出）。
  /// 转发档不用它。**它和 `_direction` 不是一件事**：`_direction` 是界面上哪一格亮着，
  /// 这个是"手上这份 `_inbox` 是哪本账"—— 切档时两本账的读法与空态都不一样。
  String _inboxDirection = kFnthinkDirectionIn;

  /// 「全部」档手里那两本幻念账（T84）。**不复用 `_inbox`**：`_inbox` 的含义是
  /// "当前挂在哪本账上的那几行"，而全部档要**同时**拿着收件与发出 ——
  /// 用一份状态装两本账，就是"切档时把另一本洗成这一本"那类错的新写法。
  List<FnthinkInboxMessage> _allIn = const [];
  List<FnthinkInboxMessage> _allOut = const [];
  bool _allLoaded = false;

  Future<void> _loadInbox() async {
    final direction = _inboxDirection;
    // 两条路都从**注入优先、生产走服务层**那一份取（页面不直连表：这是守卫钉住的那条线）。
    // ⚠ 生产那一半续到取尽（T148 差异⑦）：这两档此前写死 100 条**且没有翻页** ⇒
    // 第 101 条起在界面上不存在，而页面上没有任何一句说"还有没显示的"。
    final load = direction == kFnthinkDirectionOut
        ? (widget.sentLoader ??
              () => drainAllPages(
                (limit, offset) =>
                    _inboxService.listSent(limit: limit, offset: offset),
              ))
        : (widget.inboxLoader ??
              () => drainAllPages(
                (limit, offset) =>
                    _inboxService.list(limit: limit, offset: offset),
              ));
    final rows = await load();

    if (!mounted) return;
    // 期间用户可能又切了档：只把结果交给它属于的那一档。否则"读回来的是发出、画在收件档上"
    // —— 那正是两本账混起来的形状，而它看起来就像一条真的收件。
    if (direction != _inboxDirection) return;
    setState(() {
      _inbox = rows;
      _inboxLoaded = true;
    });
  }

  /// 「全部」档的读法（T84）：**两本账各读各的**，读径与收件档/发出档完全同一条
  /// （同一对注入点、同样续到取尽、同样"注入优先、生产走服务层"）。
  /// 这里不做任何合并或排序 —— 合起来的口径是假的（见 [_buildAllView] 上面那段）。
  Future<void> _loadAll() async {
    // 转发那本账的头一页也要在位（T133 量级①）：全部档的转发段画的就是这份
    // 分页读数 —— 镜像退役后它没有"启动时已经在内存里"可以吃，没读过就当场补。
    if (_searchResults == null) {
      unawaited(_loadSearch(reset: true));
      unawaited(_refreshTotal());
    }
    final inRows =
        await (widget.inboxLoader ??
            () => drainAllPages(
              (limit, offset) =>
                  _inboxService.list(limit: limit, offset: offset),
            ))();
    final outRows =
        await (widget.sentLoader ??
            () => drainAllPages(
              (limit, offset) =>
                  _inboxService.listSent(limit: limit, offset: offset),
            ))();
    if (!mounted) return;
    // 期间被切走了档：这两本就是别档的账本了，交出去会画在错的档位上。
    if (_direction != 'all') return;
    setState(() {
      _allIn = inRows;
      _allOut = outRows;
      _allLoaded = true;
    });
  }

  void _setDirection(String value) {
    if (_direction == value) return;
    final nextIsFnthink = value == 'received' || value == 'sent';
    final nextIsAll = value == 'all';
    setState(() {
      _direction = value;
      if (nextIsFnthink) {
        // 换档 = 换账本：把上一档那几行清掉、置回"还没读"，免得旧的一档在新档位上闪一下。
        _inboxDirection = value == 'sent'
            ? kFnthinkDirectionOut
            : kFnthinkDirectionIn;
        _inbox = const [];
        _inboxLoaded = false;
      }
      if (nextIsAll) {
        // 同一条纪律：全部档也是"换账本"，只是它一次拿两本（收件 + 发出）。
        _allIn = const [];
        _allOut = const [];
        _allLoaded = false;
      }
    });
    if (nextIsFnthink) unawaited(_loadInbox());
    if (nextIsAll) unawaited(_loadAll());
    if (value == 'forwarded' && _searchResults == null) {
      // 切回转发档而头一页还没读过（进页时停在别的档）：当场补读 ——
      // 与 initState 那一下同一条路，不另写一份。
      unawaited(_loadSearch(reset: true));
      unawaited(_refreshTotal());
    }
  }

  Widget _directionBar(AppLocalizations l10n) {
    // 四格一排，窄屏必然放不下 ⇒ 横着可滚。不是装饰：写死 Row 的下一幕就是
    // RenderFlex overflow 半条芯片（T84 加第四档时量出来的）。
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _filterChip(
            l10n.fnthinkDirForwarded,
            _direction == 'forwarded',
            () => _setDirection('forwarded'),
            keyName: 'direction-chip-forwarded',
          ),
          const SizedBox(width: 8),
          _filterChip(
            l10n.fnthinkDirInbox,
            _direction == 'received',
            () => _setDirection('received'),
            keyName: 'direction-chip-received',
          ),
          const SizedBox(width: 8),
          _filterChip(
            l10n.fnthinkDirSent,
            _direction == 'sent',
            () => _setDirection('sent'),
            keyName: 'direction-chip-sent',
          ),
          const SizedBox(width: 8),
          // T84：一次同看三张账。每行仍带来源标识，未读数与各档口径一个都不改。
          _filterChip(
            l10n.fnthinkDirAll,
            _direction == 'all',
            () => _setDirection('all'),
            keyName: 'direction-chip-all',
          ),
        ],
      ),
    );
  }

  /// 收件 / 发出那一行的**唯一构造点**（T84 起「全部」档也复用同一份形状）。
  ///
  /// 抽出来不是为了好看：全部档要列的是同一批行，若在那儿再抄一份，`read` 那一列的读法、
  /// 未读点画不画、点下去标不标已读就有了**第二份可以朝不同方向写错**的实现。
  ///
  /// T148 片3：行的**画法**交给通用件 `HistoryRowTile`，这里只留幻念收件这一族才有的判断
  /// （未读点画不画、「备用」标不标、回执那一串原话）。
  /// ⚠ `keyNamespace: 'fnthink-inbox'` + `identity: messageId` 拼出来的行 key 与改造前
  ///   **逐字相同**（`fnthink-inbox-row-<messageId>`）—— 闸门与用例都按它定位，
  ///   所以统一的是形状而不是 key 字符串（见 `history_row_tile.dart` 里那段说明）。
  Widget _inboxRow(
    AppLocalizations l10n,
    FnthinkInboxMessage m, {
    required bool outgoing,
    required int index,
    required int total,
  }) {
    final peer = m.sender.isEmpty ? l10n.unknown : m.sender;
    return HistoryRowTile(
      keyNamespace: 'fnthink-inbox',
      identity: m.messageId,
      title: m.title.isEmpty ? m.body : m.title,
      // 时间此前混在那串散文里（`发件人 · 备用 · 03-01 12:00`），拆成自己的格子才有对齐的右列
      // —— 这是 T148 差异②（各页时间列不一致）里收件那一半。
      // ⚠ 发出档里 `receivedAt` 记的是本机**发出**的时刻（含义随方向变，与 `sender` 同一套两用）。
      time: historyRowTime(m.receivedAt),
      source: outgoing ? '${l10n.fnthinkRecipient}：$peer' : peer,
      badges: [
        // 未读点只跟着表里的 read 那一列；已读就**不画**这个点（不画 ≠ 画一个透明的占位）。
        // 发出的那条没有"未读"这回事，一律不画 —— 全部档里这一条同时是判据②的落点：
        // 转发与发出两类行都没有"标已读"这件事，所以既不给点也不给入口。
        //
        // 反证登记（`8b5c8ad`，三条全 named+restored；报告在本地 outputs/，不入库）：
        //   无脑画点 ⇒ 红在「已读那行根本不画点」；标完不重新读表 ⇒ 红在「写表 + 重新读表」
        //   与「不留点不开的幽灵行」；收件档不切数据源 ⇒ 红在整组收件用例。
        if (!outgoing && !m.read)
          Container(
            width: 8,
            height: 8,
            key: ValueKey('fnthink-inbox-unread-${m.messageId}'),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.blue,
            ),
          ),
        // 「备用」与另外三族共用同一个词条（deliveryViaBackupTag）：这一族此前不标，
        // 于是同一屏里出现"webhook 标了、幻念没标"，看起来像随机丢而不是一族的事。
        if (m.viaBackup)
          _tagBadge(context, l10n.deliveryViaBackupTag, AppColors.blue),
      ],
      // 本机报出去的那一串是**原话**（`delivered` / `rejected_*` / `failed_action`）：
      // 翻成人话属 T144 片2，那一版改的是这一格的来源，不改它的画法。
      statusMessage: outgoing || m.ackResult.isEmpty ? null : m.ackResult,
      statusColor: AppColors.secondaryLabel(context),
      corner: index == 0
          ? (index == total - 1
                ? HistoryRowCorner.only
                : HistoryRowCorner.first)
          : (index == total - 1
                ? HistoryRowCorner.last
                : HistoryRowCorner.middle),
      onTap: () => _showInboxDetail(m, outgoing: outgoing),
    );
  }

  Widget _buildInboxView(AppLocalizations l10n) {
    if (!_inboxLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_inbox.isEmpty) {
      return Center(
        child: Text(
          _inboxDirection == kFnthinkDirectionOut
              ? l10n.fnthinkSentEmpty
              : l10n.fnthinkInboxEmpty,
          style: TextStyle(
            color: AppColors.secondaryLabel(context),
            fontSize: 15,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _inbox.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _inboxRow(
        l10n,
        _inbox[index],
        outgoing: _inboxDirection == kFnthinkDirectionOut,
        index: index,
        total: _inbox.length,
      ),
    );
  }

  // ── T84「全部」档：三张账**并排**看，不拼成同一条时间线 ────────────────────
  //
  // ⚠ 为什么不合并排序：转发那张表是**分页**的（`_onScroll` 按 offset 往后要下一页），而收件 /
  //   发出各是"一次读满 100 行"的 flat 读法。把三本拼进同一条时间线，表现正是 T48 那条判据点名的
  //   两件事：翻页时同一条出现两次，或整条一次都不出现。并排的代价只是"不是按时间全序"——
  //   而那个全序在分页口径下本来就是假的。
  // ⚠ 判据①：每行前面一枚来源标识。分组标题会被滚出屏幕，"这条属于哪本账"不能只写在标题里。
  // ⚠ 判据②：只有收件行有未读点与"标已读"那一下（`_inboxRow` 的 `outgoing` 分支已经给了），
  //   转发行走它自己的详情，发出行不标已读 —— 全部档不给它们长出这个入口。
  // ⚠ 判据③：**不新增第四种计数**。AppBar 上那个数仍是转发那本账的（与各档同一口径），
  //   三个分组标题上也不写数字 —— "全部 = 三者之和"这个数在分页口径下当下就不准。
  Widget _buildAllView(
    AppLocalizations l10n,
    List<NotificationRecord> records,
  ) {
    if (!_allLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(child: _allScopeNote(l10n)),
        SliverToBoxAdapter(
          child: _allSectionHeader('forwarded', l10n.fnthinkDirForwarded),
        ),
        if (records.isEmpty)
          SliverToBoxAdapter(
            // 与转发档那一屏同一句：搜不到与从来没有，是两件事。
            child: _allSectionEmpty(
              _hasActiveFilter ? l10n.noMatchRecords : l10n.noRecords,
            ),
          )
        else
          SliverList.builder(
            itemCount: records.length,
            itemBuilder: (context, index) => _withSourceTag(
              l10n.fnthinkTagForwarded,
              _buildRecordItem(context, records[index], index, records.length),
            ),
          ),
        SliverToBoxAdapter(
          child: _allSectionHeader('inbox', l10n.fnthinkDirInbox),
        ),
        if (_allIn.isEmpty)
          SliverToBoxAdapter(child: _allSectionEmpty(l10n.fnthinkInboxEmpty))
        else
          SliverList.builder(
            itemCount: _allIn.length,
            itemBuilder: (context, index) => _withSourceTag(
              l10n.fnthinkTagInbox,
              _inboxRow(
                l10n,
                _allIn[index],
                outgoing: false,
                index: index,
                total: _allIn.length,
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: _allSectionHeader('sent', l10n.fnthinkDirSent),
        ),
        if (_allOut.isEmpty)
          SliverToBoxAdapter(child: _allSectionEmpty(l10n.fnthinkSentEmpty))
        else
          SliverList.builder(
            itemCount: _allOut.length,
            itemBuilder: (context, index) => _withSourceTag(
              l10n.fnthinkTagSent,
              _inboxRow(
                l10n,
                _allOut[index],
                outgoing: true,
                index: index,
                total: _allOut.length,
              ),
            ),
          ),
      ],
    );
  }

  /// 顶部那一行说明：搜索与筛选只作用于「转发」那一段（判据③的另一半 —— 不假装一个筛子能筛三张表）。
  Widget _allScopeNote(AppLocalizations l10n) {
    return Padding(
      key: const ValueKey<String>('history-all-note'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        // 圆点在前 = §1 的「底部无序列表」那一形状（与设置页 `fnthink-boundary`、
        // 远程历史页那句边界句同一做法）；这句一字未改，只换了它挂的形状。
        '• ${l10n.fnthinkAllScopeNote}',
        style: TextStyle(fontSize: 12, color: AppColors.tertiaryLabel(context)),
      ),
    );
  }

  /// 分组标题。**刻意不带数字**：判据③要的正是"全部档不新增第四种计数"。
  Widget _allSectionHeader(String kind, String title) {
    // 组标题走公共件 `FnthinkRowLabel`（T146 片4）：画法（13px/w600/次要字色）与另外几张清单页同源，
    // 这一页只交出「段与段之间的那点留白」。
    // ⚠ key 逐字没动（`history-all-header-<kind>`），只是从外层 Padding 挪到了画出来的那一格上 ——
    //   用例与闸门 4.2 仍按同一串定位，命中的从"那一行的容器"变成"那一行的文字"。
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: FnthinkRowLabel(keyName: 'history-all-header-$kind', label: title),
    );
  }

  Widget _allSectionEmpty(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: AppColors.tertiaryLabel(context)),
      ),
    );
  }

  /// 行首那一枚来源标识（判据①）。宽度固定 ⇒ 三段对得起同一条竖线，扫一眼就分得开类别。
  Widget _withSourceTag(String tag, Widget row) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Padding(
            padding: const EdgeInsets.only(top: 14, left: 2),
            child: Text(
              tag,
              key: ValueKey<String>('history-all-tag-$tag'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ),
        ),
        Expanded(child: row),
      ],
    );
  }

  Future<void> _showInboxDetail(
    FnthinkInboxMessage message, {
    bool outgoing = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    // 「回复 / 重发」只在**这条的发送方还在本机名单里**时给入口：名单是本机唯一一本"同意过谁"的
    // 账（服务端投递时也按 grantsBy 判），不在册的那台给入口就是一个必然 403 的按钮。
    // ⚠ 这条判断放在**弹层起来之前**：入口不出现与"点了才知道不行"是两种体验，前者是实话。
    // ⚠ 发出档不看它：那一档的对端是**收件人**，回复自己发出去的东西不是这一格的事。
    final peer = outgoing || message.sender.isEmpty
        ? null
        : await (widget.inboxFindPeer ?? _findPeerInRoster)(message.sender);
    if (!mounted) return;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.cardBg(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        isScrollControlled: true,
        builder: (sheetContext) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.title.isEmpty ? message.body : message.title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryLabel(sheetContext),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        message.body,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: AppColors.primaryLabel(sheetContext),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 六项里那四项就在这一行（T105 片①）：
                  // 对端与时刻都带标签 —— 裸的一串地址码加一个光秃秃的时间，
                  // 用户读不出“这是谁”“这是什么时候”。
                  // 时刻的语义随方向变（与 sender 那一列同一套两用）：收件档＝本机收到的时刻，
                  // 发出档＝本机发出的时刻；对端“什么时候真的收到”本机今天拿不到（见 T105 片③）。
                  Text(
                    outgoing
                        ? '${l10n.fnthinkRecipient}：'
                              '${message.sender.isEmpty ? l10n.unknown : message.sender} · '
                              '${l10n.fnthinkSentAt}：${_formatTime(message.receivedAt)}'
                              // T105 片③：对面收下那一刻（服务端回执带回来的）。
                              // 0＝还不知道（对面还没 ack／旧服务端）—— 那时这一句不出现。
                              '${message.ackedAt > 0 ? ' · ${l10n.fnthinkPeerAckedAt}：${_formatTime(message.ackedAt)}' : ''}'
                              '${message.ackResult.isEmpty ? '' : ' · ${message.ackResult}'}'
                        : '${l10n.fnthinkSender}：'
                              '${message.sender.isEmpty ? l10n.unknown : message.sender} · '
                              '${l10n.fnthinkReceivedAt}：${_formatTime(message.receivedAt)}'
                              // T105 片②：服务端给过受理时刻才出这一句
                              // （旧行与旧服务端是 0 ⇒ 不出现，而不是画一个 1970 年的时刻）。
                              '${message.sentAt > 0 ? ' · ${l10n.fnthinkSentAt}：${_formatTime(message.sentAt)}' : ''}'
                              '${message.ackResult.isEmpty ? '' : ' · ${message.ackResult}'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.secondaryLabel(sheetContext),
                    ),
                  ),
                  if (peer != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // T148 差异⑧：这两枚走幻念那一族共用的行内动作件 ——
                        // 「这一条上可做的一件事」在收件箱页、端点页、名单页已经是同一个形状与
                        // 同一套语义色（`FnthinkInlineAction.colorOf` 是唯一作者），
                        // 历史页详情里再搭一枚 Material `TextButton` 就是第五种形状。
                        FnthinkInlineAction(
                          key: const ValueKey('fnthink-inbox-reply'),
                          label: l10n.fnthinkReply,
                          onPressed: () => _composeFromInbox(
                            peer: peer,
                            // 回复：标题预填「回复：<原标题>」，正文留空让用户自己写；
                            // 原标题为空（正文即标题那条路）时就用「回复」两字，不拼一个空引用。
                            title: message.title.isEmpty
                                ? l10n.fnthinkReply
                                : l10n.fnthinkReplyTitle(message.title),
                            text: '',
                          ),
                        ),
                        FnthinkInlineAction(
                          key: const ValueKey('fnthink-inbox-resend'),
                          label: l10n.fnthinkResend,
                          onPressed: () => _composeFromInbox(
                            peer: peer,
                            // 重发：把这一条的标题与正文原样带进弹层，用户点发送就是"再发一次"。
                            title: message.title,
                            text: message.body,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // 点开即已读。写完之后**重新读表**，不在这个页面自己维护第二份"看没看过"：
    // 没命中（那条已被保留策略裁掉）与命中变已读，两种结果都由这一次读表如实反映出来。
    // ⚠ 发出档**不标已读**：那是我自己发出去的东西，"未读"这个状态对它不存在 ——
    // 标它一下，表现是首页的未读数被自己发的消息减掉。
    if (!outgoing) {
      final mark = widget.inboxMarkRead ?? _inboxService.markRead;
      final hit = await mark(message.messageId);

      if (!hit) {
        debugPrint('[fnthink] 标已读没命中那一行（可能已被裁掉）: ${message.messageId}');
      }
      if (!mounted) return;
      await _loadInbox();
    }
  }

  /// 「回复 / 重发」共用的一发：同一张发送页（预填不同 ⇒ 两种语义在界面上看得见）、同一个发送函数
  /// （状态与文案与幻念推送页名单行那一发完全同源）。
  ///
  /// T98 片④：原来这里开的是弹层，弹层回 null 就是取消；换成页之后**退出这一页而不点发送**
  /// 就是取消 —— 结论留在那一页上，这一页不再挂第二份"发出去是什么结果"。
  Future<void> _composeFromInbox({
    required FnthinkPeer peer,
    required String title,
    required String text,
  }) async {
    final sendTo = widget.inboxSendTo ?? _sendViaCoordinator;
    final listPeers = widget.inboxListPeers ?? _listRoster;
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => FnthinkSendPage(
          preselectedPeer: peer.peerAddress,
          prefillTitle: title,
          prefillBody: text,
          deps: FnthinkSendDeps(
            loadPeers: listPeers,
            send: sendTo,
            contractOf: () async =>
                GetIt.instance<FnthinkContractLoader>().load(),
            saveRemoteExecution: saveRemoteExecutionRow,
          ),
        ),
      ),
    );
    // 发出去的那一条会进「我发出的」那一档：这一发不是这一页写的，但那张表要跟着变。
    if (!mounted) return;
    await _loadInbox();
  }

  Future<void> _showRecordDetail(NotificationRecord record) async {
    final l10n = AppLocalizations.of(context);
    final appName = record.appName.isNotEmpty
        ? record.appName
        : l10n.notificationDetail;
    // Q2：送达日志（webhook_delivery_log）随详情一并查出，DB 异常静默降级
    List<Map<String, dynamic>> deliveryLogs = [];
    final loadLogs =
        widget.deliveryLogsLoader ?? _dbHelper.getDeliveryLogsByNotification;
    try {
      deliveryLogs = await loadLogs(record.id);
    } catch (_) {}
    if (!mounted) return;

    // UI 统一（v1.5.69）：详情改为 iOS 底部弹层（与长按屏蔽菜单同风格），
    // 替换原 Material AlertDialog 的右对齐文字按钮布局
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.separator(sheetContext),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    appName,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryLabel(sheetContext),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.detailInfo,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppColors.secondaryLabel(sheetContext),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.inputBg(sheetContext),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          contextMenuBuilder: AppTextSelectionMenu.editableText,
                          const JsonEncoder.withIndent(
                            '  ',
                          ).convert(record.toMap()),
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: AppColors.primaryLabel(sheetContext),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.deliveryLogTitle,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppColors.secondaryLabel(sheetContext),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (deliveryLogs.isEmpty)
                        Text(
                          l10n.deliveryLogEmpty,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.secondaryLabel(sheetContext),
                          ),
                        )
                      else
                        for (final log in deliveryLogs)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(top: 5),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: log['status'] == 'success'
                                        ? AppColors.green
                                        : AppColors.red,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${channelTypeDisplayName(log['tag']?.toString() ?? '')}'
                                    ' · HTTP ${log['http_code'] ?? '-'}'
                                    ' · ${log['message'] ?? ''}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.primaryLabel(
                                        sheetContext,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(height: 0.5, color: AppColors.separator(sheetContext)),
              ListTile(
                leading: const Icon(Icons.block, color: AppColors.red),
                title: Text(
                  l10n.historyActionBlockAppShort,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryLabel(sheetContext),
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _blockApp(record);
                },
              ),
              Container(height: 0.5, color: AppColors.separator(sheetContext)),
              ListTile(
                leading: const Icon(
                  Icons.playlist_remove,
                  color: Color(0xFFFF9500),
                ),
                title: Text(
                  l10n.historyActionBlockContentShort,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryLabel(sheetContext),
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _blockContent(record);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordItem(
    BuildContext context,
    NotificationRecord record,
    int index,
    int total,
  ) {
    final l10n = AppLocalizations.of(context);
    final type = record.type;
    final title = record.title.isNotEmpty ? record.title : l10n.noTitle;
    final content = record.content;
    final appName = record.appName;
    final time = _formatTime(record.postTime);
    final isKnownType = _isKnownType(type);
    final color = isKnownType ? _getTypeColor(type) : _getAppColor(appName);
    final label = isKnownType ? _getTypeLabel(l10n, type) : appName;

    // 推送渠道标签 + 各通道送达状态（T133 片2：排法与折法走唯一作者，
    // 页面只交出"这一行此刻展开没有"那一份界面状态）
    //
    // T148 片2：这些是**推送特有**的行内容，按通用件的规矩从 `lines` 挂进去 ——
    // 件不认得"通道"，正如它不该认得"远程执行"。反过来标题/时间/正文/来源四格
    // 从此不再在这一页各拼一份（差异①③⑤⑥的基座那一半就在这一步收掉）。
    final rows = record.channels.isNotEmpty
        ? record.channels
        : record.deliveryStatus.keys.toList();
    // 有没有还能再发一次的通道（T133 片1：以前只认 `paused` ⇒ 一条真失败的记录
    // 在单条这一层没有任何出口，只能去开批量模式）
    final canRepush = recordNeedsRepush(record.deliveryStatus);
    final item = HistoryRowTile(
      keyNamespace: 'history',
      identity: record.id,
      title: title,
      time: time,
      subtitle: content,
      source: appName,
      badges: [
        if (record.priority == 2)
          _tagBadge(context, l10n.priorityBadgeHigh, AppColors.red)
        else if (record.priority == 0)
          _tagBadge(context, l10n.priorityBadgeLow, Colors.grey),
      ],
      leadingLabel: label.isNotEmpty
          ? label.substring(0, 1)
          : l10n.channelBadgeFallback,
      leadingColor: color,
      corner: index == 0
          ? (index == total - 1
                ? HistoryRowCorner.only
                : HistoryRowCorner.first)
          : (index == total - 1
                ? HistoryRowCorner.last
                : HistoryRowCorner.middle),
      // F2：批量模式下点行切换选中（不打开详情），长按菜单禁用
      onTap: _batchMode
          ? () => _toggleBatchSelect(record)
          : () => _showRecordDetail(record),
      onLongPress: _batchMode ? null : () => _showRecordActionsSheet(record),
      lines: [
        if (rows.isNotEmpty)
          _buildChannelChipWrap(record, rows, l10n)
        else
          Text(
            l10n.noChannels,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        // 还能再发一次的那几条：给单条出口（T133 片1 之前只在"暂停"时出现 ⇒
        // 一条真失败的记录只能去开批量模式才能重推）
        if (rows.isNotEmpty && canRepush && widget.onPushNow != null)
          _buildPushNowButton(record, l10n),
      ],
    );

    // F2：批量模式左侧加勾选框（不可再发的那几条不可选 —— 判据与 `_batchPool` 同一个作者）
    if (!_batchMode) return item;
    final selectable = recordNeedsRepush(record.deliveryStatus);
    return Row(
      children: [
        Checkbox(
          value: _batchSelected.contains(record.id),
          activeColor: AppColors.blue,
          onChanged: selectable ? (_) => _toggleBatchSelect(record) : null,
        ),
        Expanded(
          child: Opacity(opacity: selectable ? 1 : 0.5, child: item),
        ),
      ],
    );
  }

  /// F2：批量模式底部操作栏（取消 / 补推 N 条）
  ///
  /// T148 差异⑧ 第三格（片8）：「取消」走幻念那一族的行内动作件、tone 取中性
  /// （**这一枚不让人动手做什么，只是退出**），于是底栏只剩「补推」那一枚实心。
  /// ⚠ 「补推」**刻意留着 Material `FilledButton.icon`**（账面已登记成例外）：公共件
  /// `PrimaryActionButton` 的公开签名只有 label／subtitle／onPressed，**没有图标槽**；
  /// 而这枚动作的信息量一半在那个 replay 图标上（"把这 N 条再发一次"，区别于页面里别的实心块）。
  /// 要么给件加图标参数（那是**新增公共件能力**，会牵动它 9 个既有调用点的形状一致性），
  /// 要么丢图标 —— 两条都比"把它留在原地并写明理由"贵。账照样数着它：长第二枚仍当场红。
  Widget _buildBatchBar(BuildContext context, AppLocalizations l10n) {
    final count = _batchSelected.length;
    return Container(
      color: AppColors.cardBg(context),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              FnthinkInlineAction(
                key: const ValueKey('history-batch-cancel'),
                label: l10n.cancel,
                // 中性色：它只退出批量模式，不改任何一条的状态（差异④ 那一族
                // "动作要让某样东西从此不可用才配红"在这里不成立）。
                tone: FnthinkActionTone.neutral,
                onPressed: _exitBatchMode,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: count == 0 ? null : _runBatchPush,
                icon: const Icon(Icons.replay, size: 18),
                label: Text(l10n.batchPushAction(count)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 清除记录入口：iOS 风格弹窗（替代 Material PopupMenuButton）
  Future<void> _showClearOptions() async {
    final l10n = AppLocalizations.of(context);
    // T90 片20：这枚「清除记录」的档位列表收进唯一装配点 `showIosOptionPicker`（片6 起就在）。
    // ⚠ 「全部」那一档的红色**必须一起搬过去**（不可撤销的批量删除是安全信号）⇒ 外壳为此补了
    //   `labelColor`；点外面关掉仍然回 `null`（= 什么都不清），与旧 Material 行为一致。
    final selected = await showIosOptionPicker<String>(
      context,
      title: l10n.clearRecords,
      options: [
        IosPickerOption(value: 'today', label: l10n.clearToday),
        IosPickerOption(value: 'last10', label: l10n.clearLast10),
        IosPickerOption(value: 'last50', label: l10n.clearLast50),
        IosPickerOption(
          value: 'all',
          label: l10n.clearAll,
          labelColor: AppColors.red,
        ),
      ],
    );
    if (selected == null || !mounted) return;

    int deleted = 0;
    switch (selected) {
      case 'today':
        deleted = await widget.onClearToday();
        // 删的是分页读数底下那张表：当场重读，不能留着已经不存在的行。
        unawaited(_loadSearch(reset: true));
        unawaited(_refreshTotal());
        break;
      case 'last10':
        deleted = await widget.onClearLastN(10);
        unawaited(_loadSearch(reset: true));
        unawaited(_refreshTotal());
        break;
      case 'last50':
        deleted = await widget.onClearLastN(50);
        unawaited(_loadSearch(reset: true));
        unawaited(_refreshTotal());
        break;
      case 'all':
        // T90 片13：破坏性动作一律走统一确认框（T06 那条判据：确认写在执行那一步里）。
        // #203：形状换成早退 —— 「弹了框但没按答案办」这一类由咽喉清单那条契约钉
        // （它认的是**同一个标识符被否定过**，不是某种写法）。
        // T133 量级①：确认框里的数读分页读口的总数（镜像退役后内存里没有全集）。
        final total = _forwardedTotal;
        final confirm = await IosDialogActions.askConfirm(
          context,
          title: l10n.confirmClear,
          message: l10n.clearConfirmMsg(total ?? 0),
          confirmText: l10n.confirm,
          cancelText: l10n.cancel,
          destructive: true,
          // 旧的 Material showDialog 默认点得穿，点外面 = 不清 ⇒ 照旧保留
          barrierDismissible: true,
        );
        if (!confirm) break;
        await widget.onClear();
        deleted = total ?? 0;
        // 清空之后当场重读：列表（空了）与总数（0）都要跟上，不能留着旧页。
        unawaited(_loadSearch(reset: true));
        unawaited(_refreshTotal());
        break;
    }
    if (deleted > 0 && mounted) {
      setState(() {});
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.clearedN(deleted)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // T133 量级①：两条读路并成一条（都是分页），"搜索模式"只还剩一个含义 ——
    // 挂着筛选（标题数是"已加载的筛选结果"，不是全表总数）。
    final searchMode = _hasActiveFilter;
    final records = _displayedRecords;
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        leading: _batchMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.cancel,
                onPressed: _exitBatchMode,
              )
            : null,
        title: Text(
          _batchMode
              ? l10n.batchSelectedCount(_batchSelected.length)
              : searchMode
              ? l10n.searchResultCount(records.length)
              // 无筛选的标题数是**全表总数**（读口注入）—— 分页之后 loaded.length
              // 只是"已加载的前几页"，拿来当总数就是骗人（写着 (200)，库里 5000 条）。
              : l10n.historyTitle(_forwardedTotal ?? records.length),
        ),
        actions: _batchMode
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: l10n.batchSelectAll,
                  onPressed: _selectAllRepushable,
                ),
                IconButton(
                  icon: const Icon(Icons.deselect),
                  tooltip: l10n.batchSelectNone,
                  onPressed: () => setState(_batchSelected.clear),
                ),
              ]
            : [
                IconButton(
                  icon: Icon(
                    Icons.filter_list,
                    color: _hasActiveFilter ? AppColors.blue : null,
                  ),
                  tooltip: l10n.filterTitle,
                  onPressed: _showFilterPanel,
                ),
                IconButton(
                  icon: const Icon(Icons.more_horiz),
                  tooltip: l10n.historyMoreActions,
                  onPressed: _showMoreActionsSheet,
                ),
              ],
      ),
      body: Column(
        children: [
          // #94-A：原生离线缓存满过就必须在历史里看得见一次（不静默丢失这条不变量的落点）
          if (_offlineDrops > 0) _buildOfflineDropNotice(context, l10n),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.inputBg(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                contextMenuBuilder: AppTextSelectionMenu.editableText,
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: l10n.searchHint,
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: AppColors.secondaryLabel(context),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 18,
                    color: AppColors.secondaryLabel(context),
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.cancel,
                            size: 18,
                            color: AppColors.secondaryLabel(context),
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                            _refreshSearch();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.primaryLabel(context),
                ),
                onChanged: (v) {
                  setState(() => _searchQuery = v);
                  _refreshSearch();
                },
              ),
            ),
          ),
          // 激活筛选条：显示当前时间范围摘要 + 一键清除
          if (_hasActiveFilter)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  // T148 差异⑧ 片9：这一枚是**行内文字动作**（清掉筛选），交给那一族唯一的件；
                  // 原来的 ✕ 图标是装饰（"清除"两个字已经把动作说全了），换件时去掉 ——
                  // 与批量底栏「取消」同一处理（件没有图标槽，见那一枚的例外说明）。
                  // ⚠ 字号随件从 12 → 15（行的字号归 `FnthinkInlineAction` 一处管），版式要到设备上核。
                  FnthinkInlineAction(
                    key: const ValueKey('history-filter-clear'),
                    label: l10n.clearSearchFilter,
                    tone: FnthinkActionTone.neutral,
                    onPressed: _clearAllFilters,
                  ),
                  const Spacer(),
                  if (_rangeStart != null)
                    Text(
                      _rangeSummary,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryLabel(context),
                      ),
                    ),
                ],
              ),
            ),
          _directionBar(l10n),
          Expanded(
            child: _direction == 'all'
                ? _buildAllView(l10n, records)
                : _direction == 'received' || _direction == 'sent'
                ? _buildInboxView(l10n)
                : _searchResults == null
                ? // 头一页还没回来（T133 量级①：无筛选也要当场拉第一页）。
                  // 不给"空列表"闪一下：那一闪读起来就是"历史被清了"。
                  const Center(child: CircularProgressIndicator())
                : records.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 56,
                          color: AppColors.tertiaryLabel(context),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          // 挂着筛选筛出 0 条 = "没匹配上"；没筛选而空 = "从来没有"。
                          // （分页取数循环保证取尽之前不会以空页收场 —— 停在这里的空
                          //   一定是粗筛取尽后的空。）
                          searchMode ? l10n.noMatchRecords : l10n.noRecords,
                          style: TextStyle(
                            color: AppColors.secondaryLabel(context),
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: records.length + (_hasMore ? 1 : 0),
                    separatorBuilder: (_, _) => Padding(
                      padding: const EdgeInsets.only(left: 56),
                      child: Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: AppColors.separator(context),
                      ),
                    ),
                    itemBuilder: (context, index) {
                      // 末尾加载指示：粗筛还没取尽（T133 量级① 两条读路都有下一页）
                      if (index >= records.length) {
                        return Padding(
                          key: const ValueKey('history-load-more'),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: _loadingMore
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    l10n.loadMoreHint,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.tertiaryLabel(context),
                                    ),
                                  ),
                          ),
                        );
                      }
                      return _buildRecordItem(
                        context,
                        records[index],
                        index,
                        records.length,
                      );
                    },
                  ),
          ),
          // F2：批量模式底部操作栏
          if (_batchMode) _buildBatchBar(context, l10n),
        ],
      ),
    );
  }
}
