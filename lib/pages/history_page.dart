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
import '../services/fnthink_out_status.dart';
import '../services/fnthink_peer_service.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../services/fnthink_sender_display.dart';
import '../services/notification_service.dart';
import '../services/platform_channel.dart';
import '../theme/app_colors.dart';
import '../database/database_helper.dart';
import '../models/notification_record.dart';
import '../models/delivery_status.dart';
import '../models/fnthink_inbox_message.dart';
import '../models/fnthink_peer.dart';
import '../models/fnthink_remote_execution_record.dart';
import '../services/fnthink_remote_action_labels.dart';
import '../services/fnthink_remote_execution_state_words.dart';
import '../services/fnthink_remote_reason_words.dart';
import '../widgets/app_input_style.dart';
import '../widgets/channel_visuals.dart';
import '../services/fnthink_remote_out_record.dart';
import '../widgets/history_row_tile.dart';
import '../widgets/help_note_button.dart';
import '../widgets/fnthink_card.dart'
    show
        FnthinkActionTone,
        FnthinkChoiceChip,
        FnthinkFilledAction,
        FnthinkInlineAction,
        FnthinkMarkRole,
        FnthinkStatusMark,
        FnthinkSubMark;
import '../widgets/primary_action_button.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/ios_option_picker.dart';
import '../widgets/ios_progress_dialog.dart';
import '../widgets/app_text_selection_menu.dart';
import '../widgets/ios_input_dialog.dart';
import '../services/repush_eligibility.dart';
import '../services/history_channel_chips.dart';
import '../services/history_group_store.dart';
import '../services/history_paging.dart';
import 'fnthink_send_page.dart';

part 'history_page_actions.dart';
part 'history_page_filters.dart';
part 'history_page_details.dart';
part 'history_page_rows.dart';
part 'history_page_swipe.dart';

