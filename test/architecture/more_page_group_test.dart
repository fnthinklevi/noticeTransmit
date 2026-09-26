import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T14：「规则约束」入口在「更多」页成组，且**分组与图标对齐现有风格**。
///
/// 任务书原文写着"现挂首页 `main_page.dart:148`" —— 实测前提已不成立：应用筛选 /
/// 关键词过滤 / 规则约束 早在「更多」的 `filterRules` 分组里（首页从来没出现过这些
/// 字样，`git log -S` 查无）。所以本批真正没做完的是后半句：**同组撞色、跨组撞图标**
/// （三处实测存在，见下）。这类问题不会报错、只让列表看着像随手配的，所以钉成守卫。
///
/// 比色值时把 `AppColors.x` 解析成实际 ARGB 再比 —— 按字面串比会让
/// "同一颜色两种写法"（`AppColors.orange` 与 `const Color(0xFFFF9500)`）漏网。
void main() {
  /// ⚠ 两份源码都**惰性读取**：写在 `main()` 顶层时，文件改名会抛在测试体之外 ⇒
  ///   整个文件加载失败，CI 表现为"这个文件没有用例"而不是红（见 base.md（75））。
  String page() => File('lib/pages/more_page.dart').readAsStringSync();
  String palette() => File('lib/theme/app_colors.dart').readAsStringSync();

  /// AppColors 常量名 → 源码里写死的色值表达式
  Map<String, String> colorLiterals() {
    final out = <String, String>{};
    for (final m in RegExp(
      r'static const Color (\w+) = (Color\(0x[0-9A-Fa-f]{8}\))',
    ).allMatches(palette())) {
      out[m.group(1)!] = m.group(2)!;
    }
    return out;
  }

  String resolvedColor(String written) {
    final named = RegExp(r'AppColors\.(\w+)').firstMatch(written);
    if (named == null) {
      return RegExp(r'0x[0-9A-Fa-f]{8}').firstMatch(written)?.group(0) ??
          written;
    }
    final literal = colorLiterals()[named.group(1)];
    return literal != null
        ? RegExp(r'0x[0-9A-Fa-f]{8}').firstMatch(literal)!.group(0)!
        // 主题自适应色（systemXxx）按名字比：不同名字不算撞色
        : 'named:${named.group(1)}';
  }

  /// 按 section header 切段，返回 段名 → 该段内的 nav tile（icon / color / title 键）
  Map<String, List<({String icon, String color, String titleKey})>> sections() {
    final src = page();
    final out =
        <String, List<({String icon, String color, String titleKey})>>{};
    final headerRe = RegExp(r'_buildSectionHeader\(l10n\.(\w+)');
    final heads = headerRe.allMatches(src).toList();
    for (var i = 0; i < heads.length; i++) {
      final from = heads[i].start;
      final to = i + 1 < heads.length ? heads[i + 1].start : src.length;
      final body = src.substring(from, to);
      out[heads[i].group(1)!] = [
        for (final t in RegExp(
          r'icon: Icons\.(\w+),\s*iconColor: ([^,\n]+),\s*title: l10n\.(\w+)',
        ).allMatches(body))
          (
            icon: t.group(1)!,
            color: resolvedColor(t.group(2)!.trim()),
            titleKey: t.group(3)!,
          ),
      ];
    }
    return out;
  }

  int tileCount() => sections().values.fold(0, (a, b) => a + b.length);

  test('解析本身有效（色板 + 分组 + 条目数）：抽取落空时"无撞色"会假绿', () {
    // 下面三条判的是"没有重复"——sections() 一旦返回空 Map，三条全部空跑且全绿。
    expect(
      colorLiterals().length,
      greaterThanOrEqualTo(10),
      reason:
          '色板只解析出 ${colorLiterals().length} 个常量：写法一改（如换成 const Color(0x..) 之外的形式），'
          '同一颜色两种写法就再也归不到一起',
    );
    expect(
      sections().length,
      5,
      reason: '「更多」页分组数变了（当前 ${sections().length}）：分组切法变了要同步这三条断言',
    );
    expect(
      tileCount(),
      14,
      reason: '解析出的 nav tile 数 = ${tileCount()}，为 0 时下面几条全是空断言',
    );
  });

  test('规则约束三行都在「更多」的 filterRules 分组里', () {
    final s = sections();
    expect(
      s.containsKey('filterRules'),
      isTrue,
      reason: '更多页没有 filterRules 分组',
    );
    expect(
      s['filterRules']!.map((t) => t.titleKey).toList(),
      containsAll(['appFilter', 'keywordFilter', 'ruleEngine']),
      reason:
          '应用筛选 / 关键词过滤 / 规则约束 必须同组 —— 二分口径里它们都是'
          '"这条已到达的通知要不要转"，与设备态告警（电量/温度，归通知引擎）不是一回事',
    );
  });

  test('首页不再挂任何规则约束入口（T14 的前提钉死，防回潮）', () {
    // 只查引用点：NotificationPage 的构造参数里不许重新出现这三个 onOpen*。
    final home = File('lib/pages/notification_page.dart').readAsStringSync();
    for (final opener in ['onOpenRules', 'onOpenAppFilter', 'onOpenKeywords']) {
      expect(
        home,
        isNot(contains(opener)),
        reason: '$opener 又回到首页 ⇒ 「更多」那份就成了第二处入口（两处入口必然漂移）',
      );
    }
  });

  test('同一分组内色值不撞（两种写法算同一个色）', () {
    // 一次报全：逐个 expect 会在第一个违规处就退出，剩下的要等修完才看得见。
    final offenders = <String>[];
    for (final entry in sections().entries) {
      final seen = <String, List<String>>{};
      for (final t in entry.value) {
        (seen[t.color] ??= <String>[]).add(t.titleKey);
      }
      for (final dup in seen.entries.where((e) => e.value.length > 1)) {
        offenders.add('「${entry.key}」${dup.key}→${dup.value.join('/')}');
      }
    }
    expect(
      offenders.join(' , '),
      isEmpty,
      reason: '同组两行同色：并列条目分不出彼此，色就不是分组语言而是噪声',
    );
  });

  test('全页 nav tile 图标不重复', () {
    final seen = <String, List<String>>{};
    for (final entry in sections().entries) {
      for (final t in entry.value) {
        (seen[t.icon] ??= <String>[]).add('${entry.key}:${t.titleKey}');
      }
    }
    final offenders = seen.entries
        .where((e) => e.value.length > 1)
        .map((e) => '${e.key}→${e.value.join('/')}')
        .join(' , ');
    expect(
      offenders,
      isEmpty,
      reason:
          '两个不同功能共用一个图标（例：自建应用通道与应用筛选都是 apps）'
          '⇒ 扫一眼分不清点的是哪个',
    );
  });
}
