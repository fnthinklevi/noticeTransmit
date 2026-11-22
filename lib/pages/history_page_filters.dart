part of 'history_page.dart';

// 筛选面板、筛选芯片与清空筛选。
// R3 拆分：extension 挂在 _HistoryPageState 上（同 library），行为与拆分前完全一致。
// ignore_for_file: invalid_use_of_protected_member
extension _HistoryPageFilters on _HistoryPageState {
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
                    border: appInputBorder(context),
                    enabledBorder: appInputBorder(context),
                    focusedBorder: appInputBorder(
                      context,
                      color: AppColors.blue,
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
                    border: appInputBorder(context),
                    enabledBorder: appInputBorder(context),
                    focusedBorder: appInputBorder(
                      context,
                      color: AppColors.blue,
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
}
