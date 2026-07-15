import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

class AppFilterPage extends StatefulWidget {
  final List<Map<String, dynamic>> installedApps;
  final List<String> enabledPackages;

  const AppFilterPage({
    super.key,
    required this.installedApps,
    required this.enabledPackages,
  });

  @override
  State<AppFilterPage> createState() => _AppFilterPageState();
}

class _AppFilterPageState extends State<AppFilterPage> {
  static const platform = MethodChannel('com.fnthink.notice/notification');

  List<Map<String, dynamic>> _allApps = [];
  List<Map<String, dynamic>> _filteredApps = [];
  Set<String> _selectedPackages = {};
  final _searchController = TextEditingController();
  bool _loading = true;
  bool _refreshing = false;
  bool _showSystemApps = false;
  bool _hasPermission = true;
  bool _checkedPermission = false;

  @override
  void initState() {
    super.initState();
    _selectedPackages = Set<String>.from(widget.enabledPackages);
    _initLoad();
    _searchController.addListener(_filterApps);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      _refreshAppsInBackground();
    }

    setState(() => _loading = false);
  }

  Future<bool> _checkPermission() async {
    try {
      final result =
          await platform.invokeMethod('canQueryAllPackages') as bool?;
      return result ?? true;
    } catch (e) {
      debugPrint('检查应用列表权限失败: $e');
      return true;
    }
  }

  Future<void> _requestPermission() async {
    try {
      await platform.invokeMethod('requestQueryAllPackagesPermission');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请在设置中找到「所有应用访问权限」并开启'),
          action: SnackBarAction(
            label: '我已开启',
            onPressed: () {
              _initLoad();
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('请求应用列表权限失败: $e');
    }
  }

  Future<void> _loadCachedApps() async {
    try {
      final List<dynamic> result = await platform.invokeMethod(
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

  Future<void> _refreshAppsInBackground() async {
    if (_refreshing) return;
    _refreshing = true;

    try {
      final List<dynamic> result = await platform.invokeMethod(
        'getInstalledApps',
      );
      final newApps = result.map((e) => Map<String, dynamic>.from(e)).toList();

      if (!mounted) return;

      final existingPackages = _allApps
          .map((e) => e['packageName'] as String)
          .toSet();
      final newPackages = newApps
          .map((e) => e['packageName'] as String)
          .toSet();
      final hasChanges =
          !existingPackages.containsAll(newPackages) ||
          existingPackages.length != newPackages.length;

      if (hasChanges) {
        setState(() {
          _allApps = newApps;
          _filterApps();
        });
      }
    } catch (e) {
      debugPrint('刷新应用列表失败: $e');
    } finally {
      _refreshing = false;
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

  void _saveAndBack() {
    Navigator.pop(context, _selectedPackages.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: const Text(
          '应用筛选',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: _saveAndBack,
            child: const Text(
              '完成',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: _checkedPermission && !_hasPermission
          ? _buildPermissionRequestView()
          : _buildAppListView(),
    );
  }

  Widget _buildPermissionRequestView() {
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
              '需要应用列表权限',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '为了能够筛选需要推送通知的应用，请授予应用读取已安装应用列表的权限。',
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
                child: const Text(
                  '前往开启权限',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _initLoad,
              child: Text(
                '刷新重试',
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

  Widget _buildAppListView() {
    return Column(
      children: [
        const SizedBox(height: 8),
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
                      hintText: '搜索应用名称或包名',
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
                        '显示系统应用',
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
                          child: const Text(
                            '全选',
                            style: TextStyle(
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
                            '清空',
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
                        '已选 ${_selectedPackages.length}',
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
                const Icon(
                  Icons.info_outline,
                  color: AppColors.blue,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedPackages.isEmpty
                        ? '当前模式：所有应用都推送通知（默认）'
                        : '已选择 ${_selectedPackages.length} 个应用，仅这些应用的通知会被推送',
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
                    '没有找到应用',
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
