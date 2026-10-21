import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// workmanager 升级（0.6.0 → 0.10.10）后的两条不变量。
///
/// 一条是**跨文件派生**：app 直依赖的 androidx.work 必须与 workmanager_android
/// 要求的版本同档。不同档时 Gradle 会把两者抬到同一份（版本高的那份），
/// 而 app 的 Kotlin worker 是按旧档编译的 —— 这正是 T33/T140 保活链的底座。
/// 另一条钉住已删除/已弃用的旧 API 名不许长回来（analyze 会抓，但只在有人跑它时）。
void main() {
  final root = projectRoot();

  test('androidx.work 与 workmanager_android 要求的版本同档（派生，不抄数字）', () {
    final config = jsonDecode(
      File('$root/.dart_tool/package_config.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final packages = (config['packages'] as List).cast<Map<String, dynamic>>();
    final androidPackage = packages.firstWhere(
      (p) => p['name'] == 'workmanager_android',
      orElse: () => throw StateError('package_config 里没有 workmanager_android'),
    );
    final configFile = File('$root/.dart_tool/package_config.json');
    final rootUri = Uri.parse(androidPackage['rootUri'] as String);
    final packageRoot = rootUri.hasScheme
        ? rootUri.toFilePath()
        : configFile.parent.uri.resolveUri(rootUri).toFilePath();
    final pluginGradle = File('$packageRoot/android/build.gradle')
        .readAsStringSync();
    final required = RegExp(r'def work_version = "([^"]+)"')
        .firstMatch(pluginGradle)
        ?.group(1);
    expect(required, isNotNull, reason: '插件 build.gradle 的版本声明换了形状，守卫要先跟着改');

    final appGradle = File('$root/android/app/build.gradle.kts')
        .readAsStringSync();
    final pinned = RegExp(r'androidx\.work:work-runtime:([0-9][^")\s]*)')
        .firstMatch(appGradle)
        ?.group(1);

    expect(
      pinned,
      required,
      reason:
          'app 直依赖（$pinned）与 workmanager_android 要求（$required）不同档 ⇒ '
          '同一进程里出现两套 androidx.work，Kotlin worker 报类找不到',
    );
  });

  test('旧的枚举/参数名不许长回来（0.8.0 起 camelCase，0.10 起拆周期策略）', () {
    final service = stripComments(
      File('$root/lib/services/notification_service.dart').readAsStringSync(),
    );
    expect(service, contains('NetworkType.notRequired'));
    expect(service, contains('ExistingPeriodicWorkPolicy.'));
    expect(service, isNot(contains('NetworkType.not_required')));
    expect(service, isNot(contains('ExistingWorkPolicy.replace')));

    expect(
      stripComments(File('$root/lib/main.dart').readAsStringSync()),
      isNot(contains('isInDebugMode:')),
      reason:
          'workmanager 0.10 已把 isInDebugMode 标成 deprecated 且无效果；'
          'analyze --fatal-infos 会红',
    );
  });
}
