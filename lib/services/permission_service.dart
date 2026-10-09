import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:permission_handler/permission_handler.dart';
import 'installed_apps_service.dart';
import 'platform_channel.dart';

/// 「读取已安装应用列表」的可见性状态，与原生 `AppListState` 一一对应（跨端契约）。
///
/// 为什么不是 bool：`QUERY_ALL_PACKAGES` 是安装期权限，AOSP 又没给它建 AppOps 映射
/// （真机实测 `permissionToOp == null`）⇒ 系统**给不出**明确的授予/拒绝读数。
/// 布尔只能把"不知道"压成其中一边，旧实现压成了"已授予"，于是权限页恒显已授予、
/// 筛选页跳过引导直接扫描 —— 用户即便在系统里拒绝，也照样能看到应用列表。
enum AppListPermission {
  granted,
  denied,
  unknown;

  /// 未知/缺失值一律退回 [unknown]（绝不默认已授予）。大小写不敏感。
  static AppListPermission fromWire(String? value) {
    return switch (value?.toLowerCase()) {
      'granted' => AppListPermission.granted,
      'denied' => AppListPermission.denied,
      _ => AppListPermission.unknown,
    };
  }
}

class PermissionService {
  static const _channel = AppChannels.notification;

  /// [appListEnumerator] 供测试替换；默认实现延迟到调用时才取容器，
  /// 这样构造期不依赖服务注册顺序（PermissionService 注册得很早）。
  PermissionService({Future<void> Function()? appListEnumerator})
    : _enumerateApps = appListEnumerator ?? _enumerateInstalledApps;

  final Future<void> Function() _enumerateApps;

  static Future<void> _enumerateInstalledApps() async {
    await GetIt.instance<InstalledAppsService>().load(force: true);
  }

  bool _notificationListenerGranted = false;
  bool _postNotificationGranted = false;
  bool _batteryOptimizationIgnored = false;
  bool _smsGranted = false;
  bool _phoneGranted = false;
  AppListPermission _appList = AppListPermission.unknown;

  bool get notificationListenerGranted => _notificationListenerGranted;
  bool get postNotificationGranted => _postNotificationGranted;
  bool get batteryOptimizationIgnored => _batteryOptimizationIgnored;
  bool get smsGranted => _smsGranted;
  bool get phoneGranted => _phoneGranted;

  /// 只有**有证据**可读才算已授予。`unknown`（系统不给明确状态）不得显示成"已授予"——
  /// 旧实现用布尔承载，把 unknown 压成了 true，权限页因此在所有 Android 11+ 设备上恒显已授予。
  bool get appListGranted => _appList == AppListPermission.granted;
  AppListPermission get appListPermission => _appList;

  Future<void> checkAllPermissions() async {
    try {
      final listenerGranted =
          await _channel.invokeMethod('isNotificationPermissionGranted')
              as bool?;
      final postGranted =
          await _channel.invokeMethod('isPostNotificationPermissionGranted')
              as bool?;
      final batteryOk =
          await _channel.invokeMethod('isIgnoringBatteryOptimizations')
              as bool?;
      final smsGranted =
          await _channel.invokeMethod('isSmsPermissionGranted') as bool?;
      final phoneGranted =
          await _channel.invokeMethod('isPhonePermissionGranted') as bool?;
      final appListState =
          await _channel.invokeMethod('getAppListPermissionState') as String?;

      _notificationListenerGranted = listenerGranted ?? false;
      _postNotificationGranted = postGranted ?? false;
      _batteryOptimizationIgnored = batteryOk ?? false;
      _smsGranted = smsGranted ?? false;
      _phoneGranted = phoneGranted ?? false;
      _appList = AppListPermission.fromWire(appListState);
    } catch (e) {
      debugPrint('检查权限失败: $e');
    }
  }

  Future<void> _requestPermission(String methodName) async {
    try {
      await _channel.invokeMethod(methodName);
    } catch (e) {
      debugPrint('权限请求失败 $methodName: $e');
    }
  }

