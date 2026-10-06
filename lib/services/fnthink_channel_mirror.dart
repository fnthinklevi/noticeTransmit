import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/fnthink_channel.dart';
import 'channel_config_codec.dart';

/// 幻念通道配置的**跨端镜像**（T94 片4）。
///
/// 为什么需要它：`fnthink_channels` 住在 Dart 的 SQLite 里，而原生**打不开那个库**
/// （没有 SQLCipher 依赖，与 `ConfigManager` 里 T20 那条注释同因）。另外三族能进原生
/// `routeChannels()`，靠的全是 Dart 写进 `FlutterSharedPreferences` 的那份镜像键 ——
/// 幻念族要参与同一次主备决策，就得走同一条路，而不是另开一条读库的路。
///
/// 镜像里放什么：**启用中的**通道（含 role=none）。角色到"推不推"的裁决留在原生
/// （`ChannelRole.parse` + `ConfigManager.getFnthinkChannelConfigs` 排除 NONE），
/// 与另外三族同口径；Dart 侧提前把 none 滤掉的话，"这一族参与不参与主备"就有了第二个
/// 真值，而两处口径不同步的表现是界面上灰着的一条照样被推出去。
const String kFnthinkChannelMirrorKey = 'fnthink_channels';

/// 镜像正文（纯函数，不碰平台）⇒ 一行 JSON 数组。
///
/// 字段名用 snake_case：这是**跨语言字符串契约**，由原生侧的
/// `FnthinkMirrorContractTest` 双向钉住（它从**两侧源码现取**键集合再比对 ——
/// 各写一份期望集合的话，改 Dart 的键并顺手改 Dart 用例就会两边一起绿）。
String encodeFnthinkChannelMirror(List<FnthinkChannel> channels) {
  final rows = channels
      .where((c) => c.enabled)
      .map(
        (c) => <String, Object?>{
          'id': c.id,
          'name': c.name,
          'target_kind': FnthinkChannel.kindToDb(c.targetKind),
          'target': c.target,
          'role': ChannelConfigCodec.normalizeRole(c.role),
        },
      )
      .toList();
  return jsonEncode(rows);
}

/// 把镜像写进 prefs。返回**到底落盘了没有** —— 写失败不能静默：
/// 表现会是"通道建好了、通知到了、哪儿都没转"，而界面上没有任何一处会说这件事。
///
/// 键名落盘时自动加 `flutter.` 前缀，原生读的是 `flutter.fnthink_channels`（同
/// `ConfigManager.FLUTTER_PREFS_NAME` + `KEY_WEBHOOK_URLS` 的形状）。
Future<bool> publishFnthinkChannelMirror(List<FnthinkChannel> channels) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.setString(
    kFnthinkChannelMirrorKey,
    encodeFnthinkChannelMirror(channels),
  );
}
