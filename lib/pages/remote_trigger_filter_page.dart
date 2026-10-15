import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/services/installed_apps_service.dart';
import 'package:notice_transmit/theme/app_colors.dart';
import 'package:notice_transmit/widgets/app_text_selection_menu.dart';
import 'package:notice_transmit/widgets/fnthink_card.dart';
import 'package:notice_transmit/widgets/ios_dialog_actions.dart';

/// 远程执行「可触发的应用」筛选页（T153 片1）。
///
/// **为什么派生而不给 `AppFilterPage` 加参数**（维护者 2026-10-15 拍板 Q1=b）：
/// 那一页的文案量差异是**整页级别**的 —— 标题、两枚模式 chip、模式说明、已选摘要、
/// 底部 info 卡，五处全在说「通知要被推送」，而这一页的真实语义是
/// 「哪些应用的通知**正文**能触发本机远程指令」。给 `AppFilterPage` 加五个字符串参数
/// 只会长出一个带一堆可选口的假通用件，而两套语义在同一份代码里互相看得见 ——
/// 下一个人改通知那套文案时，很容易顺手把触发那套也改掉（它们本来就是同一屏）。
///
/// 代价是**两处要同步维护**，已接受：数据形状、权限链路、缓存/刷新、分组排序
/// 这些**与语义无关**的部分逐字相同；凡是会说出"这是什么"的地方（文案）都换成了触发语义。
/// 若将来长出第三个使用者，再把共用部分上抽（那时才有第二个真实调用点证明该抽什么）。
///
/// ⚠ **数据键不复用**：这一页的结果写 `FnthinkRemoteSettings` 自己的三份键
///    （`localTriggerFilter`，见 `fnthink_remote_settings.dart`），
///    **不碰** `enabled_packages` —— 那一份的语义是「要转发的应用」，
///    往它上面挂这一判，等于用户收窄「谁能动这台设备」时顺手改了推送名单（一次操作改两件事）。
///    这条纪律原页的调用方（`remote_credential_settings_page`）早已立好，这里照守。
class RemoteTriggerFilterPage extends StatefulWidget {
  final String initialMode; // 'allow' = 允许触发；'block' = 禁止触发
  final List<String> enabledPackages;

  const RemoteTriggerFilterPage({
    super.key,
    this.initialMode = 'allow',
    this.enabledPackages = const [],
  });

  @override
  State<RemoteTriggerFilterPage> createState() =>
      _RemoteTriggerFilterPageState();
}

