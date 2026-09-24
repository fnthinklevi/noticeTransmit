import 'dart:io';

import '../support/source_guards.dart';
import 'package:flutter_test/flutter_test.dart';

/// app_channels 表 schema 契约守卫（静态源码断言，**注释已剥离**）。
///
/// 背景：`app_channels` 是「自建应用通道」的独立表（企微自建应用 / 飞书自建应用），
/// 其列名契约分散在**三处**，任何一处单独改名都不会有编译期或运行期报错：
///
/// 1. `DatabaseHelper._onCreate` 的建表 SQL；
/// 2. `DatabaseHelper` 迁移路径中的建表 SQL（两处必须列集合一致，防升级漂移）；
/// 3. `saveAppChannels` 的写入列映射（UI camelCase → DB snake_case）；
/// 4. 读取列名 —— 第 6 步起在 `ChannelConfigCodec.appFromDb`（三向映射单点：
///    UI ↔ DB ↔ 原生），服务本身不再自己读列，所以本守卫扫的是**两个文件**。
///
/// 违反后果：列名不匹配时 SQLite 插入/查询会静默丢字段（如 secret 丢失导致
/// 推送鉴权失败），或 Dart 侧读出 null 落到默认值——都是"看起来成功了"的故障。
class _SchemaFixture {
  static const expectedColumns = {
    'id',
    'name',
    'app_type',
    'base_url',
    'secret',
    'config',
    'message_format',
    'enabled',
    // T11 主备角色。两处建表都有它，v11→v12 的老库靠 _addColumnIfMissing 补，
    // 所以"新建库"与"升级库"的最终列集合一致 —— 这正是本守卫要保的不变量。
    'role',
    'created_at',
    'updated_at',
  };
}

void main() {
  final root = projectRoot();
  final dbSource = stripComments(
    File('$root/lib/database/database_helper.dart').readAsStringSync(),
  );
  // 读取列名第 6 步起搬进 `ChannelConfigCodec.appFromDb`：两处都要扫，否则守卫会因为
  // 「读不到任何列」而静默失去保护（下面的 isNotEmpty 断言就是防这个的）。
  // ⚠ 只取 appFromDb 那一段 —— 整个 codec 里还有 webhook 的列名（url/channel_type/
  //   extra_config…），整份一起扫会把它们误判成「app_channels 读了不存在的列」。
  final serviceSource =
      stripComments(
        File('$root/lib/services/app_channel_service.dart').readAsStringSync(),
      ) +
      blockAfter(
        stripComments(
          File(
            '$root/lib/services/channel_config_codec.dart',
          ).readAsStringSync(),
        ),
        'static Map<String, dynamic> appFromDb',
      );

  final createBlocks = _createTableBlocks(dbSource);

  group('app_channels – 建表 SQL', () {
    test('建表出现两处（_onCreate + 迁移路径）', () {
      expect(
        createBlocks.length,
        2,
        reason:
            'app_channels 建表应同时存在于初始化与迁移路径；'
            '若升级路径被移除，老库升级后将缺表导致通道配置静默丢失',
      );
    });

    test('两处建表列集合完全一致（防升级漂移）', () {
      expect(createBlocks.first, equals(createBlocks.last));
    });

    test('列集合与契约一致（11 列）', () {
      expect(createBlocks.first, equals(_SchemaFixture.expectedColumns));
    });
  });

  group('app_channels – 读写列名契约', () {
    test('saveAppChannels 写入的列都在建表列内', () {
      final writeColumns = _writeColumns(dbSource);
      expect(writeColumns, isNotEmpty, reason: '未解析到写入列，断言失效');
      expect(writeColumns.difference(createBlocks.first), isEmpty);
    });

    test('自建应用通道的读取列（service + codec）都在建表列内', () {
      final readColumns = _serviceReadColumns(serviceSource);
      expect(readColumns, isNotEmpty, reason: '未解析到读取列，断言失效');
      // 'config' 等读取列必须真实存在；否则设置页字段恒为默认值
      expect(readColumns.difference(createBlocks.first), isEmpty);
    });

    test(
      '写入列覆盖全部业务列（id/name/app_type/base_url/secret/config/message_format/enabled）',
      () {
        final writeColumns = _writeColumns(dbSource);
        for (final col in const [
          'id',
          'name',
          'app_type',
          'base_url',
          'secret',
          'config',
          'message_format',
          'enabled',
        ]) {
          expect(
            writeColumns,
            contains(col),
            reason: 'saveAppChannels 未写入 $col —— 该字段会在保存后丢失',
          );
        }
      },
    );
  });

  group('app_channels – 存储接口', () {
    test('AppChannelStore 声明 getAppChannels / saveAppChannels', () {
      final storeBlock = _interfaceBlock(dbSource, 'AppChannelStore');
      expect(storeBlock, contains('getAppChannels()'));
      expect(storeBlock, contains('saveAppChannels('));
    });

    test('EmailChannelStore 声明 getEmailChannels / saveEmailChannels', () {
      final storeBlock = _interfaceBlock(dbSource, 'EmailChannelStore');
      expect(storeBlock, contains('getEmailChannels()'));
      expect(storeBlock, contains('saveEmailChannels('));
    });

    test('DatabaseHelper 实现三个存储接缝', () {
      // 用正则取 implements 子句而不是 contains('class X implements')：
      // 后者对 dart format 的换行敏感，一行变两行就静默失效（实测踩过）。
      final clause = RegExp(
        r'class DatabaseHelper\s+implements\s+([^{]+)\{',
      ).firstMatch(dbSource);
      expect(clause, isNotNull, reason: '没找到 DatabaseHelper 的 implements 子句');
      for (final store in [
        'WebhookChannelStore',
        'AppChannelStore',
        'EmailChannelStore',
      ]) {
        expect(
          clause!.group(1),
          contains(store),
          reason: '$store 失去实现 = 备份恢复的那一类在测试里再也注入不了伪存储',
        );
      }
    });
  });
}

