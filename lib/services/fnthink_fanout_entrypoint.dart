import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant, PluginUtilities;

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../di/service_locator.dart';
import '../database/database_helper.dart';
import '../models/delivery_status.dart';
import 'channel_display.dart';
import 'fnthink_delivery_link_store.dart';
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

/// 一条的转发结局（T154 片1）。
class FnthinkFanoutOutcome {
  const FnthinkFanoutOutcome({required this.sent, required this.failed});

  /// 已经交给服务端的目标数（`sendNotice` 返回 `accepted`）。
  final int sent;

  /// 这一轮没送出去的目标数（前置不满足／网络失败／服务端拒收）。
  final int failed;

  /// 该在那条通知的送达格上写哪个状态词。
  ///
  /// 口径（T154 片1 立，维护者 2026-10-15 第 2 条）：
  ///  - **只要有一条交出去了** ⇒ `queued`：那一份已经躺在服务端排队，等对面来取。
  ///    多目标时不去细分"两台里只成了一台" —— 送达格按**通道**记（`chan:fnthink`
  ///    只有一个格），而这一格要回答的是"本机还欠不欠这一次投递"，答案是"不欠了"。
  ///  - **一条都没交出去** ⇒ `failed`：本机自己就没做成，与"对面没上线"是两件事。
  String get status => sent > 0 ? 'queued' : 'failed';
}

/// 把一条的结局写回那条通知记录的送达格。**可替换**（同 [runFnthinkFanoutRound]
/// 那条理）：后台 isolate 里默认实现自己装配 DB，测试替换它来断言"报了什么"。
Future<void> Function(String recordId, FnthinkFanoutOutcome outcome)
recordFnthinkFanoutOutcome = fnthinkDefaultRecordFanoutOutcome;

/// 默认实现：读那条记录 → 改 `chan:fnthink` 那一格 → 写回。
///
/// ⚠ **这一条链在 T154 片1 之前根本不存在**：幻念设备档的转发走的是
/// 原生队列 → 本函数上一级的后台轮 → `sendNotice`，**全程没有一处发过送达回执**。
/// 而入库时 `deliveryKeysOfActiveChannels` 照给了 `chan:fnthink` 一个初始 `pending`
/// ⇒ 那一格永远停在「发送中」，无论对面在不在线（维护者看到的就是它）。
/// T150 片1 处理的是同一个形状的另一处（`role=none` 的通道领了 pending 却永远
/// 没有回执来推离 ⇒ 直接不进名单）；这一处不能靠"不进名单"解决 ——
/// 转发的确发生了，该做的是**补上回执**。
Future<void> fnthinkDefaultRecordFanoutOutcome(
  String recordId,
  FnthinkFanoutOutcome outcome,
) async {
  if (recordId.isEmpty) return;
  // ⚠ 直连 `DatabaseHelper()`：它是 factory 单例，全仓各处（含本文件所属的接线）
  //   都是直接 new，**没有走 getIt**。写 `getIt<DatabaseHelper>()` 会同时踩两件事 ——
  //   后台 isolate 里读不到、以及 `fnthink_receive_wiring_test` 那条
  //   「getIt<X>() 必须都有注册」的守卫当场红。
  final db = DatabaseHelper();
  final row = await db.getNotificationById(recordId);
  if (row == null) return;

  // 现读现改：那一格可能已经被别的通道的结果改过（一条通知同时推 webhook 与幻念），
  // 整表重建会把别人的结论抹掉。
  Map<String, dynamic> info = const {};
  final raw = row['delivery_info'];
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        info = Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      // 坏 JSON 不阻止我们写下这一条真实结局：把它当空表重写，
      // 丢的是别的通道那一格（它本来就坏得读不出来）。
      debugPrint('[fnthink] 送达格里的旧值读不出来，按空表重写：$e');
    }
  }

  final key = channelDeliveryKey(kFnthinkChannelSlug);
  debugPrint(
    '[fnthink] fanout-receipt record=$recordId channelKey=$key '
    'status=${outcome.status} sent=${outcome.sent} failed=${outcome.failed}',
  );
  final previous = info[key];
  // T154 端到端：这一轮还在发的时候，对端可能已经取走了前一台目标的那条
  // （收货循环是另一个 author，与本轮并行）⇒ 后到的转发结局不许把「已送达」
  // 降级成 `queued`。与 `applyFnthinkReceiptToDelivery` 同一条粘滞规矩。
  if (previous is Map && previous['status'] == peerDeliveredStatus) return;
  info[key] = {
    'status': outcome.status,
    'message': 'fanout: ${outcome.sent}/${outcome.sent + outcome.failed}',
    // 粘滞标记（与 `applyDelivery` 同一条规矩）：这一轮确实走了备用就不再清掉。
    if (previous is Map && previous['viaBackup'] == true) 'viaBackup': true,
  };
  await db.updateNotificationDelivery(recordId, info);
}

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
    final outcome = await sendAndReportFanoutItem(
      item,
      sendToTarget: (target) => coordinator.sendNotice(
        peer: target,
        title: item.title.trim().isEmpty ? item.appName : item.title,
        text: item.text.trim().isEmpty ? item.title : item.text,
        // T172：来源应用名进已签信封；收件端拿它当通知标题。
        appName: item.appName,
        // 逐条传而不是每轮一次：同一批里可能既有主通道选中的也有降级选中的
        // （轮询到不同通道的结果不同），按轮传就会把其中一半标错。
        viaBackup: item.viaBackup,
      ),
    );
    sent += outcome.sent;
    failed += outcome.failed;
  }
  debugPrint('[fnthink] 后台转发完成：${items.length} 条待发，成功 $sent，失败 $failed');
}