class _RemoteTriggerFilterPageState extends State<RemoteTriggerFilterPage>
    with WidgetsBindingObserver {
  /// 应用清单读取走服务层（原生方法名不下沉到 widget 层）—— 与
  /// `AppFilterPage` 同一个入口：缓存、force、ROM 过滤那些判据只有一份。
  InstalledAppsService get _apps => GetIt.instance<InstalledAppsService>();

  List<Map<String, dynamic>> _allApps = [];
  List<Map<String, dynamic>> _filteredApps = [];
  Set<String> _selectedPackages = {};
  String _selectedMode = 'allow';
  final _searchController = TextEditingController();
  bool _loading = true;
  bool _refreshing = false;
  bool _showSystemApps = false;
  bool _hasPermission = true;
  // 权限提醒弹窗每次进入页面只弹一次：从系统设置返回（resumed 重查）不再弹
  bool _permissionDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedMode = widget.initialMode == 'block' ? 'block' : 'allow';
    _selectedPackages = Set<String>.from(widget.enabledPackages);
    _initLoad();
    _searchController.addListener(_filterApps);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initLoad();
    }
  }

  Future<void> _initLoad() async {
    setState(() => _loading = true);

    final hasPermission = await _checkPermission();
    if (!mounted) return;
    setState(() {
      _hasPermission = hasPermission;
    });

    if (hasPermission) {
      // 先立刻展示之前缓存的应用列表，再后台静默刷新一次（动态更新差异部分）
      await _loadCachedApps();
      _refreshAppsSilently();
    } else if (!_permissionDialogShown) {
      // 无权限：先弹窗提醒，用户拒绝则仅在列表区域显示提示文案
      _permissionDialogShown = true;
      _showPermissionDialog();
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  /// `canQueryAllPackages` 的原生语义是「允许去枚举」，不是「已授予」：
  /// 只有拿到明确拒绝信号才返回 false。取不到结果时**按不允许处理**——
  /// 旧写法是 `?? true` / catch 也 return true，等于第二个 fail-open。
  Future<bool> _checkPermission() => _apps.canQueryPackages();

  /// 无权限进入页面时的提醒弹窗：允许 → 跳系统设置申请；拒绝 → 仅显示提示文案
  Future<void> _showPermissionDialog() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final allowed = await IosDialogActions.showPermissionGuide(
      context,
      icon: Icons.apps,
      title: l10n.appListPermTitle,
      message: l10n.appListPermMsg,
      rejectText: l10n.reject,
      allowText: l10n.allow,
    );
    if (allowed) {
      _apps.requestQueryAllPackages();
    }
  }

  Future<void> _loadCachedApps() async {
    final cached = await _apps.loadCached();
    if (!mounted) return;
    if (cached.isNotEmpty) {
      setState(() {
        _allApps = cached;
        _filterApps();
      });
    }
  }

  /// 后台静默刷新：进入页面（已授权）时自动执行一次，读取全量应用列表并
  /// 动态更新与缓存的差异部分（原生端同时更新缓存）。失败时保留已展示的缓存。
  Future<void> _refreshAppsSilently() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final newApps = await _apps.load();
      if (!mounted) return;
      setState(() {
        _allApps = newApps;
        // 空结果 = 原生判定不可读（明确拒绝，或枚举被 ROM 过滤成 0 条）。
        // 此时必须退回引导态，而不是显示"没有找到应用"。
        _hasPermission = newApps.isNotEmpty;
        _filterApps();
      });
    } catch (e) {
      debugPrint('后台刷新应用列表失败: $e');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _manualRefreshApps() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);

    try {
      final newApps = await _apps.load(force: true);
      if (!mounted) return;

      setState(() {
        _allApps = newApps;
        _hasPermission = newApps.isNotEmpty;
        _filterApps();
      });
    } catch (e) {
      debugPrint('刷新应用列表失败: $e');
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.refreshFailed(e.toString()))),
        );
      }
    } finally {
      setState(() => _refreshing = false);
    }
  }

  void _filterApps() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredApps = _allApps.where((app) {
        if (!_showSystemApps && (app['isSystemApp'] as bool? ?? false)) {
          return false;
        }
        if (query.isEmpty) return true;
        final name = (app['appName'] as String? ?? '').toLowerCase();
        final pkg = (app['packageName'] as String? ?? '').toLowerCase();
        return name.contains(query) || pkg.contains(query);
      }).toList();
    });
  }

  void _togglePackage(String packageName, bool selected) {
    setState(() {
      if (selected) {
        _selectedPackages.add(packageName);
      } else {
        _selectedPackages.remove(packageName);
      }
    });
  }

  void _selectAll(bool selected) {
    setState(() {
      for (final app in _filteredApps) {
        final packageName = app['packageName'] as String;
        if (selected) {
          _selectedPackages.add(packageName);
        } else {
          _selectedPackages.remove(packageName);
        }
      }
    });
  }

  void _clearAll() {
    setState(() {
      _selectedPackages.clear();
    });
  }

  void _invertSelection() {
    setState(() {
      for (final app in _filteredApps) {
        final packageName = app['packageName'] as String;
        if (_selectedPackages.contains(packageName)) {
          _selectedPackages.remove(packageName);
        } else {
          _selectedPackages.add(packageName);
        }
      }
    });
  }

  /// 回给调用方的形状与 `AppFilterPage` **逐字相同**（`mode` + `packages` 两个键）——
  /// 调用方（`remote_credential_settings_page._openLocalTriggerApps`）那三行解析
  /// 一行都不用改：换页不换契约，否则就是把"写进去的形状"与"读出来的形状"分成两套。
  void _saveAndBack() {
    Navigator.pop(context, {
      'mode': _selectedMode,
      'packages': _selectedPackages.toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        // 标题换成触发语义（原页是 `l10n.appFilter`「应用筛选」）
        title: Text(
          l10n.remoteTriggerFilterTitle,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.blue,
                    ),
                  )
                : const Icon(Icons.refresh, color: AppColors.blue),
            onPressed: _refreshing ? null : _manualRefreshApps,
            tooltip: l10n.refreshAppList,
          ),
          // 「完成」那枚：原页是裸 `TextButton`（T153 片6 要清的那一族）。
          // 这一页新写，**不继承那个形状** —— 直接走公共件，与列表页「完成」同一副样子。
          FnthinkInlineAction(
            key: const ValueKey('remote-trigger-done'),
            label: l10n.done,
            tone: FnthinkActionTone.action,
            onPressed: _saveAndBack,
          ),
        ],
      ),
      body: _buildAppListView(l10n),
    );
  }

  /// 模式说明：**整句换成触发语义**（原页四句说的是"通知会被推送"）。
  ///
  /// ⚠ 空清单那一句必须画出来：这一路的「允许 0 个」是真的谁都不许触发
  ///    （fail-closed，`parseLocalTriggerFilter` 从没写过/不成形也退回最窄那一档）。
  ///    不说它，用户看到的就是「我开了怎么没反应」而查不出原因。
  String _infoText(AppLocalizations l10n) {
    if (_selectedMode == 'block') {
      return _selectedPackages.isEmpty
          ? l10n.remoteTriggerBlockModeInfo
          : l10n.remoteTriggerBlockModeSelected(_selectedPackages.length);
    }
    return _selectedPackages.isEmpty
        ? l10n.remoteTriggerAllowModeInfo
        : l10n.remoteTriggerAllowModeSelected(_selectedPackages.length);
  }

  Widget _buildModeToggle(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.inputBg(context),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            _buildModeChip(
              // 图标也换：原页用 notifications_active/off（说的是"通知"），
              // 这一页说的是"这个应用能不能动这台设备"。
              icon: Icons.check_circle_outline,
              label: l10n.remoteTriggerAllow,
              mode: 'allow',
            ),
            const SizedBox(width: 4),
            _buildModeChip(
              icon: Icons.block,
              label: l10n.remoteTriggerBlock,
              mode: 'block',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeChip({
    required IconData icon,
    required String label,
    required String mode,
  }) {
    final selected = _selectedMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedMode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.cardBg(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? AppColors.blue
                    : AppColors.secondaryLabel(context),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected
                      ? AppColors.blue
                      : AppColors.secondaryLabel(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 无权限时应用列表区域显示的提示文案，点击整段文字直接发起权限申请
  Widget _buildNoPermissionPrompt(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: GestureDetector(
          onTap: () {
            _apps.requestQueryAllPackages();
          },
          child: Text(
            l10n.appFilterNoPermPrompt,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.blue,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppListView(AppLocalizations l10n) {
    return Column(
      children: [
        const SizedBox(height: 8),
        _buildModeToggle(l10n),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.inputBg(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search,
                  color: AppColors.secondaryLabel(context),
                  size: 20,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    contextMenuBuilder: AppTextSelectionMenu.editableText,
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: l10n.searchAppHint,
                      hintStyle: TextStyle(
                        color: AppColors.secondaryLabel(context),
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: TextStyle(
                      color: AppColors.primaryLabel(context),
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Text(
                        l10n.showSystemApps,
                        style: TextStyle(
                          fontSize: 15,
                          color: AppColors.primaryLabel(context),
                        ),
                      ),
                      const Spacer(),
                      CupertinoSwitch(
                        value: _showSystemApps,
                        onChanged: (v) {
                          setState(() {
                            _showSystemApps = v;
                            _filterApps();
                          });
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: AppColors.separator(context),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _selectAll(true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            l10n.selectAll,
                            style: const TextStyle(
                              color: AppColors.blue,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _clearAll,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.secondaryLabel(
                              context,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            l10n.deselectAll,
                            style: TextStyle(
                              color: AppColors.secondaryLabel(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _invertSelection,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.secondaryLabel(
                              context,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            l10n.invertSelection,
                            style: TextStyle(
                              color: AppColors.secondaryLabel(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        l10n.selectedCount(_selectedPackages.length),
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.secondaryLabel(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: AppColors.blue, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _infoText(l10n),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.blue,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: !_hasPermission
              ? _buildNoPermissionPrompt(l10n)
              : _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.blue),
                )
              : _filteredApps.isEmpty
              ? Center(
                  child: Text(
                    l10n.noAppsFound,
                    style: TextStyle(color: AppColors.secondaryLabel(context)),
                  ),
                )
              : _buildAppList(l10n),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// 应用列表：有选中应用时按「已选（置顶）/未选」分组，未做选择时保持平铺
  Widget _buildAppList(AppLocalizations l10n) {
    final items = _buildAppListItems(l10n);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final header = item.header;
        if (header != null) {
          return Padding(
            padding: const EdgeInsets.only(left: 4, top: 8, bottom: 6),
            child: Text(
              header,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          );
        }
        final app = item.app!;
        final packageName = app['packageName'] as String;
        final appName = app['appName'] as String;
        final isSelected = _selectedPackages.contains(packageName);
        final showDivider = index > 0 && items[index - 1].app != null;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.cardBg(context),
            borderRadius: BorderRadius.only(
              topLeft: item.isFirstInGroup
                  ? const Radius.circular(12)
                  : Radius.zero,
              topRight: item.isFirstInGroup
                  ? const Radius.circular(12)
                  : Radius.zero,
              bottomLeft: item.isLastInGroup
                  ? const Radius.circular(12)
                  : Radius.zero,
              bottomRight: item.isLastInGroup
                  ? const Radius.circular(12)
                  : Radius.zero,
            ),
          ),
          child: Column(
            children: [
              if (showDivider)
                Padding(
                  padding: const EdgeInsets.only(left: 60),
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: AppColors.separator(context),
                  ),
                ),
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.android,
                      color: AppColors.blue,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    appName,
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                  subtitle: Text(
                    packageName,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                  trailing: Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    color: isSelected
                        ? AppColors.green
                        : AppColors.tertiaryLabel(context),
                    size: 24,
                  ),
                  onTap: () => _togglePackage(packageName, !isSelected),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<_TriggerAppListItem> _buildAppListItems(AppLocalizations l10n) {
    final items = <_TriggerAppListItem>[];
    void addApps(List<Map<String, dynamic>> apps) {
      for (var i = 0; i < apps.length; i++) {
        items.add(
          _TriggerAppListItem.app(
            apps[i],
            isFirstInGroup: i == 0,
            isLastInGroup: i == apps.length - 1,
          ),
        );
      }
    }

    if (_selectedPackages.isEmpty) {
      addApps(_filteredApps);
      return items;
    }
    final selectedApps = _filteredApps
        .where((a) => _selectedPackages.contains(a['packageName'] as String))
        .toList();
    final unselectedApps = _filteredApps
        .where((a) => !_selectedPackages.contains(a['packageName'] as String))
        .toList();
    if (selectedApps.isNotEmpty) {
      items.add(
        _TriggerAppListItem.header(l10n.selectedCount(selectedApps.length)),
      );
      addApps(selectedApps);
    }
    if (unselectedApps.isNotEmpty) {
      items.add(
        _TriggerAppListItem.header(l10n.unselectedCount(unselectedApps.length)),
      );
      addApps(unselectedApps);
    }
    return items;
  }
}

/// 列表条目：组头或应用行（与 `AppFilterPage` 的 `_AppListItem` 同形，
/// 但**不共用那个私有类** —— 跨文件共享私有类就得把它改成 public，
/// 而那等于把一页的内部结构泄漏成另一页的依赖）。
class _TriggerAppListItem {
  final String? header;
  final Map<String, dynamic>? app;
  final bool isFirstInGroup;
  final bool isLastInGroup;

  const _TriggerAppListItem.header(this.header)
    : app = null,
      isFirstInGroup = false,
      isLastInGroup = false;

  const _TriggerAppListItem.app(
    this.app, {
    required this.isFirstInGroup,
    required this.isLastInGroup,
  }) : header = null;
}