/// 提取 app_channels 的建表列集合（每处一个 Set）。
List<Set<String>> _createTableBlocks(String source) {
  final re = RegExp(
    r'CREATE TABLE IF NOT EXISTS app_channels \(([\s\S]*?)\n\s*\)',
  );
  return re.allMatches(source).map((m) {
    final body = m.group(1)!;
    final cols = <String>{};
    for (final rawLine in body.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final first = line.split(RegExp(r'\s+')).first;
      // 只收列定义行（首 token 为小写列名，排除约束行）
      if (RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(first)) cols.add(first);
    }
    return cols;
  }).toList();
}

/// 提取 saveAppChannels 写入的列名（定位 `final row = <String, dynamic>{ ... }` 块，
/// 避免被函数内嵌套闭包 `});` 提前截断）。
Set<String> _writeColumns(String source) {
  final start = source.indexOf("final row = <String, dynamic>{");
  if (start < 0) return {};
  final end = source.indexOf('};', start);
  final body = source.substring(start, end < 0 ? source.length : end);
  return RegExp(
    r"'([a-z][a-z0-9_]*)':",
  ).allMatches(body).map((m) => m.group(1)!).toSet();
}

/// 提取 AppChannelService 读取的 DB 列名（`row['col']` 形式）。
Set<String> _serviceReadColumns(String source) {
  return RegExp(
    r"row\['([a-z][a-z0-9_]*)'\]",
  ).allMatches(source).map((m) => m.group(1)!).toSet();
}

/// 提取接口声明块（`abstract class X { ... }`）。
String _interfaceBlock(String source, String name) {
  final idx = source.indexOf('abstract class $name');
  if (idx < 0) return '';
  final end = source.indexOf('\n}', idx);
  return source.substring(idx, end < 0 ? source.length : end);
}
