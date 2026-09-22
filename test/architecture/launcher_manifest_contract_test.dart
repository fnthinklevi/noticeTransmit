import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 桌面启动入口契约（v1.62，方案 D）。
///
/// 背景：本应用可启动组件刻意只放在 `<activity-alias>` 上（17 图标 × 2 语言 = 34 个
/// alias，同一时刻仅启用一个）。而 `flutter_tools` 发现启动入口时**只扫 `<activity>`**
/// （`application_package.dart`: `findAllElements('activity')`），不认 alias——
/// 于是 `flutter test integration_test/…` 报「package identifier or launch activity not found」。
///
/// 处置：`src/main` 给 `.MainActivity` 加 MAIN/LAUNCHER 供工具发现；`src/release` 与
/// `src/profile` 用 `tools:node="removeAll"` 移除它，`src/debug` 禁用默认 alias——
/// 保证**任何变体的可启动组件恒为 1 个**，线上启动路径与桌面图标行为零变化。
///
/// 本守卫钉住这套 overlay 结构。任何一处被"顺手清理"都会退化成
/// ①集成测试再次跑不起来，或 ②release 出现双图标 / 启动入口被改（用户可见）。
/// 合并产物的实测口径见 `tools/check_launcher_manifest.py`。
void main() {
  final root = projectRoot();

  String manifest(String variant) => stripXmlComments(
    File(
      '$root/android/app/src/$variant/AndroidManifest.xml',
    ).readAsStringSync(),
  );

  final mainManifest = manifest('main');
  final debugManifest = manifest('debug');
  final releaseManifest = manifest('release');
  final profileManifest = manifest('profile');

  /// 源清单里组件写成多行属性，`<activity` 之后是换行而非空格；
  /// 又必须与 `<activity-alias` 区分，故用 `[\s>]` 限定后随字符。
  List<String> activityBlocks(String src) => RegExp(
    r'<activity[\s>][\s\S]*?</activity>',
  ).allMatches(src).map((m) => m.group(0)!).toList();

  String blockOf(String src, String name) {
    for (final b in activityBlocks(src)) {
      if (b.contains('android:name="$name"')) return b;
    }
    return '';
  }

  group('桌面启动入口 – main 清单', () {
    test('.MainActivity 带 MAIN + LAUNCHER（flutter_tools 只认 activity）', () {
      final block = blockOf(mainManifest, '.MainActivity');
      expect(block, isNotEmpty, reason: '未定位到 .MainActivity 的 activity 块');
      expect(
        block,
        contains('android.intent.action.MAIN'),
        reason: '缺 MAIN：集成测试发现不了启动 activity',
      );
      expect(
        block,
        contains('android.intent.category.LAUNCHER'),
        reason:
            '缺 LAUNCHER 时 flutter test integration_test 报 launch activity not found',
      );
    });

    test('带 LAUNCHER 的 activity 恰好 1 个（防 debug 双入口）', () {
      final n = activityBlocks(
        mainManifest,
      ).where((b) => b.contains('android.intent.category.LAUNCHER')).length;
      expect(n, 1, reason: 'main 清单里带 LAUNCHER 的 activity 必须恰好 1 个');
    });

    test('34 个 alias 与默认 alias 在场（图标切换体系未被误删）', () {
      final aliases = RegExp(
        r'<activity-alias[\s>]',
      ).allMatches(mainManifest).length;
      expect(aliases, 34, reason: '17 图标 × 2 语言 = 34 个 alias');
      expect(
        mainManifest,
        contains('android:name=".LauncherDefaultZh"'),
        reason: '默认 alias 缺失：debug 覆盖清单的 enabled=false 将指向不存在的组件',
      );
    });
  });

  group('release / profile 必须移除 activity 级 LAUNCHER', () {
    for (final entry in {
      'release': releaseManifest,
      'profile': profileManifest,
    }.entries) {
      test('${entry.key} 覆盖清单结构完整', () {
        final src = entry.value;
        expect(
          src,
          contains('xmlns:tools='),
          reason: '${entry.key} 未声明 tools 命名空间 → tools: 属性被静默忽略，移除根本不生效',
        );
        expect(
          src,
          contains('android:name=".MainActivity"'),
          reason: '${entry.key} 未针对 .MainActivity 做覆盖 → release 会出现双图标',
        );
        expect(
          src,
          contains('tools:node="removeAll"'),
          reason: '${entry.key} 缺 removeAll → 线上启动入口从 alias 变成 activity（用户可见）',
        );
        expect(
          blockOf(src, '.MainActivity'),
          isNot(contains('android.intent.category.LAUNCHER')),
          reason: '${entry.key} 覆盖清单自己又声明了 LAUNCHER，语义互相矛盾',
        );
      });
    }
  });

  group('debug 必须禁用默认 alias（可启动组件恒为 1）', () {
    test('debug 对 LauncherDefaultZh 置 enabled=false 且显式 replace', () {
      expect(
        debugManifest,
        contains('android:name=".LauncherDefaultZh"'),
        reason: 'debug 未禁用默认 alias → 与 activity 同时可启动，桌面两个图标',
      );
      expect(
        debugManifest,
        contains('android:enabled="false"'),
        reason: 'debug 的 alias 未置 enabled=false',
      );
      expect(
        debugManifest,
        contains('tools:replace="android:enabled"'),
        reason: '缺 tools:replace → 清单合并器会因 enabled 属性冲突直接报错',
      );
      expect(
        debugManifest,
        contains('xmlns:tools='),
        reason: 'debug 未声明 tools 命名空间 → tools: 属性被静默忽略',
      );
    });
  });
}
