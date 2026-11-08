import 'dart:async';
import 'dart:ui' show DartPluginRegistrant, PluginUtilities;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';
import '../di/service_locator.dart';
import 'fnthink_fanout_entrypoint.dart';
import 'fnthink_presence_scheduler.dart';
import 'fnthink_receive_coordinator.dart';
import 'fnthink_service_bridge.dart';

/// 常驻服务引擎的 handle 键（不带 `flutter.` 前缀；原生读 `flutter.fnthink_service_handle`）。
const String kFnthinkServiceHandleKey = 'fnthink_service_handle';

/// 与原生 `FnthinkServiceEngine.SERVICE_CHANNEL` 同名。
const String kFnthinkServiceChannel = 'com.fnthink.notice/service';

/// 把服务引擎入口写进 prefs。UI 冷启动写一次，服务引擎起来后再重写一次。
Future<bool> publishFnthinkServiceHandle() async {
  final handle = PluginUtilities.getCallbackHandle(fnthinkServiceEntrypoint);
  if (handle == null) return false;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(kFnthinkServiceHandleKey, handle.toRawHandle());
  return true;
}

/// 常驻服务引擎入口（T197 片3）：服务进程里一直活着，只在 UI 心跳过期时接管收货。
///
/// 与 [fnthinkPresenceEntrypoint] 的区别：那一颗只跑一轮就退出（WorkManager 的兜底），
/// 这一颗**不退出**——它用 10 秒一次的心跳检查决定"现在该不该持有收货循环"，
/// 同时在同一颗 isolate 里接住原生转来的 `fanoutNow`（发送端秒级的那一半）。
///
/// ⚠ 必须 `@pragma('vm:entry-point')`：只有原生按 handle 进，没有 Dart 调用点。
/// ⚠ 先 binding 再插件注册：这是独立 isolate，没有 `runApp` 就没有 `defaultBinaryMessenger`。
@pragma('vm:entry-point')
Future<void> fnthinkServiceEntrypoint() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // 长活引擎要持 SSE；它不是"只活一轮"的后台轮。
  fnthinkAllowStream = true;
  // 与后台轮同一档：不开常驻轮询档/不持前台锁（那是 UI 与原生服务的事），
  // 但允许门铃。重连退避沿用后台那一档的上限。
  fnthinkBackgroundIsolate = true;
  // 后台引擎没有界面：不许替用户做任何破坏性开库动作。
  DatabaseHelper.allowDestructiveOpen = false;

  if (!getIt.isRegistered<FnthinkReceiveCoordinator>()) setupLocator();

  // handle 由 UI 主 isolate 写（`PluginUtilities.getCallbackHandle` 的根 isolate 语义）：
  // 后台 isolate 不重写这三枚，避免把 UI 写好的值覆盖成 null/旧值。
  const channel = MethodChannel(kFnthinkServiceChannel);
  channel.setMethodCallHandler((call) async {
    if (call.method == 'fanoutNow') {
      await drainPendingFanout();
      return true;
    }
    if (call.method == 'stop') {
      getIt<FnthinkReceiveCoordinator>().stopLoopOnly();
      return true;
    }
    return null;
  });

  final coordinator = getIt<FnthinkReceiveCoordinator>();
  Timer.periodic(
    const Duration(seconds: 10),
    (_) => unawaited(_syncReceiveOwnership(coordinator, channel)),
  );
  await _syncReceiveOwnership(coordinator, channel);
}

/// 心跳检查：新鲜 ⇒ UI 在，服务只停自己的循环（**不动闹钟**，那颗归 UI）；
/// 过期 ⇒ UI 被收走，服务接管收货。
Future<void> _syncReceiveOwnership(
  FnthinkReceiveCoordinator coordinator,
  MethodChannel channel,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final uiAlive = prefs.getInt(kFnthinkUiAliveKey);
    final fresh = fnthinkUiAlive(
      uiAlive,
      DateTime.now().millisecondsSinceEpoch,
    );
    if (fresh) {
      if (coordinator.isRunning) coordinator.stopLoopOnly();
    } else if (!coordinator.isRunning) {
      final result = await coordinator.startIfEnabled();
      if (!result.started && result.reason != 'disabled') {
        debugPrint('[fnthink] 服务引擎收货没起来：${result.reason}');
      }
    }
    // 给原生报活：引擎僵尸时服务侧按 90 秒超时重建。
    await channel.invokeMethod<void>('alive');
  } catch (e) {
    // 这条链上的失败不许把 Timer 打死；下一轮继续。
    debugPrint('[fnthink] 服务引擎同步失败：$e');
  }
}

/// 在同一颗常驻 isolate 里排空待发队列（发送端秒级）。
///
/// 队列的"读 + 清"仍由 [claimPendingFanoutBatch] 一次做完；这里只负责在
/// 有货时连续跑到空（或到上限），不另开一颗引擎。
Future<void> drainPendingFanout() async {
  for (var i = 0; i < 20; i++) {
    final batch = await claimPendingFanoutBatch();
    if (batch == '[]') return;
    await runFnthinkFanoutRound(batch);
  }
  debugPrint('[fnthink] 服务引擎待发队列一轮未排空（到 20 轮上限）');
}
