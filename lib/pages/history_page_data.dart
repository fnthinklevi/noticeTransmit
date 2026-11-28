part of 'history_page.dart';

// T184 B：历史页取数域——搜索分页、组行回表、总条数与筛选边界。
// 纯搬移：方法体、判据、key 与拆分前逐字一致。
// ignore_for_file: invalid_use_of_protected_member
extension _HistoryPageData on _HistoryPageState {
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
      final want = loaded.length + _HistoryPageState._pageSize;
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
          limit: _HistoryPageState._pageSize,
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
}
