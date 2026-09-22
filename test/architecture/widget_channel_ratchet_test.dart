import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// widget 层裸 `invokeMethod` 棘轮守卫（**只降不升**）。
///
/// 背景：页面直接调通道，会把「原生方法名 + 参数形状 + 返回类型归一化」摊进 UI。
/// 同类调用一散到多处就变成修一处漏一处——本项目真实发生过：
/// `getInstalledApps` 的返回是 `List<dynamic>`，动态泛型 `map` 后赋给
/// `List<Map<String, dynamic>>` 会隐式 downcast 抛异常，表现为**应用列表恒为空**；
/// 这个坑在三个页面的复制里只有两处带注释绕开。v1.62 抽出
/// `InstalledAppsService` 后收敛为一份（见 lib/services/installed_apps_service.dart）。
///
/// 分层方向是 页面 → service → 通道，所以这里锁一个上限而不是精确值：
/// 迁移存量调用时数字只会变小；**变大**说明又新增了页面直连原生，
/// 应改为 service 方法（确有理由才允许下调本常量）。
///
/// 基准：v1.62 抽出 `InstalledAppsService` 前为 33，抽出后 25（棘轮值）。
const int _ratchet = 25;

void main() {
  final root = projectRoot();
  final sites = _widgetInvokeMethodSites(root);
  final total = sites.values.fold<int>(0, (a, b) => a + b);

  group('widget 层通道调用分层', () {
    test('统计非空（提取本身失效就是假绿）', () {
      expect(sites, isNotEmpty, reason: '未统计到任何站点，说明遍历/正则失效，本文件已失去保护作用');
    });

    test('裸 invokeMethod 站点数 <= 棘轮值 $_ratchet', () {
      expect(
        total,
        lessThanOrEqualTo(_ratchet),
        reason:
            'widget 层直连原生的调用增加了（当前 $total）。'
            '请把新调用写进对应 service 再由页面调用；'
            '完成迁移请顺手把 _ratchet 调小。\n当前分布：\n'
            '${sites.entries.map((e) => '  ${e.value}  ${e.key}').join('\n')}',
      );
    });

    test('应用清单原生方法名只出现在 InstalledAppsService', () {
      // 这三个方法名一旦回到页面里，就意味着应用列表逻辑又被复制了一份
      const guarded = ['getInstalledApps', 'getCachedInstalledApps'];
      const allowed = 'lib/services/installed_apps_service.dart';
      for (final m in guarded) {
        final hits = _libFilesContaining(root, m);
        expect(
          hits,
          [allowed],
          reason:
              '$m 的调用点应只有一处（$allowed）。出现在 $hits 说明应用清单'
              '逻辑又被复制进别的文件——归一化坑（List<dynamic> downcast）'
              '会随复制丢失，表现为应用列表恒为空。',
        );
      }
    });
  });
}

/// 统计 lib/pages 与 lib/widgets 下的 `invokeMethod` 出现次数（**注释已剥离**）。
Map<String, int> _widgetInvokeMethodSites(String root) {
  final result = <String, int>{};
  for (final dir in const ['lib/pages', 'lib/widgets']) {
    final d = Directory('$root/$dir');
    if (!d.existsSync()) throw StateError('目录不存在：${d.path}');
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = stripComments(f.readAsStringSync());
      final n = RegExp(r'\binvokeMethod\b').allMatches(src).length;
      if (n > 0) result[_relToLib(root, f.path)] = n;
    }
  }
  return result;
}

/// 返回 lib 下（剥注释后）包含 [needle] 的文件相对路径。
List<String> _libFilesContaining(String root, String needle) {
  final hits = <String>[];
  for (final f in Directory(
    '$root/lib',
  ).listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    if (stripComments(f.readAsStringSync()).contains(needle)) {
      hits.add(_relToLib(root, f.path));
    }
  }
  return hits..sort();
}

String _relToLib(String root, String path) {
  final normalized = path.replaceAll(Platform.pathSeparator, '/');
  final idx = normalized.lastIndexOf('/lib/');
  return idx >= 0 ? normalized.substring(idx + 1) : normalized;
}
