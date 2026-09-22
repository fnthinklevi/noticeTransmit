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
}
