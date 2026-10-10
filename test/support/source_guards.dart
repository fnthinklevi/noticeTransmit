// 静态源码守卫的共用工具（Dart 侧）。
//
// 本项目大量守卫是「读源文件 + 字符串断言」（见 test/database、test/services
// 与 android/app/src/test）。这类守卫有两个只靠约定维持的失效模式，
// 因此把算法收敛在这里，避免每份复制各自漂移：
//
// 1. **必须剥注释**：否则「解释为什么改了」的注释文本会污染键集合断言
//    （项目已踩过一次）。
// 2. **剥注释必须引号感知**：按「行内首个 //」截断会把 'https://host'
//    这类字符串字面量从中间切掉，使被守卫的键集合静默少项——
//    守卫变绿，但保护已经没了（「测试通过 ≠ 有保护」）。
import 'dart:io';

/// 剥离块注释与行注释，只留可执行代码。行注释按引号状态判定。
String stripComments(String source) {
  final withoutBlock = source.replaceAll(RegExp('/\\*[\\s\\S]*?\\*/'), '');
  final out = <String>[];
  for (final line in withoutBlock.split('\n')) {
    String? quote;
    var escaped = false;
    var cut = -1;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == quote) {
          quote = null;
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        continue;
      }
      if (ch == '/' && i + 1 < line.length && line[i + 1] == '/') {
        cut = i;
        break;
      }
    }
    out.add(cut >= 0 ? line.substring(0, cut) : line);
  }
  return out.join('\n');
}

/// 探测仓库根目录。`flutter test` 的 cwd 就是项目根，但为兼容从子目录运行做探测。
String projectRoot() {
  for (final rel in const ['../..', '..', '.']) {
    if (File('$rel/pubspec.yaml').existsSync()) return rel;
  }
  throw StateError('未找到项目根目录（pubspec.yaml）');
}

/// 剥离 XML 注释（`<!--` … `-->`）。清单类守卫读的是 XML，
/// 上面那套 C 风格注释规则对它无效——注释里出现的组件名同样会污染断言。
/// 用显式扫描而非正则：本仓库多次踩到 shell 层吞反斜杠把 `\s` 写坏的问题。
String stripXmlComments(String source) {
  var out = source;
  while (true) {
    final start = out.indexOf('<!--');
    if (start < 0) break;
    final end = out.indexOf('-->', start);
    if (end < 0) {
      out = out.substring(0, start);
      break;
    }
    out = out.substring(0, start) + out.substring(end + 3);
  }
  return out;
}

/// 剥离 shell 脚本的 `#` 注释（逐行截断、保留行数、引号内的 `#` 不算注释）。
///
/// 为什么单列一份：shell 的注释符与 Dart/XML 都不同，套用上面两个剥离器会**完全不生效**，
/// 于是 `#trap cleanup_emulator EXIT` 这种「注释掉的现役代码」在守卫眼里仍是代码 ——
/// 判据为真、闸门其实是空的（本仓库 2026-09-25 实测踩过：把 trap 注释掉，守卫照样绿）。
/// 局限：不处理 heredoc 内的 `#`（被扫描的发版脚本没有 heredoc）。
String stripShellComments(String source) {
  final out = <String>[];
  for (final line in source.split('\n')) {
    var quote = '';
    var cut = -1;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (quote.isNotEmpty) {
        if (ch == r'\') {
          i++;
        } else if (ch == quote) {
          quote = '';
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        continue;
      }
      if (ch == '#' && (i == 0 || line[i - 1] == ' ' || line[i - 1] == '\t')) {
        cut = i;
        break;
      }
    }
    out.add(cut >= 0 ? line.substring(0, cut) : line);
  }
  return out.join('\n');
}

/// 读 **整个 `lib/`** 的 Dart 源码，逐文件剥注释 + part 感知，key 为相对 `lib/` 的正斜杠路径。
///
/// 为什么收在这里：「这件事只有一个作者」类守卫反复需要同一把尺（全库扫、剥注释、
/// 带上 part）。各测试文件各抄一份的话，**抄漏的那一份就是下一个瞎守卫** ——
/// 与 T65 那次"守卫只读主文件"是同一类故障。
Map<String, String> libCodeByRel(String root) {
  final out = <String, String>{};
  final libDir = Directory('$root/lib');
  final prefix = libDir.absolute.path;
  for (final f in libDir.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final rel = f.absolute.path
        .substring(prefix.length)
        .replaceAll('\\', '/')
        .replaceFirst('/', '');
    out[rel] = stripComments(librarySource(root, 'lib/$rel'));
  }
  return out;
}

/// 从 [source] 中 [signature] 处起，按花括号配对取出整块（含函数体）。
/// 用于「顺序 / 包含关系」类断言——全文件 indexOf 会命中前面的同名片段。
String blockAfter(String source, String signature) {
  final start = source.indexOf(signature);
  if (start < 0) throw StateError('未找到函数签名：$signature');
  final bodyStart = source.indexOf('{', start);
  if (bodyStart < 0) throw StateError('签名后无左花括号：$signature');
  var depth = 0;
  for (var i = bodyStart; i < source.length; i++) {
    if (source[i] == '{') {
      depth++;
    } else if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  return source.substring(start);
}

/// 读**整个 library** 的源码：入口文件 + 它声明的全部 `part '...'`。
///
/// 为什么需要它：`R3` 那类拆分把实现从 `main_page.dart` 搬进 `main_page_actions.dart`
/// （同一个 library 的 part），而大量守卫是"读那一个文件 + 断言里面没有 X"。
/// 于是**负向断言从拆分那天起就瞎了** —— 把 X 写进 part 文件，守卫照样绿。
/// （T65 盘点 mounted 棘轮时发现的，见 base.md 116。）
///
/// 用法：负向断言（"这里不许长出第二份实现"）一律用本函数；
/// 正向断言盯的是"某个具体文件确实调了它"，那种时候按需要单独读某个 part。
String librarySource(String root, String entryRelative) {
  final entry = File('$root/$entryRelative');
  final entryText = entry.readAsStringSync();
  final parts = <String>[entryText];
  final dir = entry.parent.path;
  final declared = RegExp(
    r"^part\s+'([^']+)'",
    multiLine: true,
  ).allMatches(entryText).map((m) => m.group(1)!).toList();
  for (final rel in declared) {
    final f = File('$dir${Platform.pathSeparator}$rel');
    if (!f.existsSync()) {
      throw StateError('$entryRelative 声明了 part $rel 但文件不存在');
    }
    parts.add(f.readAsStringSync());
  }
  return parts.join('\n');
}
