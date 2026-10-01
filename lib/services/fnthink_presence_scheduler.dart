import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../di/service_locator.dart';
import 'fnthink_contract_loader.dart';
import 'fnthink_settings.dart';
import 'platform_channel.dart';

/// 幻念推送"被杀之后还有人去问一次货"的 Dart 侧（T33 第二片 / §4-9 片1b）。
///
/// 分工与原生那一片（`80bd66f`）严格对齐，一句都不含糊：
///  - **闹钟的数值与决定权在这里**（间隔从契约 `presence.pollIntervalSeconds` 读，
///    要醒就排、不要醒就撤）。Kotlin 只负责"把这个数交给系统"和"到点之后交给执行器"；
///  - **真正干活的是那一轮收货本身**：后台引擎起起来之后调的就是下面那个入口，
///    它跑的是与前台同一套判据（同一份内核、同一个协调者），这里不加第二条收货路径。
///
/// ⚠ 三条"两边各写一份字符串"的都对不齐就没人报错，所以逐个钉：
///  - 排/撤/查那三个方法走 **App 自己那条通道**（`com.fnthink.notice/notification` 上的
///    [AppChannels.notification]，由 `FnthinkChannelHandler` 接）—— 不是 presence 通道；
///    presence 通道只承载 `roundDone` 那一发回报（worker 自己接）。
///  - `com.fnthink.notice/presence` ↔ `FnthinkPresenceWorker.PRESENCE_CHANNEL`；
///  - `fnthink_presence_handle` ↔ `FnthinkPresenceWorker.KEY_HANDLE`（prefs 落盘时会自动加
///    `flutter.` 前缀，原生读的是带前缀那一份）。
/// 错一个字符的表现都是"闹钟响过、任务跑过、而没人说这一轮结束了"，只能等到超时。
class FnthinkPresenceScheduler {
  FnthinkPresenceScheduler({required this.contracts, MethodChannel? channel})
    : _channel = channel ?? AppChannels.notification;

  /// 节奏的唯一来源。与协调者一样留成公开字段：`required this.contracts` 才有初始化形参可用
  /// （私有字段的命名参数在 Dart 里不合法），而它是 final，改不了。
  final FnthinkContractLoader contracts;
  final MethodChannel _channel;

  /// 还要不要继续醒着。
  ///
  /// `keepAwake == true` 时先补一次 handle 再排：handle 是"这台引擎该进哪个 Dart 函数"的
  /// 唯一线索，而它**只有在前台跑过一次才会写进 prefs** —— 新装包第一次开开关就走到这里，
  /// 少了这一步，后台那一轮会永远在 `no-entry-handle` 上跳过（日志有，界面上没有）。
  ///
  /// ⚠ 顺序要紧：**handle 没落盘就不排**。排了一颗进不了函数的闹钟，等于让用户为一次
  /// 必然白跑的唤醒付电 —— 而界面上看不出区别。前台收货不受影响（那条走的是循环，不是闹钟）。
  ///
  /// 撤（`keepAwake == false`）**不读契约**：契约此刻多半正不可用（读不到/不校验），
  /// 而"关掉就该停"不该被契约读数挡住；反过来排的那一次必须读契约，因为间隔只有一个作者。
  Future<void> notice({required bool keepAwake}) async {
    if (!keepAwake) {
      await _channel.invokeMethod<void>('cancelFnthinkPresence');
      return;
    }
    final seconds = await _cadenceSeconds();
    if (!await publishEntryHandle()) {
      debugPrint('[fnthink] 拿不到后台入口 handle ⇒ 这次不排闹钟（排了也起不了引擎，白耗一次唤醒）');
      return;
    }
    await _channel.invokeMethod<void>('scheduleFnthinkPresence', {
      'seconds': seconds,
    });
  }

  /// 下一轮的间隔：**只从"契约 + 本机那一档设置"读**（T88 之后仍然只有一个作者）。
  /// 取不到就抛 —— 在这里补一个 `?? 20` 就是"实现里藏了一份节奏"，改契约那一刀不会有任何东西报错。
  /// 用户没选过那一档时 `effectivePollSeconds()` 落回契约的 default，行为与今天逐字节一致。
  Future<int> _cadenceSeconds() async {
    final contract = await contracts.load();
    return FnthinkSettings(contract: contract).effectivePollSeconds();
  }

  /// 读回原生那份状态（"到底还有没有人醒"）。界面上那一行与排查用的日志都从这里取。
  Future<FnthinkPresenceStatus> status() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'fnthinkPresenceStatus',
    );
    return FnthinkPresenceStatus(
      nextRoundAt: (raw?['nextRoundAt'] as num?)?.toInt() ?? 0,
      cadenceSeconds: (raw?['cadenceSeconds'] as num?)?.toInt() ?? 0,
    );
  }
}

