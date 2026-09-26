import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T21：并存期的**影子求值**——只比对、只记账，不发送、不改行为。
///
/// 两条规则集现在同时存在：`engine_rules` 表（T20 起的可信来源）与 prefs 镜像
/// （原生 `BatteryMonitor` 实际读的那份）。并存期要回答的问题只有一个：
/// **原生据以判定的规则，和库里那份，是同一份吗？**
///
/// 为什么不另写一份"影子引擎"去比结论：`NotificationEngine` 是确定性函数，
/// 同一份读数下结论只取决于规则集 ⇒ **输入等价即结论等价**。为了做影子比对而把
/// 判据再抄一份，正是 T19 花掉一整批清掉的那类东西（两处抄本迟早分叉，
/// 表现是"某类告警永远不来"）。所以这里比的是输入，并且下面这条注释就是它的证明：
/// `compareEngineRuleSets` 返回空 ⇔ 两份输入逐条同序同值 ⇔ 任何读数下结论相同。
///
/// ⚠ 记账不能省成"顺手修掉"：不一致多半会被 `_repairMirror` 以 DB 为准修好，
/// 但"曾经不一致"这件事本身是 T22（覆盖升级自检）唯一的证据来源 —— 升级时导入
/// 少了一条、阈值换了数，修好之后界面上看不出来，只有记录还在说话。
class EngineRuleDiff {
  EngineRuleDiff({
    required this.family,
    required this.kind,
    this.index,
    this.detail = '',
    required this.at,
  });

  /// `battery` / `temperature`
  final String family;

  /// mirrorAbsent / mirrorUnparsable / missingInMirror / extraInMirror /
  /// id / type / value / enabled / title / content
  final String kind;

  /// 第几条规则（0 起）；整集级别的差异为 null。
  final int? index;
  final String detail;
  final int at;

  Map<String, Object?> toJson() => {
    'family': family,
    'kind': kind,
    'index': index,
    'detail': detail,
    'at': at,
  };

  static EngineRuleDiff? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final family = raw['family']?.toString();
    final kind = raw['kind']?.toString();
    if (family == null || kind == null) return null;
    return EngineRuleDiff(
      family: family,
      kind: kind,
      index: (raw['index'] as num?)?.toInt(),
      detail: raw['detail']?.toString() ?? '',
      at: (raw['at'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() =>
      '$family[$kind]${index == null ? '' : ' #$index'} $detail';
}

/// 逐条比对（顺序敏感：库里第 i 条必须就是镜像第 i 条，顺序变了引擎判定优先级就变了）。
///
/// [mirrorRaw] 是 prefs 里的原始串，[mirror] 是它解析归一后的结果 —— 两个都要，
/// 才能把"键不存在 / 从没写过"和"写了但读不出规则"分开（这两种的处置完全不同）。
List<EngineRuleDiff> compareEngineRuleSets({
  required String family,
  required List<Map<String, dynamic>> db,
  required String? mirrorRaw,
  List<Map<String, dynamic>>? mirror,
  required int at,
}) {
  if (mirrorRaw == null || mirrorRaw.isEmpty) {
    // 镜像从没写过：原生那一侧等于"没有任何规则"，库里却有 ⇒ 告警全哑，必须记。
    if (db.isEmpty) return const [];
    return [
      EngineRuleDiff(
        family: family,
        kind: 'mirrorAbsent',
        detail: '库里有 ${db.length} 条而原生镜像不存在',
        at: at,
      ),
    ];
  }
  if (mirror == null) {
    return [
      EngineRuleDiff(
        family: family,
        kind: 'mirrorUnparsable',
        detail: '镜像存在但不是可读的规则数组',
        at: at,
      ),
    ];
  }
  final diffs = <EngineRuleDiff>[];
  final n = db.length > mirror.length ? db.length : mirror.length;
  for (var i = 0; i < n; i++) {
    final a = i < db.length ? db[i] : null;
    final b = i < mirror.length ? mirror[i] : null;
    if (a == null) {
      diffs.add(
        EngineRuleDiff(
          family: family,
          kind: 'extraInMirror',
          index: i,
          detail: '镜像比库多一条：${b!['id']}',
          at: at,
        ),
      );
      continue;
    }
    if (b == null) {
      diffs.add(
        EngineRuleDiff(
          family: family,
          kind: 'missingInMirror',
          index: i,
          detail: '镜像少一条：${a['id']}',
          at: at,
        ),
      );
      continue;
    }
    for (final field in const [
      'id',
      'type',
      'value',
      'enabled',
      'title',
      'content',
    ]) {
      final av = a[field];
      final bv = b[field];
      if (av == bv) continue;
      diffs.add(
        EngineRuleDiff(
          family: family,
          kind: field,
          index: i,
          detail: '库=$av 镜像=$bv',
          at: at,
        ),
      );
    }
  }
  return diffs;
}

/// 有界差异环（prefs）。上限 20：够 T22 一轮自检看清楚，又不至于把一份
/// 长期不一致的记录堆成噪声。
class EngineRuleDiffLog {
  static const prefsKey = 'engine_rule_diffs';
  static const maxEntries = 20;

  /// 记录并返回本轮之后的总数（调用方不改自己的行为，只为了让测试能钉住"确实记了"）。
  Future<int> record(List<EngineRuleDiff> diffs) async {
    if (diffs.isEmpty) return (await read()).length;
    final prefs = await SharedPreferences.getInstance();
    final kept = await _read(prefs);
    kept.addAll(diffs);
    final trimmed = kept.length <= maxEntries
        ? kept
        : kept.sublist(kept.length - maxEntries);
    await prefs.setString(
      prefsKey,
      jsonEncode(trimmed.map((d) => d.toJson()).toList()),
    );
    debugPrint(
      'EngineRuleDiffLog: 记 ${diffs.length} 条影子差异（累计 ${trimmed.length}）',
    );
    return trimmed.length;
  }

  Future<List<EngineRuleDiff>> read() async {
    final prefs = await SharedPreferences.getInstance();
    return _read(prefs);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }

  Future<List<EngineRuleDiff>> _read(SharedPreferences prefs) async {
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return <EngineRuleDiff>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <EngineRuleDiff>[];
      return decoded
          .map(EngineRuleDiff.fromJson)
          .whereType<EngineRuleDiff>()
          .toList();
    } catch (_) {
      // 环本身坏了：不抛（它只是诊断记录），但也不能装作是空的。
      debugPrint('EngineRuleDiffLog: 差异记录不可解析，已按空处理');
      return <EngineRuleDiff>[];
    }
  }
}
