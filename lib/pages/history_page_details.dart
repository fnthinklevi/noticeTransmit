part of 'history_page.dart';

// 送达详情、记录详情、群成员详情、收件详情与回复/重发。
// R3 拆分：extension 挂在 _HistoryPageState 上（同 library），行为与拆分前完全一致。
// ignore_for_file: invalid_use_of_protected_member
extension _HistoryPageDetails on _HistoryPageState {
  /// 送达那一行（T154 片2）：**一行统计 + 一枚「查看详情」**。
  ///
  /// 维护者 2026-10-15：「要『共X条通道·Y成功·Z失败·查看详情』子页」。
  /// 此前行内把每枚 chip 摊开（可折叠），而用户的第一个问题是"这条到底成没成" ——
  /// 摊开的 chip 只回答"每一格分别是什么"。⇒ 行内只留结论，细节进子页。
  ///
  /// ⚠ 统计的**成员判定不在这里**：`tallyDelivery` 按 `lib/models/delivery_status.dart`
  ///   那两位（`deliveredStatuses` / `notDeliveredStatuses`）数一遍 —— 与历史页筛选、
  ///   `delivery_bucket` 算的是同一张表。这一页只决定"怎么摆"。
  /// ⚠ 每段**各自带色**（成功绿 / 失败红）：整行一色会让"2 成功 1 失败"读起来像全失败，
  ///   而"失败要看得出来"是本仓的强纪律（与 chip 上那枚点同色）。
  /// ⚠ 没有送达记录（`rows` 为空）时照旧说「无推送通道」—— 那不是 0 条通道的统计。
  Widget _buildDeliveryTallyLine(
    NotificationRecord record,
    List<String> rows,
    AppLocalizations l10n,
  ) {
    if (rows.isEmpty) {
      return Text(
        l10n.noChannels,
        style: TextStyle(
          fontSize: 10,
          color: AppColors.secondaryLabel(context),
        ),
      );
    }
    final tally = tallyDelivery(record.deliveryStatus);
    const dot = ' · ';
    return Wrap(
      spacing: 0,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.historyTallyTotal(tally.total),
          style: TextStyle(
            fontSize: 10,
            color: AppColors.secondaryLabel(context),
          ),
        ),
        // 只报非零的那几段：全成功时说「共 3 条通道 · 3 成功」，
        // 而"0 失败"那一句是替一件没发生的事占地方。
        if (tally.done > 0)
          Text(
            dot + l10n.historyTallyDone(tally.done),
            style: TextStyle(
              fontSize: 10,
              color: deliveryStatusColor(context, 'success'),
            ),
          ),
        if (tally.failed > 0)
          Text(
            dot + l10n.historyTallyFailed(tally.failed),
            style: TextStyle(
              fontSize: 10,
              color: deliveryStatusColor(context, 'failed'),
            ),
          ),
        if (tally.inFlight > 0)
          Text(
            dot + l10n.historyTallyInFlight(tally.inFlight),
            style: TextStyle(
              fontSize: 10,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        const SizedBox(width: 8),
        FnthinkInlineAction(
          key: ValueKey('history-delivery-detail-${record.id}'),
          // 中性档：它是一次"展开看细节"，不改任何一条记录的状态。
          tone: FnthinkActionTone.neutral,
          label: l10n.historyDeliveryDetail,
          onPressed: () => _showDeliveryDetailSheet(record),
        ),
      ],
    );
  }

