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
    // 锚点一律写成 `fun 名字(`：带 `fun ` 就不会命中调用点，而不抄参数表/返回类型 ——
    // 那些细节一改，blockAfter 抛的 StateError 会让整条守卫变红却跟"口径"无关（base.md（75））。
    test('原生两处仍是 http+https，Dart 规则字面一致', () {
      final base = blockAfter(
        read(
          'android/app/src/main/kotlin/com/fnthink/notice/AppChannelTokenManager.kt',
        ),
        'fun normalizeBase(',
      );
      final probe = blockAfter(
        read(
          'android/app/src/main/kotlin/com/fnthink/notice/ChannelHealthProbe.kt',
        ),
        'fun isProbeableUrl(',
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
      final dir = Directory('$root/lib/pages');
      expect(
        dir.existsSync(),
        isTrue,
        reason: 'lib/pages 不在了：目录型守卫会"扫不到文件 ⇒ 没有违规"，绿得毫无意义',
      );
      var scanned = 0;
      for (final file in dir.listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        scanned++;
        final src = stripComments(file.readAsStringSync());
        // 认「字符串字面量」而不是裸前缀：`import '../services/channel_health_store.dart'`
        // 也含 channel_health_，那样每条 import 都会变成假阳性
        for (final marker in ["'channel_health_", "'email_test_results"]) {
          if (src.contains(marker)) {
            offenders.add('${file.uri.pathSegments.last} 含 $marker');
          }
        }
      }
      // 正面锚点：扫到的文件数要跟得上页面规模（口径变了 / 目录搬走时这条会红，
      // 而不是悄悄变成"零个文件、零条违规"）。
      expect(
        scanned,
        greaterThanOrEqualTo(25),
        reason: '只扫到 $scanned 个页面文件（当前约 30）⇒ 页面目录口径变了，本条已在空跑',
      );
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

  // T04：三族通道的"测一下"与"什么状态"必须各只有一个来源。
  // 抄本的代价本项目已经付过多次：徽标抄成两份 ⇒ 一份看时效、一份不看，
  // 设置页画绿勾、首页说未知；测试入口只长在 app 页 ⇒ 另两族只能靠保存触发。
  group('通道测试入口与健康徽标各只有一处（T04）', () {
    const pages = [
      'lib/pages/app_channel_settings_page.dart',
      'lib/pages/webhook_settings_page.dart',
      'lib/pages/email_settings_page.dart',
    ];

    test('三族设置页都得有「仅测试」入口', () {
      for (final rel in pages) {
        expect(
          read(rel),
          contains('l10n.testOnly'),
          reason: '$rel 没有「仅测试」⇒ 想验一次配置就只能把半成品保存进去',
        );
      }
      final arb = stripComments(
        File('$root/lib/l10n/arb/app_zh.arb').readAsStringSync(),
      );
      expect(arb, contains('"testOnly"'), reason: '三处共用同一个资源名，别再各自写一份字面量');
    });

    test('健康状态只有 ChannelHealthBadge / channelHealthState 这一条判定', () {
      final badge = read('lib/widgets/channel_health_badge.dart');
      expect(
        badge,
        contains('channelHealthState('),
        reason: '徽标自己判三态 = 又开一份真值',
      );
      // 注意 webhook：它的卡片构建在 part 文件 `webhook_settings_item.dart` 里，
      // 所以列的是"真正渲染健康的地方"，不是页面的库文件。
      for (final rel in [
        'lib/pages/app_channel_settings_page.dart',
        'lib/pages/email_settings_page.dart',
        'lib/pages/webhook_settings_item.dart',
      ]) {
        expect(
          read(rel),
          anyOf(
            contains('ChannelHealthBadge'),
            contains('channelHealthState('),
            contains('.healthState'),
          ),
          reason: '$rel 显示通道健康却没走单点',
        );
      }
      // 抄本的特征就是这个三元：只看 reachable、不看探测时效
      final offenders = <String>[
        for (final rel in [
          ...pages,
          'lib/pages/webhook_settings_item.dart',
          'lib/pages/channel_status_page.dart',
          'lib/pages/main_page.dart',
        ])
          if (read(rel).contains('reachable ?')) rel,
      ];
      expect(
        offenders,
        isEmpty,
        reason:
            '直接对 reachable 做三元判断会漏掉"成功但已过期"，'
            '首页说未知、设置页画绿勾：$offenders',
      );
    });
  });
}
