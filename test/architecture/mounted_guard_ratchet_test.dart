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
/// 2026-09-28（T65）41 → 2，两件事分开算：
/// - 判据补认「同行守卫」（`if (mounted) setState(...)`）—— 它挡的是同一件事，
///   少认一种就会把 10 处正确写法计成缺陷，并逼着带回调/带返回值的站点也改成 `return`
///   形状（那才是真把行为改坏）。这一条由反证 4/5 钉住，不是为了让数字好看。
/// - 真修的 19 处：`main_page_actions.dart`（开页/回调两条路径混着，其中换语言那处
///   setState 之后还要同步原生标签与父页回调 ⇒ 用同行守卫，不能 return）、
///   `main.dart` 主题与隐私两处、`app_filter_page` / `backup_restore_page` /
///   `rule_list_page` ×2 / `rule_tester_page`（这几处 await 之后还要 `_saveRules()` /
///   `_recompute()`，同样要活的 State ⇒ 前置 return）。
/// ⚠ 剩下的 2 处**是判据的误报，不是缺陷**：`sms_monitor_settings_page.dart` 的
///   `_toggleSmsMonitor` / `_toggleCodeMonitor` 里 `setState` 在 `await` **之前**
///   （乐观切换再落盘），回溯窗口捞到的是上一个函数尾巴上的 await。
///   留 2 而不是把判据改复杂：这条守卫的价值在于"新写的裸 setState 会被拦"，
///   而为两个假阳性去推断"await 属于哪个函数"会引入新的近似错误。
const int _ratchet = 2;

/// 判据本体（独立成函数是为了能被合成样本反证，见第一个 test）。
///
/// 两处近似：① 回溯 6 行找 `await `（所以"await 属于上一个函数尾巴"仍会误报）；
/// ② 同行守卫算已守卫 —— `if (mounted) setState(...)` 与前置 `if (!mounted) return;`
///   挡的是同一件事（dispose 之后调 setState），少认一种就会逼人全写成 `return` 形状，
///   而有些站点后面还有必须执行的动作（回调、返回值），`return` 反而改坏行为。
List<int> unguardedSetStateLines(String src) {
  final lines = src.split(RegExp(r'\r?\n'));
  final out = <int>[];
  for (var i = 0; i < lines.length; i++) {
    final at = lines[i].indexOf('setState(');
    if (at < 0) continue;
    if (lines[i].substring(0, at).contains('mounted')) continue; // 同行已守卫
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
      // 反证 4：同行守卫必须放过 —— 它挡的是同一件事（dispose 后调 setState）。
      // 判据少认这一种，就会被"存量数字"逼着把带回调/带返回值的站点也改成 return 形状，
      // 那才是真把行为改坏。
      const sameLine = '''
Future<void> _onChange(bool v) async {
  await service.save(v);
  if (mounted) setState(() {});
  widget.onChanged?.call(v);
}
''';
      expect(
        unguardedSetStateLines(sameLine),
        isEmpty,
        reason: '同行 if (mounted) 守卫没被认出来：判据会把正确写法计成缺陷',
      );
      // 反证 5：但"同一行里 mounted 出现在 setState **之后**"不算守卫（顺序反了等于没判）
      expect(
        unguardedSetStateLines(
          'Future<void> f() async {\n  await s.go();\n  setState(() {}, mounted);\n}\n',
        ),
        hasLength(1),
        reason: 'mounted 出现在 setState 之后也被放过 ⇒ 判据太松',
      );
    });

    test('扫描确实覆盖到 lib/（提取失效即假绿）', () {
      expect(
        dartFiles.length,
        greaterThan(50),
        reason: '只扫到 ${dartFiles.length} 个文件 ⇒ 目录遍历失效，本文件已失去保护作用',
      );
    });

    test('main_page 那一族（含三个 part）的病灶必须为 0（㊽ 修掉的正是这里）', () {
      // 只匹配 main_page.dart 是不够的：R3 把装配/弹窗/回调拆成 part 之后，
      // 病灶搬进 main_page_actions.dart 也不会被这条点名（它仍然被 catch 吞掉，
      // 仍然会跳过后半段启动流程）。同 library 的 part 必须一起算。
      final diseased = sites.keys.where(
        (k) => RegExp(r'lib/pages/main_page[^/]*\.dart$').hasMatch(k),
      );
      expect(
        diseased,
        isEmpty,
        reason:
            '主页面那一族的 setState 又变成裸调用了：一旦页面在 await 期间被销毁，'
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
