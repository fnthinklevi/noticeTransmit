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

    test('启用通道清单只有一个生产者，标签走显示名函数不手打文案', () {
      // 第 6 步：首页显示与历史记录的送达键快照共用 collectActiveChannels，
      // 所以「标签不手打文案」盯 active_channels.dart，同时盯首页别再自己
      // 遍历三个 service 长出第二份清单（两份实现对「什么算启用」口径漂移过一次）。
      final producer = stripComments(
        File('$root/lib/services/active_channels.dart').readAsStringSync(),
      );
      final home = stripComments(
        // 首页那一族有 3 个 part（R3 拆分），而下面这条是**负向**断言
        // （"首页不许自己算标签"）—— 只读 main_page.dart 的话，把标签代码写进
        // main_page_actions.dart 就看不见（T65 盘点时发现，见 base.md 116）。
        librarySource(root, 'lib/pages/main_page.dart'),
      );
      final snapshot = stripComments(
        File('$root/lib/services/notification_service.dart').readAsStringSync(),
      );

      expect(producer, contains('channelTypeDisplayName('));
      expect(producer, isNot(contains('自建应用:')));
      expect(producer, isNot(contains("chan:")));
      expect(
        producer,
        contains('channelDeliveryKey('),
        reason: '送达键必须仍由 channel_display 这一个生产者算',
      );

      expect(home, contains('collectActiveChannels()'));
      expect(
        home,
        isNot(contains('channelTypeDisplayName(')),
        reason: '首页又自己算标签了：清单应整体来自 active_channels',
      );
      expect(snapshot, contains('deliveryKeysOfActiveChannels()'));
      expect(
        snapshot,
        isNot(contains('WebhookService>().channels')),
        reason: '快照侧又自己遍历通道列表 = 回到两份实现',
      );
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
    test('extra_config 死链路已断开（D4=B / ㊷），且不得只删一半', () {
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
      // ⚠ 本用例原来的收尾断言是 `expect(svc, contains('extra_config'))`，理由是
      // "备份恢复、原生 testWebhook 会用" —— 那句话**经查是错的**（testWebhook 的形参恒为 null，
      // 发送层零引用）。㊷ 按 D4=B 把链路删干净，因此这里反过来钉"不许再出现"，
      // 只留 database_helper 的建表/迁移白名单（列保留，删列要迁用户数据）。
      final svc = stripComments(
        File('$root/lib/services/webhook_service.dart').readAsStringSync(),
      );
      expect(svc, isNot(contains('extra_config')));
      for (final f in [
        'lib/services/channel_config_codec.dart',
        'lib/pages/webhook_settings_page.dart',
      ]) {
        final src = stripComments(File('$root/$f').readAsStringSync());
        expect(
          src,
          isNot(contains("row['extra_config']")),
          reason: '$f 又去读写 extra_config 了 —— 该键已退出契约（D4）',
        );
      }
      // 反向自检：白名单那两处（建表 + 搬家 SELECT）必须还在，否则说明列被顺手删了
      // （同样要剥注释：一句"extra_config TEXT 列保留"的注释不算它还活着）
      final db = stripComments(
        File('$root/lib/database/database_helper.dart').readAsStringSync(),
      );
      expect(
        db,
        allOf(
          contains('extra_config TEXT'),
          contains("COALESCE(extra_config, '{}')"),
        ),
        reason: 'DB 列与 v9→v10 搬家 SELECT 必须保留（本步只删读写链路）',
      );
    });

    test('健康徽标只按本条通道的 id 取，构造期快照整条链路已退场（T07-B）', () {
      // 平铺页时代这份守卫钉的是"徽标要按并行 id 列表取，不能按 index 读
      // widget.webhookChannels"。T07-B 之后更好的答案是：**根本没有那份快照** ——
      // 构造函数只收一个 channelId，页面从服务里按 id 取那一条。
      // 所以这里钉两件：按 id 取；以及不许再出现按构造期输入下标寻址的写法。
      for (final rel in const [
        'lib/pages/webhook_settings_page.dart',
        'lib/pages/webhook_channel_list_page.dart',
      ]) {
        final src = stripComments(File('$root/$rel').readAsStringSync());
        expect(
          src,
          contains("_health.of('webhook', id)"),
          reason: '$rel 的徽标不再按 id 取 ⇒ 会退回"删一行其余行继承上一条状态"那一类缺陷',
        );
        expect(
          src,
          isNot(contains('webhookChannels')),
          reason: '$rel 又拿整表快照了：它不随行增删收缩，新增行 RangeError、删行串台（探测结论同理）',
        );
      }
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
      final page = stripComments(
        File('$root/lib/pages/webhook_settings_page.dart').readAsStringSync(),
      );
      expect(page, contains('bool get _supportsSigning'));
      // 列表页只显示状态，不该另算一次"这条要不要密钥"
      final list = stripComments(
        File(
          '$root/lib/pages/webhook_channel_list_page.dart',
        ).readAsStringSync(),
      );
      expect(
        list,
        isNot(contains('_supportsSigning')),
        reason: '判据长第二份，两页就会开始分叉',
      );
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

  // ── T150 片1（维护者 2026-10-12 第 6 条：暂停时那一格一直「发送中」）─────────
  // 「不参与推送」这一档（`role=none`）**两侧各判一次**：原生在路由第一步筛掉它，
  // Dart 在入库快照那一步不替它写初值。任一侧单独改，表现都是静默的：
  // 只改 Dart ⇒ 原生照筛、快照少一档，看不出问题；
  // 只改原生（比如不再筛）⇒ Dart 那份排除让这些通道的送达结果**无处可写**，历史永远没有这一格。
  group('role=none 这一档：送达快照侧与路由侧同一个口径（T150）', () {
    test('原生仍在第一步筛掉 NONE', () {
      final routing = stripComments(
        File(
          '$root/android/app/src/main/kotlin/com/fnthink/notice/ChannelRouting.kt',
        ).readAsStringSync(),
      );
      expect(
        routing,
        contains('it.role != ChannelRole.NONE'),
        reason:
            '原生不再筛 NONE ⇒ Dart 那侧的排除必须一起改，否则两处各判一遍；'
            '而这一枚锚点带 `it.` 就与参数名/类型改动无关',
      );
    });

    test('Dart 只为还会被人来回执的键写初值，且只排 none', () {
      final src = stripComments(
        File('$root/lib/services/active_channels.dart').readAsStringSync(),
      );
      final start = src.indexOf('List<String> deliveryKeysOfActiveChannels()');
      expect(start, greaterThanOrEqualTo(0), reason: '那份键列表的作者换了地方');
      final end = src.indexOf(';', start);
      expect(end, greaterThan(start), reason: '提取尺量不到结尾 ⇒ 尺比被量的东西窄');
      final body = src.substring(start, end);
      expect(
        body,
        contains('c.role != ChannelConfigCodec.roleNone'),
        reason: '为 role=none 的通道写 `pending` 初值 = 在历史里给一个不会来的人留一把永远亮着的「发送中」',
      );
      expect(
        body,
        isNot(contains('roleUnset')),
        reason:
            '不许把 unset 一起筛掉：原生 `ChannelRole.fromWire` 认不出就归 PRIMARY（宁可多推不可漏推），'
            '那条通道照有回执；筛掉它的表现是"新建通道没点主备 ⇒ 历史里连占位都没有"',
      );
      expect(
        body,
        isNot(contains('roleBackup')),
        reason: '现编"非主即藏"的口径会把 none 与 unset 混起来（T151 同一颗病灶）',
      );
    });

    test('页面不再自己有一张送达状态词表（「发送中」不是兜底读数）', () {
      final page = stripComments(
        File('$root/lib/pages/history_page.dart').readAsStringSync(),
      );
      expect(
        page.contains('l10n.deliveryPending'),
        isFalse,
        reason: '「发送中」只能由 `deliveryStatusText` 在 pending 那一档给；页面里再留一份就会兜底',
      );
      expect(
        page,
        contains('deliveryStatusText(l10n, status)'),
        reason: '这一格必须走唯一作者（services/delivery_display.dart）',
      );
      final display = stripComments(
        File('$root/lib/services/delivery_display.dart').readAsStringSync(),
      );
      // `default:` 那一支只许说"未知"——这是这一片的全部牙
      final armAt = display.indexOf('default:');
      expect(armAt, greaterThanOrEqualTo(0), reason: '那张表没有 default 一支了');
      final defaultArm = display.substring(armAt);
      expect(
        defaultArm,
        contains('l10n.deliveryUnknown'),
        reason:
            '`default:` 回到 deliveryPending，就等于"任何一个对不上号的串都在途"：'
            '维护者这次看到的正是这句假话',
      );
      expect(
        display,
        contains("case 'pending':"),
        reason: '「发送中」必须仍挂在 pending 一个词上（不许把在途那一档一起删了）',
      );
    });
  });
}
