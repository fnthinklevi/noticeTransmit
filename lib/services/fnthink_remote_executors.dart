import 'package:fnthink_push/fnthink_push.dart';

import 'fnthink_l2_actions.dart';
import 'fnthink_l3_settings.dart';

/// 远程执行 片3c-2：**设备侧执行器**（真正动手的那一半）。
///
/// 抽象类（[FnthinkL2Executor] / [FnthinkL3Executor]）从 T50/T51 起就在
/// `fnthink_l2_actions.dart` / `fnthink_l3_settings.dart` 里，**到那为止 `lib/` 下
/// 没有任何一个实现** —— 也就是说 `dispatchL2Action` / `dispatchL3Setting`
/// 这两个派发函数一个调用方都没有：解析与映射都做完了，没有任何东西真的动手。
/// 这两个类把那一条缺口接上。
///
/// ⚠⚠ **依赖一律是能力函数，不是服务对象**（`NotificationService` /
/// `PermissionService` / `FnthinkSettings` 都不在这里出现）。这不是洁癖：
/// 执行发生在**后台轮次**里（收货循环 → 判定 → 窗口 → 动手），那一轮没有任何界面上下文；
/// 而更要紧的是可测 —— 这一层是本批次的**安全面**，「系统拒绝了」「找不到那一条通道」
/// 「厂商那一项没接」这几支都必须能在 `flutter test` 里跑一遍；绑在具体服务上就只能靠
/// MethodChannel mock，而 mock 的"调用过没有"分不出「原生回了 false」与「原生没这个方法」。
/// 取服务那一格在装配处（`service_locator.dart`）：它把服务的方法接成这里的回调。
class DeviceL2Executor implements FnthinkL2Executor {
  const DeviceL2Executor({
    required this.setListenerEnabled,
    required this.setChannelEnabled,
    required this.pushDeviceStateNow,
    required this.reportNotificationsNow,
    required this.ringAlertNow,
    required this.searchSmsNow,
    required this.searchCallsNow,
    required this.getLocationNow,
    required this.launchAppNow,
  });

  /// 启停整个通知监听服务。回 false = 原生拒绝了。
  final Future<bool> Function({required bool enabled}) setListenerEnabled;

  /// 落一条通道的启用状态。回 false = **那一族里没有那条通道**（不是"系统拒绝了"）。
  final Future<bool> Function(RemoteChannelTarget target) setChannelEnabled;

  /// 立刻推一次设备状态（推给谁、走哪条链路是发送侧的事）。
  final Future<bool> Function() pushDeviceStateNow;

  /// 产出「最近 [count] 条通知原文」那段正文（T124 片B）。回 null = 读不出来。
  final Future<String?> Function(int count) reportNotificationsNow;

  /// 让这台响一条（T124 片B 的 `alert:ring`）。回 false = **没显示**（权限/渠道被关）。
  final Future<bool> Function() ringAlertNow;

  /// 在本机短信里按关键词搜，组装成要回传的那段正文（T124 片B 的 `sms:search`）。
  ///
  /// `payload` 非空 = 成；否则看 `reason`（`sms-search-disabled` 开关关着 /
  /// `sms-search-refused` 没权限被拒 / `sms-search-failed` 读不出来）——
  /// 三种对用户的下一步动作不一样，所以带 reason 而不是一个 null（见接口那一格）。
  final Future<({String? payload, String? reason})> Function(String keyword)
  searchSmsNow;

  /// 在本机通话记录里按关键词搜，组装成要回传的那段正文（T124 片C 的 `calls:search`）。
  ///
  /// 与 [searchSmsNow] 同形（三种 reason 对用户的下一步不一样），但**多一道本机开关**
  /// （默认关）—— `calls-search-disabled` 说的是"这台设备的持有者没允许"。
  final Future<({String? payload, String? reason})> Function(String keyword)
  searchCallsNow;

  /// 读本机最近一次定位，组装成要回传的那段正文（T124 片C 的 `location:get`；无参数）。
  final Future<({String? payload, String? reason})> Function() getLocationNow;

  /// 打开本机登记过的一条入口（T124 片B 的 `app:launch`；[entryName] 是登记时的名称）。
  ///
  /// `ok: false` 的 [reason] 有三种（与 `sms:search` 同一理由：三种对用户的下一步不一样）：
  /// `app-launch-unknown-name` 名称对不上 / `app-launch-refused` 系统没放行 / `app-launch-failed`。
  final Future<({bool ok, String? reason})> Function(String entryName)
  launchAppNow;

