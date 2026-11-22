part of 'history_page.dart';

// 离线提示、方向栏、收件行、群行、记录行与批量底栏。
// R3 拆分：extension 挂在 _HistoryPageState 上（同 library），行为与拆分前完全一致。
// ignore_for_file: invalid_use_of_protected_member
extension _HistoryPageRows on _HistoryPageState {
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

  /// 时间那一格的格式化在 `widgets/history_row_tile.dart`（T148：那一列此前每页一份笔）。
  /// 这里只留"输入可能是 String"这一层（DB 里存的形态两种都有）。
  String _formatTime(dynamic timestamp, {bool withSeconds = false}) {
    if (timestamp == null) return '';
    final ms = timestamp is int
        ? timestamp
        : int.tryParse(timestamp.toString()) ?? 0;
    return historyRowTime(ms, withSeconds: withSeconds);
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

  /// 一个地址码在屏上叫什么。地址码永远在最后兜底；名字只是让人少查一次。
  String _senderText(String address) {
    if (address.isEmpty) return '';
    final peer = _rosterByAddress[address];
    return fnthinkSenderLabel(
      mode: _senderMode,
      address: address,
      alias: peer?.alias ?? '',
      peerName: peer?.peerName ?? '',
    );
  }

  Widget _directionBar(AppLocalizations l10n) {
    // 三格一排，窄屏仍可能放不下 ⇒ 横着可滚（T84 加档时量出来过：写死 Row 的下一幕
    // 就是 RenderFlex overflow 半条芯片）。T193 撤掉了第四档「全部」。
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _filterChip(
            l10n.fnthinkDirForwarded,
            _direction == 'forwarded',
            () => _tapDirection('forwarded'),
            keyName: 'direction-chip-forwarded',
          ),
          const SizedBox(width: 8),
          _filterChip(
            l10n.fnthinkDirInbox,
            _direction == 'received',
            () => _tapDirection('received'),
            keyName: 'direction-chip-received',
          ),
          const SizedBox(width: 8),
          _filterChip(
            l10n.fnthinkDirSent,
            _direction == 'sent',
            () => _tapDirection('sent'),
            keyName: 'direction-chip-sent',
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
    final peer = m.sender.isEmpty ? l10n.unknown : _senderText(m.sender);
    // T141①：指令行不再把信封原文当标题画出来（维护者 2026-10-17 拍板：界面要显示）。
    // 「是不是指令」只有一个作者 = 包侧信封的 decode（lib/ 不出现前缀字面量，守卫钉着）；
    // 状态/原因读的是判定层落的执行记录（按消息号关联）。读不到就只换标题、不画状态、
    // 不编一句「还没执行」—— 存量行与刚落库未判定的那一瞬都是这个形状。
    final command = outgoing ? null : RemoteCommandEnvelope.decode(m.body);
    final record = command == null ? null : _commandRecords[m.messageId];
    // T208：选项态现在所有幻念档都支持（收件、发件）
    const selectable = true;
    final tile = HistoryRowTile(
      keyNamespace: 'fnthink-inbox',
      identity: m.messageId,
      title: command == null
          ? (m.title.isEmpty ? m.body : m.title)
          : '${l10n.fnthinkRemoteCommandRowTitle}'
                ' · ${fnthinkRemoteActionLabel(l10n, command.item)}',
      // 时间此前混在那串散文里（`发件人 · 备用 · 03-01 12:00`），拆成自己的格子才有对齐的右列
      // —— 这是 T148 差异②（各页时间列不一致）里收件那一半。
      // ⚠ 发出档里 `receivedAt` 记的是本机**发出**的时刻（含义随方向变，与 `sender` 同一套两用）。
      time: historyRowTime(m.receivedAt, withSeconds: true),
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
        // T195：来源应用名（维护者 2026-10-25：状态栏看得到、进了收件历史就没了）。
        // **非空才画** —— 空串＝手动发送／旧发送端／端点消息，画一枚空的徽标等于替它编一个来源。
        if (m.appName.isNotEmpty)
          _tagBadge(context, m.appName, AppColors.secondaryLabel(context)),
      ],
      // 本机报出去的那一串是**原话**（`delivered` / `rejected_*` / `failed_action`）：
      // 翻成人话属 T144 片2，那一版改的是这一格的来源，不改它的画法。
      // ⚠ 指令行不走这一格：它带的是判定层的状态词与理由（T141①），见上面那个 helper。
      statusMessage: command != null
          ? _remoteCommandStatusLine(l10n, record)
          : (outgoing || m.ackResult.isEmpty ? null : m.ackResult),
      statusColor: AppColors.secondaryLabel(context),
      corner: index == 0
          ? (index == total - 1
                ? HistoryRowCorner.only
                : HistoryRowCorner.first)
          : (index == total - 1
                ? HistoryRowCorner.last
                : HistoryRowCorner.middle),
      // T208：选项态下点行**只切勾选**，不打开详情 —— 那一下要是不拦，勾第二条时就会
      // 弹出它自己的详情页，选择态在用户眼里"看不见了"。长按进入（行件本来就有这个槽）。
      onTap: selectable && _selectMode
          ? () => _toggleInboxSelect(m)
          : () => _showInboxDetail(m, outgoing: outgoing),
      onLongPress: selectable && !_selectMode
          ? () => _enterInboxSelect(m)
          : null,
    );

    if (!selectable || !_selectMode) return tile;
    return Row(
      children: [
        Checkbox(
          value: _selected.contains(m.messageId),
          activeColor: AppColors.blue,
          onChanged: (_) => _toggleInboxSelect(m),
        ),
        Expanded(child: tile),
      ],
    );
  }

  /// 指令行的状态那一句（T141①）。词只来自两张既有表的状态/理由作者，
  /// 这里只做拼装：「状态词」+（有理由/结果时）「 · 那一句」。
  /// 记录还没有（刚落库未判定/判定异常/存量行）⇒ null：不画，不编「还没执行」。
  /// ⚠ 理由走 `remoteReasonText`（词表外原样带出，不编）——在页面里半翻
  ///   会长出第二个词表，而"半翻"的表现是有些词翻了、有些没翻（T144 那句原话）。
  String? _remoteCommandStatusLine(
    AppLocalizations l10n,
    FnthinkRemoteExecutionRecord? record,
  ) {
    if (record == null) return null;
    var line = fnthinkRemoteExecutionStateWord(
      l10n,
      record.state,
      reason: record.reason,
    );
    if (record.reason.isEmpty) {
      if (record.result.isNotEmpty) line = '$line · ${record.result}';
    } else if (record.reason != deliveryNoReceiptReason) {
      // T200：`no-receipt` 已经由状态词说全（"这一轮没拿到回执，状态未知"），不重复。
      line = '$line · ${remoteReasonText(record.reason, l10n)}';
    } else if (record.result.isNotEmpty) {
      line = '$line · ${record.result}';
    }
    return line;
  }

  Widget _buildInboxView(AppLocalizations l10n) {
    if (!_inboxLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final list = _filteredInbox;
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
    if (list.isEmpty && _searchQuery.isNotEmpty) {
      return Center(
        child: Text(
          l10n.noMatchRecords,
          style: TextStyle(
            color: AppColors.secondaryLabel(context),
            fontSize: 15,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _inboxRow(
        l10n,
        list[index],
        outgoing: _inboxDirection == kFnthinkDirectionOut,
        index: index,
        total: list.length,
      ),
    );
  }

  /// T147②：一条规则扇出的组行。**不是一条记录**：没有 `notifications` 行、
  /// 不可重推、不参与批量选择；只回答「这一批发了多少、几条没成」。
  Widget _buildGroupRow(
    BuildContext context,
    _HistoryGroupView view,
    int index,
    int total,
  ) {
    final l10n = AppLocalizations.of(context);
    final group = view.group;
    return HistoryRowTile(
      key: ValueKey('history-group-${group.id}'),
      keyNamespace: 'history-group',
      identity: group.id,
      title: group.isDelay ? l10n.historyGroupDelay : l10n.historyGroupMerge,
      subtitle: group.title.isEmpty ? null : group.title,
      time: historyRowTime(group.at, withSeconds: true),
      source: group.appName.isEmpty ? null : group.appName,
      badges: [_tagBadge(context, l10n.historyGroupBadge, AppColors.blue)],
      statusMessage: l10n.historyGroupTally(view.total, view.failed),
      // T179：组行不是记录，但"这一组扇出了什么"必须看得见。点开只读子页列出成员；
      // 组本身仍不可重推（那一枚不在子页里，也不在组行上）。
      onTap: () => _showGroupMembers(view),
      corner: index == 0
          ? (index == total - 1
                ? HistoryRowCorner.only
                : HistoryRowCorner.first)
          : (index == total - 1
                ? HistoryRowCorner.last
                : HistoryRowCorner.middle),
    );
  }

  Widget _groupMemberRow(
    BuildContext sheetContext,
    NotificationRecord record,
    int index,
    int total,
    AppLocalizations l10n,
  ) {
    final tally = tallyDelivery(record.deliveryStatus);
    return HistoryRowTile(
      key: ValueKey('history-group-member-${record.id}'),
      keyNamespace: 'history-group-member',
      identity: record.id,
      title: record.title.isEmpty ? l10n.noTitle : record.title,
      time: historyRowTime(record.postTime, withSeconds: true),
      subtitle: record.content.isEmpty ? null : record.content,
      source: record.appName.isEmpty ? null : record.appName,
      statusMessage: [
        l10n.historyTallyTotal(tally.total),
        if (tally.done > 0) l10n.historyTallyDone(tally.done),
        if (tally.failed > 0) l10n.historyTallyFailed(tally.failed),
        if (tally.inFlight > 0) l10n.historyTallyInFlight(tally.inFlight),
      ].join(' · '),
      corner: index == 0
          ? (index == total - 1
                ? HistoryRowCorner.only
                : HistoryRowCorner.first)
          : (index == total - 1
                ? HistoryRowCorner.last
                : HistoryRowCorner.middle),
      // 先关成员子页再开详情：详情自己也是一个底部弹层，叠着开会把「返回」变成
      // 关掉最上面那一层，而用户以为退回了组。
      onTap: () {
        Navigator.of(sheetContext).pop();
        unawaited(_showRecordDetail(record));
      },
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
    final time = _formatTime(record.postTime, withSeconds: true);
    final isKnownType = _isKnownType(type);
    final color = isKnownType
        ? _getTypeColor(context, type)
        : _getAppColor(appName);
    final label = isKnownType ? _getTypeLabel(l10n, type) : appName;

    // 推送渠道标签 + 各通道送达状态（T133 片2：排法与折法走唯一作者，
    // 页面只交出"这一行此刻展开没有"那一份界面状态）
    //
    // T148 片2：这些是**推送特有**的行内容，按通用件的规矩从 `lines` 挂进去 ——
    // 件不认得"通道"，正如它不该认得"远程执行"。反过来标题/时间/正文/来源四格
    // 从此不再在这一页各拼一份（差异①③⑤⑥的基座那一半就在这一步收掉）。
    final rows = _channelRowsOf(record);
    // 行内出口不再有条件（T133 片9 走 (b)）：每一条转发行都给，说的话由 `repushIntentOf` 挑。
    // 以前那句 `recordNeedsRepush(...)` 当闸门 ⇒ 一条已全送出的记录在单条这一层没有任何入口，
    // 用户要"就再发一次"只能去开批量模式，而批量那一档仍按"补缺"选人（选不中它）。
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
          _tagBadge(
            context,
            l10n.priorityBadgeLow,
            AppColors.secondaryLabel(context),
          ),
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
      // 统一选择模式下点行切换选中（不打开详情），长按也进入选择模式
      onTap: _selectMode
          ? () => _toggleSelectRecord(record.id)
          : () => _showRecordDetail(record),
      onLongPress: !_selectMode ? () => _enterSelectMode(record.id) : null,
      lines: [
        _buildDeliveryTallyLine(record, rows, l10n),
        // 每一条转发行都有这一枚（T133 片9 走 (b)）：口径由文案说清楚，判据住在作者那一处，
        // 页面不再自己比状态字面量决定"这条给不给出口"。
        if (widget.onPushNow != null) _buildPushNowButton(record, l10n),
      ],
    );

    // 统一选择模式：所有记录都可选
    if (!_selectMode) return item;
    return Row(
      children: [
        Checkbox(
          value: _selected.contains(record.id),
          activeColor: AppColors.blue,
          onChanged: (_) => _toggleSelectRecord(record.id),
        ),
        Expanded(child: item),
      ],
    );
  }

  /// 统一选择模式底部操作栏（取消 / 标已读（收件）/ 删除 / 重发）
  Widget _buildBatchBar(BuildContext context, AppLocalizations l10n) {
    final count = _selected.length;
    final isReceivedTab = _direction == 'received';
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
                tone: FnthinkActionTone.neutral,
                onPressed: _exitSelectMode,
              ),
              const Spacer(),
              if (isReceivedTab) ...[
                // 批量标已读（仅收件档）
                FnthinkFilledAction(
                  key: const ValueKey('history-batch-mark-read'),
                  icon: Icons.mark_email_read_outlined,
                  label: l10n.inboxMarkReadAction,
                  onPressed: count == 0 ? null : _runMarkReadSelected,
                ),
                const SizedBox(width: 8),
              ],
              // 批量删除（所有 tab 都有）
              FnthinkFilledAction(
                key: const ValueKey('history-batch-delete'),
                icon: Icons.delete_outline,
                label: l10n.clearRecords,
                onPressed: count == 0 ? null : _runBatchDelete,
              ),
              if (_canResend) ...[
                const SizedBox(width: 8),
                // 批量重发（转发和幻念发件档才有）
                FnthinkFilledAction(
                  key: const ValueKey('history-batch-push'),
                  icon: Icons.replay,
                  label: l10n.batchPushAction(count),
                  onPressed: count == 0 ? null : _runBatchResend,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