class FnthinkPresenceStatus {
  const FnthinkPresenceStatus({
    required this.nextRoundAt,
    required this.cadenceSeconds,
  });

  /// 下一轮被排在什么时候（毫秒）。0 = 没排。
  final int nextRoundAt;

  /// Dart 上次交下来的那一档间隔（秒）。0 = 没交过。
  final int cadenceSeconds;

  bool get armed => nextRoundAt > 0;
}

/// 后台入口的 handle 在 prefs 里的键（**不带** `flutter.` 前缀：那是 shared_preferences
/// 落盘时加的，原生读的是 `flutter.fnthink_presence_handle` —— 这一对关系由守卫钉住）。
const String kFnthinkPresenceHandleKey = 'fnthink_presence_handle';

/// 与原生 worker 那条回报通道同名（`FnthinkPresenceWorker.PRESENCE_CHANNEL`）。
const String kFnthinkPresenceChannel = 'com.fnthink.notice/presence';

/// 把"后台引擎该进哪个 Dart 函数"写进 prefs。返回**到底落盘了没有**。
///
/// 为什么值得每次续排都写一遍：这是一个幂等的整数写入，而"没写"的表现是后台那一轮
/// 每次都跳过（`no-entry-handle`）—— 用一次多余的写换掉一整类"装了新包但闹钟还在跑旧的 handle"
/// 的排查（handle 会变：函数搬家、重新编译，而 prefs 里那份不会自己跟上）。
Future<bool> publishEntryHandle() async {
  final handle = PluginUtilities.getCallbackHandle(fnthinkPresenceEntrypoint);
  if (handle == null) return false;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(kFnthinkPresenceHandleKey, handle.toRawHandle());
  return true;
}

/// 后台引擎的入口（被 `FnthinkPresenceWorker` 用 handle 调起来）。
///
/// ⚠ 这个函数**必须**是 top-level 且带 `@pragma('vm:entry-point')`：
/// tree-shaking 不看调用点（没有 Dart 代码调它，只有原生按 handle 进），
/// 少了这一行 pragma 的表现是 release 包里函数被摇掉，handle 指向一个不存在的符号 ——
/// 而那条错误要等到第一次"被杀之后"才会现形，正是最难查的那种。
///
/// ⚠ **先 `WidgetsFlutterBinding.ensureInitialized()`**（真机实测的教训，2026-09-30）：
/// 这是**另一颗 isolate**，没有跑过 `runApp` ⇒ 没有 binding ⇒ `MethodChannel` 拿不到
/// `defaultBinaryMessenger`，那一发 `roundDone` 会以 `Null check operator used on a null
/// value` 收场（日志里每 20 秒一行「roundDone 没送到」），而 SharedPreferences /
/// secure storage 这些插件同理全不可用。顺序也要紧：先建 binding，再注册插件。
///
/// `roundDone` 放在 `finally`：**不管这一轮成不成都要交回结果**。不交，worker 只能等到 90 秒
/// 超时，而 WorkManager 那侧看到的是"任务卡住"，不是"这一轮失败了"。
@pragma('vm:entry-point')
Future<void> fnthinkPresenceEntrypoint() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  const channel = MethodChannel(kFnthinkPresenceChannel);
  try {
    await runFnthinkPresenceRound();
  } catch (e) {
    // 后台 isolate 里没有 UI 也没有崩溃上报入口：留一行可 grep 的日志，不悄悄吞。
    debugPrint('[fnthink] 后台那一轮失败：$e');
  } finally {
    try {
      await channel.invokeMethod<void>('roundDone');
    } catch (e) {
      debugPrint('[fnthink] roundDone 没送到（worker 会等到超时）：$e');
    }
  }
}

/// 一轮收货。**默认值自带装配**（指向 `di/service_locator.dart` 里那个 bootstrap），
/// 于是"后台 isolate 里 getIt 是空的"这件事在那一个函数里就地解决，不指望任何人先跑过
/// `setupLocator()`。
///
/// ⚠ 这一版的形状是被真机改出来的（2026-09-30）：上一版把默认值写成"占位实现会抛"，
/// 装配那一行放在 `setupLocator()` 里 —— 而后台 isolate **永远不跑 `setupLocator()`**，
/// 于是变量一直是占位：每一轮都失败，日志里每 20 秒一行「没有装配」。那个 lambda 内部的
/// `isRegistered` 检查救不了它，因为**变量本身从来没被赋过值**。
/// 教训记在守卫里：默认值不许是空实现/占位，必须是"自己能装配起来"的那一个。
Future<void> Function() runFnthinkPresenceRound = fnthinkBackgroundRound;