/// **一条**通知的发送与记账（T154 片1 抽出来的唯一判据处）。
///
/// 为什么值得单独成一个函数：这一段的每一句都是判据（逐目标 try/catch、
/// "至少一条成 ⇒ queued"、回执失败不带走整轮），而它要能被测试注入假发送 ——
/// 测试里照抄一遍这段循环，就有了第二份判据，两份迟早会漂开
/// （本仓 `deliveryBucketOf` 那一轮漂开的正是这种形状）。
///
/// `sendToTarget` 抛异常 = 这一台没送出去；正常返回但 `status != accepted` 也算没成
/// （服务端拒收不是"已交给服务端"）；只有 `accepted` 才算这一台成了。
/// 成功时把 `messageId → item.id` 记进送达映射 —— 对端取走后的回执靠它找回本地那一行
/// （T154 端到端）。
/// 返回这一条的结局（已在内部报过回执，调用方只用来累计日志）。
Future<FnthinkFanoutOutcome> sendAndReportFanoutItem(
  FnthinkFanoutItem item, {
  required Future<FnthinkSendResult> Function(String target) sendToTarget,
}) async {
  var itemSent = 0;
  var itemFailed = 0;
  debugPrint(
    '[fnthink] fanout-send record=${item.id} '
    'channelKey=${channelDeliveryKey(kFnthinkChannelSlug)} targets=${item.targets.length}',
  );
  for (final target in item.targets) {
    try {
      final result = await sendToTarget(target);
      if (result.status != FnthinkSendStatus.accepted) {
        itemFailed++;
        continue;
      }
      itemSent++;
      final messageId = result.messageId ?? '';
      if (messageId.isNotEmpty) {
        await FnthinkDeliveryLinkStore().link(
          messageId: messageId,
          recordId: item.id,
        );
      }
    } catch (e) {
      itemFailed++;
      // 只记目标与异常，不记正文（T89 脱敏的同一口径）。
      debugPrint('[fnthink] 转发到一台设备失败：$e');
    }
  }
  final outcome = FnthinkFanoutOutcome(sent: itemSent, failed: itemFailed);
  // 回执写回**单独 try**：它失败了不该把这一轮的其他条目带走
  // （发送本身已经成功，而"历史里那一格没改"比"后面的通知没发出去"轻得多）。
  try {
    await recordFnthinkFanoutOutcome(item.id, outcome);
  } catch (e) {
    debugPrint('[fnthink] 这一条的送达回执没写进去（发送本身已结束）：$e');
  }
  return outcome;
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
