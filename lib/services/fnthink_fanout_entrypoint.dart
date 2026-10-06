import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant, PluginUtilities;

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../di/service_locator.dart';
import 'fnthink_receive_coordinator.dart';

/// 后台入口 handle 在 prefs 里的键（**不带** `flutter.` 前缀：那是 shared_preferences 落盘时
/// 加的，原生读的是 `flutter.fnthink_fanout_handle` —— 这一对关系与收货那一轮
/// （`fnthink_presence_handle`）同形，由原生侧的 `FnthinkMirrorContractTest` 钉住）。
const String kFnthinkFanoutHandleKey = 'fnthink_fanout_handle';

/// 与原生 worker 那条回报通道同名（`FnthinkFanoutWorker.FANOUT_CHANNEL`）。
const String kFnthinkFanoutChannel = 'com.fnthink.notice/fanout';

/// 把"后台引擎该进哪个 Dart 函数"写进 prefs。返回**到底落盘了没有**。
///
/// 为什么值得每次进幻念推送那块都重写一遍：这是幂等的整数写入，而"没写"的表现是每一条
/// 通知都落进待发队列然后被丢掉（原生日志一行 `fanout-round-dropped:no-entry-handle`）——
/// 用一次多余的写换掉一整类"装了新包但还拿着旧 handle"的排查。
Future<bool> publishFnthinkFanoutEntryHandle() async {
  final handle = PluginUtilities.getCallbackHandle(fnthinkFanoutEntrypoint);
  if (handle == null) return false;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(kFnthinkFanoutHandleKey, handle.toRawHandle());
  return true;
}

/// 待发队列在 prefs 里的键（**不带** `flutter.` 前缀：原生写进去时带的，
/// Dart 的 `SharedPreferences` 读回来是去掉前缀的那个名字）。
const String kFnthinkFanoutPendingKey = 'fnthink_fanout_pending';

/// 后台引擎的入口（被 `FnthinkFanoutWorker` 用 handle 调起来）。
///
/// ⚠ 这个函数**必须**是 top-level 且带 `@pragma('vm:entry-point')`，理由与收货那一轮相同：
/// tree-shaking 不看调用点，少了那一行 pragma 的表现是 release 包里函数被摇掉，
/// handle 指向一个不存在的符号 —— 而那条错误要等到第一条通知来时才现形。
///
/// ⚠ **先 `WidgetsFlutterBinding.ensureInitialized()`**：这是**另一颗 isolate**，没有跑过
/// `runApp` ⇒ 没有 binding ⇒ `MethodChannel` 拿不到 `defaultBinaryMessenger`，那一发
/// `fanoutDone` 会以空值异常收场，而 worker 那侧只能等到超时。
///
/// `fanoutDone` 放在 `finally`：不管这一轮成不成都要交回结果。
@pragma('vm:entry-point')
Future<void> fnthinkFanoutEntrypoint(List<String>? args) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  const channel = MethodChannel(kFnthinkFanoutChannel);
  try {
    await runFnthinkFanoutRound(await claimPendingFanoutBatch());
  } catch (e) {
    // 后台 isolate 里没有 UI 也没有崩溃上报入口：留一行可 grep 的日志，不悄悄吞。
    debugPrint('[fnthink] 后台转发那一轮失败：$e');
  } finally {
    try {
      await channel.invokeMethod<void>('fanoutDone');
    } catch (e) {
      debugPrint('[fnthink] fanoutDone 没送到（worker 会等到超时）：$e');
    }
  }
}

/// **取走**待发队列（读 + 清，一次连着做完）并交出正文。
///
/// 为什么读与清必须由同一侧连着做：留着的那一条会被下一次触发再发一遍，而"这一轮失败了"
/// 没有任何人替它记账 ⇒ 表现是同一条通知反复转发。
///
/// 取不到就交 `'[]'`：那不是"出错"，是队列已经空了（worker 起引擎前也判过一次，
/// 但两次之间可能有另一轮把它排空了）。
Future<String> claimPendingFanoutBatch() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kFnthinkFanoutPendingKey);
  if (raw == null || raw.isEmpty) return '[]';
  await prefs.remove(kFnthinkFanoutPendingKey);
  return raw;
}

/// 跑一轮转发。**默认值自带装配**（同收货那一轮的教训：赋值写在 `setupLocator()` 里的形状
/// 在后台 isolate 里永远是占位实现）。
Future<void> Function(String batchJson) runFnthinkFanoutRound =
    fnthinkBackgroundFanoutRound;

