import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 「一件事只有一处实现」的第 6 步守卫。
///
/// 本仓库反复出现同一类故障：同一个事实被抄成几份，抄漏的那份不会报错，
/// 只是某些通道永远行为不同。第 6 步收口的三件事各留一条守卫：
/// 1. 通道 URL 合法性规则（原生两处 + Dart 一处必须同一口径）；
/// 2. 健康度缓存的读写（只有 `ChannelHealthStore` 碰 prefs）；
/// 3. `'null'` 脏数据清洗（只有 `ChannelConfigCodec` 做）。
void main() {
  final root = projectRoot();

  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  group('URL 规则跨端同一口径', () {
    test('原生两处仍是 http+https，Dart 规则字面一致', () {
      final base = blockAfter(
        read(
          'android/app/src/main/kotlin/com/fnthink/notice/AppChannelTokenManager.kt',
        ),
        'fun normalizeBase(raw: String, fallback: String): String',
      );
      final probe = blockAfter(
        read(
          'android/app/src/main/kotlin/com/fnthink/notice/ChannelHealthProbe.kt',
        ),
        'fun isProbeableUrl(url: String): Boolean',
      );
      for (final (where, block) in [
        ('normalizeBase', base),
        ('isProbeableUrl', probe),
      ]) {
        expect(
          block,
          allOf(
            contains('startsWith("https://")'),
            contains('startsWith("http://")'),
          ),
          reason:
              '原生 $where 的 scheme 口径变了：Dart 侧 `ChannelUrlPolicy` 必须同步，'
              '否则备份/保存与推送判定用的是两套规则',
        );
      }

      final policy = read('lib/services/channel_url_policy.dart');
      expect(
        policy,
        allOf(contains("'https://'"), contains("'http://'")),
        reason: 'Dart 侧规则必须同时接受 http 与 https（自建 ntfy/Gotify 常在局域网 http）',
      );
    });

    test('备份与设置页复用规则，不再自己判 scheme', () {
      for (final rel in [
        'lib/services/backup_service.dart',
        'lib/pages/webhook_settings_page.dart',
      ]) {
        final src = read(rel);
        expect(
          src,
          contains('ChannelUrlPolicy.isHttpUrl'),
          reason: '$rel 又绕开单点自己判 URL 了',
        );
        expect(
          src,
          isNot(contains("scheme == 'https'")),
          reason: '$rel 里残留「只认 https」的旧规则 —— 它会在恢复备份时静默丢掉自建 http 通道',
        );
      }
    });
  });

  group('健康度只有一个生产者', () {
    test('页面不再直接读写 channel_health_ / email_test_results', () {
      final offenders = <String>[];
      for (final file in Directory(
        '$root/lib/pages',
      ).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final src = stripComments(file.readAsStringSync());
        // 认「字符串字面量」而不是裸前缀：`import '../services/channel_health_store.dart'`
        // 也含 channel_health_，那样每条 import 都会变成假阳性
        for (final marker in ["'channel_health_", "'email_test_results"]) {
          if (src.contains(marker)) {
            offenders.add('${file.uri.pathSegments.last} 含 $marker');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            '健康度缓存的键格式与 6h 时效只在 ChannelHealthStore 一处定义；'
            '页面自己拼键就会再次分裂成三族不同行为：$offenders',
      );
    });

    test('只有 store 碰健康键，email 服务也不再自存一份', () {
      final store = read('lib/services/channel_health_store.dart');
      expect(store, contains('channel_health_'));
      expect(store, contains('email_test_results'));

      final email = read('lib/services/email_service.dart');
      expect(email, isNot(contains('email_test_results')));
      expect(email, contains('ChannelHealthStore'), reason: '邮件测试结果必须落健康单点');
    });
  });

  group("'null\" 脏数据清洗只有一处", () {
    test('除 codec 外，服务层不再自己比较 == "null"', () {
      final offenders = <String>[];
      for (final rel in [
        'lib/services/webhook_service.dart',
        'lib/services/app_channel_service.dart',
        'lib/services/email_service.dart',
        'lib/database/database_helper.dart',
      ]) {
        final src = read(rel);
        if (src.contains("== 'null'") || src.contains('== "null"')) {
          offenders.add(rel);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            '清洗逻辑散回各处 = 迟早有一处漏洗（漏洗的字段看起来有值、原生读到 "null"）；'
            '统一走 ChannelConfigCodec.nullableText：$offenders',
      );
      expect(
        read('lib/services/channel_config_codec.dart'),
        contains("'null'"),
        reason: '清洗必须确实存在于单点里',
      );
    });
  });
}