  Future<void> requestNotificationListenerPermission() =>
      _requestPermission('requestNotificationListenerPermission');

  Future<void> requestPostNotificationPermission() async {
    final status = await Permission.notification.request();
    if (status == PermissionStatus.granted) {
      _postNotificationGranted = true;
    }
  }

  /// T55：**提升/悬浮通知**权限（`POST_PROMOTED_NOTIFICATIONS`，Android 16 起才有运行时权限）。
  ///
  /// ⚠ **走原生而不是 permission_handler**：那一版（13.x）的枚举里没有这一项，硬塞进去等于
  /// 让"没这一项"在编译期看不见 —— 而漏申请的代价是 `FLAG_PROMOTED_ONGOING` **静默无效**
  /// （上不了岛），没有任何报错可查。
  /// ⚠ 36 以下**直接回 false**（= 不支持、不必申请）：那一档系统没有这个权限，
  ///   也没有"用户拒绝"这回事，在那里弹框只会让用户看到一个莫名其妙的应用信息页。
  Future<bool> requestPromotedNotificationPermission() async {
    final sdk = await _channel.invokeMethod<int>('getSdkInt');
    if ((sdk ?? 0) < 36) return false;
    await _requestPermission('requestPromotedNotificationPermission');
    return isPromotedNotificationGranted();
  }

  Future<bool> isPromotedNotificationGranted() async {
    try {
      return await _channel.invokeMethod<bool>(
            'isPromotedNotificationPermissionGranted',
          ) ??
          false;
    } catch (e) {
      debugPrint('检查提升通知权限失败（按未授予处理）: $e');
      return false;
    }
  }

  Future<void> requestBatteryOptimization() =>
      _requestPermission('requestBatteryOptimization');

  Future<void> requestXiaomiAutoStart() =>
      _requestPermission('requestXiaomiAutoStart');

  Future<void> requestMeizuBackground() =>
      _requestPermission('requestMeizuBackground');

  Future<void> requestHuaweiLaunch() =>
      _requestPermission('requestHuaweiLaunch');

  Future<void> requestOppoBackground() =>
      _requestPermission('requestOppoBackground');

  Future<void> requestVivoBackground() =>
      _requestPermission('requestVivoBackground');

  /// B1 精确闹钟：查询开关状态 / 系统授权状态 / 切换开关 / 引导授权
  Future<bool> isExactAlarmEnabled() async {
    try {
      return await _channel.invokeMethod('isExactAlarmEnabled') as bool? ??
          false;
    } catch (e) {
      debugPrint('查询精确闹钟开关失败: $e');
      return false;
    }
  }

  Future<bool> canScheduleExactAlarms() async {
    try {
      return await _channel.invokeMethod('canScheduleExactAlarms') as bool? ??
          false;
    } catch (e) {
      debugPrint('查询精确闹钟授权失败: $e');
      return false;
    }
  }

