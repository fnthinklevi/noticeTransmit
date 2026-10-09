import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本机登记的一行：一个**名称** ＋ 打开它的**目标**（T124 片B 的 `app:launch`）。
///
/// ⚠ 名称是**用户自己起的**（对面按名字对这条登记）—— 本机的清单不出门，
/// 出门的只有"请你打开 <这个名字>"。
@immutable
class FnthinkShortcut {
  const FnthinkShortcut({required this.name, required this.target});

  final String name;
  final String target;

  @override
  bool operator ==(Object other) =>
      other is FnthinkShortcut && other.name == name && other.target == target;

  @override
  int get hashCode => Object.hash(name, target);

  @override
  String toString() => 'FnthinkShortcut($name ⇒ $target)';
}

/// 存哪儿：prefs 里一段 JSON（与 `loadWebhookUrls` 同一个做法）。
///
/// 为什么不入库：这张表只有两个读者（执行器那一格与它自己的页），没有第二条查询路；
/// 为它动 DB 版本（迁移 + 备份 + 恢复三条链）是拿大炮打蚊子。
const String kFnthinkShortcutsKey = 'fnthink.shortcuts';

/// 名称上限（与契约 `reports.app:launch.maxChars` 同值：对面能带过来的名字最长这么长）。
const int kFnthinkShortcutNameCap = 32;

/// 目标校验（纯函数）：只有两种合法形态 —— `<包名>/<类名>` 或一条**带 scheme 的 URI**。
///
/// 这两种正是维护者裁定的两条合法路（那枚 App 自己公开的 deeplink，或本机登记的组件名）；
/// 别的一律拒 —— 放行一个"看着像"的串，点下去才知道系统不认，而那时指令已经执行过了。
String? validateFnthinkShortcutTarget(String target) {
  final t = target.trim();
  if (t.isEmpty) return 'empty';
  for (final rune in t.runes) {
    if (rune < 0x20 || rune == 0x7F) return 'control-char';
  }
  final slash = t.indexOf('/');
  final colon = t.indexOf(':');
  // 组件形态：`pkg/cls`（斜杠在冒号之前；斜杠不能在头）
  if (slash > 0 && (colon < 0 || slash < colon)) {
    final pkg = t.substring(0, slash);
    final cls = t.substring(slash + 1);
    if (pkg.contains('.') && cls.isNotEmpty) return null;
    return 'bad-component';
  }
  // URI 形态：scheme 必须合法（字母开头，其后字母/数字/+/-/.）
  if (colon > 0) {
    final scheme = t.substring(0, colon);
    if (RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*$').hasMatch(scheme)) return null;
    return 'bad-scheme';
  }
  return 'not-a-target';
}

/// 名称校验（纯函数）：非空、去空白后 ≤ [kFnthinkShortcutNameCap]、无控制字符。
String? validateFnthinkShortcutName(String name) {
  final n = name.trim();
  if (n.isEmpty) return 'empty';
  if (n.length > kFnthinkShortcutNameCap) return 'too-long';
  for (final rune in n.runes) {
    if (rune < 0x20 || rune == 0x7F) return 'control-char';
  }
  return null;
}

/// 读那一张表。**读不出来回空表**（不是抛）：这张表坏了不该让页面或执行链崩。
///
/// ⚠ 坏行**跳过但留下痕迹**（debugPrint）：静默吞掉一行 = 用户登记过的东西凭空消失，
/// 而他能看见的只是"少了一条"。
Future<List<FnthinkShortcut>> loadFnthinkShortcuts() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kFnthinkShortcutsKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final out = <FnthinkShortcut>[];
    var skipped = 0;
    for (final row in decoded) {
      if (row is! Map) {
        skipped++;
        continue;
      }
      final name = row['name'];
      final target = row['target'];
      if (name is! String ||
          target is! String ||
          validateFnthinkShortcutName(name) != null ||
          validateFnthinkShortcutTarget(target) != null) {
        skipped++;
        continue;
      }
      out.add(FnthinkShortcut(name: name.trim(), target: target.trim()));
    }
    if (skipped > 0) {
      debugPrint('[fnthink] 快捷入口表里有 $skipped 行读不出来（已跳过，未静默删）');
    }
    return out;
  } catch (e) {
    debugPrint('[fnthink] 快捷入口表读取失败（按空表处理）: $e');
    return const [];
  }
}

/// 写回。**写前逐行校验**：不合法的行在这里就拒（调用方拿 String 说得出是哪一处不对）。
Future<void> saveFnthinkShortcuts(List<FnthinkShortcut> rows) async {
  final prefs = await SharedPreferences.getInstance();
  final encoded = jsonEncode([
    for (final row in rows) {'name': row.name, 'target': row.target},
  ]);
  await prefs.setString(kFnthinkShortcutsKey, encoded);
}

/// 一条登记要找的名称在不在表里（执行器那一格用的读口；**精确匹配，不猜**）。
FnthinkShortcut? findFnthinkShortcut(List<FnthinkShortcut> rows, String name) {
  final wanted = name.trim();
  for (final row in rows) {
    if (row.name == wanted) return row;
  }
  return null;
}
