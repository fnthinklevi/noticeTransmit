import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 通道身份契约守卫（v1.62 第 1–2 步）。
///
/// 这里锁的都是**静默型**缺陷：出错时不抛异常、不报错，只是某些通道的送达状态
/// 永远对不上、或某些平台的业务码判定形同虚设。
///
/// 1. **送达键生产者唯一**：键是 `chan:<slug>`，只在 `channel_display.dart` 拼装。
///    别处再手打一份字面量（历史上首页写过 `'自建应用:企微'`），两套字符串永不相等
///    ⇒ 首页通道状态与历史记录送达状态长期错配。
/// 2. **显示名不得再充当存储键**：写入侧（`notification_service` / `database_helper` /
///    `notification_record`）不得出现 `channelTypeDisplayName(`。键=显示名的后果是
///    切一次语言或改一次文案就分裂出两套键（历史重复徽标 / 旧键永远「发送中」）。
/// 3. **早期按枚举序号存的数字，两端必须同表**：Kotlin `parseWebhookType` 与 Dart
///    `_slugAliases` 各存一份数字表，任一侧改动而另一侧没跟上，旧记录就被读成通用通道。
/// 4. **判定身份必须由调用方贯穿到发送层**。`NetworkClient` 曾无条件按 host 重猜类型，
///    把显式传入的 `webhookType` 丢掉；自建 Gotify / 私有 ntfy 在注册表里 host 集合本就为空，
///    于是被降级成 GENERIC 判定，平台业务码规则失效。
/// 5. **token 失效识别必须同时认企微 `errcode` 与飞书 `code`**，只认一种会让飞书 token
///    过期后永不刷新、此后每次推送都带旧 token 失败。
void main() {
  final root = projectRoot();
  final libDir = Directory('$root/lib');

  group('送达键生产者唯一', () {
    test('chan: 字面量只允许出现在 channel_display.dart', () {
      expect(libDir.existsSync(), isTrue, reason: '未找到 lib 目录，断言会假绿');
      final offenders = <String>[];
      for (final f in libDir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final rel = f.path.replaceAll(r'\', '/');
        if (rel.endsWith('lib/services/channel_display.dart')) continue;
        if (stripComments(f.readAsStringSync()).contains("'chan:")) {
          offenders.add(rel);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            '送达键字面量散落 = 键的生产者不止一处，写入侧与读取侧会分叉。'
            '请调用 channelDeliveryKey()。',
      );
    });

    test('写入侧不得用显示名当键', () {
      const writePathFiles = [
        'lib/services/notification_service.dart',
        'lib/database/database_helper.dart',
        'lib/models/notification_record.dart',
      ];
      for (final rel in writePathFiles) {
        final src = stripComments(File('$root/$rel').readAsStringSync());
        expect(
          src,
          isNot(contains('channelTypeDisplayName(')),
          reason:
              '$rel 用显示名当存储键：用户切语言或改一次文案，同一通道就分裂成两套键，'
              '旧键永远停留「发送中」。存储键请走 channelDeliveryKey()。',
        );
      }
    });

    test('送达状态与送达日志写的是同一个键', () {
      final src = stripComments(
        File('$root/lib/services/notification_service.dart').readAsStringSync(),
      );
      // 不用 blockAfter：updateDelivery 的**命名参数**本身就带一对花括号，
      // 按花括号配对取块会只取到签名，守卫变成"签名字符串里有没有 X"。
      final start = src.indexOf('Future<void> updateDelivery(');
      final end = src.indexOf('Future<void> pushRecordNow', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start), reason: '未定位到 updateDelivery 的函数边界');
      final fn = src.substring(start, end);
      expect(fn, contains('channelDeliveryKey(kotlinType)'));
      expect(fn, contains('tag: deliveryKey'));
      // applyDelivery 的键必须由 kotlinType 推导，不接受调用方传入的 label
      expect(
        blockAfter(src, 'static Map<String, dynamic> applyDelivery({'),
        isNot(contains('String label')),
      );
    });

    test('首页通道列表的标签走显示名函数，不手打文案', () {
      final src = stripComments(
        File('$root/lib/pages/main_page.dart').readAsStringSync(),
      );
      final body = blockAfter(
        src,
        'List<Map<String, String>> _getActiveChannels()',
      );
      expect(
        body,
        contains('channelTypeDisplayName('),
        reason: '首页标签若另写字面量，就和通道体系脱钩',
      );
      expect(body, isNot(contains('自建应用:')));
      expect(body, isNot(contains('webhook:')));
    });
  });

  group('通道序号表跨端一致', () {
    test('Dart _slugAliases 的数字条目与 Kotlin parseWebhookType 一一对应', () {
      final kotlin = stripComments(
        File(
          '$root/android/app/src/main/kotlin/com/fnthink/notice/ConfigManager.kt',
        ).readAsStringSync(),
      );
      final arms = blockAfter(kotlin, 'private fun parseWebhookType(');
      final kotlinDigits = <String, String>{};
      final kotlinNames = <String>{};
      for (final line in arms.split('\n')) {
        final arrow = line.indexOf('->');
        if (arrow < 0) continue;
        final target = RegExp(
          r'WebhookType\.([A-Z_]+)',
        ).firstMatch(line.substring(arrow));
        if (target == null) continue; // else 分支走 detectType
        final slug = target.group(1)!.toLowerCase();
        kotlinNames.add(slug);
        for (final m in RegExp(
          r'"(\d+)"',
        ).allMatches(line.substring(0, arrow))) {
          kotlinDigits[m.group(1)!] = slug;
        }
      }
      expect(
        kotlinDigits.length,
        greaterThanOrEqualTo(12),
        reason: '未从 Kotlin 解析到序号表，守卫会假绿',
      );

      final dartSrc = stripComments(
        File('$root/lib/services/channel_display.dart').readAsStringSync(),
      );
      final aliasBlock = blockAfter(
        dartSrc,
        'const Map<String, String> _slugAliases = {',
      );
      final dartDigits = <String, String>{};
      for (final m in RegExp(
        r"'(\d+)':\s*'([a-z_]+)'",
      ).allMatches(aliasBlock)) {
        dartDigits[m.group(1)!] = m.group(2)!;
      }

      expect(
        dartDigits,
        kotlinDigits,
        reason:
            '数字序号两端不一致：一侧新增/改动而另一侧'
            '没跟上，早期按序号存储的记录会被读成另一个通道（表现为通用 Webhook）',
      );
      // 每个平台名都要在 Dart 侧有 snake_case 别名，否则新平台读旧值即失配
      for (final slug in kotlinNames) {
        expect(
          RegExp("'$slug': '$slug',").hasMatch(aliasBlock),
          isTrue,
          reason: 'channel_display.dart 缺少 $slug 的别名条目',
        );
      }
    });
  });

  group('发送层与 token 失效识别', () {
    test('发送层不得再按 host 重猜平台身份', () {
      final src = stripComments(
        File(
          '$root/android/app/src/main/kotlin/com/fnthink/notice/NetworkClient.kt',
        ).readAsStringSync(),
      );
      expect(
        src,
        contains('resolveWebhookType('),
        reason: '显式类型应优先，仅 GENERIC 才允许按 host 回退',
      );
      expect(
        src,
        isNot(contains('detectType(signed.url)')),
        reason:
            '无条件 detectType 会丢弃调用方传入的 webhookType：自建 Gotify / 私有 ntfy '
            '的 hosts 集合本就为空，会被误判成 GENERIC 而使平台业务码规则失效',
      );
    });

    test('token 失效识别须同时覆盖 errcode 与 code', () {
      final src = stripComments(
        File(
          '$root/android/app/src/main/kotlin/com/fnthink/notice/AppChannelTokenManager.kt',
        ).readAsStringSync(),
      );
      expect(
        src,
        contains(r'(?:errcode|code)'),
        reason: '只匹配 errcode= 时，飞书的 code=99991661 永不被识别为 token 失效',
      );
    });
  });
}
