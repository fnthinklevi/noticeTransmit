import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 通道身份契约守卫（v1.62 第 1 步）。
///
/// 这里锁的都是**静默型**缺陷：出错时不抛异常、不报错，只是某些通道的送达状态
/// 永远对不上、或某些平台的业务码判定形同虚设。
///
/// 1. **送达键的唯一生产者必须是 `channelTypeDisplayName()`**（`lib/services/channel_display.dart`）。
///    别处再手打一份字面量（历史上首页写过 `'自建应用:企微'`，而键是 `'应用:企业微信应用'`），
///    两套字符串永不相等 ⇒ 首页通道状态与历史记录送达状态长期错配。
/// 2. **判定身份必须由调用方贯穿到发送层**。`NetworkClient` 曾无条件按 host 重猜类型，
///    把显式传入的 `webhookType` 丢掉；自建 Gotify / 私有 ntfy 在注册表里 host 集合本就为空，
///    于是被降级成 GENERIC 判定，平台业务码规则失效。
/// 3. **token 失效识别必须同时认企微 `errcode` 与飞书 `code`**，只认一种会让飞书 token
///    过期后永不刷新、此后每次推送都带旧 token 失败。
void main() {
  final root = projectRoot();
  final libDir = Directory('$root/lib');

  group('通道身份与送达键', () {
    test('带前缀的送达键字面量只允许出现在 channel_display.dart', () {
      expect(libDir.existsSync(), isTrue, reason: '未找到 lib 目录，断言会假绿');
      const prefixes = ["'webhook:", "'应用:", "'自建应用:"];
      final offenders = <String>[];
      for (final f in libDir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final rel = f.path.replaceAll(r'\', '/');
        if (rel.endsWith('lib/services/channel_display.dart')) continue;
        final src = stripComments(f.readAsStringSync());
        for (final p in prefixes) {
          if (src.contains(p)) offenders.add('$rel 含 $p');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            '送达键字面量散落 = 首页标签与 deliveryStatus 键分叉（表现为历史重复徽标、'
            '或某些通道永远「发送中」）。请统一调用 channelTypeDisplayName()。',
      );
    });

    test('首页通道列表的标签必须与送达键同源', () {
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
        reason: '首页标签若另写字面量，就和原生回传生成的送达键不是同一串',
      );
      expect(body, isNot(contains('自建应用:')));
      expect(body, isNot(contains('webhook:')));
    });

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