  @override
  Future<FnthinkL2Result> setListener({required bool enabled}) async {
    try {
      final ok = await setListenerEnabled(enabled: enabled);
      // ⚠ **不判"当前是不是已经是那一档"**：原生回 false 有两种含义
      //   （"已经是了" 与 "系统拒绝了"），而这一层分不出来。
      //   把"已经是那一档"当失败，用户看到的是"我让它开着，它说没开成"。
      return ok
          ? const FnthinkL2Result.ok()
          : FnthinkL2Result.failed('listener:${enabled ? "start" : "stop"}');
    } catch (e) {
      // 抛异常也要记成"做失败了"而不是让整轮收货停在这里（与 dispatchL3Setting 同一纪律）。
      return FnthinkL2Result.failed(
        'threw:listener:${enabled ? "start" : "stop"}',
      );
    }
  }

  @override
  Future<FnthinkL2Result> toggleChannel(RemoteChannelTarget target) async {
    try {
      // ⚠ 落的是**目标值**不是"翻"：见 [parseChannelTarget] 顶上那段（重投会翻回去）。
      //   幂等地写一次，重投多少次都是同一个结果。
      final ok = await setChannelEnabled(target);
      if (ok) return const FnthinkL2Result.ok();
      return FnthinkL2Result.failed(
        'no-such-channel:${target.family}/${target.id}',
      );
    } catch (e) {
      return FnthinkL2Result.failed(
        'threw:channel:${target.family}/${target.id}',
      );
    }
  }

  @override
  Future<FnthinkL2Result> pushDeviceState() async {
    try {
      return await pushDeviceStateNow()
          ? const FnthinkL2Result.ok()
          : const FnthinkL2Result.failed('device-state-push-refused');
    } catch (e) {
      return const FnthinkL2Result.failed('threw:device_state:push');
    }
  }

