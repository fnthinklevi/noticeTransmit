import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/theme/app_colors.dart';

import '../support/source_guards.dart';

/// base.md §9.1 / §9.2 / §9.3 的静态那半：颜色只从色板取、输入框/列表项/弹窗
/// 走同一套默认值、开关开启态只有主题绿、界面层不写硬编码中文。
///
/// 本文件只断**契约**（"这个值只能有一个作者"），不断某版行形状：
/// - 色板外的 `Color(0x…)` / `Colors.<名>` 一律红（`Colors.transparent` 是"没有颜色"，放行）；
///   `theme/app_colors.dart`、`widgets/channel_visuals.dart`（品牌色唯一表）、
///   `services/icon_service.dart`（启动图标色数据）是仅有的三处例外。
/// - 主题默认值：列表项 44、输入框填充 `inputBg` + 分割线边框 + 聚焦蓝、弹窗 14。
/// - 所有 `CupertinoTextField` 必须走 `appCupertinoInputDecoration`（圆角 10/浅底/描边）。
/// - `CupertinoSwitch` 若显式给开启色，只能是 `AppColors.systemGreen`；不给则吃 iOS 默认绿。
/// - `lib/pages` 与 `lib/widgets` 里的中文只允许出现在 `debugPrint` / `log` / `assert`
///   与"匹配原生错误原话"的 `text.contains(...)` 里；其余一律应进 ARB。
void main() {
  final root = projectRoot();
  final codeByPath = libCodeByRel(root);

  int lineOf(String src, int index) =>
      src.substring(0, index).split('\n').length;

  const colorOwners = {
    'theme/app_colors.dart',
    'widgets/channel_visuals.dart',
    'services/icon_service.dart',
  };

  List<String> colorOffenders(Map<String, String> sources) {
    final literal = RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)');
    final named = RegExp(r'(^|[^A-Za-z0-9_])Colors\.([A-Za-z]+)');
    final out = <String>[];
    for (final entry in sources.entries) {
      if (colorOwners.contains(entry.key)) continue;
      for (final m in literal.allMatches(entry.value)) {
        out.add('${entry.key}:${lineOf(entry.value, m.start)}: ${m.group(0)}');
      }
      for (final m in named.allMatches(entry.value)) {
        if (m.group(2) == 'transparent') continue;
        out.add(
          '${entry.key}:${lineOf(entry.value, m.start)}: Colors.${m.group(2)}',
        );
      }
    }
    return out;
  }

  /// 从 [start] 处的左括号起取配平块（只用于本文件的两种构造点）。
  String balanced(String src, int start) {
    var depth = 0;
    for (var i = start; i < src.length; i++) {
      if (src[i] == '(') depth++;
      if (src[i] == ')') {
        depth--;
        if (depth == 0) return src.substring(start, i + 1);
      }
    }
    return src.substring(start);
  }

  List<String> cupertinoFieldOffenders(Map<String, String> sources) {
    final out = <String>[];
    for (final entry in sources.entries) {
      final src = entry.value;
      for (final m in RegExp(r'CupertinoTextField\(').allMatches(src)) {
        final block = balanced(src, m.end - 1);
        if (!block.contains('appCupertinoInputDecoration(')) {
          out.add('${entry.key}:${lineOf(src, m.start)}');
        }
      }
    }
    return out;
  }

  List<String> switchColorOffenders(Map<String, String> sources) {
    final out = <String>[];
    for (final entry in sources.entries) {
      final src = entry.value;
      for (final m in RegExp(r'CupertinoSwitch\(').allMatches(src)) {
        final block = balanced(src, m.end - 1);
        if (block.contains('activeTrackColor:') &&
            !block.contains('activeTrackColor: AppColors.systemGreen(')) {
          out.add('${entry.key}:${lineOf(src, m.start)}');
        }
      }
    }
    return out;
  }

  List<String> hardcodedUiTextOffenders(Map<String, String> sources) {
    final cjk = RegExp(r'[\u3400-\u9fff]');
    final allowed = RegExp(r'debugPrint\(|\blog\(|assert\(|text\.contains\(');
    final out = <String>[];
    for (final entry in sources.entries) {
      if (!entry.key.startsWith('pages/') &&
          !entry.key.startsWith('widgets/')) {
        continue;
      }
      final lines = entry.value.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!cjk.hasMatch(line)) continue;
        if (allowed.hasMatch(line)) continue;
        out.add('${entry.key}:${i + 1}: ${line.trim()}');
      }
    }
    return out;
  }

  group('硬编码颜色', () {
    test('色板之外没有 Color(0x…) / Colors.<名>', () {
      expect(
        colorOffenders(codeByPath),
        isEmpty,
        reason:
            'base.md §9.1「所有颜色使用 AppColors」：新色值先加进 app_colors.dart；'
            '品牌色只有 channel_visuals 一张表，启动图标色只有 icon_service。'
            '`Colors.transparent` 表示"没有颜色"，是唯一放行的字面量。',
      );
    });

    test('尺认得合成样本（否则上一条可能是"正则没匹配到"的假绿）', () {
      final sample = {
        'lib/pages/x.dart':
            'const a = Color(0xFF123456);\n'
            'const b = Colors.white;\n'
            'const c = Colors.transparent;\n'
            'const d = AppColors.blue;\n',
        'theme/app_colors.dart': 'const e = Color(0xFF123456);\n',
      };
      expect(colorOffenders(sample), [
        'lib/pages/x.dart:1: Color(0xFF123456)',
        'lib/pages/x.dart:2: Colors.white',
      ], reason: '抓不到/抓多了 ⇒ 上面那条对真实仓库也不可信');
    });
  });

  group('主题默认值', () {
    test('AppColors 的明暗两套值就是 base §9.2 那张表', () {
      final light = AppThemeColors.light();
      final dark = AppThemeColors.dark();
      const expectedLight = {
        'bgColor': 0xFFF2F2F7,
        'cardBg': 0xFFFFFFFF,
        'primaryLabel': 0xFF000000,
        'secondaryLabel': 0xFF8E8E93,
        'tertiaryLabel': 0xFFC7C7CC,
        'separator': 0xFFE5E5EA,
        'inputBg': 0xFFF2F2F7,
        'systemBlue': 0xFF007AFF,
        'systemGreen': 0xFF34C759,
        'systemRed': 0xFFFF3B30,
        'systemOrange': 0xFFFF9500,
        'systemPurple': 0xFFAF52DE,
        'systemCyan': 0xFF5AC8FA,
        'systemYellow': 0xFFFFCC00,
        'systemGray': 0xFFF2F2F7,
      };
      const expectedDark = {
        'bgColor': 0xFF000000,
        'cardBg': 0xFF1C1C1E,
        'primaryLabel': 0xFFFFFFFF,
        'secondaryLabel': 0xFF8E8E93,
        'tertiaryLabel': 0xFF48484A,
        'separator': 0xFF38383A,
        'inputBg': 0xFF2C2C2E,
        'systemBlue': 0xFF0A84FF,
        'systemGreen': 0xFF30D158,
        'systemRed': 0xFFFF453A,
        'systemOrange': 0xFFFF9F0A,
        'systemPurple': 0xFFBF5AF2,
        'systemCyan': 0xFF64D2FF,
        'systemYellow': 0xFFFFD60A,
        'systemGray': 0xFF2C2C2E,
      };
      final gotLight = <String, int>{
        'bgColor': light.bgColor.toARGB32(),
        'cardBg': light.cardBg.toARGB32(),
        'primaryLabel': light.primaryLabel.toARGB32(),
        'secondaryLabel': light.secondaryLabel.toARGB32(),
        'tertiaryLabel': light.tertiaryLabel.toARGB32(),
        'separator': light.separator.toARGB32(),
        'inputBg': light.inputBg.toARGB32(),
        'systemBlue': light.systemBlue.toARGB32(),
        'systemGreen': light.systemGreen.toARGB32(),
        'systemRed': light.systemRed.toARGB32(),
        'systemOrange': light.systemOrange.toARGB32(),
        'systemPurple': light.systemPurple.toARGB32(),
        'systemCyan': light.systemCyan.toARGB32(),
        'systemYellow': light.systemYellow.toARGB32(),
        'systemGray': light.systemGray.toARGB32(),
      };
      final gotDark = <String, int>{
        'bgColor': dark.bgColor.toARGB32(),
        'cardBg': dark.cardBg.toARGB32(),
        'primaryLabel': dark.primaryLabel.toARGB32(),
        'secondaryLabel': dark.secondaryLabel.toARGB32(),
        'tertiaryLabel': dark.tertiaryLabel.toARGB32(),
        'separator': dark.separator.toARGB32(),
        'inputBg': dark.inputBg.toARGB32(),
        'systemBlue': dark.systemBlue.toARGB32(),
        'systemGreen': dark.systemGreen.toARGB32(),
        'systemRed': dark.systemRed.toARGB32(),
        'systemOrange': dark.systemOrange.toARGB32(),
        'systemPurple': dark.systemPurple.toARGB32(),
        'systemCyan': dark.systemCyan.toARGB32(),
        'systemYellow': dark.systemYellow.toARGB32(),
        'systemGray': dark.systemGray.toARGB32(),
      };
      expect(gotLight, expectedLight, reason: '浅色表与 base §9.2 不一致');
      expect(gotDark, expectedDark, reason: '深色表与 base §9.2 不一致');
      expect(AppColors.avatarPalette, const [
        AppColors.blue,
        AppColors.orange,
        AppColors.green,
        AppColors.red,
        AppColors.purple,
        AppColors.indigo,
        AppColors.teal,
        AppColors.pink,
        AppColors.yellow,
      ], reason: 'base §9.2：头像色板顺序即取色顺序，重排会让既有记录颜色整体跳变');
    });

    test('列表项 44 / 输入框边框与聚焦 / 弹窗 14', () {
      final theme = codeByPath['theme/app_theme.dart'];
      expect(theme, isNotNull, reason: '主题文件不在了 ⇒ 这条守卫在空转');
      final src = theme!;
      expect(
        src,
        contains('minTileHeight: 44'),
        reason: 'base §9.3：列表项高度 44dp',
      );
      expect(
        src,
        contains('enabledBorder: OutlineInputBorder('),
        reason: '输入框常态要有边框；没有边框时 inputBg 与页面底色相同就看不见',
      );
      expect(
        src,
        contains('borderSide: BorderSide(color: colors.separator)'),
        reason: 'base §9.1：输入框边框取分割线色',
      );
      expect(
        src,
        contains('borderSide: BorderSide(color: colors.systemBlue)'),
        reason: 'base §9.1：聚焦边框取系统蓝',
      );
      expect(
        RegExp(r'dialogTheme: DialogThemeData\([\s\S]*?circular\(14\)')
            .hasMatch(src),
        isTrue,
        reason: 'base §9.1：弹窗圆角 14',
      );
    });
  });

  group('输入框与开关', () {
    test('每个 CupertinoTextField 都走统一输入形状', () {
      expect(
        cupertinoFieldOffenders(codeByPath),
        isEmpty,
        reason:
            'CupertinoTextField 不吃 InputDecorationTheme ⇒ 不套 appCupertinoInputDecoration '
            '就没有圆角 10／浅底／描边，同一页的 Material 输入框与它会长成两种。',
      );
    });

    test('输入形状的尺认得合成样本', () {
      final sample = {
        'lib/pages/x.dart':
            'CupertinoTextField(key: k);\n'
            'CupertinoTextField(decoration: appCupertinoInputDecoration(context));\n',
      };
      expect(cupertinoFieldOffenders(sample), ['lib/pages/x.dart:1']);
    });

    test('CupertinoSwitch 显式开启色只能是主题绿', () {
      expect(
        switchColorOffenders(codeByPath),
        isEmpty,
        reason: 'base §9.2：系统绿用于「成功、开启状态」。蓝/紫开关会让"开着"变成另一种语义色。',
      );
    });

    test('开关色的尺认得合成样本', () {
      final sample = {
        'lib/pages/x.dart':
            'CupertinoSwitch(value: a, onChanged: f, activeTrackColor: AppColors.blue);\n'
            'CupertinoSwitch(value: b, onChanged: g, activeTrackColor: AppColors.systemGreen(context));\n'
            'CupertinoSwitch(value: c, onChanged: h);\n',
      };
      expect(switchColorOffenders(sample), ['lib/pages/x.dart:1']);
    });
  });

  group('界面层文案', () {
    test('lib/pages 与 lib/widgets 里的中文只出现在调试/断言/匹配键里', () {
      expect(
        hardcodedUiTextOffenders(codeByPath),
        isEmpty,
        reason:
            'base §3.6：所有 UI 可见文本必须走 l10n。调试输出与「匹配原生错误原话」'
            '不是界面文案（前者仅开发可见，后者要拿原话判类）；其余中文一律进两份 ARB。',
      );
    });

    test('中文扫描的尺认得合成样本', () {
      final sample = {
        'pages/x.dart':
            "debugPrint('调试可见');\n"
            "Text('用户可见');\n"
            "if (text.contains('匹配键')) {}\n",
        'services/x.dart': "throw StateError('服务层不在这把尺里');\n",
      };
      expect(hardcodedUiTextOffenders(sample), [
        'pages/x.dart:2: Text(\'用户可见\');',
      ]);
    });
  });

  test('扫描口径还在（文件数/源码非空，避免全套守卫空转）', () {
    expect(codeByPath.length, greaterThan(150));
    expect(File('$root/lib/theme/app_theme.dart').existsSync(), isTrue);
  });
}