/// 转发那本账的一页读口（T133 量级①）：一页 = `(本页记录, 是否还有下一页, 本页行数)`。
///
/// ⚠ 走 (c) 之后**没有"粗筛／精筛"两层了**（送达档判定落进 `delivery_bucket` 那一列，
/// SQL 一层就筛完），所以第三位与第一位是同一个数：翻页 offset 按它累加就是按行数累加。
/// 两层筛的年代里，按精筛后条数累加会把游标往回拨 —— 那一段留在这里当理由，
/// 别再把它当成两种数（替身 `fakeForwardedLoader` 也照这一条切片）。
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

  /// 送达详情子页里「重推此通道」逐格那一枚的**可用性**（T154 片3）。
  ///
  /// null = 一律可用。判据住在服务层（`canRepushChannelIndividually`：这一族现在还配着没有），
  /// 页面只把它读出来画成灰的或可点的 —— **不自己判「这一族还在不在」**。
  final bool Function(String channel)? channelRepushAvailable;

  /// 逐格／子页底部「全部重推」那一发（T154 片3）。范围是**用户指着的那几格**，
  /// 与当前启用通道的交集由服务层算（`repushChannels`）——
  /// 页面不在这一层判断"哪些真的发得出去"，否则两处判据迟早漂开。
  final Future<void> Function(NotificationRecord record, List<String> channels)?
  onPushChannels;

  /// 收件（幻念）那一档的数据来源。默认走 `FnthinkInboxService`，测试注入内存列表 ——
  /// 让 widget 测试**不必去开 sqlite**：那条路在 flutter_test 绑定下要向平台通道要真实库路径，
  /// 桩答 null 就永远等不到（实测整份用例卡死在 00:00，与页面逻辑无关）。
  final Future<List<FnthinkInboxMessage>> Function()? inboxLoader;

  /// 标已读的那一斧子。同上：默认走收件服务，测试注入替身。
  final Future<bool> Function(String messageId)? inboxMarkRead;

  /// T208：批量标已读的两个写口＋未读数读口。都可注入 —— 与 `inboxMarkRead` 同一条理由
  /// （widget 测试不开真库）。判据不在页面里：**回的是受影响行数**，页面只负责如实说出来。
  final Future<int> Function(List<String> messageIds)? inboxMarkReadMany;
  final Future<int> Function()? inboxMarkReadAll;
  final Future<int> Function()? inboxUnreadCount;

  /// 幻念消息（收件/发件都行）批量删除的写口。默认走 `FnthinkInboxService.deleteMessages`，
  /// 测试注入替身 —— 与 `inboxLoader` 同一条理由（widget 测试不开真库）。
  final Future<int> Function(List<String> messageIds)? inboxDeleteMany;

  /// 批量标已读之后的通知（T208）：首页那张「幻念收件」卡要用**同一个算法**重算未读，
  /// 页面不许自己减（它手上只有分页过的列表，数出来永远偏小）。
  final VoidCallback? onInboxChanged;

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

  /// 收件行上「一条远程指令」的状态读口（T141①）：按消息号批量查执行记录。
  /// 默认走真库，测试注入替身 —— 与 `inboxLoader` 同一条理由：真库读口在
  /// flutter_test 绑定下要向平台通道要数据库路径。
  /// ⚠ 判定发生在落库之后（同一轮内），所以可能短暂读到空：那时只换标题、
  /// 不画状态，不编一句「还没执行」出来。
  final Future<Map<String, FnthinkRemoteExecutionRecord>> Function(
    List<String> messageIds,
  )?
  remoteCommandRecordsLoader;

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

  /// 收件详情拆回传正文（文字／图像）用的契约（T124② 片2）。
  ///
  /// null = 生产默认（`FnthinkContractLoader.cached`）；测试注入，免得为一张图去起 loader。
  /// 契约没就绪时详情退回"正文原样显示"，不把一条消息藏起来。
  final FnthinkContract? reportContract;

  /// 规则扇出组的读口（T147②）。null = 生产默认（`HistoryGroupStore`）；
  /// 测试注入内存列表，不去碰 SharedPreferences。
  final Future<List<HistoryGroup>> Function()? historyGroupsLoader;

  /// 组行算「扇出 X·失败 Y」要按成员 id 回表读送达状态。null = 真库批量读；
  /// 测试注入替身（与 `forwardedLoader` 同一条理由：widget 测试不开 sqlite）。
  final Future<List<NotificationRecord>> Function(List<String> ids)?
  groupMembersLoader;

  const HistoryPage({
    super.key,
    this.forwardedLoader,
    this.forwardedCountLoader,
    required this.onClear,
    required this.onExport,
    required this.onClearToday,
    required this.onClearLastN,
    this.onPushNow,
    this.channelRepushAvailable,
    this.onPushChannels,
    this.inboxLoader,
    this.sentLoader,
    this.inboxMarkRead,
    this.inboxMarkReadMany,
    this.inboxMarkReadAll,
    this.inboxUnreadCount,
    this.inboxDeleteMany,
    this.onInboxChanged,
    this.inboxFindPeer,
    this.inboxSendTo,
    this.inboxListPeers,
    this.deliveryLogsLoader,
    this.remoteCommandRecordsLoader,
    this.initialDirection = 'forwarded',
    this.focusMessageId,
    this.reportContract,
    this.historyGroupsLoader,
    this.groupMembersLoader,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
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

  /// T147②：规则扇出组（与转发行混排；只在不带筛选时展示）。
  List<_HistoryGroupView> _groupViews = const [];

  /// 分页游标：本会话已经扫过多少行。走 (c) 之后 SQL 一层就筛完，这个数**既是本页行数也是
  /// 筛中的行数**（名字里的 coarse 是两层筛年代的残留，留着因为它同时就是 offset）。
  /// 之所以按读口回报的行数累加而不按 `_pageSize` 累加：最后一页不满一页。
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

  // ── 统一选择模式（三个 tab 共用）──
  bool _selectMode = false;
  final Set<String> _selected = {};

  /// T133 片2：哪些记录的通道 chip 被展开了。
  ///
  /// 这是**界面状态**而不是事实，所以它住在页面里而不是那个排法文件里 ——
  /// 后者只回答"该露哪几枚"，不该知道"这一行此刻被谁点开过"。

  /// 当前展示的记录（统一走分页读数；null = 头一页还没回来）
  List<NotificationRecord> get _displayedRecords => _searchResults ?? const [];

  /// 当前 tab 是否支持批量重发（转发和幻念发件支持）
  bool get _canResend => _direction == 'forwarded' || _direction == 'sent';

  /// 当前 tab 是否有独立数据源（幻念收件/发件走 inbox 列表）
  bool get _isFnthinkTab => _direction == 'received' || _direction == 'sent';

  /// 幻念档搜索过滤后的列表
  List<FnthinkInboxMessage> get _filteredInbox {
    if (!_isFnthinkTab) return const [];
    if (_searchQuery.isEmpty) return _inbox;
    final q = _searchQuery.toLowerCase();
    return _inbox.where((m) {
      return m.title.toLowerCase().contains(q) ||
          m.body.toLowerCase().contains(q) ||
          m.sender.toLowerCase().contains(q);
    }).toList();
  }

  /// T147②：转发行 + 组行按时间混排；挂着筛选时只给转发行（理由见 `_refreshGroups`）。
  /// 返回 `Object` 是因为两种行不是同一类型 —— 列表 builder 按 `is` 分派，不靠字段猜。
  List<Object> get _forwardedRows {
    final records = _displayedRecords;
    if (_hasActiveFilter || _groupViews.isEmpty) return records;
    final rows = <Object>[...records, ..._groupViews];
    rows.sort((a, b) => _rowTime(b).compareTo(_rowTime(a)));
    return rows;
  }

  int _rowTime(Object row) => row is _HistoryGroupView
      ? row.group.at
      : (row as NotificationRecord).postTime;

  /// 可补推池（仅转发档使用）：当前展示列表里**可以再发一次**的那些。
  List<NotificationRecord> get _batchPool => _displayedRecords
      .where((r) => recordNeedsRepush(r.deliveryStatus))
      .toList();

  /// 当前 tab 所有可选记录的 id 列表（用于全选/反选）
  List<String> get _allSelectableIds {
    if (_isFnthinkTab) {
      return _filteredInbox.map((m) => m.messageId).toList();
    }
    return _displayedRecords.map((r) => r.id).toList();
  }

  @override
  void initState() {
    super.initState();
    _direction = widget.initialDirection;
    _swipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..addListener(_onSwipeTick);
    // 点通知跳进来时带上的那一条（T83）。抄进 State 而不是每次读 widget：
    // 它是一次**待兑现的意图**，兑现过就要能清空，而 widget 的字段是不变的。
    _pendingFocusMessageId = widget.focusMessageId;
    _scrollController.addListener(_onScroll);
    // 取一次溢出计数：首页首帧后的 hydrateOfflineData() 已经跑过 drainOfflineCache
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
  /// ⚠ 走 (c) 之后送达档判定落进 `delivery_bucket` 那一列，SQL 一层就筛完 —— 已经没有
  /// 「粗筛宽、精筛窄」那两层了，所以「空页不许停手」在这一条读路上不会再触发；
  /// 条件留着是纵深：读口可注入（`forwardedLoader`，测试替身只做切片不做筛选），
  /// 「本页 0 条但 hasMore 为真」这种回报仍不许停手 —— 停手等于把后面还有的说成没有了。
  /// 游标按读口回报的行数累加（见 [_coarseOffset]），终止性由它保证：hasMore 为真时
  /// 每轮至少前进那几行，游标单调递增直到取尽。
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
      // T147②：组行只在无边界的默认视图里与转发行混排；挂着筛选时不画 ——
      // 组行是合成行，没有逐条的送达桶可筛，混进来会让"筛过了"变成一句不实陈述。
      if (reset && !_hasActiveFilter) unawaited(_refreshGroups());
    } catch (e) {
      debugPrint('历史搜索失败: $e');
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<List<NotificationRecord>> _loadGroupMembers(List<String> ids) async {
    final rows = await DatabaseHelper().getNotificationsByIds(ids);
    return rows.map(NotificationRecord.fromMap).toList();
  }

  /// 读组映射 + 按成员 id 回表算「扇出 X·失败 Y」。
  ///
  /// X 是**组里记下的成员数**（不是当前分页里碰巧在的那几条）；Y 是回表找到的成员里
  /// 落进「没发出去的」那一桶的条数。成员全被保留策略裁掉 ⇒ 不画幽灵组行。
  Future<void> _refreshGroups() async {
    try {
      final groups =
          await (widget.historyGroupsLoader ??
              () => HistoryGroupStore().list())();
      final ids = <String>{for (final g in groups) ...g.memberIds}.toList();
      final members = ids.isEmpty
          ? const <NotificationRecord>[]
          : await (widget.groupMembersLoader ?? _loadGroupMembers)(ids);
      final byId = {for (final m in members) m.id: m};
      final views = <_HistoryGroupView>[];
      for (final group in groups) {
        if (group.memberIds.length < 2) continue;
        final found = group.memberIds.where(byId.containsKey).toList();
        if (found.isEmpty) continue;
        var failed = 0;
        for (final id in found) {
          if (deliveryBucketOf(byId[id]!.deliveryStatus) ==
              deliveryBucketNotDelivered) {
            failed++;
          }
        }
        views.add(
          _HistoryGroupView(
            group: group,
            total: group.memberIds.length,
            failed: failed,
          ),
        );
      }
      if (!mounted) return;
      setState(() => _groupViews = views);
    } catch (e) {
      debugPrint('历史组行读取失败: $e');
    }
  }

  /// 时间范围摘要（筛选条显示用），如 09-01 ~ 09-07 或单日 2026-09-08
  String get _rangeSummary {
    if (_rangeStart == null) return '';
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (_rangeEnd == null) return fmt(_rangeStart!);
    return '${fmt(_rangeStart!)} ~ ${fmt(_rangeEnd!)}';
  }

  Color _getTypeColor(BuildContext context, String? type) {
    switch (type) {
      case 'sms':
        return AppColors.orange;
      case 'call_incoming':
      case 'call_answered':
      case 'call_ended':
        return AppColors.green;
      case 'wechat':
        return AppColors.brandWeChat;
      case 'qq':
        return AppColors.brandQQ;
      case 'alipay':
        return AppColors.brandAlipay;
      case 'system':
        return AppColors.secondaryLabel(context);
      case 'battery_charging':
      case 'battery_full':
      case 'battery_low_30':
      case 'battery_low_20':
        return AppColors.blue;
      default:
        return AppColors.indigo;
    }
  }

  Color _getAppColor(String appName) {
    if (appName.isEmpty) return AppColors.indigo;
    final hash = appName.hashCode;
    return AppColors.avatarPalette[hash.abs() % AppColors.avatarPalette.length];
  }

  Color _getChannelColor(BuildContext context, String channel) {
    // channel 是送达键（chan:<slug>），早期记录也可能是本地化显示名——channelKey
    // 两种都认。品牌色只从 `channel_visuals` 那张唯一表取：这里是第二个作者时，
    // 同一家企业微信在通道卡与历史行就会是两种绿（本仓实测过）。
    final slug = channelKey(channel);
    if (!hasChannelVisual(slug)) return AppColors.secondaryLabel(context);
    return channelVisual(slug).color;
  }

  /// 状态那一格（词表→人话、词表→颜色）住 `services/delivery_display.dart`，
  /// 是**唯一作者**（T150 片1）：这一页以前自己拿 `default:` 兜底成「发送中」，
  /// 于是任何对不上号的状态串都会被界面替本机说一句"这条正在发"。

  // ── P1 筛选面板 ──

  bool _sameDay(DateTime? a, DateTime? b) =>
      a != null &&
      b != null &&
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day;

  /// 送达日志查询/展示用
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // ── 快捷屏蔽（长按记录菜单与详情页按钮共用）──

  FilterService get _filterService => GetIt.instance<FilterService>();

  /// 收件的读写一律从这一层走。页面上那句 `_dbHelper.loadFnthinkInbox(...)` 更短，代价是
  /// **排序口径与「标已读命中没有」各长一份** —— 首页入口卡的未读数与这里的行数迟早对不上。
  /// 写成 getter 而不是字段：注入替身的 widget 测试从不注册它，解析只能发生在默认分支上。
  FnthinkInboxService get _inboxService =>
      GetIt.instance<FnthinkInboxService>();

  /// 收件详情拆回传正文用的契约（T124② 片2）。注入优先；生产取 loader 的缓存，
  /// 还没加载好就返回 null（详情退化成正文原样显示，不藏消息）。
  FnthinkContract? _reportContract() {
    final injected = widget.reportContract;
    if (injected != null) return injected;
    if (!GetIt.instance.isRegistered<FnthinkContractLoader>()) return null;
    return GetIt.instance<FnthinkContractLoader>().cached;
  }

  /// 屏蔽该应用：按当前过滤模式分流。
  /// - allow（白名单）模式：仅选中应用会被推送 → 应用在名单中则移出即屏蔽；
  ///   不在名单中说明本就不推送，提示无需操作。
  /// - block（黑名单）模式：应用加入屏蔽名单；已在名单中提示无需操作。
  /// 返回后由调用方刷新列表显示。
  /// 本应用自身的通知（电量提醒/测试推送等）不经过应用过滤与黑白名单，
  /// 由电量规则与内置逻辑直接控制——「屏蔽该应用」对其无效，需特判提示。
  static const _selfPackage = 'com.fnthink.notice';

  // ── T48 收件档（表 `fnthink_messages`，别人推给本机的消息）──
  //
  // ⚠ "方向"是**数据源切换**，不是又一个筛选条件：转发记录与收件行来自两张表、分页口径不同，
  //   拼进同一条时间线会出现"翻页时同一条出现两次、或整条一次都不出现"。所以整档换列表。
  // late 而非写死默认值：进来停在哪一档由 widget.initialDirection 定（首页那张未读卡要它=收件）。
  late String _direction;
  List<FnthinkInboxMessage> _inbox = const [];
  bool _inboxLoaded = false;

  /// 收件未读数（「一键已读」那一格的可用性与确认框里的 N）。**只是缓存一个读数**：
  /// 数法只有 `FnthinkInboxService.unreadCount` 一处，页面不自己数列表（列表有 limit）。
  int _inboxUnread = 0;

  /// 「进来就要展开的那一条」还欠着的那一次兑现（T83，只在**这一次进入**里有效）。
  /// 兑现一次就清空（见 [_applyPendingFocus]）；把它落盘则会变成"下次冷启动还跳去三天前那条通知"。
  String? _pendingFocusMessageId;

  /// 幻念那一族当前挂在哪一档：`kFnthinkDirectionIn`（收件）或 `kFnthinkDirectionOut`（发出）。
  /// 转发档不用它。**它和 `_direction` 不是一件事**：`_direction` 是界面上哪一格亮着，
  /// 这个是"手上这份 `_inbox` 是哪本账"—— 切档时两本账的读法与空态都不一样。
  String _inboxDirection = kFnthinkDirectionIn;

  /// 指令行的状态账（T141①）：消息号 → 判定层落的执行记录。
  /// 只在装载收件行时刷新；读失败保持旧值/空 —— 界面上那格不画，不编话。
  Map<String, FnthinkRemoteExecutionRecord> _commandRecords = const {};

  /// T172：发送人显示档位 + 名单（收件行与详情共用同一份解析）。
  FnthinkSenderDisplayMode _senderMode = FnthinkSenderDisplayMode.aliasFirst;
  Map<String, FnthinkPeer> _rosterByAddress = const {};

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

    // T172：把这一屏要用的名单与显示档一次读齐。名单读失败只让名字回落到地址码，
    // 不能让整页收件打不开 —— 地址码本来就是唯一能被核对的那一项。
    var mode = FnthinkSenderDisplayMode.aliasFirst;
    final byAddress = <String, FnthinkPeer>{};
    try {
      mode = (await FnthinkSenderDisplaySettings.load()).mode;
      final addresses = rows
          .map((m) => m.sender)
          .where((s) => s.isNotEmpty)
          .toSet();
      final findPeer = widget.inboxFindPeer ?? _findPeerInRoster;
      for (final address in addresses) {
        final peer = await findPeer(address);
        if (peer != null) byAddress[address] = peer;
      }
    } catch (e) {
      debugPrint('[fnthink] 收件发送人显示资料读失败（回落地址码）：$e');
    }

    if (!mounted) return;
    // 期间用户可能又切了档：只把结果交给它属于的那一档。否则"读回来的是发出、画在收件档上"
    // —— 那正是两本账混起来的形状，而它看起来就像一条真的收件。
    if (direction != _inboxDirection) return;
    final unread = direction == kFnthinkDirectionIn
        ? await _readInboxUnread()
        : 0;
    if (!mounted) return;
    if (direction != _inboxDirection) return;
    setState(() {
      _inbox = rows;
      _inboxLoaded = true;
      _senderMode = mode;
      _rosterByAddress = byAddress;
      _inboxUnread = unread;
    });
    // 发出档没有指令行：传空把上一档的账清掉，免得切档后旧状态还挂在同号消息上。
    unawaited(
      _loadCommandRecords(direction == kFnthinkDirectionIn ? rows : const []),
    );
  }

  // ── T208：收件档多选 +「确认已读」＋「⋯→一键已读」 ──────────────────────────
  //
  // 三件事的分工写死在这里，别往别处挪：
  //  · **能标哪些**由 DB 那两个写口的 WHERE 决定（`read = 0 AND direction = 'in'`）；
  //  · **标了几条**由写口回的受影响行数说；
  //  · **未读数**只由 `unreadCount` 那一处算，页面不自己减（列表有 limit，减着减着就错）。

  Future<int> _readInboxUnread() async {
    try {
      return await (widget.inboxUnreadCount ?? _inboxService.unreadCount)();
    } catch (e) {
      // 读失败沿用上一个数（0 在这张卡上的意思是"没有未读"，与"没读到"是两件事）。
      debugPrint('[fnthink] 收件未读数没取到，沿用上一个数: $e');
      return _inboxUnread;
    }
  }

  void _enterInboxSelect(FnthinkInboxMessage m) {
    setState(() {
      _selectMode = true;
      _selected
        ..clear()
        ..add(m.messageId);
    });
  }

  void _toggleInboxSelect(FnthinkInboxMessage m) {
    setState(() {
      if (!_selected.remove(m.messageId)) {
        _selected.add(m.messageId);
      }
    });
  }

  /// 退出选项态。`inSetState: false` 给"已经在 setState 里"的调用点（切档那一处）。
  void _exitInboxSelect({bool inSetState = true}) {
    if (!_selectMode && _selected.isEmpty) return;
    void clear() {
      _selectMode = false;
      _selected.clear();
    }

    if (inSetState) {
      setState(clear);
    } else {
      clear();
    }
  }

  Future<void> _runMarkReadSelected() async {
    final ids = _selected.toList(growable: false);
    if (ids.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final mark = widget.inboxMarkReadMany ?? _inboxService.markReadMany;
    final done = await mark(ids);
    if (!mounted) return;
    _exitInboxSelect();
    // 写完之后**重新读表**：未读点、列表、首页那个数全部由读决定。
    await _loadInbox();
    widget.onInboxChanged?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.inboxMarkReadDone(done))));
  }

  Future<void> _runMarkAllRead() async {
    final l10n = AppLocalizations.of(context);
    // 确认框里的 N 走同一个算法现读一次（不用 `_inboxUnread` 那份可能已经旧了的缓存）。
    final total = await _readInboxUnread();
    if (!mounted || total == 0) return;
    final ok = await IosDialogActions.askConfirm(
      context,
      title: l10n.inboxMarkAllRead,
      message: l10n.inboxMarkAllConfirmMsg(total),
      confirmText: l10n.inboxMarkReadAction,
    );
    if (!ok || !mounted) return;
    final mark = widget.inboxMarkReadAll ?? _inboxService.markReadAll;
    final done = await mark();
    if (!mounted) return;
    await _loadInbox();
    widget.onInboxChanged?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.inboxMarkReadDone(done))));
  }

  /// 指令行的状态账（T141①）：按这批收件行的消息号一发批量查。
  /// 空列表 = 这档没有收件行（发出档）⇒ 清账。读失败保持空 ——
  /// 界面上那行退回「换了标题、不画状态」，与「记录还没有」同一形状。
  Future<void> _loadCommandRecords(
    List<FnthinkInboxMessage> incomingRows,
  ) async {
    final ids = [
      for (final m in incomingRows)
        if (m.messageId.isNotEmpty) m.messageId,
    ];
    if (ids.isEmpty) {
      if (!mounted) return;
      setState(() => _commandRecords = const {});
      return;
    }
    final load =
        widget.remoteCommandRecordsLoader ??
        _dbHelper.remoteExecutionRecordsByMessageIds;
    try {
      final map = await load(ids);
      if (!mounted) return;
      setState(() => _commandRecords = map);
    } catch (_) {
      // 读不出来就不画状态；正文也不因此多出一句话。
    }
  }

  /// 三档的固定顺序：左右滑按它切换，到头即止（不循环）。
  static const List<String> _directionOrder = ['forwarded', 'received', 'sent'];

  /// 本次横滑累计位移（右正左负）。只用于「慢拖」：
  /// 轻扫有速度看速度，慢慢拖到半屏也有位移可看 —— 只认速度会让慢拖失灵。
  double _swipeDx = 0;

  /// 左右滑切档的过渡动画：旧内容滑出（0→0.5）→ 中点换档 → 新内容滑入（0.5→1）。
  ///
  /// 为什么在中点才换：_setDirection 会换数据源并触发异步读表，若一开始就换，
  /// 滑出的是"新档的加载中"而不是用户眼前那一屏；中点换能让旧档完整滑走。
  late final AnimationController _swipeController;
  bool _swipeAnimating = false;
  bool _swipeSwitched = false;
  String? _swipeTarget;

  /// 动画方向：true = 左滑切下一档（旧内容向左、新内容从右入），false 反之。
  bool _swipeForward = true;

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _swipeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // T133 量级①：两条读路并成一条（都是分页），"搜索模式"只还剩一个含义 ——
    // 挂着筛选（标题数是"已加载的筛选结果"，不是全表总数）。
    final searchMode = _hasActiveFilter;
    final records = _displayedRecords;
    // 批量模式下转发行只显示记录（不混排组行）
    final rows = _selectMode && !_isFnthinkTab ? records : _forwardedRows;
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        // 统一选择模式顶栏
        leading: _selectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.cancel,
                onPressed: _exitSelectMode,
              )
            : null,
        title: Text(
          _selectMode
              ? l10n.batchSelectedCount(_selected.length)
              : searchMode
              ? l10n.searchResultCount(records.length)
              // 无筛选的标题数是**全表总数**（读口注入）—— 分页之后 loaded.length
              // 只是"已加载的前几页"，拿来当总数就是骗人（写着 (200)，库里 5000 条）。
              : l10n.historyTitle(_forwardedTotal ?? records.length),
        ),
        actions: _selectMode
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: l10n.batchSelectAll,
                  onPressed: _selectAllCurrent,
                ),
                IconButton(
                  icon: const Icon(Icons.check_box_outline_blank),
                  tooltip: l10n.invertSelection,
                  onPressed: _invertSelection,
                ),
                IconButton(
                  icon: const Icon(Icons.deselect),
                  tooltip: l10n.batchSelectNone,
                  onPressed: () => setState(_selected.clear),
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
            child: GestureDetector(
              // 内容区左右滑切三档（T84 那排芯片的滑动手势版）。竖滑不抢：
              // 这里的识别器只认横向，列表的纵向滚动照旧归 ListView。
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => _swipeDx = 0,
              onHorizontalDragUpdate: (d) => _swipeDx += d.delta.dx,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              // 切档过渡：只平移内容区，顶部芯片与搜索框不动；ClipRect 防止滑出边界。
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: _swipeController,
                  builder: (context, child) {
                    final width = MediaQuery.sizeOf(context).width;
                    return Transform.translate(
                      offset: Offset(_swipeOffsetFraction() * width, 0),
                      child: child,
                    );
                  },
                  child: _direction == 'received' || _direction == 'sent'
                      ? _buildInboxView(l10n)
                      : _searchResults == null
                      ? // 头一页还没回来（T133 量级①：无筛选也要当场拉第一页）。
                        // 不给"空列表"闪一下：那一闪读起来就是"历史被清了"。
                        const Center(child: CircularProgressIndicator())
                      : rows.isEmpty
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
                                searchMode
                                    ? l10n.noMatchRecords
                                    : l10n.noRecords,
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
                          itemCount: rows.length + (_hasMore ? 1 : 0),
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
                            if (index >= rows.length) {
                              return Padding(
                                key: const ValueKey('history-load-more'),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
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
                                            color: AppColors.tertiaryLabel(
                                              context,
                                            ),
                                          ),
                                        ),
                                ),
                              );
                            }
                            final row = rows[index];
                            if (row is _HistoryGroupView) {
                              return _buildGroupRow(
                                context,
                                row,
                                index,
                                rows.length,
                              );
                            }
                            return _buildRecordItem(
                              context,
                              row as NotificationRecord,
                              index,
                              rows.length,
                            );
                          },
                        ),
                ),
              ),
            ),
          ),
          // F2：批量模式底部操作栏
          if (_selectMode) _buildBatchBar(context, l10n),
        ],
      ),
    );
  }
}

/// 组行的**读时视图**：组本身（持久事实）＋回表算出的 X/Y（现在的事实）。
class _HistoryGroupView {
  const _HistoryGroupView({
    required this.group,
    required this.total,
    required this.failed,
  });

  final HistoryGroup group;

  /// 组里记下的成员数（不是当前分页里碰巧在的那几条）。
  final int total;

  /// 回表找到的成员里，落进「没发出去的」那一桶的条数。
  final int failed;
}