  /// ⚠ 这里回的是**产出本身**（`Future<String?>`）而不是 [FnthinkL2Result]：
  /// "发去哪儿"不归执行器管（它连发起方是谁都看不到），它只答"取到了没有"。
  /// 抛异常与读不出来都回 null（与 `pushDeviceState` 的 catch 同一纪律：
  /// 一条坏指令不许让整轮收货停在半路）。
  @override
  Future<String?> reportNotifications(int count) async {
    try {
      return await reportNotificationsNow(count);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<FnthinkL2Result> ringAlert() async {
    try {
      return await ringAlertNow()
          ? const FnthinkL2Result.ok()
          // ⚠ "没显示"与"做失败了"在这一步是同一件事的两面：通知权限被关 / 渠道被禁用
          //   ⇒ 用户什么都没看到，而对面收到 done 会以为这台的用户被提醒过了。
          : const FnthinkL2Result.failed('alert-ring-refused');
    } catch (e) {
      return const FnthinkL2Result.failed('threw:alert:ring');
    }
  }

  @override
  Future<({String? payload, String? reason})> searchSms(String keyword) async {
    try {
      return await searchSmsNow(keyword);
    } catch (e) {
      return (payload: null, reason: 'threw:sms:search');
    }
  }

  @override
  Future<({String? payload, String? reason})> searchCalls(
    String keyword,
  ) async {
    try {
      return await searchCallsNow(keyword);
    } catch (e) {
      return (payload: null, reason: 'threw:calls:search');
    }
  }

  @override
  Future<({String? payload, String? reason})> getLocation() async {
    try {
      return await getLocationNow();
    } catch (e) {
      return (payload: null, reason: 'threw:location:get');
    }
  }

  @override
  Future<({bool ok, String? reason})> launchApp(String entryName) async {
    try {
      return await launchAppNow(entryName);
    } catch (e) {
      return (ok: false, reason: 'threw:app:launch');
    }
  }
}

/// 设备侧执行某一项 L3 设置（`grant` 把用户送到设置页 / `toggle` 直接翻本机的开关）。
///
/// ⚠ [grant] 回 true 的含义是「**已经把人送到那一页了**」，不是「已经改好了」——
/// 契约里那几个 `grant` 项全是"跳设置页请用户自己点"（原生侧至今没有静默改系统设置的能力）。
/// 两者混为一谈，界面上会立刻显示已开启，而用户还得自己去点。
///
/// ⚠ 契约 `settings.<key>.native` 记的是**语义名**（`vendorAutostart`），
/// 而这一层的 switch 用的是 `setting.key`。两者不是同一组词，也不该合成一组：
/// 加一项要同时改契约与这里，而漏掉哪一处的表现不同 —— 漏契约那处是
/// 「这一项在词表外被静默忽略」，漏这里那处是「它认得这个词、但没有对应的动作」。
class DeviceL3Executor implements FnthinkL3Executor {
  const DeviceL3Executor({
    required this.grantNotificationListener,
    required this.grantExactAlarm,
    required this.grantBatteryOptimization,
    required this.grantVendorAutoStart,
    required this.serviceRunning,
    required this.setListenerEnabled,
    required this.collectInboxEnabled,
    required this.setCollectInboxEnabled,
  });

  final Future<void> Function() grantNotificationListener;
  final Future<void> Function() grantExactAlarm;
  final Future<void> Function() grantBatteryOptimization;

  /// 厂商自启动那一条入口。**null = 这一台/这一版没接**（不是"已开启"）。
  ///
  /// ⚠ 本机有五个方法（小米/魅族/华为/oppo/vivo），而"这一台是哪个厂商"是
  /// **读设备信息**那件事 —— 按厂商选哪一个放在装配处，这里只收那一条被选中的。
  final Future<void> Function()? grantVendorAutoStart;

  /// 当前监听服务在不在跑（`monitoring` 要读它才能翻）。
  final Future<bool> Function() serviceRunning;

  /// 启停监听服务（`monitoring` 写它）。
  final Future<bool> Function({required bool enabled}) setListenerEnabled;

  /// 当前「收进幻念推送」开没开 / 把它设成某一档（`collect_inbox`）。
  final Future<bool> Function() collectInboxEnabled;
  final Future<bool> Function(bool enabled) setCollectInboxEnabled;

  @override
  Future<bool> grant(FnthinkL3Setting setting) async {
    // ⚠ `default` 那一格**不是**兜底成功：它回 false，也就是
    // 「这一台压根没有那一项的入口」。把不认识的一项当成功，
    // 界面上就会立刻显示"已开启"而用户根本没被送到任何地方。
    try {
      switch (setting.key) {
        case 'notification':
          await grantNotificationListener();
          return true;
        case 'exact_alarm':
          await grantExactAlarm();
          return true;
        case 'battery_optimization':
          await grantBatteryOptimization();
          return true;
        case 'autostart':
          final go = grantVendorAutoStart;
          if (go == null) return false;
          await go();
          return true;
        default:
          return false;
      }
    } catch (e) {
      // 抛异常同样回 false（"没送成"），而不是让整轮收货停在一条坏指令上。
      return false;
    }
  }

  /// 设一个本机开关（L3 那两个 `toggle` 项：`monitoring` / `collect_inbox`）。
  ///
  /// ⚠ **带目标值时幂等**：item 写成 `<key>/on` 或 `<key>/off`
  ///   （契约 `l3.itemMayCarryTarget` / `itemTargetWords`）⇒ 写进去的就是那一档，
  ///   重投多少次结果一样。
  /// ⚠ **不带目标值时退回读当前再翻**（`setting.targetValue == null`）——
  ///   那是老的对端今天那套写法，**不幂等**：重投一次就翻两次、回到原状。
  ///   仍然保留它是因为老发送侧不必升级就能继续用；代价由维护者知情（见契约
  ///   `itemTargetWhy` 里的发版次序那一段）。
  /// ⚠ 也不许把不带目标值的那一格悄悄做成幂等（写死成开）——
  ///   那会让 `collect_inbox` 永远开着，而那正是这一项存在的反面。
  @override
  Future<bool> toggle(FnthinkL3Setting setting) async {
    try {
      switch (setting.key) {
        case 'monitoring':
          return await setListenerEnabled(
            enabled: setting.targetValue ?? !(await serviceRunning()),
          );
        case 'collect_inbox':
          return await setCollectInboxEnabled(
            setting.targetValue ?? !(await collectInboxEnabled()),
          );
        default:
          return false;
      }
    } catch (e) {
      return false;
    }
  }
}
