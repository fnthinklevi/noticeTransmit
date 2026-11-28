part of 'history_page.dart';

// T184 B：幻念收件区——收件/发出取数、未读、批量已读与指令状态账。
// 纯搬移：方法体、判据、key 与拆分前逐字一致。
// ignore_for_file: invalid_use_of_protected_member
extension _HistoryPageInbox on _HistoryPageState {
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
}