  /// 这一条「有哪些通道格可看」（**唯一作者**：行内那一行与子页共用一份，T154 片3 立）。
  ///
  /// ⚠ `channels` 为空时回退到 `deliveryStatus` 的键，这不是边角料：**老记录**与
  ///   「一条真实通道都没有、只留了拦截标记」那一类（迁移注释里点名的那一种）就是这个形状。
  ///   不回退 ⇒ 子页顶上一句「共 1 条通道」而下面一格都不画 —— 自己跟自己打架，
  ///   且「全部重推」会拿到一个空范围却仍显示成可按。
  List<String> _channelRowsOf(NotificationRecord record) {
    // T175 ③：快照与送达表取并集。旧写法二选一（有快照就只看快照），于是快照里有、
    // 送达表里没有的那一格**一行都不画** —— 用户读到的是"这条只发过一个通道"。
    final rows = <String>[...record.channels];
    for (final key in record.deliveryStatus.keys) {
      if (!rows.contains(key)) rows.add(key);
    }
    return rows;
  }

  /// 送达详情子页（T154 片2）：这一条到底推给了谁、每一格现在是什么。
  ///
  /// 内容就是此前摊在行内那一串 chip（一个字没少）—— 排法仍是
  /// `orderChannelsByAttention`（要人动手的排最前），chip 的渲染仍是
  /// `_buildChannelChipFor`（状态点、备用标、失败原因内联都照旧）。
  /// T154 片3 的"每通道单独重推"也落在这里（那时候每格多一枚按钮）。
  Future<void> _showDeliveryDetailSheet(NotificationRecord record) async {
    final l10n = AppLocalizations.of(context);
    final ordered = orderChannelsByAttention(
      _channelRowsOf(record),
      record.deliveryStatus,
    );
    final tally = tallyDelivery(record.deliveryStatus);
    // 片3：把"哪几格按了不会动"算在**开弹层那一次**，不在 build 里数 ——
    // 底部那一枚与逐格那 N 枚读的是同一个数，两处各数一遍就会打架。
    final push = widget.onPushChannels;
    final repushable = ordered.where(_canRepushChannel).toList();
    final gone = ordered.length - repushable.length;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.historyDeliveryDetailTitle,
                key: const ValueKey('history-delivery-detail-title'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryLabel(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  l10n.historyTallyTotal(tally.total),
                  if (tally.done > 0) l10n.historyTallyDone(tally.done),
                  if (tally.failed > 0) l10n.historyTallyFailed(tally.failed),
                  if (tally.inFlight > 0)
                    l10n.historyTallyInFlight(tally.inFlight),
                ].join(' · '),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in ordered)
                        _buildChannelDetailRow(context, record, c, l10n),
                    ],
                  ),
                ),
              ),
              // ⚠ 这一句放**底部单行**，不在每一格旁边重复 —— 同一件事说 N 遍
              //   就是"像论文"那一族（§1 视觉口径②）。
              if (gone > 0) ...[
                const SizedBox(height: 10),
                Text(
                  l10n.historyChannelRepushGone(gone),
                  key: const ValueKey('history-delivery-gone-note'),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.tertiaryLabel(context),
                  ),
                ),
              ],
              // T202：把「会不会重试」与「没拿到回执」两句说真话。三种事实
              //（没重试／重试过／不再重试）今天在界面上长得一样，用户拿着「失败」
              // 两字没法判断该不该手动再发一次；而 no-receipt 只在打开 App/回前台时
              // 才可能落下 —— 这两条都必须点得开看到，不在页面上摊成一段小字。
              HelpNoteRow(
                noteKey: 'history-delivery-retry-note',
                helpKey: 'history-delivery-retry-help',
                text: l10n.deliveryRetryHelpShort,
                helpTitle: l10n.deliveryRetryHelpTitle,
                helpBody: l10n.deliveryRetryHelpBody,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: PrimaryActionButton(
                  key: const ValueKey('history-delivery-repush-all'),
                  label: l10n.historyChannelRepushAll,
                  // 一格都不可再发时**置灰留着**，不藏起来（藏掉=用户读到"这里没这个功能"）。
                  // ⚠ 两道闸都要看：`onPushChannels` 没接上时同样置灰 —— 那一页
                  //   根本不接补推，而「能按」在屏上等于给用户一个按了没反应的地方。
                  onPressed: (push == null || repushable.isEmpty)
                      ? null
                      : () => _repushChannelsFromSheet(record, repushable),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 这一格此刻还能不能被指着重发一次（**只转发判据**，T154 片3）。
  ///
  /// ⚠ null 回调 = 一律可用：判据住在服务层，页面这一格只负责读它。
  /// 页面自己判「这一族还在不在」就是第二个作者 —— 而那一判据判错的方向很贵：
  /// 放行一枚按了不动的钮 = 那一格被写成 pending 且永远没有回执（T150 片1 修的那一族）。
  bool _canRepushChannel(String channel) {
    final available = widget.channelRepushAvailable;
    return available == null || available(channel);
  }

  /// 子页里逐格／全部那一发的共同落口（T154 片3）：先关弹层，再发。
  ///
  /// ⚠ **先关**是刻意的：这一发之后那一行会变成「发送中」，留在屏上给的是发之前那一帧的
  /// 读数 —— 用户看着一个不会变的「已送达」以为没按，比弹层直接消失更难解释。
  /// ⚠ 发完要 `setState`：行的读数来自 `record.deliveryStatus`，不回帧就一直画旧的。
  Future<void> _repushChannelsFromSheet(
    NotificationRecord record,
    List<String> channels,
  ) async {
    final push = widget.onPushChannels;
    if (push == null) return;
    Navigator.of(context, rootNavigator: true).pop();
    await push(record, channels);
    if (mounted) setState(() {});
  }

  /// 子页里每一格：chip + 一枚「重推此通道」（T154 片3）。
  ///
  /// ⚠ 这一枚**不在** `_buildChannelChip` 里 —— chip 本体是状态标记，那条守卫
  /// （`history_chip_family_test` ②）不许它长出点击；逐格这一枚是另一个成员、另一个宿主。
  /// ⚠ 走 `FnthinkInlineAction`：这是"对行里那一格做点什么"，与页脚那一枚全宽主操作
  /// 不同族（那一族是"这一页要办的事"）。两枚别混用，否则一高一矮。
  Widget _buildChannelDetailRow(
    BuildContext context,
    NotificationRecord record,
    String channel,
    AppLocalizations l10n,
  ) {
    final push = widget.onPushChannels;
    final enabled = push != null && _canRepushChannel(channel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildChannelChipFor(context, record, channel, l10n),
        FnthinkInlineAction(
          key: ValueKey('history-channel-repush-${record.id}-$channel'),
          tone: FnthinkActionTone.action,
          label: l10n.historyChannelRepush,
          onPressed: enabled
              ? () => _repushChannelsFromSheet(record, [channel])
              : null,
        ),
      ],
    );
  }

  Widget _buildChannelChipFor(
    BuildContext context,
    NotificationRecord record,
    String channel,
    AppLocalizations l10n,
  ) {
    final statusInfo = record.deliveryStatus[channel];
    return _buildChannelChip(
      channel,
      _getChannelColor(context, channel),
      statusInfo is Map
          ? (statusInfo['status']?.toString() ?? '')
          // T175 ③：快照有这一族、送达表没有这一格 ⇒ 说「未入账」，不静默省掉。
          : notAccountedStatus,
      statusInfo is Map ? (statusInfo['message']?.toString() ?? '') : '',
      l10n,
      viaBackup: statusInfo is Map && statusInfo['viaBackup'] == true,
    );
  }

  Widget _buildChannelChip(
    String channel,
    Color chipColor,
    String status,
    String message,
    AppLocalizations l10n, {
    bool viaBackup = false,
  }) {
    final submarks = <FnthinkSubMark>[
      if (viaBackup)
        FnthinkSubMark.text(l10n.deliveryViaBackupTag, AppColors.orange),
      if (status.isNotEmpty)
        FnthinkSubMark.dot(
          deliveryStatusText(l10n, status),
          deliveryStatusColor(context, status),
        ),
    ];
    final chip = FnthinkStatusMark(
      role: FnthinkMarkRole.channel,
      label: channelTypeDisplayName(channel),
      color: chipColor,
      submarks: submarks,
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

  /// 行内那一枚出口：**每一条转发行都有**（T133 片9 走 (b)），说的话按这一条此刻的事实分两种。
  ///
  /// 文案与范围**同源** —— 两边都取 `repush_eligibility.dart` 的 [repushIntentOf]：
  /// 还有没发出去的那几族 ⇒「现在推送」（只补那几族）；整条没有送达记录 ⇒「现在推送」
  /// （按当前启用通道发一次）；每一族都有了终态或还在途 ⇒「再发一次」（收件端会多收一条）。
  ///
  /// T148 片15 起走 `FnthinkFilledAction`。它此前是页面自搭的 `GestureDetector` + 蓝底
  /// `Container`，账面记成"行内填充式小钮没有公共件"的例外 —— 例外的代价不是那几行壳子，
  /// 是这一枚的字号／留白／圆角由页面挑，而同一种动作在幻念那几张页早有唯一作者。
  ///
  /// ⚠ key 字符串逐字没动（`history-push-now-<记录 id>`）：闸门与用例按 key 点，不按文案 ——
  /// 这一枚在每一行都长一个样，`find.text(pushNow)` 在多行列表里必然抓到多枚。
  Widget _buildPushNowButton(NotificationRecord record, AppLocalizations l10n) {
    final again = repushIntentOf(record.deliveryStatus) == RepushIntent.again;
    return FnthinkFilledAction(
      key: ValueKey('history-push-now-${record.id}'),
      compact: true,
      icon: again ? Icons.replay : Icons.send,
      label: again ? l10n.pushAgain : l10n.pushNow,
      onPressed: () => widget.onPushNow!(record),
    );
  }

  /// 标题前那枚文字徽标（优先级 0=低 / 2=高、幻念那一条走了备用路由……）。
  ///
  /// 形状只有一份，词由调用方给 —— T148 片3 把收件行的「备用」也接进来时，
  /// 它和「高优」是同一格事实（这条有什么额外要标的），不是两种控件。
  ///
  /// 片16 起这枚方法**只转发**给 `FnthinkStatusMark`（attribute 档）：以前这里是一份
  /// 自搭 `Container` + `BoxDecoration`，与通道 chip 的壳、通道状态页的 `_RoleBadge`
  /// 各自长一套 padding／圆角／淡底 α，下一枚徽标就会从这三份里挑一份抄。
  Widget _tagBadge(BuildContext context, String label, Color color) {
    return FnthinkStatusMark(
      role: FnthinkMarkRole.attribute,
      label: label,
      color: color,
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

  Future<void> _showInboxDetail(
    FnthinkInboxMessage message, {
    bool outgoing = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    // T124② 片2：回传正文可能是契约声明的图像形态 JSON。拆得开就画图、画事实文字；
    // 拆不开（旧消息/契约没就绪/坏载荷）就原样显示正文 —— 详情从不因为解析失败而变空。
    final contract = _reportContract();
    final reportPayload = contract == null
        ? null
        : parseFnthinkReportPayload(
            contract,
            title: message.title,
            body: message.body,
          );
    final displayText = reportPayload?.text ?? message.body;
    final imageBytes = reportPayload?.imageBytes;
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
                    message.title.isEmpty ? displayText : message.title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryLabel(sheetContext),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (displayText.isNotEmpty)
                            SelectableText(
                              displayText,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: AppColors.primaryLabel(sheetContext),
                              ),
                            ),
                          if (imageBytes != null) ...[
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 320),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  imageBytes,
                                  key: ValueKey(
                                    'fnthink-inbox-image-${message.messageId}',
                                  ),
                                  fit: BoxFit.contain,
                                  semanticLabel: l10n.fnthinkPhotoLabel,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Text(
                                        l10n.fnthinkPhotoBroken,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppColors.secondaryLabel(
                                            sheetContext,
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                            ),
                          ],
                          if (reportPayload?.imageOmitted == true) ...[
                            const SizedBox(height: 8),
                            Text(
                              l10n.fnthinkPhotoOmitted,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.secondaryLabel(sheetContext),
                              ),
                            ),
                          ],
                        ],
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
                              '${message.sender.isEmpty ? l10n.unknown : _senderText(message.sender)} · '
                              '${l10n.fnthinkSentAt}：${_formatTime(message.receivedAt, withSeconds: true)}'
                              // T105 片③：对面收下那一刻（服务端回执带回来的）。
                              // 0＝还不知道（对面还没 ack／旧服务端）—— 那时这一句不出现。
                              '${message.ackedAt > 0 ? ' · ${l10n.fnthinkPeerAckedAt}：${_formatTime(message.ackedAt, withSeconds: true)}' : ''}'
                              '${message.ackResult.isEmpty ? '' : ' · ${message.ackResult}'}'
                        : '${l10n.fnthinkSender}：'
                              '${message.sender.isEmpty ? l10n.unknown : _senderText(message.sender)} · '
                              '${l10n.fnthinkReceivedAt}：${_formatTime(message.receivedAt, withSeconds: true)}'
                              // T105 片②：服务端给过受理时刻才出这一句
                              // （旧行与旧服务端是 0 ⇒ 不出现，而不是画一个 1970 年的时刻）。
                              '${message.sentAt > 0 ? ' · ${l10n.fnthinkSentAt}：${_formatTime(message.sentAt, withSeconds: true)}' : ''}'
                              '${message.ackResult.isEmpty ? '' : ' · ${message.ackResult}'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.secondaryLabel(sheetContext),
                    ),
                  ),
                  // T195：来源应用名单列一行（非空才画）。与行上那枚徽标同一个判据 ——
                  // 空串是"手动发送／旧发送端／端点"，不是"应用叫空字符串"。
                  if (message.appName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${l10n.fnthinkAppLabel}：${message.appName}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryLabel(sheetContext),
                      ),
                    ),
                  ],
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
                          const JsonEncoder.withIndent('  ')
                              .convert(record.toMap()),
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
                  color: AppColors.orange,
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

  /// 组行的只读成员子页（T179）。
  ///
  /// 成员按组里记下的顺序排（`memberIds` 是有序的），不按回表的数据库顺序：
  /// 那一串顺序是扇出当时的顺序，换一种排法会让同一组在两次打开之间自己跳。
  /// 组本身**没有**「再发一次」：它不是一条记录，重推哪一条由成员那一行说了算。
  Future<void> _showGroupMembers(_HistoryGroupView view) async {
    final l10n = AppLocalizations.of(context);
    final loader = widget.groupMembersLoader ?? _loadGroupMembers;
    List<NotificationRecord> ordered;
    try {
      final rows = await loader(view.group.memberIds);
      final byId = {for (final row in rows) row.id: row};
      ordered = [
        for (final id in view.group.memberIds)
          if (byId[id] != null) byId[id]!,
      ];
    } catch (e) {
      debugPrint('历史组成员读取失败: $e');
      ordered = const <NotificationRecord>[];
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          key: const ValueKey('history-group-members-sheet'),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(
                  l10n.historyGroupMembersTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryLabel(sheetContext),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l10n.historyGroupTally(view.total, view.failed),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryLabel(sheetContext),
                  ),
                ),
              ),
              if (ordered.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(
                    l10n.historyGroupMembersEmpty,
                    key: const ValueKey('history-group-members-empty'),
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryLabel(sheetContext),
                    ),
                  ),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        for (var i = 0; i < ordered.length; i++)
                          _groupMemberRow(
                            sheetContext,
                            ordered[i],
                            i,
                            ordered.length,
                            l10n,
                          ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Text(
                  l10n.historyGroupMembersNote,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.tertiaryLabel(sheetContext),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
}
