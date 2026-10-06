import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T77：部署卫生守卫族 —— 钉住「**入库的生成物里不许带着生成它那台机器的配置**」。
///
/// 为什么这条要重开：上一版的守卫脚本写在 `outputs/check_*.js`，而 **`outputs/` 整个在
/// `.gitignore` 里** —— 它们从来没进过版本库，于是「守卫不在」不是被谁删了，是**从来没提交过**。
/// 守卫放在一个不入库的目录里，等于没有守卫。⇒ 本文件放在 `test/architecture/`，
/// 跟着 `flutter test` 进 CI。
///
/// 钉三件（每件都对应一种「本地好好的、到别人机器上就坏」）：
///  ① **ignore 覆盖面**：`.gitignore` 必须挡住那几类。看到文件被删过、想临时放开的人，
///     这一条会当场喊 —— 而「先放开再说」正是这类泄漏的起点。
///  ② **库里没有它们**：反过来核一遍已入库清单（`.gitignore` 挡住不等于没进去过：
///     `git add -f` 与历史提交都能绕过）。
///  ③ **生成物里没有绝对机器路径**：本条是这个守卫族的正题。入库的生成物
///     （l10n 产物 / lock 文件 / wrapper 配置 / 版本 JSON…）里出现 `D:/`、`C:\Users`、
///     `/Users/`、`/home/`，在**别人的机器上**表现为路径不存在或行为不同，
///     而在**这台机器上**永远是绿的。
void main() {
  final root = projectRoot();
  final rootIO = Directory(root);
  if (!rootIO.existsSync()) {
    throw StateError('仓库根目录不存在：$root（cwd=${Directory.current.path}）');
  }

  String read(String rel) => File('$root/$rel').readAsStringSync();

  group('① .gitignore 必须挡住那几类', () {
    // 为什么是逐条钉而不是"整份快照对比"：整份对比一改就红，而这里的每一行都是一条
    // 独立的泄漏通道，改它的人必须当场知道自己在放开什么。
    const required = <String, String>{
      'server/node_modules/': 'npm 依赖（几百 MB，且带着装它那台机器的传递版本）',
      '/build/': 'Flutter 构建产物（带着构建机路径与绝对符号）',
      'android/app/build/': 'Gradle 应用构建产物',
      'android/build/': 'Gradle 根构建产物',
      '.dart_tool/': '工具链状态（含本机解析出的包图）',
      'outputs/': '本机工作产物（守卫脚本与日志都在这儿）',
      '*.keystore': '**签名私钥**',
      'android/key.properties': '签名口令与别名（真身；.example 模板要留）',
      '.env': '服务端环境变量（明文凭证）',
      'server/data/blocked_ips.json': '运行时状态，不随代码走',
      'server/data/failed_attempts.json': '运行时状态，不随代码走',
    };

    test('逐条点名，不是一整份快照', () {
      final lines = read('.gitignore')
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toSet();
      final missing = required.keys.where((k) => !lines.contains(k)).toList();
      expect(
        missing,
        isEmpty,
        reason:
            '`.gitignore` 少了这几条（各自挡的是：\n'
            '${missing.map((k) => '  · $k —— ${required[k]}').join('\n')}）\n'
            '要放开哪一条，先说清它挡住的是什么 —— 「先放开再说」就是这类泄漏的起点。',
      );
    });
  });

  group('② 那些路径要么不存在、要么仍被 ignore 挡着', () {
    // ⚠ 这里**不**用 `git ls-files`：它在 Windows 上要走 `cmd.exe`，而 git 常驻在
    //   Git Bash 的 /usr/bin 里 —— 闸门进程那条 PATH 上常常没有 git，于是这条判据
    //   在本机与 CI 上表现不同（一个绿一个红），而绿的那个还是"根本没跑成"。
    //   「本地绿、CI 红」正是 T63-B 记过的那一类假绿。
    //   改成纯文件系统判定：**要么它不存在，要么它仍被 .gitignore 挡着**。
    //   它盖不住"历史上 `git add -f` 进来的"（那要读索引），但那属于历史债，
    //   靠一条会时绿时红的判据去守是守不住的。
    const dangerous = <String, String>{
      'server/node_modules': 'npm 依赖',
      'build': 'Flutter 构建产物',
      '.dart_tool': '工具链状态',
      'outputs': '本机工作产物',
      'android/build': 'Gradle 根构建产物',
      'android/app/build': 'Gradle 应用构建产物',
      '.env': '服务端环境变量（明文凭证）',
      'android/key.properties': '签名口令与别名',
    };

    /// 极简 .gitignore 判定：目录/文件被任一条「前缀或路径等于」命中即算被挡。
    List<String> ignoreLines() => read('.gitignore')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();

    bool ignoredBy(String rel, List<String> lines) => lines.any((pat) {
      var p = pat;
      if (p.endsWith('/')) p = p.substring(0, p.length - 1);
      if (p.startsWith('/')) p = p.substring(1);
      if (p.isEmpty) return false;
      return rel == p || rel.startsWith('$p/');
    });

    test('忽略判定认得锚定写法（`/build/` 与 `build` 是一回事）', () {
      // ⚠ 这条是补自己踩的坑：第一版只剥了尾部的 `/`，于是 `/build/` 匹配不上 `build`，
      //   而 `.gitignore` 里**恰恰**写的是 `/build/` ⇒ ② 把「明明挡着」报成「不再挡着」。
      //   没有这条锚点，把首部 `/` 的处理改回去不会有任何人发现。
      final lines = ignoreLines();
      expect(
        ignoredBy('build', lines),
        isTrue,
        reason:
            '`.gitignore` 里写的是 `/build/`（锚定仓库根），'
            '判定剥掉首部 `/` 后仍必须匹配 `build`',
      );
      expect(
        ignoredBy('server/node_modules', lines),
        isTrue,
        reason: '目录写法（尾部 `/`）也要认 —— 那是另一种形状',
      );
      expect(
        ignoredBy('lib', lines),
        isFalse,
        reason:
            '反向锚点：不在清单里的路径必须判成「没被挡着」，'
            '否则 ② 恒真',
      );
    });

    test('逐个点名：要么不存在，要么仍被 ignore 挡着', () {
      final lines = ignoreLines();
      final leaked = <String>[];
      for (final entry in dangerous.entries) {
        if (!Directory('$root/${entry.key}').existsSync() &&
            !File('$root/${entry.key}').existsSync()) {
          continue; // 本机根本没生成 —— 那是干净状态
        }
        if (!ignoredBy(entry.key, lines)) {
          leaked.add('  · ${entry.key}（${entry.value}）已存在，却不再被 .gitignore 挡住');
        }
      }
      expect(
        leaked,
        isEmpty,
        reason:
            '这些路径在磁盘上存在，而 .gitignore 不再挡它们 —— '
            '一次 `git add .` 就会把它们带进版本库：\n${leaked.join('\n')}',
      );
    });

    test('签名真身不存在（模板要留，真身不许在库里）', () {
      expect(
        ignoredBy('android/key.properties', ignoreLines()),
        isTrue,
        reason:
            '签名真身（口令与别名）不再被 .gitignore 挡住 ⇒ '
            '一次 `git add .` 就把它带进版本库。\n'
            '⚠ 这里判的是「**被挡着**」而不是「不存在」：本地有一份是对的（release 打包要读它），'
            '它不在版本库里才是对的；用「不存在」去判会把一台配好的开发机判红。',
      );
      expect(
        File('$root/android/key.properties.example').existsSync(),
        isTrue,
        reason:
            '签名配置**模板**不见了 ⇒ 别人照着它配不出本地环境，'
            '而本机一切正常（这台机器上有真身兜着）',
      );
    });
  });

  group('③ 入库的生成物里不许有绝对机器路径', () {
    /// 只查"入库的生成物"：全量扫 lib/ 会把测试夹具里故意写的假路径一起喊出来。
    const artifacts = <String>[
      'lib/l10n/app_localizations.dart',
      'lib/l10n/app_localizations_zh.dart',
      'lib/l10n/app_localizations_en.dart',
      'android/gradle/wrapper/gradle-wrapper.properties',
      'server/data/version.json',
      'pubspec.lock',
      'server/package-lock.json',
      '.github/workflows/integration_test.yml',
    ];

    /// Windows 盘符、`C:\Users`、POSIX 的 `/Users/` 与 `/home/`。
    ///
    /// ⚠ 盘符那段**必须有负向后顾**：写成 `[A-Za-z]:[\\/]` 时，`https://` 的 `s:/`
    /// 会被匹配上 —— 而 `pubspec.lock` 与 `server/package-lock.json` 里全是 https 的
    /// 仓库地址，于是 107 处与 551 处**全是假阳性**，而这条守卫会显得"发现了 658 个问题"。
    /// 盘符的判据是"**一个**字母 + `:` + 斜杠，且那个字母前面不是字母/数字/下划线"。
    ///
    /// ⚠ 必须在**剥注释之后**扫：注释里引用一条示例路径是很正常的写法，
    /// 而它会让这条判据永远红 —— 与 ChannelRouting 那支守卫踩过的同一类。
    final machinePaths = RegExp(
      r'''(?<![A-Za-z0-9_])[A-Za-z]:[\\/]|/Users/|/home/[a-z]|%USERPROFILE%''',
    );

    test('逐个产物扫，命中要点名到文件', () {
      final hits = <String>[];
      for (final rel in artifacts) {
        final f = File('$root/$rel');
        if (!f.existsSync()) continue; // 产物不在库里就没什么可扫
        final body = stripComments(f.readAsStringSync());
        if (machinePaths.hasMatch(body)) {
          final m = machinePaths.firstMatch(body)!;
          hits.add('  · $rel：$m');
        }
      }
      expect(
        hits,
        isEmpty,
        reason:
            '入库的生成物里带着**生成它那台机器**的路径：\n${hits.join('\n')}\n'
            '这台机器上永远是绿的，换一台就坏 —— 而报错会出现在别人手里。',
      );
    });

    test('正向锚点：真的扫到了东西（防"提取退化成永远通过"）', () {
      // 扫的正则若哪天写坏了，上面那条会变成恒真。拿样本当锚。
      expect(
        machinePaths.hasMatch(r'D:\fnthinklevi\flutter'),
        isTrue,
        reason: '机器路径正则自己失效了 ⇒ ③ 变成恒真',
      );
      expect(
        machinePaths.hasMatch('/Users/someone/flutter'),
        isTrue,
        reason: '机器路径正则漏了 POSIX 那一种 ⇒ ③ 只挡 Windows',
      );
      // 反向锚点：`https://` 的 `s:/` **不是**盘符。少了这条，③ 会在两个 lock 文件里
      // 报出几百处假阳性，而"报了几百个问题"的守卫照样没人当真 ——
      // 与「两种新假绿」里那条"命令被另一条路顺手满足"同族。
      expect(
        machinePaths.hasMatch('https://pub.flutter-io.cn'),
        isFalse,
        reason: 'https 的 s:/ 被当成了盘符 ⇒ ③ 全是假阳性',
      );
    });
  });
}
