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
