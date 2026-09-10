import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MethodChannel 方法名双端契约守卫。
///
/// 背景：`com.fnthink.notice/notification` 是单通道 + 按域分发的结构。Kotlin 侧
/// 由 5 个 ChannelHandler 各自 `when (call.method)` 消费，Dart 侧散落在
/// pages/services 中以 `invokeMethod('xxx')` 直接调用。方法名是**字符串契约**，
/// 编译器完全不校验——重命名一端、删掉一个分支、或新增 Dart 调用而忘记加原生
/// 分支，都不会有任何编译期或测试期报错。
///
/// 本测试把这条隐式契约变成显式断言，锁两件事：
///
/// 1. **方向 1（致命）= 0**：Dart 调用的每个方法名，Kotlin 必须已定义。
///    违反后果是运行时 `MissingPluginException`——通常只在某个特定页面/按钮
///    被点到时才炸，常规回归测试（走 mock 通道）根本发现不了。
///    这是本文件存在的首要原因，不允许为通过而放宽。
///
/// 2. **总数 == 79**：防止「悄悄删掉一个原生分支」或「新增分支忘记登记」。
///    数字变化本身没风险，但**未经确认**的数字变化应当让人停下来看一眼：
///    改动这个期望值时必须同时确认 Dart 侧是否也该同步。
///
/// 方向 2（Kotlin 定义但 Dart 未调用）**不做断言**：其中一批是原生自用
/// （如 `openAppDetailsSettings` 被 MainActivity 内部 7 处直接调用），
/// 属正常设计，不必也不该强制 Dart 调用。
void main() {
  /// 仓库根目录。`flutter test` 的 cwd 是项目根，但为兼容从子目录运行做了探测。
  final root = _projectRoot();

  /// 原生 MethodChannel 方法名 → 定义它的 handler 文件。
  final native = _nativeChannelMethods(root);

  /// Dart 侧实际会发出的方法名集合。
  final dart = _dartChannelMethods(root);

  group('MethodChannel 方法名双端契约', () {
    test('方向1：Dart 调用的方法 Kotlin 必须已定义（MissingPluginException 守卫）', () {
      final undefined = dart.difference(native.keys.toSet()).toList()..sort();
      expect(
        undefined,
        isEmpty,
        reason:
            '以下方法名被 Dart 通过 MethodChannel 调用，但没有任何 Kotlin ChannelHandler '
            '定义它们。运行时将抛 MissingPluginException：\n'
            '${undefined.map((m) => '  - $m').join('\n')}\n'
            '修复方式二选一：在对应 handler 补 when 分支，或删除 Dart 侧调用。',
      );
    });

    test('原生方法总数 == 79（防止分支被静默删除/新增未登记）', () {
      expect(
        native.length,
        79,
        reason:
            '原生 ChannelHandler 方法数发生变化。\n'
            '当前分布：${_distribution(native).entries.map((e) => '${e.key}=${e.value}').join(', ')}\n'
            '若为有意改动，请同时更新本期望值；若为误删，请恢复分支。',
      );
    });

    test('每个 handler 的方法数固定（按域分布守卫）', () {
      final dist = _distribution(native);
      expect(dist, {
        'ConfigChannelHandler': 23,
        'PermissionChannelHandler': 23,
        'DeviceChannelHandler': 13,
        'FileChannelHandler': 11,
        'StatsChannelHandler': 9,
      });
    });

    test('方法名全局唯一（不允许两个 handler 抢同一方法名）', () {
      final dup = native.entries.where((e) => e.value.length > 1).toList();
      expect(
        dup,
        isEmpty,
        reason:
            '同一方法名被多个 handler 定义：'
            '${dup.map((e) => '${e.key} -> ${e.value}').join('; ')}。'
            'ChannelDispatcher 取首个消费者，后面的分支永远不会执行（死分支）。',
      );
    });
  });
}

/// 探测仓库根目录。
String _projectRoot() {
  final candidates = ['../..', '..', '.'];
  for (final rel in candidates) {
    if (File(
      '$rel/android/app/src/main/kotlin/com/fnthink/notice/channels/'
      'ChannelDispatcher.kt',
    ).existsSync()) {
      return rel;
    }
  }
  if (File('CHANGELOG.md').existsSync()) return '.';
  throw StateError('未找到仓库根目录（channels/*.kt 不存在）');
}

/// 解析 Kotlin ChannelHandler 中的 `"methodName" ->` 分支。
///
/// 返回 **方法名 → 定义它的 handler 列表**（列表而非单值）：同一方法名被两个
/// handler 定义时必须能同时看到两者，否则「重名死分支」会被 Map 覆盖而静默消失，
/// 唯一性断言将永远通过（典型「测试通过 ≠ 有保护」陷阱）。
///
/// 只认 when 分支形态（字符串字面量紧跟箭头），避免把 `call.argument<...>("key")`
/// 这类参数名误判成方法名。
Map<String, List<String>> _nativeChannelMethods(String root) {
  final dir = Directory(
    '$root/android/app/src/main/kotlin/com/fnthink/notice/channels',
  );
  final handlers = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.kt'))
      .where((f) => !f.path.endsWith('ChannelDispatcher.kt'))
      .toList();

  if (handlers.isEmpty) {
    throw StateError('未在 ${dir.path} 找到任何 ChannelHandler');
  }

  final branchPattern = RegExp(r'"([A-Za-z0-9_]+)"\s*->');
  final result = <String, List<String>>{};
  for (final f in handlers) {
    final name = f.uri.pathSegments.last.replaceAll('.kt', '');
    final src = f.readAsStringSync();
    for (final m in branchPattern.allMatches(src)) {
      result.putIfAbsent(m.group(1)!, () => []).add(name);
    }
  }
  return result;
}

/// 解析 Dart 侧实际发出的方法名。
///
/// 两种来源：
/// 1. `invokeMethod` 之后的第一个字符串字面量。用「窗口内首个字面量」而非
///    「同行正则」，是为了同时覆盖 `invokeMethod('m')`、`invokeMethod('m', {..})`、
///    `invokeMethod<T>('m')`、`invokeMethod(\n  'm',\n)` 四种写法——项目中四种都在用。
/// 2. 项目内的间接转发点 `_requestPermission('m')`（permission_service.dart 的
///    统一权限请求入口，方法名以参数传入，不直接出现在 invokeMethod 之后）。
Set<String> _dartChannelMethods(String root) {
  final files = Directory('$root/lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  final window = RegExp(r'''['"]([A-Za-z0-9_]+)['"]''');
  final indirect = RegExp(r"_requestPermission\(\s*'([A-Za-z0-9_]+)'");
  final methods = <String>{};

  for (final f in files) {
    final src = f.readAsStringSync();
    for (final call in RegExp(r'invokeMethod\b').allMatches(src)) {
      // 240 字符足够覆盖 invokeMethod<T>(\n  'name',\n) 的最长现实形态；
      // 不足以跨到下一次 invokeMethod（方法名之间通常隔着参数与日志）。
      final end = call.end + 240;
      final slice = src.substring(
        call.end,
        end > src.length ? src.length : end,
      );
      final lit = window.firstMatch(slice);
      if (lit != null) methods.add(lit.group(1)!);
    }
    for (final m in indirect.allMatches(src)) {
      methods.add(m.group(1)!);
    }
  }
  return methods;
}

Map<String, int> _distribution(Map<String, List<String>> native) {
  final dist = <String, int>{};
  for (final handlers in native.values) {
    for (final handler in handlers) {
      dist[handler] = (dist[handler] ?? 0) + 1;
    }
  }
  return dist;
}
