import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一条「规则扇出组」在历史页里的最小事实（T147②）。
///
/// 组行**不写 `notifications`**（零迁移：那表没有组列，`extra_config` 只活在别处）。
/// 原生在广播里多带 `historyGroupId` / `historyGroupKind`，Dart 侧在收下这一条时
/// 把「成员 id → 组」记进这里；历史页再把成员行折叠成一行。
class HistoryGroup {
  HistoryGroup({
    required this.id,
    required this.kind,
    required this.at,
    required this.appName,
    required this.title,
    required List<String> memberIds,
  }) : memberIds = List<String>.of(memberIds);

  /// merge: `{key}:merge:{windowEnd}`；delay: `delay:{fireAt}`。
  final String id;

  /// `merge` / `delay`（只有这两种；原生那两处是唯一作者）。
  final String kind;

  /// 组的时间：merge 是窗口结束点，delay 是到点时刻（毫秒）。
  final int at;

  final String appName;
  final String title;

  /// 这一组里的成员通知 id（有序，去重；上限见 [HistoryGroupStore.maxMembersPerGroup]）。
  final List<String> memberIds;

  bool get isMerge => kind == 'merge';
  bool get isDelay => kind == 'delay';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind,
    'at': at,
    'appName': appName,
    'title': title,
    'memberIds': memberIds,
  };

  static HistoryGroup? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}'.trim();
    final kind = '${raw['kind'] ?? ''}'.trim();
    if (id.isEmpty || (kind != 'merge' && kind != 'delay')) return null;
    final members = <String>[];
    final rawMembers = raw['memberIds'];
    if (rawMembers is List) {
      for (final m in rawMembers) {
        final s = '$m'.trim();
        if (s.isNotEmpty && !members.contains(s)) members.add(s);
      }
    }
    return HistoryGroup(
      id: id,
      kind: kind,
      at: (raw['at'] as num?)?.toInt() ?? 0,
      appName: '${raw['appName'] ?? ''}',
      title: '${raw['title'] ?? ''}',
      memberIds: members,
    );
  }
}

/// 组映射的**唯一存储**（Dart SharedPreferences；不动 DB schema）。
///
/// 为什么住在 Dart 而不是原生：组 id 由原生算，但历史页在 Dart；两边共用一份
/// prefs 文件需要新开一条方法通道，而"随广播多带两个字段"已经够把事实带过来。
/// 这里只负责存/读，不解释「一条规则」—— 那是页面的事。
class HistoryGroupStore {
  HistoryGroupStore({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  /// 只保留最近的组；更老的组行随成员行一起被保留策略裁掉后没有意义。
  static const int maxGroups = 200;

  /// 一组最多记这么多成员（merge 自身上限 50；delay 队列上限 200）。
  static const int maxMembersPerGroup = 300;

  static const String prefsKey = 'history.groups.v1';

  final Future<SharedPreferences> Function() _prefs;

  /// 收下一条成员：落进 [groupId]；同一成员若曾在别的组（延迟改点重排），从旧组移走。
  ///
  /// 失败只打印、不往上抛：组行是历史页的增强，不该让一条通知的落库/显示因它失败。
  Future<void> noteMember({
    required String groupId,
    required String kind,
    required Map<String, dynamic> record,
  }) async {
    final memberId = '${record['id'] ?? ''}'.trim();
    if (groupId.isEmpty || memberId.isEmpty) return;
    if (kind != 'merge' && kind != 'delay') return;
    try {
      final prefs = await _prefs();
      final groups = _read(prefs);
      final at =
          groupTime(groupId) ??
          (record['postTime'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;
      HistoryGroup? found;
      for (final g in groups) {
        if (g.id == groupId) {
          found = g;
          break;
        }
      }
      final target =
          found ??
          HistoryGroup(
            id: groupId,
            kind: kind,
            at: at,
            appName: '${record['appName'] ?? ''}',
            title: '${record['title'] ?? ''}',
            memberIds: const [],
          );
      if (found == null) groups.add(target);
      for (final g in groups) {
        if (g.id != groupId) g.memberIds.remove(memberId);
      }
      if (!target.memberIds.contains(memberId)) {
        target.memberIds.add(memberId);
      }
      if (target.memberIds.length > maxMembersPerGroup) {
        target.memberIds.removeRange(
          0,
          target.memberIds.length - maxMembersPerGroup,
        );
      }
      groups.sort((a, b) => b.at.compareTo(a.at));
      if (groups.length > maxGroups) {
        groups.removeRange(maxGroups, groups.length);
      }
      await prefs.setString(
        prefsKey,
        jsonEncode(groups.map((g) => g.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[history-group] 组映射写入失败（历史组行这一格暂缺）: $e');
    }
  }

  Future<List<HistoryGroup>> list() async {
    try {
      return _read(await _prefs());
    } catch (e) {
      debugPrint('[history-group] 组映射读取失败（按没有组行处理）: $e');
      return const [];
    }
  }

  /// 从组 id 里读回组的时间；认不出回 null（调用方退回落库时间，不猜）。
  static int? groupTime(String id) {
    const mergeMark = ':merge:';
    final at = id.lastIndexOf(mergeMark);
    if (at >= 0) {
      final value = int.tryParse(id.substring(at + mergeMark.length));
      if (value != null && value > 0) return value;
    }
    if (id.startsWith('delay:')) {
      final value = int.tryParse(id.substring('delay:'.length));
      if (value != null && value > 0) return value;
    }
    return null;
  }

  List<HistoryGroup> _read(SharedPreferences prefs) {
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return <HistoryGroup>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <HistoryGroup>[];
      final out = <HistoryGroup>[];
      for (final item in decoded) {
        final group = HistoryGroup.fromJson(item);
        if (group != null) out.add(group);
      }
      return out;
    } catch (e) {
      debugPrint('[history-group] 组映射不是合法 JSON（按没有组行处理）: $e');
      return <HistoryGroup>[];
    }
  }
}
