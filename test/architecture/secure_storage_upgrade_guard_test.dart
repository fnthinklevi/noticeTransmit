import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// flutter_secure_storage 的两步迁移闸。
///
/// 官方明确：v11 删掉了 v10 的迁移路径，从 v9 直跳 v11 会让旧数据不可用；
/// 正确路径是 v9 → v10（首次访问自动迁移）→ 设备验证 → 再谈 v11。
/// 这里钉住「停在 10.x」与「迁移开关显式打开、不再传已废弃参数」。
void main() {
  final root = projectRoot();

  test('flutter_secure_storage 先停在 10.x（9→11 直跳会丢迁移路径）', () {
    final pubspec = File('$root/pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('flutter_secure_storage: ^10.'));
    expect(pubspec, isNot(contains('flutter_secure_storage: ^9.')));
    expect(
      pubspec,
      isNot(contains('flutter_secure_storage: ^11.')),
      reason: '11 只能在 10.x 的设备迁移验证通过后再抬',
    );
  });

  test('不再传已废弃的 encryptedSharedPreferences，迁移开关显式打开', () {
    final src = stripComments(
      File('$root/lib/services/secure_storage_service.dart').readAsStringSync(),
    );
    expect(
      src,
      isNot(contains('encryptedSharedPreferences')),
      reason: 'v10 起该参数被忽略且已废弃；传它会让 analyze --fatal-infos 红',
    );
    expect(
      src,
      contains('migrateOnAlgorithmChange: true'),
      reason: '旧 EncryptedSharedPreferences 数据要靠这一步在首次访问时迁移',
    );
  });
}