  Future<void> setExactAlarmEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setExactAlarmEnabled', {'enabled': enabled});
    } catch (e) {
      debugPrint('切换精确闹钟失败: $e');
    }
  }

  Future<void> requestExactAlarmPermission() =>
      _requestPermission('requestExactAlarmPermission');

  Future<void> requestSmsPermission() async {
    final status = await Permission.sms.request();
    if (status == PermissionStatus.granted) {
      _smsGranted = true;
    }
  }

  /// T124 片C：通话记录那一格（`READ_CALL_LOG`）。
  ///
  /// ⚠ **走原生而不是 `Permission.phone`**：那一枚在 permission_handler 里是"电话组"，
  /// 会把它认得的所有组内权限**一起请求** —— 清单里一有 READ_CALL_LOG，用户点
  /// 「电话状态」那一格时就会连带被问通话记录（而那是另一档数据面，"一条一开"不许这样）。
  /// 原生那一侧单独一个请求码（见 MainActivity 的 REQUEST_CALL_LOG_PERMISSION）。
  Future<void> requestCallLogPermission() =>
      _requestPermission('requestCallLogPermission');

  /// 通话记录权限当前给没给。⚠ 读不出来按**未授予**处理（与 [isPromotedNotificationGranted]
  /// 同一纪律：不得把"没读到"显示成"已授予"，那会让人以为开着而实际读不到）。
  Future<bool> isCallLogPermissionGranted() async {
    try {
      return await _channel.invokeMethod<bool>('isCallLogPermissionGranted') ??
          false;
    } catch (e) {
      debugPrint('检查通话记录权限失败（按未授予处理）: $e');
      return false;
    }
  }

  /// T124 片C-2：定位那一格（`ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION`）。
  ///
  /// ⚠ 两枚**一起申请**是系统的形状（Android 12+ 的"精确／大致"二选一就长这一次弹框里），
  /// 不是"打包两条权限面"；另一条既有的是 `locationAlways`（后台定位）——**不申请它**，
  /// 后台读不到就诚实失败（`location-unavailable`），不为它多开一条权限面。
  /// ⚠ 走原生而不是 `permission_handler`：那一枚的组语义会把"给了大致"读成"没给"，
  /// 而大致位置**能用**（精度随结果带出去）—— 判据收在原生一枚方法里。
  Future<void> requestLocationPermission() =>
      _requestPermission('requestLocationPermission');

  /// 定位权限当前给没给（**FINE 或 COARSE 任一**；读不出来按未授予处理）。
  Future<bool> isLocationPermissionGranted() async {
    try {
      return await _channel.invokeMethod<bool>('isLocationPermissionGranted') ??
          false;
    } catch (e) {
      debugPrint('检查定位权限失败（按未授予处理）: $e');
      return false;
    }
  }

  Future<void> requestPhonePermission() async {
    final status = await Permission.phone.request();
    if (status == PermissionStatus.granted) {
      _phoneGranted = true;
    }
  }

  /// 向系统申请「读取已安装应用列表」（维护者 1.5.76 反馈 #3：点这一行就该直接申请，
  /// 不要先挡一层应用内说明框）。
  ///
  /// 为什么不照抄短信那行的 `Permission.sms.request()`：`QUERY_ALL_PACKAGES` 是**安装期**
  /// 权限，AOSP 没给它建 AppOps 映射（真机实测 `permissionToOp == null`），
  /// `permission_handler` 里也没有对应的一枚 Permission ⇒ 原生层压根没有"运行时弹框"这件事；
  /// 硬调 `requestPermissions` 只会立刻回 GRANTED，那是撒谎。
  ///
  /// 但**国产 ROM（MIUI / 澎湃 / Flyme）是在"第一次真的去枚举应用列表"的那一刻弹自己的框**。
  /// 所以顺序是：① 按用户这一次点击发起一次真枚举（给 ROM 弹框的机会）→ ② 枚举完复查三态
  /// （用户在 ROM 框里点了允许，只有这一步才看得见）→ ③ 仍读不到明确结论才退到那个固定的
  /// 系统详情页。反过来先跳详情页，就永远只是"让用户自己去设置里找开关"。
  ///
  /// 枚举走 [InstalledAppsService] 而不是裸通道：原生那道 `shouldScan` 闸门会在系统已经
  /// 明确拒绝时直接返空（不再骚扰拒绝过的用户），widget 层的通道棘轮也不因此涨数。
  Future<void> requestAppListPermission() async {
    try {
      await _enumerateApps();
    } catch (e) {
      // 枚举失败（含 ROM 框被拒后原生返错）不是终止条件：后面照样复查 + 必要时跳详情页
      debugPrint('申请应用列表权限：主动枚举未成功（$e），继续复查状态');
    }
    await checkAllPermissions();
    if (_appList == AppListPermission.granted) return;
    await _requestPermission('requestQueryAllPackagesPermission');
  }
}
