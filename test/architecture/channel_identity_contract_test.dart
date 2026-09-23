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
    test('Dart _slugAliases 与 Kotlin 描述符的 legacyTokens / 枚举名一一对应', () {
      // 第 4 步起 Kotlin 侧的真值不再是 `ConfigManager` 的 12 臂 when，
      // 而是 ChannelRegistry 每个条目的 type + legacyTokens（本守卫同时确保
      // ConfigManager 没有把那张表偷偷长回来）。
      final registry = stripComments(
        File(
          '$root/android/app/src/main/kotlin/com/fnthink/notice/ChannelRegistry.kt',
        ).readAsStringSync(),
      );
      final configManager = stripComments(
        File(
          '$root/android/app/src/main/kotlin/com/fnthink/notice/ConfigManager.kt',
        ).readAsStringSync(),
      );
      expect(
        RegExp(
          r'"(wechat_work|dingtalk|feishu|generic)",\s*"\d+"',
        ).hasMatch(configManager),
        isFalse,
        reason:
            'ConfigManager 又自己存了一份 channel_type 映射表 ⇒ 与描述符表两处真相，'
            '加通道时漏改一侧会把已有通道静默读成 GENERIC',
      );
      expect(
        configManager,
        contains('ChannelRegistry.typeByStoredToken'),
        reason: '存储值解析必须走描述符表',
      );

      final kotlinDigits = <String, String>{};
      final kotlinNames = <String>{};
      for (final chunk in registry.split('ChannelSpec(').skip(1)) {
        final typeMatch = RegExp(
          r'type = WebhookPayloadBuilder\.WebhookType\.([A-Z_]+)',
        ).firstMatch(chunk);
        if (typeMatch == null) continue;
        final slug = typeMatch.group(1)!.toLowerCase();
        kotlinNames.add(slug);
        final tokens = RegExp(
          r'legacyTokens = listOf\(([^)]*)\)',
        ).firstMatch(chunk);
        for (final m in RegExp(r'"(\d+)"').allMatches(tokens?.group(1) ?? '')) {
          kotlinDigits[m.group(1)!] = slug;
        }
      }
      expect(
        kotlinDigits.length,
        12,
        reason: '未从描述符表解析到 12 个数字序号（0..11），守卫会假绿',
      );
      expect(kotlinNames.length, 12, reason: '描述符表条目数与 WebhookType 枚举不符（12 个）');

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

  group('第 3 步局部缺陷不得复活', () {
    test('webhook 设置页不再留 extra_config 死路径', () {
      final page = stripComments(
        File('$root/lib/pages/webhook_settings_page.dart').readAsStringSync(),
      );
      final item = stripComments(
        File('$root/lib/pages/webhook_settings_item.dart').readAsStringSync(),
      );
      // 页面上没有任何 corpid/agentid/touser 输入框（自建应用凭据在 app_channels 体系里编辑），
      // 却声明过三个从不渲染、也从不 dispose 的控制器 + 一个恒为 null 的 extraConfig 假传参。
      for (final dead in ['extraConfig', 'corpid', 'agentid', 'touser']) {
        expect(page, isNot(contains(dead)), reason: 'webhook 页面残留 $dead');
        expect(item, isNot(contains(dead)), reason: 'webhook 卡片残留 $dead');
      }
      // 服务层/DB 层的 extra_config 是活的（备份恢复、原生 testWebhook 会用），不许一起删
      final svc = File(
        '$root/lib/services/webhook_service.dart',
      ).readAsStringSync();
      expect(svc, contains('extra_config'));
    });

    test('健康徽标按并行 id 列表取，不按下标读构造期输入', () {
      final item = stripComments(
        File('$root/lib/pages/webhook_settings_item.dart').readAsStringSync(),
      );
      final badge = blockAfter(
        item,
        'Widget _buildHealthBadge(int index, BuildContext context) {',
      );
      expect(badge, contains('_channelIds[index]'));
      expect(
        badge,
        isNot(contains('widget.webhookChannels[')),
        reason: 'widget.webhookChannels 不随行增删收缩：新增行会 RangeError，删行会串台',
      );
    });

    test('签名能力与提示文案只有一处判定', () {
      final model = stripComments(
        File('$root/lib/models/webhook_channel.dart').readAsStringSync(),
      );
      for (final dup in ['supportsSigning', 'signingHint']) {
        expect(
          model,
          isNot(contains(dup)),
          reason:
              '模型里再存一份 $dup 就会出现第二处真相：此前那份 12 臂全 false，'
              '而 UI 实际只排除 6 个平台，且提示文案是硬编码中文（UI 走 l10n）',
        );
      }
      final page = File(
        '$root/lib/pages/webhook_settings_page.dart',
      ).readAsStringSync();
      expect(page, contains('bool _supportsSigning(int index)'));
    });

    test('应用通道类型标签必须有未知兜底，不许用否定分支当默认', () {
      final listPage = stripComments(
        File('$root/lib/pages/app_channel_list_page.dart').readAsStringSync(),
      );
      expect(
        listPage,
        isNot(contains("? l10n.channelTypeFeishuApp")),
        reason: '三元否定分支会把未知 app_type 标成企业微信应用',
      );
      expect(
        listPage,
        isNot(contains("appType != 'feishu_app'")),
        reason: '「不是 X 就是 Y」的否定分支 = 新增应用通道时静默冒充既有平台',
      );
      // 第 5 步起标签与图标都查视觉表：兜底必须是显式的「未知」，不是某个平台
      expect(listPage, contains('hasChannelVisual(appType)'));
      expect(
        listPage,
        contains('l10n.unknown'),
        reason: '未登记的 app_type 要显示「未知」，让用户看得见配错了',
      );
    });

    test('AppChannelSettingsPage 不再收留从未读取的 initialIndex', () {
      for (final rel in [
        'lib/pages/app_channel_settings_page.dart',
        'lib/pages/app_channel_list_page.dart',
      ]) {
        expect(
          stripComments(File('$root/$rel').readAsStringSync()),
          isNot(contains('initialIndex')),
          reason: '$rel 仍有 initialIndex：参数传而不用，从列表点第 2 条与点 FAB 无区别',
        );
      }
    });
  });
}
