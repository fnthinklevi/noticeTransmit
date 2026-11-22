part of 'history_page.dart';

// 更多操作、选择态与批量删除/重发、归档目录、导出、清空、拉黑。
// R3 拆分：extension 挂在 _HistoryPageState 上（同 library），行为与拆分前完全一致。
// ignore_for_file: invalid_use_of_protected_member
extension _HistoryPageActions on _HistoryPageState {
  /// F4：右上角「⋯」动作弹层——收纳低频操作（批量补推/导出/归档路径/清空），
  /// 解决 AppBar 图标过多的问题；样式与长按屏蔽菜单一致（iOS 底部弹层）。
  void _showMoreActionsSheet() {
    final l10n = AppLocalizations.of(context);
    // T133 量级①：转发档看 _searchResults（分页读数），幻念档看已加载的列表
    final canAct = _isFnthinkTab
        ? (_inboxLoaded
              ? (_searchQuery.isEmpty ? _inbox : _filteredInbox).isNotEmpty
              : false)
        : (_searchResults?.isNotEmpty ?? false);
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
                  // 统一通过长按进入选择模式后点底部「批量重发」来触发
                  // 转发档默认全选当前页可重发的记录
                  if (_displayedRecords.isNotEmpty) {
                    setState(() {
                      _selectMode = true;
                      _selected
                        ..clear()
                        ..addAll(_batchPool.map((r) => r.id));
                    });
                  }
                },
              ),
              // T208：「一键已读」**只在收件档出现** —— 发出档那本账没有"未读"这一列
              // （见 `_inboxRow` 上面那段判据②），转发行更没有。
              if (_direction == 'received')
                ListTile(
                  key: const ValueKey('history-inbox-mark-all'),
                  leading: Icon(
                    Icons.mark_email_read_outlined,
                    color: _inboxUnread > 0
                        ? AppColors.blue
                        : AppColors.secondaryLabel(sheetContext),
                  ),
                  title: Text(
                    l10n.inboxMarkAllRead,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: _inboxUnread > 0
                          ? AppColors.primaryLabel(sheetContext)
                          : AppColors.secondaryLabel(sheetContext),
                    ),
                  ),
                  enabled: _inboxUnread > 0,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _runMarkAllRead();
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

  /// 长按进入选择模式，选中当前这一条
  void _enterSelectMode(String id) {
    setState(() {
      _selectMode = true;
      _selected
        ..clear()
        ..add(id);
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  /// 切换一条记录的选中状态（转发 NotificationRecord）
  void _toggleSelectRecord(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  /// 全选当前页所有可选记录
  void _selectAllCurrent() {
    setState(() {
      _selected
        ..clear()
        ..addAll(_allSelectableIds);
    });
  }

  /// 反选：选中当前页未选中的，取消选中已选中的
  void _invertSelection() {
    final all = _allSelectableIds.toSet();
    final inverted = all.difference(_selected);
    setState(() {
      _selected
        ..clear()
        ..addAll(inverted);
    });
  }

  /// 批量删除所有 tab 共用
  Future<void> _runBatchDelete() async {
    final l10n = AppLocalizations.of(context);
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final confirmed = await IosDialogActions.askConfirm(
      context,
      title: l10n.clearRecords,
      message: l10n.clearConfirmMsg(count),
      confirmText: l10n.confirm,
      cancelText: l10n.cancel,
      destructive: true,
      barrierDismissible: true,
    );
    if (!confirmed || !mounted) return;

    var deleted = 0;
    if (_isFnthinkTab) {
      final fnthinkDelete =
          widget.inboxDeleteMany ?? _inboxService.deleteMessages;
      deleted = await fnthinkDelete(_selected.toList());
    } else {
      deleted = await GetIt.instance<NotificationService>().deleteRecords(
        _selected.toList(),
      );
    }

    if (!mounted) return;
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
    // 重新读表/刷新分页
    if (_isFnthinkTab) {
      await _loadInbox();
    } else {
      unawaited(_loadSearch(reset: true));
      unawaited(_refreshTotal());
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.clearedN(deleted)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 批量重发（仅转发和幻念发件档）
  Future<void> _runBatchResend() async {
    final l10n = AppLocalizations.of(context);
    if (_selected.isEmpty) return;

    if (_isFnthinkTab) {
      // 幻念发件：不能直接"重发"，需要打开发送页让用户确认目标
      // 这里我们提供一个简单的提示，说明幻念发件的重发方式
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.batchPushNothingToResend)));
      return;
    }

    if (widget.onPushNow == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.batchPushUnsupported)));
      return;
    }

    final targets = _displayedRecords
        .where((r) => _selected.contains(r.id))
        .toList();
    if (targets.isEmpty) return;

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
      _selectMode = false;
      _selected.clear();
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.batchPushDone(submitted))));
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
    // 按 tab 分发：转发档走 widget.onExport，幻念档走自有的 buildExportJson + saveFile
    if (_isFnthinkTab) {
      await _handleExportFnthink();
    } else {
      await _handleExportForwarded();
    }
  }

  Future<void> _handleExportForwarded() async {
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
          content: Text(l10n.errorWithDetail(e.toString())),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 幻念档导出：自己弹确认、调 FnthinkInboxService.buildExportJson、走同一个原生 saveFile。
  /// 文件名后缀区分档（`fnthink_inbox_` / `fnthink_sent_`），方便用户事后区分。
  Future<void> _handleExportFnthink() async {
    final l10n = AppLocalizations.of(context);
    final isSent = _direction == 'sent';
    final confirm = await IosDialogActions.askConfirm(
      context,
      title: l10n.confirmExport,
      message: isSent
          ? l10n.fnthinkExportSentDesc(_inbox.length)
          : l10n.fnthinkExportInboxDesc(_inbox.length),
      confirmText: l10n.exportBtn,
      destructive: false,
    );
    if (!confirm || !mounted) return;
    try {
      final json = await _inboxService.buildExportJson(
        isSent ? kFnthinkDirectionOut : kFnthinkDirectionIn,
      );
      final suffix = isSent ? 'fnthink_sent' : 'fnthink_inbox';
      final result = await AppChannels.notification.invokeMethod('saveFile', {
        'fileName': '${suffix}_${DateTime.now().millisecondsSinceEpoch}.json',
        'content': json,
      });
      if (!mounted) return;
      final message = result is Map
          ? (result['message']?.toString() ?? l10n.exportDone)
          : l10n.exportDone;
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
          content: Text(l10n.errorWithDetail(e.toString())),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _blockApp(NotificationRecord record) async {
    final l10n = AppLocalizations.of(context);
    final pkg = record.packageName;
    final app = record.appName.isNotEmpty ? record.appName : pkg;
    if (pkg.isEmpty) {
      _showToast(l10n.historyBlockNoAppName);
      return;
    }
    // 本应用自身通知：不受应用过滤/黑白名单影响，屏蔽无效
    if (pkg == _HistoryPageState._selfPackage) {
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
}
