import '../support/source_guards.dart';
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
/// 2. **总数 == 93**：防止「悄悄删掉一个原生分支」或「新增分支忘记登记」。
///    （6e 加了两个非侵入探测 `probeAppChannelToken` / `verifySmtp`：91 → 93。）
///    数字变化本身没风险，但**未经确认**的数字变化应当让人停下来看一眼：
///    改动这个期望值时必须同时确认 Dart 侧是否也该同步。
///
/// 方向 2（Kotlin 定义但 Dart 未调用）**不做断言**：其中一批是原生自用
/// （如 `openAppDetailsSettings` 被 MainActivity 内部 7 处直接调用），
/// 属正常设计，不必也不该强制 Dart 调用。
void main() {
  /// 仓库根目录。`flutter test` 的 cwd 是项目根，但为兼容从子目录运行做了探测。
  final root = projectRoot();

  /// ⚠ 两侧解析包在 try 里：目录改名时 `_nativeChannelMethods` 的 StateError 或
  ///   `listSync` 的 FileSystemException 若抛在 `main()` 顶层 = 整个文件加载失败，
  ///   CI 表现为"这个文件没有用例"而不是红（base.md（75））。改成红交给下面第一条用例。
  Object? parseError;
  Map<String, List<String>> native = const {};
  Set<String> dart = const {};
  try {
    /// 原生 MethodChannel 方法名 → 定义它的 handler 文件。
    native = _nativeChannelMethods(root);

    /// Dart 侧实际会发出的方法名集合。
    dart = _dartChannelMethods(root);
  } catch (e) {
    parseError = e;
  }

  group('MethodChannel 方法名双端契约', () {
    test('两侧源码都解析成功（口径漂移要红，不许静默变空）', () {
      final err = parseError;
      if (err != null) throw err;
      expect(native, isNotEmpty, reason: '原生侧一枚方法名都没解析到');
      expect(dart, isNotEmpty, reason: 'Dart 侧一枚方法名都没解析到');
    });

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

    test('原生方法总数 == 93（防止分支被静默删除/新增未登记）', () {
      expect(
        native.length,
        93,
        reason:
            '原生 ChannelHandler 方法数发生变化。\n'
            '当前分布：${_distribution(native).entries.map((e) => '${e.key}=${e.value}').join(', ')}\n'
            '若为有意改动，请同时更新本期望值；若为误删，请恢复分支。',
      );
    });

    test('每个 handler 的方法数固定（按域分布守卫）', () {
      final dist = _distribution(native);
      expect(dist, {
        'ConfigChannelHandler': 35,
        'PermissionChannelHandler': 23,
        'DeviceChannelHandler': 14,
        'FileChannelHandler': 12,
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

    test('Dart 侧抽取有效（正面锚点：拦住"一个都没抓到"的假绿）', () {
      // 方向 1 判的是 dart ⊆ native —— dart 集合若因正则退化而变空，那条断言就**永远成立**，
      // 整个文件只剩"原生方法数"在守，而它守不到"Dart 调用了一个不存在的方法"。
      expect(
        dart.length,
        greaterThanOrEqualTo(70),
        reason:
            'Dart 侧只解析出 ${dart.length} 个方法名，远低于原生 93 个里的实际调用面：'
            '要么 _dartChannelMethods 的正则退化了，要么调用写法又多了第五种',
      );
      // 三种书写形态各钉一枚代表：少一种 = 对应的解析分支已经不再命中。
      const probes = {
        'testAppChannel': 'invokeMethod(\'m\') 同行写法',
        'isIgnoringBatteryOptimizations':
            'invokeMethod<bool>(\\n  \'m\', 带泛型跨行写法',
        'requestBatteryOptimization': '_requestPermission(\'m\') 间接转发写法',
      };
      for (final probe in probes.entries) {
        expect(
          dart,
          contains(probe.key),
          reason: '缺「${probe.value}」这一形态的样本 ⇒ 该形态以后新增方法会漏出守卫',
        );
      }
    });

    test('三个非侵入探测方法都有 Dart 侧调用点（6e 的动态方法名补钉）', () {
      // 探测走 `ChannelProbeService`，方法名来自变量 ⇒ 上面那套字面量解析看不见它。
      // 方向 2（原生有、Dart 不调）本文件整体不做断言，所以这里为这一族单独钉一次：
      // 原生多出一扇没人走的门 = 探测白写，而通道状态列会一直说"未知"。
      final dartFiles = Directory('$root/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      for (final name in const [
        'probeChannelHealth',
        'probeAppChannelToken',
        'verifySmtp',
      ]) {
        final hits = dartFiles
            .where(
              (f) => stripComments(f.readAsStringSync()).contains("'$name'"),
            )
            .map((f) => f.uri.pathSegments.last)
            .toList();
        expect(
          hits,
          isNotEmpty,
          reason:
              '$name 在 lib 里没有任何字面量调用点 ⇒ 原生那扇门白开了：'
              '这一族的通道状态永远刷不出结论，而测试全绿',
        );
      }
    });
  });
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
    final src = stripComments(f.readAsStringSync());
    for (final m in branchPattern.allMatches(src)) {
      result.putIfAbsent(m.group(1)!, () => []).add(name);
    }
  }
  return result;
}

/// 解析 Dart 侧实际发出的方法名。
///
/// ⚠ 两侧源码都先 `stripComments`：本守卫靠「invokeMethod 之后第一个字符串字面量」
/// 取名字，注释里出现 `invokeMethod` 这个词（写文档时很常见）就会把注释正文里的
/// 引号片段当成方法名 —— T08-C 就是这么红了一次（`'switch'` 被当成方法）。
/// 剥注释是引号感知的，所以真实字符串字面量不受影响。
///
/// 两种来源：
/// 1. `invokeMethod` 之后的第一个字符串字面量。用「窗口内首个字面量」而非
///    「同行正则」，是为了同时覆盖 `invokeMethod('m')`、`invokeMethod('m', {..})`、
///    `invokeMethod<T>('m')`、`invokeMethod(\n  'm',\n)` 四种写法——项目中四种都在用。
/// 2. 项目内的间接转发点 `_requestPermission('m')`（permission_service.dart 的
///    统一权限请求入口，方法名以参数传入，不直接出现在 invokeMethod 之后）。
///
/// 第三种写法是**方法名来自变量**（`ChannelProbeService` 按 family 选探测方法）：
/// 这种调用点必须跳过 —— 窗口里的首个字面量会是**后面的**表达式
/// （`r['reachable']` ⇒ 曾被当成方法名 `'reachable'` 而假红）。跳过不等于漏守：
/// 变量取值的集合由下面那条「三个探测方法都得在 lib 里出现为字面量」钉住。
Set<String> _dartChannelMethods(String root) {
  final files = Directory('$root/lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  final window = RegExp(r'''['"]([A-Za-z0-9_]+)['"]''');
  final indirect = RegExp(r"_requestPermission\(\s*'([A-Za-z0-9_]+)'");
  final methods = <String>{};

  for (final f in files) {
    final src = stripComments(f.readAsStringSync());
    for (final call in RegExp(r'invokeMethod\b').allMatches(src)) {
      // 240 字符足够覆盖 invokeMethod<T>(\n  'name',\n) 的最长现实形态；
      // 不足以跨到下一次 invokeMethod（方法名之间通常隔着参数与日志）。
      final end = call.end + 240;
      final slice = src.substring(
        call.end,
        end > src.length ? src.length : end,
      );
      final lit = window.firstMatch(slice);
      if (lit == null) continue;
      // 字面量之前除泛型与标点之外还有标识符 ⇒ 方法名不是字面量（动态调用点）
      final before = slice
          .substring(0, lit.start)
          .replaceAll(RegExp(r'<[^<>]*>'), '');
      if (RegExp(r'[A-Za-z_$][\w$]*').hasMatch(before)) continue;
      methods.add(lit.group(1)!);
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
