import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一条通道最近一次探测的结果。
class ChannelHealth {
  const ChannelHealth({
    required this.reachable,
    required this.latencyMs,
    required this.probedAt,
    this.httpCode,
  });

  final bool reachable;
  final int latencyMs;

  /// 毫秒时间戳（epoch ms）
  final int probedAt;

  /// webhook 探测有 HTTP 码；应用通道（换 token）与邮件（SMTP 认证）没有
  final int? httpCode;

  factory ChannelHealth.fromMap(Map<dynamic, dynamic> map) => ChannelHealth(
    reachable: map['reachable'] == true,
    latencyMs: (map['latencyMs'] as num?)?.toInt() ?? 0,
    probedAt: (map['probedAt'] as num?)?.toInt() ?? 0,
    httpCode: (map['httpCode'] as num?)?.toInt(),
  );

  Map<String, Object?> toMap() => {
    'reachable': reachable,
    'latencyMs': latencyMs,
    'httpCode': httpCode,
    'probedAt': probedAt,
  };
}

/// 通道健康度的**唯一**读写处（第 6 步）。
///
/// 之前是三份：webhook 页自己读 + 自己写 + 自己判 6h 时效；应用通道页自己读 + 自己写
/// （6h 判定根本没有，进页不探，见 ㉝ 的注释）；email 另用
/// `email_test_results` 一个 JSON Map（没有时间戳，所以永远说不出"多久以前"）。
/// 同一件事三份实现，表现就是三族通道的徽标行为互不相同、且没人说得清哪族是"对的"。
///
/// 键格式 `channel_health_<family>:<id>`：带 family 是因为三族通道各自有 id 序列，
/// 不带 family 时一旦 id 撞上（历史上有过 `wh_`/`app_` 前缀不一致的时期）徽标就会串台。
/// 旧格式 `channel_health_<id>`（不带 family，第 6 步之前的写法）**不迁移、只读穿**：
/// 键里的 id 就是那条通道自己的 id，所以按调用方的族解释即可，不需要猜 family
/// （靠 id 前缀猜会把 `app-h2` 这类命名判成 webhook）。下次探测自然写成新键。
class ChannelHealthStore {
  ChannelHealthStore();

  static const keyPrefix = 'channel_health_';
  static const legacyEmailMapKey = 'email_test_results';

  /// 超过这个时长就算过期，页面进页时后台刷新（webhook 沿用既有 6h 口径）
  static const staleness = Duration(hours: 6);

  final Map<String, ChannelHealth> _entries = {};
  bool _loaded = false;

  static String keyOf(String family, String id) => '$keyPrefix$family:$id';

  /// 装载（幂等）。页面进页前由 splash 调一次，写过的条目会被同步进内存。
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().where((k) => k.startsWith(keyPrefix))) {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        final health = _decode(raw);
        if (health == null) continue;
        _entries[key] = health;
      }
      _migrateEmailResults(prefs);
      _loaded = true;
    } catch (e) {
      debugPrint('ChannelHealthStore: 装载失败（徽标会暂时不显示）: $e');
    }
  }

  /// 读某条通道的最近结果；没有记录返回 null（页面据此"不显示徽标"）。
  ChannelHealth? of(String family, String id) {
    if (id.isEmpty) return null;
    // 旧键（不带 family）按键面原样读：id 本身就是那条通道的标识，
    // 归到哪个族由**调用方**决定，不靠 id 前缀猜。
    return _entries[keyOf(family, id)] ?? _entries['$keyPrefix$id'];
  }

  /// 是否该重新探测（没有记录，或记录超过 [staleness]）。
  static bool needsProbe(ChannelHealth? health, {DateTime? now}) {
    if (health == null) return true;
    final probedAt = DateTime.fromMillisecondsSinceEpoch(health.probedAt);
    return now == null
        ? DateTime.now().difference(probedAt) > staleness
        : now.difference(probedAt) > staleness;
  }

  /// 记一次探测结果（内存 + prefs）。失败只记日志：健康度是派生缓存，
  /// 写不进去下次再探就是，不该把保存/测试流程带崩。
  Future<void> record(
    String family,
    String id, {
    required bool reachable,
    required int latencyMs,
    int? httpCode,
  }) async {
    if (id.isEmpty) return;
    final health = ChannelHealth(
      reachable: reachable,
      latencyMs: latencyMs,
      httpCode: httpCode,
      probedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final key = keyOf(family, id);
    _entries[key] = health;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(health.toMap()));
    } catch (e) {
      debugPrint('ChannelHealthStore: 写入 $key 失败: $e');
    }
  }

  /// 通道被删除后清掉它的缓存条目（否则 id 复用时徽标会复活成上一条的状态）。
  ///
  /// 两个键都要清：新格式 `channel_health_<family>:<id>`，以及第 6 步之前留下的
  /// 旧格式 `channel_health_<id>`（[of] 会读穿它 ⇒ 只清新键的话，删掉的通道在界面上
  /// 仍然带着上一次的徽标，这条是 webhook 删除用例实测出来的）。
  Future<void> remove(String family, String id) async {
    if (id.isEmpty) return;
    final keys = [keyOf(family, id), '$keyPrefix$id'];
    for (final key in keys) {
      _entries.remove(key);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint('ChannelHealthStore: 删除 $keys 失败: $e');
    }
  }

  /// email 族旧存储：`email_test_results` 是一个 `id → bool` 的 JSON Map，
  /// 没有耗时与时间戳。搬进来时 probedAt 记 0 ⇒ 一定算过期，下次进页自然重探。
  void _migrateEmailResults(SharedPreferences prefs) {
    final raw = prefs.getString(legacyEmailMapKey);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.forEach((id, ok) {
        final key = keyOf('email', id);
        if (_entries.containsKey(key)) return;
        _entries[key] = ChannelHealth(
          reachable: ok == true,
          latencyMs: 0,
          probedAt: 0,
        );
      });
      unawaited(
        prefs.remove(legacyEmailMapKey).catchError((Object e) {
          debugPrint('ChannelHealthStore: 清理 email 旧缓存失败: $e');
          return false;
        }),
      );
    } catch (e) {
      debugPrint('ChannelHealthStore: email 旧缓存解析失败: $e');
    }
  }

  static ChannelHealth? _decode(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is Map) return ChannelHealth.fromMap(map);
    } catch (_) {
      // 坏数据按「没有记录」处理：一个坏条目不该让整份缓存读不出来
    }
    return null;
  }
}
