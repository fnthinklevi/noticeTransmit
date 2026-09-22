import '../support/source_guards.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 备份 / 恢复键对称性守卫（静态源码断言，**注释已剥离**）。
///
/// 背景：`BackupService` 的配置类别分散在三处——
/// ① `collectBackupData` 打包（`return { 'key': ... }`）、
/// ② `restoreFromBackup` 恢复（`payload['key']` 分支）、
/// ③ `detectExisting` 冲突判定（`return { 'key': bool }`）。
///
/// 新增一类可备份配置时（如 v1.59 的「自建应用通道」）若只改 ①，用户换机/重装后
/// 该类配置**静默丢失**（备份面板仍显示成功），且没有任何编译期或运行期报错。
/// 本守卫把这条对称性变成显式断言。
void main() {
  final root = projectRoot();
  final source = stripComments(
    File('$root/lib/services/backup_service.dart').readAsStringSync(),
  );

  final collectKeys = _blockKeys(source, 'collectBackupData');
  final restoreKeys = _restoreKeys(source);
  final detectKeys = _blockKeys(source, 'detectExisting');

  group('备份键对称性', () {
    test('解析到三类键（断言不空，防止提取失效导致假绿）', () {
      expect(collectKeys, isNotEmpty, reason: 'collectBackupData 键解析失败');
      expect(restoreKeys, isNotEmpty, reason: 'restore 键解析失败');
      expect(detectKeys, isNotEmpty, reason: 'detectExisting 键解析失败');
    });

    test('collect 的每个键都有 restore 分支（防「备份了但恢复不到」）', () {
      final missing = collectKeys.difference(restoreKeys);
      expect(missing, isEmpty, reason: '以下配置类别已打包但未实现恢复分支：$missing');
    });

    test('detectExisting 覆盖 collect 全部键（恢复冲突判定不漏类别）', () {
      final missing = collectKeys.difference(detectKeys);
      expect(missing, isEmpty, reason: '冲突判定缺少类别：$missing');
    });

    test('restore 不处理 collect 之外的孤儿键', () {
      final orphans = restoreKeys.difference(collectKeys);
      expect(orphans, isEmpty, reason: '恢复分支存在无来源键：$orphans');
    });
  });

  group('自建应用通道（v1.59 回归守卫）', () {
    test('appChannels 在 collect / restore / detectExisting 三处都在场', () {
      expect(
        collectKeys,
        contains('appChannels'),
        reason: 'collectBackupData 未打包自建应用通道 —— 换机后配置丢失',
      );
      expect(
        restoreKeys,
        contains('appChannels'),
        reason: 'restoreFromBackup 未实现自建应用通道恢复',
      );
      expect(
        detectKeys,
        contains('appChannels'),
        reason: 'detectExisting 未统计自建应用通道（恢复冲突策略会误判）',
      );
    });

    test('恢复分支把通道交给 AppChannelService.saveChannels', () {
      expect(
        source.contains('AppChannelService>().saveChannels'),
        isTrue,
        reason: 'appChannels 恢复未走 AppChannelService（否则不会同步原生）',
      );
    });
  });
}

/// 提取指定方法体内 `return { ... }` 的**顶层键**集合。
///
/// 只取恰好 6 空格缩进的键（`return {` 为 4 空格，其直接子项为 6 空格）——
/// 嵌套子字段（如 `smsSettings` 内的 `sms_monitor_enabled`）缩进更深，不会被误收。
Set<String> _blockKeys(String source, String methodName) {
  final start = source.indexOf(methodName);
  if (start < 0) return {};
  final nextMethod = RegExp(
    r'\n  (?:Future|void|Map|List|String|bool|int)[^\n]*\(',
  ).firstMatch(source.substring(start + methodName.length));
  final end = nextMethod == null
      ? source.length
      : start + methodName.length + nextMethod.start;
  final body = source.substring(start, end);
  final keys = <String>{};
  for (final line in body.split('\n')) {
    final m = RegExp(r"^ {6}'([a-zA-Z][a-zA-Z0-9]*)':").firstMatch(line);
    if (m != null) keys.add(m.group(1)!);
  }
  return keys;
}

/// 提取 restore 分支处理的键。两种实现形式都要覆盖：
/// ① 直接分支 `payload['key']`；② 键→方法名映射表 `'key': 'saveXxx'`（动态调用）。
Set<String> _restoreKeys(String source) {
  final direct = RegExp(
    r"payload\['([a-zA-Z][a-zA-Z0-9]*)'\]",
  ).allMatches(source).map((m) => m.group(1)!);
  final mapped = RegExp(
    r"'([a-zA-Z][a-zA-Z0-9]*)':\s*'save[A-Za-z]*'",
  ).allMatches(source).map((m) => m.group(1)!);
  return {...direct, ...mapped};
}
