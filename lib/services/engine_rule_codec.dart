import 'dart:convert';

/// 通知引擎规则（电量族 / 温度族）的**唯一形状归一点**：UI map ↔ DB 行 ↔ 原生兼容镜像。
///
/// 为什么要有这个文件：T20 之前这条形状保证散在**两处** —— Dart 把 UI map 原样
/// `jsonEncode` 进 prefs，原生 `setBatteryRules` 再按自己那套默认值把**同一把键**重写一遍。
/// 两处默认值本就不一致（原生缺省 `value=20/45`、Dart 侧从不缺省），而规则形状一旦漂移，
/// 表现是"原生读到缺省值 → 用户配的阈值永远不触发"，界面上看不出任何异常。
/// 单点之后原生侧只读不写（roadmap T20）。
///
/// ⚠ 镜像 JSON 的键名是**跨语言字符串契约**：`BatteryMonitor.parseBatteryRules` 按
/// `id/type/value/enabled/title` 取值，改这里必须同时改那里，否则静默失配。
/// 由 `android/.../EngineRuleMirrorContractTest.kt` 实测比对两个键集合。
class EngineRuleCodec {
  EngineRuleCodec._();

  static const familyBattery = 'battery';
  static const familyTemperature = 'temperature';

  /// 引擎规则一共就这五族（`position` 与 `updated_at` 是存储侧的，不进 UI map）。
  static const uiKeys = ['id', 'type', 'value', 'enabled', 'title', 'content'];

  /// 规则类型缺失时原生今天用的就是这些缺省（`parseBatteryRules` 的 `optString`）。
  /// 沿用同值，才等于"入 DB 这一步不改变任何人的告警行为"。
  static const _defaultType = {
    familyBattery: 'level_below',
    familyTemperature: 'battery_temp_above',
  };
  static const _defaultValue = {familyBattery: 20, familyTemperature: 45};

  /// 归一单条规则：认不出的形状（null、非 Map）由调用方丢弃，**不**在这里塞默认值 ——
  /// 凭空造出一条用户没配过的规则比少一条更糟。
  static Map<String, dynamic>? normalize(Object? raw, String family) {
    if (raw is! Map) return null;
    final type = raw['type'];
    final value = raw['value'];
    return <String, dynamic>{
      'id': raw['id']?.toString() ?? '',
      'type': type is String && type.isNotEmpty
          ? type
          : (_defaultType[family] ?? 'level_below'),
      // MethodChannel / JSON 都可能给 Double（滑块、老备份）：`as int` 会抛，
      // 而原生那侧一直是 `Number.toInt()`，这里同口径。
      // ⚠ 缺 `value` 时取 20/45 而不是旧镜像写的 0：`level_below 0` 永不触发，
      //   等于把用户一条规则静默作废（两处默认值不一致正是本文件要结束的）。
      'value': value is num ? value.toInt() : (_defaultValue[family] ?? 20),
      // 缺键 = 启用（原生 `optBoolean("enabled", true)` 同口径）：把一条没写 enabled
      // 的老规则判成"关闭"，升级后就再也推不出来了。显式写了才按写的算。
      'enabled': raw['enabled'] == null || raw['enabled'] == true,
      'title': raw['title']?.toString() ?? '',
      'content': raw['content']?.toString() ?? '',
    };
  }

  /// 归一整个列表：坏条目跳过（保留其余），**不**整批退回默认值。
  static List<Map<String, dynamic>> normalizeAll(
    Iterable<Object?> raw,
    String family,
  ) => raw
      .map((e) => normalize(e, family))
      .whereType<Map<String, dynamic>>()
      .toList();

  /// 写进 `engine_rules` 的一行。列名 `threshold` 而 JSON 键是 `value`：
  /// 后者是原生契约（改不动），前者是库里更自洽的名字。
  static Map<String, Object?> toDbRow(
    Map<String, dynamic> ui,
    String family,
    int position,
    int now,
  ) => {
    'family': family,
    'position': position,
    'id': ui['id'],
    'type': ui['type'],
    'threshold': ui['value'],
    'title': ui['title'],
    'content': ui['content'],
    'enabled': ui['enabled'] == true ? 1 : 0,
    'updated_at': now,
  };

  static Map<String, dynamic> fromDbRow(Map<String, Object?> row) => {
    'id': row['id']?.toString() ?? '',
    'type': row['type']?.toString() ?? '',
    'value': (row['threshold'] as num?)?.toInt() ?? 0,
    'enabled': (row['enabled'] as num?)?.toInt() == 1,
    'title': row['title']?.toString() ?? '',
    'content': row['content']?.toString() ?? '',
  };

  /// 原生兼容镜像（prefs 键 `flutter.<family>_rules` 的值）。
  static String toLegacyJson(List<Map<String, dynamic>> rules) =>
      jsonEncode(rules);

  /// 解析旧键。**null 与空表是两件事**：
  /// null = 键不存在 / 不是合法 JSON 数组 = "这台设备从没配过规则"（可以播种默认规则）；
  /// `[]` = 用户把规则删空了（不许播种，否则删掉的默认规则每开机复活一次）。
  static List<Map<String, dynamic>>? parseLegacyJson(
    String? json,
    String family,
  ) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return null;
      return normalizeAll(decoded, family);
    } catch (_) {
      return null;
    }
  }
}
