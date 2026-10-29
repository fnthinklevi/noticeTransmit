import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// sqflite_common 的 vendored 补丁（2026-10-29 真机数据库永久打不开的修复）。
///
/// 上游 2.5.11 在 `recoveredInTransaction` 分支把 options 硬转成
/// `SqfliteOpenDatabaseOptions`；`sqflite_sqlcipher` 传的 options 不是它的子类
/// ⇒ CastError，且 ROLLBACK 排在那行之后永远执行不到。这里钉住三件事：
/// 1) override 指向 vendored 目录（补丁真的会被用上）；
/// 2) `recoveredInTransaction` 分支先判类型、未知类型默认回滚、再发 ROLLBACK；
/// 3) `onDowngrade` 那一处也不再硬转。
void main() {
  final root = projectRoot();
  final mixin = '$root/third_party/sqflite_common/lib/src/database_mixin.dart';

  String read(String path) => File(path).readAsStringSync();
  String code(String path) => stripComments(read(path));
  String flat(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

  test('pubspec 把 sqflite_common 指到 vendored 目录（补丁才生效）', () {
    final pubspec = read('$root/pubspec.yaml');
    expect(pubspec, contains('dependency_overrides:'));
    expect(pubspec, contains('sqflite_common:'));
    expect(pubspec, contains('path: third_party/sqflite_common'));

    final vendored = read('$root/third_party/sqflite_common/pubspec.yaml');
    expect(vendored, contains('name: sqflite_common'));
    expect(vendored, contains('version: 2.5.11'));
    expect(
      File('$root/third_party/sqflite_common/LICENSE').existsSync(),
      isTrue,
      reason: 'vendored 包必须带许可证',
    );
  });

  test('recoveredInTransaction：类型判断 + 未知 options 默认回滚 + 再发 ROLLBACK', () {
    final branch = blockAfter(code(mixin), 'if (recoveredInTransaction)');
    expect(
      flat(branch),
      contains(
        'openOptions is SqfliteOpenDatabaseOptions ? '
        'openOptions.rollbackActiveTransactionOnOpen : true',
      ),
      reason: '未知 options（sqlcipher）必须走回滚；只修 cast 不回滚仍会卡死',
    );
    expect(
      flat(branch),
      contains('final openOptions = options'),
      reason: '`options` 是字段，先绑局部变量才能做类型提升',
    );
    expect(branch, contains('ROLLBACK'));
    expect(
      branch.indexOf('ROLLBACK'),
      greaterThan(branch.indexOf('openOptions is SqfliteOpenDatabaseOptions')),
      reason: '先判类型再发 ROLLBACK —— 顺序反了仍是永久打不开',
    );
    expect(branch, isNot(contains('as SqfliteOpenDatabaseOptions')));
  });

  test('onDowngrade：类型判断替代硬转', () {
    final block = blockAfter(
      code(mixin),
      'if (options is SqfliteOpenDatabaseOptions)',
    );
    expect(block, contains('onDowngrade = onDatabaseDowngradeDoDelete'));
    expect(block, isNot(contains('as SqfliteOpenDatabaseOptions')));
  });

  test('整个 vendored mixin 不再出现硬转（上游再加一处也要拦）', () {
    expect(code(mixin), isNot(contains('as SqfliteOpenDatabaseOptions')));
  });
}