/// 一轮转发（后台 isolate 用）。
///
/// 逐条走**既有的** [FnthinkReceiveCoordinator.sendNotice] 咽喉 —— 不另开一条发消息的路：
/// 那条咽喉已经带着签名、nonce、契约正文信封与 T60 的 `chan:fnthink` 送达记录，
/// 另写一份只会得到一个"发出去了但历史里什么都不留"的次品。
Future<void> fnthinkBackgroundFanoutRound(String batchJson) async {
  // 前台进程里整棵树已经装好了（`registerLazySingleton` 二次注册会抛）；
  // 后台 isolate 里 getIt 是空的 —— 那一次由这里补上，且必须在发送之前。
  if (!getIt.isRegistered<FnthinkReceiveCoordinator>()) setupLocator();
  final coordinator = getIt<FnthinkReceiveCoordinator>();

  final items = parseFanoutBatch(batchJson);
  if (items.isEmpty) return;

  var sent = 0;
  var failed = 0;
  for (final item in items) {
    // 标题正文都空的那一条不占位：契约的正文信封要求有内容，
    // 发一条空消息得到的是对端一次无意义的 4xx 与一条"发送失败"的送达记录。
    if (item.title.trim().isEmpty && item.text.trim().isEmpty) continue;
    for (final target in item.targets) {
      try {
        await coordinator.sendNotice(
          peer: target,
          title: item.title.trim().isEmpty ? item.appName : item.title,
          text: item.text.trim().isEmpty ? item.title : item.text,
          // 逐条传而不是每轮一次：同一批里可能既有主通道选中的也有降级选中的
          // （轮询到不同通道的结果不同），按轮传就会把其中一半标错。
          viaBackup: item.viaBackup,
        );
        sent++;
      } catch (e) {
        failed++;
        // 只记目标与异常，不记正文（T89 脱敏的同一口径）。
        debugPrint('[fnthink] 转发到一台设备失败：$e');
      }
    }
  }
  debugPrint('[fnthink] 后台转发完成：${items.length} 条待发，成功 $sent，失败 $failed');
}

/// 一条待发通知（原生队列里的形状，跨语言契约）。
class FnthinkFanoutItem {
  const FnthinkFanoutItem({
    required this.id,
    required this.title,
    required this.text,
    required this.appName,
    required this.targets,
    this.viaBackup = false,
  });

  final String id;
  final String title;
  final String text;
  final String appName;

  /// 这一轮路由判下来的**设备地址码**（webhook 目标由原生自己发，不过这里）。
  final List<String> targets;

  /// 这一轮是不是降级后才选中幻念通道的（T94 片4d）。
  ///
  /// ⚠ **这一列此前被丢在这里**：原生 `buildItem` 一直在写它，而本类没有这个字段，
  /// 于是值在解析这一步消失，往下再没有一处知道"这一条走了备用"。
  /// 表现是**只有幻念这一族**的历史不标「备用」，另外三族都标 ——
  /// 比一律不标更难查，因为看起来像随机丢。
  final bool viaBackup;
}

/// 解析原生交下来的那一批（纯函数，便于用例直接喂字符串）。
///
/// 坏形状一律**整条跳过**而不是抛：那批东西已经被原生从队列里取走了，为一条读不懂的项
/// 把整轮丢掉，代价是这一轮里本来读得懂的那些也一起没了。
List<FnthinkFanoutItem> parseFanoutBatch(String batchJson) {
  final Object? decoded;
  try {
    decoded = jsonDecode(batchJson);
  } catch (_) {
    return const [];
  }
  if (decoded is! List) return const [];
  final items = <FnthinkFanoutItem>[];
  for (final raw in decoded) {
    if (raw is! Map) continue;
    final targets = <String>[];
    final rawTargets = raw['targets'];
    if (rawTargets is List) {
      for (final t in rawTargets) {
        if (t is Map && t['target'] is String) {
          final addr = '${t['target']}'.trim();
          if (addr.isNotEmpty) targets.add(addr);
        }
      }
    }
    if (targets.isEmpty) continue;
    items.add(
      FnthinkFanoutItem(
        id: '${raw['id'] ?? ''}',
        title: '${raw['title'] ?? ''}',
        text: '${raw['content'] ?? ''}',
        appName: '${raw['appName'] ?? ''}',
        targets: targets,
        // 只认真正的 bool：原生写的是 JSON true/false，而 `1`/`'true'` 这类形状
        // 说明有人改过写盘那一侧 —— 宁可当成"没走备用"（少标一枚）也不替它猜。
        viaBackup: raw['viaBackup'] == true,
      ),
    );
  }
  return items;
}
