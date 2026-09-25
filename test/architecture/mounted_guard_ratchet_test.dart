import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 异步回调里 `setState` 的 `mounted` 守卫棘轮（**只降不升**）。
///
/// 为什么立这条（㊽）：v1.5.75 的发版闸门**全绿**，但日志里冒出一行
/// `setState() called after dispose(): _MainPageState` —— 出处是
/// `main_page.dart` 装配链里 4 个 `await` 之后的裸 `setState`。它被下面的
/// `catch` 吞成一行 print，**连带把 catch 之后的 `_checkFirstLaunch()` 与延迟启动服务整段跳掉**：
/// 页面没崩、测试没红，但启动流程少跑了一半。这类缺陷只有"日志被读"时才现形，
/// 所以给它一道机器守卫，而不是等下一次翻日志。
///
/// 判据是保守近似（回溯 6 行找 `await `、同窗口内没有 `mounted` 就算一处），
/// 因此**存量计数里含误报**（例如 await 属于上一个函数的尾巴）。
/// 本文件锁的是「不要再新增」，不是「已经干净」；修掉存量请把 `_ratchet` 一起调小。
/// 2026-09-25（T15）48 → 41：删掉 main_page 为 BatteryPage 包的那 6 个
/// "调服务 + 父页 setState"包装（路由里的子页收不到父页 rebuild，那些 setState
/// 本来就没有效果）+ 温度入口改由骨架页 push。
const int _ratchet = 41;

/// 判据本体（独立成函数是为了能被合成样本反证，见第一个 test）。
List<int> unguardedSetStateLines(String src) {
  final lines = src.split(RegExp(r'\r?\n'));
  final out = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].contains('setState(')) continue;
    final back = lines.sublist(i - (i < 6 ? i : 6), i).join('\n');
    if (back.contains('await ') && !back.contains('mounted')) out.add(i + 1);
  }
  return out;
}

void main() {
  final root = projectRoot();
  final libDir = Directory('$root/lib');
  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
  final sites = <String, List<int>>{};
  for (final f in dartFiles) {
    // ⚠ 必须先剥注释：本仓库的注释里会写 `setState()` 这种字面量（第一次自测就是被
    //   自己的注释骗出的假站点）。共用工具是引号感知的，见 test/support/source_guards.dart。
    final hits = unguardedSetStateLines(stripComments(f.readAsStringSync()));
    if (hits.isNotEmpty) {
      sites[f.path.replaceAll(r'\', '/').substring(root.length + 1)] = hits;
    }
  }
  final total = sites.values.fold<int>(0, (a, b) => a + b.length);

  group('await 之后的 setState 必须有 mounted 守卫', () {
    test('判据本身能判红也能判绿（否则守卫是摆设）', () {
      // 反证 1：真实的缺陷形状必须被抓住
      const bad = '''
Future<void> _onToggle(bool v) async {
  await service.save(v);
  setState(() {});
}
''';
      expect(
        unguardedSetStateLines(bad),
        hasLength(1),
        reason: '这个形状就是 main_page.dart 冒出来的那种，判不出来说明扫描失效',
      );
      // 反证 2：加了守卫的必须放过（否则棘轮值会被误报淹没）
      const good = '''
Future<void> _onToggle(bool v) async {
  await service.save(v);
  if (!mounted) return;
  setState(() {});
}
''';
      expect(unguardedSetStateLines(good), isEmpty);
      // 反证 3：没有 await 的同步 setState 与本缺陷无关
      expect(
        unguardedSetStateLines('void f() {\n  setState(() {});\n}\n'),
        isEmpty,
      );
    });

    test('扫描确实覆盖到 lib/（提取失效即假绿）', () {
      expect(
        dartFiles.length,
        greaterThan(50),
        reason: '只扫到 ${dartFiles.length} 个文件 ⇒ 目录遍历失效，本文件已失去保护作用',
      );
    });

    test('main_page.dart 的病灶必须为 0（㊽ 修掉的正是这里）', () {
      expect(
        sites.keys.where((k) => k.endsWith('pages/main_page.dart')),
        isEmpty,
        reason:
            '主页面装配链的 setState 又变成裸调用了：一旦页面在 await 期间被销毁，'
            '异常会被 catch 吞掉并跳过后半段启动流程（首启引导 / 延迟启动前台服务）。',
      );
    });

    test('全仓站点数 <= 棘轮值 $_ratchet', () {
      final dist = sites.entries
          .map((e) => '  ${e.value.length}  ${e.key}  行 ${e.value.join(",")}')
          .join('\n');
      expect(
        total,
        lessThanOrEqualTo(_ratchet),
        reason:
            '新增了「await 之后没有 mounted 守卫」的 setState（当前 $total）。请写成 '
            '`if (!mounted) return;` 之后再 setState；修掉存量请顺手把 _ratchet 调小。\n'
            '当前分布：\n$dist',
      );
    });
  });
}
