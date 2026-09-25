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

/// 图标体系规模（唯一维护点）：新增/删除桌面图标时只需修改 [launcherIconCount]。
/// 期望 alias 总数由它与语言数推导，中英是否成对由测试从清单实际解析校验——
/// 不再散落硬编码的 34。
const launcherIconCount = 17;
const launcherLanguageCount = 2;

void main() {
  final root = projectRoot();

  /// ⚠ 清单按**变体名惰性读取**：早先是在 `main()` 顶层把四份读进变量，某个变体目录改名
  ///   就抛在测试体之外 ⇒ 整个文件加载失败，CI 表现为"这个文件没有用例"而不是红。
  ///   下面「四个变体都在」那条测试就是把这个空洞补上的正面锚点。
  String manifest(String variant) {
    final file = File('$root/android/app/src/$variant/AndroidManifest.xml');
    expect(file.existsSync(), isTrue, reason: '缺 $variant 覆盖清单');
    return stripXmlComments(file.readAsStringSync());
  }

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
    test('四个变体清单都在（缺文件要红，不许表现为"没有用例"）', () {
      for (final variant in const ['main', 'debug', 'release', 'profile']) {
        expect(
          File(
            '$root/android/app/src/$variant/AndroidManifest.xml',
          ).existsSync(),
          isTrue,
          reason:
              'src/$variant/AndroidManifest.xml 不见了：'
              'overlay 结构一旦被挪走，下面所有断言都无从谈起',
        );
      }
    });

    test('.MainActivity 带 MAIN + LAUNCHER（flutter_tools 只认 activity）', () {
      final block = blockOf(manifest('main'), '.MainActivity');
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
        manifest('main'),
      ).where((b) => b.contains('android.intent.category.LAUNCHER')).length;
      expect(n, 1, reason: 'main 清单里带 LAUNCHER 的 activity 必须恰好 1 个');
    });

    test('alias 数量与中英配对完整（图标切换体系未被误删）', () {
      const expected = launcherIconCount * launcherLanguageCount;
      final mainManifest = manifest('main');
      // 从清单实际解析：原始标签数（含任何不符合命名约定的 alias）
      final rawCount = RegExp(
        r'<activity-alias[\s>]',
      ).allMatches(mainManifest).length;
      // 解析出 (图标基名, 语言后缀)；不匹配约定的 alias 不会进入此列表
      final named = RegExp(
        r'<activity-alias\s+android:name="\.Launcher([A-Za-z0-9]+)(Zh|En)"',
      ).allMatches(mainManifest).map((m) => (m.group(1)!, m.group(2)!)).toList();

      expect(
        rawCount,
        named.length,
        reason: '存在不符合 .Launcher<图标>Zh/En 命名约定的 alias，计数会失真',
      );
      expect(
        named.length,
        expected,
        reason:
            '$launcherIconCount 图标 × $launcherLanguageCount 语言 = $expected 个 alias',
      );

      // 结构契约：每个图标基名必须同时具备 Zh 与 En，漏配一种语言即失败
      final byIcon = <String, Set<String>>{};
      for (final (icon, lang) in named) {
        byIcon.putIfAbsent(icon, () => <String>{}).add(lang);
      }
      expect(
        byIcon.length,
        launcherIconCount,
        reason: '图标基名数应为 $launcherIconCount（alias 数对但图标数变了也要显式确认）',
      );
      for (final entry in byIcon.entries) {
        expect(
          entry.value,
          containsAll(<String>['Zh', 'En']),
          reason:
              '图标 .Launcher${entry.key} 缺少语言变体: '
              '${<String>{'Zh', 'En'}.difference(entry.value)}',
        );
      }

      expect(
        mainManifest,
        contains('android:name=".LauncherDefaultZh"'),
        reason: '默认 alias 缺失：debug 覆盖清单的 enabled=false 将指向不存在的组件',
      );
    });
  });

  group('release / profile 必须移除 activity 级 LAUNCHER', () {
    for (final variant in const ['release', 'profile']) {
      test('$variant 覆盖清单结构完整', () {
        final src = manifest(variant);
        expect(
          src,
          contains('xmlns:tools='),
          reason: '$variant 未声明 tools 命名空间 → tools: 属性被静默忽略，移除根本不生效',
        );
        expect(
          src,
          contains('android:name=".MainActivity"'),
          reason: '$variant 未针对 .MainActivity 做覆盖 → release 会出现双图标',
        );
        expect(
          src,
          contains('tools:node="removeAll"'),
          reason: '$variant 缺 removeAll → 线上启动入口从 alias 变成 activity（用户可见）',
        );
        final block = blockOf(src, '.MainActivity');
        expect(
          block,
          isNotEmpty,
          reason:
              '$variant 里定位不到 .MainActivity 的 activity 块 ⇒ 下面那条「不含 LAUNCHER」'
              '会对空串永远成立（典型的抽取落空假绿）',
        );
        expect(
          block,
          isNot(contains('android.intent.category.LAUNCHER')),
          reason: '$variant 覆盖清单自己又声明了 LAUNCHER，语义互相矛盾',
        );
      });
    }
  });

  group('debug 必须禁用默认 alias（可启动组件恒为 1）', () {
    test('debug 对 LauncherDefaultZh 置 enabled=false 且显式 replace', () {
      final debugManifest = manifest('debug');
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
