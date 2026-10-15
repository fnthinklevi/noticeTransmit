import 'package:flutter/foundation.dart';

import 'platform_channel.dart';

/// 已安装应用清单服务（应用筛选页 / 规则应用范围选择 / 规则测试器共用）。
///
/// 此前三处各自复制「invokeMethod → `List<dynamic>` → `Map` 归一化」：
/// 动态泛型会产出 `List<dynamic>`，直接赋给 `List<Map<String, dynamic>>`
/// 触发隐式 downcast 异常，表现为**应用列表恒为空**——这个坑只在带注释的
/// 两处被绕开，复制一次就丢一次教训。读取入口收敛到这里后，页面不再
/// 知道原生方法名（widget 层裸 invokeMethod 只降不升，见
/// test/architecture/widget_channel_ratchet_test.dart）。
class InstalledAppsService {
  static const _channel = AppChannels.notification;

  /// 读原生缓存（新鲜时不重扫）。失败吞掉并返回空列表——调用方据此再决定
  /// 是否走 [load]，页面首帧不该因缓存读取失败而报错。
  Future<List<Map<String, dynamic>>> loadCached() async {
    try {
      final List<dynamic> rows = await _channel.invokeMethod(
        'getCachedInstalledApps',
      );
      return _rows(rows);
    } catch (e) {
      debugPrint('InstalledAppsService: 读取缓存应用列表失败: $e');
      return const [];
    }
  }

  /// 取全量列表。[force] = true 绕过原生缓存强制重扫
  /// （Flyme 等机型首次扫描不全的兜底，用户主动下拉刷新时使用）。
  /// 失败向上抛出，由调用方决定提示文案。
  Future<List<Map<String, dynamic>>> load({bool force = false}) async {
    final List<dynamic> rows = force
        ? await _channel.invokeMethod('getInstalledApps', {'force': true})
        : await _channel.invokeMethod('getInstalledApps');
    return _rows(rows);
  }

  /// 显式声明元素类型，避免 `List<dynamic>` 隐式 downcast（见类注释）。
  static List<Map<String, dynamic>> _rows(List<dynamic> rows) =>
      rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();

  // ── 应用列表权限（T153 片1 收进来）────────────────────────────────────
  //
  // 此前「能不能读应用列表」与「去申请它」这两发**各自写在页面里**
  // （`AppFilterPage` 三处、T153 派生页又照搬三处）—— widget 层裸
  // `invokeMethod` 是只降不升的棘轮（25 处封顶，见
  // `test/architecture/widget_channel_ratchet_test.dart`），照搬一次就超一次；
  // 而" Permission 语义"这种与文案无关的部分，本就不该有两个作者。
  //
  // ⚠ `canQueryAllPackages` 的原生语义是「允许去枚举」，不是「已授予」：
  //    只有明确拒绝才该返回 false。取不到结果时**按不允许处理**——
  //    旧写法是 `?? true` / catch 也 return true，那是第二个 fail-open：
  //    用户在系统里拒了权限，页面照样去扫描并展示结果。
  Future<bool> canQueryPackages() async {
    try {
      return await _channel.invokeMethod('canQueryAllPackages') as bool? ??
          false;
    } catch (e) {
      debugPrint('InstalledAppsService: 检查应用列表权限失败: $e');
      return false;
    }
  }

  /// 发起申请：`QUERY_ALL_PACKAGES` 在 Android 11+ 只能跳系统设置页
  /// （`requestPermissions()` 对它无效），所以这一发就是跳转。
  /// T153 片4 会把"先弹窗说清再跳"那一步接在调用方，本服务只负责跳本身。
  Future<void> requestQueryAllPackages() async {
    try {
      await _channel.invokeMethod('requestQueryAllPackagesPermission');
    } catch (e) {
      debugPrint('InstalledAppsService: 申请应用列表权限失败: $e');
    }
  }
}
