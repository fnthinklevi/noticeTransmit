import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// file_picker 8 → 13 换代后的两条不变量。
///
/// 13 的 API 与 8 不兼容：`FilePicker` 改成静态方法、`pickFiles` 不再返回
/// `FilePickerResult`、`withData` 已删、SAF 下 `path` 可能为 null。
/// 这里钉住「已经迁到新形状」与「旧形状不许长回」；具体文件读写走
/// `PlatformFile.readAsBytes()`，不再依赖本地路径。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  test('pubspec 已抬到 file_picker 13（API 换代才成立）', () {
    final pubspec = File('$root/pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('file_picker: ^13.'));
    expect(
      pubspec,
      isNot(contains('file_picker: ^8.')),
      reason: '8.x 的实例 API 与 13 不兼容，回退会直接编译失败',
    );
  });

  test('两个入口都走 pickFile + readAsBytes（不用实例 API / withData / 本地路径）', () {
    for (final rel in const [
      'lib/pages/backup_restore_page.dart',
      'lib/widgets/rule_template_sheet.dart',
    ]) {
      final src = read(rel);
      expect(src, contains('FilePicker.pickFile('), reason: rel);
      expect(
        src,
        contains('readAsBytes()'),
        reason: '$rel：SAF 下 path 可能为 null，必须走字节读口',
      );
      expect(src, isNot(contains('FilePicker.platform')), reason: rel);
      expect(src, isNot(contains('withData:')), reason: rel);
      expect(src, isNot(contains('File(path)')), reason: rel);
    }
  });
}
