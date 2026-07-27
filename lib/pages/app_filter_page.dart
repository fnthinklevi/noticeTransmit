import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/platform_channel.dart';
import '../theme/app_colors.dart';

class AppFilterPage extends StatefulWidget {
  final List<Map<String, dynamic>> installedApps;
  final List<String> enabledPackages;
  final String initialMode; // 'allow' = 通知应用；'block' = 不通知应用

  const AppFilterPage({
    super.key,
    required this.installedApps,
    required this.enabledPackages,
    this.initialMode = 'allow',
  });

  @override
  State<AppFilterPage> createState() => _AppFilterPageState();
}

class _AppFilterPageState extends State<AppFilterPage>
    with WidgetsBindingObserver {
  static const _channel = AppChannels.notification;

  List<Map<String, dynamic>> _allApps = [];
  List<Map<String, dynamic>> _filteredApps = [];
  Set<String> _selectedPackages = {};
  String _selectedMode = 'allow';
  final _searchController = TextEditingController();
  bool _loading = true;
  bool _refreshing = false;
  bool _showSystemApps = false;
  bool _hasPermission = true;
  bool _checkedPermission = false;

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
    setState(() {
      _hasPermission = hasPermission;
      _checkedPermission = true;
    });

    if (hasPermission) {
      await _loadCachedApps();
    }

    setState(() => _loading = false);
  }

  Future<bool> _checkPermission() async {
    try {
      final result =
          await _channel.invokeMethod('canQueryAllPackages') as bool?;
      return result ?? true;
    } catch (e) {
      debugPrint('检查应用列表权限失败: $e');
      return true;
    }
  }

  Future<void> _requestPermission() async {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return AlertDialog(
          backgroundColor: AppColors.cardBg(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.apps, size: 44, color: AppColors.blue),
              const SizedBox(height: 14),
              Text(
                l10n.appListPermTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryLabel(ctx),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.appListPermMsg,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.primaryLabel(ctx),
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                l10n.reject,
                style: TextStyle(
                  color: AppColors.secondaryLabel(ctx),
                  fontSize: 15,
                ),
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _channel.invokeMethod('requestQueryAllPackagesPermission');
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(l10n.allow, style: const TextStyle(fontSize: 15)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadCachedApps() async {
    try {
      final List<dynamic> result = await _channel.invokeMethod(
        'getCachedInstalledApps',
      );
      if (result.isNotEmpty) {
        setState(() {
          _allApps = result.map((e) => Map<String, dynamic>.from(e)).toList();
          _filterApps();
        });
      }
    } catch (e) {
      debugPrint('加载缓存应用列表失败: $e');
    }
  }

  Future<void> _manualRefreshApps() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);

    try {
      final List<dynamic> result = await _channel.invokeMethod(
        'getInstalledApps',
      );
      final newApps = result.map((e) => Map<String, dynamic>.from(e)).toList();

      if (!mounted) return;

      setState(() {
        _allApps = newApps;
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
      if (selected) {
        for (final app in _filteredApps) {
          _selectedPackages.add(app['packageName'] as String);
        }
      } else {
        for (final app in _filteredApps) {
          _selectedPackages.remove(app['packageName'] as String);
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
        title: Text(
          l10n.appFilter,
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
          TextButton(
            onPressed: _saveAndBack,
            child: Text(
              l10n.done,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: _checkedPermission && !_hasPermission
          ? _buildPermissionRequestView(l10n)
          : _buildAppListView(l10n),
    );
  }

  String _infoText(AppLocalizations l10n) {
    if (_selectedMode == 'block') {
      return _selectedPackages.isEmpty
          ? l10n.appFilterBlockModeInfo
          : l10n.appFilterBlockModeSelected(_selectedPackages.length);
    }
    return _selectedPackages.isEmpty
        ? l10n.appFilterAllowModeInfo
        : l10n.appFilterAllowModeSelected(_selectedPackages.length);
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
              icon: Icons.notifications_active,
              label: l10n.filterNotifyApps,
              mode: 'allow',
            ),
            const SizedBox(width: 4),
            _buildModeChip(
              icon: Icons.notifications_off,
              label: l10n.filterBlockApps,
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

  Widget _buildPermissionRequestView(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9500).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.security,
                size: 36,
                color: Color(0xFFFF9500),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.appListPermTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.appListPermDesc2,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.secondaryLabel(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _requestPermission,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  l10n.goEnablePermission,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _initLoad,
              child: Text(
                l10n.refreshRetry,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
          ],
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
                      Switch(
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
          child: _loading
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
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filteredApps.length,
                  separatorBuilder: (_, _) => Padding(
                    padding: const EdgeInsets.only(left: 60),
                    child: Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: AppColors.separator(context),
                    ),
                  ),
                  itemBuilder: (context, index) {
                    final app = _filteredApps[index];
                    final packageName = app['packageName'] as String;
                    final appName = app['appName'] as String;
                    final isSelected = _selectedPackages.contains(packageName);
                    return Container(
                      decoration: BoxDecoration(
                        color: AppColors.cardBg(context),
                        borderRadius: BorderRadius.only(
                          topLeft: index == 0
                              ? const Radius.circular(12)
                              : Radius.zero,
                          topRight: index == 0
                              ? const Radius.circular(12)
                              : Radius.zero,
                          bottomLeft: index == _filteredApps.length - 1
                              ? const Radius.circular(12)
                              : Radius.zero,
                          bottomRight: index == _filteredApps.length - 1
                              ? const Radius.circular(12)
                              : Radius.zero,
                        ),
                      ),
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
                          isSelected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: isSelected
                              ? AppColors.green
                              : AppColors.tertiaryLabel(context),
                          size: 24,
                        ),
                        onTap: () => _togglePackage(packageName, !isSelected),
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
